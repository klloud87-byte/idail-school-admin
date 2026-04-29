-- فصول الأستاذ + عدد الطلاب (نفس منطق الإدارة) عبر SECURITY DEFINER عندما RLS يخفي classes أو العدد.
-- نفّذ في Supabase SQL Editor بعد teacher_get_my_students إن وُجد.

DROP FUNCTION IF EXISTS public.teacher_get_my_classes();

CREATE OR REPLACE FUNCTION public.teacher_get_my_classes()
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
STABLE
AS $$
DECLARE
  has_tid boolean;
  res jsonb;
BEGIN
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'classes' AND column_name = 'teacher_id'
  ) INTO has_tid;

  IF has_tid THEN
    SELECT coalesce(jsonb_agg(sub.jb), '[]'::jsonb) INTO res
    FROM (
      SELECT
        (to_jsonb(c) || jsonb_build_object(
          'student_count',
          (SELECT count(*)::int FROM public.students s
           WHERE s.class_id = c.id AND coalesce(s.is_active, true))
        )) AS jb
      FROM public.classes c
      INNER JOIN public.staff st ON st.user_id = auth.uid() AND c.teacher_id = st.id
    ) sub;
  ELSE
    SELECT coalesce(jsonb_agg(sub.jb), '[]'::jsonb) INTO res
    FROM (
      SELECT
        (to_jsonb(c) || jsonb_build_object(
          'student_count',
          (SELECT count(*)::int FROM public.students s
           WHERE s.class_id = c.id AND coalesce(s.is_active, true))
        )) AS jb
      FROM public.classes c
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
        )
    ) sub;
  END IF;

  RETURN coalesce(res, '[]'::jsonb);
END;
$$;

REVOKE ALL ON FUNCTION public.teacher_get_my_classes() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.teacher_get_my_classes() TO authenticated, service_role;
