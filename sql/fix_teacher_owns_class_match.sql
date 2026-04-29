-- Fix teacher_owns_class_id matching (strict + partial)
-- Use after emergency_fix_students_rls_recursion.sql

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

  -- If classes.teacher_id exists, prefer exact id matching.
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

  -- Textual fallback with strict + partial matching (name can be short in classes).
  SELECT EXISTS (
    SELECT 1
    FROM public.classes c
    JOIN public.staff st ON st.user_id = auth.uid()
    WHERE c.id::text = p_class_id_text
      AND (
        -- exact matches
        lower(trim(coalesce(to_jsonb(c)->>'teacher_name', ''))) = lower(trim(coalesce(st.full_name_ar, '')))
        OR lower(trim(coalesce(to_jsonb(c)->>'teacher', ''))) = lower(trim(coalesce(st.staff_code, '')))
        OR lower(trim(coalesce(to_jsonb(c)->>'teacher', ''))) = lower(trim(coalesce(st.full_name_ar, '')))
        -- partial matches
        OR (
          nullif(trim(coalesce(to_jsonb(c)->>'teacher_name', '')), '') IS NOT NULL
          AND (
            lower(coalesce(st.full_name_ar, '')) LIKE '%' || lower(trim(coalesce(to_jsonb(c)->>'teacher_name', ''))) || '%'
            OR lower(trim(coalesce(to_jsonb(c)->>'teacher_name', ''))) LIKE '%' || lower(trim(split_part(coalesce(st.full_name_ar, ''), ' ', 1))) || '%'
          )
        )
        OR (
          nullif(trim(coalesce(to_jsonb(c)->>'teacher', '')), '') IS NOT NULL
          AND (
            lower(coalesce(st.full_name_ar, '')) LIKE '%' || lower(trim(coalesce(to_jsonb(c)->>'teacher', ''))) || '%'
            OR lower(trim(coalesce(to_jsonb(c)->>'teacher', ''))) LIKE '%' || lower(trim(split_part(coalesce(st.full_name_ar, ''), ' ', 1))) || '%'
          )
        )
      )
  ) INTO ok;

  RETURN coalesce(ok, false);
END;
$$;

REVOKE ALL ON FUNCTION public.teacher_owns_class_id(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.teacher_owns_class_id(text) TO authenticated, service_role;

