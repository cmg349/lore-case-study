BEGIN;

ALTER DEFAULT PRIVILEGES IN SCHEMA eligibility
    REVOKE ALL ON TABLES    FROM eligibility_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA eligibility
    REVOKE ALL ON SEQUENCES FROM eligibility_admin;
ALTER DEFAULT PRIVILEGES IN SCHEMA eligibility
    REVOKE ALL ON FUNCTIONS FROM eligibility_admin;

ALTER DEFAULT PRIVILEGES IN SCHEMA eligibility
    REVOKE ALL ON TABLES    FROM eligibility_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA eligibility
    REVOKE ALL ON SEQUENCES FROM eligibility_app;
ALTER DEFAULT PRIVILEGES IN SCHEMA eligibility
    REVOKE ALL ON FUNCTIONS FROM eligibility_app;

REVOKE ALL ON ALL TABLES     IN SCHEMA eligibility FROM eligibility_admin;
REVOKE ALL ON ALL SEQUENCES  IN SCHEMA eligibility FROM eligibility_admin;
REVOKE ALL ON ALL FUNCTIONS  IN SCHEMA eligibility FROM eligibility_admin;
REVOKE ALL ON ALL PROCEDURES IN SCHEMA eligibility FROM eligibility_admin;
REVOKE USAGE ON SCHEMA eligibility FROM eligibility_admin;

REVOKE ALL ON ALL TABLES     IN SCHEMA eligibility FROM eligibility_app;
REVOKE ALL ON ALL SEQUENCES  IN SCHEMA eligibility FROM eligibility_app;
REVOKE ALL ON ALL FUNCTIONS  IN SCHEMA eligibility FROM eligibility_app;
REVOKE ALL ON ALL PROCEDURES IN SCHEMA eligibility FROM eligibility_app;
REVOKE USAGE ON SCHEMA eligibility FROM eligibility_app;

COMMIT;
