BEGIN;

DROP VIEW IF EXISTS eligibility.v_email_format_errors;
DROP VIEW IF EXISTS eligibility.v_duplicate_pii_email;

DROP FUNCTION IF EXISTS eligibility.evaluate_batch_dq(UUID);
DROP FUNCTION IF EXISTS eligibility.evaluate_canonical_record_dq(UUID);

COMMIT;
