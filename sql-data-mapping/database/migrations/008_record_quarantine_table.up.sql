BEGIN;

CREATE TABLE eligibility.eligibility_quarantine (
    quarantine_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    batch_id UUID NOT NULL
        REFERENCES eligibility.partner_eligibility_batch(batch_id),

    eligibility_record_id UUID
        REFERENCES eligibility.canonical_eligibility_record(eligibility_record_id)
        ON DELETE SET NULL,

    partner_id TEXT NOT NULL,
    tenant_id TEXT NOT NULL,
    org_id TEXT NOT NULL,
    data_region TEXT NOT NULL,

    source_row_number INTEGER,
    raw_record_reference TEXT NOT NULL,
    canonical_record_reference TEXT,

    error_code TEXT NOT NULL,
    error_severity eligibility.error_severity NOT NULL,
    failed_field TEXT,
    failure_reason TEXT NOT NULL,

    requires_partner_action BOOLEAN NOT NULL DEFAULT FALSE,
    review_status eligibility.review_status NOT NULL DEFAULT 'open',

    reviewer TEXT,
    review_notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    resolved_at TIMESTAMPTZ,

    CONSTRAINT chk_quarantine_source_row_positive
        CHECK (
            source_row_number IS NULL
            OR source_row_number > 0
        ),

    CONSTRAINT chk_quarantine_resolution
        CHECK (
            review_status NOT IN ('resolved', 'closed')
            OR resolved_at IS NOT NULL
        )
);

CREATE INDEX idx_quarantine_batch
    ON eligibility.eligibility_quarantine(batch_id);

CREATE INDEX idx_quarantine_partner_status
    ON eligibility.eligibility_quarantine(
        partner_id,
        review_status,
        created_at DESC
    );

CREATE INDEX idx_quarantine_error_code
    ON eligibility.eligibility_quarantine(
        error_code,
        created_at DESC
    );

CREATE INDEX idx_quarantine_requires_partner_action
    ON eligibility.eligibility_quarantine(
        requires_partner_action,
        review_status
    )
    WHERE requires_partner_action = TRUE;

COMMIT;
