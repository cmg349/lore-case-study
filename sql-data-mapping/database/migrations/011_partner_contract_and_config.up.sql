BEGIN;

CREATE TYPE eligibility.contract_status AS ENUM (
    'draft',
    'active',
    'deprecated',
    'retired'
);

CREATE TYPE eligibility.field_requirement_level AS ENUM (
    'required',
    'conditional',
    'optional',
    'prohibited'
);

CREATE TYPE eligibility.validation_rule_type AS ENUM (
    'not_null',
    'not_empty',
    'regex',
    'allowed_values',
    'date_format',
    'date_not_future',
    'date_range',
    'unique',
    'unique_current_record',
    'expression',
    'pii_detection',
    'custom'
);

CREATE TYPE eligibility.validation_severity AS ENUM (
    'blocking',
    'warning',
    'info'
);

CREATE TYPE eligibility.pii_policy_action AS ENUM (
    'allow',
    'allow_with_encryption',
    'allow_with_tokenization',
    'allow_with_masking',
    'quarantine',
    'reject'
);

CREATE TYPE eligibility.schema_change_type AS ENUM (
    'backward_compatible',
    'breaking',
    'privacy_review_required',
    'emergency'
);

CREATE TABLE eligibility.partner_contract (
    partner_contract_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    partner_id TEXT NOT NULL,
    tenant_id TEXT NOT NULL,
    org_id TEXT NOT NULL,
    data_region TEXT NOT NULL,

    contract_name TEXT NOT NULL,
    contract_status eligibility.contract_status NOT NULL DEFAULT 'draft',

    effective_from DATE NOT NULL DEFAULT CURRENT_DATE,
    effective_to DATE,

    business_owner TEXT,
    technical_owner TEXT,
    privacy_owner TEXT,
    partner_contact_name TEXT,
    partner_contact_email CITEXT,

    description TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_partner_contract_effective_range
        CHECK (
            effective_to IS NULL
            OR effective_to >= effective_from
        )
);

CREATE UNIQUE INDEX idx_partner_contract_active_unique
    ON eligibility.partner_contract (
        partner_id,
        tenant_id,
        org_id,
        data_region
    )
    WHERE contract_status = 'active';

CREATE INDEX idx_partner_contract_partner_status
    ON eligibility.partner_contract (
        partner_id,
        tenant_id,
        contract_status
    );

CREATE TABLE eligibility.partner_schema_version (
    partner_schema_version_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    partner_contract_id UUID NOT NULL
        REFERENCES eligibility.partner_contract(partner_contract_id)
        ON DELETE CASCADE,

    schema_version TEXT NOT NULL,
    schema_status eligibility.contract_status NOT NULL DEFAULT 'draft',

    delivery_type eligibility.delivery_type NOT NULL,
    file_format TEXT,
    delimiter TEXT,
    encoding TEXT,
    has_header BOOLEAN,

    is_full_snapshot BOOLEAN NOT NULL DEFAULT FALSE,
    supports_incremental BOOLEAN NOT NULL DEFAULT FALSE,
    supports_deletes BOOLEAN NOT NULL DEFAULT FALSE,

    expected_min_columns INTEGER,
    expected_max_columns INTEGER,

    effective_from DATE NOT NULL DEFAULT CURRENT_DATE,
    effective_to DATE,

    sample_file_uri TEXT,
    raw_schema JSONB,
    notes TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_partner_schema_effective_range
        CHECK (
            effective_to IS NULL
            OR effective_to >= effective_from
        ),

    CONSTRAINT chk_partner_schema_column_count_range
        CHECK (
            expected_min_columns IS NULL
            OR expected_max_columns IS NULL
            OR expected_max_columns >= expected_min_columns
        ),

    CONSTRAINT chk_partner_schema_file_details
        CHECK (
            delivery_type NOT IN ('file', 'sftp')
            OR file_format IS NOT NULL
        )
);

CREATE UNIQUE INDEX idx_partner_schema_version_unique
    ON eligibility.partner_schema_version (
        partner_contract_id,
        schema_version
    );

CREATE UNIQUE INDEX idx_partner_schema_active_unique
    ON eligibility.partner_schema_version (
        partner_contract_id
    )
    WHERE schema_status = 'active';

CREATE INDEX idx_partner_schema_status
    ON eligibility.partner_schema_version (
        schema_status,
        effective_from DESC
    );

CREATE TABLE eligibility.partner_field_mapping (
    partner_field_mapping_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    partner_schema_version_id UUID NOT NULL
        REFERENCES eligibility.partner_schema_version(partner_schema_version_id)
        ON DELETE CASCADE,

    source_field_name TEXT NOT NULL,
    source_field_position INTEGER,

    canonical_field_name TEXT NOT NULL,
    canonical_table_name TEXT NOT NULL DEFAULT 'canonical_eligibility_record',

    requirement_level eligibility.field_requirement_level NOT NULL,

    source_data_type TEXT,
    canonical_data_type TEXT,

    default_value TEXT,
    transform_config JSONB,
    validation_config JSONB,

    pii_classification TEXT,
    pii_policy_action eligibility.pii_policy_action NOT NULL DEFAULT 'allow',

    is_identity_field BOOLEAN NOT NULL DEFAULT FALSE,
    is_eligibility_field BOOLEAN NOT NULL DEFAULT FALSE,
    is_matching_field BOOLEAN NOT NULL DEFAULT FALSE,

    description TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_partner_field_position_positive
        CHECK (
            source_field_position IS NULL
            OR source_field_position > 0
        ),

    CONSTRAINT chk_partner_field_source_name_not_empty
        CHECK (length(trim(source_field_name)) > 0),

    CONSTRAINT chk_partner_field_canonical_name_not_empty
        CHECK (length(trim(canonical_field_name)) > 0)
);

CREATE UNIQUE INDEX idx_partner_field_mapping_source_name
    ON eligibility.partner_field_mapping (
        partner_schema_version_id,
        source_field_name
    );

CREATE INDEX idx_partner_field_mapping_canonical_field
    ON eligibility.partner_field_mapping (
        partner_schema_version_id,
        canonical_field_name
    );

CREATE INDEX idx_partner_field_mapping_requirement
    ON eligibility.partner_field_mapping (
        requirement_level
    );

CREATE INDEX idx_partner_field_mapping_pii
    ON eligibility.partner_field_mapping (
        pii_policy_action,
        pii_classification
    );

CREATE TABLE eligibility.partner_data_quality_rule (
    partner_data_quality_rule_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    partner_schema_version_id UUID NOT NULL
        REFERENCES eligibility.partner_schema_version(partner_schema_version_id)
        ON DELETE CASCADE,

    rule_name TEXT NOT NULL,
    rule_type eligibility.validation_rule_type NOT NULL,
    severity eligibility.validation_severity NOT NULL,

    canonical_field_name TEXT,
    applies_to_table TEXT NOT NULL DEFAULT 'canonical_eligibility_record',

    rule_config JSONB NOT NULL DEFAULT '{}'::JSONB,

    error_code TEXT NOT NULL,
    error_message TEXT NOT NULL,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,
    execution_order INTEGER NOT NULL DEFAULT 100,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_dq_rule_name_not_empty
        CHECK (length(trim(rule_name)) > 0),

    CONSTRAINT chk_dq_error_code_not_empty
        CHECK (length(trim(error_code)) > 0),

    CONSTRAINT chk_dq_execution_order_positive
        CHECK (execution_order > 0)
);

CREATE UNIQUE INDEX idx_partner_dq_rule_name
    ON eligibility.partner_data_quality_rule (
        partner_schema_version_id,
        rule_name
    );

CREATE INDEX idx_partner_dq_rule_active_order
    ON eligibility.partner_data_quality_rule (
        partner_schema_version_id,
        is_active,
        execution_order
    );

CREATE INDEX idx_partner_dq_rule_field
    ON eligibility.partner_data_quality_rule (
        canonical_field_name
    )
    WHERE canonical_field_name IS NOT NULL;

CREATE TABLE eligibility.partner_value_mapping (
    partner_value_mapping_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    partner_schema_version_id UUID NOT NULL
        REFERENCES eligibility.partner_schema_version(partner_schema_version_id)
        ON DELETE CASCADE,

    canonical_field_name TEXT NOT NULL,
    source_value TEXT NOT NULL,
    canonical_value TEXT NOT NULL,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    description TEXT,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_value_mapping_canonical_field_not_empty
        CHECK (length(trim(canonical_field_name)) > 0),

    CONSTRAINT chk_value_mapping_source_value_not_empty
        CHECK (length(trim(source_value)) > 0),

    CONSTRAINT chk_value_mapping_canonical_value_not_empty
        CHECK (length(trim(canonical_value)) > 0)
);

CREATE UNIQUE INDEX idx_partner_value_mapping_unique
    ON eligibility.partner_value_mapping (
        partner_schema_version_id,
        canonical_field_name,
        source_value
    );

CREATE INDEX idx_partner_value_mapping_field
    ON eligibility.partner_value_mapping (
        canonical_field_name,
        is_active
    );

CREATE TABLE eligibility.partner_delivery_sla (
    partner_delivery_sla_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    partner_contract_id UUID NOT NULL
        REFERENCES eligibility.partner_contract(partner_contract_id)
        ON DELETE CASCADE,

    delivery_frequency TEXT NOT NULL,
    expected_delivery_time TIME,
    expected_timezone TEXT,

    max_delivery_delay_minutes INTEGER,
    max_processing_delay_minutes INTEGER,
    max_curation_delay_minutes INTEGER,

    attrition_update_sla_minutes INTEGER,
    correction_sla_minutes INTEGER,

    alert_after_minutes INTEGER,
    page_after_minutes INTEGER,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_delivery_sla_non_negative
        CHECK (
            COALESCE(max_delivery_delay_minutes, 0) >= 0
            AND COALESCE(max_processing_delay_minutes, 0) >= 0
            AND COALESCE(max_curation_delay_minutes, 0) >= 0
            AND COALESCE(attrition_update_sla_minutes, 0) >= 0
            AND COALESCE(correction_sla_minutes, 0) >= 0
            AND COALESCE(alert_after_minutes, 0) >= 0
            AND COALESCE(page_after_minutes, 0) >= 0
        )
);

CREATE UNIQUE INDEX idx_partner_delivery_sla_active
    ON eligibility.partner_delivery_sla (
        partner_contract_id
    )
    WHERE is_active = TRUE;

CREATE TABLE eligibility.partner_pii_policy (
    partner_pii_policy_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    partner_contract_id UUID NOT NULL
        REFERENCES eligibility.partner_contract(partner_contract_id)
        ON DELETE CASCADE,

    field_name TEXT NOT NULL,
    canonical_field_name TEXT,

    pii_classification TEXT NOT NULL,
    policy_action eligibility.pii_policy_action NOT NULL,

    requires_encryption BOOLEAN NOT NULL DEFAULT FALSE,
    requires_tokenization BOOLEAN NOT NULL DEFAULT FALSE,
    requires_masking BOOLEAN NOT NULL DEFAULT FALSE,

    allowed_in_raw BOOLEAN NOT NULL DEFAULT TRUE,
    allowed_in_canonical BOOLEAN NOT NULL DEFAULT TRUE,
    allowed_in_curated BOOLEAN NOT NULL DEFAULT FALSE,
    allowed_in_logs BOOLEAN NOT NULL DEFAULT FALSE,

    retention_policy_id TEXT,
    delete_after_days INTEGER,

    is_active BOOLEAN NOT NULL DEFAULT TRUE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_pii_policy_field_not_empty
        CHECK (length(trim(field_name)) > 0),

    CONSTRAINT chk_pii_delete_after_days_positive
        CHECK (
            delete_after_days IS NULL
            OR delete_after_days > 0
        )
);

CREATE UNIQUE INDEX idx_partner_pii_policy_field
    ON eligibility.partner_pii_policy (
        partner_contract_id,
        field_name
    );

CREATE INDEX idx_partner_pii_policy_action
    ON eligibility.partner_pii_policy (
        policy_action,
        is_active
    );

CREATE TABLE eligibility.partner_schema_change_log (
    partner_schema_change_log_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    partner_contract_id UUID NOT NULL
        REFERENCES eligibility.partner_contract(partner_contract_id)
        ON DELETE CASCADE,

    old_schema_version TEXT,
    new_schema_version TEXT NOT NULL,

    change_type eligibility.schema_change_type NOT NULL,
    change_description TEXT NOT NULL,

    requested_by TEXT,
    reviewed_by TEXT,
    approved_by TEXT,

    requested_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    approved_at TIMESTAMPTZ,
    deployed_at TIMESTAMPTZ,

    requires_privacy_review BOOLEAN NOT NULL DEFAULT FALSE,
    privacy_review_completed BOOLEAN NOT NULL DEFAULT FALSE,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT chk_schema_change_versions_different
        CHECK (
            old_schema_version IS NULL
            OR old_schema_version <> new_schema_version
        )
);

CREATE INDEX idx_partner_schema_change_contract
    ON eligibility.partner_schema_change_log (
        partner_contract_id,
        requested_at DESC
    );

CREATE INDEX idx_partner_schema_change_pending_privacy
    ON eligibility.partner_schema_change_log (
        requires_privacy_review,
        privacy_review_completed
    )
    WHERE requires_privacy_review = TRUE;

CREATE TRIGGER trg_partner_contract_updated_at
BEFORE UPDATE ON eligibility.partner_contract
FOR EACH ROW
EXECUTE FUNCTION eligibility.set_updated_at();

CREATE TRIGGER trg_partner_schema_version_updated_at
BEFORE UPDATE ON eligibility.partner_schema_version
FOR EACH ROW
EXECUTE FUNCTION eligibility.set_updated_at();

CREATE TRIGGER trg_partner_field_mapping_updated_at
BEFORE UPDATE ON eligibility.partner_field_mapping
FOR EACH ROW
EXECUTE FUNCTION eligibility.set_updated_at();

CREATE TRIGGER trg_partner_data_quality_rule_updated_at
BEFORE UPDATE ON eligibility.partner_data_quality_rule
FOR EACH ROW
EXECUTE FUNCTION eligibility.set_updated_at();

CREATE TRIGGER trg_partner_value_mapping_updated_at
BEFORE UPDATE ON eligibility.partner_value_mapping
FOR EACH ROW
EXECUTE FUNCTION eligibility.set_updated_at();

CREATE TRIGGER trg_partner_delivery_sla_updated_at
BEFORE UPDATE ON eligibility.partner_delivery_sla
FOR EACH ROW
EXECUTE FUNCTION eligibility.set_updated_at();

CREATE TRIGGER trg_partner_pii_policy_updated_at
BEFORE UPDATE ON eligibility.partner_pii_policy
FOR EACH ROW
EXECUTE FUNCTION eligibility.set_updated_at();

COMMIT;
