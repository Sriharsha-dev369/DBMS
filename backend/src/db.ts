import { Pool, PoolClient } from 'pg';
import dotenv from 'dotenv';

dotenv.config({ path: '../.env' });

// App pool — connects as saasledger_app (non-superuser).
// RLS policies are enforced on every query. Use for all authenticated requests.
export const pool = new Pool({
  host:     process.env.DB_HOST     || 'localhost',
  port:     parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME     || 'saasledger',
  user:     process.env.DB_USER     || 'saasledger_app',
  password: process.env.DB_PASSWORD || '',
  max: 20,
  idleTimeoutMillis:    30000,
  connectionTimeoutMillis: 2000,
});

// Admin pool — connects as postgres (superuser, bypasses RLS).
// Use only for: tenant registration, auth credential lookup, billing cron job.
export const adminPool = new Pool({
  host:     process.env.DB_HOST           || 'localhost',
  port:     parseInt(process.env.DB_PORT  || '5432'),
  database: process.env.DB_NAME           || 'saasledger',
  user:     process.env.DB_ADMIN_USER     || 'postgres',
  password: process.env.DB_ADMIN_PASSWORD || '',
  max: 5,
  idleTimeoutMillis:    30000,
  connectionTimeoutMillis: 2000,
});

pool.on('error',      (err) => { console.error('App pool error',   err); process.exit(-1); });
adminPool.on('error', (err) => { console.error('Admin pool error', err); process.exit(-1); });

/**
 * Sets the RLS tenant context for a connection.
 * Must be called at the start of every authenticated request.
 */
export async function setTenantContext(client: PoolClient, tenantId: string): Promise<void> {
  // is_local = false → setting persists for the session (this connection).
  // is_local = true  → local to current transaction only; in autocommit mode
  //                    the setting is gone before the next query runs.
  // Safe with false: tenantContext middleware always resets the context on
  // every checkout, so a recycled pool connection is never stale.
  await client.query('SELECT set_config($1, $2, false)', [
    'app.current_tenant_id',
    tenantId,
  ]);
}

/**
 * Runs a callback inside a READ COMMITTED transaction (default).
 * Used for standard write operations.
 */
export async function withTransaction<T>(
  fn: (client: PoolClient) => Promise<T>,
  useAdmin = false,
): Promise<T> {
  const client = await (useAdmin ? adminPool : pool).connect();
  try {
    await client.query('BEGIN');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/**
 * Runs a callback inside a SERIALIZABLE transaction.
 * Used for billing-critical operations (invoice generation, payment posting).
 */
export async function withSerializableTransaction<T>(
  fn: (client: PoolClient) => Promise<T>,
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query('BEGIN ISOLATION LEVEL SERIALIZABLE');
    const result = await fn(client);
    await client.query('COMMIT');
    return result;
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}
