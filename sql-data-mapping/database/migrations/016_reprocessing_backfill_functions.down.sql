BEGIN;

DROP FUNCTION IF EXISTS eligibility.reprocess_resolved_quarantine(
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    BOOLEAN,
    TEXT
);

DROP FUNCTION IF EXISTS eligibility.reprocess_partner(
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    BOOLEAN,
    JSONB,
    TEXT
);

DROP FUNCTION IF EXISTS eligibility.reprocess_batch(
    UUID,
    TEXT,
    BOOLEAN,
    TEXT
);

DROP FUNCTION IF EXISTS eligibility.reprocess_job(UUID, BOOLEAN);

DROP FUNCTION IF EXISTS eligibility.create_reprocessing_job(
    TEXT,
    TEXT,
    TEXT,
    TEXT,
    eligibility.reprocessing_job_type,
    TEXT,
    UUID,
    UUID[],
    JSONB,
    TEXT
);

DROP FUNCTION IF EXISTS eligibility.refresh_reprocessing_job_counts(UUID);

DROP POLICY IF EXISTS rls_reprocessing_job_record_scope
    ON eligibility.reprocessing_job_record;

DROP POLICY IF EXISTS rls_reprocessing_job_scope
    ON eligibility.reprocessing_job;

DROP TRIGGER IF EXISTS trg_reprocessing_job_record_updated_at
    ON eligibility.reprocessing_job_record;

DROP TRIGGER IF EXISTS trg_reprocessing_job_updated_at
    ON eligibility.reprocessing_job;

DROP TABLE IF EXISTS eligibility.reprocessing_job_record;
DROP TABLE IF EXISTS eligibility.reprocessing_job;

DROP TYPE IF EXISTS eligibility.reprocessing_record_status;
DROP TYPE IF EXISTS eligibility.reprocessing_job_status;
DROP TYPE IF EXISTS eligibility.reprocessing_job_type;

COMMIT;
