import pg from 'pg';
import { readFile } from 'node:fs/promises';
import type { PoolClient } from 'pg';

export const managedDatabase = process.env.RMCS_DATABASE_MANAGED === 'true';

export const db = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  max: 10,
  connectionTimeoutMillis: 5000,
});

// Idle connections can drop during a database restart. The pool replaces them.
db.on('error', (error) => {
  console.error('Idle database connection lost', error.name);
});

export async function migrate() {
  if (managedDatabase) {
    const { rows: [schema] } = await db.query<{ ready: boolean }>(`
      SELECT to_regnamespace('rmcs') IS NOT NULL AND current_schema()='rmcs'
        AND to_regclass('users')=to_regclass('rmcs.users')
        AND to_regclass('rmcs.active_job_access') IS NOT NULL
        AND to_regclass('rmcs_auth.confirmed_users') IS NOT NULL
        AND (SELECT count(*) FROM pg_tables WHERE schemaname='rmcs' AND tablename IN
          ('users','sessions','jobs','job_access','complaints','complaint_history','photos','photo_uploads'))=8 AS ready`);
    if (!schema.ready) throw new Error('Install the managed RMCS schema and connect with its application role.');
    return;
  }
  await db.query(await readFile(new URL('../schema.sql', import.meta.url), 'utf8'));
}

export async function transaction<T>(work: (connection: PoolClient) => Promise<T>) {
  const connection = await db.connect();
  try {
    await connection.query('BEGIN');
    const result = await work(connection);
    await connection.query('COMMIT');
    return result;
  } catch (error) {
    await connection.query('ROLLBACK');
    throw error;
  } finally {
    connection.release();
  }
}
