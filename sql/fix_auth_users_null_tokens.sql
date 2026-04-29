-- Fix: signInWithPassword → 500 "Database error querying schema"
-- Causes (GoTrue):
--   1) auth.users token columns must be '' not NULL when users were inserted via raw SQL.
--   2) Email login requires a row in auth.identities (provider = 'email'); raw SQL on auth.users only is not enough.
-- Run once in Supabase SQL Editor (as project owner).

UPDATE auth.users
SET
  confirmation_token = coalesce(confirmation_token, ''),
  recovery_token = coalesce(recovery_token, ''),
  email_change = coalesce(email_change, ''),
  email_change_token_new = coalesce(email_change_token_new, '')
WHERE
  confirmation_token IS NULL
  OR recovery_token IS NULL
  OR email_change IS NULL
  OR email_change_token_new IS NULL;

-- Some projects also have this column nullable; ignore errors if column missing:
DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'auth' AND table_name = 'users' AND column_name = 'email_change_token_current'
  ) THEN
    EXECUTE $u$
      UPDATE auth.users
      SET email_change_token_current = coalesce(email_change_token_current, '')
      WHERE email_change_token_current IS NULL
    $u$;
  END IF;
END $$;

-- Backfill missing email identities (manual auth.users inserts often skip this).
INSERT INTO auth.identities (
  id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
)
SELECT
  gen_random_uuid(),
  u.id::text,
  u.id,
  jsonb_build_object(
    'sub', u.id::text,
    'email', u.email,
    'email_verified', (u.email_confirmed_at IS NOT NULL)
  ),
  'email',
  now(),
  now(),
  now()
FROM auth.users u
WHERE
  u.email IS NOT NULL
  AND btrim(u.email) <> ''
  AND NOT EXISTS (
    SELECT 1 FROM auth.identities i
    WHERE i.user_id = u.id AND i.provider = 'email'
  );
