BEGIN;

CREATE TABLE eligibility.eligibility_person_pii (
    pii_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    eligibility_record_id UUID NOT NULL
        REFERENCES eligibility.canonical_eligibility_record(eligibility_record_id)
        ON DELETE CASCADE,

    partner_id TEXT NOT NULL,
    tenant_id TEXT NOT NULL,
    org_id TEXT NOT NULL,
    data_region TEXT NOT NULL,

    first_name TEXT NOT NULL,
    middle_name TEXT,
    last_name TEXT NOT NULL,
    preferred_name TEXT,
    full_name TEXT,
    name_suffix TEXT,

    date_of_birth DATE,

    primary_email CITEXT,
    work_email CITEXT,
    personal_email CITEXT,

    primary_phone TEXT,
    mobile_phone TEXT,
    work_phone TEXT,
    phone_country_code TEXT,

    address_line_1 TEXT,
    address_line_2 TEXT,
    city TEXT,
    region TEXT,
    postal_code TEXT,
    country TEXT,

    last_four_ssn TEXT,
    national_id TEXT,

    normalized_primary_email CITEXT,
    normalized_work_email CITEXT,
    normalized_personal_email CITEXT,
    normalized_primary_phone TEXT,

    pii_encryption_key_id TEXT,
    encryption_status eligibility.encryption_status NOT NULL DEFAULT 'not_required',

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_pii_names_not_empty
        CHECK (
            length(trim(first_name)) > 0
            AND length(trim(last_name)) > 0
        ),

    CONSTRAINT chk_pii_last_four_ssn_format
        CHECK (
            last_four_ssn IS NULL
            OR last_four_ssn ~ '^[0-9]{4}$'
        )
);

CREATE UNIQUE INDEX idx_eligibility_person_pii_record
    ON eligibility.eligibility_person_pii(eligibility_record_id);

CREATE INDEX idx_eligibility_person_pii_partner
    ON eligibility.eligibility_person_pii(
        partner_id,
        tenant_id,
        org_id
    );

CREATE INDEX idx_eligibility_person_pii_email
    ON eligibility.eligibility_person_pii(
        partner_id,
        tenant_id,
        normalized_primary_email
    )
    WHERE normalized_primary_email IS NOT NULL;

COMMIT;
