BEGIN;

CREATE TABLE eligibility.eligibility_identity_token (
    identity_token_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    eligibility_record_id UUID NOT NULL
        REFERENCES eligibility.canonical_eligibility_record(eligibility_record_id)
        ON DELETE CASCADE,

    partner_id TEXT NOT NULL,
    tenant_id TEXT NOT NULL,
    org_id TEXT NOT NULL,
    data_region TEXT NOT NULL,

    token_type eligibility.token_type NOT NULL,
    token_value TEXT NOT NULL,
    token_version TEXT NOT NULL DEFAULT 'v1',

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_identity_token_value_not_empty
        CHECK (length(trim(token_value)) > 0)
);

CREATE UNIQUE INDEX idx_identity_token_unique_per_record
    ON eligibility.eligibility_identity_token(
        eligibility_record_id,
        token_type,
        token_version
    );

CREATE INDEX idx_identity_token_lookup
    ON eligibility.eligibility_identity_token(
        partner_id,
        tenant_id,
        token_type,
        token_value
    );

CREATE INDEX idx_identity_token_cross_partner_lookup
    ON eligibility.eligibility_identity_token(
        tenant_id,
        token_type,
        token_value
    );

COMMIT;
