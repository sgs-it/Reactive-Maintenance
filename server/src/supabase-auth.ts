import { db, managedDatabase } from './db.ts';
import { RequestError } from './workflow.ts';

export const uuidPattern = /^[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}$/i;
export const authSchema = managedDatabase ? 'rmcs_auth' : 'auth';
const unavailable = () => new RequestError(503, 'Sign-in is temporarily unavailable. Try again later.');

export function useSupabaseAuth() {
  const mode = process.env.RMCS_AUTH_MODE ?? 'supabase';
  if (mode !== 'supabase' && mode !== 'local') throw new Error('Set RMCS_AUTH_MODE to supabase or local.');
  return mode === 'supabase';
}

function authSettings() {
  const url = URL.parse(process.env.SUPABASE_URL ?? '');
  const key = process.env.SUPABASE_PUBLISHABLE_KEY?.trim();
  if (!url || url.protocol !== 'https:' || url.username || url.password || url.pathname !== '/' ||
      url.search || url.hash || !key?.startsWith('sb_publishable_')) {
    throw new Error('Set the HTTPS project origin (SUPABASE_URL) and SUPABASE_PUBLISHABLE_KEY for Supabase Auth.');
  }
  return { base: url.origin + '/auth/v1', key };
}

// Match the session to an approved RMCS account and enforce the provider's current access state.
export const activeSupabaseSession = `
  auth_user.id=u.auth_user_id AND auth_user.email_confirmed_at IS NOT NULL
  AND lower(auth_user.email)=u.email AND (auth_user.banned_until IS NULL OR auth_user.banned_until <= now())
  AND (auth_session.not_after IS NULL OR auth_session.not_after > now())
  AND NOT EXISTS (SELECT 1 FROM ${authSchema}.mfa_factors WHERE user_id=auth_user.id AND status='verified')`;

export async function checkAuthConfiguration() {
  if (!useSupabaseAuth()) return;
  authSettings();
  // Check the exact columns and permissions the API needs before accepting requests.
  await db.query(`
    SELECT id,email,email_confirmed_at,banned_until FROM ${authSchema}.users WHERE false;
    SELECT id,user_id,not_after FROM ${authSchema}.sessions WHERE false;
    SELECT user_id,status FROM ${authSchema}.mfa_factors WHERE false`);
}

async function authRequest(path: string, method: string, body: object, accessToken?: string) {
  const { base, key } = authSettings();
  try {
    return await fetch(base + path, {
      method,
      body: JSON.stringify(body),
      headers: {
        apikey: key,
        'Content-Type': 'application/json',
        ...(accessToken ? { Authorization: `Bearer ${accessToken}` } : {}),
      },
      redirect: 'error',
      signal: AbortSignal.timeout(10_000),
    });
  } catch {
    throw unavailable();
  }
}

async function authErrorCode(response: Response) {
  const error = await response.json().catch(() => null) as { error_code?: string } | null;
  return error?.error_code ?? '';
}

export function canCreateSupabaseUser() {
  return process.env.SUPABASE_SECRET_KEY?.trim().startsWith('sb_secret_') === true;
}

export async function createSupabaseUser(email: string, password: string) {
  if (!canCreateSupabaseUser()) {
    throw new RequestError(503, 'Creating a new Supabase identity requires a server-side Supabase secret key.');
  }
  const { base } = authSettings();
  let response: Response;
  try {
    response = await fetch(base + '/admin/users', {
      method: 'POST',
      headers: { apikey: process.env.SUPABASE_SECRET_KEY!.trim(), 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, email_confirm: true }),
      redirect: 'error',
      signal: AbortSignal.timeout(10_000),
    });
  } catch {
    throw new RequestError(503, 'Account creation could not be confirmed. Check Supabase before retrying.');
  }
  if (!response.ok) {
    const code = await authErrorCode(response);
    if (code === 'email_exists' || code === 'user_already_exists') {
      throw new RequestError(409, 'That email already has a Supabase account. Choose Link Existing Account.');
    }
    if (code === 'weak_password') throw new RequestError(400, 'Choose a stronger initial password.');
    if (response.status === 429) throw new RequestError(429, 'Too many account requests. Try again later.');
    throw new RequestError(503, 'Supabase could not create the account. Ask your administrator to check the configuration.');
  }
  const created = await response.json().catch(() => null) as { id?: string } | null;
  if (!created?.id || !uuidPattern.test(created.id)) {
    throw new RequestError(503, 'Account creation could not be confirmed. Check Supabase before retrying.');
  }
  return created.id;
}

export async function supabasePasswordLogin(email: string, password: string) {
  const response = await authRequest('/token?grant_type=password', 'POST', { email, password });
  if (!response.ok) {
    const code = await authErrorCode(response);
    if (response.status === 429) throw new RequestError(429, 'Too many sign-in attempts. Try again later.');
    if (['invalid_credentials', 'email_not_confirmed', 'user_banned'].includes(code)) {
      return null;
    }
    throw unavailable();
  }
  try {
    const { access_token: accessToken, user } = await response.json() as {
      access_token?: string; user?: { id?: string };
    };
    // Parse only the token received from Supabase over HTTPS. The database verifies session ownership.
    if (typeof accessToken !== 'string') throw unavailable();
    const encodedClaims = accessToken.split('.')[1];
    if (!encodedClaims) throw unavailable();
    const claims = JSON.parse(Buffer.from(encodedClaims, 'base64url').toString('utf8'));
    if (typeof user?.id !== 'string' || !uuidPattern.test(user.id) || claims.sub !== user.id ||
        typeof claims.session_id !== 'string' || !uuidPattern.test(claims.session_id) ||
        !Number.isSafeInteger(claims.exp) || claims.exp * 1000 <= Date.now()) throw unavailable();
    return {
      userId: user.id, sessionId: claims.session_id as string,
      expiresAt: claims.exp as number, accessToken,
    };
  } catch {
    throw unavailable();
  }
}

export async function updateSupabasePassword(accessToken: string, current: string, password: string) {
  const response = await authRequest('/user', 'PUT', { password, current_password: current }, accessToken);
  if (response.ok) {
    await response.body?.cancel();
    return;
  }
  const code = await authErrorCode(response);
  if (code === 'weak_password' || code === 'same_password') {
    throw new RequestError(400, 'Choose a different password that meets your company’s password requirements.');
  }
  if (code === 'reauthentication_needed') {
    throw new RequestError(400, 'Ask your RMCS administrator to reset your password.');
  }
  if (code === 'invalid_credentials' || code === 'validation_failed') {
    throw new RequestError(400, 'Check the current password and try again.');
  }
  if (response.status === 429) throw new RequestError(429, 'Too many password changes. Try again later.');
  throw unavailable();
}
