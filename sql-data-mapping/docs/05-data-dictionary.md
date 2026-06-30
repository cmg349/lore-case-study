# Data Dictionary — Eligibility Schema

All tables live in the `eligibility` schema. Every table is scoped by `(partner_id, tenant_id, org_id, data_region)` and protected by Row-Level Security (RLS) enforced via session GUCs.

---

## Pipeline Layers at a Glance

```
[Intake]          partner_eligibility_batch
                       │
[Normalization]   canonical_eligibility_record
                  ├── eligibility_person_pii       (1:1 PII vault)
                  └── eligibility_identity_token   (N:1 token store)
                       │
[DQ Gate]         eligibility_quarantine           (failures held here)
                       │
[Serving]         curated_eligibility_current      (one row per employee)
                  └── curated_eligibility_history  (SCD Type 2, partitioned)
                       │
[Audit]           promotion_audit
                       │
[Config]          partner_contract ──► partner_schema_version
                                   ├── partner_field_mapping
                                   ├── partner_data_quality_rule
                                   ├── partner_value_mapping
                                   ├── partner_delivery_sla
                                   ├── partner_pii_policy
                                   └── partner_schema_change_log
                       │
[Identity Verif.] identity_verification_request
                  ├── identity_verification_match_candidate
                  └── identity_verification_decision
                       │
[Reprocessing]    reprocessing_job
                  └── reprocessing_job_record
```

---

## Layer 1 — Intake

### `partner_eligibility_batch`

**Purpose:** Entry point for all data into the system. One row is created for every delivery event — file drop, API call, or event stream — regardless of how many member records it contains. Every downstream table traces back to a `batch_id`.

**Source migration:** `002_eligbility_batch_table`

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `batch_id` | UUID | NOT NULL | `gen_random_uuid()` | Primary key |
| `partner_id` | TEXT | NOT NULL | — | Identifies the delivering partner |
| `tenant_id` | TEXT | NOT NULL | — | Tenant within the partner scope |
| `org_id` | TEXT | NOT NULL | — | Organisation within the tenant |
| `data_region` | TEXT | NOT NULL | — | Data residency region (e.g. `us-east`) |
| `source_file_name` | TEXT | NULL | — | Original filename of the delivered file, if applicable |
| `source_file_uri` | TEXT | NULL | — | Storage URI where the raw file resides |
| `source_file_checksum` | TEXT | NOT NULL | — | Hash of the delivered file; used for duplicate detection |
| `source_schema_version` | TEXT | NOT NULL | — | Schema version string declared by the partner for this delivery |
| `delivery_type` | `delivery_type` ENUM | NOT NULL | — | How the data was delivered (`file`, `sftp`, `api`, `event_stream`, etc.) |
| `is_full_snapshot` | BOOLEAN | NOT NULL | `FALSE` | TRUE when the delivery represents a complete population snapshot rather than an incremental diff |
| `snapshot_as_of_at` | TIMESTAMPTZ | NULL | — | Point-in-time the snapshot was taken; required when `is_full_snapshot = TRUE` |
| `received_at` | TIMESTAMPTZ | NOT NULL | `now()` | When the platform accepted the delivery |
| `processing_started_at` | TIMESTAMPTZ | NULL | — | When pipeline processing began |
| `processing_completed_at` | TIMESTAMPTZ | NULL | — | When pipeline processing finished |
| `batch_status` | `batch_status` ENUM | NOT NULL | `'received'` | Lifecycle state (`received` → `processing` → `completed` / `failed`) |
| `record_count` | INTEGER | NULL | — | Total records in the delivery |
| `valid_record_count` | INTEGER | NULL | — | Records that passed DQ with no issues |
| `valid_with_warnings_record_count` | INTEGER | NULL | — | Records that passed DQ but with warnings |
| `quarantined_record_count` | INTEGER | NULL | — | Records held in quarantine due to blocking DQ failures |
| `rejected_record_count` | INTEGER | NULL | — | Records rejected outright |
| `dq_error_count` | INTEGER | NOT NULL | `0` | Total blocking DQ errors across all records in the batch |
| `dq_warning_count` | INTEGER | NOT NULL | `0` | Total DQ warnings across all records in the batch |
| `created_at` | TIMESTAMPTZ | NOT NULL | `now()` | Row creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `now()` | Last modification timestamp (maintained by trigger) |

**Key constraints:**
- `chk_batch_record_counts_non_negative` — all count columns must be ≥ 0
- `chk_batch_snapshot_as_of_required` — if `is_full_snapshot = TRUE`, `snapshot_as_of_at` must be set

**Key indexes:**
- `UNIQUE (partner_id, tenant_id, source_file_checksum)` — prevents re-ingesting the same file
- `(partner_id, received_at DESC)` — recent deliveries per partner
- `(batch_status, received_at DESC)` — monitoring queues filtered by status

---

## Layer 2 — Normalization

### `canonical_eligibility_record`

**Purpose:** The central hub table. Holds the normalized, PII-free representation of one person's eligibility record from one batch delivery. Every other table in the schema either references this table or is derived from it. Deliberately contains no personal identifying information — all PII lives in the companion `eligibility_person_pii` table.

**Source migration:** `003_canonical_eligibility_record`

#### Identity & Provenance

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `eligibility_record_id` | UUID | NOT NULL | `gen_random_uuid()` | Primary key |
| `batch_id` | UUID | NOT NULL | — | FK → `partner_eligibility_batch`; the delivery this record belongs to |
| `partner_id` | TEXT | NOT NULL | — | Partner scope column |
| `tenant_id` | TEXT | NOT NULL | — | Tenant scope column |
| `org_id` | TEXT | NOT NULL | — | Organisation scope column |
| `data_region` | TEXT | NOT NULL | — | Data residency region |
| `source_record_id` | TEXT | NULL | — | Partner's own ID for this row in the source system |
| `source_row_number` | INTEGER | NULL | — | Row number in the delivered file (must be > 0 if set) |
| `source_schema_version` | TEXT | NOT NULL | — | Schema version at time of delivery |
| `source_operation` | `source_operation` ENUM | NULL | — | What the source said happened: `insert`, `update`, `delete`, `snapshot` |
| `source_event_id` | TEXT | NULL | — | Unique event identifier for event-stream deliveries |
| `source_event_timestamp` | TIMESTAMPTZ | NULL | — | When the event was emitted by the source system |
| `is_full_snapshot` | BOOLEAN | NOT NULL | `FALSE` | Inherited from the batch; TRUE for snapshot deliveries |
| `snapshot_as_of_at` | TIMESTAMPTZ | NULL | — | Point-in-time the snapshot represents |

#### Partner Identifiers

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `partner_employee_id` | TEXT | NOT NULL | — | Primary partner-assigned employee identifier (required) |
| `partner_member_id` | TEXT | NULL | — | Plan-level member identifier (used for dependent matching) |
| `partner_person_id` | TEXT | NULL | — | Person-level identifier spanning multiple member records |
| `external_account_id` | TEXT | NULL | — | Identifier from an external HR or benefits system |
| `employee_number` | TEXT | NULL | — | HR system employee number |
| `legacy_employee_id` | TEXT | NULL | — | Identifier from a legacy system retained for continuity |

> At least one of `partner_employee_id`, `partner_person_id`, or `partner_member_id` must be non-null (`chk_canonical_required_identifiers`).

#### Work Location (Non-PII)

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `work_location_city` | TEXT | NULL | — | City of the person's work location (not home address) |
| `work_location_region` | TEXT | NULL | — | State / province of work location |
| `work_location_country` | TEXT | NULL | — | Country of work location |
| `legal_entity_country` | TEXT | NULL | — | Country of the legal employing entity |

#### Employment Details

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `employment_status` | TEXT | NULL | — | Free-text employment status from the source (e.g. `active`, `on_leave`) |
| `employment_type` | TEXT | NULL | — | Full-time / part-time / contractor classification |
| `worker_type` | TEXT | NULL | — | Sub-classification of worker (e.g. `W2`, `1099`, `intern`) |
| `job_title` | TEXT | NULL | — | Job title from the source system |
| `job_code` | TEXT | NULL | — | Structured job code from the HR system |
| `department` | TEXT | NULL | — | Department name |
| `division` | TEXT | NULL | — | Division or business unit |
| `cost_center` | TEXT | NULL | — | Cost center code for payroll allocation |
| `manager_employee_id` | TEXT | NULL | — | `partner_employee_id` of the person's manager |
| `hire_date` | DATE | NULL | — | Original hire date |
| `termination_date` | DATE | NULL | — | Termination date (must be ≥ `hire_date` if both set) |
| `leave_start_date` | DATE | NULL | — | Start of leave of absence |
| `leave_end_date` | DATE | NULL | — | End of leave of absence (must be ≥ `leave_start_date` if both set) |

#### Eligibility Details

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `eligibility_status` | `eligibility_status` ENUM | NOT NULL | — | Current eligibility state: `active`, `inactive`, `terminated`, `on_leave`, `expired`, `pending`, `unknown` |
| `eligibility_status_reason` | TEXT | NULL | — | Free-text reason for the current eligibility status |
| `eligibility_start_date` | DATE | NOT NULL | — | Date when eligibility coverage begins |
| `eligibility_end_date` | DATE | NULL | — | Date when eligibility coverage ends (NULL = open-ended) |
| `eligibility_effective_date` | DATE | NULL | — | Date the eligibility event takes administrative effect |
| `eligibility_group_code` | TEXT | NULL | — | Benefit group or plan class code |
| `eligibility_group_name` | TEXT | NULL | — | Human-readable name for the benefit group |
| `benefit_plan_id` | TEXT | NULL | — | Identifier for the specific benefit plan |
| `benefit_plan_name` | TEXT | NULL | — | Human-readable benefit plan name |
| `coverage_level` | TEXT | NULL | — | Coverage tier (e.g. `employee_only`, `family`, `employee_spouse`) |
| `eligibility_priority` | INTEGER | NULL | — | Numeric priority when a person has multiple eligibility records |

> `inactive`, `terminated`, and `expired` statuses require `eligibility_end_date` to be set (`chk_canonical_end_date_for_inactive_states`).

#### Relationship Details

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `person_relationship_type` | `person_relationship_type` ENUM | NOT NULL | `'employee'` | Role of the person: `employee`, `spouse`, `dependent`, `domestic_partner`, etc. |
| `primary_employee_partner_id` | TEXT | NULL | — | `partner_employee_id` of the primary subscriber (set for dependents) |
| `relationship_start_date` | DATE | NULL | — | Date the relationship coverage began |
| `relationship_end_date` | DATE | NULL | — | Date the relationship coverage ended |

#### Compliance & Privacy

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `privacy_jurisdiction` | TEXT | NULL | — | Applicable privacy regulation (e.g. `GDPR`, `CCPA`, `HIPAA`) |
| `processing_basis` | TEXT | NULL | — | Legal basis for processing under GDPR (e.g. `contract`, `legitimate_interest`) |
| `consent_required` | BOOLEAN | NULL | — | Whether explicit consent is required before processing |
| `legal_entity_id` | TEXT | NULL | — | Identifier of the legal employing entity |
| `legal_entity_name` | TEXT | NULL | — | Name of the legal employing entity |

#### Change Detection

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `record_hash` | TEXT | NOT NULL | — | Deterministic hash of all meaningful eligibility fields; used to detect changes between deliveries |
| `previous_record_hash` | TEXT | NULL | — | Hash from the previous version of this record |
| `change_detected_at` | TIMESTAMPTZ | NULL | — | When a change was detected versus the prior delivery |
| `change_reason` | TEXT | NULL | — | Description of what changed |

#### Data Quality State

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `dq_status` | `dq_status` ENUM | NOT NULL | `'pending_review'` | DQ outcome: `pending_review`, `valid`, `valid_with_warnings`, `quarantined`, `rejected` |
| `dq_score` | NUMERIC(5,2) | NULL | — | 0–100 quality score; computed as `100 - (blocking×20) - (warning×5) - (info×1)` |
| `dq_error_count` | INTEGER | NOT NULL | `0` | Number of blocking DQ rule failures |
| `dq_warning_count` | INTEGER | NOT NULL | `0` | Number of warning-level DQ rule failures |
| `dq_error_codes` | TEXT[] | NULL | — | Array of error codes from all failed DQ rules |
| `dq_last_checked_at` | TIMESTAMPTZ | NOT NULL | `now()` | When `evaluate_canonical_record_dq` last ran against this record |
| `requires_manual_review` | BOOLEAN | NOT NULL | `FALSE` | Blocks promotion until cleared; set when any blocking DQ failure occurs |

#### Privacy / Security Classification

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `pii_classification` | TEXT[] | NULL | — | Array of PII category labels applicable to this record (e.g. `['health', 'financial']`) |
| `contains_sensitive_pii` | BOOLEAN | NOT NULL | `FALSE` | TRUE if the record involves sensitive PII categories |
| `contains_prohibited_pii` | BOOLEAN | NOT NULL | `FALSE` | TRUE if prohibited PII was detected; blocks promotion |
| `tokenization_status` | `tokenization_status` ENUM | NOT NULL | `'pending'` | State of PII tokenization: `pending`, `completed`, `failed`, `not_required` |
| `encryption_status` | `encryption_status` ENUM | NOT NULL | `'not_required'` | State of PII encryption: `not_required`, `pending`, `completed`, `failed` |
| `retention_policy_id` | TEXT | NULL | — | Reference to the applicable data retention policy |
| `delete_after_date` | DATE | NULL | — | Date after which this record must be deleted (used by retention enforcement procedure) |
| `legal_hold` | BOOLEAN | NOT NULL | `FALSE` | TRUE prevents deletion by the retention procedure regardless of `delete_after_date` |
| `access_policy_id` | TEXT | NULL | — | Reference to the access control policy governing this record |

#### Timestamps

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `processed_at` | TIMESTAMPTZ | NOT NULL | `now()` | When the record was first normalized and written |
| `created_at` | TIMESTAMPTZ | NOT NULL | `now()` | Row creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `now()` | Last modification timestamp (trigger-maintained) |

---

### `eligibility_person_pii`

**Purpose:** The PII vault. Stores all personal identifying information for one canonical record. The 1:1 relationship with `canonical_eligibility_record` is enforced by a unique index on `eligibility_record_id`. Physically separating PII means the canonical record can be queried, hashed, and audit-logged without constituting a PII access event.

**Source migration:** `004_pii_vault`

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `pii_id` | UUID | NOT NULL | `gen_random_uuid()` | Primary key |
| `eligibility_record_id` | UUID | NOT NULL | — | FK → `canonical_eligibility_record` (CASCADE DELETE) |
| `partner_id` | TEXT | NOT NULL | — | Partner scope (duplicated for RLS) |
| `tenant_id` | TEXT | NOT NULL | — | Tenant scope (duplicated for RLS) |
| `org_id` | TEXT | NOT NULL | — | Organisation scope (duplicated for RLS) |
| `data_region` | TEXT | NOT NULL | — | Data residency region (duplicated for RLS) |
| `first_name` | TEXT | NOT NULL | — | Legal first name (must be non-empty after trimming) |
| `middle_name` | TEXT | NULL | — | Middle name or initial |
| `last_name` | TEXT | NOT NULL | — | Legal last name (must be non-empty after trimming) |
| `preferred_name` | TEXT | NULL | — | Preferred or chosen name |
| `full_name` | TEXT | NULL | — | Pre-composed full name as delivered by the partner |
| `name_suffix` | TEXT | NULL | — | Generational suffix (Jr., Sr., III, etc.) |
| `date_of_birth` | DATE | NULL | — | Date of birth |
| `primary_email` | CITEXT | NULL | — | Primary email address (case-insensitive storage) |
| `work_email` | CITEXT | NULL | — | Work email address |
| `personal_email` | CITEXT | NULL | — | Personal email address |
| `primary_phone` | TEXT | NULL | — | Primary phone number |
| `mobile_phone` | TEXT | NULL | — | Mobile/cell phone number |
| `work_phone` | TEXT | NULL | — | Work phone number |
| `phone_country_code` | TEXT | NULL | — | Country dialling code for `primary_phone` |
| `address_line_1` | TEXT | NULL | — | Home address line 1 |
| `address_line_2` | TEXT | NULL | — | Home address line 2 (apartment, suite, etc.) |
| `city` | TEXT | NULL | — | Home city |
| `region` | TEXT | NULL | — | Home state / province |
| `postal_code` | TEXT | NULL | — | Home postal / ZIP code |
| `country` | TEXT | NULL | — | Home country |
| `last_four_ssn` | TEXT | NULL | — | Last four digits of SSN (regex-enforced: exactly 4 digits `[0-9]{4}`) |
| `national_id` | TEXT | NULL | — | National identification number (non-US) |
| `normalized_primary_email` | CITEXT | NULL | — | Lowercased, trimmed version of `primary_email` used for consistent matching and tokenization |
| `normalized_work_email` | CITEXT | NULL | — | Normalized work email |
| `normalized_personal_email` | CITEXT | NULL | — | Normalized personal email |
| `normalized_primary_phone` | TEXT | NULL | — | Phone number normalized to E.164 or a consistent format |
| `pii_encryption_key_id` | TEXT | NULL | — | Reference to the encryption key used to encrypt this row's fields at rest |
| `encryption_status` | `encryption_status` ENUM | NOT NULL | `'not_required'` | Whether fields in this row are encrypted |
| `created_at` | TIMESTAMPTZ | NOT NULL | `now()` | Row creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `now()` | Last modification timestamp (trigger-maintained) |

**Key constraints:**
- `chk_pii_names_not_empty` — `first_name` and `last_name` cannot be blank after trimming
- `chk_pii_last_four_ssn_format` — `last_four_ssn` must match `^[0-9]{4}$`
- `UNIQUE (eligibility_record_id)` — enforces the 1:1 relationship with the canonical record

---

### `eligibility_identity_token`

**Purpose:** Stores one-way hashed tokens derived from PII fields. Each row is a single token: a hash of one PII value (email, phone, date of birth, name+DOB composite, or a partner identifier), typed by `token_type` and versioned. The raw PII value is never stored here. Tokens are the bridge used by the identity verification pipeline to match consumer-submitted hashes against stored records without ever comparing raw PII.

**Source migration:** `005_id_tokens`

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `identity_token_id` | UUID | NOT NULL | `gen_random_uuid()` | Primary key |
| `eligibility_record_id` | UUID | NOT NULL | — | FK → `canonical_eligibility_record` (CASCADE DELETE) |
| `partner_id` | TEXT | NOT NULL | — | Partner scope (for RLS and partner-scoped lookups) |
| `tenant_id` | TEXT | NOT NULL | — | Tenant scope |
| `org_id` | TEXT | NOT NULL | — | Organisation scope |
| `data_region` | TEXT | NOT NULL | — | Data residency region |
| `token_type` | `token_type` ENUM | NOT NULL | — | Which PII field was hashed: `email`, `phone`, `dob`, `name_dob`, `partner_employee_id`, `partner_person_id`, `partner_member_id` |
| `token_value` | TEXT | NOT NULL | — | The one-way hash value (must be non-empty) |
| `token_version` | TEXT | NOT NULL | `'v1'` | Hash algorithm version; allows rotation without invalidating old tokens |
| `created_at` | TIMESTAMPTZ | NOT NULL | `now()` | Row creation timestamp |

**Key constraints:**
- `chk_identity_token_value_not_empty` — `token_value` cannot be blank
- `UNIQUE (eligibility_record_id, token_type, token_version)` — one token per type per version per record

**Key indexes:**
- `(partner_id, tenant_id, token_type, token_value)` — within-partner matching during identity verification
- `(tenant_id, token_type, token_value)` — cross-partner deduplication within a tenant

---

## Layer 3 — Data Quality Gate

### `eligibility_quarantine`

**Purpose:** Holds records (or individual rule failures) that did not pass data quality checks. One row is created per failed DQ rule per canonical record. A record with multiple failures generates multiple quarantine rows. Records remain blocked from promotion while any of their quarantine rows have a non-terminal `review_status`. The reprocessing pipeline targets records whose quarantine issues have been resolved.

**Source migration:** `008_record_quarantine_table`

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `quarantine_id` | UUID | NOT NULL | `gen_random_uuid()` | Primary key |
| `batch_id` | UUID | NOT NULL | — | FK → `partner_eligibility_batch` (the delivery that produced the failure) |
| `eligibility_record_id` | UUID | NULL | — | FK → `canonical_eligibility_record` (SET NULL on delete; preserves quarantine even if the source record is deleted) |
| `partner_id` | TEXT | NOT NULL | — | Partner scope |
| `tenant_id` | TEXT | NOT NULL | — | Tenant scope |
| `org_id` | TEXT | NOT NULL | — | Organisation scope |
| `data_region` | TEXT | NOT NULL | — | Data residency region |
| `source_row_number` | INTEGER | NULL | — | Row number from the source file (> 0 if set) |
| `raw_record_reference` | TEXT | NOT NULL | — | Reference to the raw input record (e.g. source row ID or serialised key fields) for traceability back to the original delivery |
| `canonical_record_reference` | TEXT | NULL | — | Reference to the canonical record at the time of failure (JSON snapshot or key) |
| `error_code` | TEXT | NOT NULL | — | Machine-readable error code from the failed DQ rule (e.g. `REQUIRED_FIELD_MISSING`) |
| `error_severity` | `error_severity` ENUM | NOT NULL | — | Severity band: `sev_1` (critical) through `sev_5` (informational) |
| `failed_field` | TEXT | NULL | — | Name of the specific field that failed the rule |
| `failure_reason` | TEXT | NOT NULL | — | Human-readable description of why the rule failed |
| `requires_partner_action` | BOOLEAN | NOT NULL | `FALSE` | TRUE when the partner must supply corrected data before the issue can be resolved |
| `review_status` | `review_status` ENUM | NOT NULL | `'open'` | Lifecycle state: `open`, `in_review`, `partner_action_required`, `resolved`, `closed`, `ignored` |
| `reviewer` | TEXT | NULL | — | Username or identifier of the person reviewing this issue |
| `review_notes` | TEXT | NULL | — | Free-text notes from the reviewer |
| `created_at` | TIMESTAMPTZ | NOT NULL | `now()` | When the quarantine row was created |
| `resolved_at` | TIMESTAMPTZ | NULL | — | When the issue was resolved or closed (required when `review_status` is `resolved` or `closed`) |

**Key constraints:**
- `chk_quarantine_resolution` — `resolved_at` must be set when `review_status` is `resolved` or `closed`
- `chk_quarantine_source_row_positive` — `source_row_number` must be > 0 if provided

**Key indexes:**
- `(partner_id, review_status, created_at DESC)` — primary review queue query
- `(error_code, created_at DESC)` — error frequency analysis
- Partial index on `requires_partner_action = TRUE` — partner action queue

---

## Layer 4 — Serving

### `curated_eligibility_current`

**Purpose:** The serving layer that consumers read. Contains one row per unique employee per partner scope (`partner_id + tenant_id + partner_employee_id`). Only records that have passed the promotion gate (valid DQ status, no open quarantine, employee relationship type) are written here. The promotion functions upsert this table; the nightly sweep procedure updates rows when eligibility expires. Direct reads should go through the `v_current_active_eligibility` view, not this table.

**Source migration:** `006_current_curated_eligibility`

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `curated_eligibility_id` | UUID | NOT NULL | `gen_random_uuid()` | Primary key |
| `eligibility_record_id` | UUID | NOT NULL | — | FK → `canonical_eligibility_record` (the canonical record this row was last promoted from) |
| `partner_id` | TEXT | NOT NULL | — | Partner scope |
| `tenant_id` | TEXT | NOT NULL | — | Tenant scope |
| `org_id` | TEXT | NOT NULL | — | Organisation scope |
| `data_region` | TEXT | NOT NULL | — | Data residency region |
| `partner_employee_id` | TEXT | NOT NULL | — | Partner-assigned employee identifier |
| `partner_person_id` | TEXT | NULL | — | Person-level identifier (when provided) |
| `partner_member_id` | TEXT | NULL | — | Plan-level member identifier (when provided) |
| `eligibility_status` | `eligibility_status` ENUM | NOT NULL | — | Current eligibility state |
| `eligibility_start_date` | DATE | NOT NULL | — | Coverage start date |
| `eligibility_end_date` | DATE | NULL | — | Coverage end date (NULL = open-ended; updated by expiry sweep when the date passes) |
| `eligibility_group_code` | TEXT | NULL | — | Benefit group code |
| `benefit_plan_id` | TEXT | NULL | — | Benefit plan identifier |
| `person_relationship_type` | `person_relationship_type` ENUM | NOT NULL | `'employee'` | Only `employee` records are promoted to this table by the current serving model |
| `identity_match_policy_id` | TEXT | NOT NULL | — | Identifier of the matching policy version that generated this row |
| `dq_status` | `dq_status` ENUM | NOT NULL | — | Constrained to `valid` or `valid_with_warnings` only |
| `source_last_updated_at` | TIMESTAMPTZ | NOT NULL | — | Timestamp of the source event or change that last updated this row |
| `curated_at` | TIMESTAMPTZ | NOT NULL | `now()` | When this row was last written by the promotion pipeline |
| `created_at` | TIMESTAMPTZ | NOT NULL | `now()` | Row creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `now()` | Last modification timestamp (trigger-maintained) |

**Key constraints:**
- `chk_curated_only_valid_dq_status` — `dq_status` must be `valid` or `valid_with_warnings`
- `chk_curated_eligibility_date_range` — `eligibility_end_date` ≥ `eligibility_start_date`

**Key indexes:**
- `UNIQUE (partner_id, tenant_id, partner_employee_id)` — one current row per employee per partner scope
- Partial `UNIQUE (partner_id, tenant_id, partner_person_id) WHERE partner_person_id IS NOT NULL`
- Partial `(partner_id, tenant_id, eligibility_status) WHERE eligibility_status = 'active'` — primary serving query
- Partial `(eligibility_end_date) WHERE eligibility_end_date IS NOT NULL` — nightly expiry sweep target

> `is_currently_eligible` is **not stored** here. It is computed at query time by `v_current_active_eligibility` to avoid a staleness window between partner updates.

---

### `curated_eligibility_history`

**Purpose:** Bi-temporal SCD Type 2 history table for the serving layer. Every state change to `curated_eligibility_current` produces a new row here with `valid_from` / `valid_to` timestamps. The open row (`valid_to IS NULL`) represents the current state. Enables full temporal queries and provides an immutable audit trail independent of the canonical record. Partitioned by year on `valid_from`; archival is achieved by dropping a year partition.

**Source migration:** `007_curated_eligibility_history`

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `history_id` | UUID | NOT NULL | `gen_random_uuid()` | Part of composite PK |
| `curated_eligibility_id` | UUID | NOT NULL | — | References `curated_eligibility_current.curated_eligibility_id` (bare UUID, not FK, to avoid partition FK complexity) |
| `eligibility_record_id` | UUID | NOT NULL | — | FK → `canonical_eligibility_record` |
| `partner_id` | TEXT | NOT NULL | — | Partner scope |
| `tenant_id` | TEXT | NOT NULL | — | Tenant scope |
| `org_id` | TEXT | NOT NULL | — | Organisation scope |
| `data_region` | TEXT | NOT NULL | — | Data residency region |
| `partner_employee_id` | TEXT | NOT NULL | — | Employee identifier at time of write |
| `partner_person_id` | TEXT | NULL | — | Person identifier at time of write |
| `partner_member_id` | TEXT | NULL | — | Member identifier at time of write |
| `eligibility_status` | `eligibility_status` ENUM | NOT NULL | — | Eligibility status frozen at write time |
| `is_currently_eligible` | BOOLEAN | NOT NULL | — | Computed by `calculate_current_eligibility` and frozen at write time; answers "was this person eligible at `valid_from`?" |
| `eligibility_start_date` | DATE | NOT NULL | — | Coverage start date at time of write |
| `eligibility_end_date` | DATE | NULL | — | Coverage end date at time of write |
| `valid_from` | TIMESTAMPTZ | NOT NULL | — | Start of this history period (also the partition key) |
| `valid_to` | TIMESTAMPTZ | NULL | — | End of this history period (NULL = currently open / active state) |
| `change_reason` | TEXT | NULL | — | Why this history row was created (e.g. `canonical_promotion_update`) |
| `source_operation` | `source_operation` ENUM | NULL | — | The source operation that triggered this change |
| `record_hash` | TEXT | NOT NULL | — | Hash of the canonical record at time of promotion |
| `created_at` | TIMESTAMPTZ | NOT NULL | `now()` | Row creation timestamp |

**Primary key:** `(history_id, valid_from)` — partition key must be part of the PK.

**Partitions:**
- `curated_eligibility_history_2024` — 2024-01-01 to 2025-01-01
- `curated_eligibility_history_2025` — 2025-01-01 to 2026-01-01
- `curated_eligibility_history_2026` — 2026-01-01 to 2027-01-01
- `curated_eligibility_history_2027` — 2027-01-01 to 2028-01-01
- `curated_eligibility_history_default` — catch-all for out-of-range rows

**Key indexes:**
- `(curated_eligibility_id) WHERE valid_to IS NULL` — fast lookup of the open (current) history row
- `(partner_id, tenant_id, record_hash)` — change detection during promotion

---

## Layer 5 — Audit

### `promotion_audit`

**Purpose:** Immutable log of every promotion attempt. One row per attempt, whether successful, skipped, or failed. Both `batch_id` and `eligibility_record_id` are nullable with SET NULL on delete so audit records survive the deletion of source data. Used by the promotion gate for idempotency checks (if a record with the same hash was already successfully promoted, the next attempt is skipped).

**Source migration:** `012_promotion_functions`

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `promotion_attempt_id` | UUID | NOT NULL | `gen_random_uuid()` | Primary key |
| `batch_id` | UUID | NULL | — | FK → `partner_eligibility_batch` (SET NULL on delete) |
| `eligibility_record_id` | UUID | NULL | — | FK → `canonical_eligibility_record` (SET NULL on delete) |
| `partner_id` | TEXT | NULL | — | Partner scope snapshot (retained even if record is deleted) |
| `tenant_id` | TEXT | NULL | — | Tenant scope snapshot |
| `org_id` | TEXT | NULL | — | Organisation scope snapshot |
| `data_region` | TEXT | NULL | — | Data region snapshot |
| `source_event_id` | TEXT | NULL | — | Source event ID at time of attempt |
| `record_hash` | TEXT | NULL | — | Hash of the record at time of attempt |
| `previous_record_hash` | TEXT | NULL | — | Hash of the previous version at time of attempt |
| `promotion_status` | `promotion_status` ENUM | NOT NULL | — | Outcome: `promoted`, `skipped_duplicate`, `failed_validation`, `failed_system` |
| `failure_code` | TEXT | NULL | — | Machine-readable failure code when `promotion_status` is a failure |
| `failure_reason` | TEXT | NULL | — | Human-readable description of the failure |
| `curated_eligibility_current_id` | UUID | NULL | — | The `curated_eligibility_current` row written during a successful promotion |
| `curated_eligibility_history_id` | UUID | NULL | — | The `curated_eligibility_history` row written during a successful promotion |
| `attempted_at` | TIMESTAMPTZ | NOT NULL | `now()` | When the promotion attempt began |
| `promoted_at` | TIMESTAMPTZ | NULL | — | When the promotion completed successfully (NULL for non-promoted outcomes) |
| `created_at` | TIMESTAMPTZ | NOT NULL | `now()` | Row creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `now()` | Last modification timestamp |

**Key constraints:**
- `promotion_audit_failure_reason_required_chk` — non-promoted, non-skipped outcomes must include a `failure_reason`

**Key indexes:**
- Partial `(eligibility_record_id, record_hash) WHERE promotion_status = 'promoted'` — idempotency check
- BRIN `(attempted_at) pages_per_range=32` (migration 017) — space-efficient time-range queries on naturally ordered data
- Partial `(promoted_at DESC) WHERE promotion_status = 'promoted' AND promoted_at IS NOT NULL` — recent successful promotions

---

## Layer 6 — Partner Configuration

The seven partner configuration tables form the **configuration spine** of the pipeline. Ingestion, DQ evaluation, PII policy enforcement, and identity matching are all driven by data in these tables rather than hard-coded logic. Onboarding a new partner requires no code changes.

### `partner_contract`

**Purpose:** Root contract object. One active contract per `(partner_id, tenant_id, org_id, data_region)` at a time. Establishes the business, technical, and privacy ownership for a partner integration.

**Source migration:** `011_partner_contract_and_config`

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `partner_contract_id` | UUID | NOT NULL | `gen_random_uuid()` | Primary key |
| `partner_id` | TEXT | NOT NULL | — | Partner identifier |
| `tenant_id` | TEXT | NOT NULL | — | Tenant identifier |
| `org_id` | TEXT | NOT NULL | — | Organisation identifier |
| `data_region` | TEXT | NOT NULL | — | Data residency region |
| `contract_name` | TEXT | NOT NULL | — | Human-readable name for this contract |
| `contract_status` | `contract_status` ENUM | NOT NULL | `'draft'` | Lifecycle: `draft`, `active`, `deprecated`, `retired` |
| `effective_from` | DATE | NOT NULL | `CURRENT_DATE` | Date this contract takes effect |
| `effective_to` | DATE | NULL | — | Date this contract expires (NULL = no expiry) |
| `business_owner` | TEXT | NULL | — | Business owner contact |
| `technical_owner` | TEXT | NULL | — | Technical owner contact |
| `privacy_owner` | TEXT | NULL | — | Privacy/DPO contact |
| `partner_contact_name` | TEXT | NULL | — | Partner-side primary contact name |
| `partner_contact_email` | CITEXT | NULL | — | Partner-side primary contact email |
| `description` | TEXT | NULL | — | Free-text description of the contract |
| `created_at` | TIMESTAMPTZ | NOT NULL | `now()` | Row creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `now()` | Last modification timestamp (trigger-maintained) |

**Key indexes:**
- `UNIQUE (partner_id, tenant_id, org_id, data_region) WHERE contract_status = 'active'` — one active contract per scope

---

### `partner_schema_version`

**Purpose:** Describes how a partner's data is formatted for a specific schema version. Specifies file format, delivery capabilities, column bounds, and holds the raw JSON schema. Only one schema version per contract can be `active` at a time.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `partner_schema_version_id` | UUID | NOT NULL | `gen_random_uuid()` | Primary key |
| `partner_contract_id` | UUID | NOT NULL | — | FK → `partner_contract` (CASCADE DELETE) |
| `schema_version` | TEXT | NOT NULL | — | Version string (e.g. `v1.2.0`) |
| `schema_status` | `contract_status` ENUM | NOT NULL | `'draft'` | Lifecycle status |
| `delivery_type` | `delivery_type` ENUM | NOT NULL | — | Delivery mechanism this schema applies to |
| `file_format` | TEXT | NULL | — | File format (e.g. `csv`, `json`, `parquet`); required for `file`/`sftp` delivery types |
| `delimiter` | TEXT | NULL | — | Column delimiter for delimited file formats |
| `encoding` | TEXT | NULL | — | Character encoding (e.g. `UTF-8`) |
| `has_header` | BOOLEAN | NULL | — | Whether the file has a header row |
| `is_full_snapshot` | BOOLEAN | NOT NULL | `FALSE` | Schema produces full snapshots |
| `supports_incremental` | BOOLEAN | NOT NULL | `FALSE` | Schema supports incremental deliveries |
| `supports_deletes` | BOOLEAN | NOT NULL | `FALSE` | Schema can signal record deletions |
| `expected_min_columns` | INTEGER | NULL | — | Minimum expected column count |
| `expected_max_columns` | INTEGER | NULL | — | Maximum expected column count (must be ≥ `expected_min_columns`) |
| `effective_from` | DATE | NOT NULL | `CURRENT_DATE` | Date this schema version takes effect |
| `effective_to` | DATE | NULL | — | Date this schema version expires |
| `sample_file_uri` | TEXT | NULL | — | URI of a sample file for this schema version |
| `raw_schema` | JSONB | NULL | — | Full raw schema definition (e.g. JSON Schema, Avro schema) |
| `notes` | TEXT | NULL | — | Free-text notes about this version |
| `created_at` | TIMESTAMPTZ | NOT NULL | `now()` | Row creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `now()` | Last modification timestamp |

---

### `partner_field_mapping`

**Purpose:** Maps each field in the partner's source schema to a field in the canonical schema. Specifies transformation rules, validation config, PII classification, and role flags used by ingestion and the DQ evaluator.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `partner_field_mapping_id` | UUID | NOT NULL | `gen_random_uuid()` | Primary key |
| `partner_schema_version_id` | UUID | NOT NULL | — | FK → `partner_schema_version` (CASCADE DELETE) |
| `source_field_name` | TEXT | NOT NULL | — | Field name as it appears in the partner's delivery |
| `source_field_position` | INTEGER | NULL | — | Column position in the file (1-indexed); used for positional file formats |
| `canonical_field_name` | TEXT | NOT NULL | — | Corresponding column name in the canonical schema |
| `canonical_table_name` | TEXT | NOT NULL | `'canonical_eligibility_record'` | Target table: `canonical_eligibility_record` or `eligibility_person_pii` |
| `requirement_level` | `field_requirement_level` ENUM | NOT NULL | — | `required`, `conditional`, `optional`, or `prohibited` |
| `source_data_type` | TEXT | NULL | — | Data type in the source system |
| `canonical_data_type` | TEXT | NULL | — | Expected data type in the canonical schema |
| `default_value` | TEXT | NULL | — | Value to use when the source field is absent |
| `transform_config` | JSONB | NULL | — | Transformation rules (format conversion, value mapping, etc.) |
| `validation_config` | JSONB | NULL | — | Field-level validation rules applied during ingestion |
| `pii_classification` | TEXT | NULL | — | PII category label for this field (e.g. `email`, `health`) |
| `pii_policy_action` | `pii_policy_action` ENUM | NOT NULL | `'allow'` | What to do with this field's PII: `allow`, `allow_with_encryption`, `allow_with_tokenization`, `allow_with_masking`, `quarantine`, `reject` |
| `is_identity_field` | BOOLEAN | NOT NULL | `FALSE` | Used for identity matching |
| `is_eligibility_field` | BOOLEAN | NOT NULL | `FALSE` | Directly determines eligibility |
| `is_matching_field` | BOOLEAN | NOT NULL | `FALSE` | Used for record deduplication matching |
| `description` | TEXT | NULL | — | Free-text description of this mapping |
| `created_at` | TIMESTAMPTZ | NOT NULL | `now()` | Row creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `now()` | Last modification timestamp |

---

### `partner_data_quality_rule`

**Purpose:** Named DQ validation rules executed by `evaluate_canonical_record_dq`. Each rule specifies a type, severity (blocking vs. warning), which field and table it targets, type-specific parameters in `rule_config`, and the error code emitted when it fails.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `partner_data_quality_rule_id` | UUID | NOT NULL | `gen_random_uuid()` | Primary key |
| `partner_schema_version_id` | UUID | NOT NULL | — | FK → `partner_schema_version` (CASCADE DELETE) |
| `rule_name` | TEXT | NOT NULL | — | Human-readable rule name (unique per schema version) |
| `rule_type` | `validation_rule_type` ENUM | NOT NULL | — | `not_null`, `not_empty`, `regex`, `allowed_values`, `date_format`, `date_not_future`, `date_range`, `unique`, `unique_current_record`, `expression`, `pii_detection`, `custom` |
| `severity` | `validation_severity` ENUM | NOT NULL | — | `blocking` (prevents promotion), `warning` (allows promotion), `info` (logged only) |
| `canonical_field_name` | TEXT | NULL | — | Field targeted by this rule |
| `applies_to_table` | TEXT | NOT NULL | `'canonical_eligibility_record'` | Either `canonical_eligibility_record` or `eligibility_person_pii` |
| `rule_config` | JSONB | NOT NULL | `'{}'` | Type-specific parameters (e.g. `{"pattern": "^\\S+@\\S+"}` for `regex`, `{"values": ["active","inactive"]}` for `allowed_values`) |
| `error_code` | TEXT | NOT NULL | — | Machine-readable code emitted when the rule fails (e.g. `EMAIL_INVALID_FORMAT`) |
| `error_message` | TEXT | NOT NULL | — | Human-readable failure message |
| `is_active` | BOOLEAN | NOT NULL | `TRUE` | Inactive rules are skipped by the DQ evaluator |
| `execution_order` | INTEGER | NOT NULL | `100` | Rules are evaluated in ascending order; lower numbers run first |
| `created_at` | TIMESTAMPTZ | NOT NULL | `now()` | Row creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `now()` | Last modification timestamp |

---

### `partner_value_mapping`

**Purpose:** Lookup table for translating partner-specific coded values to canonical enum values. For example, mapping a partner's `"EMP"` to the canonical `"employee"` relationship type.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `partner_value_mapping_id` | UUID | NOT NULL | `gen_random_uuid()` | Primary key |
| `partner_schema_version_id` | UUID | NOT NULL | — | FK → `partner_schema_version` (CASCADE DELETE) |
| `canonical_field_name` | TEXT | NOT NULL | — | The canonical field whose values this table maps |
| `source_value` | TEXT | NOT NULL | — | The value as delivered by the partner |
| `canonical_value` | TEXT | NOT NULL | — | The corresponding canonical value |
| `is_active` | BOOLEAN | NOT NULL | `TRUE` | Inactive mappings are ignored during ingestion |
| `description` | TEXT | NULL | — | Description of this mapping |
| `created_at` | TIMESTAMPTZ | NOT NULL | `now()` | Row creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `now()` | Last modification timestamp |

**Key indexes:**
- `UNIQUE (partner_schema_version_id, canonical_field_name, source_value)` — one mapping per source value per field

---

### `partner_delivery_sla`

**Purpose:** SLA and alerting thresholds for a partner contract. Specifies delivery frequency, expected delivery time, maximum acceptable delays at each pipeline stage, and escalation timings (alert vs. page).

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `partner_delivery_sla_id` | UUID | NOT NULL | `gen_random_uuid()` | Primary key |
| `partner_contract_id` | UUID | NOT NULL | — | FK → `partner_contract` (CASCADE DELETE) |
| `delivery_frequency` | TEXT | NOT NULL | — | How often deliveries are expected (e.g. `daily`, `weekly`, `real_time`) |
| `expected_delivery_time` | TIME | NULL | — | Expected clock time of delivery (UTC) |
| `expected_timezone` | TEXT | NULL | — | Timezone context for `expected_delivery_time` |
| `max_delivery_delay_minutes` | INTEGER | NULL | — | Maximum acceptable minutes late for delivery |
| `max_processing_delay_minutes` | INTEGER | NULL | — | Maximum acceptable minutes for pipeline processing |
| `max_curation_delay_minutes` | INTEGER | NULL | — | Maximum acceptable minutes for promotion to curated serving layer |
| `attrition_update_sla_minutes` | INTEGER | NULL | — | SLA for reflecting member attrition (terminations) in the serving layer |
| `correction_sla_minutes` | INTEGER | NULL | — | SLA for delivering corrected data after a quarantine notification |
| `alert_after_minutes` | INTEGER | NULL | — | Minutes overdue before an alert is raised |
| `page_after_minutes` | INTEGER | NULL | — | Minutes overdue before an on-call page is raised |
| `is_active` | BOOLEAN | NOT NULL | `TRUE` | Only one active SLA per contract (partial unique index) |
| `created_at` | TIMESTAMPTZ | NOT NULL | `now()` | Row creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `now()` | Last modification timestamp |

---

### `partner_pii_policy`

**Purpose:** Per-field PII handling policy. Specifies what the platform is permitted to do with each PII field: encrypt, tokenize, mask, allow, quarantine, or reject. Also controls which processing layers (raw, canonical, curated, logs) are allowed to see the field.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `partner_pii_policy_id` | UUID | NOT NULL | `gen_random_uuid()` | Primary key |
| `partner_contract_id` | UUID | NOT NULL | — | FK → `partner_contract` (CASCADE DELETE) |
| `field_name` | TEXT | NOT NULL | — | Field this policy applies to (source or canonical field name) |
| `canonical_field_name` | TEXT | NULL | — | Corresponding canonical field name if different |
| `pii_classification` | TEXT | NOT NULL | — | PII category (e.g. `email`, `health`, `financial`, `biometric`) |
| `policy_action` | `pii_policy_action` ENUM | NOT NULL | — | What to do: `allow`, `allow_with_encryption`, `allow_with_tokenization`, `allow_with_masking`, `quarantine`, `reject` |
| `requires_encryption` | BOOLEAN | NOT NULL | `FALSE` | Field must be encrypted at rest |
| `requires_tokenization` | BOOLEAN | NOT NULL | `FALSE` | Field must be tokenized (one-way hash) |
| `requires_masking` | BOOLEAN | NOT NULL | `FALSE` | Field must be masked in output |
| `allowed_in_raw` | BOOLEAN | NOT NULL | `TRUE` | Field may appear in raw/staging storage |
| `allowed_in_canonical` | BOOLEAN | NOT NULL | `TRUE` | Field may appear in the canonical record layer |
| `allowed_in_curated` | BOOLEAN | NOT NULL | `FALSE` | Field may appear in the curated serving layer |
| `allowed_in_logs` | BOOLEAN | NOT NULL | `FALSE` | Field may appear in application or audit logs |
| `retention_policy_id` | TEXT | NULL | — | Reference to the retention policy for this field |
| `delete_after_days` | INTEGER | NULL | — | Maximum days this field may be retained (must be > 0) |
| `is_active` | BOOLEAN | NOT NULL | `TRUE` | Inactive policies are ignored |
| `created_at` | TIMESTAMPTZ | NOT NULL | `now()` | Row creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `now()` | Last modification timestamp |

---

### `partner_schema_change_log`

**Purpose:** Immutable audit trail of all schema version changes. Records who requested, reviewed, and approved each change, and whether a privacy review was required and completed. Rows are never updated after initial insert.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `partner_schema_change_log_id` | UUID | NOT NULL | `gen_random_uuid()` | Primary key |
| `partner_contract_id` | UUID | NOT NULL | — | FK → `partner_contract` (CASCADE DELETE) |
| `old_schema_version` | TEXT | NULL | — | Previous schema version (NULL for initial creation) |
| `new_schema_version` | TEXT | NOT NULL | — | New schema version (must differ from `old_schema_version`) |
| `change_type` | `schema_change_type` ENUM | NOT NULL | — | `backward_compatible`, `breaking`, `privacy_review_required`, `emergency` |
| `change_description` | TEXT | NOT NULL | — | Description of what changed |
| `requested_by` | TEXT | NULL | — | Who requested the change |
| `reviewed_by` | TEXT | NULL | — | Who reviewed the change |
| `approved_by` | TEXT | NULL | — | Who approved the change |
| `requested_at` | TIMESTAMPTZ | NOT NULL | `now()` | When the change was requested |
| `approved_at` | TIMESTAMPTZ | NULL | — | When the change was approved |
| `deployed_at` | TIMESTAMPTZ | NULL | — | When the change was deployed to production |
| `requires_privacy_review` | BOOLEAN | NOT NULL | `FALSE` | Whether a privacy/DPO review is required before deployment |
| `privacy_review_completed` | BOOLEAN | NOT NULL | `FALSE` | Whether the required privacy review has been completed |
| `created_at` | TIMESTAMPTZ | NOT NULL | `now()` | Row creation timestamp (no `updated_at`; this table is append-only) |

---

## Layer 7 — Identity Verification

The three identity verification tables record every attempt to confirm a person's eligibility using hashed token evidence. Raw PII is never stored in these tables.

### `identity_verification_request`

**Purpose:** Created when a consumer submits identity evidence to verify eligibility. Stores only hashed or masked versions of submitted PII. The entire verification pipeline — from submission to decision — is traceable through this row.

**Source migration:** `014_identity_verification_decision_tables`

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `identity_verification_request_id` | UUID | NOT NULL | `gen_random_uuid()` | Primary key |
| `partner_id` | TEXT | NOT NULL | — | Partner scope |
| `tenant_id` | TEXT | NOT NULL | — | Tenant scope |
| `org_id` | TEXT | NOT NULL | — | Organisation scope |
| `data_region` | TEXT | NOT NULL | — | Data residency region |
| `external_request_id` | TEXT | NULL | — | Caller-provided request ID (unique per scope when set) |
| `request_source` | TEXT | NOT NULL | — | Identifies the calling system or application |
| `requester_subject_id` | TEXT | NULL | — | Subject identifier of the entity making the request |
| `requester_account_id` | TEXT | NULL | — | Account identifier of the requester |
| `application_user_id` | TEXT | NULL | — | User ID within the calling application |
| `idempotency_key` | TEXT | NULL | — | Caller-provided key; if a matching request exists, the existing one is returned instead of creating a new one |
| `request_status` | `identity_verification_request_status` ENUM | NOT NULL | `'received'` | Lifecycle: `received` → `matching` → `matched` / `not_matched` / `ambiguous_match` → `decisioned` / `manual_review` / `failed` |
| `requested_at` | TIMESTAMPTZ | NOT NULL | `now()` | When the request was received |
| `matching_started_at` | TIMESTAMPTZ | NULL | — | When the matching engine began processing |
| `matching_completed_at` | TIMESTAMPTZ | NULL | — | When the matching engine finished |
| `decisioned_at` | TIMESTAMPTZ | NULL | — | When a decision was recorded |
| `failed_at` | TIMESTAMPTZ | NULL | — | When the request entered a failed state |
| `identity_match_policy_id` | TEXT | NOT NULL | `'policy_v1'` | Matching policy applied to this request |
| `identity_match_policy_version` | TEXT | NOT NULL | `'v1'` | Version of the matching policy |
| `decision_policy_id` | TEXT | NOT NULL | `'decision_policy_v1'` | Decision policy applied to this request |
| `decision_policy_version` | TEXT | NOT NULL | `'v1'` | Version of the decision policy |
| `submitted_normalized_email_hash` | TEXT | NULL | — | One-way hash of the submitted normalized email (weight: 45) |
| `submitted_phone_hash` | TEXT | NULL | — | One-way hash of the submitted phone number (weight: 30) |
| `submitted_dob_hash` | TEXT | NULL | — | One-way hash of the submitted date of birth (weight: 35) |
| `submitted_name_dob_hash` | TEXT | NULL | — | One-way hash of the submitted name + date of birth composite (weight: 80) |
| `submitted_partner_employee_id_hash` | TEXT | NULL | — | One-way hash of the submitted partner employee ID (weight: 60) |
| `submitted_partner_person_id_hash` | TEXT | NULL | — | One-way hash of the submitted partner person ID (weight: 60) |
| `submitted_partner_member_id_hash` | TEXT | NULL | — | One-way hash of the submitted partner member ID (weight: 60) |
| `submitted_masked_email` | TEXT | NULL | — | Partially masked email for human review display (not a hash) |
| `submitted_masked_phone` | TEXT | NULL | — | Partially masked phone for human review display |
| `submitted_last_four_ssn` | TEXT | NULL | — | Last four digits of SSN (4 digits only; used as supporting non-hash evidence) |
| `submitted_identity_token_count` | INTEGER | NOT NULL | `0` | Count of non-null hash tokens submitted; must be > 0 |
| `request_context` | JSONB | NOT NULL | `'{}'` | Safe request context (client app, flow, locale). Must not contain raw PII. |
| `request_metadata` | JSONB | NOT NULL | `'{}'` | Operational metadata (trace IDs, diagnostics). Must not contain raw PII. |
| `failure_reason` | TEXT | NULL | — | Reason for failure when `request_status = 'failed'` |
| `created_at` | TIMESTAMPTZ | NOT NULL | `now()` | Row creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `now()` | Last modification timestamp (trigger-maintained) |

---

### `identity_verification_match_candidate`

**Purpose:** One row per curated eligibility record that the matching engine identified as a potential match for a verification request. Captures the match mechanics (score, strategy, matched token types) and a safe snapshot of the eligibility state at match time for auditability.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `identity_verification_match_candidate_id` | UUID | NOT NULL | `gen_random_uuid()` | Primary key |
| `identity_verification_request_id` | UUID | NOT NULL | — | FK → `identity_verification_request` (CASCADE DELETE) |
| `partner_id` | TEXT | NOT NULL | — | Partner scope |
| `tenant_id` | TEXT | NOT NULL | — | Tenant scope |
| `org_id` | TEXT | NOT NULL | — | Organisation scope |
| `data_region` | TEXT | NOT NULL | — | Data residency region |
| `curated_eligibility_id` | UUID | NOT NULL | — | FK → `curated_eligibility_current`; the matched serving-layer record |
| `eligibility_record_id` | UUID | NOT NULL | — | FK → `canonical_eligibility_record` |
| `match_rank` | INTEGER | NOT NULL | — | Rank of this candidate (1 = best match; unique per request) |
| `match_score` | NUMERIC(5,2) | NOT NULL | — | Composite score 0–100; sum of matched token weights capped at 100 |
| `match_strategy` | `identity_match_strategy` ENUM | NOT NULL | — | How the match was made: `exact_token`, `composite_token`, `partner_identifier`, `eligibility_identifier`, `manual_review`, `fallback` |
| `match_candidate_status` | `identity_match_candidate_status` ENUM | NOT NULL | `'candidate'` | Outcome of this candidate: `candidate`, `selected`, `rejected`, `superseded`, `manual_review` |
| `matched_token_types` | TEXT[] | NULL | — | Array of `token_type` values that contributed to the match |
| `matched_identifier_types` | TEXT[] | NULL | — | Array of identifier types that contributed to the match |
| `match_reason` | TEXT | NULL | — | Human-readable explanation of why this record matched |
| `mismatch_reason` | TEXT | NULL | — | Why this candidate was not selected (for rejected candidates) |
| `eligibility_status` | `eligibility_status` ENUM | NOT NULL | — | Snapshot of `eligibility_status` at match time |
| `is_currently_eligible` | BOOLEAN | NOT NULL | — | Snapshot of computed eligibility at match time |
| `eligibility_start_date` | DATE | NOT NULL | — | Snapshot of coverage start date at match time |
| `eligibility_end_date` | DATE | NULL | — | Snapshot of coverage end date at match time |
| `dq_status` | `dq_status` ENUM | NOT NULL | — | Snapshot of DQ status at match time |
| `source_last_updated_at` | TIMESTAMPTZ | NOT NULL | — | Snapshot of when the curated record was last updated |
| `curated_at` | TIMESTAMPTZ | NOT NULL | — | Snapshot of when the curated record was last promoted |
| `candidate_snapshot` | JSONB | NOT NULL | `'{}'` | Safe JSON snapshot of eligibility fields for auditability. Must not contain PII. |
| `created_at` | TIMESTAMPTZ | NOT NULL | `now()` | Row creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `now()` | Last modification timestamp |

---

### `identity_verification_decision`

**Purpose:** The final, immutable decision for a verification request. One row per request (unique constraint enforced). CHECK constraints enforce state machine consistency at the database level.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `identity_verification_decision_id` | UUID | NOT NULL | `gen_random_uuid()` | Primary key |
| `identity_verification_request_id` | UUID | NOT NULL | — | FK → `identity_verification_request` (CASCADE DELETE); unique — one decision per request |
| `identity_verification_match_candidate_id` | UUID | NULL | — | FK → the candidate that was selected (SET NULL on delete) |
| `partner_id` | TEXT | NOT NULL | — | Partner scope |
| `tenant_id` | TEXT | NOT NULL | — | Tenant scope |
| `org_id` | TEXT | NOT NULL | — | Organisation scope |
| `data_region` | TEXT | NOT NULL | — | Data residency region |
| `curated_eligibility_id` | UUID | NULL | — | FK → `curated_eligibility_current` (required when `decision_status = 'approved'`) |
| `eligibility_record_id` | UUID | NULL | — | FK → `canonical_eligibility_record` |
| `decision_status` | `identity_verification_decision_status` ENUM | NOT NULL | — | `approved`, `denied`, `manual_review`, `failed` |
| `decision_reason_code` | TEXT | NOT NULL | — | Machine-readable reason code (e.g. `AUTO_APPROVED`, `NO_ELIGIBLE_MATCH`, `AMBIGUOUS_MATCH`) |
| `decision_reason` | TEXT | NULL | — | Human-readable decision reason |
| `is_eligible` | BOOLEAN | NOT NULL | — | Whether the person is eligible (TRUE only for `approved`) |
| `requires_manual_review` | BOOLEAN | NOT NULL | `FALSE` | TRUE only when `decision_status = 'manual_review'` |
| `confidence_score` | NUMERIC(5,2) | NULL | — | Confidence in the decision (0–100) |
| `decision_policy_id` | TEXT | NOT NULL | `'decision_policy_v1'` | Policy that produced this decision |
| `decision_policy_version` | TEXT | NOT NULL | `'v1'` | Policy version |
| `decision_rule_version` | TEXT | NOT NULL | `'v1'` | Rule version |
| `decision_evidence` | JSONB | NOT NULL | `'{}'` | Safe evidence used to support the decision (matched tokens, scores, rule IDs). Must not contain PII. |
| `decided_by` | TEXT | NOT NULL | `'system'` | Who or what made the decision (`system` for automated, a user ID for manual decisions) |
| `decided_at` | TIMESTAMPTZ | NOT NULL | `now()` | When the decision was made |
| `created_at` | TIMESTAMPTZ | NOT NULL | `now()` | Row creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `now()` | Last modification timestamp |

**State machine constraints (`chk_identity_verification_decision_status_consistency`):**

| `decision_status` | `is_eligible` | `requires_manual_review` | `curated_eligibility_id` |
|---|---|---|---|
| `approved` | TRUE | FALSE | NOT NULL |
| `denied` | FALSE | FALSE | any |
| `manual_review` | any | TRUE | any |
| `failed` | FALSE | any | any |

---

## Layer 8 — Reprocessing

### `reprocessing_job`

**Purpose:** Represents a request to re-run the promotion gate against a set of canonical records. Used when partner corrects previously quarantined data, when a DQ rule is relaxed after negotiation, or when a policy change means previously-blocked records should now be promoted.

**Source migration:** `016_reprocessing_backfill_functions`

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `reprocessing_job_id` | UUID | NOT NULL | `gen_random_uuid()` | Primary key |
| `partner_id` | TEXT | NOT NULL | — | Partner scope |
| `tenant_id` | TEXT | NOT NULL | — | Tenant scope |
| `org_id` | TEXT | NOT NULL | — | Organisation scope |
| `data_region` | TEXT | NOT NULL | — | Data residency region |
| `job_type` | `reprocessing_job_type` ENUM | NOT NULL | — | `batch` (all records from one batch), `partner` (all records for a partner scope), `resolved_quarantine` (records whose quarantine issues are resolved), `record_set` (explicit list of record IDs) |
| `job_status` | `reprocessing_job_status` ENUM | NOT NULL | `'queued'` | Lifecycle: `queued` → `running` → `completed` / `completed_with_failures` / `failed` / `cancelled` |
| `requested_by` | TEXT | NOT NULL | `current_user` | Who or what initiated the job |
| `reason` | TEXT | NOT NULL | — | Required free-text explanation for why reprocessing was triggered |
| `source_batch_id` | UUID | NULL | — | FK → `partner_eligibility_batch` (SET NULL on delete); required for `batch` job type |
| `filter_config` | JSONB | NOT NULL | `'{}'` | Additional filter parameters (e.g. `only_currently_valid_dq` for partner jobs) |
| `total_records` | INTEGER | NOT NULL | `0` | Total records included in this job |
| `queued_count` | INTEGER | NOT NULL | `0` | Records still awaiting processing |
| `processed_count` | INTEGER | NOT NULL | `0` | Records that have been processed (any terminal status) |
| `promoted_count` | INTEGER | NOT NULL | `0` | Records successfully promoted |
| `skipped_duplicate_count` | INTEGER | NOT NULL | `0` | Records skipped because they were already promoted with the same hash |
| `failed_validation_count` | INTEGER | NOT NULL | `0` | Records that failed the promotion gate |
| `failed_system_count` | INTEGER | NOT NULL | `0` | Records that failed due to a system error |
| `started_at` | TIMESTAMPTZ | NULL | — | When job execution began |
| `completed_at` | TIMESTAMPTZ | NULL | — | When job execution ended (required for terminal statuses) |
| `created_at` | TIMESTAMPTZ | NOT NULL | `now()` | Row creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `now()` | Last modification timestamp |

---

### `reprocessing_job_record`

**Purpose:** One row per canonical record in a reprocessing job. Links the job to the specific records being reprocessed and captures the outcome of each individual promotion attempt.

| Column | Type | Nullable | Default | Description |
|--------|------|----------|---------|-------------|
| `reprocessing_job_record_id` | UUID | NOT NULL | `gen_random_uuid()` | Primary key |
| `reprocessing_job_id` | UUID | NOT NULL | — | FK → `reprocessing_job` (CASCADE DELETE) |
| `batch_id` | UUID | NOT NULL | — | FK → `partner_eligibility_batch` (CASCADE DELETE); the original batch of this record |
| `eligibility_record_id` | UUID | NOT NULL | — | FK → `canonical_eligibility_record` (CASCADE DELETE) |
| `partner_id` | TEXT | NOT NULL | — | Partner scope (for RLS) |
| `tenant_id` | TEXT | NOT NULL | — | Tenant scope |
| `org_id` | TEXT | NOT NULL | — | Organisation scope |
| `data_region` | TEXT | NOT NULL | — | Data residency region |
| `record_status` | `reprocessing_record_status` ENUM | NOT NULL | `'queued'` | Per-record status: `queued`, `processing`, `promoted`, `skipped_duplicate`, `failed_validation`, `failed_system` |
| `promotion_attempt_id` | UUID | NULL | — | FK → `promotion_audit` (SET NULL on delete); the audit row from the promotion attempt |
| `promotion_status` | `promotion_status` ENUM | NULL | — | Outcome from the promotion attempt (copied from audit row) |
| `failure_code` | TEXT | NULL | — | Machine-readable failure code if promotion failed |
| `failure_reason` | TEXT | NULL | — | Human-readable failure reason (required for `failed_*` statuses) |
| `queued_at` | TIMESTAMPTZ | NOT NULL | `now()` | When this record was added to the job queue |
| `processed_at` | TIMESTAMPTZ | NULL | — | When processing completed (required for non-queued, non-processing statuses) |
| `created_at` | TIMESTAMPTZ | NOT NULL | `now()` | Row creation timestamp |
| `updated_at` | TIMESTAMPTZ | NOT NULL | `now()` | Last modification timestamp |

**Key constraints:**
- `UNIQUE (reprocessing_job_id, eligibility_record_id)` — no duplicate records per job

---

## ENUM Types Reference

| ENUM | Values | Used By |
|------|--------|---------|
| `delivery_type` | `file`, `sftp`, `api`, `event_stream`, `manual`, `other` | `partner_eligibility_batch`, `partner_schema_version` |
| `batch_status` | `received`, `processing`, `completed`, `failed`, `partially_processed` | `partner_eligibility_batch` |
| `eligibility_status` | `active`, `inactive`, `terminated`, `on_leave`, `expired`, `pending`, `unknown` | `canonical_eligibility_record`, `curated_eligibility_current`, `curated_eligibility_history` |
| `source_operation` | `insert`, `update`, `delete`, `snapshot` | `canonical_eligibility_record`, `curated_eligibility_history` |
| `person_relationship_type` | `employee`, `spouse`, `dependent`, `domestic_partner`, `other` | `canonical_eligibility_record`, `curated_eligibility_current`, `curated_eligibility_history` |
| `dq_status` | `pending_review`, `valid`, `valid_with_warnings`, `quarantined`, `rejected` | `canonical_eligibility_record`, `curated_eligibility_current`, `identity_verification_match_candidate` |
| `error_severity` | `sev_1`, `sev_2`, `sev_3`, `sev_4`, `sev_5` | `eligibility_quarantine` |
| `review_status` | `open`, `in_review`, `partner_action_required`, `resolved`, `closed`, `ignored` | `eligibility_quarantine` |
| `token_type` | `email`, `phone`, `dob`, `name_dob`, `partner_employee_id`, `partner_person_id`, `partner_member_id` | `eligibility_identity_token` |
| `tokenization_status` | `pending`, `completed`, `failed`, `not_required` | `canonical_eligibility_record` |
| `encryption_status` | `not_required`, `pending`, `completed`, `failed` | `canonical_eligibility_record`, `eligibility_person_pii` |
| `contract_status` | `draft`, `active`, `deprecated`, `retired` | `partner_contract`, `partner_schema_version` |
| `field_requirement_level` | `required`, `conditional`, `optional`, `prohibited` | `partner_field_mapping` |
| `validation_rule_type` | `not_null`, `not_empty`, `regex`, `allowed_values`, `date_format`, `date_not_future`, `date_range`, `unique`, `unique_current_record`, `expression`, `pii_detection`, `custom` | `partner_data_quality_rule` |
| `validation_severity` | `blocking`, `warning`, `info` | `partner_data_quality_rule` |
| `pii_policy_action` | `allow`, `allow_with_encryption`, `allow_with_tokenization`, `allow_with_masking`, `quarantine`, `reject` | `partner_field_mapping`, `partner_pii_policy` |
| `schema_change_type` | `backward_compatible`, `breaking`, `privacy_review_required`, `emergency` | `partner_schema_change_log` |
| `promotion_status` | `promoted`, `skipped_duplicate`, `failed_validation`, `failed_system` | `promotion_audit`, `reprocessing_job_record` |
| `identity_verification_request_status` | `received`, `matching`, `matched`, `not_matched`, `ambiguous_match`, `decisioned`, `manual_review`, `failed` | `identity_verification_request` |
| `identity_match_strategy` | `exact_token`, `composite_token`, `partner_identifier`, `eligibility_identifier`, `manual_review`, `fallback` | `identity_verification_match_candidate` |
| `identity_match_candidate_status` | `candidate`, `selected`, `rejected`, `superseded`, `manual_review` | `identity_verification_match_candidate` |
| `identity_verification_decision_status` | `approved`, `denied`, `manual_review`, `failed` | `identity_verification_decision` |
| `reprocessing_job_type` | `batch`, `partner`, `resolved_quarantine`, `record_set` | `reprocessing_job` |
| `reprocessing_job_status` | `queued`, `running`, `completed`, `completed_with_failures`, `failed`, `cancelled` | `reprocessing_job` |
| `reprocessing_record_status` | `queued`, `processing`, `promoted`, `skipped_duplicate`, `failed_validation`, `failed_system` | `reprocessing_job_record` |

---

## Diagnostic Views Reference

| View | Source Migration | Description |
|------|-----------------|-------------|
| `v_batch_quality_summary` | 010 | Wraps `partner_eligibility_batch`; adds computed `accepted_record_percentage` = (valid + valid_with_warnings) / total × 100 |
| `v_current_active_eligibility` | 010 (upgraded in 012) | Filters `curated_eligibility_current` to currently active records; computes `is_currently_eligible` via `calculate_current_eligibility()`. **Primary consumer-facing serving surface** — always use this instead of querying the base table directly |
| `v_open_quarantine_issues` | 010 | Filters `eligibility_quarantine` to `review_status IN ('open', 'in_review', 'partner_action_required')`. The review queue surface |
| `v_duplicate_pii_email` | 018 | Surfaces active curated records within the same partner scope sharing a `normalized_primary_email`; signals duplicate entries or shared mailboxes |
| `v_email_format_errors` | 018 | Surfaces canonical records where `primary_email` exists but fails basic RFC 5321 format check; these records cannot produce a valid email hash token |

---

## Key Foreign Key Relationships

```
partner_eligibility_batch
  └──< canonical_eligibility_record          (batch_id)
         ├── eligibility_person_pii           (1:1, CASCADE)
         ├──< eligibility_identity_token      (N:1, CASCADE)
         ├──< eligibility_quarantine          (N:1, SET NULL on canonical delete)
         ├── curated_eligibility_current      (eligibility_record_id)
         │     └──< curated_eligibility_history (eligibility_record_id)
         └──< promotion_audit                 (SET NULL on delete)

partner_contract
  ├── partner_schema_version
  │     ├──< partner_field_mapping
  │     ├──< partner_data_quality_rule
  │     └──< partner_value_mapping
  ├── partner_delivery_sla
  ├──< partner_pii_policy
  └──< partner_schema_change_log

identity_verification_request
  ├──< identity_verification_match_candidate  (CASCADE)
  └── identity_verification_decision          (1:1, CASCADE)

reprocessing_job
  └──< reprocessing_job_record                (CASCADE)
```
