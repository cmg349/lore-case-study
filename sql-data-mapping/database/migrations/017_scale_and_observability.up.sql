BEGIN;

CREATE INDEX IF NOT EXISTS idx_promotion_audit_attempted_at_brin
    ON eligibility.promotion_audit USING BRIN (attempted_at)
    WITH (pages_per_range = 32);

CREATE INDEX IF NOT EXISTS idx_promotion_audit_promoted_at
    ON eligibility.promotion_audit(promoted_at DESC)
    WHERE promotion_status = 'promoted'
      AND promoted_at IS NOT NULL;

CREATE INDEX IF NOT EXISTS idx_canonical_delete_after_date
    ON eligibility.canonical_eligibility_record(delete_after_date)
    WHERE delete_after_date IS NOT NULL;

COMMIT;

CREATE OR REPLACE PROCEDURE eligibility.promote_batch_chunked(
    p_batch_id        UUID,
    p_force_reprocess BOOLEAN DEFAULT FALSE,
    p_chunk_size      INTEGER DEFAULT 1000
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_last_id    UUID;
    v_record_ids UUID[];
    v_record_id  UUID;
BEGIN
    IF NOT EXISTS (
        SELECT 1
        FROM eligibility.partner_eligibility_batch b
        WHERE b.batch_id = p_batch_id
    ) THEN
        RAISE EXCEPTION 'Partner eligibility batch % not found', p_batch_id
            USING ERRCODE = 'P0002';
    END IF;

    v_last_id := '00000000-0000-0000-0000-000000000000'::UUID;

    LOOP

        SELECT ARRAY_AGG(r.eligibility_record_id ORDER BY r.eligibility_record_id)
        INTO v_record_ids
        FROM (
            SELECT r.eligibility_record_id
            FROM eligibility.canonical_eligibility_record r
            WHERE r.batch_id    = p_batch_id
              AND r.eligibility_record_id > v_last_id
            ORDER BY r.eligibility_record_id
            LIMIT p_chunk_size
        ) r;

        EXIT WHEN v_record_ids IS NULL OR array_length(v_record_ids, 1) = 0;

        FOREACH v_record_id IN ARRAY v_record_ids LOOP
            BEGIN
                PERFORM eligibility.promote_canonical_record(
                    v_record_id,
                    p_force_reprocess
                );
            EXCEPTION
                WHEN OTHERS THEN

                    NULL;
            END;
        END LOOP;

        v_last_id := v_record_ids[array_length(v_record_ids, 1)];

        COMMIT;

    END LOOP;
END;
$$;

CREATE OR REPLACE PROCEDURE eligibility.sweep_expired_curated_records(
    p_as_of      DATE    DEFAULT CURRENT_DATE,
    p_chunk_size INTEGER DEFAULT 500
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_last_id UUID;
    v_ids     UUID[];
    v_id      UUID;
BEGIN
    v_last_id := '00000000-0000-0000-0000-000000000000'::UUID;

    LOOP
        SELECT ARRAY_AGG(c.curated_eligibility_id ORDER BY c.curated_eligibility_id)
        INTO v_ids
        FROM (
            SELECT c.curated_eligibility_id
            FROM eligibility.curated_eligibility_current c
            WHERE c.eligibility_status    = 'active'
              AND c.eligibility_end_date  IS NOT NULL
              AND c.eligibility_end_date  < p_as_of
              AND c.curated_eligibility_id > v_last_id
            ORDER BY c.curated_eligibility_id
            LIMIT p_chunk_size
        ) c;

        EXIT WHEN v_ids IS NULL OR array_length(v_ids, 1) = 0;

        FOREACH v_id IN ARRAY v_ids LOOP

            PERFORM eligibility.close_current_history_record(v_id, now());

            INSERT INTO eligibility.curated_eligibility_history (
                curated_eligibility_id,
                eligibility_record_id,
                partner_id,
                tenant_id,
                org_id,
                data_region,
                partner_employee_id,
                partner_person_id,
                partner_member_id,
                eligibility_status,
                is_currently_eligible,
                eligibility_start_date,
                eligibility_end_date,
                valid_from,
                valid_to,
                change_reason,
                record_hash,
                created_at
            )
            SELECT
                c.curated_eligibility_id,
                c.eligibility_record_id,
                c.partner_id,
                c.tenant_id,
                c.org_id,
                c.data_region,
                c.partner_employee_id,
                c.partner_person_id,
                c.partner_member_id,
                'expired',
                FALSE,
                c.eligibility_start_date,
                c.eligibility_end_date,
                now(),
                now(),
                'eligibility_end_date_passed',
                c.curated_eligibility_id::TEXT,
                now()
            FROM eligibility.curated_eligibility_current c
            WHERE c.curated_eligibility_id = v_id;

            UPDATE eligibility.curated_eligibility_current c
            SET
                eligibility_status = 'expired',
                updated_at         = now()
            WHERE c.curated_eligibility_id = v_id;
        END LOOP;

        v_last_id := v_ids[array_length(v_ids, 1)];

        COMMIT;

    END LOOP;
END;
$$;

CREATE OR REPLACE PROCEDURE eligibility.enforce_canonical_retention(
    p_as_of      DATE    DEFAULT CURRENT_DATE,
    p_dry_run    BOOLEAN DEFAULT TRUE,
    p_chunk_size INTEGER DEFAULT 200
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_last_id    UUID;
    v_ids        UUID[];
    v_deleted    INTEGER := 0;
    v_chunk_del  INTEGER;
BEGIN
    v_last_id := '00000000-0000-0000-0000-000000000000'::UUID;

    LOOP
        SELECT ARRAY_AGG(r.eligibility_record_id ORDER BY r.eligibility_record_id)
        INTO v_ids
        FROM (
            SELECT r.eligibility_record_id
            FROM eligibility.canonical_eligibility_record r
            WHERE r.delete_after_date       IS NOT NULL
              AND r.delete_after_date        < p_as_of
              AND COALESCE(r.legal_hold, FALSE) = FALSE
              AND r.eligibility_record_id    > v_last_id
            ORDER BY r.eligibility_record_id
            LIMIT p_chunk_size
        ) r;

        EXIT WHEN v_ids IS NULL OR array_length(v_ids, 1) = 0;

        IF p_dry_run THEN

            v_deleted := v_deleted + array_length(v_ids, 1);
        ELSE
            DELETE FROM eligibility.canonical_eligibility_record r
            WHERE r.eligibility_record_id = ANY(v_ids);

            GET DIAGNOSTICS v_chunk_del = ROW_COUNT;
            v_deleted := v_deleted + v_chunk_del;

            COMMIT;
        END IF;

        v_last_id := v_ids[array_length(v_ids, 1)];

    END LOOP;

    IF p_dry_run THEN
        RAISE NOTICE 'DRY RUN: % canonical records eligible for deletion as of %',
            v_deleted, p_as_of;
    ELSE
        RAISE NOTICE 'Deleted % canonical records with delete_after_date < %',
            v_deleted, p_as_of;
    END IF;
END;
$$;
