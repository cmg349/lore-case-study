BEGIN;

CREATE TABLE eligibility.curated_eligibility_current (
    curated_eligibility_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

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

    eligibility_start_date DATE NOT NULL,
    eligibility_end_date DATE,
    eligibility_group_code TEXT,
    benefit_plan_id TEXT,

    person_relationship_type eligibility.person_relationship_type NOT NULL DEFAULT 'employee',

    identity_match_policy_id TEXT NOT NULL,
    dq_status eligibility.dq_status NOT NULL,

    source_last_updated_at TIMESTAMPTZ NOT NULL,
    curated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_curated_only_valid_dq_status
        CHECK (dq_status IN ('valid', 'valid_with_warnings')),

    CONSTRAINT chk_curated_eligibility_date_range
        CHECK (
            eligibility_end_date IS NULL
            OR eligibility_end_date >= eligibility_start_date
        )
);

CREATE UNIQUE INDEX idx_curated_current_partner_employee
    ON eligibility.curated_eligibility_current(
        partner_id,
        tenant_id,
        partner_employee_id
    );

CREATE UNIQUE INDEX idx_curated_current_partner_person
    ON eligibility.curated_eligibility_current(
        partner_id,
        tenant_id,
        partner_person_id
    )
    WHERE partner_person_id IS NOT NULL;

CREATE INDEX idx_curated_current_org_lookup
    ON eligibility.curated_eligibility_current(
        tenant_id,
        org_id,
        eligibility_status
    )
    WHERE eligibility_status = 'active';

CREATE INDEX idx_curated_current_active
    ON eligibility.curated_eligibility_current(
        partner_id,
        tenant_id,
        eligibility_status
    )
    WHERE eligibility_status = 'active';

CREATE INDEX idx_curated_current_source_updated
    ON eligibility.curated_eligibility_current(
        source_last_updated_at DESC
    );

CREATE INDEX idx_curated_current_end_date
    ON eligibility.curated_eligibility_current(eligibility_end_date)
    WHERE eligibility_end_date IS NOT NULL;

COMMIT;
