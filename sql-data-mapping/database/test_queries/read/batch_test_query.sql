SELECT *
FROM eligibility.reprocess_batch(
    (
        SELECT batch_id
        FROM eligibility.partner_eligibility_batch
        WHERE partner_id = 'partner_acme'
          AND tenant_id = 'tenant_001'
          AND org_id = 'org_hq'
          AND data_region = 'us-east-1'
        ORDER BY received_at DESC
        LIMIT 1
    )::UUID,
    'test reprocess after migration 019',
    FALSE
);