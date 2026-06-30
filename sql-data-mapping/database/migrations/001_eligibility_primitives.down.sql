BEGIN;

DROP TYPE IF EXISTS eligibility.encryption_status;
DROP TYPE IF EXISTS eligibility.tokenization_status;
DROP TYPE IF EXISTS eligibility.token_type;
DROP TYPE IF EXISTS eligibility.review_status;
DROP TYPE IF EXISTS eligibility.error_severity;
DROP TYPE IF EXISTS eligibility.dq_status;
DROP TYPE IF EXISTS eligibility.person_relationship_type;
DROP TYPE IF EXISTS eligibility.source_operation;
DROP TYPE IF EXISTS eligibility.eligibility_status;
DROP TYPE IF EXISTS eligibility.batch_status;
DROP TYPE IF EXISTS eligibility.delivery_type;

DROP SCHEMA IF EXISTS eligibility;

DROP EXTENSION IF EXISTS citext;
DROP EXTENSION IF EXISTS pgcrypto;

COMMIT;
