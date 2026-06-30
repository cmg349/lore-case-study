BEGIN;

DO $$
DECLARE
    r RECORD;
BEGIN
    FOR r IN
        SELECT p.oid::REGPROCEDURE AS function_signature
        FROM pg_proc p
        JOIN pg_namespace n
          ON n.oid = p.pronamespace
        WHERE n.nspname = 'eligibility'
          AND p.proname IN (
              'verify_identity_by_tokens',
              'record_identity_verification_decision',
              'find_identity_verification_matches',
              'create_identity_verification_request'
          )
        ORDER BY p.proname
    LOOP
        EXECUTE format('DROP FUNCTION IF EXISTS %s', r.function_signature);
    END LOOP;
END $$;

COMMIT;
