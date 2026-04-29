-- Create table for real grades saved by teachers.
-- Run once in Supabase SQL Editor.

CREATE TABLE IF NOT EXISTS public.student_grades (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  student_id uuid NOT NULL,
  class_id text NULL,
  teacher_id text NULL,
  subject text NOT NULL,
  eval_type text NOT NULL DEFAULT 'exam',
  semester int NOT NULL DEFAULT 1,
  score numeric(5,2) NOT NULL CHECK (score >= 0 AND score <= 20),
  exam_date date NOT NULL DEFAULT CURRENT_DATE,
  notes text NULL,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.student_grades ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "student_grades_select_authenticated" ON public.student_grades;
DROP POLICY IF EXISTS "student_grades_insert_authenticated" ON public.student_grades;

CREATE POLICY "student_grades_select_authenticated"
ON public.student_grades
FOR SELECT
TO authenticated
USING (true);

CREATE POLICY "student_grades_insert_authenticated"
ON public.student_grades
FOR INSERT
TO authenticated
WITH CHECK (true);

ALTER PUBLICATION supabase_realtime ADD TABLE public.student_grades;
