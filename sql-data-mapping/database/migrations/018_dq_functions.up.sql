BEGIN;

-- evaluates all active dq rules for a single canonical record and its pii row.
-- writes a quarantine entry for each failed rule, then updates dq_status/score
-- on the canonical record. returns a one-row summary of the outcome.
-- security invoker ensures the caller's rls context is enforced throughout.
CREATE OR REPLACE FUNCTION eligibility.evaluate_canonical_record_dq(
    p_eligibility_record_id UUID
)
RETURNS TABLE (
    dq_status      eligibility.dq_status,
    dq_score       NUMERIC(5,2),
    blocking_count INTEGER,
    warning_count  INTEGER,
    info_count     INTEGER
)
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_record          eligibility.canonical_eligibility_record%ROWTYPE;
    v_pii             eligibility.eligibility_person_pii%ROWTYPE;
    v_canonical_json  JSONB;
    v_pii_json        JSONB;
    v_rule            RECORD;
    v_field_value     TEXT;
    v_rule_passed     BOOLEAN;
    v_blocking        INTEGER := 0;
    v_warning         INTEGER := 0;
    v_info            INTEGER := 0;
    v_error_codes     TEXT[]  := ARRAY[]::TEXT[];
    v_final_status    eligibility.dq_status;
    v_score           NUMERIC(5,2);
BEGIN
    -- step 1: load the canonical record; raise if it doesn't exist
    SELECT r.*
    INTO v_record
    FROM eligibility.canonical_eligibility_record r
    WHERE r.eligibility_record_id = p_eligibility_record_id;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Canonical record % not found', p_eligibility_record_id
            USING ERRCODE = 'P0002';
    END IF;

    -- step 2: load the paired pii row (may not exist; handled below)
    SELECT p.*
    INTO v_pii
    FROM eligibility.eligibility_person_pii p
    WHERE p.eligibility_record_id = p_eligibility_record_id;

    -- step 3: serialize both rows to jsonb so field values can be extracted by
    -- name without dynamic sql. pii defaults to empty object if no row was found.
    v_canonical_json := to_jsonb(v_record);
    v_pii_json       := CASE
                            WHEN v_pii.pii_id IS NOT NULL THEN to_jsonb(v_pii)
                            ELSE '{}'::JSONB
                        END;

    -- step 4: fetch all active dq rules for this record's partner contract and
    -- schema version, ordered so rules run in the intended sequence
    FOR v_rule IN
        SELECT r.*
        FROM eligibility.partner_data_quality_rule r
        JOIN eligibility.partner_schema_version sv
          ON sv.partner_schema_version_id = r.partner_schema_version_id
        JOIN eligibility.partner_contract pc
          ON pc.partner_contract_id = sv.partner_contract_id
        WHERE pc.partner_id      = v_record.partner_id
          AND pc.tenant_id       = v_record.tenant_id
          AND pc.org_id          = v_record.org_id
          AND pc.data_region     = v_record.data_region
          AND pc.contract_status = 'active'
          AND sv.schema_version  = v_record.source_schema_version
          AND r.is_active        = TRUE
        ORDER BY r.execution_order ASC, r.partner_data_quality_rule_id ASC
    LOOP

        -- step 5: extract the field value from the correct source table.
        -- rules targeting pii only read from the pii json; all others check
        -- the canonical row first and fall back to pii if not found there.
        IF v_rule.applies_to_table = 'eligibility_person_pii' THEN
            v_field_value := v_pii_json ->> v_rule.canonical_field_name;
        ELSE
            v_field_value := COALESCE(
                v_canonical_json ->> v_rule.canonical_field_name,
                v_pii_json       ->> v_rule.canonical_field_name
            );
        END IF;

        -- step 6: evaluate the rule against the extracted field value.
        -- unknown rule types pass silently so unimplemented types don't block promotion.
        v_rule_passed := CASE v_rule.rule_type

            -- fails if the field is null
            WHEN 'not_null' THEN
                v_field_value IS NOT NULL

            -- fails if the field is null or contains only whitespace
            WHEN 'not_empty' THEN
                v_field_value IS NOT NULL
                AND btrim(v_field_value) <> ''

            -- fails if the field is null or doesn't match the configured pattern
            WHEN 'regex' THEN
                v_field_value IS NOT NULL
                AND v_field_value ~ (v_rule.rule_config ->> 'pattern')

            -- fails if the field is null or not in the configured whitelist
            WHEN 'allowed_values' THEN
                v_field_value IS NOT NULL
                AND v_field_value IN (
                    SELECT jsonb_array_elements_text(v_rule.rule_config -> 'values')
                )

            -- fails only if a date value is present and is in the future; nulls pass
            WHEN 'date_not_future' THEN
                v_field_value IS NULL
                OR v_field_value::DATE <= CURRENT_DATE

            -- fails if another active curated record in the same partner scope
            -- already holds the same value for this field (case-insensitive).
            -- checks the pii table since uniqueness is typically on pii fields like email.
            -- nulls pass so optional fields don't trigger false positives.
            WHEN 'unique_current_record' THEN

                v_field_value IS NULL
                OR NOT EXISTS (
                    SELECT 1
                    FROM eligibility.curated_eligibility_current c
                    JOIN eligibility.eligibility_person_pii op
                      ON op.eligibility_record_id = c.eligibility_record_id
                    WHERE c.partner_id                  =  v_record.partner_id
                      AND c.tenant_id                   =  v_record.tenant_id
                      AND c.org_id                      =  v_record.org_id
                      AND c.data_region                 =  v_record.data_region
                      AND c.eligibility_record_id       <> v_record.eligibility_record_id
                      AND LOWER(to_jsonb(op) ->> v_rule.canonical_field_name) = LOWER(v_field_value)
                )

            ELSE TRUE

        END;

        -- step 7: on failure, write a quarantine row and increment the relevant counter.
        -- severity is mapped to error_severity: blocking→sev_1, warning→sev_3, info→sev_5.
        -- requires_partner_action is only flagged true for blocking failures.
        IF NOT v_rule_passed THEN
            INSERT INTO eligibility.eligibility_quarantine (
                batch_id,
                eligibility_record_id,
                partner_id,
                tenant_id,
                org_id,
                data_region,
                source_row_number,
                raw_record_reference,
                canonical_record_reference,
                error_code,
                error_severity,
                failed_field,
                failure_reason,
                requires_partner_action
            ) VALUES (
                v_record.batch_id,
                v_record.eligibility_record_id,
                v_record.partner_id,
                v_record.tenant_id,
                v_record.org_id,
                v_record.data_region,
                v_record.source_row_number,
                COALESCE(v_record.source_record_id, v_record.eligibility_record_id::TEXT),
                v_record.eligibility_record_id::TEXT,
                v_rule.error_code,
                CASE v_rule.severity
                    WHEN 'blocking' THEN 'sev_1'::eligibility.error_severity
                    WHEN 'warning'  THEN 'sev_3'::eligibility.error_severity
                    ELSE                 'sev_5'::eligibility.error_severity
                END,
                v_rule.canonical_field_name,
                format(
                    '%s — rule: %s, field: %s, value: %s',
                    v_rule.error_message,
                    v_rule.rule_name,
                    COALESCE(v_rule.canonical_field_name, 'record-level'),
                    COALESCE(v_field_value, 'NULL')
                ),
                v_rule.severity = 'blocking'
            );

            v_error_codes := array_append(v_error_codes, v_rule.error_code);

            CASE v_rule.severity
                WHEN 'blocking' THEN v_blocking := v_blocking + 1;
                WHEN 'warning'  THEN v_warning  := v_warning  + 1;
                ELSE                 v_info     := v_info     + 1;
            END CASE;
        END IF;
    END LOOP;

    -- step 8: determine final dq status. any blocking failure quarantines the record;
    -- warnings alone yield valid_with_warnings; a clean run yields valid.
    v_final_status := CASE
        WHEN v_blocking > 0 THEN 'quarantined'::eligibility.dq_status
        WHEN v_warning  > 0 THEN 'valid_with_warnings'::eligibility.dq_status
        ELSE                     'valid'::eligibility.dq_status
    END;

    -- step 9: compute the dq score. each blocking failure costs 20 points,
    -- each warning costs 5, each info costs 1. floor is 0.
    v_score := GREATEST(
        0.00,
        100.00
            - (v_blocking * 20.00)
            - (v_warning  *  5.00)
            - (v_info     *  1.00)
    );

    -- step 10: write dq results back to the canonical record.
    -- requires_manual_review is or-ed so any flag set by another process is preserved.
    UPDATE eligibility.canonical_eligibility_record r
    SET
        dq_status              = v_final_status,
        dq_score               = v_score,
        dq_error_count         = v_blocking,
        dq_warning_count       = v_warning,
        dq_error_codes         = CASE
                                     WHEN array_length(v_error_codes, 1) > 0 THEN v_error_codes
                                     ELSE NULL
                                 END,
        dq_last_checked_at     = now(),

        requires_manual_review = r.requires_manual_review OR (v_blocking > 0)
    WHERE r.eligibility_record_id = p_eligibility_record_id;

    -- step 11: populate the output row and return
    dq_status      := v_final_status;
    dq_score       := v_score;
    blocking_count := v_blocking;
    warning_count  := v_warning;
    info_count     := v_info;
    RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION eligibility.evaluate_canonical_record_dq(UUID) IS
'Evaluates all active partner DQ rules against one canonical record + its PII vault row. '
'Writes quarantine rows for failures, updates dq_status/score on the canonical record, '
'and returns a one-row summary. SECURITY INVOKER so RLS remains enforced.';

-- batch-level dq wrapper. calls evaluate_canonical_record_dq for every record
-- in the batch, then rolls the aggregate counts back up to partner_eligibility_batch.
-- must be called before promote_batch / promote_batch_chunked.
CREATE OR REPLACE FUNCTION eligibility.evaluate_batch_dq(
    p_batch_id UUID
)
RETURNS TABLE (
    batch_id                   UUID,
    total_evaluated            INTEGER,
    valid_count                INTEGER,
    valid_with_warnings_count  INTEGER,
    quarantined_count          INTEGER
)
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_record_id    UUID;
    v_result       RECORD;
    v_total        INTEGER := 0;
    v_valid        INTEGER := 0;
    v_warnings     INTEGER := 0;
    v_quarantined  INTEGER := 0;
BEGIN
    -- step 1: guard against a non-existent batch id
    IF NOT EXISTS (
        SELECT 1
        FROM eligibility.partner_eligibility_batch b
        WHERE b.batch_id = p_batch_id
    ) THEN
        RAISE EXCEPTION 'Partner eligibility batch % not found', p_batch_id
            USING ERRCODE = 'P0002';
    END IF;

    -- step 2: iterate every canonical record in the batch in a stable order
    -- (source_row_number first so failures map back to the partner's original file)
    FOR v_record_id IN
        SELECT r.eligibility_record_id
        FROM eligibility.canonical_eligibility_record r
        WHERE r.batch_id = p_batch_id
        ORDER BY r.source_row_number NULLS LAST,
                 r.created_at        ASC,
                 r.eligibility_record_id ASC
    LOOP
        v_total := v_total + 1;

        -- step 3: run per-record dq evaluation and tally the outcome
        SELECT *
        INTO v_result
        FROM eligibility.evaluate_canonical_record_dq(v_record_id);

        CASE v_result.dq_status::TEXT
            WHEN 'valid'               THEN v_valid       := v_valid       + 1;
            WHEN 'valid_with_warnings' THEN v_warnings    := v_warnings    + 1;
            ELSE                            v_quarantined := v_quarantined + 1;
        END CASE;
    END LOOP;

    -- step 4: write aggregate dq counters back to the batch row.
    -- error/warning counts are re-summed from canonical records rather than
    -- accumulated in the loop so the numbers stay consistent if the function
    -- is called more than once on the same batch.
    UPDATE eligibility.partner_eligibility_batch b
    SET
        valid_record_count               = v_valid,
        valid_with_warnings_record_count = v_warnings,
        quarantined_record_count         = v_quarantined,
        dq_error_count = (
            SELECT COALESCE(SUM(r.dq_error_count), 0)
            FROM eligibility.canonical_eligibility_record r
            WHERE r.batch_id = p_batch_id
        ),
        dq_warning_count = (
            SELECT COALESCE(SUM(r.dq_warning_count), 0)
            FROM eligibility.canonical_eligibility_record r
            WHERE r.batch_id = p_batch_id
        )
    WHERE b.batch_id = p_batch_id;

    -- step 5: populate the output row and return
    batch_id                  := p_batch_id;
    total_evaluated           := v_total;
    valid_count               := v_valid;
    valid_with_warnings_count := v_warnings;
    quarantined_count         := v_quarantined;
    RETURN NEXT;
END;
$$;

COMMENT ON FUNCTION eligibility.evaluate_batch_dq(UUID) IS
'Runs evaluate_canonical_record_dq for every record in a batch and refreshes '
'the batch-level DQ counters. Call this before promote_batch / promote_batch_chunked.';

-- surfaces active curated records within the same partner scope that share a
-- normalized_primary_email across different partner_employee_ids. each row
-- represents one email address that maps to more than one employee, which
-- signals either a duplicate person entry or a shared mailbox used as a
-- personal email. rls is enforced via the underlying tables.
CREATE OR REPLACE VIEW eligibility.v_duplicate_pii_email AS
WITH email_groups AS (
    SELECT
        p.normalized_primary_email,
        c.partner_id,
        c.tenant_id,
        c.org_id,
        c.data_region,
        COUNT(DISTINCT c.partner_employee_id)              AS conflicting_record_count,
        ARRAY_AGG(
            DISTINCT c.partner_employee_id
            ORDER BY c.partner_employee_id
        )                                                  AS partner_employee_ids,
        -- most recently curated record listed first so callers can identify the latest entry
        ARRAY_AGG(
            c.eligibility_record_id
            ORDER BY c.curated_at DESC
        )                                                  AS eligibility_record_ids,
        MIN(c.curated_at)                                  AS first_curated_at,
        MAX(c.curated_at)                                  AS last_curated_at
    FROM eligibility.curated_eligibility_current c
    JOIN eligibility.eligibility_person_pii p
      ON p.eligibility_record_id = c.eligibility_record_id
    WHERE p.normalized_primary_email IS NOT NULL
      AND c.eligibility_status = 'active'
    GROUP BY
        p.normalized_primary_email,
        c.partner_id,
        c.tenant_id,
        c.org_id,
        c.data_region
    -- only return groups where more than one distinct employee shares the email
    HAVING COUNT(DISTINCT c.partner_employee_id) > 1
)
SELECT
    partner_id,
    tenant_id,
    org_id,
    data_region,
    normalized_primary_email,
    conflicting_record_count,
    partner_employee_ids,
    eligibility_record_ids,
    first_curated_at,
    last_curated_at
FROM email_groups
ORDER BY partner_id, tenant_id, conflicting_record_count DESC, normalized_primary_email;

-- surfaces canonical records whose primary_email fails a basic rfc 5321 format
-- check (must contain non-whitespace on both sides of @ and a dot after @).
-- malformed emails cannot produce a valid normalized_email_hash token, which
-- breaks identity matching downstream. use this view to find records that need
-- partner correction or manual remediation before they can be identity-matched.
CREATE OR REPLACE VIEW eligibility.v_email_format_errors AS
SELECT
    c.eligibility_record_id,
    c.batch_id,
    c.partner_id,
    c.tenant_id,
    c.org_id,
    c.data_region,
    c.partner_employee_id,
    p.primary_email,
    p.normalized_primary_email,
    c.dq_status,
    c.source_schema_version,
    c.created_at
FROM eligibility.canonical_eligibility_record c
JOIN eligibility.eligibility_person_pii p
  ON p.eligibility_record_id = c.eligibility_record_id
-- only rows where an email was supplied but it doesn't match the basic pattern
WHERE p.primary_email IS NOT NULL
  AND p.primary_email !~ '^\S+@\S+\.\S+$'
ORDER BY c.partner_id, c.tenant_id, c.created_at DESC;

COMMIT;
