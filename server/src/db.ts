import pg from 'pg';
import { readFile } from 'node:fs/promises';
import type { PoolClient } from 'pg';

export const db = new pg.Pool({
  connectionString: process.env.DATABASE_URL,
  max: 10,
  connectionTimeoutMillis: 5000,
});

export async function migrate() {
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
