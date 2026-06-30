BEGIN;

CREATE OR REPLACE FUNCTION eligibility.create_identity_verification_request(
    p_partner_id TEXT,
    p_tenant_id TEXT,
    p_org_id TEXT,
    p_data_region TEXT,
    p_request_source TEXT,
    p_external_request_id TEXT DEFAULT NULL,
    p_requester_subject_id TEXT DEFAULT NULL,
    p_requester_account_id TEXT DEFAULT NULL,
    p_application_user_id TEXT DEFAULT NULL,
    p_idempotency_key TEXT DEFAULT NULL,
    p_submitted_normalized_email_hash TEXT DEFAULT NULL,
    p_submitted_phone_hash TEXT DEFAULT NULL,
    p_submitted_dob_hash TEXT DEFAULT NULL,
    p_submitted_name_dob_hash TEXT DEFAULT NULL,
    p_submitted_partner_employee_id_hash TEXT DEFAULT NULL,
    p_submitted_partner_person_id_hash TEXT DEFAULT NULL,
    p_submitted_partner_member_id_hash TEXT DEFAULT NULL,
    p_submitted_masked_email TEXT DEFAULT NULL,
    p_submitted_masked_phone TEXT DEFAULT NULL,
    p_submitted_last_four_ssn TEXT DEFAULT NULL,
    p_request_context JSONB DEFAULT '{}'::JSONB,
    p_request_metadata JSONB DEFAULT '{}'::JSONB,
    p_identity_match_policy_id TEXT DEFAULT 'policy_v1',
    p_identity_match_policy_version TEXT DEFAULT 'v1',
    p_decision_policy_id TEXT DEFAULT 'decision_policy_v1',
    p_decision_policy_version TEXT DEFAULT 'v1'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_request_id UUID;
    v_token_count INTEGER;
BEGIN
    IF p_partner_id IS NULL OR btrim(p_partner_id) = '' THEN
        RAISE EXCEPTION 'partner_id is required';
    END IF;

    IF p_tenant_id IS NULL OR btrim(p_tenant_id) = '' THEN
        RAISE EXCEPTION 'tenant_id is required';
    END IF;

    IF p_org_id IS NULL OR btrim(p_org_id) = '' THEN
        RAISE EXCEPTION 'org_id is required';
    END IF;

    IF p_data_region IS NULL OR btrim(p_data_region) = '' THEN
        RAISE EXCEPTION 'data_region is required';
    END IF;

    IF p_request_source IS NULL OR btrim(p_request_source) = '' THEN
        RAISE EXCEPTION 'request_source is required';
    END IF;

    v_token_count :=
        CASE WHEN p_submitted_normalized_email_hash IS NOT NULL AND btrim(p_submitted_normalized_email_hash) <> '' THEN 1 ELSE 0 END +
        CASE WHEN p_submitted_phone_hash IS NOT NULL AND btrim(p_submitted_phone_hash) <> '' THEN 1 ELSE 0 END +
        CASE WHEN p_submitted_dob_hash IS NOT NULL AND btrim(p_submitted_dob_hash) <> '' THEN 1 ELSE 0 END +
        CASE WHEN p_submitted_name_dob_hash IS NOT NULL AND btrim(p_submitted_name_dob_hash) <> '' THEN 1 ELSE 0 END +
        CASE WHEN p_submitted_partner_employee_id_hash IS NOT NULL AND btrim(p_submitted_partner_employee_id_hash) <> '' THEN 1 ELSE 0 END +
        CASE WHEN p_submitted_partner_person_id_hash IS NOT NULL AND btrim(p_submitted_partner_person_id_hash) <> '' THEN 1 ELSE 0 END +
        CASE WHEN p_submitted_partner_member_id_hash IS NOT NULL AND btrim(p_submitted_partner_member_id_hash) <> '' THEN 1 ELSE 0 END;

    IF v_token_count = 0 THEN
        RAISE EXCEPTION 'At least one submitted identity token hash is required';
    END IF;

    IF p_idempotency_key IS NOT NULL AND btrim(p_idempotency_key) <> '' THEN
        SELECT r.identity_verification_request_id
        INTO v_request_id
        FROM eligibility.identity_verification_request r
        WHERE r.partner_id = p_partner_id
          AND r.tenant_id = p_tenant_id
          AND r.org_id = p_org_id
          AND r.data_region = p_data_region
          AND r.idempotency_key = p_idempotency_key
        LIMIT 1;

        IF v_request_id IS NOT NULL THEN
            RETURN v_request_id;
        END IF;
    END IF;

    INSERT INTO eligibility.identity_verification_request (
        partner_id,
        tenant_id,
        org_id,
        data_region,
        external_request_id,
        request_source,
        requester_subject_id,
        requester_account_id,
        application_user_id,
        idempotency_key,
        request_status,
        identity_match_policy_id,
        identity_match_policy_version,
        decision_policy_id,
        decision_policy_version,
        submitted_normalized_email_hash,
        submitted_phone_hash,
        submitted_dob_hash,
        submitted_name_dob_hash,
        submitted_partner_employee_id_hash,
        submitted_partner_person_id_hash,
        submitted_partner_member_id_hash,
        submitted_masked_email,
        submitted_masked_phone,
        submitted_last_four_ssn,
        submitted_identity_token_count,
        request_context,
        request_metadata
    )
    VALUES (
        p_partner_id,
        p_tenant_id,
        p_org_id,
        p_data_region,
        p_external_request_id,
        p_request_source,
        p_requester_subject_id,
        p_requester_account_id,
        p_application_user_id,
        NULLIF(btrim(COALESCE(p_idempotency_key, '')), ''),
        'received'::eligibility.identity_verification_request_status,
        p_identity_match_policy_id,
        p_identity_match_policy_version,
        p_decision_policy_id,
        p_decision_policy_version,
        NULLIF(btrim(COALESCE(p_submitted_normalized_email_hash, '')), ''),
        NULLIF(btrim(COALESCE(p_submitted_phone_hash, '')), ''),
        NULLIF(btrim(COALESCE(p_submitted_dob_hash, '')), ''),
        NULLIF(btrim(COALESCE(p_submitted_name_dob_hash, '')), ''),
        NULLIF(btrim(COALESCE(p_submitted_partner_employee_id_hash, '')), ''),
        NULLIF(btrim(COALESCE(p_submitted_partner_person_id_hash, '')), ''),
        NULLIF(btrim(COALESCE(p_submitted_partner_member_id_hash, '')), ''),
        p_submitted_masked_email,
        p_submitted_masked_phone,
        p_submitted_last_four_ssn,
        v_token_count,
        COALESCE(p_request_context, '{}'::JSONB),
        COALESCE(p_request_metadata, '{}'::JSONB)
    )
    RETURNING identity_verification_request_id INTO v_request_id;

    RETURN v_request_id;
END;
$$;

COMMENT ON FUNCTION eligibility.create_identity_verification_request(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
    JSONB, JSONB, TEXT, TEXT, TEXT, TEXT
) IS
'Creates an identity verification request using tokenized/masked submitted evidence. SECURITY INVOKER so RLS remains enforced.';

CREATE OR REPLACE FUNCTION eligibility.find_identity_verification_matches(
    p_identity_verification_request_id UUID,
    p_min_match_score NUMERIC DEFAULT 80.00,
    p_max_candidates INTEGER DEFAULT 5
)
RETURNS TABLE (
    identity_verification_match_candidate_id UUID,
    curated_eligibility_id UUID,
    eligibility_record_id UUID,
    match_rank INTEGER,
    match_score NUMERIC(5,2),
    match_strategy eligibility.identity_match_strategy,
    match_candidate_status eligibility.identity_match_candidate_status,
    matched_token_types TEXT[]
)
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_request eligibility.identity_verification_request%ROWTYPE;
    v_existing_candidate_count INTEGER;
    v_final_candidate_count INTEGER;
BEGIN
    IF p_identity_verification_request_id IS NULL THEN
        RAISE EXCEPTION 'identity_verification_request_id is required';
    END IF;

    IF p_min_match_score IS NULL OR p_min_match_score < 0 OR p_min_match_score > 100 THEN
        RAISE EXCEPTION 'p_min_match_score must be between 0 and 100';
    END IF;

    IF p_max_candidates IS NULL OR p_max_candidates < 1 THEN
        RAISE EXCEPTION 'p_max_candidates must be greater than 0';
    END IF;

    SELECT r.*
    INTO v_request
    FROM eligibility.identity_verification_request r
    WHERE r.identity_verification_request_id = p_identity_verification_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Identity verification request % was not found or is not visible under the current RLS scope',
            p_identity_verification_request_id;
    END IF;

    UPDATE eligibility.identity_verification_request r
    SET
        request_status = 'matching'::eligibility.identity_verification_request_status,
        matching_started_at = COALESCE(r.matching_started_at, now())
    WHERE r.identity_verification_request_id = p_identity_verification_request_id
      AND r.request_status NOT IN (
          'decisioned'::eligibility.identity_verification_request_status,
          'manual_review'::eligibility.identity_verification_request_status,
          'failed'::eligibility.identity_verification_request_status
      );

    SELECT COUNT(*)
    INTO v_existing_candidate_count
    FROM eligibility.identity_verification_match_candidate c
    WHERE c.identity_verification_request_id = p_identity_verification_request_id;

    IF v_existing_candidate_count = 0 THEN
        WITH submitted_tokens AS (
            SELECT *
            FROM (
                VALUES
                    ('normalized_email_hash'::eligibility.token_type, v_request.submitted_normalized_email_hash, 45.00::NUMERIC),
                    ('phone_hash'::eligibility.token_type, v_request.submitted_phone_hash, 30.00::NUMERIC),
                    ('dob_hash'::eligibility.token_type, v_request.submitted_dob_hash, 35.00::NUMERIC),
                    ('name_dob_hash'::eligibility.token_type, v_request.submitted_name_dob_hash, 80.00::NUMERIC),
                    ('partner_employee_id_hash'::eligibility.token_type, v_request.submitted_partner_employee_id_hash, 60.00::NUMERIC),
                    ('partner_person_id_hash'::eligibility.token_type, v_request.submitted_partner_person_id_hash, 60.00::NUMERIC),
                    ('partner_member_id_hash'::eligibility.token_type, v_request.submitted_partner_member_id_hash, 60.00::NUMERIC)
            ) AS t(token_type, token_value, weight)
            WHERE t.token_value IS NOT NULL
              AND btrim(t.token_value) <> ''
        ), matched_curated AS (
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
                c.eligibility_status,
                eligibility.calculate_current_eligibility(
                    c.eligibility_status,
                    c.eligibility_start_date,
                    c.eligibility_end_date
                ) AS is_currently_eligible,
                c.eligibility_start_date,
                c.eligibility_end_date,
                c.dq_status,
                c.source_last_updated_at,
                c.curated_at,
                ARRAY_AGG(DISTINCT st.token_type::TEXT ORDER BY st.token_type::TEXT) AS matched_token_types,
                LEAST(100.00, SUM(DISTINCT st.weight))::NUMERIC(5,2) AS match_score
            FROM submitted_tokens st
            JOIN eligibility.eligibility_identity_token tok
              ON tok.token_type = st.token_type
             AND tok.token_value = st.token_value
             AND tok.partner_id = v_request.partner_id
             AND tok.tenant_id = v_request.tenant_id
             AND tok.org_id = v_request.org_id
             AND tok.data_region = v_request.data_region
            JOIN eligibility.curated_eligibility_current c
              ON c.eligibility_record_id = tok.eligibility_record_id
             AND c.partner_id = v_request.partner_id
             AND c.tenant_id = v_request.tenant_id
             AND c.org_id = v_request.org_id
             AND c.data_region = v_request.data_region
            WHERE c.dq_status IN ('valid'::eligibility.dq_status, 'valid_with_warnings'::eligibility.dq_status)
              AND c.eligibility_status = 'active'
              AND (c.eligibility_start_date IS NULL OR c.eligibility_start_date <= CURRENT_DATE)
              AND (c.eligibility_end_date IS NULL OR c.eligibility_end_date >= CURRENT_DATE)
            GROUP BY
                c.curated_eligibility_id,
                c.eligibility_record_id,
                c.partner_id,
                c.tenant_id,
                c.org_id,
                c.data_region,
                c.partner_employee_id,
                c.partner_person_id,
                c.partner_member_id,
                c.eligibility_status,
                c.eligibility_start_date,
                c.eligibility_end_date,
                c.dq_status,
                c.source_last_updated_at,
                c.curated_at
        ), ranked AS (
            SELECT
                m.*,
                ROW_NUMBER() OVER (
                    ORDER BY m.match_score DESC, m.source_last_updated_at DESC, m.curated_eligibility_id
                )::INTEGER AS match_rank
            FROM matched_curated m
            WHERE m.match_score >= p_min_match_score
            ORDER BY m.match_score DESC, m.source_last_updated_at DESC, m.curated_eligibility_id
            LIMIT p_max_candidates
        )
        INSERT INTO eligibility.identity_verification_match_candidate (
            identity_verification_request_id,
            partner_id,
            tenant_id,
            org_id,
            data_region,
            curated_eligibility_id,
            eligibility_record_id,
            match_rank,
            match_score,
            match_strategy,
            match_candidate_status,
            matched_token_types,
            matched_identifier_types,
            match_reason,
            eligibility_status,
            is_currently_eligible,
            eligibility_start_date,
            eligibility_end_date,
            dq_status,
            source_last_updated_at,
            curated_at,
            candidate_snapshot
        )
        SELECT
            p_identity_verification_request_id,
            r.partner_id,
            r.tenant_id,
            r.org_id,
            r.data_region,
            r.curated_eligibility_id,
            r.eligibility_record_id,
            r.match_rank,
            r.match_score,
            CASE
                WHEN 'partner_employee_id_hash' = ANY(r.matched_token_types)
                  OR 'partner_person_id_hash' = ANY(r.matched_token_types)
                  OR 'partner_member_id_hash' = ANY(r.matched_token_types)
                    THEN 'eligibility_identifier'::eligibility.identity_match_strategy
                WHEN 'name_dob_hash' = ANY(r.matched_token_types)
                    THEN 'composite_token'::eligibility.identity_match_strategy
                ELSE 'exact_token'::eligibility.identity_match_strategy
            END,
            'candidate'::eligibility.identity_match_candidate_status,
            r.matched_token_types,
            ARRAY_REMOVE(ARRAY[
                CASE WHEN 'partner_employee_id_hash' = ANY(r.matched_token_types) THEN 'partner_employee_id' END,
                CASE WHEN 'partner_person_id_hash' = ANY(r.matched_token_types) THEN 'partner_person_id' END,
                CASE WHEN 'partner_member_id_hash' = ANY(r.matched_token_types) THEN 'partner_member_id' END
            ], NULL),
            format(
                'Matched %s submitted identity token(s) to an active curated eligibility record.',
                cardinality(r.matched_token_types)
            ),
            r.eligibility_status,
            r.is_currently_eligible,
            r.eligibility_start_date,
            r.eligibility_end_date,
            r.dq_status,
            r.source_last_updated_at,
            r.curated_at,
            jsonb_build_object(
                'partner_employee_id', r.partner_employee_id,
                'partner_person_id', r.partner_person_id,
                'partner_member_id', r.partner_member_id,
                'eligibility_status', r.eligibility_status,
                'is_currently_eligible', r.is_currently_eligible,
                'dq_status', r.dq_status,
                'matched_token_types', r.matched_token_types
            )
        FROM ranked r;
    END IF;

    SELECT COUNT(*)
    INTO v_final_candidate_count
    FROM eligibility.identity_verification_match_candidate c
    WHERE c.identity_verification_request_id = p_identity_verification_request_id;

    UPDATE eligibility.identity_verification_request r
    SET
        request_status = CASE
            WHEN v_final_candidate_count = 0 THEN 'not_matched'::eligibility.identity_verification_request_status
            WHEN v_final_candidate_count = 1 THEN 'matched'::eligibility.identity_verification_request_status
            ELSE 'ambiguous_match'::eligibility.identity_verification_request_status
        END,
        matching_completed_at = COALESCE(r.matching_completed_at, now())
    WHERE r.identity_verification_request_id = p_identity_verification_request_id
      AND r.request_status NOT IN (
          'decisioned'::eligibility.identity_verification_request_status,
          'manual_review'::eligibility.identity_verification_request_status,
          'failed'::eligibility.identity_verification_request_status
      );

    RETURN QUERY
    SELECT
        c.identity_verification_match_candidate_id,
        c.curated_eligibility_id,
        c.eligibility_record_id,
        c.match_rank,
        c.match_score,
        c.match_strategy,
        c.match_candidate_status,
        c.matched_token_types
    FROM eligibility.identity_verification_match_candidate c
    WHERE c.identity_verification_request_id = p_identity_verification_request_id
    ORDER BY c.match_rank;
END;
$$;

COMMENT ON FUNCTION eligibility.find_identity_verification_matches(UUID, NUMERIC, INTEGER) IS
'Finds active curated eligibility match candidates for a verification request using submitted identity token hashes. SECURITY INVOKER so RLS remains enforced.';

CREATE OR REPLACE FUNCTION eligibility.record_identity_verification_decision(
    p_identity_verification_request_id UUID,
    p_decision_status eligibility.identity_verification_decision_status,
    p_identity_verification_match_candidate_id UUID DEFAULT NULL,
    p_decision_reason_code TEXT DEFAULT NULL,
    p_decision_reason TEXT DEFAULT NULL,
    p_is_eligible BOOLEAN DEFAULT NULL,
    p_requires_manual_review BOOLEAN DEFAULT NULL,
    p_confidence_score NUMERIC DEFAULT NULL,
    p_decision_evidence JSONB DEFAULT '{}'::JSONB,
    p_decided_by TEXT DEFAULT 'system',
    p_decision_policy_id TEXT DEFAULT 'decision_policy_v1',
    p_decision_policy_version TEXT DEFAULT 'v1',
    p_decision_rule_version TEXT DEFAULT 'v1'
)
RETURNS UUID
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_request eligibility.identity_verification_request%ROWTYPE;
    v_candidate eligibility.identity_verification_match_candidate%ROWTYPE;
    v_decision_id UUID;
    v_is_eligible BOOLEAN;
    v_requires_manual_review BOOLEAN;
    v_reason_code TEXT;
    v_reason TEXT;
BEGIN
    IF p_identity_verification_request_id IS NULL THEN
        RAISE EXCEPTION 'identity_verification_request_id is required';
    END IF;

    IF p_decision_status IS NULL THEN
        RAISE EXCEPTION 'decision_status is required';
    END IF;

    SELECT d.identity_verification_decision_id
    INTO v_decision_id
    FROM eligibility.identity_verification_decision d
    WHERE d.identity_verification_request_id = p_identity_verification_request_id
    LIMIT 1;

    IF v_decision_id IS NOT NULL THEN
        RETURN v_decision_id;
    END IF;

    SELECT r.*
    INTO v_request
    FROM eligibility.identity_verification_request r
    WHERE r.identity_verification_request_id = p_identity_verification_request_id
    FOR UPDATE;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Identity verification request % was not found or is not visible under the current RLS scope',
            p_identity_verification_request_id;
    END IF;

    IF p_identity_verification_match_candidate_id IS NOT NULL THEN
        SELECT c.*
        INTO v_candidate
        FROM eligibility.identity_verification_match_candidate c
        WHERE c.identity_verification_match_candidate_id = p_identity_verification_match_candidate_id
          AND c.identity_verification_request_id = p_identity_verification_request_id;

        IF NOT FOUND THEN
            RAISE EXCEPTION 'Match candidate % was not found for request % or is not visible under the current RLS scope',
                p_identity_verification_match_candidate_id,
                p_identity_verification_request_id;
        END IF;
    END IF;

    IF p_decision_status = 'approved'::eligibility.identity_verification_decision_status
       AND p_identity_verification_match_candidate_id IS NULL THEN
        RAISE EXCEPTION 'approved decisions require a selected match candidate';
    END IF;

    v_is_eligible := COALESCE(
        p_is_eligible,
        CASE
            WHEN p_decision_status = 'approved'::eligibility.identity_verification_decision_status THEN TRUE
            ELSE FALSE
        END
    );

    v_requires_manual_review := COALESCE(
        p_requires_manual_review,
        CASE
            WHEN p_decision_status = 'manual_review'::eligibility.identity_verification_decision_status THEN TRUE
            ELSE FALSE
        END
    );

    v_reason_code := COALESCE(
        NULLIF(btrim(COALESCE(p_decision_reason_code, '')), ''),
        CASE p_decision_status
            WHEN 'approved'::eligibility.identity_verification_decision_status THEN 'ELIGIBLE_ACTIVE_MATCH'
            WHEN 'denied'::eligibility.identity_verification_decision_status THEN 'NO_ELIGIBLE_MATCH'
            WHEN 'manual_review'::eligibility.identity_verification_decision_status THEN 'MANUAL_REVIEW_REQUIRED'
            WHEN 'failed'::eligibility.identity_verification_decision_status THEN 'VERIFICATION_FAILED'
        END
    );

    v_reason := COALESCE(
        p_decision_reason,
        CASE p_decision_status
            WHEN 'approved'::eligibility.identity_verification_decision_status THEN 'Submitted identity evidence matched an active eligible curated record.'
            WHEN 'denied'::eligibility.identity_verification_decision_status THEN 'Submitted identity evidence did not match an active eligible curated record.'
            WHEN 'manual_review'::eligibility.identity_verification_decision_status THEN 'Submitted identity evidence requires manual review.'
            WHEN 'failed'::eligibility.identity_verification_decision_status THEN 'Identity verification failed due to a system or policy error.'
        END
    );

    INSERT INTO eligibility.identity_verification_decision (
        identity_verification_request_id,
        identity_verification_match_candidate_id,
        partner_id,
        tenant_id,
        org_id,
        data_region,
        curated_eligibility_id,
        eligibility_record_id,
        decision_status,
        decision_reason_code,
        decision_reason,
        is_eligible,
        requires_manual_review,
        confidence_score,
        decision_policy_id,
        decision_policy_version,
        decision_rule_version,
        decision_evidence,
        decided_by
    )
    VALUES (
        v_request.identity_verification_request_id,
        p_identity_verification_match_candidate_id,
        v_request.partner_id,
        v_request.tenant_id,
        v_request.org_id,
        v_request.data_region,
        CASE WHEN p_identity_verification_match_candidate_id IS NOT NULL THEN v_candidate.curated_eligibility_id ELSE NULL END,
        CASE WHEN p_identity_verification_match_candidate_id IS NOT NULL THEN v_candidate.eligibility_record_id ELSE NULL END,
        p_decision_status,
        v_reason_code,
        v_reason,
        v_is_eligible,
        v_requires_manual_review,
        p_confidence_score,
        p_decision_policy_id,
        p_decision_policy_version,
        p_decision_rule_version,
        COALESCE(p_decision_evidence, '{}'::JSONB),
        COALESCE(NULLIF(btrim(COALESCE(p_decided_by, '')), ''), 'system')
    )
    RETURNING identity_verification_decision_id INTO v_decision_id;

    IF p_identity_verification_match_candidate_id IS NOT NULL THEN
        UPDATE eligibility.identity_verification_match_candidate c
        SET match_candidate_status = CASE
            WHEN p_decision_status = 'approved'::eligibility.identity_verification_decision_status THEN 'selected'::eligibility.identity_match_candidate_status
            WHEN p_decision_status = 'manual_review'::eligibility.identity_verification_decision_status THEN 'manual_review'::eligibility.identity_match_candidate_status
            ELSE 'rejected'::eligibility.identity_match_candidate_status
        END
        WHERE c.identity_verification_match_candidate_id = p_identity_verification_match_candidate_id;
    END IF;

    UPDATE eligibility.identity_verification_request r
    SET
        request_status = CASE
            WHEN p_decision_status = 'manual_review'::eligibility.identity_verification_decision_status
                THEN 'manual_review'::eligibility.identity_verification_request_status
            WHEN p_decision_status = 'failed'::eligibility.identity_verification_decision_status
                THEN 'failed'::eligibility.identity_verification_request_status
            ELSE 'decisioned'::eligibility.identity_verification_request_status
        END,
        decisioned_at = CASE
            WHEN p_decision_status <> 'failed'::eligibility.identity_verification_decision_status THEN now()
            ELSE r.decisioned_at
        END,
        failed_at = CASE
            WHEN p_decision_status = 'failed'::eligibility.identity_verification_decision_status THEN now()
            ELSE r.failed_at
        END,
        matching_completed_at = COALESCE(r.matching_completed_at, now()),
        failure_reason = CASE
            WHEN p_decision_status = 'failed'::eligibility.identity_verification_decision_status THEN v_reason
            ELSE r.failure_reason
        END
    WHERE r.identity_verification_request_id = p_identity_verification_request_id;

    RETURN v_decision_id;
END;
$$;

COMMENT ON FUNCTION eligibility.record_identity_verification_decision(
    UUID,
    eligibility.identity_verification_decision_status,
    UUID,
    TEXT,
    TEXT,
    BOOLEAN,
    BOOLEAN,
    NUMERIC,
    JSONB,
    TEXT,
    TEXT,
    TEXT,
    TEXT
) IS
'Records one final decision for an identity verification request and updates request/candidate lifecycle state. SECURITY INVOKER so RLS remains enforced.';

CREATE OR REPLACE FUNCTION eligibility.verify_identity_by_tokens(
    p_partner_id TEXT,
    p_tenant_id TEXT,
    p_org_id TEXT,
    p_data_region TEXT,
    p_request_source TEXT,
    p_external_request_id TEXT DEFAULT NULL,
    p_requester_subject_id TEXT DEFAULT NULL,
    p_requester_account_id TEXT DEFAULT NULL,
    p_application_user_id TEXT DEFAULT NULL,
    p_idempotency_key TEXT DEFAULT NULL,
    p_submitted_normalized_email_hash TEXT DEFAULT NULL,
    p_submitted_phone_hash TEXT DEFAULT NULL,
    p_submitted_dob_hash TEXT DEFAULT NULL,
    p_submitted_name_dob_hash TEXT DEFAULT NULL,
    p_submitted_partner_employee_id_hash TEXT DEFAULT NULL,
    p_submitted_partner_person_id_hash TEXT DEFAULT NULL,
    p_submitted_partner_member_id_hash TEXT DEFAULT NULL,
    p_submitted_masked_email TEXT DEFAULT NULL,
    p_submitted_masked_phone TEXT DEFAULT NULL,
    p_submitted_last_four_ssn TEXT DEFAULT NULL,
    p_request_context JSONB DEFAULT '{}'::JSONB,
    p_request_metadata JSONB DEFAULT '{}'::JSONB,
    p_min_match_score NUMERIC DEFAULT 80.00,
    p_auto_approve_score NUMERIC DEFAULT 95.00,
    p_max_candidates INTEGER DEFAULT 5
)
RETURNS TABLE (
    identity_verification_request_id UUID,
    identity_verification_decision_id UUID,
    decision_status eligibility.identity_verification_decision_status,
    curated_eligibility_id UUID,
    eligibility_record_id UUID,
    match_score NUMERIC(5,2),
    decision_reason_code TEXT,
    decision_reason TEXT,
    requires_manual_review BOOLEAN
)
LANGUAGE plpgsql
SECURITY INVOKER
AS $$
DECLARE
    v_request_id UUID;
    v_decision_id UUID;
    v_existing_decision_id UUID;
    v_candidate_count INTEGER;
    v_top_candidate eligibility.identity_verification_match_candidate%ROWTYPE;
    v_decision_status eligibility.identity_verification_decision_status;
    v_reason_code TEXT;
    v_reason TEXT;
    v_requires_manual_review BOOLEAN;
BEGIN
    IF p_min_match_score IS NULL OR p_min_match_score < 0 OR p_min_match_score > 100 THEN
        RAISE EXCEPTION 'p_min_match_score must be between 0 and 100';
    END IF;

    IF p_auto_approve_score IS NULL OR p_auto_approve_score < 0 OR p_auto_approve_score > 100 THEN
        RAISE EXCEPTION 'p_auto_approve_score must be between 0 and 100';
    END IF;

    v_request_id := eligibility.create_identity_verification_request(
        p_partner_id => p_partner_id,
        p_tenant_id => p_tenant_id,
        p_org_id => p_org_id,
        p_data_region => p_data_region,
        p_request_source => p_request_source,
        p_external_request_id => p_external_request_id,
        p_requester_subject_id => p_requester_subject_id,
        p_requester_account_id => p_requester_account_id,
        p_application_user_id => p_application_user_id,
        p_idempotency_key => p_idempotency_key,
        p_submitted_normalized_email_hash => p_submitted_normalized_email_hash,
        p_submitted_phone_hash => p_submitted_phone_hash,
        p_submitted_dob_hash => p_submitted_dob_hash,
        p_submitted_name_dob_hash => p_submitted_name_dob_hash,
        p_submitted_partner_employee_id_hash => p_submitted_partner_employee_id_hash,
        p_submitted_partner_person_id_hash => p_submitted_partner_person_id_hash,
        p_submitted_partner_member_id_hash => p_submitted_partner_member_id_hash,
        p_submitted_masked_email => p_submitted_masked_email,
        p_submitted_masked_phone => p_submitted_masked_phone,
        p_submitted_last_four_ssn => p_submitted_last_four_ssn,
        p_request_context => p_request_context,
        p_request_metadata => p_request_metadata
    );

    SELECT d.identity_verification_decision_id
    INTO v_existing_decision_id
    FROM eligibility.identity_verification_decision d
    WHERE d.identity_verification_request_id = v_request_id
    LIMIT 1;

    IF v_existing_decision_id IS NOT NULL THEN
        RETURN QUERY
        SELECT
            r.identity_verification_request_id,
            d.identity_verification_decision_id,
            d.decision_status,
            d.curated_eligibility_id,
            d.eligibility_record_id,
            COALESCE(c.match_score, d.confidence_score)::NUMERIC(5,2),
            d.decision_reason_code,
            d.decision_reason,
            d.requires_manual_review
        FROM eligibility.identity_verification_request r
        JOIN eligibility.identity_verification_decision d
          ON d.identity_verification_request_id = r.identity_verification_request_id
        LEFT JOIN eligibility.identity_verification_match_candidate c
          ON c.identity_verification_match_candidate_id = d.identity_verification_match_candidate_id
        WHERE r.identity_verification_request_id = v_request_id;
        RETURN;
    END IF;

    PERFORM *
    FROM eligibility.find_identity_verification_matches(
        v_request_id,
        p_min_match_score,
        p_max_candidates
    );

    SELECT COUNT(*)
    INTO v_candidate_count
    FROM eligibility.identity_verification_match_candidate c
    WHERE c.identity_verification_request_id = v_request_id;

    SELECT c.*
    INTO v_top_candidate
    FROM eligibility.identity_verification_match_candidate c
    WHERE c.identity_verification_request_id = v_request_id
    ORDER BY c.match_rank
    LIMIT 1;

    IF v_candidate_count = 0 THEN
        v_decision_status := 'denied'::eligibility.identity_verification_decision_status;
        v_reason_code := 'NO_ELIGIBLE_MATCH';
        v_reason := 'Submitted identity evidence did not match an active eligible curated record.';
        v_requires_manual_review := FALSE;
        v_decision_id := eligibility.record_identity_verification_decision(
            p_identity_verification_request_id => v_request_id,
            p_decision_status => v_decision_status,
            p_identity_verification_match_candidate_id => NULL,
            p_decision_reason_code => v_reason_code,
            p_decision_reason => v_reason,
            p_is_eligible => FALSE,
            p_requires_manual_review => v_requires_manual_review,
            p_confidence_score => 0.00,
            p_decision_evidence => jsonb_build_object(
                'candidate_count', v_candidate_count,
                'min_match_score', p_min_match_score,
                'auto_approve_score', p_auto_approve_score
            )
        );
    ELSIF v_candidate_count = 1 AND v_top_candidate.match_score >= p_auto_approve_score THEN
        v_decision_status := 'approved'::eligibility.identity_verification_decision_status;
        v_reason_code := 'ELIGIBLE_ACTIVE_TOKEN_MATCH';
        v_reason := 'Submitted identity evidence matched one active eligible curated record above the auto-approval threshold.';
        v_requires_manual_review := FALSE;
        v_decision_id := eligibility.record_identity_verification_decision(
            p_identity_verification_request_id => v_request_id,
            p_decision_status => v_decision_status,
            p_identity_verification_match_candidate_id => v_top_candidate.identity_verification_match_candidate_id,
            p_decision_reason_code => v_reason_code,
            p_decision_reason => v_reason,
            p_is_eligible => TRUE,
            p_requires_manual_review => v_requires_manual_review,
            p_confidence_score => v_top_candidate.match_score,
            p_decision_evidence => jsonb_build_object(
                'candidate_count', v_candidate_count,
                'selected_match_rank', v_top_candidate.match_rank,
                'selected_match_score', v_top_candidate.match_score,
                'matched_token_types', v_top_candidate.matched_token_types,
                'min_match_score', p_min_match_score,
                'auto_approve_score', p_auto_approve_score
            )
        );
    ELSE
        v_decision_status := 'manual_review'::eligibility.identity_verification_decision_status;
        v_reason_code := CASE
            WHEN v_candidate_count > 1 THEN 'AMBIGUOUS_MATCH'
            ELSE 'LOW_CONFIDENCE_MATCH'
        END;
        v_reason := CASE
            WHEN v_candidate_count > 1 THEN 'Submitted identity evidence matched multiple active curated records and requires review.'
            ELSE 'Submitted identity evidence matched one active curated record below the auto-approval threshold.'
        END;
        v_requires_manual_review := TRUE;
        v_decision_id := eligibility.record_identity_verification_decision(
            p_identity_verification_request_id => v_request_id,
            p_decision_status => v_decision_status,
            p_identity_verification_match_candidate_id => v_top_candidate.identity_verification_match_candidate_id,
            p_decision_reason_code => v_reason_code,
            p_decision_reason => v_reason,
            p_is_eligible => FALSE,
            p_requires_manual_review => v_requires_manual_review,
            p_confidence_score => v_top_candidate.match_score,
            p_decision_evidence => jsonb_build_object(
                'candidate_count', v_candidate_count,
                'top_match_rank', v_top_candidate.match_rank,
                'top_match_score', v_top_candidate.match_score,
                'matched_token_types', v_top_candidate.matched_token_types,
                'min_match_score', p_min_match_score,
                'auto_approve_score', p_auto_approve_score
            )
        );
    END IF;

    RETURN QUERY
    SELECT
        r.identity_verification_request_id,
        d.identity_verification_decision_id,
        d.decision_status,
        d.curated_eligibility_id,
        d.eligibility_record_id,
        COALESCE(c.match_score, d.confidence_score)::NUMERIC(5,2),
        d.decision_reason_code,
        d.decision_reason,
        d.requires_manual_review
    FROM eligibility.identity_verification_request r
    JOIN eligibility.identity_verification_decision d
      ON d.identity_verification_request_id = r.identity_verification_request_id
    LEFT JOIN eligibility.identity_verification_match_candidate c
      ON c.identity_verification_match_candidate_id = d.identity_verification_match_candidate_id
    WHERE r.identity_verification_request_id = v_request_id;
END;
$$;

COMMENT ON FUNCTION eligibility.verify_identity_by_tokens(
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
    TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT, TEXT,
    JSONB, JSONB, NUMERIC, NUMERIC, INTEGER
) IS
'End-to-end identity verification workflow using submitted token hashes: create request, find matches, record decision, and return the result. SECURITY INVOKER so RLS remains enforced.';

COMMIT;
