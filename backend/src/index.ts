import express, { Request, Response } from 'express';
import cors from 'cors';
import dotenv from 'dotenv';
import { pool } from './db';
import authRoutes     from './routes/auth';
import planRoutes     from './routes/plans';
import customerRoutes from './routes/customers';
import { protected_ } from './middleware/protected';
import { AuthRequest } from './types/auth';

dotenv.config({ path: '../.env' });

const app  = express();
const PORT = parseInt(process.env.PORT || '3000');

app.use(cors());
app.use(express.json());

// Public routes
app.use('/api/auth', authRoutes);

// Protected routes — each router applies the protected_ middleware stack internally
app.use('/api/plans',     planRoutes);
app.use('/api/customers', customerRoutes);

// Health check (public)
app.get('/health', async (_req, res) => {
  try {
    const result = await pool.query('SELECT NOW() AS time, current_database() AS db');
    res.json({ status: 'ok', db: result.rows[0].db, time: result.rows[0].time });
  } catch {
    res.status(503).json({ status: 'error', message: 'Database unreachable' });
  }
});

// Verify middleware stack works — protected test route
app.get('/api/me', ...protected_, (req: Request, res: Response) => {
  const { auth } = req as AuthRequest;
  res.json({ tenantId: auth.tenantId, userId: auth.userId, role: auth.role, email: auth.email });
});

app.listen(PORT, () => {
  console.log(`SaaSLedger backend → http://localhost:${PORT}`);
});

export default app;
