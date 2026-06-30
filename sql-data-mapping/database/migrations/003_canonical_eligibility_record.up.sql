BEGIN;

CREATE TABLE eligibility.canonical_eligibility_record (
    eligibility_record_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    batch_id UUID NOT NULL REFERENCES eligibility.partner_eligibility_batch(batch_id),

    partner_id TEXT NOT NULL,
    tenant_id TEXT NOT NULL,
    org_id TEXT NOT NULL,
    data_region TEXT NOT NULL,

    source_record_id TEXT,
    source_row_number INTEGER,
    source_schema_version TEXT NOT NULL,
    source_operation eligibility.source_operation,
    source_event_id TEXT,
    source_event_timestamp TIMESTAMPTZ,
    is_full_snapshot BOOLEAN NOT NULL DEFAULT FALSE,
    snapshot_as_of_at TIMESTAMPTZ,

    partner_employee_id TEXT NOT NULL,
    partner_member_id TEXT,
    partner_person_id TEXT,
    external_account_id TEXT,
    employee_number TEXT,
    legacy_employee_id TEXT,

    work_location_city TEXT,
    work_location_region TEXT,
    work_location_country TEXT,
    legal_entity_country TEXT,

    employment_status TEXT,
    employment_type TEXT,
    worker_type TEXT,
    job_title TEXT,
    job_code TEXT,
    department TEXT,
    division TEXT,
    cost_center TEXT,
    manager_employee_id TEXT,
    hire_date DATE,
    termination_date DATE,
    leave_start_date DATE,
    leave_end_date DATE,

    eligibility_status eligibility.eligibility_status NOT NULL,
    eligibility_status_reason TEXT,
    eligibility_start_date DATE NOT NULL,
    eligibility_end_date DATE,
    eligibility_effective_date DATE,
    eligibility_group_code TEXT,
    eligibility_group_name TEXT,
    benefit_plan_id TEXT,
    benefit_plan_name TEXT,
    coverage_level TEXT,
    eligibility_priority INTEGER,

    person_relationship_type eligibility.person_relationship_type NOT NULL DEFAULT 'employee',
    primary_employee_partner_id TEXT,
    relationship_start_date DATE,
    relationship_end_date DATE,

    privacy_jurisdiction TEXT,
    processing_basis TEXT,
    consent_required BOOLEAN,
    legal_entity_id TEXT,
    legal_entity_name TEXT,

    record_hash TEXT NOT NULL,
    previous_record_hash TEXT,
    change_detected_at TIMESTAMPTZ,
    change_reason TEXT,

    dq_status eligibility.dq_status NOT NULL DEFAULT 'pending_review',
    dq_score NUMERIC(5,2),
    dq_error_count INTEGER NOT NULL DEFAULT 0,
    dq_warning_count INTEGER NOT NULL DEFAULT 0,
    dq_error_codes TEXT[],
    dq_last_checked_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    requires_manual_review BOOLEAN NOT NULL DEFAULT FALSE,

    pii_classification TEXT[],
    contains_sensitive_pii BOOLEAN NOT NULL DEFAULT FALSE,
    contains_prohibited_pii BOOLEAN NOT NULL DEFAULT FALSE,
    tokenization_status eligibility.tokenization_status NOT NULL DEFAULT 'pending',
    encryption_status eligibility.encryption_status NOT NULL DEFAULT 'not_required',
    retention_policy_id TEXT,
    delete_after_date DATE,
    legal_hold BOOLEAN NOT NULL DEFAULT FALSE,
    access_policy_id TEXT,

    processed_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_canonical_source_row_positive
        CHECK (source_row_number IS NULL OR source_row_number > 0),

    CONSTRAINT chk_canonical_required_identifiers
        CHECK (
            partner_employee_id IS NOT NULL
            OR partner_person_id IS NOT NULL
            OR partner_member_id IS NOT NULL
        ),

    CONSTRAINT chk_canonical_eligibility_date_range
        CHECK (
            eligibility_end_date IS NULL
            OR eligibility_end_date >= eligibility_start_date
        ),

    CONSTRAINT chk_canonical_termination_date_reasonable
        CHECK (
            termination_date IS NULL
            OR hire_date IS NULL
            OR termination_date >= hire_date
        ),

    CONSTRAINT chk_canonical_leave_date_range
        CHECK (
            leave_end_date IS NULL
            OR leave_start_date IS NULL
            OR leave_end_date >= leave_start_date
        ),

    CONSTRAINT chk_canonical_relationship_date_range
        CHECK (
            relationship_end_date IS NULL
            OR relationship_start_date IS NULL
            OR relationship_end_date >= relationship_start_date
        ),

    CONSTRAINT chk_canonical_snapshot_as_of_required
        CHECK (
            is_full_snapshot = FALSE
            OR snapshot_as_of_at IS NOT NULL
        ),

    CONSTRAINT chk_canonical_end_date_for_inactive_states
        CHECK (
            eligibility_status NOT IN ('inactive', 'terminated', 'expired')
            OR eligibility_end_date IS NOT NULL
        ),

    CONSTRAINT chk_canonical_dq_counts_non_negative
        CHECK (
            dq_error_count >= 0
            AND dq_warning_count >= 0
        )
);

CREATE INDEX idx_canonical_batch_id
    ON eligibility.canonical_eligibility_record(batch_id);

CREATE INDEX idx_canonical_partner_employee
    ON eligibility.canonical_eligibility_record(
        partner_id,
        tenant_id,
        partner_employee_id
    );

CREATE INDEX idx_canonical_partner_person
    ON eligibility.canonical_eligibility_record(
        partner_id,
        tenant_id,
        partner_person_id
    )
    WHERE partner_person_id IS NOT NULL;

CREATE INDEX idx_canonical_partner_member
    ON eligibility.canonical_eligibility_record(
        partner_id,
        tenant_id,
        partner_member_id
    )
    WHERE partner_member_id IS NOT NULL;

CREATE INDEX idx_canonical_dq_status
    ON eligibility.canonical_eligibility_record(
        dq_status,
        processed_at DESC
    );

CREATE INDEX idx_canonical_eligibility_status
    ON eligibility.canonical_eligibility_record(
        eligibility_status,
        eligibility_start_date,
        eligibility_end_date
    );

CREATE INDEX idx_canonical_record_hash
    ON eligibility.canonical_eligibility_record(
        partner_id,
        tenant_id,
        record_hash
    );

CREATE INDEX idx_canonical_source_event_id
    ON eligibility.canonical_eligibility_record(
        partner_id,
        tenant_id,
        source_event_id
    )
    WHERE source_event_id IS NOT NULL;

COMMIT;
