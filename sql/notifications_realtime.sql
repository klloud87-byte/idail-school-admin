-- إشعارات + مستلمون + Realtime + RPC إرسال (SECURITY DEFINER)
-- نفّذ في SQL Editor (مرة واحدة أو عند التحديث).

-- 1) جدول الإشعارات (يتوافق مع الأسماء الشائعة في المشاريع القديمة)
CREATE TABLE IF NOT EXISTS public.notifications (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  title text NOT NULL,
  content text NOT NULL,
  sender_id uuid REFERENCES public.profiles (id) ON DELETE SET NULL,
  target_type text NOT NULL DEFAULT 'all'
    CHECK (target_type IN ('all', 'all_parents', 'all_teachers', 'specific')),
  target_username text,
  created_at timestamptz NOT NULL DEFAULT now()
);

ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS target_type text;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS target_username text;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS sender_id uuid;
ALTER TABLE public.notifications ADD COLUMN IF NOT EXISTS created_at timestamptz;

DO $$
BEGIN
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'notifications' AND column_name = 'recipient_type'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'notifications' AND column_name = 'target_type'
  ) THEN
    ALTER TABLE public.notifications RENAME COLUMN recipient_type TO target_type;
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'notifications' AND column_name = 'body'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'notifications' AND column_name = 'content'
  ) THEN
    ALTER TABLE public.notifications RENAME COLUMN body TO content;
  END IF;
  IF EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'notifications' AND column_name = 'sent_at'
  ) AND NOT EXISTS (
    SELECT 1 FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name = 'notifications' AND column_name = 'created_at'
  ) THEN
    ALTER TABLE public.notifications RENAME COLUMN sent_at TO created_at;
  END IF;
END $$;

ALTER TABLE public.notifications
  DROP CONSTRAINT IF EXISTS notifications_target_type_check;
ALTER TABLE public.notifications
  ADD CONSTRAINT notifications_target_type_check
  CHECK (target_type IN ('all', 'all_parents', 'all_teachers', 'specific'));

-- 2) مستلمون (صف لكل مستخدم = يظهر في واجهته + Realtime حسب user_id)
CREATE TABLE IF NOT EXISTS public.notification_recipients (
  id uuid PRIMARY KEY DEFAULT gen_random_uuid(),
  notification_id uuid NOT NULL REFERENCES public.notifications (id) ON DELETE CASCADE,
  user_id uuid NOT NULL REFERENCES public.profiles (id) ON DELETE CASCADE,
  is_read boolean NOT NULL DEFAULT false,
  read_at timestamptz,
  created_at timestamptz NOT NULL DEFAULT now(),
  UNIQUE (notification_id, user_id)
);

ALTER TABLE public.notification_recipients ADD COLUMN IF NOT EXISTS created_at timestamptz NOT NULL DEFAULT now();
CREATE INDEX IF NOT EXISTS idx_notification_recipients_user ON public.notification_recipients (user_id);
CREATE INDEX IF NOT EXISTS idx_notification_recipients_notif ON public.notification_recipients (notification_id);

-- 3) Realtime
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'notifications'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notifications;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Could not add notifications to publication: %', SQLERRM;
END $$;

DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_publication_tables
    WHERE pubname = 'supabase_realtime' AND schemaname = 'public' AND tablename = 'notification_recipients'
  ) THEN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.notification_recipients;
  END IF;
EXCEPTION WHEN OTHERS THEN
  RAISE NOTICE 'Could not add notification_recipients to publication: %', SQLERRM;
END $$;

-- 4) RLS
ALTER TABLE public.notifications ENABLE ROW LEVEL SECURITY;
ALTER TABLE public.notification_recipients ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS "notifications_select_admin" ON public.notifications;
DROP POLICY IF EXISTS "notifications_select_via_recipient" ON public.notifications;
DROP POLICY IF EXISTS "nr_select_own" ON public.notification_recipients;
DROP POLICY IF EXISTS "nr_update_own" ON public.notification_recipients;

CREATE POLICY "notifications_select_admin" ON public.notifications
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.profiles p
      JOIN public.roles r ON r.id = p.role_id
      WHERE p.id = auth.uid() AND r.role_name = 'super_admin'
    )
  );

CREATE POLICY "notifications_select_via_recipient" ON public.notifications
  FOR SELECT USING (
    EXISTS (
      SELECT 1 FROM public.notification_recipients nr
      WHERE nr.notification_id = notifications.id AND nr.user_id = auth.uid()
    )
  );

CREATE POLICY "nr_select_own" ON public.notification_recipients
  FOR SELECT USING (user_id = auth.uid());

CREATE POLICY "nr_update_own" ON public.notification_recipients
  FOR UPDATE USING (user_id = auth.uid()) WITH CHECK (user_id = auth.uid());

-- 5) دالة مساعدة: هل المستخدم الحالي super_admin؟
CREATE OR REPLACE FUNCTION public._is_super_admin()
RETURNS boolean
LANGUAGE sql
STABLE
SECURITY DEFINER
SET search_path = public
AS $$
  SELECT EXISTS (
    SELECT 1 FROM public.profiles p
    JOIN public.roles r ON r.id = p.role_id
    WHERE p.id = auth.uid() AND r.role_name = 'super_admin'
  );
$$;

-- 6) إرسال إشعار + تعبئة المستلمين
CREATE OR REPLACE FUNCTION public.send_notification_broadcast(
  p_title text,
  p_content text,
  p_target_type text,
  p_target_username text DEFAULT NULL
)
RETURNS jsonb
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
DECLARE
  v_nid uuid;
  v_uid uuid;
  v_code text;
  v_norm text;
  v_email text;
BEGIN
  IF NOT public._is_super_admin() THEN
    RAISE EXCEPTION 'غير مصرح: فقط super_admin يرسل الإشعارات';
  END IF;

  IF coalesce(trim(p_title), '') = '' OR coalesce(trim(p_content), '') = '' THEN
    RAISE EXCEPTION 'العنوان والمحتوى مطلوبان';
  END IF;

  IF p_target_type NOT IN ('all', 'all_parents', 'all_teachers', 'specific') THEN
    RAISE EXCEPTION 'نوع المستلم غير صالح';
  END IF;

  IF p_target_type = 'specific' THEN
    v_code := upper(trim(coalesce(p_target_username, '')));
    v_norm := regexp_replace(v_code, '[^A-Z0-9]', '', 'g');
    IF v_code = '' THEN
      RAISE EXCEPTION 'لم يُحدد رمز المستخدم للإرسال المحدد';
    END IF;
    -- 1) تطابق مباشر مع رموز الجداول (سلوك قديم)
    SELECT p.user_id INTO v_uid FROM public.parents p WHERE upper(trim(p.parent_code)) = v_code LIMIT 1;
    IF v_uid IS NULL THEN
      SELECT s.user_id INTO v_uid FROM public.students s WHERE upper(trim(s.student_code)) = v_code LIMIT 1;
    END IF;
    IF v_uid IS NULL THEN
      SELECT s.user_id INTO v_uid FROM public.staff s WHERE upper(trim(s.staff_code)) = v_code LIMIT 1;
    END IF;
    -- 2) تطبيع كتسجيل الدخول: PA-001 = PA001 (نفس منطق get_email_by_username)
    IF v_uid IS NULL AND coalesce(v_norm, '') <> '' THEN
      SELECT p.user_id INTO v_uid FROM public.parents p
      WHERE regexp_replace(upper(trim(coalesce(p.parent_code, ''))), '[^A-Z0-9]', '', 'g') = v_norm
      LIMIT 1;
    END IF;
    IF v_uid IS NULL AND coalesce(v_norm, '') <> '' THEN
      SELECT s.user_id INTO v_uid FROM public.students s
      WHERE regexp_replace(upper(trim(coalesce(s.student_code, ''))), '[^A-Z0-9]', '', 'g') = v_norm
      LIMIT 1;
    END IF;
    IF v_uid IS NULL AND coalesce(v_norm, '') <> '' THEN
      SELECT s.user_id INTO v_uid FROM public.staff s
      WHERE regexp_replace(upper(trim(coalesce(s.staff_code, ''))), '[^A-Z0-9]', '', 'g') = v_norm
      LIMIT 1;
    END IF;
    -- 3) اسم المستخدم في profiles (id = auth user)
    IF v_uid IS NULL AND coalesce(v_norm, '') <> '' THEN
      SELECT pr.id INTO v_uid FROM public.profiles pr
      WHERE regexp_replace(upper(trim(coalesce(pr.username, ''))), '[^A-Z0-9]', '', 'g') = v_norm
      LIMIT 1;
    END IF;
    -- 4) fallback نهائي: نفس Resolver شاشة الدخول (username -> email -> profile.id)
    IF v_uid IS NULL AND coalesce(v_norm, '') <> '' THEN
      BEGIN
        SELECT public.get_email_by_username(v_code) INTO v_email;
      EXCEPTION WHEN undefined_function THEN
        v_email := NULL;
      END;
      IF coalesce(trim(v_email), '') <> '' THEN
        SELECT pr.id INTO v_uid
        FROM public.profiles pr
        WHERE lower(coalesce(pr.email, '')) = lower(trim(v_email))
        LIMIT 1;
      END IF;
    END IF;
    IF v_uid IS NULL THEN
      RAISE EXCEPTION 'لم يُعثر على مستخدم بالرمز أو اسم المستخدم %', v_code;
    END IF;
  END IF;

  INSERT INTO public.notifications (title, content, sender_id, target_type, target_username)
  VALUES (trim(p_title), trim(p_content), auth.uid(), p_target_type, nullif(trim(p_target_username), ''))
  RETURNING id INTO v_nid;

  IF p_target_type = 'all_parents' THEN
    INSERT INTO public.notification_recipients (notification_id, user_id)
    SELECT v_nid, p.user_id FROM public.parents p
    WHERE p.user_id IS NOT NULL
    ON CONFLICT (notification_id, user_id) DO NOTHING;

  ELSIF p_target_type = 'all_teachers' THEN
    INSERT INTO public.notification_recipients (notification_id, user_id)
    SELECT v_nid, s.user_id FROM public.staff s
    WHERE s.user_id IS NOT NULL AND lower(coalesce(s.job_type, '')) = 'teacher'
    ON CONFLICT (notification_id, user_id) DO NOTHING;

  ELSIF p_target_type = 'all' THEN
    INSERT INTO public.notification_recipients (notification_id, user_id)
    SELECT v_nid, t.uid FROM (
      SELECT p.user_id AS uid FROM public.parents p WHERE p.user_id IS NOT NULL
      UNION
      SELECT s.user_id FROM public.students s WHERE s.user_id IS NOT NULL
      UNION
      SELECT s.user_id FROM public.staff s
      WHERE s.user_id IS NOT NULL AND lower(coalesce(s.job_type, '')) = 'teacher'
    ) t
    WHERE t.uid IS NOT NULL
    ON CONFLICT (notification_id, user_id) DO NOTHING;

  ELSIF p_target_type = 'specific' THEN
    INSERT INTO public.notification_recipients (notification_id, user_id)
    VALUES (v_nid, v_uid)
    ON CONFLICT (notification_id, user_id) DO NOTHING;
  END IF;

  RETURN jsonb_build_object('success', true, 'notification_id', v_nid);
END;
$$;

REVOKE ALL ON FUNCTION public.send_notification_broadcast(text, text, text, text) FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public.send_notification_broadcast(text, text, text, text) TO authenticated, service_role;

REVOKE ALL ON FUNCTION public._is_super_admin() FROM PUBLIC;
GRANT EXECUTE ON FUNCTION public._is_super_admin() TO authenticated, service_role;
