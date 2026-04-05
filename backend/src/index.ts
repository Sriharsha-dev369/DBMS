import express from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { pool } from './db';

dotenv.config({ path: '../.env' });

const app = express();
const PORT = parseInt(process.env.PORT || '3000');

app.use(cors());
app.use(express.json());

// Health check — also verifies DB connection
app.get('/health', async (_req, res) => {
  try {
    const result = await pool.query('SELECT NOW() AS time, current_database() AS db');
    res.json({
      status: 'ok',
      db: result.rows[0].db,
      time: result.rows[0].time,
    });
  } catch (err) {
    res.status(503).json({ status: 'error', message: 'Database unreachable' });
  }
});

app.listen(PORT, () => {
  console.log(`SaaSLedger backend running on http://localhost:${PORT}`);
  console.log(`Health check: http://localhost:${PORT}/health`);
});

export default app;
