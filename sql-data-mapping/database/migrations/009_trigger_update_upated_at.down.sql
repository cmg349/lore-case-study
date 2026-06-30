BEGIN;

DROP TRIGGER IF EXISTS trg_curated_eligibility_current_updated_at
ON eligibility.curated_eligibility_current;

DROP TRIGGER IF EXISTS trg_eligibility_person_pii_updated_at
ON eligibility.eligibility_person_pii;

DROP TRIGGER IF EXISTS trg_canonical_eligibility_record_updated_at
ON eligibility.canonical_eligibility_record;

DROP TRIGGER IF EXISTS trg_partner_eligibility_batch_updated_at
ON eligibility.partner_eligibility_batch;

DROP FUNCTION IF EXISTS eligibility.set_updated_at();

COMMIT;
