-- seed_demo.sql
-- Walks data through the full pipeline:
--   partner config → batch ingestion → DQ evaluation → promotion → identity verification
--
-- Prerequisites: all migrations 001–018 applied; pgcrypto extension enabled.
-- Run as: psql -d <db> -f seed_demo.sql

BEGIN;

SET ROLE eligibility_admin;

DO $$
DECLARE
    -- Config IDs
    v_contract_id            UUID;
    v_schema_version_id      UUID;

    -- Batch IDs
    v_batch1_id              UUID;
    v_batch2_id              UUID;

    -- Canonical record IDs (Batch 1)
    v_alice_id               UUID;
    v_bob_id                 UUID;
    v_carol_id               UUID;
    v_dave_id                UUID;
    v_eve_id                 UUID;

    -- Canonical record ID (Batch 2)
    v_frank_id               UUID;

    -- Working variables
    v_dq_result              RECORD;
    v_promote_result         RECORD;
    v_idv_result             RECORD;

BEGIN

    -- ─────────────────────────────────────────────────────────────────────────
    -- SECTION 1 — Partner Contract & Configuration
    -- ─────────────────────────────────────────────────────────────────────────
    RAISE NOTICE '=== SECTION 1: Partner Configuration ===';

    INSERT INTO eligibility.partner_contract (
        partner_id, tenant_id, org_id, data_region,
        contract_name, contract_status,
        business_owner, technical_owner,
        partner_contact_email,
        description
    ) VALUES (
        'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
        'ACME Corp Benefits Eligibility',
        'active',
        'jane.smith@acme-corp.com',
        'tech.lead@acme-corp.com',
        'benefits@acme-corp.com',
        'Demo seed: monthly eligibility feed for ACME Corp'
    )
    RETURNING partner_contract_id INTO v_contract_id;

    RAISE NOTICE 'Contract created: %', v_contract_id;

    INSERT INTO eligibility.partner_schema_version (
        partner_contract_id,
        schema_version, schema_status,
        delivery_type, file_format, delimiter, encoding, has_header,
        is_full_snapshot, supports_incremental, supports_deletes,
        expected_min_columns, expected_max_columns
    ) VALUES (
        v_contract_id,
        'v1', 'active',
        'file', 'csv', ',', 'UTF-8', TRUE,
        TRUE, TRUE, FALSE,
        9, 12
    )
    RETURNING partner_schema_version_id INTO v_schema_version_id;

    RAISE NOTICE 'Schema version v1 created: %', v_schema_version_id;

    -- Field mappings
    INSERT INTO eligibility.partner_field_mapping (
        partner_schema_version_id,
        source_field_name, source_field_position,
        canonical_field_name, canonical_table_name,
        requirement_level, source_data_type, canonical_data_type,
        is_identity_field, is_eligibility_field
    ) VALUES
        (v_schema_version_id, 'employee_id',  1, 'partner_employee_id',    'canonical_eligibility_record', 'required', 'string', 'text',   TRUE,  FALSE),
        (v_schema_version_id, 'emp_status',   2, 'employment_status',      'canonical_eligibility_record', 'required', 'string', 'text',   FALSE, FALSE),
        (v_schema_version_id, 'emp_type',     3, 'employment_type',        'canonical_eligibility_record', 'required', 'string', 'text',   FALSE, FALSE),
        (v_schema_version_id, 'elig_status',  4, 'eligibility_status',     'canonical_eligibility_record', 'required', 'string', 'text',   FALSE, TRUE),
        (v_schema_version_id, 'elig_start',   5, 'eligibility_start_date', 'canonical_eligibility_record', 'required', 'date',   'date',   FALSE, TRUE),
        (v_schema_version_id, 'first_name',   6, 'first_name',             'eligibility_person_pii',       'required', 'string', 'text',   FALSE, FALSE),
        (v_schema_version_id, 'last_name',    7, 'last_name',              'eligibility_person_pii',       'required', 'string', 'text',   FALSE, FALSE),
        (v_schema_version_id, 'email',        8, 'primary_email',          'eligibility_person_pii',       'optional', 'string', 'citext', TRUE,  FALSE),
        (v_schema_version_id, 'dob',          9, 'date_of_birth',          'eligibility_person_pii',       'optional', 'date',   'date',   TRUE,  FALSE);

    -- Value mappings (source → canonical)
    INSERT INTO eligibility.partner_value_mapping (
        partner_schema_version_id, canonical_field_name, source_value, canonical_value
    ) VALUES
        (v_schema_version_id, 'employment_status', 'ACTIVE',      'active'),
        (v_schema_version_id, 'employment_status', 'TERMINATED',  'terminated'),
        (v_schema_version_id, 'eligibility_status','ELIGIBLE',    'active'),
        (v_schema_version_id, 'eligibility_status','INELIGIBLE',  'inactive');

    -- DQ Rules (evaluated in execution_order; all reference schema version v1)
    --
    --  Rule 1 — BLOCKING: employment_type must be present
    --    Catches Eve Davis (HR system sent NULL).
    --
    --  Rule 2 — WARNING: employment_type must be a standard class
    --    Catches Bob Chen (TEMP); alerts ops without blocking promotion.
    --
    --  Rule 3 — WARNING: primary_email must match a basic RFC-5322 shape
    --    Catches Dave Williams (missing @); promotion still allowed.
    --
    --  Rule 4 — BLOCKING: normalized_primary_email must be unique in curated layer
    --    Catches Frank Wilson in Batch 2 (re-uses Alice's alice@acme.com).
    INSERT INTO eligibility.partner_data_quality_rule (
        partner_schema_version_id,
        rule_name, rule_type, severity,
        canonical_field_name, applies_to_table,
        rule_config, error_code, error_message,
        is_active, execution_order
    ) VALUES

        (v_schema_version_id,
         'employment_type_required',
         'not_null', 'blocking',
         'employment_type', 'canonical_eligibility_record',
         '{}',
         'DQ_EMPLOYMENT_TYPE_REQUIRED',
         'employment_type must not be null — HR system failed to classify worker type',
         TRUE, 10),

        (v_schema_version_id,
         'employment_type_standard',
         'allowed_values', 'warning',
         'employment_type', 'canonical_eligibility_record',
         '{"values": ["FT", "PT"]}',
         'DQ_EMPLOYMENT_TYPE_NONSTANDARD',
         'employment_type is non-standard (TEMP/CONTRACT) — benefits review may be required',
         TRUE, 20),

        (v_schema_version_id,
         'primary_email_format',
         'regex', 'warning',
         'primary_email', 'eligibility_person_pii',
         '{"pattern": "^\\S+@\\S+\\.\\S+$"}',
         'DQ_EMAIL_FORMAT_INVALID',
         'primary_email does not match expected format — downstream notification delivery at risk',
         TRUE, 30),

        (v_schema_version_id,
         'email_uniqueness',
         'unique_current_record', 'blocking',
         'normalized_primary_email', 'eligibility_person_pii',
         '{}',
         'DQ_DUPLICATE_EMAIL',
         'normalized_primary_email already exists in a different active curated record',
         TRUE, 40);

    -- Delivery SLA
    INSERT INTO eligibility.partner_delivery_sla (
        partner_contract_id,
        delivery_frequency, expected_delivery_time, expected_timezone,
        max_delivery_delay_minutes, max_processing_delay_minutes,
        alert_after_minutes, page_after_minutes
    ) VALUES (
        v_contract_id,
        'monthly', '02:00', 'America/New_York',
        60, 120,
        90, 180
    );

    -- PII policy
    INSERT INTO eligibility.partner_pii_policy (
        partner_contract_id,
        field_name, canonical_field_name,
        pii_classification, policy_action,
        requires_encryption,
        allowed_in_raw, allowed_in_canonical, allowed_in_curated, allowed_in_logs
    ) VALUES
        (v_contract_id,
         'primary_email', 'primary_email',
         'contact_pii', 'allow_with_encryption',
         TRUE, TRUE, TRUE, FALSE, FALSE),

        (v_contract_id,
         'date_of_birth', 'date_of_birth',
         'sensitive_pii', 'allow_with_encryption',
         TRUE, TRUE, FALSE, FALSE, FALSE),

        (v_contract_id,
         'last_four_ssn', 'last_four_ssn',
         'government_id', 'allow_with_tokenization',
         TRUE, TRUE, FALSE, FALSE, FALSE);

    RAISE NOTICE 'Partner configuration complete (contract=%, schema=%)',
        v_contract_id, v_schema_version_id;


    -- ─────────────────────────────────────────────────────────────────────────
    -- SECTION 2 — Batch 1 Ingestion (5 records, mixed DQ outcomes)
    -- ─────────────────────────────────────────────────────────────────────────
    RAISE NOTICE '';
    RAISE NOTICE '=== SECTION 2: Batch 1 Ingestion (5 records) ===';

    INSERT INTO eligibility.partner_eligibility_batch (
        partner_id, tenant_id, org_id, data_region,
        source_file_name, source_file_uri,
        source_file_checksum, source_schema_version,
        delivery_type,
        is_full_snapshot, snapshot_as_of_at,
        record_count, batch_status
    ) VALUES (
        'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
        'acme_elig_2026_01.csv',
        's3://acme-corp-eligibility/2026/01/acme_elig_2026_01.csv',
        encode(digest('acme-corp|batch1|2026-01-01', 'sha256'), 'hex'),
        'v1',
        'file',
        TRUE, '2026-01-01 00:00:00+00',
        5, 'processing'
    )
    RETURNING batch_id INTO v_batch1_id;

    RAISE NOTICE 'Batch 1 created: %', v_batch1_id;

    -- ── Alice Johnson (emp-001) ─────────────────────────────────────────────
    -- Expected DQ outcome: VALID (FT, well-formed email, unique)
    INSERT INTO eligibility.canonical_eligibility_record (
        batch_id, partner_id, tenant_id, org_id, data_region,
        source_row_number, source_record_id, source_schema_version,
        source_operation, is_full_snapshot, snapshot_as_of_at,
        partner_employee_id,
        employment_status, employment_type,
        eligibility_status, eligibility_start_date,
        record_hash
    ) VALUES (
        v_batch1_id, 'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
        1, 'emp-001', 'v1',
        'snapshot', TRUE, '2026-01-01 00:00:00+00',
        'emp-001',
        'active', 'FT',
        'active', '2020-04-01',
        encode(digest('emp-001|acme-corp|active|2020-04-01', 'sha256'), 'hex')
    )
    RETURNING eligibility_record_id INTO v_alice_id;

    INSERT INTO eligibility.eligibility_person_pii (
        eligibility_record_id, partner_id, tenant_id, org_id, data_region,
        first_name, last_name, date_of_birth,
        primary_email, normalized_primary_email
    ) VALUES (
        v_alice_id, 'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
        'Alice', 'Johnson', '1985-06-14',
        'alice@acme.com', 'alice@acme.com'
    );

    -- ── Bob Chen (emp-002) ──────────────────────────────────────────────────
    -- Expected DQ outcome: VALID_WITH_WARNINGS
    --   Rule 2 (employment_type_standard) fires: TEMP not in allowed ['FT','PT']
    INSERT INTO eligibility.canonical_eligibility_record (
        batch_id, partner_id, tenant_id, org_id, data_region,
        source_row_number, source_record_id, source_schema_version,
        source_operation, is_full_snapshot, snapshot_as_of_at,
        partner_employee_id,
        employment_status, employment_type,
        eligibility_status, eligibility_start_date,
        record_hash
    ) VALUES (
        v_batch1_id, 'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
        2, 'emp-002', 'v1',
        'snapshot', TRUE, '2026-01-01 00:00:00+00',
        'emp-002',
        'active', 'TEMP',
        'active', '2025-10-15',
        encode(digest('emp-002|acme-corp|active|2025-10-15', 'sha256'), 'hex')
    )
    RETURNING eligibility_record_id INTO v_bob_id;

    INSERT INTO eligibility.eligibility_person_pii (
        eligibility_record_id, partner_id, tenant_id, org_id, data_region,
        first_name, last_name, date_of_birth,
        primary_email, normalized_primary_email
    ) VALUES (
        v_bob_id, 'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
        'Bob', 'Chen', '1990-03-22',
        'bob@acme.com', 'bob@acme.com'
    );

    -- ── Carol Rodriguez (emp-003) ───────────────────────────────────────────
    -- Expected DQ outcome: VALID (FT, well-formed email, unique)
    INSERT INTO eligibility.canonical_eligibility_record (
        batch_id, partner_id, tenant_id, org_id, data_region,
        source_row_number, source_record_id, source_schema_version,
        source_operation, is_full_snapshot, snapshot_as_of_at,
        partner_employee_id,
        employment_status, employment_type,
        eligibility_status, eligibility_start_date,
        record_hash
    ) VALUES (
        v_batch1_id, 'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
        3, 'emp-003', 'v1',
        'snapshot', TRUE, '2026-01-01 00:00:00+00',
        'emp-003',
        'active', 'FT',
        'active', '2018-07-30',
        encode(digest('emp-003|acme-corp|active|2018-07-30', 'sha256'), 'hex')
    )
    RETURNING eligibility_record_id INTO v_carol_id;

    INSERT INTO eligibility.eligibility_person_pii (
        eligibility_record_id, partner_id, tenant_id, org_id, data_region,
        first_name, last_name, date_of_birth,
        primary_email, normalized_primary_email
    ) VALUES (
        v_carol_id, 'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
        'Carol', 'Rodriguez', '1978-11-05',
        'carol@acme.com', 'carol@acme.com'
    );

    -- ── Dave Williams (emp-004) ─────────────────────────────────────────────
    -- Expected DQ outcome: VALID_WITH_WARNINGS
    --   Rule 3 (primary_email_format) fires: 'dave.at.acme.com' has no @
    --   normalized_primary_email is NULL (ingestion layer couldn't normalize)
    --   so Rule 4 (email_uniqueness) short-circuits to TRUE (NULL field → pass)
    INSERT INTO eligibility.canonical_eligibility_record (
        batch_id, partner_id, tenant_id, org_id, data_region,
        source_row_number, source_record_id, source_schema_version,
        source_operation, is_full_snapshot, snapshot_as_of_at,
        partner_employee_id,
        employment_status, employment_type,
        eligibility_status, eligibility_start_date,
        record_hash
    ) VALUES (
        v_batch1_id, 'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
        4, 'emp-004', 'v1',
        'snapshot', TRUE, '2026-01-01 00:00:00+00',
        'emp-004',
        'active', 'FT',
        'active', '2022-01-10',
        encode(digest('emp-004|acme-corp|active|2022-01-10', 'sha256'), 'hex')
    )
    RETURNING eligibility_record_id INTO v_dave_id;

    INSERT INTO eligibility.eligibility_person_pii (
        eligibility_record_id, partner_id, tenant_id, org_id, data_region,
        first_name, last_name,
        primary_email,
        normalized_primary_email   -- NULL: ingestion could not parse the malformed email
    ) VALUES (
        v_dave_id, 'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
        'Dave', 'Williams',
        'dave.at.acme.com',        -- malformed: missing '@' symbol
        NULL
    );

    -- ── Eve Davis (emp-005) ─────────────────────────────────────────────────
    -- Expected DQ outcome: QUARANTINED
    --   Rule 1 (employment_type_required) fires: NULL → BLOCKING → quarantined
    --   Rule 2 (employment_type_standard) also fires: NULL fails allowed_values → WARNING
    --   dq_score = 100 - (1×20) - (1×5) = 75; requires_manual_review = TRUE
    INSERT INTO eligibility.canonical_eligibility_record (
        batch_id, partner_id, tenant_id, org_id, data_region,
        source_row_number, source_record_id, source_schema_version,
        source_operation, is_full_snapshot, snapshot_as_of_at,
        partner_employee_id,
        employment_status,
        employment_type,           -- NULL: HR system did not populate this field
        eligibility_status, eligibility_start_date,
        record_hash
    ) VALUES (
        v_batch1_id, 'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
        5, 'emp-005', 'v1',
        'snapshot', TRUE, '2026-01-01 00:00:00+00',
        'emp-005',
        'active',
        NULL,
        'active', '2024-02-20',
        encode(digest('emp-005|acme-corp|active|2024-02-20', 'sha256'), 'hex')
    )
    RETURNING eligibility_record_id INTO v_eve_id;

    INSERT INTO eligibility.eligibility_person_pii (
        eligibility_record_id, partner_id, tenant_id, org_id, data_region,
        first_name, last_name, date_of_birth,
        primary_email, normalized_primary_email
    ) VALUES (
        v_eve_id, 'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
        'Eve', 'Davis', '2001-08-17',
        'eve@acme.com', 'eve@acme.com'
    );

    RAISE NOTICE 'Batch 1 records inserted: alice=%, bob=%, carol=%, dave=%, eve=%',
        v_alice_id, v_bob_id, v_carol_id, v_dave_id, v_eve_id;


    -- ─────────────────────────────────────────────────────────────────────────
    -- SECTION 3 — DQ Evaluation: Batch 1
    -- Must run before promote_batch; promotion gate rejects dq_status='pending_review'
    -- ─────────────────────────────────────────────────────────────────────────
    RAISE NOTICE '';
    RAISE NOTICE '=== SECTION 3: DQ Evaluation — Batch 1 ===';

    SELECT * INTO v_dq_result
    FROM eligibility.evaluate_batch_dq(v_batch1_id);

    RAISE NOTICE 'Batch 1 DQ summary: total=%, valid=%, warnings=%, quarantined=%',
        v_dq_result.total_evaluated,
        v_dq_result.valid_count,
        v_dq_result.valid_with_warnings_count,
        v_dq_result.quarantined_count;
    -- Expected: total=5, valid=2 (Alice, Carol), warnings=2 (Bob, Dave), quarantined=1 (Eve)


    -- ─────────────────────────────────────────────────────────────────────────
    -- SECTION 4 — Promotion: Batch 1
    -- Eve (quarantined) is skipped; Alice, Bob, Carol, Dave are promoted.
    -- ─────────────────────────────────────────────────────────────────────────
    RAISE NOTICE '';
    RAISE NOTICE '=== SECTION 4: Promotion — Batch 1 ===';

    SELECT * INTO v_promote_result
    FROM eligibility.promote_batch(v_batch1_id);

    RAISE NOTICE 'Batch 1 promotion: total=%, promoted=%, skipped_duplicate=%, failed_validation=%, failed_system=%',
        v_promote_result.total_records,
        v_promote_result.promoted_count,
        v_promote_result.skipped_duplicate_count,
        v_promote_result.failed_validation_count,
        v_promote_result.failed_system_count;
    -- Expected: promoted=4, failed_validation=1 (Eve — DQ_STATUS_NOT_PROMOTABLE)


    -- ─────────────────────────────────────────────────────────────────────────
    -- SECTION 5 — Identity Tokens
    -- Inserted after promotion so tokens reference records that exist in curated.
    -- ─────────────────────────────────────────────────────────────────────────
    RAISE NOTICE '';
    RAISE NOTICE '=== SECTION 5: Identity Tokens ===';

    -- Alice: email (weight 45) + name_dob (weight 80) + employee_id (weight 60)
    --   Total capped at 100 → auto-approve threshold (95) is met
    INSERT INTO eligibility.eligibility_identity_token (
        eligibility_record_id, partner_id, tenant_id, org_id, data_region,
        token_type, token_value
    ) VALUES
        (v_alice_id, 'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
         'normalized_email_hash',
         encode(digest(lower(trim('alice@acme.com')), 'sha256'), 'hex')),

        (v_alice_id, 'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
         'name_dob_hash',
         encode(digest('alice|johnson|1985-06-14', 'sha256'), 'hex')),

        (v_alice_id, 'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
         'partner_employee_id_hash',
         encode(digest('emp-001', 'sha256'), 'hex'));

    -- Bob: email + employee_id
    INSERT INTO eligibility.eligibility_identity_token (
        eligibility_record_id, partner_id, tenant_id, org_id, data_region,
        token_type, token_value
    ) VALUES
        (v_bob_id, 'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
         'normalized_email_hash',
         encode(digest(lower(trim('bob@acme.com')), 'sha256'), 'hex')),

        (v_bob_id, 'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
         'partner_employee_id_hash',
         encode(digest('emp-002', 'sha256'), 'hex'));

    -- Carol: email + employee_id
    INSERT INTO eligibility.eligibility_identity_token (
        eligibility_record_id, partner_id, tenant_id, org_id, data_region,
        token_type, token_value
    ) VALUES
        (v_carol_id, 'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
         'normalized_email_hash',
         encode(digest(lower(trim('carol@acme.com')), 'sha256'), 'hex')),

        (v_carol_id, 'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
         'partner_employee_id_hash',
         encode(digest('emp-003', 'sha256'), 'hex'));

    RAISE NOTICE 'Identity tokens inserted for Alice, Bob, Carol.';


    -- ─────────────────────────────────────────────────────────────────────────
    -- SECTION 6 — Batch 2 Ingestion: Frank Wilson (duplicate email)
    -- ─────────────────────────────────────────────────────────────────────────
    RAISE NOTICE '';
    RAISE NOTICE '=== SECTION 6: Batch 2 Ingestion (1 record — duplicate email) ===';

    INSERT INTO eligibility.partner_eligibility_batch (
        partner_id, tenant_id, org_id, data_region,
        source_file_name, source_file_uri,
        source_file_checksum, source_schema_version,
        delivery_type,
        is_full_snapshot, snapshot_as_of_at,
        record_count, batch_status
    ) VALUES (
        'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
        'acme_elig_delta_2026_01_15.csv',
        's3://acme-corp-eligibility/2026/01/acme_elig_delta_2026_01_15.csv',
        encode(digest('acme-corp|batch2|2026-01-15', 'sha256'), 'hex'),
        'v1',
        'file',
        FALSE, NULL,   -- incremental delta; not a full snapshot
        1, 'processing'
    )
    RETURNING batch_id INTO v_batch2_id;

    RAISE NOTICE 'Batch 2 created: %', v_batch2_id;

    -- ── Frank Wilson (emp-006) ──────────────────────────────────────────────
    -- Expected DQ outcome: QUARANTINED
    --   Rule 4 (email_uniqueness) fires: normalized_primary_email='alice@acme.com'
    --   already exists in curated_eligibility_current for Alice (emp-001).
    INSERT INTO eligibility.canonical_eligibility_record (
        batch_id, partner_id, tenant_id, org_id, data_region,
        source_row_number, source_record_id, source_schema_version,
        source_operation, is_full_snapshot, snapshot_as_of_at,
        partner_employee_id,
        employment_status, employment_type,
        eligibility_status, eligibility_start_date,
        record_hash
    ) VALUES (
        v_batch2_id, 'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
        1, 'emp-006', 'v1',
        'insert', FALSE, NULL,
        'emp-006',
        'active', 'FT',
        'active', '2026-01-10',
        encode(digest('emp-006|acme-corp|active|2026-01-10', 'sha256'), 'hex')
    )
    RETURNING eligibility_record_id INTO v_frank_id;

    INSERT INTO eligibility.eligibility_person_pii (
        eligibility_record_id, partner_id, tenant_id, org_id, data_region,
        first_name, last_name, date_of_birth,
        primary_email,
        normalized_primary_email   -- duplicate of Alice's normalized email
    ) VALUES (
        v_frank_id, 'acme-corp', 'tenant-main', 'org-us', 'us-east-1',
        'Frank', 'Wilson', '1995-04-30',
        'alice@acme.com',
        'alice@acme.com'
    );

    RAISE NOTICE 'Batch 2 record inserted: frank=%', v_frank_id;


    -- ─────────────────────────────────────────────────────────────────────────
    -- SECTION 7 — DQ Evaluation + Promotion: Batch 2
    -- ─────────────────────────────────────────────────────────────────────────
    RAISE NOTICE '';
    RAISE NOTICE '=== SECTION 7: DQ + Promotion — Batch 2 ===';

    SELECT * INTO v_dq_result
    FROM eligibility.evaluate_batch_dq(v_batch2_id);

    RAISE NOTICE 'Batch 2 DQ summary: total=%, valid=%, warnings=%, quarantined=%',
        v_dq_result.total_evaluated,
        v_dq_result.valid_count,
        v_dq_result.valid_with_warnings_count,
        v_dq_result.quarantined_count;
    -- Expected: total=1, valid=0, warnings=0, quarantined=1 (Frank — DQ_DUPLICATE_EMAIL)

    SELECT * INTO v_promote_result
    FROM eligibility.promote_batch(v_batch2_id);

    RAISE NOTICE 'Batch 2 promotion: total=%, promoted=%, skipped_duplicate=%, failed_validation=%, failed_system=%',
        v_promote_result.total_records,
        v_promote_result.promoted_count,
        v_promote_result.skipped_duplicate_count,
        v_promote_result.failed_validation_count,
        v_promote_result.failed_system_count;
    -- Expected: promoted=0, failed_validation=1 (Frank — DQ_STATUS_NOT_PROMOTABLE)


    -- ─────────────────────────────────────────────────────────────────────────
    -- SECTION 8 — Identity Verification
    -- ─────────────────────────────────────────────────────────────────────────
    RAISE NOTICE '';
    RAISE NOTICE '=== SECTION 8: Identity Verification ===';

    -- Alice: email hash + name_dob hash → score capped at 100 → auto-approved (threshold 95)
    SELECT * INTO v_idv_result
    FROM eligibility.verify_identity_by_tokens(
        p_partner_id                      => 'acme-corp',
        p_tenant_id                       => 'tenant-main',
        p_org_id                          => 'org-us',
        p_data_region                     => 'us-east-1',
        p_request_source                  => 'seed_demo',
        p_external_request_id             => 'demo-idv-alice-001',
        p_submitted_normalized_email_hash => encode(digest(lower(trim('alice@acme.com')), 'sha256'), 'hex'),
        p_submitted_name_dob_hash         => encode(digest('alice|johnson|1985-06-14', 'sha256'), 'hex')
    );

    RAISE NOTICE 'IDV Alice:   decision=%, score=%, reason=%',
        v_idv_result.decision_status, v_idv_result.match_score, v_idv_result.decision_reason_code;
    -- Expected: decision=approved, score=100.00

    -- Unknown person: hash not in any token table → no_match → denied
    SELECT * INTO v_idv_result
    FROM eligibility.verify_identity_by_tokens(
        p_partner_id                      => 'acme-corp',
        p_tenant_id                       => 'tenant-main',
        p_org_id                          => 'org-us',
        p_data_region                     => 'us-east-1',
        p_request_source                  => 'seed_demo',
        p_external_request_id             => 'demo-idv-unknown-001',
        p_submitted_normalized_email_hash => encode(digest('unknown@nowhere.com', 'sha256'), 'hex')
    );

    RAISE NOTICE 'IDV Unknown: decision=%, score=%, reason=%',
        v_idv_result.decision_status, v_idv_result.match_score, v_idv_result.decision_reason_code;
    -- Expected: decision=denied (no_match)

    RAISE NOTICE '';
    RAISE NOTICE '=== Seed complete. Run verification queries below. ===';

END;
$$;

COMMIT;


-- ═════════════════════════════════════════════════════════════════════════════
-- Verification Queries
-- Run these after the seed to inspect end-to-end state.
-- ═════════════════════════════════════════════════════════════════════════════

-- 1. Batch overview — DQ counters per batch
SELECT
    b.source_file_name,
    b.is_full_snapshot,
    b.record_count,
    b.valid_record_count,
    b.valid_with_warnings_record_count,
    b.quarantined_record_count,
    b.dq_error_count,
    b.dq_warning_count
FROM eligibility.partner_eligibility_batch b
WHERE b.partner_id = 'acme-corp'
ORDER BY b.received_at;


-- 2. DQ status per canonical record
SELECT
    r.partner_employee_id,
    r.employment_type,
    r.dq_status,
    r.dq_score,
    r.dq_error_count,
    r.dq_warning_count,
    r.dq_error_codes,
    r.requires_manual_review
FROM eligibility.canonical_eligibility_record r
WHERE r.partner_id = 'acme-corp'
ORDER BY r.source_row_number NULLS LAST, r.created_at;


-- 3. Quarantine issues — what failed and why
SELECT
    q.error_code,
    q.error_severity,
    q.failed_field,
    q.failure_reason,
    q.requires_partner_action,
    q.created_at
FROM eligibility.eligibility_quarantine q
WHERE q.partner_id = 'acme-corp'
ORDER BY q.created_at, q.error_code;


-- 4. Curated eligibility — promoted records only
SELECT
    c.partner_employee_id,
    c.eligibility_status,
    c.eligibility_start_date,
    c.curated_at
FROM eligibility.curated_eligibility_current c
WHERE c.partner_id = 'acme-corp'
ORDER BY c.curated_at;


-- 5. Active eligibility serving view
SELECT
    partner_employee_id,
    eligibility_status,
    eligibility_start_date
FROM eligibility.v_current_active_eligibility
WHERE partner_id = 'acme-corp'
ORDER BY partner_employee_id;


-- 6. Duplicate email audit — should surface Frank's collision with Alice
SELECT
    normalized_primary_email,
    conflicting_record_count,
    partner_employee_ids,
    first_curated_at,
    last_curated_at
FROM eligibility.v_duplicate_pii_email
WHERE partner_id = 'acme-corp';


-- 7. Email format errors — should surface Dave's malformed address
SELECT
    partner_employee_id,
    primary_email,
    normalized_primary_email,
    dq_status
FROM eligibility.v_email_format_errors
WHERE partner_id = 'acme-corp';


-- 8. Identity verification decisions
SELECT
    vr.external_request_id,
    vd.decision_status,
    vd.match_score,
    vd.decision_reason_code,
    vd.decided_at
FROM eligibility.identity_verification_decision vd
JOIN eligibility.identity_verification_request vr
  ON vr.identity_verification_request_id = vd.identity_verification_request_id
WHERE vr.partner_id = 'acme-corp'
ORDER BY vd.decided_at;
