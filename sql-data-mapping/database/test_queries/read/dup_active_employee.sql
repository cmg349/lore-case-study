SELECT
    partner_id,
    tenant_id,
    partner_employee_id,
    COUNT(*) AS active_record_count
FROM eligibility.canonical_eligibility_record
WHERE eligibility_status = 'active'
  AND dq_status IN ('valid', 'valid_with_warnings')
GROUP BY
    partner_id,
    tenant_id,
    partner_employee_id
HAVING COUNT(*) > 1;