/**
 * Seed runner — executes SQL files from /db/seeds/ in alphabetical order.
 * Each seed file is idempotent: it deletes then re-inserts its own data.
 *
 * Seeds always run as the admin user (postgres) — the app user cannot
 * bypass RLS to insert rows without an existing tenant context.
 *
 * Usage:
 *   npm run seed              — runs all seed files
 *   npm run seed -- 001       — runs only files whose name contains "001"
 */
import fs   from 'fs';
import path from 'path';
import { Pool } from 'pg';
import dotenv from 'dotenv';

dotenv.config({ path: path.resolve(__dirname, '../../.env') });

const pool = new Pool({
  host:     process.env.DB_HOST           || 'localhost',
  port:     parseInt(process.env.DB_PORT  || '5432'),
  database: process.env.DB_NAME           || 'saasledger',
  user:     process.env.DB_ADMIN_USER     || 'postgres',
  password: process.env.DB_ADMIN_PASSWORD || '',
});

const SEEDS_DIR = path.resolve(__dirname, '../../db/seeds');

async function run(): Promise<void> {
  const filter = process.argv[2];

  const files = fs.readdirSync(SEEDS_DIR)
    .filter(f => f.endsWith('.sql'))
    .filter(f => !filter || f.includes(filter))
    .sort();

  if (files.length === 0) {
    console.log(filter ? `No seed files matching "${filter}".` : 'No seed files found.');
    await pool.end();
    return;
  }

  const client = await pool.connect();
  try {
    for (const file of files) {
      const sql = fs.readFileSync(path.join(SEEDS_DIR, file), 'utf-8');
      console.log(`Seeding: ${file}`);
      await client.query('BEGIN');
      try {
        await client.query(sql);
        await client.query('COMMIT');
        console.log(`  ✓ ${file}`);
      } catch (err) {
        await client.query('ROLLBACK');
        console.error(`  ✗ ${file} failed:`, err);
        process.exit(1);
      }
    }
    console.log(`Done — ${files.length} seed file(s) applied.`);
  } finally {
    client.release();
    await pool.end();
  }
}

run().catch(console.error);
