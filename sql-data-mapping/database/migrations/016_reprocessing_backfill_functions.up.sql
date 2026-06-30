BEGIN;

DO $$
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'eligibility'
          AND t.typname = 'reprocessing_job_type'
    ) THEN
        CREATE TYPE eligibility.reprocessing_job_type AS ENUM (
            'batch',
            'partner',
            'resolved_quarantine',
            'record_set'
        );
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'eligibility'
          AND t.typname = 'reprocessing_job_status'
    ) THEN
        CREATE TYPE eligibility.reprocessing_job_status AS ENUM (
            'queued',
            'running',
            'completed',
            'completed_with_failures',
            'failed',
            'cancelled'
        );
    END IF;

    IF NOT EXISTS (
        SELECT 1
        FROM pg_type t
        JOIN pg_namespace n ON n.oid = t.typnamespace
        WHERE n.nspname = 'eligibility'
          AND t.typname = 'reprocessing_record_status'
    ) THEN
        CREATE TYPE eligibility.reprocessing_record_status AS ENUM (
            'queued',
            'processing',
            'promoted',
            'skipped_duplicate',
            'failed_validation',
            'failed_system'
        );
    END IF;
END $$;

CREATE TABLE IF NOT EXISTS eligibility.reprocessing_job (
    reprocessing_job_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    partner_id TEXT NOT NULL,
    tenant_id TEXT NOT NULL,
    org_id TEXT NOT NULL,
    data_region TEXT NOT NULL,

    job_type eligibility.reprocessing_job_type NOT NULL,
    job_status eligibility.reprocessing_job_status NOT NULL DEFAULT 'queued',

    requested_by TEXT NOT NULL DEFAULT current_user,
    reason TEXT NOT NULL,

    source_batch_id UUID NULL
        REFERENCES eligibility.partner_eligibility_batch(batch_id)
        ON DELETE SET NULL,

    filter_config JSONB NOT NULL DEFAULT '{}'::JSONB,

    total_records INTEGER NOT NULL DEFAULT 0,
    queued_count INTEGER NOT NULL DEFAULT 0,
    processed_count INTEGER NOT NULL DEFAULT 0,
    promoted_count INTEGER NOT NULL DEFAULT 0,
    skipped_duplicate_count INTEGER NOT NULL DEFAULT 0,
    failed_validation_count INTEGER NOT NULL DEFAULT 0,
    failed_system_count INTEGER NOT NULL DEFAULT 0,

    started_at TIMESTAMPTZ NULL,
    completed_at TIMESTAMPTZ NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT reprocessing_job_counts_non_negative_chk
        CHECK (
            total_records >= 0
            AND queued_count >= 0
            AND processed_count >= 0
            AND promoted_count >= 0
            AND skipped_duplicate_count >= 0
            AND failed_validation_count >= 0
            AND failed_system_count >= 0
        ),

    CONSTRAINT reprocessing_job_completed_timestamp_chk
        CHECK (
            job_status NOT IN ('completed', 'completed_with_failures', 'failed', 'cancelled')
            OR completed_at IS NOT NULL
        ),

    CONSTRAINT reprocessing_job_reason_not_empty_chk
        CHECK (length(trim(reason)) > 0)
);

CREATE INDEX IF NOT EXISTS idx_reprocessing_job_scope_created_at
    ON eligibility.reprocessing_job (partner_id, tenant_id, org_id, data_region, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_reprocessing_job_status_created_at
    ON eligibility.reprocessing_job (job_status, created_at DESC);

CREATE INDEX IF NOT EXISTS idx_reprocessing_job_source_batch_id
    ON eligibility.reprocessing_job (source_batch_id)
    WHERE source_batch_id IS NOT NULL;

CREATE TABLE IF NOT EXISTS eligibility.reprocessing_job_record (
    reprocessing_job_record_id UUID PRIMARY KEY DEFAULT gen_random_uuid(),

    reprocessing_job_id UUID NOT NULL
        REFERENCES eligibility.reprocessing_job(reprocessing_job_id)
        ON DELETE CASCADE,

    batch_id UUID NOT NULL
        REFERENCES eligibility.partner_eligibility_batch(batch_id)
        ON DELETE CASCADE,

    eligibility_record_id UUID NOT NULL
        REFERENCES eligibility.canonical_eligibility_record(eligibility_record_id)
        ON DELETE CASCADE,

    partner_id TEXT NOT NULL,
    tenant_id TEXT NOT NULL,
    org_id TEXT NOT NULL,
    data_region TEXT NOT NULL,

    record_status eligibility.reprocessing_record_status NOT NULL DEFAULT 'queued',

    promotion_attempt_id UUID NULL
        REFERENCES eligibility.promotion_audit(promotion_attempt_id)
        ON DELETE SET NULL,

    promotion_status eligibility.promotion_status NULL,
    failure_code TEXT NULL,
    failure_reason TEXT NULL,

    queued_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    processed_at TIMESTAMPTZ NULL,

    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),

    CONSTRAINT reprocessing_job_record_unique_record_per_job_uq
        UNIQUE (reprocessing_job_id, eligibility_record_id),

    CONSTRAINT reprocessing_job_record_processed_timestamp_chk
        CHECK (
            record_status IN ('queued', 'processing')
            OR processed_at IS NOT NULL
        ),

    CONSTRAINT reprocessing_job_record_failure_reason_chk
        CHECK (
            record_status NOT IN ('failed_validation', 'failed_system')
            OR failure_reason IS NOT NULL
        )
);

CREATE INDEX IF NOT EXISTS idx_reprocessing_job_record_job_status
    ON eligibility.reprocessing_job_record (reprocessing_job_id, record_status);

CREATE INDEX IF NOT EXISTS idx_reprocessing_job_record_record_id
    ON eligibility.reprocessing_job_record (eligibility_record_id);

CREATE INDEX IF NOT EXISTS idx_reprocessing_job_record_scope
    ON eligibility.reprocessing_job_record (partner_id, tenant_id, org_id, data_region);

CREATE INDEX IF NOT EXISTS idx_reprocessing_job_record_promotion_attempt
    ON eligibility.reprocessing_job_record (promotion_attempt_id)
    WHERE promotion_attempt_id IS NOT NULL;

DROP TRIGGER IF EXISTS trg_reprocessing_job_updated_at
    ON eligibility.reprocessing_job;

CREATE TRIGGER trg_reprocessing_job_updated_at
BEFORE UPDATE ON eligibility.reprocessing_job
FOR EACH ROW
EXECUTE FUNCTION eligibility.set_updated_at();

DROP TRIGGER IF EXISTS trg_reprocessing_job_record_updated_at
    ON eligibility.reprocessing_job_record;

CREATE TRIGGER trg_reprocessing_job_record_updated_at
BEFORE UPDATE ON eligibility.reprocessing_job_record
FOR EACH ROW
EXECUTE FUNCTION eligibility.set_updated_at();

ALTER TABLE eligibility.reprocessing_job ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.reprocessing_job FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_reprocessing_job_scope ON eligibility.reprocessing_job;
CREATE POLICY rls_reprocessing_job_scope
ON eligibility.reprocessing_job
FOR ALL
USING (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
)
WITH CHECK (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
);

ALTER TABLE eligibility.reprocessing_job_record ENABLE ROW LEVEL SECURITY;
ALTER TABLE eligibility.reprocessing_job_record FORCE ROW LEVEL SECURITY;
DROP POLICY IF EXISTS rls_reprocessing_job_record_scope ON eligibility.reprocessing_job_record;
CREATE POLICY rls_reprocessing_job_record_scope
ON eligibility.reprocessing_job_record
FOR ALL
USING (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
)
WITH CHECK (
    eligibility.rls_scope_matches(partner_id, tenant_id, org_id, data_region)
);

CREATE OR REPLACE FUNCTION eligibility.refresh_reprocessing_job_counts(
    p_reprocessing_job_id UUID
)
RETURNS VOID
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_counts RECORD;
BEGIN
    SELECT
        COUNT(*)::INTEGER AS total_records,
        COUNT(*) FILTER (WHERE r.record_status = 'queued')::INTEGER AS queued_count,
        COUNT(*) FILTER (WHERE r.record_status IN ('promoted', 'skipped_duplicate', 'failed_validation', 'failed_system'))::INTEGER AS processed_count,
        COUNT(*) FILTER (WHERE r.record_status = 'promoted')::INTEGER AS promoted_count,
        COUNT(*) FILTER (WHERE r.record_status = 'skipped_duplicate')::INTEGER AS skipped_duplicate_count,
        COUNT(*) FILTER (WHERE r.record_status = 'failed_validation')::INTEGER AS failed_validation_count,
        COUNT(*) FILTER (WHERE r.record_status = 'failed_system')::INTEGER AS failed_system_count
    INTO v_counts
    FROM eligibility.reprocessing_job_record r
    WHERE r.reprocessing_job_id = p_reprocessing_job_id;

    UPDATE eligibility.reprocessing_job j
    SET total_records = COALESCE(v_counts.total_records, 0),
        queued_count = COALESCE(v_counts.queued_count, 0),
        processed_count = COALESCE(v_counts.processed_count, 0),
        promoted_count = COALESCE(v_counts.promoted_count, 0),
        skipped_duplicate_count = COALESCE(v_counts.skipped_duplicate_count, 0),
        failed_validation_count = COALESCE(v_counts.failed_validation_count, 0),
        failed_system_count = COALESCE(v_counts.failed_system_count, 0)
    WHERE j.reprocessing_job_id = p_reprocessing_job_id;
END;
$$;

CREATE OR REPLACE FUNCTION eligibility.create_reprocessing_job(
    p_partner_id TEXT,
    p_tenant_id TEXT,
    p_org_id TEXT,
    p_data_region TEXT,
    p_job_type eligibility.reprocessing_job_type,
    p_reason TEXT,
    p_source_batch_id UUID DEFAULT NULL,
    p_eligibility_record_ids UUID[] DEFAULT NULL,
    p_filter_config JSONB DEFAULT '{}'::JSONB,
    p_requested_by TEXT DEFAULT current_user
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_job_id UUID;
    v_batch_scope RECORD;
BEGIN
    IF NOT eligibility.rls_scope_matches(p_partner_id, p_tenant_id, p_org_id, p_data_region) THEN
        RAISE EXCEPTION 'Requested reprocessing scope does not match current RLS session scope.'
            USING ERRCODE = '42501';
    END IF;

    IF p_reason IS NULL OR length(trim(p_reason)) = 0 THEN
        RAISE EXCEPTION 'Reprocessing reason is required.'
            USING ERRCODE = '23514';
    END IF;

    IF p_job_type::TEXT = 'batch' AND p_source_batch_id IS NULL THEN
        RAISE EXCEPTION 'source_batch_id is required for batch reprocessing jobs.'
            USING ERRCODE = '23502';
    END IF;

    IF p_job_type::TEXT = 'record_set'
       AND (p_eligibility_record_ids IS NULL OR cardinality(p_eligibility_record_ids) = 0) THEN
        RAISE EXCEPTION 'eligibility_record_ids is required for record_set reprocessing jobs.'
            USING ERRCODE = '23502';
    END IF;

    IF p_source_batch_id IS NOT NULL THEN
        SELECT b.partner_id,
               b.tenant_id,
               b.org_id,
               b.data_region
        INTO v_batch_scope
        FROM eligibility.partner_eligibility_batch b
        WHERE b.batch_id = p_source_batch_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Partner eligibility batch % not found or not visible under current RLS scope.', p_source_batch_id
                USING ERRCODE = 'P0002';
        END IF;

        IF v_batch_scope.partner_id <> p_partner_id
           OR v_batch_scope.tenant_id <> p_tenant_id
           OR v_batch_scope.org_id <> p_org_id
           OR v_batch_scope.data_region <> p_data_region THEN
            RAISE EXCEPTION 'source_batch_id scope does not match requested reprocessing scope.'
                USING ERRCODE = '42501';
        END IF;
    END IF;

    INSERT INTO eligibility.reprocessing_job (
        partner_id,
        tenant_id,
        org_id,
        data_region,
        job_type,
        job_status,
        requested_by,
        reason,
        source_batch_id,
        filter_config
    )
    VALUES (
        p_partner_id,
        p_tenant_id,
        p_org_id,
        p_data_region,
        p_job_type,
        'queued',
        COALESCE(NULLIF(trim(p_requested_by), ''), current_user),
        p_reason,
        p_source_batch_id,
        COALESCE(p_filter_config, '{}'::JSONB)
    )
    RETURNING reprocessing_job_id INTO v_job_id;

    IF p_job_type::TEXT = 'batch' THEN
        INSERT INTO eligibility.reprocessing_job_record (
            reprocessing_job_id,
            batch_id,
            eligibility_record_id,
            partner_id,
            tenant_id,
            org_id,
            data_region
        )
        SELECT
            v_job_id,
            r.batch_id,
            r.eligibility_record_id,
            r.partner_id,
            r.tenant_id,
            r.org_id,
            r.data_region
        FROM eligibility.canonical_eligibility_record r
        WHERE r.batch_id = p_source_batch_id
          AND eligibility.rls_scope_matches(r.partner_id, r.tenant_id, r.org_id, r.data_region)
        ORDER BY r.source_row_number NULLS LAST, r.created_at, r.eligibility_record_id
        ON CONFLICT (reprocessing_job_id, eligibility_record_id) DO NOTHING;

    ELSIF p_job_type::TEXT = 'partner' THEN
        INSERT INTO eligibility.reprocessing_job_record (
            reprocessing_job_id,
            batch_id,
            eligibility_record_id,
            partner_id,
            tenant_id,
            org_id,
            data_region
        )
        SELECT
            v_job_id,
            r.batch_id,
            r.eligibility_record_id,
            r.partner_id,
            r.tenant_id,
            r.org_id,
            r.data_region
        FROM eligibility.canonical_eligibility_record r
        WHERE r.partner_id = p_partner_id
          AND r.tenant_id = p_tenant_id
          AND r.org_id = p_org_id
          AND r.data_region = p_data_region
          AND eligibility.rls_scope_matches(r.partner_id, r.tenant_id, r.org_id, r.data_region)
          AND (
              COALESCE((p_filter_config ->> 'only_currently_valid_dq')::BOOLEAN, FALSE) = FALSE
              OR r.dq_status::TEXT IN ('valid', 'valid_with_warnings')
          )
        ORDER BY r.created_at, r.eligibility_record_id
        ON CONFLICT (reprocessing_job_id, eligibility_record_id) DO NOTHING;

    ELSIF p_job_type::TEXT = 'resolved_quarantine' THEN
        INSERT INTO eligibility.reprocessing_job_record (
            reprocessing_job_id,
            batch_id,
            eligibility_record_id,
            partner_id,
            tenant_id,
            org_id,
            data_region
        )
        SELECT DISTINCT
            v_job_id,
            r.batch_id,
            r.eligibility_record_id,
            r.partner_id,
            r.tenant_id,
            r.org_id,
            r.data_region
        FROM eligibility.canonical_eligibility_record r
        JOIN eligibility.eligibility_quarantine q
          ON q.eligibility_record_id = r.eligibility_record_id
        WHERE r.partner_id = p_partner_id
          AND r.tenant_id = p_tenant_id
          AND r.org_id = p_org_id
          AND r.data_region = p_data_region
          AND q.review_status::TEXT IN ('resolved', 'closed', 'ignored')
          AND eligibility.rls_scope_matches(r.partner_id, r.tenant_id, r.org_id, r.data_region)
        ORDER BY r.eligibility_record_id
        ON CONFLICT (reprocessing_job_id, eligibility_record_id) DO NOTHING;

    ELSIF p_job_type::TEXT = 'record_set' THEN
        INSERT INTO eligibility.reprocessing_job_record (
            reprocessing_job_id,
            batch_id,
            eligibility_record_id,
            partner_id,
            tenant_id,
            org_id,
            data_region
        )
        SELECT
            v_job_id,
            r.batch_id,
            r.eligibility_record_id,
            r.partner_id,
            r.tenant_id,
            r.org_id,
            r.data_region
        FROM eligibility.canonical_eligibility_record r
        WHERE r.eligibility_record_id = ANY(p_eligibility_record_ids)
          AND r.partner_id = p_partner_id
          AND r.tenant_id = p_tenant_id
          AND r.org_id = p_org_id
          AND r.data_region = p_data_region
          AND eligibility.rls_scope_matches(r.partner_id, r.tenant_id, r.org_id, r.data_region)
        ORDER BY r.created_at, r.eligibility_record_id
        ON CONFLICT (reprocessing_job_id, eligibility_record_id) DO NOTHING;
    END IF;

    PERFORM eligibility.refresh_reprocessing_job_counts(v_job_id);

    RETURN v_job_id;
END;
$$;

CREATE OR REPLACE FUNCTION eligibility.reprocess_job(
    p_reprocessing_job_id UUID,
    p_force_reprocess BOOLEAN DEFAULT FALSE
)
RETURNS TABLE (
    reprocessing_job_id UUID,
    total_records INTEGER,
    processed_count INTEGER,
    promoted_count INTEGER,
    skipped_duplicate_count INTEGER,
    failed_validation_count INTEGER,
    failed_system_count INTEGER
)
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_job eligibility.reprocessing_job;
    v_job_record RECORD;
    v_audit_id UUID;
    v_audit RECORD;
BEGIN
    SELECT j.*
    INTO v_job
    FROM eligibility.reprocessing_job j
    WHERE j.reprocessing_job_id = p_reprocessing_job_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Reprocessing job % not found or not visible under current RLS scope.', p_reprocessing_job_id
            USING ERRCODE = 'P0002';
    END IF;

    IF v_job.job_status::TEXT = 'cancelled' THEN
        RAISE EXCEPTION 'Reprocessing job % is cancelled and cannot be executed.', p_reprocessing_job_id
            USING ERRCODE = '55000';
    END IF;

    UPDATE eligibility.reprocessing_job j
    SET job_status = 'running',
        started_at = COALESCE(j.started_at, now()),
        completed_at = NULL
    WHERE j.reprocessing_job_id = p_reprocessing_job_id;

    FOR v_job_record IN
        SELECT r.*
        FROM eligibility.reprocessing_job_record r
        WHERE r.reprocessing_job_id = p_reprocessing_job_id
          AND (
              p_force_reprocess = TRUE
              OR r.record_status = 'queued'
          )
        ORDER BY r.queued_at, r.reprocessing_job_record_id
        FOR UPDATE
    LOOP
        UPDATE eligibility.reprocessing_job_record r
        SET record_status = 'processing',
            promotion_attempt_id = NULL,
            promotion_status = NULL,
            failure_code = NULL,
            failure_reason = NULL,
            processed_at = NULL
        WHERE r.reprocessing_job_record_id = v_job_record.reprocessing_job_record_id;

        BEGIN
            v_audit_id := eligibility.promote_canonical_record(
                v_job_record.eligibility_record_id,
                p_force_reprocess
            );

            SELECT a.promotion_attempt_id,
                   a.promotion_status,
                   a.failure_code,
                   a.failure_reason
            INTO v_audit
            FROM eligibility.promotion_audit a
            WHERE a.promotion_attempt_id = v_audit_id;

            IF NOT FOUND THEN
                UPDATE eligibility.reprocessing_job_record r
                SET record_status = 'failed_system',
                    promotion_attempt_id = v_audit_id,
                    failure_code = 'PROMOTION_AUDIT_NOT_FOUND',
                    failure_reason = 'Promotion function returned an audit id that could not be found.',
                    processed_at = now()
                WHERE r.reprocessing_job_record_id = v_job_record.reprocessing_job_record_id;
            ELSE
                UPDATE eligibility.reprocessing_job_record r
                SET record_status = v_audit.promotion_status::TEXT::eligibility.reprocessing_record_status,
                    promotion_attempt_id = v_audit.promotion_attempt_id,
                    promotion_status = v_audit.promotion_status,
                    failure_code = v_audit.failure_code,
                    failure_reason = v_audit.failure_reason,
                    processed_at = now()
                WHERE r.reprocessing_job_record_id = v_job_record.reprocessing_job_record_id;
            END IF;

        EXCEPTION
            WHEN OTHERS THEN
                UPDATE eligibility.reprocessing_job_record r
                SET record_status = 'failed_system',
                    failure_code = SQLSTATE,
                    failure_reason = SQLERRM,
                    processed_at = now()
                WHERE r.reprocessing_job_record_id = v_job_record.reprocessing_job_record_id;
        END;
    END LOOP;

    PERFORM eligibility.refresh_reprocessing_job_counts(p_reprocessing_job_id);

    UPDATE eligibility.reprocessing_job j
    SET job_status = CASE
            WHEN j.failed_system_count > 0 OR j.failed_validation_count > 0 THEN 'completed_with_failures'::eligibility.reprocessing_job_status
            ELSE 'completed'::eligibility.reprocessing_job_status
        END,
        completed_at = now()
    WHERE j.reprocessing_job_id = p_reprocessing_job_id;

    RETURN QUERY
    SELECT
        j.reprocessing_job_id,
        j.total_records,
        j.processed_count,
        j.promoted_count,
        j.skipped_duplicate_count,
        j.failed_validation_count,
        j.failed_system_count
    FROM eligibility.reprocessing_job j
    WHERE j.reprocessing_job_id = p_reprocessing_job_id;
END;
$$;

CREATE OR REPLACE FUNCTION eligibility.reprocess_batch(
    p_batch_id UUID,
    p_reason TEXT DEFAULT 'manual batch reprocessing',
    p_force_reprocess BOOLEAN DEFAULT FALSE,
    p_requested_by TEXT DEFAULT current_user
)
RETURNS TABLE (
    reprocessing_job_id UUID,
    batch_id UUID,
    total_records INTEGER,
    processed_count INTEGER,
    promoted_count INTEGER,
    skipped_duplicate_count INTEGER,
    failed_validation_count INTEGER,
    failed_system_count INTEGER
)
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_batch eligibility.partner_eligibility_batch;
    v_job_id UUID;
BEGIN
    SELECT b.*
    INTO v_batch
    FROM eligibility.partner_eligibility_batch b
    WHERE b.batch_id = p_batch_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Partner eligibility batch % not found or not visible under current RLS scope.', p_batch_id
            USING ERRCODE = 'P0002';
    END IF;

    v_job_id := eligibility.create_reprocessing_job(
        v_batch.partner_id,
        v_batch.tenant_id,
        v_batch.org_id,
        v_batch.data_region,
        'batch',
        p_reason,
        p_batch_id,
        NULL,
        jsonb_build_object('source', 'reprocess_batch'),
        p_requested_by
    );

    RETURN QUERY
    SELECT
        r.reprocessing_job_id,
        p_batch_id,
        r.total_records,
        r.processed_count,
        r.promoted_count,
        r.skipped_duplicate_count,
        r.failed_validation_count,
        r.failed_system_count
    FROM eligibility.reprocess_job(v_job_id, p_force_reprocess) r;
END;
$$;

CREATE OR REPLACE FUNCTION eligibility.reprocess_partner(
    p_partner_id TEXT,
    p_tenant_id TEXT,
    p_org_id TEXT,
    p_data_region TEXT,
    p_reason TEXT DEFAULT 'manual partner reprocessing',
    p_force_reprocess BOOLEAN DEFAULT FALSE,
    p_filter_config JSONB DEFAULT '{}'::JSONB,
    p_requested_by TEXT DEFAULT current_user
)
RETURNS TABLE (
    reprocessing_job_id UUID,
    total_records INTEGER,
    processed_count INTEGER,
    promoted_count INTEGER,
    skipped_duplicate_count INTEGER,
    failed_validation_count INTEGER,
    failed_system_count INTEGER
)
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_job_id UUID;
BEGIN
    v_job_id := eligibility.create_reprocessing_job(
        p_partner_id,
        p_tenant_id,
        p_org_id,
        p_data_region,
        'partner',
        p_reason,
        NULL,
        NULL,
        COALESCE(p_filter_config, '{}'::JSONB),
        p_requested_by
    );

    RETURN QUERY
    SELECT
        r.reprocessing_job_id,
        r.total_records,
        r.processed_count,
        r.promoted_count,
        r.skipped_duplicate_count,
        r.failed_validation_count,
        r.failed_system_count
    FROM eligibility.reprocess_job(v_job_id, p_force_reprocess) r;
END;
$$;

CREATE OR REPLACE FUNCTION eligibility.reprocess_resolved_quarantine(
    p_partner_id TEXT,
    p_tenant_id TEXT,
    p_org_id TEXT,
    p_data_region TEXT,
    p_reason TEXT DEFAULT 'manual resolved-quarantine reprocessing',
    p_force_reprocess BOOLEAN DEFAULT FALSE,
    p_requested_by TEXT DEFAULT current_user
)
RETURNS TABLE (
    reprocessing_job_id UUID,
    total_records INTEGER,
    processed_count INTEGER,
    promoted_count INTEGER,
    skipped_duplicate_count INTEGER,
    failed_validation_count INTEGER,
    failed_system_count INTEGER
)
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_job_id UUID;
BEGIN
    v_job_id := eligibility.create_reprocessing_job(
        p_partner_id,
        p_tenant_id,
        p_org_id,
        p_data_region,
        'resolved_quarantine',
        p_reason,
        NULL,
        NULL,
        jsonb_build_object('source', 'reprocess_resolved_quarantine'),
        p_requested_by
    );

    RETURN QUERY
    SELECT
        r.reprocessing_job_id,
        r.total_records,
        r.processed_count,
        r.promoted_count,
        r.skipped_duplicate_count,
        r.failed_validation_count,
        r.failed_system_count
    FROM eligibility.reprocess_job(v_job_id, p_force_reprocess) r;
END;
$$;

COMMIT;
