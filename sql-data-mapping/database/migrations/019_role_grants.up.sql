BEGIN;


GRANT USAGE ON SCHEMA eligibility TO eligibility_admin;
GRANT USAGE ON SCHEMA eligibility TO eligibility_app;


GRANT ALL ON ALL TABLES    IN SCHEMA eligibility TO eligibility_admin;
GRANT ALL ON ALL SEQUENCES IN SCHEMA eligibility TO eligibility_admin;
GRANT ALL ON ALL FUNCTIONS IN SCHEMA eligibility TO eligibility_admin;
GRANT ALL ON ALL PROCEDURES IN SCHEMA eligibility TO eligibility_admin;

ALTER DEFAULT PRIVILEGES IN SCHEMA eligibility
    GRANT ALL ON TABLES    TO eligibility_admin;

ALTER DEFAULT PRIVILEGES IN SCHEMA eligibility
    GRANT ALL ON SEQUENCES TO eligibility_admin;

ALTER DEFAULT PRIVILEGES IN SCHEMA eligibility
    GRANT ALL ON FUNCTIONS TO eligibility_admin;


GRANT SELECT, INSERT, UPDATE, DELETE
    ON ALL TABLES IN SCHEMA eligibility
    TO eligibility_app;

GRANT USAGE ON ALL SEQUENCES IN SCHEMA eligibility TO eligibility_app;

GRANT EXECUTE ON ALL FUNCTIONS  IN SCHEMA eligibility TO eligibility_app;
GRANT EXECUTE ON ALL PROCEDURES IN SCHEMA eligibility TO eligibility_app;

ALTER DEFAULT PRIVILEGES IN SCHEMA eligibility
    GRANT SELECT, INSERT, UPDATE, DELETE ON TABLES TO eligibility_app;

ALTER DEFAULT PRIVILEGES IN SCHEMA eligibility
    GRANT USAGE ON SEQUENCES TO eligibility_app;

ALTER DEFAULT PRIVILEGES IN SCHEMA eligibility
    GRANT EXECUTE ON FUNCTIONS TO eligibility_app;

COMMIT;
