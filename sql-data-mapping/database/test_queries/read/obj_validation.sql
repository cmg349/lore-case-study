SELECT typname
FROM pg_type
WHERE typname = 'promotion_status';

SELECT table_name
FROM information_schema.tables
WHERE table_schema = 'eligibility'
  AND table_name = 'promotion_audit';

SELECT routine_name
FROM information_schema.routines
WHERE routine_schema = 'eligibility'
  AND routine_name IN (
    'promote_canonical_record',
    'promote_batch'
  );