SELECT
    eligibility_record_id,
    partner_employee_id,
    partner_person_id,
    partner_member_id,
    person_relationship_type,
    eligibility_status,
    dq_status,
    requires_manual_review,
    contains_prohibited_pii,
    tokenization_status,
    encryption_status
FROM eligibility.canonical_eligibility_record
WHERE partner_id = 'partner_acme'
ORDER BY source_row_number;