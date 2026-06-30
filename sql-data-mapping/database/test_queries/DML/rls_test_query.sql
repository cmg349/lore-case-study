CREATE ROLE eligibility_app_test LOGIN PASSWORD 'dev_only_password';

GRANT USAGE ON SCHEMA eligibility TO eligibility_app_test;

GRANT SELECT, INSERT, UPDATE, DELETE
ON ALL TABLES IN SCHEMA eligibility
TO eligibility_app_test;

GRANT EXECUTE
ON ALL FUNCTIONS IN SCHEMA eligibility
TO eligibility_app_test;

--this is used for testing 017 migration for id verification 
GRANT SELECT, INSERT, UPDATE, DELETE
ON eligibility.identity_verification_request,
   eligibility.identity_verification_match_candidate,
   eligibility.identity_verification_decision
TO eligibility_app_test;
/*
--sanity check of RLS

SET ROLE eligibility_app_test;

SELECT *
FROM eligibility.curated_eligibility_current;
--should get 0 returns

--then set these
SET app.partner_id = 'partner_acme';
SET app.tenant_id = 'tenant_001';
SET app.org_id = 'org_hq';
SET app.data_region = 'us-east-1';

SELECT
    partner_employee_id,
    partner_person_id,
    eligibility_status,
    eligibility.calculate_current_eligibility(
        eligibility_status,
        eligibility_start_date,
        eligibility_end_date
    ) AS is_currently_eligible,
    dq_status
FROM eligibility.curated_eligibility_current
ORDER BY partner_employee_id;

--ioslation check
SET app.tenant_id = 'wrong_tenant';

SELECT *
FROM eligibility.curated_eligibility_current;
-- again should get 0 returns
*/