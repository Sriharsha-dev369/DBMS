import { Router, Request, Response } from 'express';
import { register, login } from '../services/authService';
import { RegisterBody, LoginBody } from '../types/auth';

const router = Router();

// POST /api/auth/register
// Creates a new tenant + owner user in a single transaction.
router.post('/register', async (req: Request, res: Response): Promise<void> => {
  const { tenantName, slug, email, name, password } = req.body as RegisterBody;

  if (!tenantName || !slug || !email || !name || !password) {
    res.status(400).json({ error: 'tenantName, slug, email, name, and password are required' });
    return;
  }
  if (password.length < 8) {
    res.status(400).json({ error: 'Password must be at least 8 characters' });
    return;
  }

  try {
    const token = await register({ tenantName, slug, email, name, password });
    res.status(201).json({ token });
  } catch (err) {
    const message = err instanceof Error ? err.message : 'Registration failed';
    const status  = message.includes('already taken') ? 409 : 400;
    res.status(status).json({ error: message });
  }
});

// POST /api/auth/login
// Verifies credentials and returns a JWT.
router.post('/login', async (req: Request, res: Response): Promise<void> => {
  const { email, password } = req.body as LoginBody;

  if (!email || !password) {
    res.status(400).json({ error: 'email and password are required' });
    return;
  }

  try {
    const token = await login({ email, password });
    res.json({ token });
  } catch (err) {
    // Always return 401 for auth failures — don't reveal whether email exists
    res.status(401).json({ error: 'Invalid email or password' });
  }
});

export default router;
