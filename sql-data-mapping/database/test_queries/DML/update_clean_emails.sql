UPDATE eligibility.canonical_eligibility_record
SET
    primary_email = lower(trim(primary_email::TEXT))::CITEXT,
    work_email = lower(trim(work_email::TEXT))::CITEXT,
    personal_email = lower(trim(personal_email::TEXT))::CITEXT,
    updated_at = now()
WHERE primary_email IS NOT NULL
   OR work_email IS NOT NULL
   OR personal_email IS NOT NULL;