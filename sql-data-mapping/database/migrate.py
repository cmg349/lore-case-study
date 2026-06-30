#!/usr/bin/env python3
"""
deploy.py — Apply or roll back eligibility schema migrations.

Tracks applied migrations in public.schema_migrations so each file is only
ever applied once. Uses psql to execute migration files so that complex SQL
(dollar-quoted functions, DO blocks, multi-statement transactions) works
without any parsing on this side.

Usage
-----
  # Apply all pending migrations
  python deploy.py

  # Show current migration status
  python deploy.py --status

  # Dry run — print what would run without executing anything
  python deploy.py --dry-run

  # Roll back the last N applied migrations (default 1)
  python deploy.py --rollback [N]

  # Migrate to a specific migration number (up or down as needed)
  python deploy.py --target 008

Connection
----------
Set standard PostgreSQL environment variables before running:

  PGHOST      (default: localhost)
  PGPORT      (default: 5432)
  PGDATABASE  (default: postgres)
  PGUSER      (default: postgres)
  PGPASSWORD  (no default — omit for peer/trust auth)

Or use a connection URL:

  DATABASE_URL=postgresql://user:pass@localhost:5432/mydb python deploy.py
"""

from __future__ import annotations

import argparse
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path
from urllib.parse import urlparse

import psycopg2

# ---------------------------------------------------------------------------
# Paths
# ---------------------------------------------------------------------------

SCRIPT_DIR     = Path(__file__).resolve().parent
MIGRATIONS_DIR = SCRIPT_DIR / "migrations"
TRACKING_TABLE = "public.schema_migrations"

# ---------------------------------------------------------------------------
# ANSI colour helpers
# ---------------------------------------------------------------------------

_USE_COLOUR = sys.stdout.isatty()

def _c(code: str, text: str) -> str:
    return f"\033[{code}m{text}\033[0m" if _USE_COLOUR else text

def green(t):  return _c("32", t)
def yellow(t): return _c("33", t)
def red(t):    return _c("31", t)
def bold(t):   return _c("1",  t)
def dim(t):    return _c("2",  t)

# ---------------------------------------------------------------------------
# Connection helpers
# ---------------------------------------------------------------------------

def _parse_database_url(url: str) -> dict:
    p = urlparse(url)
    return {
        "host":     p.hostname or "localhost",
        "port":     p.port     or 5432,
        "dbname":   (p.path or "/postgres").lstrip("/") or "postgres",
        "user":     p.username or "postgres",
        "password": p.password or "",
    }


def get_conn_params() -> dict:
    db_url = os.environ.get("DATABASE_URL")
    if db_url:
        return _parse_database_url(db_url)
    return {
        "host":     os.environ.get("PGHOST",     "localhost"),
        "port":     int(os.environ.get("PGPORT", 5432)),
        "dbname":   os.environ.get("PGDATABASE", "postgres"),
        "user":     os.environ.get("PGUSER",     "postgres"),
        "password": os.environ.get("PGPASSWORD", ""),
    }


def get_psql_env() -> dict:
    """Build an env dict that psql will read for connection details."""
    params = get_conn_params()
    env = os.environ.copy()
    env["PGHOST"]     = str(params["host"])
    env["PGPORT"]     = str(params["port"])
    env["PGDATABASE"] = str(params["dbname"])
    env["PGUSER"]     = str(params["user"])
    if params["password"]:
        env["PGPASSWORD"] = str(params["password"])
    return env


def open_conn():
    params = get_conn_params()
    try:
        conn = psycopg2.connect(**{k: v for k, v in params.items() if v != ""})
        conn.autocommit = False
        return conn
    except psycopg2.OperationalError as exc:
        print(red(f"Cannot connect to database: {exc}"), file=sys.stderr)
        print(
            dim("  Hint: set PGHOST, PGPORT, PGDATABASE, PGUSER, PGPASSWORD "
                "(or DATABASE_URL) before running."),
            file=sys.stderr,
        )
        sys.exit(1)

# ---------------------------------------------------------------------------
# psql binary discovery
# ---------------------------------------------------------------------------

_PSQL_SEARCH_PATHS = [
    r"C:\Program Files\PostgreSQL\17\bin\psql.exe",
    r"C:\Program Files\PostgreSQL\16\bin\psql.exe",
    r"C:\Program Files\PostgreSQL\15\bin\psql.exe",
    r"C:\Program Files\PostgreSQL\14\bin\psql.exe",
]


def find_psql() -> str:
    psql = shutil.which("psql")
    if psql:
        return psql
    for path in _PSQL_SEARCH_PATHS:
        if Path(path).exists():
            return path
    print(
        red("psql not found. Add the PostgreSQL bin directory to your PATH."),
        file=sys.stderr,
    )
    sys.exit(1)

# ---------------------------------------------------------------------------
# Tracking table
# ---------------------------------------------------------------------------

def ensure_tracking_table(conn) -> None:
    with conn.cursor() as cur:
        cur.execute(f"""
            CREATE TABLE IF NOT EXISTS {TRACKING_TABLE} (
                migration_id TEXT        PRIMARY KEY,
                file_name    TEXT        NOT NULL,
                applied_at   TIMESTAMPTZ NOT NULL DEFAULT now()
            )
        """)
    conn.commit()


def get_applied_migrations(conn) -> set:
    with conn.cursor() as cur:
        cur.execute(f"SELECT migration_id FROM {TRACKING_TABLE} ORDER BY migration_id")
        return {row[0] for row in cur.fetchall()}


def get_applied_ordered(conn) -> list:
    with conn.cursor() as cur:
        cur.execute(
            f"SELECT migration_id, file_name, applied_at "
            f"FROM {TRACKING_TABLE} ORDER BY migration_id"
        )
        return cur.fetchall()


def record_applied(conn, migration_id: str, file_name: str) -> None:
    with conn.cursor() as cur:
        cur.execute(
            f"INSERT INTO {TRACKING_TABLE} (migration_id, file_name) VALUES (%s, %s)"
            f" ON CONFLICT (migration_id) DO NOTHING",
            (migration_id, file_name),
        )
    conn.commit()


def remove_applied(conn, migration_id: str) -> None:
    with conn.cursor() as cur:
        cur.execute(
            f"DELETE FROM {TRACKING_TABLE} WHERE migration_id = %s",
            (migration_id,),
        )
    conn.commit()

# ---------------------------------------------------------------------------
# Migration file discovery
# ---------------------------------------------------------------------------

_ID_RE = re.compile(r"^(\d{3})_")


def _migration_id(path: Path) -> str | None:
    m = _ID_RE.match(path.name)
    return m.group(1) if m else None


def get_all_up_migrations() -> list[tuple[str, Path]]:
    """Return [(migration_id, path), ...] for all .up.sql files, sorted."""
    result = []
    for f in sorted(MIGRATIONS_DIR.glob("*.up.sql")):
        mid = _migration_id(f)
        if mid:
            result.append((mid, f))
    return result


def down_file_for(up_path: Path) -> Path:
    return up_path.parent / up_path.name.replace(".up.sql", ".down.sql")

# ---------------------------------------------------------------------------
# Migration execution via psql
# ---------------------------------------------------------------------------

def run_sql_file(psql_bin: str, sql_path: Path, dry_run: bool = False) -> bool:
    """Execute a SQL file via psql. Returns True on success."""
    if dry_run:
        return True

    result = subprocess.run(
        [psql_bin, "--no-psqlrc", "-v", "ON_ERROR_STOP=1", "-f", str(sql_path)],
        env=get_psql_env(),
        capture_output=True,
        text=True,
    )

    if result.stdout.strip():
        for line in result.stdout.strip().splitlines():
            print(f"    {dim(line)}")

    if result.returncode != 0:
        for line in result.stderr.strip().splitlines():
            print(f"    {red(line)}", file=sys.stderr)
        return False

    return True

# ---------------------------------------------------------------------------
# Commands
# ---------------------------------------------------------------------------

def cmd_status(conn) -> None:
    all_migrations  = get_all_up_migrations()
    applied_ids     = get_applied_migrations(conn)
    applied_ordered = {row[0]: row for row in get_applied_ordered(conn)}

    print(bold("\nMigration status"))
    print(dim(f"  Tracking table : {TRACKING_TABLE}"))
    print(dim(f"  Migrations dir : {MIGRATIONS_DIR}\n"))

    if not all_migrations:
        print(yellow("  No migration files found."))
        return

    for mid, path in all_migrations:
        if mid in applied_ids:
            _, _, applied_at = applied_ordered[mid]
            tag = green("✓ applied")
            ts  = dim(f"  ({applied_at.strftime('%Y-%m-%d %H:%M:%S %Z')})")
        else:
            tag = yellow("  pending")
            ts  = ""
        print(f"  {tag}  {path.name}{ts}")

    pending = [(m, p) for m, p in all_migrations if m not in applied_ids]
    print(f"\n  {len(applied_ids)} applied, {len(pending)} pending\n")


def cmd_up(conn, psql_bin: str, target: str | None, dry_run: bool) -> None:
    all_migrations = get_all_up_migrations()
    applied_ids    = get_applied_migrations(conn)

    pending = [
        (mid, path)
        for mid, path in all_migrations
        if mid not in applied_ids and (target is None or mid <= target)
    ]

    if not pending:
        print(green("Nothing to apply — database is up to date."))
        return

    label = "Would apply" if dry_run else "Applying"
    print(bold(f"\n{label} {len(pending)} migration(s):\n"))

    for mid, path in pending:
        print(f"  → {bold(path.name)}")
        ok = run_sql_file(psql_bin, path, dry_run)
        if not ok:
            print(red(f"\n  Migration {path.name} FAILED — stopping."))
            sys.exit(1)
        if not dry_run:
            record_applied(conn, mid, path.name)
            print(f"    {green('✓ done')}")

    if dry_run:
        print(yellow("\n  Dry run — no changes were made."))
    else:
        print(green(f"\n  All {len(pending)} migration(s) applied successfully.\n"))


def cmd_rollback(conn, psql_bin: str, steps: int, dry_run: bool) -> None:
    applied_ordered = get_applied_ordered(conn)

    if not applied_ordered:
        print(yellow("No applied migrations to roll back."))
        return

    to_rollback = list(reversed(applied_ordered))[:steps]

    label = "Would roll back" if dry_run else "Rolling back"
    print(bold(f"\n{label} {len(to_rollback)} migration(s):\n"))

    for mid, file_name, _ in to_rollback:
        down = MIGRATIONS_DIR / file_name.replace(".up.sql", ".down.sql")
        print(f"  ← {bold(file_name)}  →  {dim(down.name)}")

        if not down.exists():
            print(red(f"    Down migration not found: {down}"))
            sys.exit(1)

        ok = run_sql_file(psql_bin, down, dry_run)
        if not ok:
            print(red(f"\n  Rollback of {file_name} FAILED — stopping."))
            sys.exit(1)

        if not dry_run:
            remove_applied(conn, mid)
            print(f"    {green('✓ rolled back')}")

    if dry_run:
        print(yellow("\n  Dry run — no changes were made."))
    else:
        print(green(f"\n  {len(to_rollback)} migration(s) rolled back.\n"))


def cmd_rollback_to_target(conn, psql_bin: str, target: str, dry_run: bool) -> None:
    applied_ordered = get_applied_ordered(conn)
    applied_above   = [(m, fn, ts) for m, fn, ts in reversed(applied_ordered) if m > target]

    if not applied_above:
        print(green(f"Already at or below target {target}."))
        return

    cmd_rollback_rows(conn, psql_bin, applied_above, dry_run)


def cmd_rollback_rows(conn, psql_bin, rows, dry_run) -> None:
    label = "Would roll back" if dry_run else "Rolling back"
    print(bold(f"\n{label} {len(rows)} migration(s):\n"))

    for mid, file_name, _ in rows:
        down = MIGRATIONS_DIR / file_name.replace(".up.sql", ".down.sql")
        print(f"  ← {bold(file_name)}  →  {dim(down.name)}")

        if not down.exists():
            print(red(f"    Down migration not found: {down}"))
            sys.exit(1)

        ok = run_sql_file(psql_bin, down, dry_run)
        if not ok:
            print(red(f"\n  Rollback of {file_name} FAILED — stopping."))
            sys.exit(1)

        if not dry_run:
            remove_applied(conn, mid)
            print(f"    {green('✓ rolled back')}")

    if dry_run:
        print(yellow("\n  Dry run — no changes were made."))
    else:
        print(green(f"\n  {len(rows)} migration(s) rolled back.\n"))

# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------

def parse_args():
    p = argparse.ArgumentParser(
        description="Apply or roll back eligibility schema migrations.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    p.add_argument(
        "--status",
        action="store_true",
        help="Show which migrations are applied or pending.",
    )
    p.add_argument(
        "--rollback",
        nargs="?",
        const=1,
        type=int,
        metavar="N",
        help="Roll back the last N applied migrations (default 1).",
    )
    p.add_argument(
        "--target",
        metavar="NUM",
        help=(
            "Three-digit migration number to migrate to, e.g. 008. "
            "Applies pending migrations up to NUM, or rolls back above NUM."
        ),
    )
    p.add_argument(
        "--dry-run",
        action="store_true",
        help="Print what would run without executing anything.",
    )
    return p.parse_args()


def main():
    args = parse_args()

    if not MIGRATIONS_DIR.exists():
        print(red(f"Migrations directory not found: {MIGRATIONS_DIR}"), file=sys.stderr)
        sys.exit(1)

    psql_bin = find_psql()
    conn     = open_conn()
    ensure_tracking_table(conn)

    # --status
    if args.status:
        cmd_status(conn)
        return

    # --rollback [N]
    if args.rollback is not None:
        if args.target:
            print(red("--rollback and --target cannot be used together."), file=sys.stderr)
            sys.exit(1)
        cmd_rollback(conn, psql_bin, args.rollback, args.dry_run)
        return

    # --target NUM
    if args.target:
        target = args.target.zfill(3)
        applied_ids = get_applied_migrations(conn)
        highest_applied = max(applied_ids, default="000")

        if target > highest_applied:
            # Migrate up to target
            cmd_up(conn, psql_bin, target, args.dry_run)
        elif target < highest_applied:
            # Roll back to target
            cmd_rollback_to_target(conn, psql_bin, target, args.dry_run)
        else:
            print(green(f"Already at target {target}."))
        return

    # Default: apply all pending
    cmd_up(conn, psql_bin, target=None, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
