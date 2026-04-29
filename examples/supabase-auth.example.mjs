/**
 * Example for Vite/ESM projects — mirror of patterns used in index.html.
 * Copy SUPABASE_URL / ANON_KEY from Dashboard → Settings → API.
 */
import { createClient } from '@supabase/supabase-js';

const SUPABASE_URL = import.meta.env.VITE_SUPABASE_URL || 'PASTE_URL_HERE';
const SUPABASE_ANON_KEY = import.meta.env.VITE_SUPABASE_ANON_KEY || 'PASTE_KEY_HERE';
const DEBUG = import.meta.env.DEV || import.meta.env.VITE_DEBUG_AUTH === '1';

export const supabase = createClient(SUPABASE_URL, SUPABASE_ANON_KEY, {
  auth: {
    persistSession: true,
    autoRefreshToken: true,
    detectSessionInUrl: true,
    flowType: 'pkce',
  },
});

function logAuth(label, obj) {
  if (!DEBUG) return;
  console.group(`[AUTH] ${label}`);
  console.log(obj);
  console.groupEnd();
}

function describeError(err) {
  const st = Number(err?.status) || 0;
  const msg = String(err?.message || '');
  if (st === 500) {
    return [
      'Supabase Auth returned HTTP 500 (server-side).',
      'Check: Dashboard → Logs (Auth), reset password for user,',
      'Authentication → Providers → Email (confirm email),',
      'and auth.users row integrity (instance_id, password hash).',
      msg ? `Message: ${msg}` : '',
    ].join(' ');
  }
  return msg || `Auth error${st ? ` (${st})` : ''}`;
}

export async function doLogin(email, password) {
  const em = String(email || '').trim().toLowerCase();
  logAuth('signInWithPassword', { email: em });
  try {
    const { data, error } = await supabase.auth.signInWithPassword({
      email: em,
      password: String(password),
    });
    if (error) {
      console.error('[LOGIN]', error, JSON.stringify({ name: error.name, message: error.message, status: error.status }));
      const ui = describeError(error);
      if (DEBUG) alert(ui);
      return { ok: false, error: error, message: ui };
    }
    logAuth('session', { user: data.user?.id, expires_at: data.session?.expires_at });
    return { ok: true, data };
  } catch (e) {
    console.error('[LOGIN] thrown', e);
    return { ok: false, error: e, message: String(e?.message || e) };
  }
}
