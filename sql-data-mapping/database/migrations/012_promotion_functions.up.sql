BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'eligibility'
          AND t.typname = 'promotion_status'
    ) THEN
        CREATE TYPE eligibility.promotion_status AS ENUM (
            'promoted',
            'skipped_duplicate',
            'failed_validation',
            'failed_system'
        );
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS eligibility.promotion_audit (
    promotion_attempt_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    batch_id UUID NULL
        REFERENCES eligibility.partner_eligibility_batch(batch_id)
        ON DELETE SET NULL,

    eligibility_record_id UUID NULL
        REFERENCES eligibility.canonical_eligibility_record(eligibility_record_id)
        ON DELETE SET NULL,

    partner_id TEXT NULL,
    tenant_id TEXT NULL,
    org_id TEXT NULL,
    data_region TEXT NULL,

    source_event_id TEXT NULL,
    record_hash TEXT NULL,
    previous_record_hash TEXT NULL,

    promotion_status eligibility.promotion_status NOT NULL,

    failure_code TEXT NULL,
    failure_reason TEXT NULL,

    curated_eligibility_current_id UUID NULL,
    curated_eligibility_history_id UUID NULL,

    attempted_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    promoted_at TIMESTAMPTZ NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT promotion_audit_failure_reason_required_chk
        CHECK (
            promotion_status IN ('promoted', 'skipped_duplicate')
            OR failure_reason IS NOT NULL
        )
);

CREATE INDEX IF NOT EXISTS idx_promotion_audit_success_lookup
    ON eligibility.promotion_audit (eligibility_record_id, record_hash)
    WHERE promotion_status = 'promoted';

CREATE INDEX IF NOT EXISTS idx_promotion_audit_batch_id
    ON eligibility.promotion_audit (batch_id);

CREATE INDEX IF NOT EXISTS idx_promotion_audit_record_id
    ON eligibility.promotion_audit (eligibility_record_id);

CREATE INDEX IF NOT EXISTS idx_promotion_audit_status_attempted_at
    ON eligibility.promotion_audit (promotion_status, attempted_at DESC);

CREATE INDEX IF NOT EXISTS idx_promotion_audit_partner_tenant
    ON eligibility.promotion_audit (partner_id, tenant_id, attempted_at DESC);

DROP TRIGGER IF EXISTS trg_promotion_audit_updated_at
    ON eligibility.promotion_audit;

CREATE TRIGGER trg_promotion_audit_updated_at
BEFORE UPDATE ON eligibility.promotion_audit
FOR EACH ROW
EXECUTE FUNCTION eligibility.set_updated_at();

CREATE OR REPLACE FUNCTION eligibility.insert_promotion_audit(
    p_record eligibility.canonical_eligibility_record,
    p_status eligibility.promotion_status,
    p_failure_code TEXT DEFAULT NULL,
    p_failure_reason TEXT DEFAULT NULL,
    p_previous_record_hash TEXT DEFAULT NULL,
    p_curated_eligibility_current_id UUID DEFAULT NULL,
    p_curated_eligibility_history_id UUID DEFAULT NULL
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_audit_id UUID;
BEGIN
    INSERT INTO eligibility.promotion_audit (
        batch_id,
        eligibility_record_id,
        partner_id,
        tenant_id,
        org_id,
        data_region,
        source_event_id,
        record_hash,
        previous_record_hash,
        promotion_status,
        failure_code,
        failure_reason,
        curated_eligibility_current_id,
        curated_eligibility_history_id,
        promoted_at
    )
    VALUES (
        p_record.batch_id,
        p_record.eligibility_record_id,
        p_record.partner_id,
        p_record.tenant_id,
        p_record.org_id,
        p_record.data_region,
        p_record.source_event_id,
        p_record.record_hash,
        p_previous_record_hash,
        p_status,
        p_failure_code,
        p_failure_reason,
        p_curated_eligibility_current_id,
        p_curated_eligibility_history_id,
        CASE WHEN p_status = 'promoted' THEN now() ELSE NULL END
    )
    RETURNING promotion_attempt_id INTO v_audit_id;

    RETURN v_audit_id;
END;
$$;

CREATE OR REPLACE FUNCTION eligibility.canonical_record_has_open_quarantine(
    p_eligibility_record_id UUID
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT EXISTS (
        SELECT 1
        FROM eligibility.eligibility_quarantine q
        WHERE q.eligibility_record_id = p_eligibility_record_id
          AND COALESCE(q.review_status::TEXT, 'open') NOT IN ('resolved', 'closed', 'ignored')
    );
$$;

CREATE OR REPLACE FUNCTION eligibility.is_canonical_record_promotable(
    p_record eligibility.canonical_eligibility_record,
    OUT is_promotable BOOLEAN,
    OUT failure_code TEXT,
    OUT failure_reason TEXT
)
LANGUAGE plpgsql
STABLE
AS $$
BEGIN
    is_promotable := FALSE;
    failure_code := NULL;
    failure_reason := NULL;

    IF p_record.dq_status::TEXT NOT IN ('valid', 'valid_with_warnings') THEN
        failure_code := 'DQ_STATUS_NOT_PROMOTABLE';
        failure_reason := format(
            'Record dq_status is %s, expected valid or valid_with_warnings.',
            p_record.dq_status::TEXT
        );
        RETURN;
    END IF;

    IF COALESCE(p_record.contains_prohibited_pii, FALSE) = TRUE THEN
        failure_code := 'PROHIBITED_PII_PRESENT';
        failure_reason := 'Record contains prohibited PII and cannot be promoted.';
        RETURN;
    END IF;

    IF COALESCE(p_record.requires_manual_review, FALSE) = TRUE THEN
        failure_code := 'MANUAL_REVIEW_REQUIRED';
        failure_reason := 'Record requires manual review before promotion.';
        RETURN;
    END IF;

    IF p_record.tokenization_status IS NOT NULL
       AND p_record.tokenization_status::TEXT IN ('pending', 'failed') THEN
        failure_code := 'TOKENIZATION_INCOMPLETE';
        failure_reason := format(
            'Record tokenization_status is %s, expected completed or not_required.',
            p_record.tokenization_status::TEXT
        );
        RETURN;
    END IF;

    IF p_record.encryption_status IS NOT NULL
       AND p_record.encryption_status::TEXT = 'failed' THEN
        failure_code := 'ENCRYPTION_FAILED';
        failure_reason := 'Record encryption_status is failed.';
        RETURN;
    END IF;

    IF p_record.partner_id IS NULL
       OR p_record.tenant_id IS NULL
       OR p_record.org_id IS NULL
       OR p_record.data_region IS NULL THEN
        failure_code := 'MISSING_SCOPE';
        failure_reason := 'Record must include partner_id, tenant_id, org_id, and data_region.';
        RETURN;
    END IF;

    IF p_record.partner_employee_id IS NULL
       AND p_record.partner_person_id IS NULL
       AND p_record.partner_member_id IS NULL THEN
        failure_code := 'MISSING_PARTNER_IDENTIFIER';
        failure_reason := 'Record must include at least one partner employee/person/member identifier.';
        RETURN;
    END IF;

    IF p_record.person_relationship_type::TEXT <> 'employee' THEN
        failure_code := 'RELATIONSHIP_NOT_CURATABLE';
        failure_reason := format(
            'Record relationship type %s is not promoted into curated_eligibility_current by this serving model.',
            p_record.person_relationship_type::TEXT
        );
        RETURN;
    END IF;

    IF p_record.eligibility_status IS NULL
       OR p_record.eligibility_status::TEXT = 'unknown' THEN
        failure_code := 'UNKNOWN_ELIGIBILITY_STATUS';
        failure_reason := 'Record eligibility_status cannot be unknown for curated serving.';
        RETURN;
    END IF;

    IF p_record.eligibility_start_date IS NOT NULL
       AND p_record.eligibility_end_date IS NOT NULL
       AND p_record.eligibility_end_date < p_record.eligibility_start_date THEN
        failure_code := 'INVALID_ELIGIBILITY_DATE_RANGE';
        failure_reason := 'eligibility_end_date cannot be before eligibility_start_date.';
        RETURN;
    END IF;

    IF eligibility.canonical_record_has_open_quarantine(p_record.eligibility_record_id) THEN
        failure_code := 'OPEN_QUARANTINE';
        failure_reason := 'Record has an unresolved quarantine issue.';
        RETURN;
    END IF;

    is_promotable := TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION eligibility.find_curated_current_id_for_record(
    p_record eligibility.canonical_eligibility_record
)
RETURNS UUID
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
    v_current_id UUID;
BEGIN

    SELECT c.curated_eligibility_id
    INTO v_current_id
    FROM eligibility.curated_eligibility_current c
    WHERE c.partner_id = p_record.partner_id
      AND c.tenant_id = p_record.tenant_id
      AND c.org_id = p_record.org_id
      AND c.data_region = p_record.data_region
      AND (
            (p_record.partner_member_id IS NOT NULL
             AND c.partner_member_id = p_record.partner_member_id)

         OR (p_record.partner_member_id IS NULL
             AND p_record.partner_person_id IS NOT NULL
             AND c.partner_person_id = p_record.partner_person_id)

         OR (p_record.partner_member_id IS NULL
             AND p_record.partner_person_id IS NULL
             AND p_record.partner_employee_id IS NOT NULL
             AND c.partner_employee_id = p_record.partner_employee_id)
      )
    ORDER BY c.updated_at DESC
    LIMIT 1;

    RETURN v_current_id;
END;
$$;

CREATE OR REPLACE FUNCTION eligibility.close_current_history_record(
    p_curated_eligibility_current_id UUID,
    p_valid_to TIMESTAMPTZ DEFAULT now()
)
RETURNS INTEGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_closed_count INTEGER;
BEGIN
    UPDATE eligibility.curated_eligibility_history h
    SET valid_to = p_valid_to
    WHERE h.curated_eligibility_id = p_curated_eligibility_current_id
      AND h.valid_to IS NULL;

    GET DIAGNOSTICS v_closed_count = ROW_COUNT;
    RETURN v_closed_count;
END;
$$;

DROP FUNCTION IF EXISTS eligibility.calculate_current_eligibility(
    eligibility.eligibility_status, DATE, DATE
) CASCADE;

CREATE FUNCTION eligibility.calculate_current_eligibility(
    p_status     eligibility.eligibility_status,
    p_start_date DATE,
    p_end_date   DATE
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT
        p_status::TEXT = 'active'
        AND (p_start_date IS NULL OR p_start_date <= CURRENT_DATE)
        AND (p_end_date   IS NULL OR p_end_date   >= CURRENT_DATE);
$$;

CREATE OR REPLACE VIEW eligibility.v_current_active_eligibility AS
SELECT
    curated_eligibility_id,
    eligibility_record_id,
    partner_id,
    tenant_id,
    org_id,
    data_region,
    partner_employee_id,
    partner_person_id,
    partner_member_id,
    eligibility_status,
    eligibility.calculate_current_eligibility(
        eligibility_status,
        eligibility_start_date,
        eligibility_end_date
    ) AS is_currently_eligible,
    eligibility_start_date,
    eligibility_end_date,
    eligibility_group_code,
    benefit_plan_id,
    person_relationship_type,
    identity_match_policy_id,
    source_last_updated_at,
    curated_at
FROM eligibility.curated_eligibility_current
WHERE eligibility_status = 'active'
  AND (eligibility_start_date IS NULL OR eligibility_start_date <= CURRENT_DATE)
  AND (eligibility_end_date IS NULL OR eligibility_end_date >= CURRENT_DATE);

CREATE OR REPLACE FUNCTION eligibility.upsert_curated_current(
    p_record eligibility.canonical_eligibility_record,
    OUT curated_eligibility_current_id UUID,
    OUT previous_record_hash TEXT,
    OUT changed BOOLEAN
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_existing_id UUID;
    v_existing_hash TEXT;
    v_source_last_updated_at TIMESTAMPTZ;
BEGIN
    v_existing_id := eligibility.find_curated_current_id_for_record(p_record);
    v_source_last_updated_at := COALESCE(
        p_record.source_event_timestamp,
        p_record.change_detected_at,
        p_record.processed_at,
        p_record.updated_at,
        now()
    );

    IF v_existing_id IS NOT NULL THEN

        SELECT h.record_hash
        INTO v_existing_hash
        FROM eligibility.curated_eligibility_history h
        WHERE h.curated_eligibility_id = v_existing_id
          AND h.valid_to IS NULL
        ORDER BY h.valid_from DESC
        LIMIT 1;

        curated_eligibility_current_id := v_existing_id;
        previous_record_hash := v_existing_hash;

        IF v_existing_hash IS NOT DISTINCT FROM p_record.record_hash THEN
            changed := FALSE;
            RETURN;
        END IF;

        UPDATE eligibility.curated_eligibility_current c
        SET
            eligibility_record_id      = p_record.eligibility_record_id,
            partner_employee_id        = p_record.partner_employee_id,
            partner_person_id          = p_record.partner_person_id,
            partner_member_id          = p_record.partner_member_id,
            eligibility_status         = p_record.eligibility_status,
            eligibility_start_date     = p_record.eligibility_start_date,
            eligibility_end_date       = p_record.eligibility_end_date,
            eligibility_group_code     = p_record.eligibility_group_code,
            benefit_plan_id            = p_record.benefit_plan_id,
            person_relationship_type   = p_record.person_relationship_type,
            identity_match_policy_id   = 'policy_v1',
            dq_status                  = p_record.dq_status,
            source_last_updated_at     = v_source_last_updated_at,
            curated_at                 = now(),
            updated_at                 = now()
        WHERE c.curated_eligibility_id = v_existing_id
        RETURNING c.curated_eligibility_id
        INTO curated_eligibility_current_id;

        changed := TRUE;
        RETURN;
    END IF;

    INSERT INTO eligibility.curated_eligibility_current (
        eligibility_record_id,
        partner_id,
        tenant_id,
        org_id,
        data_region,
        partner_employee_id,
        partner_person_id,
        partner_member_id,
        eligibility_status,
        eligibility_start_date,
        eligibility_end_date,
        eligibility_group_code,
        benefit_plan_id,
        person_relationship_type,
        identity_match_policy_id,
        dq_status,
        source_last_updated_at,
        curated_at,
        created_at,
        updated_at
    )
    VALUES (
        p_record.eligibility_record_id,
        p_record.partner_id,
        p_record.tenant_id,
        p_record.org_id,
        p_record.data_region,
        p_record.partner_employee_id,
        p_record.partner_person_id,
        p_record.partner_member_id,
        p_record.eligibility_status,
        p_record.eligibility_start_date,
        p_record.eligibility_end_date,
        p_record.eligibility_group_code,
        p_record.benefit_plan_id,
        p_record.person_relationship_type,
        'policy_v1',
        p_record.dq_status,
        v_source_last_updated_at,
        now(),
        now(),
        now()
    )
    RETURNING curated_eligibility_id
    INTO curated_eligibility_current_id;

    previous_record_hash := NULL;
    changed := TRUE;
END;
$$;

CREATE OR REPLACE FUNCTION eligibility.insert_curated_history(
    p_record eligibility.canonical_eligibility_record,
    p_curated_eligibility_current_id UUID
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_history_id UUID;
    v_valid_from TIMESTAMPTZ;
BEGIN
    v_valid_from := COALESCE(
        p_record.source_event_timestamp,
        p_record.change_detected_at,
        p_record.processed_at,
        now()
    );

    INSERT INTO eligibility.curated_eligibility_history (
        history_id,
        curated_eligibility_id,
        eligibility_record_id,
        partner_id,
        tenant_id,
        org_id,
        data_region,
        partner_employee_id,
        partner_person_id,
        partner_member_id,
        eligibility_status,
        is_currently_eligible,
        eligibility_start_date,
        eligibility_end_date,
        valid_from,
        valid_to,
        change_reason,
        source_operation,
        record_hash,
        created_at
    )
    VALUES (
        gen_random_uuid(),
        p_curated_eligibility_current_id,
        p_record.eligibility_record_id,
        p_record.partner_id,
        p_record.tenant_id,
        p_record.org_id,
        p_record.data_region,
        p_record.partner_employee_id,
        p_record.partner_person_id,
        p_record.partner_member_id,
        p_record.eligibility_status,
        eligibility.calculate_current_eligibility(
            p_record.eligibility_status,
            p_record.eligibility_start_date,
            p_record.eligibility_end_date
        ),
        p_record.eligibility_start_date,
        p_record.eligibility_end_date,
        v_valid_from,
        NULL,
        CASE
            WHEN p_record.change_reason IS NOT NULL THEN p_record.change_reason
            WHEN p_record.source_operation IS NULL THEN 'canonical_promotion'
            ELSE 'canonical_promotion_' || p_record.source_operation::TEXT
        END,
        p_record.source_operation,
        p_record.record_hash,
        now()
    )
    RETURNING history_id
    INTO v_history_id;

    RETURN v_history_id;
END;
$$;

CREATE OR REPLACE FUNCTION eligibility.promote_canonical_record(
    p_eligibility_record_id UUID,
    p_force_reprocess BOOLEAN DEFAULT FALSE
)
RETURNS UUID
LANGUAGE plpgsql
AS $$
DECLARE
    v_record             eligibility.canonical_eligibility_record;
    v_existing_success_id UUID;
    v_validation         RECORD;
    v_current_id         UUID;
    v_history_id         UUID;
    v_previous_hash      TEXT;
    v_changed            BOOLEAN;
    v_audit_id           UUID;
BEGIN
    SELECT r.*
    INTO v_record
    FROM eligibility.canonical_eligibility_record r
    WHERE r.eligibility_record_id = p_eligibility_record_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Canonical eligibility record % not found', p_eligibility_record_id
            USING ERRCODE = 'P0002';
    END IF;

    IF NOT p_force_reprocess THEN
        SELECT a.promotion_attempt_id
        INTO v_existing_success_id
        FROM eligibility.promotion_audit a
        WHERE a.eligibility_record_id = p_eligibility_record_id
          AND a.record_hash = v_record.record_hash
          AND a.promotion_status = 'promoted'
        ORDER BY a.promoted_at DESC NULLS LAST, a.attempted_at DESC
        LIMIT 1;

        IF v_existing_success_id IS NOT NULL THEN
            RETURN eligibility.insert_promotion_audit(
                v_record,
                'skipped_duplicate',
                'ALREADY_PROMOTED',
                NULL,
                v_record.record_hash,
                NULL,
                NULL
            );
        END IF;
    END IF;

    SELECT *
    INTO v_validation
    FROM eligibility.is_canonical_record_promotable(v_record);

    IF NOT v_validation.is_promotable THEN
        RETURN eligibility.insert_promotion_audit(
            v_record,
            'failed_validation',
            v_validation.failure_code,
            v_validation.failure_reason,
            NULL,
            NULL,
            NULL
        );
    END IF;

    SELECT u.curated_eligibility_current_id,
           u.previous_record_hash,
           u.changed
    INTO   v_current_id,
           v_previous_hash,
           v_changed
    FROM eligibility.upsert_curated_current(v_record) u;

    IF NOT v_changed THEN
        RETURN eligibility.insert_promotion_audit(
            v_record,
            'skipped_duplicate',
            'UNCHANGED_RECORD_HASH',
            NULL,
            v_previous_hash,
            v_current_id,
            NULL
        );
    END IF;

    PERFORM eligibility.close_current_history_record(v_current_id, now());

    v_history_id := eligibility.insert_curated_history(v_record, v_current_id);

    v_audit_id := eligibility.insert_promotion_audit(
        v_record,
        'promoted',
        NULL,
        NULL,
        v_previous_hash,
        v_current_id,
        v_history_id
    );

    PERFORM pg_notify(
        'eligibility.promotion_events',
        jsonb_build_object(
            'event',                    'record_promoted',
            'partner_id',               v_record.partner_id,
            'tenant_id',                v_record.tenant_id,
            'eligibility_record_id',    v_record.eligibility_record_id,
            'curated_eligibility_id',   v_current_id,
            'batch_id',                 v_record.batch_id,
            'promoted_at',              now()
        )::TEXT
    );

    RETURN v_audit_id;

EXCEPTION
    WHEN OTHERS THEN

        IF v_record.eligibility_record_id IS NOT NULL THEN
            RETURN eligibility.insert_promotion_audit(
                v_record,
                'failed_system',
                SQLSTATE,
                SQLERRM,
                NULL,
                NULL,
                NULL
            );
        END IF;

        RAISE;
END;
$$;

CREATE OR REPLACE FUNCTION eligibility.promote_batch(
    p_batch_id UUID,
    p_force_reprocess BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    batch_id                  UUID,
    total_records             INTEGER,
    promoted_count            INTEGER,
    skipped_duplicate_count   INTEGER,
    failed_validation_count   INTEGER,
    failed_system_count       INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_record_id  UUID;
    v_audit_id   UUID;
    v_audit_ids  UUID[] := ARRAY[]::UUID[];
BEGIN
    total_records           := 0;
    promoted_count          := 0;
    skipped_duplicate_count := 0;
    failed_validation_count := 0;
    failed_system_count     := 0;

    IF NOT EXISTS (
        SELECT 1
        FROM eligibility.partner_eligibility_batch b
        WHERE b.batch_id = p_batch_id
    ) THEN
        RAISE EXCEPTION 'Partner eligibility batch % not found', p_batch_id
            USING ERRCODE = 'P0002';
    END IF;

    FOR v_record_id IN
        SELECT r.eligibility_record_id
        FROM eligibility.canonical_eligibility_record r
        WHERE r.batch_id = p_batch_id
        ORDER BY r.source_row_number NULLS LAST,
                 r.created_at ASC,
                 r.eligibility_record_id ASC
    LOOP
        total_records := total_records + 1;

        BEGIN
            v_audit_id := eligibility.promote_canonical_record(
                v_record_id,
                p_force_reprocess
            );

            IF v_audit_id IS NOT NULL THEN
                v_audit_ids := array_append(v_audit_ids, v_audit_id);
            END IF;

        EXCEPTION
            WHEN OTHERS THEN

                INSERT INTO eligibility.promotion_audit (
                    batch_id,
                    eligibility_record_id,
                    promotion_status,
                    failure_code,
                    failure_reason
                )
                VALUES (
                    p_batch_id,
                    v_record_id,
                    'failed_system',
                    SQLSTATE,
                    SQLERRM
                )
                RETURNING promotion_attempt_id INTO v_audit_id;

                v_audit_ids := array_append(v_audit_ids, v_audit_id);
        END;
    END LOOP;

    SELECT
        COALESCE(COUNT(*) FILTER (WHERE a.promotion_status = 'promoted'),          0)::INTEGER,
        COALESCE(COUNT(*) FILTER (WHERE a.promotion_status = 'skipped_duplicate'), 0)::INTEGER,
        COALESCE(COUNT(*) FILTER (WHERE a.promotion_status = 'failed_validation'), 0)::INTEGER,
        COALESCE(COUNT(*) FILTER (WHERE a.promotion_status = 'failed_system'),     0)::INTEGER
    INTO
        promoted_count,
        skipped_duplicate_count,
        failed_validation_count,
        failed_system_count
    FROM eligibility.promotion_audit a
    WHERE a.promotion_attempt_id = ANY(v_audit_ids);

    batch_id := p_batch_id;

    RETURN NEXT;
END;
$$;

COMMIT;
