-- إعدادات عامة للتطبيق (صلاحيات الأدوار JSON) — نفّذ في SQL Editor ثم أعد تحميل الواجهة.
-- القراءة: أي مستخدم مسجّل. الكتابة: فقط super_admin (profiles.role_id → roles.role_name).

CREATE TABLE IF NOT EXISTS public.app_settings (
  id text PRIMARY KEY,
  role_permissions jsonb NOT NULL DEFAULT '{}'::jsonb,
  updated_at timestamptz NOT NULL DEFAULT now()
);

INSERT INTO public.app_settings (id, role_permissions)
VALUES ('default', '{}'::jsonb)
ON CONFLICT (id) DO NOTHING;

ALTER TABLE public.app_settings ENABLE ROW LEVEL SECURITY;

DROP POLICY IF EXISTS app_settings_select_authenticated ON public.app_settings;
CREATE POLICY app_settings_select_authenticated ON public.app_settings
  FOR SELECT TO authenticated
  USING (true);

DROP POLICY IF EXISTS app_settings_insert_super ON public.app_settings;
CREATE POLICY app_settings_insert_super ON public.app_settings
  FOR INSERT TO authenticated
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.profiles p
      JOIN public.roles r ON r.id = p.role_id
      WHERE p.id = auth.uid()
        AND lower(trim(coalesce(r.role_name::text, ''))) = 'super_admin'
    )
  );

DROP POLICY IF EXISTS app_settings_update_super ON public.app_settings;
CREATE POLICY app_settings_update_super ON public.app_settings
  FOR UPDATE TO authenticated
  USING (
    EXISTS (
      SELECT 1
      FROM public.profiles p
      JOIN public.roles r ON r.id = p.role_id
      WHERE p.id = auth.uid()
        AND lower(trim(coalesce(r.role_name::text, ''))) = 'super_admin'
    )
  )
  WITH CHECK (
    EXISTS (
      SELECT 1
      FROM public.profiles p
      JOIN public.roles r ON r.id = p.role_id
      WHERE p.id = auth.uid()
        AND lower(trim(coalesce(r.role_name::text, ''))) = 'super_admin'
    )
  );

GRANT SELECT ON public.app_settings TO authenticated;
GRANT INSERT, UPDATE ON public.app_settings TO authenticated;

-- مهم للـ Realtime: ضم الجدول إلى publication (مرة واحدة فقط).
DO $$
BEGIN
  BEGIN
    ALTER PUBLICATION supabase_realtime ADD TABLE public.app_settings;
  EXCEPTION
    WHEN duplicate_object THEN NULL;
    WHEN undefined_object THEN NULL;
  END;
END $$;
