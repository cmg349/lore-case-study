-- full teardown for acme-corp seed data
BEGIN;

DELETE FROM eligibility.identity_verification_decision   WHERE partner_id = 'acme-corp';
DELETE FROM eligibility.identity_verification_match_candidate WHERE partner_id = 'acme-corp';
DELETE FROM eligibility.identity_verification_request    WHERE partner_id = 'acme-corp';

DELETE FROM eligibility.promotion_audit                  WHERE partner_id = 'acme-corp';

DELETE FROM eligibility.curated_eligibility_history      WHERE partner_id = 'acme-corp';
DELETE FROM eligibility.curated_eligibility_current      WHERE partner_id = 'acme-corp';

DELETE FROM eligibility.eligibility_quarantine           WHERE partner_id = 'acme-corp';
DELETE FROM eligibility.eligibility_identity_token       WHERE partner_id = 'acme-corp';
DELETE FROM eligibility.eligibility_person_pii           WHERE partner_id = 'acme-corp';
DELETE FROM eligibility.canonical_eligibility_record     WHERE partner_id = 'acme-corp';

DELETE FROM eligibility.partner_eligibility_batch        WHERE partner_id = 'acme-corp';
DELETE FROM eligibility.partner_contract                 WHERE partner_id = 'acme-corp';

COMMIT;