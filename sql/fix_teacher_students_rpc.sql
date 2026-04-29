-- Fallback RPC for teacher roster when RLS blocks direct students select.
-- Run in Supabase SQL Editor (same project).

DROP FUNCTION IF EXISTS public.teacher_get_my_students();

CREATE OR REPLACE FUNCTION public.teacher_get_my_students()
RETURNS TABLE(
  id uuid,
  user_id uuid,
  student_code text,
  full_name_ar text,
  full_name_en text,
  class_id text,
  class_name text,
  level_code text,
  language text,
  gender text,
  phone1 text,
  email text,
  parent_code text,
  amount_due numeric,
  amount_paid numeric,
  is_active boolean
)
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  has_classes_teacher_id boolean := false;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='classes' AND column_name='teacher_id'
  ) INTO has_classes_teacher_id;

  IF has_classes_teacher_id THEN
    RETURN QUERY
    SELECT
      s.id,
      s.user_id,
      s.student_code,
      s.full_name_ar,
      s.full_name_en,
      s.class_id::text,
      c.name AS class_name,
      coalesce(nullif(row_to_json(s)->>'level_code',''), c.level, 'B1') AS level_code,
      coalesce(nullif(row_to_json(s)->>'language',''), c.language, 'EN') AS language,
      coalesce(nullif(row_to_json(s)->>'gender',''), 'male') AS gender,
      coalesce(nullif(row_to_json(s)->>'phone1',''), '') AS phone1,
      coalesce(nullif(row_to_json(s)->>'email',''), '') AS email,
      coalesce(p.parent_code, '') AS parent_code,
      coalesce((nullif(row_to_json(s)->>'amount_due',''))::numeric, 0) AS amount_due,
      coalesce((nullif(row_to_json(s)->>'amount_paid',''))::numeric, 0) AS amount_paid,
      coalesce((nullif(row_to_json(s)->>'is_active',''))::boolean, true) AS is_active
    FROM public.students s
    LEFT JOIN public.classes c ON c.id = s.class_id
    LEFT JOIN public.parents p ON p.id = s.parent_id
    JOIN public.staff st ON st.id = c.teacher_id
    WHERE st.user_id = auth.uid();
  ELSE
    -- Fallback: teacher_name/teacher with strict + partial matching
    RETURN QUERY
    SELECT
      s.id,
      s.user_id,
      s.student_code,
      s.full_name_ar,
      s.full_name_en,
      s.class_id::text,
      c.name AS class_name,
      coalesce(nullif(row_to_json(s)->>'level_code',''), c.level, 'B1') AS level_code,
      coalesce(nullif(row_to_json(s)->>'language',''), c.language, 'EN') AS language,
      coalesce(nullif(row_to_json(s)->>'gender',''), 'male') AS gender,
      coalesce(nullif(row_to_json(s)->>'phone1',''), '') AS phone1,
      coalesce(nullif(row_to_json(s)->>'email',''), '') AS email,
      coalesce(p.parent_code, '') AS parent_code,
      coalesce((nullif(row_to_json(s)->>'amount_due',''))::numeric, 0) AS amount_due,
      coalesce((nullif(row_to_json(s)->>'amount_paid',''))::numeric, 0) AS amount_paid,
      coalesce((nullif(row_to_json(s)->>'is_active',''))::boolean, true) AS is_active
    FROM public.students s
    LEFT JOIN public.classes c ON c.id = s.class_id
    LEFT JOIN public.parents p ON p.id = s.parent_id
    CROSS JOIN public.staff st
    WHERE st.user_id = auth.uid()
      AND (
        lower(trim(coalesce(row_to_json(c)->>'teacher_name', ''))) = lower(trim(coalesce(st.full_name_ar, '')))
        OR lower(trim(coalesce(row_to_json(c)->>'teacher', ''))) = lower(trim(coalesce(st.staff_code, '')))
        OR (
          nullif(trim(coalesce(row_to_json(c)->>'teacher_name', '')), '') IS NOT NULL
          AND (
            lower(coalesce(st.full_name_ar, '')) LIKE '%' || lower(trim(coalesce(row_to_json(c)->>'teacher_name', ''))) || '%'
            OR lower(trim(coalesce(row_to_json(c)->>'teacher_name', ''))) LIKE '%' || lower(trim(split_part(coalesce(st.full_name_ar, ''), ' ', 1))) || '%'
          )
        )
        OR (
          nullif(trim(coalesce(row_to_json(c)->>'teacher', '')), '') IS NOT NULL
          AND (
            lower(coalesce(st.full_name_ar, '')) LIKE '%' || lower(trim(coalesce(row_to_json(c)->>'teacher', ''))) || '%'
            OR lower(trim(coalesce(row_to_json(c)->>'teacher', ''))) = lower(trim(coalesce(st.full_name_ar, '')))
          )
        )
      );
  END IF;
END;
$$;

REVOKE ALL ON FUNCTION public.teacher_get_my_students() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.teacher_get_my_students() TO authenticated, service_role;