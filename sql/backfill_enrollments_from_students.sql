-- Backfill enrollments from students.class_id
-- Use when enrollments table is empty and students are already linked to classes.

ALTER TABLE public.enrollments ENABLE ROW LEVEL SECURITY;

DO $$
DECLARE
  has_students_class_id boolean := false;
  has_students_id boolean := false;
  has_enrollments_student_id boolean := false;
  has_enrollments_class_id boolean := false;
  has_enrollments_created_at boolean := false;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='students' AND column_name='class_id'
  ) INTO has_students_class_id;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='students' AND column_name='id'
  ) INTO has_students_id;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='enrollments' AND column_name='student_id'
  ) INTO has_enrollments_student_id;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='enrollments' AND column_name='class_id'
  ) INTO has_enrollments_class_id;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='enrollments' AND column_name='created_at'
  ) INTO has_enrollments_created_at;

  IF NOT (has_students_class_id AND has_students_id AND has_enrollments_student_id AND has_enrollments_class_id) THEN
    RAISE EXCEPTION 'Missing required columns. Need students(id,class_id) and enrollments(student_id,class_id).';
  END IF;

  IF has_enrollments_created_at THEN
    EXECUTE $q$
      INSERT INTO public.enrollments (student_id, class_id, created_at)
      SELECT s.id, s.class_id, now()
      FROM public.students s
      WHERE s.class_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1
          FROM public.enrollments e
          WHERE e.student_id = s.id
            AND e.class_id = s.class_id
        )
    $q$;
  ELSE
    EXECUTE $q$
      INSERT INTO public.enrollments (student_id, class_id)
      SELECT s.id, s.class_id
      FROM public.students s
      WHERE s.class_id IS NOT NULL
        AND NOT EXISTS (
          SELECT 1
          FROM public.enrollments e
          WHERE e.student_id = s.id
            AND e.class_id = s.class_id
        )
    $q$;
  END IF;
END $$;

-- quick check
SELECT count(*) AS enrollments_count FROM public.enrollments;
