import { createHash, randomBytes, scrypt, timingSafeEqual } from 'node:crypto';
import { promisify } from 'node:util';
import { db } from './db.ts';
import { RequestError } from './workflow.ts';
import type { User } from './workflow.ts';

const derive = promisify(scrypt);
const digest = (token: string) => createHash('sha256').update(token).digest('hex');
const dummyHash = `${'0'.repeat(32)}:${'0'.repeat(128)}`;

export async function hashPassword(password: string, salt = randomBytes(16).toString('hex')) {
  return `${salt}:${(await derive(password, salt, 64) as Buffer).toString('hex')}`;
}

export async function login(email: string, password: string) {
  const { rows: [account] } = await db.query<User & { password_hash: string }>(
    'SELECT id, name, email, role, password_hash FROM users WHERE email=$1 AND active', [email.toLowerCase()],
  );
  const stored = account?.password_hash ?? dummyHash;
  const calculated = await hashPassword(password, stored.split(':')[0]);
  if (!timingSafeEqual(Buffer.from(stored), Buffer.from(calculated)) || !account) {
    throw new RequestError(401, 'Check your email and password.');
  }
  const { id, name, role } = account;
  const token = randomBytes(32).toString('base64url');
  await db.query(`INSERT INTO sessions VALUES ($1,$2,now() + interval '12 hours')`, [digest(token), id]);
  return { token, user: { id, name, role, email: account.email } };
}

export async function authenticate(header: string | undefined) {
  const token = /^Bearer ([\w-]{43})$/.exec(header ?? '')?.[1];
  if (!token) throw new RequestError(401, 'Sign in to continue.');
  const tokenHash = digest(token);
  const { rows: [user] } = await db.query<User>(`
    SELECT u.id,u.name,u.email,u.role FROM users u JOIN sessions s ON s.user_id=u.id
    WHERE s.token_hash=$1 AND s.expires_at > now() AND u.active`, [tokenHash]);
  if (!user) throw new RequestError(401, 'Your session has expired.');
  return { user, tokenHash };
}
