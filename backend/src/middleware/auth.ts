import { Request, Response, NextFunction } from 'express';
import { verifyToken } from '../services/authService';
import { AuthRequest } from '../types/auth';

export function authenticate(req: Request, res: Response, next: NextFunction): void {
  const header = req.headers.authorization;

  if (!header?.startsWith('Bearer ')) {
    res.status(401).json({ error: 'Missing or malformed Authorization header' });
    return;
  }

  const token = header.slice(7);
  try {
    (req as AuthRequest).auth = verifyToken(token);
    next();
  } catch {
    res.status(401).json({ error: 'Invalid or expired token' });
  }
}
