-- Teacher access for enrollments -> students path used by attendance/grades.
-- Run in Supabase SQL Editor.

ALTER TABLE public.enrollments ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.students ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.classes ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "teacher_select_own_enrollments" ON public.enrollments;
DROP POLICY IF EXISTS "teacher_select_students_via_enrollments" ON public.students;

DO $$
DECLARE
  has_classes_teacher_id boolean := false;
  has_classes_teacher_text boolean := false;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='classes' AND column_name='teacher_id'
  ) INTO has_classes_teacher_id;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='classes' AND column_name IN ('teacher_name','teacher')
  ) INTO has_classes_teacher_text;

  IF has_classes_teacher_id THEN
    EXECUTE $p$
      CREATE POLICY "teacher_select_own_enrollments"
      ON public.enrollments
      FOR SELECT
      USING (
        EXISTS (
          SELECT 1
          FROM public.classes c
          JOIN public.staff st ON st.user_id = auth.uid()
          WHERE c.id = enrollments.class_id
            AND (c.teacher_id::text = st.id::text OR c.teacher_id::text = auth.uid()::text)
        )
      )
    $p$;
  ELSIF has_classes_teacher_text THEN
    EXECUTE $p$
      CREATE POLICY "teacher_select_own_enrollments"
      ON public.enrollments
      FOR SELECT
      USING (
        EXISTS (
          SELECT 1
          FROM public.classes c
          JOIN public.staff st ON st.user_id = auth.uid()
          WHERE c.id = enrollments.class_id
            AND (
              lower(trim(coalesce(c.teacher_name,''))) = lower(trim(coalesce(st.full_name_ar,'')))
              OR lower(trim(coalesce(c.teacher,''))) = lower(trim(coalesce(st.staff_code,'')))
              OR lower(trim(coalesce(c.teacher,''))) = lower(trim(coalesce(st.full_name_ar,'')))
            )
        )
      )
    $p$;
  END IF;

  EXECUTE $p$
    CREATE POLICY "teacher_select_students_via_enrollments"
    ON public.students
    FOR SELECT
    USING (
      EXISTS (
        SELECT 1
        FROM public.enrollments e
        WHERE e.student_id = students.id
          AND EXISTS (
            SELECT 1
            FROM public.classes c
            JOIN public.staff st ON st.user_id = auth.uid()
            WHERE c.id = e.class_id
              AND (
                (to_jsonb(c)->>'teacher_id' = st.id::text)
                OR (to_jsonb(c)->>'teacher_id' = auth.uid()::text)
                OR lower(trim(coalesce(to_jsonb(c)->>'teacher_name',''))) = lower(trim(coalesce(st.full_name_ar,'')))
                OR lower(trim(coalesce(to_jsonb(c)->>'teacher',''))) = lower(trim(coalesce(st.staff_code,'')))
                OR lower(trim(coalesce(to_jsonb(c)->>'teacher',''))) = lower(trim(coalesce(st.full_name_ar,'')))
              )
          )
      )
    )
  $p$;
END $$;

