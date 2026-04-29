-- Emergency fix for: 42P17 infinite recursion detected in policy for relation "students"
-- Safe approach:
-- 1) Drop teacher policies that may recurse
-- 2) Create helper function that checks class ownership WITHOUT querying students
-- 3) Recreate non-recursive students/enrollments policies

ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.classes ENABLE ROW LEVEL SECURITY;

-- Drop known policies created during previous attempts
DROP POLICY IF EXISTS "teacher_select_students_via_enrollments" ON public.students;
DROP POLICY IF EXISTS "teacher_select_students_of_own_classes" ON public.students;
DROP POLICY IF EXISTS "Teacher can view students" ON public.students;
DROP POLICY IF EXISTS "teacher_select_own_enrollments" ON public.enrollments;
DROP POLICY IF EXISTS "Teacher can view their students" ON public.enrollments;

-- Drop any students policy that references enrollments (common recursion source)
DO $$
DECLARE
  p record;
BEGIN
  FOR p IN
    SELECT policyname
    FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename = 'students'
      AND (
        coalesce(qual,'') ILIKE '%enrollments%'
        OR coalesce(with_check,'') ILIKE '%enrollments%'
      )
  LOOP
    EXECUTE format('DROP POLICY IF EXISTS %I ON public.students', p.policyname);
  END LOOP;
END $$;

-- Helper: checks if current teacher owns a class id (by id, no students access)
CREATE OR REPLACE FUNCTION public.teacher_owns_class_id(p_class_id_text text)
RETURNS boolean
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  ok boolean := false;
BEGIN
  IF p_class_id_text IS NULL OR btrim(p_class_id_text) = '' THEN
    RETURN false;
  END IF;

  -- Branch 1: classes.teacher_id exists
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='classes' AND column_name='teacher_id'
  ) THEN
    SELECT EXISTS (
      SELECT 1
      FROM public.classes c
      JOIN public.staff st ON st.user_id = auth.uid()
      WHERE c.id::text = p_class_id_text
        AND (
          c.teacher_id::text = st.id::text
          OR c.teacher_id::text = auth.uid()::text
        )
    ) INTO ok;
    IF ok THEN RETURN true; END IF;
  END IF;

  -- Branch 2: textual teacher fields
  SELECT EXISTS (
    SELECT 1
    FROM public.classes c
    JOIN public.staff st ON st.user_id = auth.uid()
    WHERE c.id::text = p_class_id_text
      AND (
        lower(trim(coalesce(to_jsonb(c)->>'teacher_name', ''))) = lower(trim(coalesce(st.full_name_ar, '')))
        OR lower(trim(coalesce(to_jsonb(c)->>'teacher', ''))) = lower(trim(coalesce(st.staff_code, '')))
        OR lower(trim(coalesce(to_jsonb(c)->>'teacher', ''))) = lower(trim(coalesce(st.full_name_ar, '')))
      )
  ) INTO ok;

  RETURN coalesce(ok, false);
END;
$$;

REVOKE ALL ON FUNCTION public.teacher_owns_class_id(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.teacher_owns_class_id(text) TO authenticated, service_role;

-- Non-recursive students policy: only uses students.class_id + helper
CREATE POLICY "teacher_select_students_non_recursive"
ON public.students
FOR SELECT
TO authenticated
USING (
  public.teacher_owns_class_id(to_jsonb(students)->>'class_id')
);

-- Non-recursive enrollments policy
CREATE POLICY "teacher_select_enrollments_non_recursive"
ON public.enrollments
FOR SELECT
TO authenticated
USING (
  public.teacher_owns_class_id(to_jsonb(enrollments)->>'class_id')
);

