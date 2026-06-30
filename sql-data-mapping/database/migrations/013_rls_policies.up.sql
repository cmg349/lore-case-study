BEGIN;

CREATE OR REPLACE FUNCTION eligibility.current_partner_id()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.partner_id', true), '');
$$;

CREATE OR REPLACE FUNCTION eligibility.current_tenant_id()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.tenant_id', true), '');
$$;

CREATE OR REPLACE FUNCTION eligibility.current_org_id()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.org_id', true), '');
$$;

CREATE OR REPLACE FUNCTION eligibility.current_data_region()
RETURNS TEXT
LANGUAGE sql
STABLE
AS $$
    SELECT NULLIF(current_setting('app.data_region', true), '');
$$;

CREATE OR REPLACE FUNCTION eligibility.rls_scope_matches(
    p_partner_id TEXT,
    p_tenant_id TEXT,
    p_org_id TEXT,
    p_data_region TEXT
)
RETURNS BOOLEAN
LANGUAGE sql
STABLE
AS $$
    SELECT
        p_partner_id  IS NOT NULL
        AND p_tenant_id   IS NOT NULL
        AND p_org_id      IS NOT NULL
        AND p_data_region IS NOT NULL
        AND p_partner_id  = eligibility.current_partner_id()
        AND p_tenant_id   = eligibility.current_tenant_id()
        AND p_org_id      = eligibility.current_org_id()
        AND p_data_region = eligibility.current_data_region();
$$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'eligibility_app') THEN
        CREATE ROLE eligibility_app NOLOGIN;
    END IF;
END $$;

DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'eligibility_admin') THEN
        CREATE ROLE eligibility_admin NOLOGIN BYPASSRLS;
    END IF;
END $$;

ALTER TABLE eligibility.partner_contract ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.partner_contract FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_partner_contract_scope ON eligibility.partner_contract;
CREATE POLICY rls_partner_contract_scope
ON eligibility.partner_contract
FOR ALL
USING (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
)
WITH CHECK (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
);

ALTER TABLE eligibility.partner_eligibility_batch ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.partner_eligibility_batch FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_partner_eligibility_batch_scope ON eligibility.partner_eligibility_batch;
CREATE POLICY rls_partner_eligibility_batch_scope
ON eligibility.partner_eligibility_batch
FOR ALL
USING (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
)
WITH CHECK (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
);

ALTER TABLE eligibility.canonical_eligibility_record ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.canonical_eligibility_record FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_canonical_eligibility_record_scope ON eligibility.canonical_eligibility_record;
CREATE POLICY rls_canonical_eligibility_record_scope
ON eligibility.canonical_eligibility_record
FOR ALL
USING (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
)
WITH CHECK (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
);

ALTER TABLE eligibility.eligibility_person_pii ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.eligibility_person_pii FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_eligibility_person_pii_scope ON eligibility.eligibility_person_pii;
CREATE POLICY rls_eligibility_person_pii_scope
ON eligibility.eligibility_person_pii
FOR ALL
USING (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
)
WITH CHECK (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
);

ALTER TABLE eligibility.eligibility_identity_token ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.eligibility_identity_token FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_eligibility_identity_token_scope ON eligibility.eligibility_identity_token;
CREATE POLICY rls_eligibility_identity_token_scope
ON eligibility.eligibility_identity_token
FOR ALL
USING (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
)
WITH CHECK (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
);

ALTER TABLE eligibility.curated_eligibility_current ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.curated_eligibility_current FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_curated_eligibility_current_scope ON eligibility.curated_eligibility_current;
CREATE POLICY rls_curated_eligibility_current_scope
ON eligibility.curated_eligibility_current
FOR ALL
USING (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
)
WITH CHECK (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
);

ALTER TABLE eligibility.curated_eligibility_history ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.curated_eligibility_history FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_curated_eligibility_history_scope ON eligibility.curated_eligibility_history;
CREATE POLICY rls_curated_eligibility_history_scope
ON eligibility.curated_eligibility_history
FOR ALL
USING (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
)
WITH CHECK (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
);

ALTER TABLE eligibility.eligibility_quarantine ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.eligibility_quarantine FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_eligibility_quarantine_scope ON eligibility.eligibility_quarantine;
CREATE POLICY rls_eligibility_quarantine_scope
ON eligibility.eligibility_quarantine
FOR ALL
USING (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
)
WITH CHECK (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
);

ALTER TABLE eligibility.promotion_audit ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.promotion_audit FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_promotion_audit_scope ON eligibility.promotion_audit;
CREATE POLICY rls_promotion_audit_scope
ON eligibility.promotion_audit
FOR ALL
USING (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
)
WITH CHECK (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
);

ALTER TABLE eligibility.partner_schema_version ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.partner_schema_version FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_partner_schema_version_scope ON eligibility.partner_schema_version;
CREATE POLICY rls_partner_schema_version_scope
ON eligibility.partner_schema_version
FOR ALL
USING (
    EXISTS (
        SELECT 1
        FROM eligibility.partner_contract pc
        WHERE pc.partner_contract_id = partner_schema_version.partner_contract_id
          AND eligibility.rls_scope_matches(pc.partner_id, pc.tenant_id, pc.org_id, pc.data_region)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1
        FROM eligibility.partner_contract pc
        WHERE pc.partner_contract_id = partner_schema_version.partner_contract_id
          AND eligibility.rls_scope_matches(pc.partner_id, pc.tenant_id, pc.org_id, pc.data_region)
    )
);

ALTER TABLE eligibility.partner_field_mapping ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.partner_field_mapping FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_partner_field_mapping_scope ON eligibility.partner_field_mapping;
CREATE POLICY rls_partner_field_mapping_scope
ON eligibility.partner_field_mapping
FOR ALL
USING (
    EXISTS (
        SELECT 1
        FROM eligibility.partner_schema_version sv
        JOIN eligibility.partner_contract pc
          ON pc.partner_contract_id = sv.partner_contract_id
        WHERE sv.partner_schema_version_id = partner_field_mapping.partner_schema_version_id
          AND eligibility.rls_scope_matches(pc.partner_id, pc.tenant_id, pc.org_id, pc.data_region)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1
        FROM eligibility.partner_schema_version sv
        JOIN eligibility.partner_contract pc
          ON pc.partner_contract_id = sv.partner_contract_id
        WHERE sv.partner_schema_version_id = partner_field_mapping.partner_schema_version_id
          AND eligibility.rls_scope_matches(pc.partner_id, pc.tenant_id, pc.org_id, pc.data_region)
    )
);

ALTER TABLE eligibility.partner_data_quality_rule ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.partner_data_quality_rule FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_partner_data_quality_rule_scope ON eligibility.partner_data_quality_rule;
CREATE POLICY rls_partner_data_quality_rule_scope
ON eligibility.partner_data_quality_rule
FOR ALL
USING (
    EXISTS (
        SELECT 1
        FROM eligibility.partner_schema_version sv
        JOIN eligibility.partner_contract pc
          ON pc.partner_contract_id = sv.partner_contract_id
        WHERE sv.partner_schema_version_id = partner_data_quality_rule.partner_schema_version_id
          AND eligibility.rls_scope_matches(pc.partner_id, pc.tenant_id, pc.org_id, pc.data_region)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1
        FROM eligibility.partner_schema_version sv
        JOIN eligibility.partner_contract pc
          ON pc.partner_contract_id = sv.partner_contract_id
        WHERE sv.partner_schema_version_id = partner_data_quality_rule.partner_schema_version_id
          AND eligibility.rls_scope_matches(pc.partner_id, pc.tenant_id, pc.org_id, pc.data_region)
    )
);

ALTER TABLE eligibility.partner_value_mapping ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.partner_value_mapping FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_partner_value_mapping_scope ON eligibility.partner_value_mapping;
CREATE POLICY rls_partner_value_mapping_scope
ON eligibility.partner_value_mapping
FOR ALL
USING (
    EXISTS (
        SELECT 1
        FROM eligibility.partner_schema_version sv
        JOIN eligibility.partner_contract pc
          ON pc.partner_contract_id = sv.partner_contract_id
        WHERE sv.partner_schema_version_id = partner_value_mapping.partner_schema_version_id
          AND eligibility.rls_scope_matches(pc.partner_id, pc.tenant_id, pc.org_id, pc.data_region)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1
        FROM eligibility.partner_schema_version sv
        JOIN eligibility.partner_contract pc
          ON pc.partner_contract_id = sv.partner_contract_id
        WHERE sv.partner_schema_version_id = partner_value_mapping.partner_schema_version_id
          AND eligibility.rls_scope_matches(pc.partner_id, pc.tenant_id, pc.org_id, pc.data_region)
    )
);

ALTER TABLE eligibility.partner_delivery_sla ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.partner_delivery_sla FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_partner_delivery_sla_scope ON eligibility.partner_delivery_sla;
CREATE POLICY rls_partner_delivery_sla_scope
ON eligibility.partner_delivery_sla
FOR ALL
USING (
    EXISTS (
        SELECT 1
        FROM eligibility.partner_contract pc
        WHERE pc.partner_contract_id = partner_delivery_sla.partner_contract_id
          AND eligibility.rls_scope_matches(pc.partner_id, pc.tenant_id, pc.org_id, pc.data_region)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1
        FROM eligibility.partner_contract pc
        WHERE pc.partner_contract_id = partner_delivery_sla.partner_contract_id
          AND eligibility.rls_scope_matches(pc.partner_id, pc.tenant_id, pc.org_id, pc.data_region)
    )
);

ALTER TABLE eligibility.partner_pii_policy ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.partner_pii_policy FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_partner_pii_policy_scope ON eligibility.partner_pii_policy;
CREATE POLICY rls_partner_pii_policy_scope
ON eligibility.partner_pii_policy
FOR ALL
USING (
    EXISTS (
        SELECT 1
        FROM eligibility.partner_contract pc
        WHERE pc.partner_contract_id = partner_pii_policy.partner_contract_id
          AND eligibility.rls_scope_matches(pc.partner_id, pc.tenant_id, pc.org_id, pc.data_region)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1
        FROM eligibility.partner_contract pc
        WHERE pc.partner_contract_id = partner_pii_policy.partner_contract_id
          AND eligibility.rls_scope_matches(pc.partner_id, pc.tenant_id, pc.org_id, pc.data_region)
    )
);

ALTER TABLE eligibility.partner_schema_change_log ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.partner_schema_change_log FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_partner_schema_change_log_scope ON eligibility.partner_schema_change_log;
CREATE POLICY rls_partner_schema_change_log_scope
ON eligibility.partner_schema_change_log
FOR ALL
USING (
    EXISTS (
        SELECT 1
        FROM eligibility.partner_contract pc
        WHERE pc.partner_contract_id = partner_schema_change_log.partner_contract_id
          AND eligibility.rls_scope_matches(pc.partner_id, pc.tenant_id, pc.org_id, pc.data_region)
    )
)
WITH CHECK (
    EXISTS (
        SELECT 1
        FROM eligibility.partner_contract pc
        WHERE pc.partner_contract_id = partner_schema_change_log.partner_contract_id
          AND eligibility.rls_scope_matches(pc.partner_id, pc.tenant_id, pc.org_id, pc.data_region)
    )
);

COMMIT;
