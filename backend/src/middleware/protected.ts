import { Request, Response, NextFunction } from 'express';
import { authenticate } from './auth';
import { tenantContext } from './tenantContext';
import { AuthRequest } from '../types/auth';

// Reusable middleware stack: JWT verify → pool client checkout + RLS SET.
// Import into any router: router.use(...protected_)
// Or spread onto individual routes: router.get('/path', ...protected_, handler)
export const protected_ = [
  authenticate,
  (req: Request, res: Response, next: NextFunction) =>
    tenantContext(req as AuthRequest, res, next),
];
