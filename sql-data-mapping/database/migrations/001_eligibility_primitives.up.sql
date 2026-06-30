BEGIN;

CREATE EXTENSION IF NOT EXISTS pgcrypto;
CREATE EXTENSION IF NOT EXISTS citext;

CREATE SCHEMA IF NOT EXISTS eligibility;

CREATE TYPE eligibility.delivery_type AS ENUM (
    'file',
    'api',
    'sftp',
    'event_stream',
    'database_replication',
    'manual'
);

CREATE TYPE eligibility.batch_status AS ENUM (
    'received',
    'processing',
    'completed',
    'completed_with_warnings',
    'failed',
    'rejected',
    'held_for_review'
);

CREATE TYPE eligibility.eligibility_status AS ENUM (
    'active',
    'inactive',
    'pending',
    'terminated',
    'expired',
    'suspended',
    'unknown'
);

CREATE TYPE eligibility.source_operation AS ENUM (
    'insert',
    'update',
    'deactivate',
    'delete',
    'snapshot',
    'correction'
);

CREATE TYPE eligibility.person_relationship_type AS ENUM (
    'employee',
    'spouse',
    'dependent',
    'domestic_partner',
    'beneficiary',
    'other'
);

CREATE TYPE eligibility.dq_status AS ENUM (
    'valid',
    'valid_with_warnings',
    'quarantined',
    'rejected',
    'pending_review',
    'superseded'
);

CREATE TYPE eligibility.error_severity AS ENUM (
    'sev_1',
    'sev_2',
    'sev_3',
    'sev_4',
    'sev_5'
);

CREATE TYPE eligibility.review_status AS ENUM (
    'open',
    'in_review',
    'partner_action_required',
    'resolved',
    'ignored',
    'closed'
);

CREATE TYPE eligibility.token_type AS ENUM (
    'normalized_email_hash',
    'phone_hash',
    'dob_hash',
    'name_dob_hash',
    'partner_employee_id_hash',
    'partner_person_id_hash',
    'partner_member_id_hash'
);

CREATE TYPE eligibility.tokenization_status AS ENUM (
    'not_required',
    'pending',
    'completed',
    'failed'
);

CREATE TYPE eligibility.encryption_status AS ENUM (
    'not_required',
    'encrypted',
    'failed'
);

COMMIT;
