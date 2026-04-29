-- Audit + baseline fix for UPDATE/DELETE permissions in Supabase
-- Run this in Supabase SQL editor as project owner.

BEGIN;

-- 1) Ensure RLS enabled on app tables
ALTER TABLE IF EXISTS public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.parents ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.staff ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.payments ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.exams ENABLE ROW LEVEL SECURITY;
ALTER TABLE IF EXISTS public.timetable_slots ENABLE ROW LEVEL SECURITY;

-- 2) Remove conflicting old mutation policies (safe if missing)
DROP POLICY IF EXISTS "students_update_admin" ON public.students;
DROP POLICY IF EXISTS "students_delete_admin" ON public.students;
DROP POLICY IF EXISTS "parents_update_admin" ON public.parents;
DROP POLICY IF EXISTS "parents_delete_admin" ON public.parents;
DROP POLICY IF EXISTS "staff_update_admin" ON public.staff;
DROP POLICY IF EXISTS "staff_delete_admin" ON public.staff;
DROP POLICY IF EXISTS "payments_update_admin" ON public.payments;
DROP POLICY IF EXISTS "payments_delete_admin" ON public.payments;
DROP POLICY IF EXISTS "classes_update_admin" ON public.classes;
DROP POLICY IF EXISTS "classes_delete_admin" ON public.classes;
DROP POLICY IF EXISTS "exams_update_admin" ON public.exams;
DROP POLICY IF EXISTS "exams_delete_admin" ON public.exams;
DROP POLICY IF EXISTS "slots_update_admin" ON public.timetable_slots;
DROP POLICY IF EXISTS "slots_delete_admin" ON public.timetable_slots;

-- 3) Helper role check function for policies
CREATE OR REPLACE FUNCTION public.has_admin_role(_uid uuid)
RETURNS boolean
LANGUAGE plpgsql
STABLE
AS $$
DECLARE
  profile_json jsonb := '{}'::jsonb;
  role_value text := '';
BEGIN
  SELECT to_jsonb(p)
  INTO profile_json
  FROM public.profiles p
  WHERE p.id = _uid
  LIMIT 1;

  role_value := lower(
    coalesce(
      profile_json->>'app_role',
      profile_json->>'role',
      profile_json->>'user_role',
      profile_json->>'type',
      ''
    )
  );

  RETURN coalesce(role_value, '') IN ('super_admin','admin','receptionist');
END;
$$;

-- 4) Uniform mutation policies (UPDATE + DELETE)
CREATE POLICY "students_update_admin" ON public.students
FOR UPDATE TO authenticated
USING (public.has_admin_role(auth.uid()))
WITH CHECK (public.has_admin_role(auth.uid()));

CREATE POLICY "students_delete_admin" ON public.students
FOR DELETE TO authenticated
USING (public.has_admin_role(auth.uid()));

CREATE POLICY "parents_update_admin" ON public.parents
FOR UPDATE TO authenticated
USING (public.has_admin_role(auth.uid()))
WITH CHECK (public.has_admin_role(auth.uid()));

CREATE POLICY "parents_delete_admin" ON public.parents
FOR DELETE TO authenticated
USING (public.has_admin_role(auth.uid()));

CREATE POLICY "staff_update_admin" ON public.staff
FOR UPDATE TO authenticated
USING (public.has_admin_role(auth.uid()))
WITH CHECK (public.has_admin_role(auth.uid()));

CREATE POLICY "staff_delete_admin" ON public.staff
FOR DELETE TO authenticated
USING (public.has_admin_role(auth.uid()));

CREATE POLICY "payments_update_admin" ON public.payments
FOR UPDATE TO authenticated
USING (public.has_admin_role(auth.uid()))
WITH CHECK (public.has_admin_role(auth.uid()));

CREATE POLICY "payments_delete_admin" ON public.payments
FOR DELETE TO authenticated
USING (public.has_admin_role(auth.uid()));

CREATE POLICY "classes_update_admin" ON public.classes
FOR UPDATE TO authenticated
USING (public.has_admin_role(auth.uid()))
WITH CHECK (public.has_admin_role(auth.uid()));

CREATE POLICY "classes_delete_admin" ON public.classes
FOR DELETE TO authenticated
USING (public.has_admin_role(auth.uid()));

CREATE POLICY "exams_update_admin" ON public.exams
FOR UPDATE TO authenticated
USING (public.has_admin_role(auth.uid()))
WITH CHECK (public.has_admin_role(auth.uid()));

CREATE POLICY "exams_delete_admin" ON public.exams
FOR DELETE TO authenticated
USING (public.has_admin_role(auth.uid()));

CREATE POLICY "slots_update_admin" ON public.timetable_slots
FOR UPDATE TO authenticated
USING (public.has_admin_role(auth.uid()))
WITH CHECK (public.has_admin_role(auth.uid()));

CREATE POLICY "slots_delete_admin" ON public.timetable_slots
FOR DELETE TO authenticated
USING (public.has_admin_role(auth.uid()));

COMMIT;

-- 5) Diagnostics you can run after policy creation
-- Check policies:
-- SELECT schemaname, tablename, policyname, roles, cmd, qual, with_check
-- FROM pg_policies
-- WHERE schemaname='public'
--   AND tablename IN ('students','parents','staff','payments','classes','exams','timetable_slots')
-- ORDER BY tablename, cmd, policyname;

-- Check triggers that might block update/delete:
-- SELECT event_object_table AS table_name, trigger_name, action_timing, event_manipulation, action_statement
-- FROM information_schema.triggers
-- WHERE event_object_schema='public'
--   AND event_object_table IN ('students','parents','staff','payments','classes','exams','timetable_slots')
-- ORDER BY table_name, trigger_name;
