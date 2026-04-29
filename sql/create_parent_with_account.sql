-- اختياري: بعد تنفيذ هذا في Supabase SQL Editor، ضَع في CONFIG داخل index.html:
--   createParentWithAccount: 'create_parent_with_account'
-- يجب أن تتطابق مفاتيح JSON المرسلة من الواجهة مع أعمدة جدول public.parents (snake_case).

CREATE OR REPLACE FUNCTION public.create_parent_with_account(p_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  r public.parents%ROWTYPE;
BEGIN
  INSERT INTO public.parents
  SELECT * FROM jsonb_populate_record(NULL::public.parents, p_data)
  RETURNING * INTO STRICT r;

  RETURN to_jsonb(r);
END;
$$;

REVOKE ALL ON FUNCTION public.create_parent_with_account(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_parent_with_account(jsonb) TO authenticated;
GRANT EXECUTE ON FUNCTION public.create_parent_with_account(jsonb) TO service_role;
