BEGIN;

DROP VIEW IF EXISTS eligibility.v_open_quarantine_issues;
DROP VIEW IF EXISTS eligibility.v_current_active_eligibility;
DROP VIEW IF EXISTS eligibility.v_batch_quality_summary;

COMMIT;
