/**
 * Migration runner — reads SQL files from /db/migrations/ in order.
 * Each migration file must contain both an UP and DOWN section, separated by:
 *   -- @DOWN
 *
 * Usage:
 *   npm run migrate        — runs all pending UP migrations
 *   npm run migrate:down   — rolls back the last applied migration
 */
import fs from 'fs';
import path from 'path';
import { Pool, PoolClient } from 'pg';
import dotenv from 'dotenv';

dotenv.config({ path: path.resolve(__dirname, '../../.env') });

const pool = new Pool({
  host:     process.env.DB_HOST     || 'localhost',
  port:     parseInt(process.env.DB_PORT || '5432'),
  database: process.env.DB_NAME     || 'saasledger',
  user:     process.env.DB_USER     || 'postgres',
  password: process.env.DB_PASSWORD || '',
});

const MIGRATIONS_DIR = path.resolve(__dirname, '../../db/migrations');

async function ensureMigrationsTable(client: PoolClient): Promise<void> {
  await client.query(`
    CREATE TABLE IF NOT EXISTS schema_migrations (
      id          SERIAL PRIMARY KEY,
      filename    VARCHAR(255) NOT NULL UNIQUE,
      applied_at  TIMESTAMPTZ NOT NULL DEFAULT NOW()
    )
  `);
}

async function getAppliedMigrations(client: PoolClient): Promise<Set<string>> {
  const result = await client.query('SELECT filename FROM schema_migrations ORDER BY id');
  return new Set(result.rows.map((r: { filename: string }) => r.filename));
}

async function runUp(): Promise<void> {
  const client = await pool.connect();
  try {
    await ensureMigrationsTable(client);
    const applied = await getAppliedMigrations(client);

    const files = fs.readdirSync(MIGRATIONS_DIR)
      .filter(f => f.endsWith('.sql'))
      .sort();

    let count = 0;
    for (const file of files) {
      if (applied.has(file)) continue;

      const content = fs.readFileSync(path.join(MIGRATIONS_DIR, file), 'utf-8');
      const [upSql] = content.split('-- @DOWN');

      console.log(`Applying: ${file}`);
      await client.query('BEGIN');
      try {
        await client.query(upSql);
        await client.query('INSERT INTO schema_migrations (filename) VALUES ($1)', [file]);
        await client.query('COMMIT');
        count++;
      } catch (err) {
        await client.query('ROLLBACK');
        console.error(`Failed on ${file}:`, err);
        process.exit(1);
      }
    }

    if (count === 0) console.log('Nothing to migrate.');
    else console.log(`Applied ${count} migration(s).`);
  } finally {
    client.release();
    await pool.end();
  }
}

async function runDown(): Promise<void> {
  const client = await pool.connect();
  try {
    await ensureMigrationsTable(client);
    const result = await client.query(
      'SELECT filename FROM schema_migrations ORDER BY id DESC LIMIT 1'
    );

    if (result.rows.length === 0) {
      console.log('Nothing to roll back.');
      return;
    }

    const { filename } = result.rows[0];
    const content = fs.readFileSync(path.join(MIGRATIONS_DIR, filename), 'utf-8');
    const parts = content.split('-- @DOWN');

    if (parts.length < 2 || !parts[1].trim()) {
      console.error(`No DOWN section found in ${filename}`);
      process.exit(1);
    }

    console.log(`Rolling back: ${filename}`);
    await client.query('BEGIN');
    try {
      await client.query(parts[1]);
      await client.query('DELETE FROM schema_migrations WHERE filename = $1', [filename]);
      await client.query('COMMIT');
      console.log('Done.');
    } catch (err) {
      await client.query('ROLLBACK');
      console.error('Rollback failed:', err);
      process.exit(1);
    }
  } finally {
    client.release();
    await pool.end();
  }
}

const direction = process.argv[2];
if (direction === 'down') runDown().catch(console.error);
else runUp().catch(console.error);
