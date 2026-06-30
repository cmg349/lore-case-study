BEGIN;

CREATE TABLE eligibility.partner_eligibility_batch (
    batch_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    partner_id TEXT NOT NULL,
    tenant_id TEXT NOT NULL,
    org_id TEXT NOT NULL,
    data_region TEXT NOT NULL,

    source_file_name TEXT,
    source_file_uri TEXT,
    source_file_checksum TEXT NOT NULL,
    source_schema_version TEXT NOT NULL,

    delivery_type eligibility.delivery_type NOT NULL,
    is_full_snapshot BOOLEAN NOT NULL DEFAULT FALSE,
    snapshot_as_of_at TIMESTAMPTZ,

    received_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    processing_started_at TIMESTAMPTZ,
    processing_completed_at TIMESTAMPTZ,

    batch_status eligibility.batch_status NOT NULL DEFAULT 'received',

    record_count INTEGER,
    valid_record_count INTEGER,
    valid_with_warnings_record_count INTEGER,
    quarantined_record_count INTEGER,
    rejected_record_count INTEGER,

    dq_error_count INTEGER NOT NULL DEFAULT 0,
    dq_warning_count INTEGER NOT NULL DEFAULT 0,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_batch_record_counts_non_negative
        CHECK (
            COALESCE(record_count, 0) >= 0
            AND COALESCE(valid_record_count, 0) >= 0
            AND COALESCE(valid_with_warnings_record_count, 0) >= 0
            AND COALESCE(quarantined_record_count, 0) >= 0
            AND COALESCE(rejected_record_count, 0) >= 0
        ),

    CONSTRAINT chk_batch_snapshot_as_of_required
        CHECK (
            is_full_snapshot = FALSE
            OR snapshot_as_of_at IS NOT NULL
        )
);

CREATE UNIQUE INDEX idx_partner_eligibility_batch_checksum
    ON eligibility.partner_eligibility_batch (
        partner_id,
        tenant_id,
        source_file_checksum
    );

CREATE INDEX idx_partner_eligibility_batch_partner_received
    ON eligibility.partner_eligibility_batch (
        partner_id,
        received_at DESC
    );

CREATE INDEX idx_partner_eligibility_batch_status
    ON eligibility.partner_eligibility_batch (
        batch_status,
        received_at DESC
    );

COMMIT;
