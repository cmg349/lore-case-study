BEGIN;

DROP FUNCTION IF EXISTS eligibility.promote_batch(UUID, BOOLEAN);
DROP FUNCTION IF EXISTS eligibility.promote_canonical_record(UUID, BOOLEAN);
DROP FUNCTION IF EXISTS eligibility.insert_curated_history(eligibility.canonical_eligibility_record, UUID);
DROP FUNCTION IF EXISTS eligibility.upsert_curated_current(eligibility.canonical_eligibility_record);
DROP FUNCTION IF EXISTS eligibility.calculate_current_eligibility(eligibility.eligibility_status, DATE, DATE);
DROP FUNCTION IF EXISTS eligibility.close_current_history_record(UUID, TIMESTAMPTZ);
DROP FUNCTION IF EXISTS eligibility.find_curated_current_id_for_record(eligibility.canonical_eligibility_record);
DROP FUNCTION IF EXISTS eligibility.is_canonical_record_promotable(eligibility.canonical_eligibility_record);
DROP FUNCTION IF EXISTS eligibility.canonical_record_has_open_quarantine(UUID);
DROP FUNCTION IF EXISTS eligibility.insert_promotion_audit(
    eligibility.canonical_eligibility_record,
    eligibility.promotion_status,
    TEXT,
    TEXT,
    TEXT,
    UUID,
    UUID
);

DROP TRIGGER IF EXISTS trg_promotion_audit_updated_at
    ON eligibility.promotion_audit;

DROP INDEX IF EXISTS eligibility.idx_promotion_audit_partner_tenant;
DROP INDEX IF EXISTS eligibility.idx_promotion_audit_status_attempted_at;
DROP INDEX IF EXISTS eligibility.idx_promotion_audit_record_id;
DROP INDEX IF EXISTS eligibility.idx_promotion_audit_batch_id;
DROP INDEX IF EXISTS eligibility.idx_promotion_audit_success_lookup;

DROP TABLE IF EXISTS eligibility.promotion_audit;

DROP TYPE IF EXISTS eligibility.promotion_status;

COMMIT;
