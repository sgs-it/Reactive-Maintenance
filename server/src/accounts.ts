import { db, managedDatabase, transaction } from './db.ts';
import { hashPassword, validNewPassword } from './auth.ts';
import { field, requireRole, uuid } from './operations.ts';
import type { Input } from './operations.ts';
import { canCreateSupabaseUser, createSupabaseUser, useSupabaseAuth } from './supabase-auth.ts';
import { RequestError, roles } from './workflow.ts';
import type { User } from './workflow.ts';

const accountRoles = ['engineer', 'manager'] as const;
const accountFields = 'id,name,email,role,active';

function accountRole(input: Input) {
  const value = field(input, 'role', 20);
  const role = roles.find((role) => role === value);
  if (!role) throw new RequestError(400, 'Choose a user role.');
  return role;
}

export async function listAccounts(actor: User) {
  requireRole(actor, [...accountRoles]);
  const [{ rows: users }, { rows: jobs }, { rows: grants }] = await Promise.all([
    db.query(`SELECT ${accountFields} FROM users WHERE managed_by=$1 ORDER BY lower(name),email`, [actor.id]),
    db.query(`SELECT j.id,j.code,j.site,a.visible_until FROM jobs j
      JOIN active_job_access a ON a.job_id=j.id WHERE a.user_id=$1 ORDER BY lower(j.site),j.code`, [actor.id]),
    db.query(`SELECT g.user_id,g.job_id,g.visible_from,g.visible_until FROM job_access g
      JOIN active_job_access own ON own.job_id=g.job_id AND own.user_id=$1
      JOIN users u ON u.id=g.user_id WHERE u.managed_by=$1`, [actor.id]),
  ]);
  const hosted = useSupabaseAuth();
  const canAddUser = actor.role === 'manager';
  return { users, jobs, grants, hosted, can_add_user: canAddUser,
    can_create_credentials: canAddUser && (!hosted || canCreateSupabaseUser()) };
}

export async function createAccount(actor: User, input: Input) {
  requireRole(actor, ['manager']);
  const name = field(input, 'name', 160);
  const email = field(input, 'email', 254).toLowerCase();
  if (!/^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(email) || email.endsWith('@rmcs.demo')) {
    throw new RequestError(400, 'Enter the person’s email address.');
  }
  const role = accountRole(input);
  const hosted = useSupabaseAuth();
  const { rowCount: exists } = await db.query('SELECT 1 FROM users WHERE email=$1', [email]);
  if (exists) throw new RequestError(409, 'An RMCS account already uses this email address.');
  const password = input.password;
  if ((!hosted || password !== undefined) && !validNewPassword(password)) {
    throw new RequestError(400, 'Use an initial password of 14–256 characters without spaces at either end.');
  }

  let authUserId: string | null = null;
  if (hosted) {
    if (typeof password === 'string') {
      authUserId = await createSupabaseUser(email, password);
    } else {
      const query = managedDatabase ? 'SELECT id FROM rmcs_auth.confirmed_users WHERE email=$1' :
        `SELECT id FROM auth.users WHERE lower(email)=$1 AND email_confirmed_at IS NOT NULL AND NOT is_anonymous
          AND (banned_until IS NULL OR banned_until <= now())`;
      const { rows } = await db.query<{ id: string }>(query, [email]);
      if (rows.length !== 1) throw new RequestError(404, 'A confirmed Supabase user with this email could not be found.');
      authUserId = rows[0].id;
    }
  }

  const params = [name, email, role, authUserId, actor.id];
  const { rows: [account] } = hosted
    ? await db.query(`INSERT INTO users (name,email,role,auth_user_id,managed_by)
        VALUES ($1,$2,$3,$4,$5) ON CONFLICT DO NOTHING RETURNING ${accountFields}`, params)
    : await db.query(`INSERT INTO users (name,email,role,auth_user_id,managed_by,password_hash)
        VALUES ($1,$2,$3,$4,$5,$6) ON CONFLICT DO NOTHING RETURNING ${accountFields}`,
      [...params, await hashPassword(password as string)]);
  if (!account) throw new RequestError(409, 'An RMCS account is already linked to this identity.');
  return { account };
}

export async function updateAccount(actor: User, accountId: string, input: Input) {
  requireRole(actor, [...accountRoles]);
  const id = uuid(accountId);
  const name = field(input, 'name', 160);
  const role = accountRole(input);
  const active = input.active;
  if (typeof active !== 'boolean') throw new RequestError(400, 'Choose an account status.');
  return transaction(async (connection) => {
    const { rows: [current] } = await connection.query<Pick<User, 'role'>>(
      'SELECT role FROM users WHERE id=$1 AND managed_by=$2 FOR UPDATE', [id, actor.id],
    );
    if (!current) throw new RequestError(404, 'Managed account not found.');
    if (actor.role !== 'manager' && (current.role === 'manager' || role === 'manager')) {
      throw new RequestError(403, 'Only a Manager can assign or edit the Manager role.');
    }
    const { rows: [account] } = await connection.query(
      `UPDATE users SET name=$2,role=$3,active=$4 WHERE id=$1 AND managed_by=$5 RETURNING ${accountFields}`,
      [id, name, role, active, actor.id],
    );
    if (!active || current.role !== role) await connection.query('DELETE FROM sessions WHERE user_id=$1', [id]);
    return { account };
  });
}

function accessDate(value: unknown) {
  if (value === null || value === undefined) return null;
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,3})?Z$/.test(value)) {
    throw new RequestError(400, 'Choose a valid access date and time.');
  }
  const date = new Date(value);
  if (!Number.isFinite(date.getTime()) || date.toISOString().slice(0, 19) !== value.slice(0, 19)) {
    throw new RequestError(400, 'Choose a valid access date and time.');
  }
  return date;
}

export async function setAccountJob(actor: User, accountId: string, jobId: string, input: Input) {
  requireRole(actor, [...accountRoles]);
  const params = [uuid(accountId), uuid(jobId), actor.id];
  if (input.granted === false) {
    await db.query(`DELETE FROM job_access grant_row USING users u,active_job_access own
      WHERE u.id=$1 AND u.managed_by=$3 AND own.job_id=$2 AND own.user_id=$3
        AND grant_row.user_id=u.id AND grant_row.job_id=own.job_id`, params);
    return { granted: false };
  }
  if (input.granted !== true) throw new RequestError(400, 'Choose whether to grant access.');
  const start = accessDate(input.visible_from);
  const end = accessDate(input.visible_until);
  if (end && (end <= new Date() || (start && end <= start))) {
    throw new RequestError(400, 'Access must end in the future, after its start.');
  }
  const { rowCount } = await db.query(`
    INSERT INTO job_access (user_id,job_id,visible_from,visible_until)
    SELECT u.id,own.job_id,$4::timestamptz,LEAST($5::timestamptz,own.visible_until)
    FROM users u JOIN active_job_access own ON own.job_id=$2 AND own.user_id=$3
    WHERE u.id=$1 AND u.managed_by=$3 AND (
      own.visible_until IS NULL OR $4::timestamptz IS NULL OR $4::timestamptz < own.visible_until
    )
    ON CONFLICT (job_id,user_id) DO UPDATE SET
      visible_from=EXCLUDED.visible_from,visible_until=EXCLUDED.visible_until`,
  [...params, start, end]);
  if (!rowCount) throw new RequestError(404, 'The account or job is outside your access, or the start is after your own access ends.');
  return { granted: true };
}
