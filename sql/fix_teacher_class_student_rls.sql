-- Fix teacher view: allow teacher to read own classes and students.
-- This version is schema-safe (works if classes.teacher_id does NOT exist).
-- Run in Supabase SQL Editor (same project).

ALTER TABLE public.classes ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "teacher_select_own_classes" ON public.classes;
DROP POLICY IF EXISTS "teacher_select_students_of_own_classes" ON public.students;

DO $$
DECLARE
  has_classes_teacher_id boolean := false;
  has_classes_teacher_name boolean := false;
  has_students_class_id boolean := false;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='classes' AND column_name='teacher_id'
  ) INTO has_classes_teacher_id;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='classes' AND column_name IN ('teacher_name','teacher')
  ) INTO has_classes_teacher_name;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='students' AND column_name='class_id'
  ) INTO has_students_class_id;

  -- POLICY: teacher can read own classes
  IF has_classes_teacher_id THEN
    EXECUTE $p$
      CREATE POLICY "teacher_select_own_classes"
      ON public.classes
      FOR SELECT
      USING (
        EXISTS (
          SELECT 1
          FROM public.staff st
          WHERE st.id = classes.teacher_id
            AND st.user_id = auth.uid()
        )
      )
    $p$;
  ELSIF has_classes_teacher_name THEN
    -- Fallback when classes has teacher_name/teacher text only
    EXECUTE $p$
      CREATE POLICY "teacher_select_own_classes"
      ON public.classes
      FOR SELECT
      USING (
        EXISTS (
          SELECT 1
          FROM public.staff st
          WHERE st.user_id = auth.uid()
            AND lower(trim(coalesce(st.full_name_ar,''))) = lower(trim(coalesce(classes.teacher_name, classes.teacher, '')))
        )
      )
    $p$;
  ELSE
    RAISE NOTICE 'No teacher reference column found in public.classes; class policy not created.';
  END IF;

  -- POLICY: teacher can read students of own classes
  IF has_students_class_id AND has_classes_teacher_id THEN
    EXECUTE $p$
      CREATE POLICY "teacher_select_students_of_own_classes"
      ON public.students
      FOR SELECT
      USING (
        EXISTS (
          SELECT 1
          FROM public.classes c
          JOIN public.staff st ON st.id = c.teacher_id
          WHERE c.id = students.class_id
            AND st.user_id = auth.uid()
        )
      )
    $p$;
  ELSIF has_students_class_id AND has_classes_teacher_name THEN
    EXECUTE $p$
      CREATE POLICY "teacher_select_students_of_own_classes"
      ON public.students
      FOR SELECT
      USING (
        EXISTS (
          SELECT 1
          FROM public.classes c
          JOIN public.staff st
            ON lower(trim(coalesce(st.full_name_ar,''))) = lower(trim(coalesce(c.teacher_name, c.teacher, '')))
          WHERE c.id = students.class_id
            AND st.user_id = auth.uid()
        )
      )
    $p$;
  ELSE
    RAISE NOTICE 'Cannot create students policy (missing students.class_id or teacher reference in classes).';
  END IF;
END $$;
