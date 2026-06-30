INSERT INTO eligibility.eligibility_quarantine (
    batch_id,
    eligibility_record_id,
    partner_id,
    tenant_id,
    org_id,
    data_region,
    source_row_number,
    raw_record_reference,
    canonical_record_reference,
    error_code,
    error_severity,
    failed_field,
    failure_reason,
    requires_partner_action,
    review_status
)
SELECT
    batch_id,
    eligibility_record_id,
    partner_id,
    tenant_id,
    org_id,
    data_region,
    source_row_number,
    CONCAT('batch_id=', batch_id, ';row=', source_row_number),
    CONCAT('eligibility_record_id=', eligibility_record_id),
    'INVALID_ELIGIBILITY_DATE_RANGE',
    'sev_3',
    'eligibility_end_date',
    'eligibility_end_date is earlier than eligibility_start_date',
    TRUE,
    'partner_action_required'
FROM eligibility.canonical_eligibility_record
WHERE eligibility_end_date IS NOT NULL
  AND eligibility_end_date < eligibility_start_date;