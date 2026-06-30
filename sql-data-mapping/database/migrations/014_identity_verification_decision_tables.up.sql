BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'eligibility'
          AND t.typname = 'identity_verification_request_status'
    ) THEN
        CREATE TYPE eligibility.identity_verification_request_status AS ENUM (
            'received',
            'matching',
            'matched',
            'not_matched',
            'ambiguous_match',
            'decisioned',
            'manual_review',
            'failed'
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'eligibility'
          AND t.typname = 'identity_match_strategy'
    ) THEN
        CREATE TYPE eligibility.identity_match_strategy AS ENUM (
            'exact_token',
            'composite_token',
            'partner_identifier',
            'eligibility_identifier',
            'manual_review',
            'fallback'
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'eligibility'
          AND t.typname = 'identity_match_candidate_status'
    ) THEN
        CREATE TYPE eligibility.identity_match_candidate_status AS ENUM (
            'candidate',
            'selected',
            'rejected',
            'superseded',
            'manual_review'
        );
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'eligibility'
          AND t.typname = 'identity_verification_decision_status'
    ) THEN
        CREATE TYPE eligibility.identity_verification_decision_status AS ENUM (
            'approved',
            'denied',
            'manual_review',
            'failed'
        );
    END IF;
END $$;

CREATE TABLE eligibility.identity_verification_request (
    identity_verification_request_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    partner_id TEXT NOT NULL,
    tenant_id TEXT NOT NULL,
    org_id TEXT NOT NULL,
    data_region TEXT NOT NULL,

    external_request_id TEXT NULL,
    request_source TEXT NOT NULL,
    requester_subject_id TEXT NULL,
    requester_account_id TEXT NULL,
    application_user_id TEXT NULL,
    idempotency_key TEXT NULL,

    request_status eligibility.identity_verification_request_status NOT NULL DEFAULT 'received',
    requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    matching_started_at TIMESTAMPTZ NULL,
    matching_completed_at TIMESTAMPTZ NULL,
    decisioned_at TIMESTAMPTZ NULL,
    failed_at TIMESTAMPTZ NULL,

    identity_match_policy_id TEXT NOT NULL DEFAULT 'policy_v1',
    identity_match_policy_version TEXT NOT NULL DEFAULT 'v1',
    decision_policy_id TEXT NOT NULL DEFAULT 'decision_policy_v1',
    decision_policy_version TEXT NOT NULL DEFAULT 'v1',

    submitted_normalized_email_hash TEXT NULL,
    submitted_phone_hash TEXT NULL,
    submitted_dob_hash TEXT NULL,
    submitted_name_dob_hash TEXT NULL,
    submitted_partner_employee_id_hash TEXT NULL,
    submitted_partner_person_id_hash TEXT NULL,
    submitted_partner_member_id_hash TEXT NULL,
    submitted_masked_email TEXT NULL,
    submitted_masked_phone TEXT NULL,
    submitted_last_four_ssn TEXT NULL,
    submitted_identity_token_count INTEGER NOT NULL DEFAULT 0,

    request_context JSONB NOT NULL DEFAULT '{}'::JSONB,
    request_metadata JSONB NOT NULL DEFAULT '{}'::JSONB,
    failure_reason TEXT NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_identity_verification_request_scope_not_empty CHECK (
        btrim(partner_id) <> ''
        AND btrim(tenant_id) <> ''
        AND btrim(org_id) <> ''
        AND btrim(data_region) <> ''
    ),
    CONSTRAINT chk_identity_verification_request_source_not_empty CHECK (btrim(request_source) <> ''),
    CONSTRAINT chk_identity_verification_request_token_count_nonnegative CHECK (submitted_identity_token_count >= 0),
    CONSTRAINT chk_identity_verification_request_has_identity_evidence CHECK (
        submitted_identity_token_count > 0
        OR submitted_normalized_email_hash IS NOT NULL
        OR submitted_phone_hash IS NOT NULL
        OR submitted_dob_hash IS NOT NULL
        OR submitted_name_dob_hash IS NOT NULL
        OR submitted_partner_employee_id_hash IS NOT NULL
        OR submitted_partner_person_id_hash IS NOT NULL
        OR submitted_partner_member_id_hash IS NOT NULL
    ),
    CONSTRAINT chk_identity_verification_request_last_four_ssn CHECK (
        submitted_last_four_ssn IS NULL
        OR submitted_last_four_ssn ~ '^[0-9]{4}$'
    ),
    CONSTRAINT chk_identity_verification_request_matching_completed_after_started CHECK (
        matching_completed_at IS NULL
        OR matching_started_at IS NULL
        OR matching_completed_at >= matching_started_at
    ),
    CONSTRAINT chk_identity_verification_request_terminal_timestamp CHECK (
        (request_status <> 'decisioned' OR decisioned_at IS NOT NULL)
        AND (request_status <> 'failed' OR failed_at IS NOT NULL)
    )
);

COMMENT ON TABLE eligibility.identity_verification_request IS
'Identity verification attempts against the curated eligibility serving layer. Stores submitted identity evidence as hashes/masked values rather than raw PII.';

COMMENT ON COLUMN eligibility.identity_verification_request.request_context IS
'Safe request context such as client application, flow, locale, or non-PII request attributes. Do not store raw PII.';

COMMENT ON COLUMN eligibility.identity_verification_request.request_metadata IS
'Operational metadata such as trace IDs or request diagnostics. Do not store raw PII.';

CREATE UNIQUE INDEX idx_identity_verification_request_external_request
ON eligibility.identity_verification_request (partner_id, tenant_id, org_id, data_region, external_request_id)
WHERE external_request_id IS NOT NULL;

CREATE UNIQUE INDEX idx_identity_verification_request_idempotency_key
ON eligibility.identity_verification_request (partner_id, tenant_id, org_id, data_region, idempotency_key)
WHERE idempotency_key IS NOT NULL;

CREATE INDEX idx_identity_verification_request_scope_status_requested
ON eligibility.identity_verification_request (partner_id, tenant_id, org_id, data_region, request_status, requested_at DESC);

CREATE INDEX idx_identity_verification_request_email_hash
ON eligibility.identity_verification_request (partner_id, tenant_id, org_id, data_region, submitted_normalized_email_hash)
WHERE submitted_normalized_email_hash IS NOT NULL;

CREATE INDEX idx_identity_verification_request_name_dob_hash
ON eligibility.identity_verification_request (partner_id, tenant_id, org_id, data_region, submitted_name_dob_hash)
WHERE submitted_name_dob_hash IS NOT NULL;

CREATE INDEX idx_identity_verification_request_employee_hash
ON eligibility.identity_verification_request (partner_id, tenant_id, org_id, data_region, submitted_partner_employee_id_hash)
WHERE submitted_partner_employee_id_hash IS NOT NULL;

CREATE TABLE eligibility.identity_verification_match_candidate (
    identity_verification_match_candidate_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    identity_verification_request_id UUID NOT NULL
        REFERENCES eligibility.identity_verification_request(identity_verification_request_id)
        ON DELETE CASCADE,

    partner_id TEXT NOT NULL,
    tenant_id TEXT NOT NULL,
    org_id TEXT NOT NULL,
    data_region TEXT NOT NULL,

    curated_eligibility_id UUID NOT NULL
        REFERENCES eligibility.curated_eligibility_current(curated_eligibility_id),
    eligibility_record_id UUID NOT NULL
        REFERENCES eligibility.canonical_eligibility_record(eligibility_record_id),

    match_rank INTEGER NOT NULL,
    match_score NUMERIC(5,2) NOT NULL,
    match_strategy eligibility.identity_match_strategy NOT NULL,
    match_candidate_status eligibility.identity_match_candidate_status NOT NULL DEFAULT 'candidate',
    matched_token_types TEXT[] NULL,
    matched_identifier_types TEXT[] NULL,
    match_reason TEXT NULL,
    mismatch_reason TEXT NULL,

    eligibility_status eligibility.eligibility_status NOT NULL,
    is_currently_eligible BOOLEAN NOT NULL,
    eligibility_start_date DATE NOT NULL,
    eligibility_end_date DATE NULL,
    dq_status eligibility.dq_status NOT NULL,
    source_last_updated_at TIMESTAMPTZ NOT NULL,
    curated_at TIMESTAMPTZ NOT NULL,
    candidate_snapshot JSONB NOT NULL DEFAULT '{}'::JSONB,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_identity_match_candidate_scope_not_empty CHECK (
        btrim(partner_id) <> ''
        AND btrim(tenant_id) <> ''
        AND btrim(org_id) <> ''
        AND btrim(data_region) <> ''
    ),
    CONSTRAINT chk_identity_match_candidate_rank_positive CHECK (match_rank > 0),
    CONSTRAINT chk_identity_match_candidate_score_range CHECK (match_score >= 0 AND match_score <= 100),
    CONSTRAINT chk_identity_match_candidate_dates CHECK (
        eligibility_end_date IS NULL OR eligibility_end_date >= eligibility_start_date
    )
);

COMMENT ON TABLE eligibility.identity_verification_match_candidate IS
'Candidate curated eligibility records identified during identity verification matching, including match score, strategy, and a safe eligibility snapshot.';

CREATE UNIQUE INDEX idx_identity_match_candidate_unique_curated_per_request
ON eligibility.identity_verification_match_candidate (identity_verification_request_id, curated_eligibility_id);

CREATE UNIQUE INDEX idx_identity_match_candidate_unique_rank_per_request
ON eligibility.identity_verification_match_candidate (identity_verification_request_id, match_rank);

CREATE INDEX idx_identity_match_candidate_scope_request
ON eligibility.identity_verification_match_candidate (partner_id, tenant_id, org_id, data_region, identity_verification_request_id);

CREATE INDEX idx_identity_match_candidate_curated
ON eligibility.identity_verification_match_candidate (curated_eligibility_id);

CREATE INDEX idx_identity_match_candidate_status_score
ON eligibility.identity_verification_match_candidate (match_candidate_status, match_score DESC);

CREATE TABLE eligibility.identity_verification_decision (
    identity_verification_decision_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    identity_verification_request_id UUID NOT NULL
        REFERENCES eligibility.identity_verification_request(identity_verification_request_id)
        ON DELETE CASCADE,
    identity_verification_match_candidate_id UUID NULL
        REFERENCES eligibility.identity_verification_match_candidate(identity_verification_match_candidate_id)
        ON DELETE SET NULL,

    partner_id TEXT NOT NULL,
    tenant_id TEXT NOT NULL,
    org_id TEXT NOT NULL,
    data_region TEXT NOT NULL,

    curated_eligibility_id UUID NULL
        REFERENCES eligibility.curated_eligibility_current(curated_eligibility_id),
    eligibility_record_id UUID NULL
        REFERENCES eligibility.canonical_eligibility_record(eligibility_record_id),

    decision_status eligibility.identity_verification_decision_status NOT NULL,
    decision_reason_code TEXT NOT NULL,
    decision_reason TEXT NULL,
    is_eligible BOOLEAN NOT NULL,
    requires_manual_review BOOLEAN NOT NULL DEFAULT FALSE,
    confidence_score NUMERIC(5,2) NULL,

    decision_policy_id TEXT NOT NULL DEFAULT 'decision_policy_v1',
    decision_policy_version TEXT NOT NULL DEFAULT 'v1',
    decision_rule_version TEXT NOT NULL DEFAULT 'v1',
    decision_evidence JSONB NOT NULL DEFAULT '{}'::JSONB,

    decided_by TEXT NOT NULL DEFAULT 'system',
    decided_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_identity_verification_decision_scope_not_empty CHECK (
        btrim(partner_id) <> ''
        AND btrim(tenant_id) <> ''
        AND btrim(org_id) <> ''
        AND btrim(data_region) <> ''
    ),
    CONSTRAINT chk_identity_verification_decision_reason_code_not_empty CHECK (btrim(decision_reason_code) <> ''),
    CONSTRAINT chk_identity_verification_decision_confidence_range CHECK (
        confidence_score IS NULL OR (confidence_score >= 0 AND confidence_score <= 100)
    ),
    CONSTRAINT chk_identity_verification_decision_status_consistency CHECK (
        (decision_status = 'approved' AND is_eligible = TRUE AND requires_manual_review = FALSE AND curated_eligibility_id IS NOT NULL)
        OR (decision_status = 'denied' AND is_eligible = FALSE AND requires_manual_review = FALSE)
        OR (decision_status = 'manual_review' AND requires_manual_review = TRUE)
        OR (decision_status = 'failed' AND is_eligible = FALSE)
    )
);

COMMENT ON TABLE eligibility.identity_verification_decision IS
'Final auditable decision for an identity verification request, including eligibility outcome, policy version, and safe decision evidence.';

COMMENT ON COLUMN eligibility.identity_verification_decision.decision_evidence IS
'Safe evidence used to support the decision, such as matched token types, score, rule IDs, and non-PII diagnostics. Do not store raw PII.';

CREATE UNIQUE INDEX idx_identity_verification_decision_one_per_request
ON eligibility.identity_verification_decision (identity_verification_request_id);

CREATE INDEX idx_identity_verification_decision_scope_status_decided
ON eligibility.identity_verification_decision (partner_id, tenant_id, org_id, data_region, decision_status, decided_at DESC);

CREATE INDEX idx_identity_verification_decision_curated
ON eligibility.identity_verification_decision (curated_eligibility_id)
WHERE curated_eligibility_id IS NOT NULL;

CREATE INDEX idx_identity_verification_decision_record
ON eligibility.identity_verification_decision (eligibility_record_id)
WHERE eligibility_record_id IS NOT NULL;

DROP TRIGGER IF EXISTS trg_identity_verification_request_updated_at
ON eligibility.identity_verification_request;
CREATE TRIGGER trg_identity_verification_request_updated_at
BEFORE UPDATE ON eligibility.identity_verification_request
FOR EACH ROW
EXECUTE FUNCTION eligibility.set_updated_at();

DROP TRIGGER IF EXISTS trg_identity_match_candidate_updated_at
ON eligibility.identity_verification_match_candidate;
CREATE TRIGGER trg_identity_match_candidate_updated_at
BEFORE UPDATE ON eligibility.identity_verification_match_candidate
FOR EACH ROW
EXECUTE FUNCTION eligibility.set_updated_at();

DROP TRIGGER IF EXISTS trg_identity_verification_decision_updated_at
ON eligibility.identity_verification_decision;
CREATE TRIGGER trg_identity_verification_decision_updated_at
BEFORE UPDATE ON eligibility.identity_verification_decision
FOR EACH ROW
EXECUTE FUNCTION eligibility.set_updated_at();

ALTER TABLE eligibility.identity_verification_request ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.identity_verification_request FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_identity_verification_request_scope
ON eligibility.identity_verification_request;
CREATE POLICY rls_identity_verification_request_scope
ON eligibility.identity_verification_request
FOR ALL
USING (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
)
WITH CHECK (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
);

ALTER TABLE eligibility.identity_verification_match_candidate ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.identity_verification_match_candidate FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_identity_match_candidate_scope
ON eligibility.identity_verification_match_candidate;
CREATE POLICY rls_identity_match_candidate_scope
ON eligibility.identity_verification_match_candidate
FOR ALL
USING (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
)
WITH CHECK (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
);

ALTER TABLE eligibility.identity_verification_decision ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.identity_verification_decision FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_identity_verification_decision_scope
ON eligibility.identity_verification_decision;
CREATE POLICY rls_identity_verification_decision_scope
ON eligibility.identity_verification_decision
FOR ALL
USING (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
)
WITH CHECK (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
);

COMMIT;
