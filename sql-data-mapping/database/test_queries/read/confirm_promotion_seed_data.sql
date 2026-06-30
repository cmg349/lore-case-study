SELECT
    partner_id,
    tenant_id,
    org_id,
    data_region,
    batch_status,
    record_count,
    valid_record_count,
    quarantined_record_count
FROM eligibility.partner_eligibility_batch
WHERE partner_id = 'partner_acme'
  AND tenant_id = 'tenant_001'
  AND org_id = 'org_hq'
  AND data_region = 'us-east-1';