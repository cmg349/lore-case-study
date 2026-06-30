BEGIN;

CREATE OR REPLACE VIEW eligibility.v_batch_quality_summary AS
SELECT
    b.batch_id,
    b.partner_id,
    b.tenant_id,
    b.org_id,
    b.data_region,
    b.source_file_name,
    b.source_schema_version,
    b.delivery_type,
    b.is_full_snapshot,
    b.received_at,
    b.processing_completed_at,
    b.batch_status,
    b.record_count,
    b.valid_record_count,
    b.valid_with_warnings_record_count,
    b.quarantined_record_count,
    b.rejected_record_count,
    b.dq_error_count,
    b.dq_warning_count,
    CASE
        WHEN b.record_count IS NULL OR b.record_count = 0 THEN NULL
        ELSE ROUND(
            ((COALESCE(b.valid_record_count, 0)
              + COALESCE(b.valid_with_warnings_record_count, 0))::NUMERIC
             / b.record_count::NUMERIC) * 100,
            2
        )
    END AS accepted_record_percentage
FROM eligibility.partner_eligibility_batch b;

CREATE OR REPLACE VIEW eligibility.v_current_active_eligibility AS
SELECT
    curated_eligibility_id,
    eligibility_record_id,
    partner_id,
    tenant_id,
    org_id,
    data_region,
    partner_employee_id,
    partner_person_id,
    partner_member_id,
    eligibility_status,
    (
        eligibility_status::TEXT = 'active'
        AND (eligibility_start_date IS NULL OR eligibility_start_date <= CURRENT_DATE)
        AND (eligibility_end_date   IS NULL OR eligibility_end_date   >= CURRENT_DATE)
    ) AS is_currently_eligible,
    eligibility_start_date,
    eligibility_end_date,
    eligibility_group_code,
    benefit_plan_id,
    person_relationship_type,
    identity_match_policy_id,
    source_last_updated_at,
    curated_at
FROM eligibility.curated_eligibility_current
WHERE eligibility_status = 'active'
  AND (eligibility_start_date IS NULL OR eligibility_start_date <= CURRENT_DATE)
  AND (eligibility_end_date IS NULL OR eligibility_end_date >= CURRENT_DATE);

CREATE OR REPLACE VIEW eligibility.v_open_quarantine_issues AS
SELECT
    q.quarantine_id,
    q.batch_id,
    q.partner_id,
    q.tenant_id,
    q.org_id,
    q.data_region,
    q.source_row_number,
    q.error_code,
    q.error_severity,
    q.failed_field,
    q.failure_reason,
    q.requires_partner_action,
    q.review_status,
    q.created_at
FROM eligibility.eligibility_quarantine q
WHERE q.review_status IN ('open', 'in_review', 'partner_action_required');

COMMIT;
