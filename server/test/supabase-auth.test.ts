import assert from 'node:assert/strict';
import { randomUUID } from 'node:crypto';
import { execFile } from 'node:child_process';
import { test } from 'node:test';
import { promisify } from 'node:util';

const databaseUrl = process.env.RMCS_TEST_DATABASE_URL;

test('Supabase password sign-in requires a linked user and an active provider session', { skip: !databaseUrl }, async (t) => {
  assert(databaseUrl);
  const database = new URL(databaseUrl);
  assert.equal(database.hostname, '127.0.0.1');
  assert.match(database.pathname, /^\/rmcs_test_[a-z0-9_]+$/);
  process.env.DATABASE_URL = databaseUrl;
  process.env.RMCS_AUTH_MODE = 'supabase';
  process.env.SUPABASE_URL = 'https://project.example.test';
  process.env.SUPABASE_PUBLISHABLE_KEY = 'sb_publishable_test';

  const { db, migrate } = await import('../src/db.ts');
  t.after(() => db.end());
  const { authenticate, changePassword, login } = await import('../src/auth.ts');
  const { checkAuthConfiguration } = await import('../src/supabase-auth.ts');
  await db.query(`
    CREATE SCHEMA IF NOT EXISTS auth;
    CREATE TABLE IF NOT EXISTS auth.users (
      id uuid PRIMARY KEY, email text, email_confirmed_at timestamptz, banned_until timestamptz
    );
    CREATE TABLE IF NOT EXISTS auth.sessions (
      id uuid PRIMARY KEY, user_id uuid REFERENCES auth.users ON DELETE CASCADE, not_after timestamptz
    );
    CREATE TABLE IF NOT EXISTS auth.mfa_factors (user_id uuid REFERENCES auth.users ON DELETE CASCADE, status text)`);
  await migrate();
  await checkAuthConfiguration();

  const userId = randomUUID();
  const sessionId = randomUUID();
  const email = `supabase+${userId}@example.test`;
  let password = randomUUID();
  const replacement = randomUUID();
  await db.query('INSERT INTO auth.users(id,email,email_confirmed_at) VALUES($1,$2,now())', [userId, email]);
  await db.query('INSERT INTO auth.sessions(id,user_id) VALUES($1,$2)', [sessionId, userId]);

  const expiredClaims = Buffer.from(JSON.stringify({
    sub: userId, session_id: sessionId, exp: Math.floor(Date.now() / 1000) - 1,
  })).toString('base64url');
  const validClaims = Buffer.from(JSON.stringify({
    sub: userId, session_id: sessionId, exp: Math.floor(Date.now() / 1000) + 3600,
  })).toString('base64url');
  const accessToken = `header.${validClaims}.signature`;
  let loginToken = accessToken;
  t.mock.method(globalThis, 'fetch', async (url: string, request: RequestInit) => {
    const headers = new Headers(request.headers);
    assert.equal(headers.get('apikey'), 'sb_publishable_test');
    const data = JSON.parse(String(request.body));
    if (url === 'https://project.example.test/auth/v1/user') {
      assert.equal(request.method, 'PUT');
      assert.equal(headers.get('Authorization'), `Bearer ${accessToken}`);
      assert.deepEqual(data, { password: replacement, current_password: password });
      password = replacement;
      return Response.json({ id: userId });
    }
    assert.equal(url, 'https://project.example.test/auth/v1/token?grant_type=password');
    assert.equal(request.method, 'POST');
    if (data.email !== email || data.password !== password) {
      return Response.json({ error_code: 'invalid_credentials' }, { status: 400 });
    }
    return Response.json({ access_token: loginToken, user: { id: userId, user_metadata: { role: 'engineer' } } });
  });

  await assert.rejects(authenticate(undefined), { status: 401 });
  await assert.rejects(login(email, password), { status: 401 });
  const seed = (role: string) => promisify(execFile)(process.execPath, ['src/seed.ts'], {
    env: {
      ...process.env, RMCS_USER_EMAIL: email, RMCS_USER_NAME: 'Linked Client',
      RMCS_USER_ROLE: role, RMCS_AUTH_USER_ID: userId,
    },
  });
  await seed('client');
  await assert.rejects(seed('engineer'), /Could not grant RMCS access/);
  await assert.rejects(login(email, 'wrong password'), { status: 401 });
  loginToken = `header.${expiredClaims}.signature`;
  await assert.rejects(login(email, password), { status: 503 });
  loginToken = accessToken;
  const original = await login(email, password);
  const bearer = (token: string) => `Bearer ${token}`;
  assert.equal((await authenticate(bearer(original.token))).user.role, 'client');
  assert.deepEqual(await changePassword(original.user, password, replacement), { changed: true });
  await assert.rejects(authenticate(bearer(original.token)), { status: 401 });

  const session = await login(email, replacement);
  await db.query("INSERT INTO auth.mfa_factors(user_id,status) VALUES($1,'verified')", [userId]);
  await assert.rejects(login(email, replacement), { status: 401 });
  await assert.rejects(authenticate(bearer(session.token)), { status: 401 });
  await db.query('DELETE FROM auth.mfa_factors WHERE user_id=$1', [userId]);
  assert.equal((await authenticate(bearer(session.token))).user.id, session.user.id);
  await db.query('DELETE FROM auth.sessions WHERE id=$1', [sessionId]);
  await assert.rejects(authenticate(bearer(session.token)), { status: 401 });
});
