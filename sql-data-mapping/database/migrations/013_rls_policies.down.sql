BEGIN;

DROP POLICY IF EXISTS rls_partner_contract_scope ON eligibility.partner_contract;
DROP POLICY IF EXISTS rls_partner_eligibility_batch_scope ON eligibility.partner_eligibility_batch;
DROP POLICY IF EXISTS rls_canonical_eligibility_record_scope ON eligibility.canonical_eligibility_record;
DROP POLICY IF EXISTS rls_eligibility_person_pii_scope ON eligibility.eligibility_person_pii;
DROP POLICY IF EXISTS rls_eligibility_identity_token_scope ON eligibility.eligibility_identity_token;
DROP POLICY IF EXISTS rls_curated_eligibility_current_scope ON eligibility.curated_eligibility_current;
DROP POLICY IF EXISTS rls_curated_eligibility_history_scope ON eligibility.curated_eligibility_history;
DROP POLICY IF EXISTS rls_eligibility_quarantine_scope ON eligibility.eligibility_quarantine;
DROP POLICY IF EXISTS rls_promotion_audit_scope ON eligibility.promotion_audit;

DROP POLICY IF EXISTS rls_partner_schema_version_scope ON eligibility.partner_schema_version;
DROP POLICY IF EXISTS rls_partner_field_mapping_scope ON eligibility.partner_field_mapping;
DROP POLICY IF EXISTS rls_partner_data_quality_rule_scope ON eligibility.partner_data_quality_rule;
DROP POLICY IF EXISTS rls_partner_value_mapping_scope ON eligibility.partner_value_mapping;
DROP POLICY IF EXISTS rls_partner_delivery_sla_scope ON eligibility.partner_delivery_sla;
DROP POLICY IF EXISTS rls_partner_pii_policy_scope ON eligibility.partner_pii_policy;
DROP POLICY IF EXISTS rls_partner_schema_change_log_scope ON eligibility.partner_schema_change_log;

ALTER TABLE eligibility.partner_contract DISABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.partner_schema_version DISABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.partner_field_mapping DISABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.partner_data_quality_rule DISABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.partner_value_mapping DISABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.partner_delivery_sla DISABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.partner_pii_policy DISABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.partner_schema_change_log DISABLE ROW LEVEL SECURITY;

ALTER TABLE eligibility.partner_eligibility_batch DISABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.canonical_eligibility_record DISABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.eligibility_person_pii DISABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.eligibility_identity_token DISABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.curated_eligibility_current DISABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.curated_eligibility_history DISABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.eligibility_quarantine DISABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.promotion_audit DISABLE ROW LEVEL SECURITY;

DROP FUNCTION IF EXISTS eligibility.rls_scope_matches(TEXT, TEXT, TEXT, TEXT);
DROP FUNCTION IF EXISTS eligibility.rls_bypass_enabled();
DROP FUNCTION IF EXISTS eligibility.current_data_region();
DROP FUNCTION IF EXISTS eligibility.current_org_id();
DROP FUNCTION IF EXISTS eligibility.current_tenant_id();
DROP FUNCTION IF EXISTS eligibility.current_partner_id();

COMMIT;
