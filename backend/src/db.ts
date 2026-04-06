import { Pool, PoolClient } from "pg";
import dotenv from "dotenv";

dotenv.config({ path: "../.env" });

export const pool = new Pool({
  host: process.env.DB_HOST || "localhost",
  port: parseInt(process.env.DB_PORT || "5432"),
  database: process.env.DB_NAME || "saasledger",
  user: process.env.DB_USER || "postgres",
  password: process.env.DB_PASSWORD || "",
  max: 20,
  idleTimeoutMillis: 30000,
  connectionTimeoutMillis: 2000,
});

pool.on("error", (err) => {
  console.error("Unexpected error on idle client", err);
  process.exit(-1);
});

/**
 * Sets the RLS tenant context for a connection.
 * Must be called at the start of every request after auth.
 */
export async function setTenantContext(
  client: PoolClient,
  tenantId: string,
): Promise<void> {
  await client.query("SELECT set_config($1, $2, true)", [
    "app.current_tenant_id",
    tenantId,
  ]);
}

/**
 * Runs a callback inside a transaction, rolling back on any error.
 */
export async function withTransaction<T>(
  fn: (client: PoolClient) => Promise<T>,
): Promise<T> {
  const client = await pool.connect();
  try {
    await client.query("BEGIN");
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (err) {
    await client.query("ROLLBACK");
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
    await client.query("BEGIN ISOLATION LEVEL SERIALIZABLE");
    const result = await fn(client);
    await client.query("COMMIT");
    return result;
  } catch (err) {
    await client.query("ROLLBACK");
    throw err;
  } finally {
    client.release();
  }
}
