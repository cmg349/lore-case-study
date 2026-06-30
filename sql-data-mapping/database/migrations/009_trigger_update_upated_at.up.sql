BEGIN;

CREATE OR REPLACE FUNCTION eligibility.set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_partner_eligibility_batch_updated_at
BEFORE UPDATE ON eligibility.partner_eligibility_batch
FOR EACH ROW
EXECUTE FUNCTION eligibility.set_updated_at();

CREATE TRIGGER trg_canonical_eligibility_record_updated_at
BEFORE UPDATE ON eligibility.canonical_eligibility_record
FOR EACH ROW
EXECUTE FUNCTION eligibility.set_updated_at();

CREATE TRIGGER trg_eligibility_person_pii_updated_at
BEFORE UPDATE ON eligibility.eligibility_person_pii
FOR EACH ROW
EXECUTE FUNCTION eligibility.set_updated_at();

CREATE TRIGGER trg_curated_eligibility_current_updated_at
BEFORE UPDATE ON eligibility.curated_eligibility_current
FOR EACH ROW
EXECUTE FUNCTION eligibility.set_updated_at();

COMMIT;
