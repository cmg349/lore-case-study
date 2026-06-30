BEGIN;

DROP TRIGGER IF EXISTS trg_partner_pii_policy_updated_at
ON eligibility.partner_pii_policy;

DROP TRIGGER IF EXISTS trg_partner_delivery_sla_updated_at
ON eligibility.partner_delivery_sla;

DROP TRIGGER IF EXISTS trg_partner_value_mapping_updated_at
ON eligibility.partner_value_mapping;

DROP TRIGGER IF EXISTS trg_partner_data_quality_rule_updated_at
ON eligibility.partner_data_quality_rule;

DROP TRIGGER IF EXISTS trg_partner_field_mapping_updated_at
ON eligibility.partner_field_mapping;

DROP TRIGGER IF EXISTS trg_partner_schema_version_updated_at
ON eligibility.partner_schema_version;

DROP TRIGGER IF EXISTS trg_partner_contract_updated_at
ON eligibility.partner_contract;

DROP TABLE IF EXISTS eligibility.partner_schema_change_log;
DROP TABLE IF EXISTS eligibility.partner_pii_policy;
DROP TABLE IF EXISTS eligibility.partner_delivery_sla;
DROP TABLE IF EXISTS eligibility.partner_value_mapping;
DROP TABLE IF EXISTS eligibility.partner_data_quality_rule;
DROP TABLE IF EXISTS eligibility.partner_field_mapping;
DROP TABLE IF EXISTS eligibility.partner_schema_version;
DROP TABLE IF EXISTS eligibility.partner_contract;

DROP TYPE IF EXISTS eligibility.schema_change_type;
DROP TYPE IF EXISTS eligibility.pii_policy_action;
DROP TYPE IF EXISTS eligibility.validation_severity;
DROP TYPE IF EXISTS eligibility.validation_rule_type;
DROP TYPE IF EXISTS eligibility.field_requirement_level;
DROP TYPE IF EXISTS eligibility.contract_status;

COMMIT;
