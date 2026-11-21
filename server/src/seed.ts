import { hashPassword, validNewPassword } from './auth.ts';
import { db, managedDatabase, migrate } from './db.ts';
import { useSupabaseAuth, uuidPattern } from './supabase-auth.ts';
import { roles } from './workflow.ts';

const {
  RMCS_USER_EMAIL, RMCS_USER_NAME, RMCS_USER_ROLE: role,
  RMCS_USER_PASSWORD: password, RMCS_AUTH_USER_ID: authUserId,
} = process.env;
const email = RMCS_USER_EMAIL?.trim().toLowerCase();
const name = RMCS_USER_NAME?.trim();
const hosted = useSupabaseAuth();

if (process.argv.length > 2) throw new Error('Set the account details through environment variables.');
if (!process.env.DATABASE_URL) throw new Error('Set DATABASE_URL before provisioning accounts.');
if (managedDatabase) throw new Error('Grant access through the Supabase SQL Editor for a managed RMCS database.');
if (!email || email.length > 254 || !/^[^\s@]+@[^\s@]+$/.test(email) || email.endsWith('@rmcs.demo') ||
    !name || name.length > 160 || !roles.some((value) => value === role)) {
  throw new Error('Set RMCS_USER_EMAIL, RMCS_USER_NAME and a valid RMCS_USER_ROLE.');
}

try {
  await migrate();
  if (hosted) {
    if (!authUserId || !uuidPattern.test(authUserId)) {
      throw new Error('Set RMCS_AUTH_USER_ID to the UUID of the confirmed user in Supabase Authentication.');
    }
    const { rowCount } = await db.query(`
      INSERT INTO users(name,email,role,auth_user_id)
      SELECT $1,lower(email),$3,id FROM auth.users WHERE id=$4 AND lower(email)=$2 AND email_confirmed_at IS NOT NULL
      ON CONFLICT (email) DO UPDATE SET auth_user_id=EXCLUDED.auth_user_id,password_hash=NULL
      WHERE users.active AND users.role=EXCLUDED.role
        AND (users.auth_user_id IS NULL OR users.auth_user_id=EXCLUDED.auth_user_id)`,
    [name, email, role, authUserId]);
    if (!rowCount) {
      throw new Error('Could not grant RMCS access. Check the confirmed Supabase email and UUID, and any existing RMCS role or link.');
    }
    console.log('RMCS access granted.');
  } else {
    if (!validNewPassword(password)) throw new Error('Set RMCS_USER_PASSWORD to a password of 14–256 characters.');
    const { rowCount } = await db.query(
      'INSERT INTO users(name,email,password_hash,role) VALUES($1,$2,$3,$4) ON CONFLICT (email) DO NOTHING',
      [name, email, await hashPassword(password), role],
    );
    if (!rowCount) throw new Error('An RMCS account already exists for this email address.');
    console.log('Account created.');
  }
} finally {
  await db.end();
}
