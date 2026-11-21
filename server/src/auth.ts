import { createHash, randomBytes, scrypt, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
import { db, transaction } from './db.ts';
import {
  activeSupabaseSession, authSchema, supabasePasswordLogin, updateSupabasePassword, useSupabaseAuth,
} from './supabase-auth.ts';
import { RequestError } from './workflow.ts';
import type { User } from './workflow.ts';

const derive = promisify(scrypt);
const digest = (token: string) => createHash('sha256').update(token).digest('hex');
const dummyHash = `${'0'.repeat(32)}:${'0'.repeat(128)}`;

export async function hashPassword(password: string, salt = randomBytes(16).toString('hex')) {
  return `${salt}:${(await derive(password, salt, 64) as Buffer).toString('hex')}`;
}

export function validNewPassword(password: unknown): password is string {
  return typeof password === 'string' && password.length >= 14 && password.length <= 256 &&
    password === password.trim();
}

async function matchesPassword(password: string, stored: string) {
  const calculated = await hashPassword(password, stored.split(':')[0]);
  return timingSafeEqual(Buffer.from(stored), Buffer.from(calculated));
}

const invalidCredentials = () => new RequestError(401, 'Check your email and password, or ask your administrator to check your access.');

async function loginWithSupabase(email: string, password: string) {
  const identity = await supabasePasswordLogin(email, password);
  if (!identity) throw invalidCredentials();
  const token = randomBytes(32).toString('base64url');
  const { rows: [user] } = await db.query<User>(`
    WITH account AS (
      SELECT u.id,u.name,u.email,u.role FROM users u
      JOIN ${authSchema}.users auth_user ON auth_user.id=$2
      JOIN ${authSchema}.sessions auth_session ON auth_session.id=$3 AND auth_session.user_id=auth_user.id
      WHERE u.active AND u.email=$5 AND ${activeSupabaseSession}
    ), issued AS (
      INSERT INTO sessions (token_hash,user_id,expires_at,auth_session_id)
      SELECT $1,id,LEAST(to_timestamp($4),now() + interval '12 hours'),$3 FROM account
      RETURNING user_id
    )
    SELECT account.* FROM account JOIN issued ON issued.user_id=account.id`,
  [digest(token), identity.userId, identity.sessionId, identity.expiresAt, email]);
  if (!user) throw invalidCredentials();
  return { token, user };
}

export async function login(email: string, password: string) {
  email = email.toLowerCase();
  if (useSupabaseAuth()) return loginWithSupabase(email, password);
  const { rows: [account] } = await db.query<User & { password_hash: string }>(
    'SELECT id,name,email,role,password_hash FROM users WHERE email=$1 AND active AND auth_user_id IS NULL AND password_hash IS NOT NULL',
    [email],
  );
  const stored = account?.password_hash ?? dummyHash;
  if (!await matchesPassword(password, stored) || !account) {
    throw new RequestError(401, 'Check your email and password.');
  }
  const { id, name, role } = account;
  const token = randomBytes(32).toString('base64url');
  const { rowCount } = await db.query(`
    INSERT INTO sessions (token_hash,user_id,expires_at)
    SELECT $1,id,now() + interval '12 hours' FROM users
    WHERE id=$2 AND password_hash=$3 AND active AND auth_user_id IS NULL FOR SHARE`, [digest(token), id, stored]);
  if (!rowCount) throw new RequestError(401, 'Check your email and password.');
  return { token, user: { id, name, role, email: account.email } };
}

export async function changePassword(user: User, current: string, replacement: unknown) {
  if (!validNewPassword(replacement)) {
    throw new RequestError(400, 'Use 14–256 characters without spaces at the beginning or end.');
  }
  if (current === replacement) throw new RequestError(400, 'Choose a different password.');
  if (useSupabaseAuth()) {
    const identity = await supabasePasswordLogin(user.email, current);
    if (!identity) throw new RequestError(400, 'The current password is incorrect.');
    const { rowCount } = await db.query(`
      SELECT 1 FROM users u
      JOIN ${authSchema}.users auth_user ON auth_user.id=$2
      JOIN ${authSchema}.sessions auth_session ON auth_session.id=$3 AND auth_session.user_id=auth_user.id
      WHERE u.id=$1 AND u.active AND ${activeSupabaseSession}`, [user.id, identity.userId, identity.sessionId]);
    if (!rowCount) throw new RequestError(401, 'Your session has expired.');
    await updateSupabasePassword(identity.accessToken, current, replacement);
    await db.query('DELETE FROM sessions WHERE user_id=$1', [user.id]);
    return { changed: true };
  }
  const { rows: [account] } = await db.query<{ password_hash: string }>(
    'SELECT password_hash FROM users WHERE id=$1 AND active AND auth_user_id IS NULL AND password_hash IS NOT NULL',
    [user.id],
  );
  if (!account || !await matchesPassword(current, account.password_hash)) {
    throw new RequestError(400, 'The current password is incorrect.');
  }
  const passwordHash = await hashPassword(replacement);
  await transaction(async (connection) => {
    const { rowCount } = await connection.query(`
      UPDATE users SET password_hash=$2 WHERE id=$1 AND password_hash=$3 AND active AND auth_user_id IS NULL`,
    [user.id, passwordHash, account.password_hash]);
    if (!rowCount) throw new RequestError(409, 'The account has changed. Sign in and try again.');
    await connection.query('DELETE FROM sessions WHERE user_id=$1', [user.id]);
  });
  return { changed: true };
}

export async function authenticate(header: string | undefined) {
  const token = /^Bearer ([\w-]{43})$/.exec(header ?? '')?.[1];
  if (!token) throw new RequestError(401, 'Sign in to continue.');
  const tokenHash = digest(token);
  const hosted = useSupabaseAuth();
  const { rows: [user] } = await db.query<User>(`
    SELECT u.id,u.name,u.email,u.role FROM users u JOIN sessions s ON s.user_id=u.id
    ${hosted ? `JOIN ${authSchema}.users auth_user ON auth_user.id=u.auth_user_id
    JOIN ${authSchema}.sessions auth_session ON auth_session.id=s.auth_session_id AND auth_session.user_id=auth_user.id` : ''}
    WHERE s.token_hash=$1 AND s.expires_at > now() AND u.active
    AND ${hosted ? activeSupabaseSession : 'u.auth_user_id IS NULL AND s.auth_session_id IS NULL'}`, [tokenHash]);
  if (!user) throw new RequestError(401, 'Your session has expired.');
  return { user, tokenHash };
}
