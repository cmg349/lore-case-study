BEGIN;

DROP PROCEDURE IF EXISTS eligibility.enforce_canonical_retention(DATE, BOOLEAN, INTEGER);
DROP PROCEDURE IF EXISTS eligibility.sweep_expired_curated_records(DATE, INTEGER);
DROP PROCEDURE IF EXISTS eligibility.promote_batch_chunked(UUID, BOOLEAN, INTEGER);

DROP INDEX IF EXISTS eligibility.idx_canonical_delete_after_date;
DROP INDEX IF EXISTS eligibility.idx_promotion_audit_promoted_at;
DROP INDEX IF EXISTS eligibility.idx_promotion_audit_attempted_at_brin;

COMMIT;
