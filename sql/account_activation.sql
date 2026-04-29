-- Account activation (Supabase SQL Editor).
-- is_active / can_login: DEFAULT true so new profile rows are login-ready; super_admin can deactivate via admin_set_profile_login_active.

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'is_active'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN is_active boolean;
    UPDATE public.profiles SET is_active = true WHERE is_active IS NULL;
    ALTER TABLE public.profiles ALTER COLUMN is_active SET NOT NULL;
    ALTER TABLE public.profiles ALTER COLUMN is_active SET DEFAULT true;
  ELSE
    UPDATE public.profiles SET is_active = true WHERE is_active IS NULL;
    ALTER TABLE public.profiles ALTER COLUMN is_active SET DEFAULT true;
  END IF;

  IF NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'profiles' AND column_name = 'can_login'
  ) THEN
    ALTER TABLE public.profiles ADD COLUMN can_login boolean;
    UPDATE public.profiles SET can_login = true WHERE can_login IS NULL;
    ALTER TABLE public.profiles ALTER COLUMN can_login SET NOT NULL;
    ALTER TABLE public.profiles ALTER COLUMN can_login SET DEFAULT true;
  ELSE
    UPDATE public.profiles SET can_login = true WHERE can_login IS NULL;
    ALTER TABLE public.profiles ALTER COLUMN can_login SET DEFAULT true;
  END IF;
END $$;

COMMENT ON COLUMN public.profiles.is_active IS 'Login gate: default true; super_admin may set false via admin_set_profile_login_active.';

-- Same signature (uuid, boolean) as an older deploy: must DROP first — Postgres forbids renaming args via CREATE OR REPLACE (42P13).
DROP FUNCTION IF EXISTS public.admin_set_profile_login_active(uuid, boolean);

-- PostgREST / supabase-js body: { "user_id": "...", "status": true }
CREATE FUNCTION public.admin_set_profile_login_active(user_id uuid, status boolean)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_caller uuid := auth.uid();
  v_is_super boolean := false;
BEGIN
  IF v_caller IS NULL THEN
    RAISE EXCEPTION 'Unauthorized';
  END IF;
  IF user_id = v_caller AND NOT coalesce(status, false) THEN
    RAISE EXCEPTION 'You cannot deactivate your own account';
  END IF;

  SELECT EXISTS (
    SELECT 1
    FROM public.profiles p
    JOIN public.roles r ON r.id = p.role_id
    WHERE p.id = v_caller
      AND lower(coalesce(r.role_name, '')) = 'super_admin'
  ) INTO v_is_super;

  IF NOT v_is_super THEN
    RAISE EXCEPTION 'Only super_admin may change account activation';
  END IF;

  IF NOT EXISTS (SELECT 1 FROM public.profiles WHERE id = user_id) THEN
    RAISE EXCEPTION 'Profile not found';
  END IF;

  UPDATE public.profiles
  SET
    is_active = coalesce(status, false),
    can_login = coalesce(status, false)
  WHERE id = user_id;

  RETURN jsonb_build_object(
    'success', true,
    'user_id', user_id,
    'is_active', coalesce(status, false)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.admin_set_profile_login_active(uuid, boolean) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.admin_set_profile_login_active(uuid, boolean) TO anon, authenticated, service_role;
