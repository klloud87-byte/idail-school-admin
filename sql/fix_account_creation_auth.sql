-- Run this file in Supabase SQL Editor (one time).
-- Goal: create real auth.users + profiles + domain row (single transaction).
-- New profiles: is_active=true / can_login=true so users can log in immediately (admin may deactivate later via UI/RPC).
CREATE EXTENSION IF NOT EXISTS pgcrypto;

CREATE OR REPLACE FUNCTION public._mk_temp_password(p_seed text DEFAULT 'IDAIL')
RETURNS text
LANGUAGE plpgsql
AS $$
DECLARE
  s text := upper(regexp_replace(coalesce(p_seed,'IDAIL'),'[^A-Za-z0-9]','','g'));
BEGIN
  s := left(s,6);
  IF s = '' THEN s := 'IDAIL'; END IF;
  RETURN s || '@' || to_char(now(),'YYYY') || '#' || upper(substr(md5(random()::text),1,4));
END;
$$;

CREATE OR REPLACE FUNCTION public.create_parent_with_account(p_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_parent_id uuid;
  v_user_id uuid;
  v_role_id int;
  v_parent_code text;
  v_username text;
  v_email text;
  v_password text;
  v_instance uuid;
BEGIN
  SELECT coalesce((SELECT id FROM auth.instances LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid)
  INTO v_instance;

  v_parent_code := upper(coalesce(p_data->>'parent_code',''));
  IF v_parent_code = '' THEN
    RAISE EXCEPTION 'parent_code مطلوب';
  END IF;
  v_username := v_parent_code;
  v_email := lower(trim(coalesce(
    nullif(trim(coalesce(p_data->>'email','')), ''),
    lower(replace(v_parent_code,'-','')) || '@idail.dz'
  )));
  IF exists (SELECT 1 FROM auth.users au WHERE lower(trim(au.email)) = v_email) THEN
    RAISE EXCEPTION 'البريد الإلكتروني مستخدم مسبقاً';
  END IF;
  v_password := public._mk_temp_password(v_parent_code);

  v_user_id := gen_random_uuid();
  SELECT id INTO v_role_id FROM roles WHERE role_name='parent' LIMIT 1;
  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'الدور parent غير موجود في roles';
  END IF;

  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, role, aud, created_at, updated_at, confirmation_sent_at,
    confirmation_token, recovery_token, email_change, email_change_token_new
  ) VALUES (
    v_user_id,
    v_instance,
    v_email,
    extensions.crypt(v_password, extensions.gen_salt('bf')),
    now(),
    jsonb_build_object('provider','email','providers',array['email'],'role','parent'),
    jsonb_build_object('username',v_username,'role','parent','full_name',coalesce(p_data->>'full_name_ar','')),
    'authenticated',
    'authenticated',
    now(), now(), now(),
    '', '', '', ''
  );

  INSERT INTO auth.identities (
    id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) VALUES (
    gen_random_uuid(),
    v_user_id::text,
    v_user_id,
    jsonb_build_object(
      'sub', v_user_id::text,
      'email', v_email,
      'email_verified', true
    ),
    'email',
    now(), now(), now()
  );

  INSERT INTO profiles (id, username, role_id, is_active, can_login, full_name_ar, full_name_en, email, phone, must_change_password, created_at)
  VALUES (
    v_user_id, v_username, v_role_id, true, true,
    coalesce(p_data->>'full_name_ar',''),
    coalesce(p_data->>'full_name_en',''),
    v_email,
    coalesce(p_data->>'phone1','0000000000'),
    true,
    now()
  )
  ON CONFLICT (id) DO UPDATE SET
    username = excluded.username,
    role_id = excluded.role_id,
    is_active = profiles.is_active,
    can_login = profiles.can_login,
    full_name_ar = excluded.full_name_ar,
    full_name_en = excluded.full_name_en,
    email = excluded.email,
    phone = excluded.phone,
    must_change_password = excluded.must_change_password;

  INSERT INTO parents (
    user_id, parent_code, full_name_ar, full_name_en, date_of_birth, national_id, address, phone1, phone2, email,
    relation, whatsapp, doc_type, doc_issue_date, doc_issue_place, job, employer, monthly_income,
    is_payer, has_discount, discount_note, emergency_name, emergency_relation, emergency_phone, emergency_phone2,
    wilaya, neighborhood, notes, kids_count
  )
  VALUES (
    v_user_id, v_parent_code, coalesce(p_data->>'full_name_ar',''), coalesce(p_data->>'full_name_en',''),
    nullif(p_data->>'date_of_birth','')::date, nullif(p_data->>'national_id',''), nullif(p_data->>'address',''),
    coalesce(nullif(p_data->>'phone1',''),'0000000000'), nullif(p_data->>'phone2',''), v_email,
    coalesce(nullif(p_data->>'relation',''),'father'), nullif(p_data->>'whatsapp',''), nullif(p_data->>'doc_type',''),
    nullif(p_data->>'doc_issue_date','')::date, nullif(p_data->>'doc_issue_place',''), nullif(p_data->>'job',''),
    nullif(p_data->>'employer',''), nullif(p_data->>'monthly_income','')::numeric,
    coalesce((p_data->>'is_payer')::boolean,true), coalesce((p_data->>'has_discount')::boolean,false), nullif(p_data->>'discount_note',''),
    nullif(p_data->>'emergency_name',''), nullif(p_data->>'emergency_relation',''), nullif(p_data->>'emergency_phone',''),
    nullif(p_data->>'emergency_phone2',''), nullif(p_data->>'wilaya',''), nullif(p_data->>'neighborhood',''),
    nullif(p_data->>'notes',''), coalesce((p_data->>'kids_count')::int,0)
  )
  RETURNING id INTO v_parent_id;

  RETURN jsonb_build_object(
    'success', true,
    'parent_id', v_parent_id,
    'username', v_username,
    'password', v_password,
    'parent_code', v_parent_code,
    'email', v_email
  );
END;
$$;

CREATE OR REPLACE FUNCTION public.create_staff_with_account(p_data jsonb)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_staff_id uuid;
  v_user_id uuid;
  v_role_id int;
  v_code text;
  v_role_name text;
  v_email text;
  v_password text;
  v_instance uuid;
BEGIN
  SELECT coalesce((SELECT id FROM auth.instances LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid)
  INTO v_instance;

  v_code := upper(coalesce(p_data->>'staff_code',''));
  IF v_code='' THEN RAISE EXCEPTION 'staff_code مطلوب'; END IF;
  v_role_name := case when coalesce(p_data->>'job_type','')='admin' then 'receptionist' else coalesce(p_data->>'job_type','receptionist') end;
  v_email := lower(trim(coalesce(
    nullif(trim(coalesce(p_data->>'email','')), ''),
    lower(replace(v_code,'-','')) || '@idail.dz'
  )));
  IF exists (SELECT 1 FROM auth.users au WHERE lower(trim(au.email)) = v_email) THEN
    RAISE EXCEPTION 'البريد الإلكتروني مستخدم مسبقاً';
  END IF;
  v_password := public._mk_temp_password(v_code);

  v_user_id := gen_random_uuid();
  SELECT id INTO v_role_id FROM roles WHERE role_name=v_role_name LIMIT 1;
  IF v_role_id IS NULL THEN
    SELECT id INTO v_role_id FROM roles WHERE role_name='receptionist' LIMIT 1;
  END IF;

  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, role, aud, created_at, updated_at, confirmation_sent_at,
    confirmation_token, recovery_token, email_change, email_change_token_new
  ) VALUES (
    v_user_id,
    v_instance,
    v_email,
    extensions.crypt(v_password, extensions.gen_salt('bf')),
    now(),
    jsonb_build_object('provider','email','providers',array['email'],'role',v_role_name),
    jsonb_build_object('username',v_code,'role',v_role_name,'full_name',coalesce(p_data->>'full_name_ar','')),
    'authenticated',
    'authenticated',
    now(), now(), now(),
    '', '', '', ''
  );

  INSERT INTO auth.identities (
    id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) VALUES (
    gen_random_uuid(),
    v_user_id::text,
    v_user_id,
    jsonb_build_object(
      'sub', v_user_id::text,
      'email', v_email,
      'email_verified', true
    ),
    'email',
    now(), now(), now()
  );

  INSERT INTO profiles (id, username, role_id, is_active, can_login, full_name_ar, full_name_en, email, phone, must_change_password, created_at)
  VALUES (
    v_user_id, v_code, v_role_id, true, true,
    coalesce(p_data->>'full_name_ar',''), coalesce(p_data->>'full_name_en',''),
    v_email, coalesce(p_data->>'phone1','0000000000'), true, now()
  )
  ON CONFLICT (id) DO UPDATE SET
    username = excluded.username,
    role_id = excluded.role_id,
    is_active = profiles.is_active,
    can_login = profiles.can_login,
    full_name_ar = excluded.full_name_ar,
    full_name_en = excluded.full_name_en,
    email = excluded.email,
    phone = excluded.phone,
    must_change_password = excluded.must_change_password;

  INSERT INTO staff (
    user_id, staff_code, full_name_ar, full_name_en, phone1, email, hire_date, job_type, contract_type, salary, qualification, is_active
  ) VALUES (
    v_user_id, v_code, coalesce(p_data->>'full_name_ar',''), coalesce(p_data->>'full_name_en',''),
    coalesce(p_data->>'phone1','0000000000'), v_email, nullif(p_data->>'hire_date','')::date,
    coalesce(nullif(p_data->>'job_type',''),'receptionist'),
    coalesce(nullif(p_data->>'contract_type',''),'permanent'),
    nullif(p_data->>'salary','')::numeric,
    nullif(p_data->>'qualification',''),
    coalesce((p_data->>'is_active')::boolean,true)
  )
  RETURNING id INTO v_staff_id;

  RETURN jsonb_build_object(
    'success', true,
    'staff_id', v_staff_id,
    'username', v_code,
    'password', v_password,
    'staff_code', v_code,
    'email', v_email
  );
END;
$$;

-- Permissions for web app role
REVOKE ALL ON FUNCTION public.create_parent_with_account(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_parent_with_account(jsonb) TO anon, authenticated, service_role;

REVOKE ALL ON FUNCTION public.create_staff_with_account(jsonb) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_staff_with_account(jsonb) TO anon, authenticated, service_role;

-- Student account creator compatible with current frontend RPC signature
DROP FUNCTION IF EXISTS public.create_student_with_account(text,text,uuid,text,date,text,text,text,text,integer,date);
CREATE OR REPLACE FUNCTION public.create_student_with_account(
  p_full_name_ar text,
  p_full_name_en text,
  p_parent_id uuid,
  p_gender text,
  p_date_of_birth date,
  p_phone1 text,
  p_email text DEFAULT NULL,
  p_address text DEFAULT NULL,
  p_national_id text DEFAULT NULL,
  p_class_id integer DEFAULT NULL,
  p_enrollment_date date DEFAULT CURRENT_DATE,
  p_level_code text DEFAULT 'B1',
  p_language text DEFAULT 'English',
  p_pay_status text DEFAULT 'unpaid',
  p_amount_due numeric DEFAULT 0,
  p_amount_paid numeric DEFAULT 0
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public, extensions
AS $$
DECLARE
  v_user_id uuid;
  v_role_id int;
  v_student_code text;
  v_username text;
  v_email text;
  v_password text;
  v_student_id uuid;
  v_instance uuid;
  has_level_code boolean := false;
  has_current_level boolean := false;
  has_grade_level boolean := false;
  has_language boolean := false;
  has_current_lang boolean := false;
  has_pay_status boolean := false;
BEGIN
  SELECT coalesce((SELECT id FROM auth.instances LIMIT 1), '00000000-0000-0000-0000-000000000000'::uuid)
  INTO v_instance;

  IF coalesce(trim(p_full_name_ar),'')='' THEN
    RAISE EXCEPTION 'الاسم الكامل بالعربية مطلوب';
  END IF;

  IF p_parent_id IS NOT NULL AND NOT EXISTS (SELECT 1 FROM parents WHERE id=p_parent_id) THEN
    RAISE EXCEPTION 'معرف ولي الأمر غير موجود';
  END IF;

  v_student_code := 'ET-' || lpad(nextval('student_code_seq')::text,3,'0');
  v_username := v_student_code;
  v_email := lower(trim(coalesce(
    nullif(trim(coalesce(p_email,'')), ''),
    lower(replace(v_student_code,'-','')) || '@idail.dz'
  )));
  IF exists (SELECT 1 FROM auth.users au WHERE lower(trim(au.email)) = v_email) THEN
    RAISE EXCEPTION 'البريد الإلكتروني مستخدم مسبقاً';
  END IF;
  v_password := public._mk_temp_password(v_student_code);

  v_user_id := gen_random_uuid();
  SELECT id INTO v_role_id FROM roles WHERE role_name='student' LIMIT 1;
  IF v_role_id IS NULL THEN
    RAISE EXCEPTION 'الدور student غير موجود في roles';
  END IF;

  INSERT INTO auth.users (
    id, instance_id, email, encrypted_password, email_confirmed_at,
    raw_app_meta_data, raw_user_meta_data, role, aud, created_at, updated_at, confirmation_sent_at,
    confirmation_token, recovery_token, email_change, email_change_token_new
  ) VALUES (
    v_user_id,
    v_instance,
    v_email,
    extensions.crypt(v_password, extensions.gen_salt('bf')),
    now(),
    jsonb_build_object('provider','email','providers',array['email'],'role','student'),
    jsonb_build_object('username',v_username,'role','student','full_name',p_full_name_ar),
    'authenticated',
    'authenticated',
    now(), now(), now(),
    '', '', '', ''
  );

  INSERT INTO auth.identities (
    id, provider_id, user_id, identity_data, provider, last_sign_in_at, created_at, updated_at
  ) VALUES (
    gen_random_uuid(),
    v_user_id::text,
    v_user_id,
    jsonb_build_object(
      'sub', v_user_id::text,
      'email', v_email,
      'email_verified', true
    ),
    'email',
    now(), now(), now()
  );

  INSERT INTO profiles (id, username, role_id, is_active, can_login, full_name_ar, full_name_en, email, phone, must_change_password, created_at)
  VALUES (
    v_user_id, v_username, v_role_id, true, true,
    p_full_name_ar, coalesce(p_full_name_en,''), v_email, coalesce(p_phone1,'0000000000'), true, now()
  )
  ON CONFLICT (id) DO UPDATE SET
    username = excluded.username,
    role_id = excluded.role_id,
    is_active = profiles.is_active,
    can_login = profiles.can_login,
    full_name_ar = excluded.full_name_ar,
    full_name_en = excluded.full_name_en,
    email = excluded.email,
    phone = excluded.phone,
    must_change_password = excluded.must_change_password;

  INSERT INTO students (
    user_id, student_code, full_name_ar, full_name_en, parent_id, gender, date_of_birth, phone1,
    address, national_id, enrollment_date, is_active, amount_due, amount_paid, class_id, email
  )
  VALUES (
    v_user_id, v_student_code, p_full_name_ar, coalesce(p_full_name_en,''), p_parent_id, coalesce(nullif(p_gender,''),'male'),
    p_date_of_birth, coalesce(p_phone1,'0000000000'), p_address, p_national_id, coalesce(p_enrollment_date,current_date),
    true, greatest(coalesce(p_amount_due,0),0), greatest(coalesce(p_amount_paid,0),0), p_class_id, v_email
  )
  RETURNING id INTO v_student_id;

  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='students' AND column_name='level_code'
  ) INTO has_level_code;
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='students' AND column_name='current_level'
  ) INTO has_current_level;
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='students' AND column_name='grade_level'
  ) INTO has_grade_level;
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='students' AND column_name='language'
  ) INTO has_language;
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='students' AND column_name='current_lang'
  ) INTO has_current_lang;
  SELECT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema='public' AND table_name='students' AND column_name='pay_status'
  ) INTO has_pay_status;

  IF has_level_code THEN
    UPDATE students SET level_code = coalesce(nullif(p_level_code,''),'B1') WHERE id=v_student_id;
  END IF;
  IF has_current_level THEN
    UPDATE students SET current_level = coalesce(nullif(p_level_code,''),'B1') WHERE id=v_student_id;
  END IF;
  IF has_grade_level THEN
    UPDATE students SET grade_level = coalesce(nullif(p_level_code,''),'B1') WHERE id=v_student_id;
  END IF;
  IF has_language THEN
    UPDATE students SET language = coalesce(nullif(p_language,''),'English') WHERE id=v_student_id;
  END IF;
  IF has_current_lang THEN
    UPDATE students SET current_lang = coalesce(nullif(p_language,''),'English') WHERE id=v_student_id;
  END IF;
  IF has_pay_status THEN
    UPDATE students SET pay_status = coalesce(nullif(p_pay_status,''),'unpaid') WHERE id=v_student_id;
  END IF;

  RETURN jsonb_build_object(
    'success', true,
    'student_id', v_student_id,
    'student_code', v_student_code,
    'username', v_username,
    'password', v_password,
    'email', v_email,
    'message', format('تم إنشاء الطالب "%s" بنجاح', p_full_name_ar)
  );
END;
$$;

REVOKE ALL ON FUNCTION public.create_student_with_account(text,text,uuid,text,date,text,text,text,text,integer,date,text,text,text,numeric,numeric) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.create_student_with_account(text,text,uuid,text,date,text,text,text,text,integer,date,text,text,text,numeric,numeric) TO anon, authenticated, service_role;

-- Username -> email resolver used by login screen
DROP FUNCTION IF EXISTS public.get_email_by_username(text);
CREATE OR REPLACE FUNCTION public.get_email_by_username(username_input text)
RETURNS text
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  u text := upper(coalesce(username_input,''));
  n text := regexp_replace(u,'[^A-Z0-9]','','g');
  em text;
BEGIN
  SELECT email INTO em
  FROM profiles
  WHERE upper(regexp_replace(coalesce(username,''),'[^A-Z0-9]','','g')) = n
  LIMIT 1;
  IF em IS NOT NULL THEN RETURN em; END IF;

  SELECT p.email INTO em
  FROM parents pa
  LEFT JOIN profiles p ON p.id = pa.user_id
  WHERE upper(regexp_replace(coalesce(pa.parent_code,''),'[^A-Z0-9]','','g')) = n
  LIMIT 1;
  IF em IS NOT NULL THEN RETURN em; END IF;

  SELECT p.email INTO em
  FROM students st
  LEFT JOIN profiles p ON p.id = st.user_id
  WHERE upper(regexp_replace(coalesce(st.student_code,''),'[^A-Z0-9]','','g')) = n
  LIMIT 1;
  IF em IS NOT NULL THEN RETURN em; END IF;

  SELECT p.email INTO em
  FROM staff sf
  LEFT JOIN profiles p ON p.id = sf.user_id
  WHERE upper(regexp_replace(coalesce(sf.staff_code,''),'[^A-Z0-9]','','g')) = n
  LIMIT 1;

  RETURN em;
END;
$$;

REVOKE ALL ON FUNCTION public.get_email_by_username(text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.get_email_by_username(text) TO anon, authenticated, service_role;

