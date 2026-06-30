BEGIN;

CREATE TABLE eligibility.curated_eligibility_history (
    history_id UUID NOT NULL DEFAULT gen_random_uuid(),

    curated_eligibility_id UUID NOT NULL,
    eligibility_record_id UUID NOT NULL
        REFERENCES eligibility.canonical_eligibility_record(eligibility_record_id),

    partner_id TEXT NOT NULL,
    tenant_id TEXT NOT NULL,
    org_id TEXT NOT NULL,
    data_region TEXT NOT NULL,

    partner_employee_id TEXT NOT NULL,
    partner_person_id TEXT,
    partner_member_id TEXT,

    eligibility_status eligibility.eligibility_status NOT NULL,
    is_currently_eligible BOOLEAN NOT NULL,

    eligibility_start_date DATE NOT NULL,
    eligibility_end_date DATE,

    valid_from TIMESTAMPTZ NOT NULL,
    valid_to TIMESTAMPTZ,

    change_reason TEXT,
    source_operation eligibility.source_operation,
    record_hash TEXT NOT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_history_valid_range
        CHECK (
            valid_to IS NULL
            OR valid_to > valid_from
        ),

    CONSTRAINT chk_history_eligibility_date_range
        CHECK (
            eligibility_end_date IS NULL
            OR eligibility_end_date >= eligibility_start_date
        ),

    PRIMARY KEY (history_id, valid_from)

) PARTITION BY RANGE (valid_from);

CREATE TABLE eligibility.curated_eligibility_history_2024
    PARTITION OF eligibility.curated_eligibility_history
    FOR VALUES FROM ('2024-01-01 00:00:00+00') TO ('2025-01-01 00:00:00+00');

CREATE TABLE eligibility.curated_eligibility_history_2025
    PARTITION OF eligibility.curated_eligibility_history
    FOR VALUES FROM ('2025-01-01 00:00:00+00') TO ('2026-01-01 00:00:00+00');

CREATE TABLE eligibility.curated_eligibility_history_2026
    PARTITION OF eligibility.curated_eligibility_history
    FOR VALUES FROM ('2026-01-01 00:00:00+00') TO ('2027-01-01 00:00:00+00');

CREATE TABLE eligibility.curated_eligibility_history_2027
    PARTITION OF eligibility.curated_eligibility_history
    FOR VALUES FROM ('2027-01-01 00:00:00+00') TO ('2028-01-01 00:00:00+00');

CREATE TABLE eligibility.curated_eligibility_history_default
    PARTITION OF eligibility.curated_eligibility_history
    DEFAULT;

CREATE INDEX idx_history_curated_id
    ON eligibility.curated_eligibility_history(
        curated_eligibility_id,
        valid_from DESC
    );

CREATE INDEX idx_history_partner_employee
    ON eligibility.curated_eligibility_history(
        partner_id,
        tenant_id,
        partner_employee_id,
        valid_from DESC
    );

CREATE INDEX idx_history_open_records
    ON eligibility.curated_eligibility_history(
        curated_eligibility_id
    )
    WHERE valid_to IS NULL;

CREATE INDEX idx_history_record_hash
    ON eligibility.curated_eligibility_history(
        partner_id,
        tenant_id,
        record_hash
    );

COMMIT;
