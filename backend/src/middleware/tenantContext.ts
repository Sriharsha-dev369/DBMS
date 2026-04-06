import { Response, NextFunction } from 'express';
import { pool, setTenantContext } from '../db';
import { AuthRequest } from '../types/auth';

// Checks out a PoolClient, sets the RLS tenant context, attaches it to the request.
// Releases the client back to the pool when the response finishes — success or error.
//
// Must run after authenticate() so req.auth.tenantId is available.
// Route handlers use req.dbClient directly — all queries are automatically tenant-scoped.
export async function tenantContext(
  req: AuthRequest,
  res: Response,
  next: NextFunction,
): Promise<void> {
  let client;
  try {
    client = await pool.connect();
    await setTenantContext(client, req.auth.tenantId);
    req.dbClient = client;
  } catch (err) {
    client?.release();
    res.status(503).json({ error: 'Database unavailable' });
    return;
  }

  // Release the client exactly once — whichever of finish/close fires first.
  // Both events can fire on the same response, so guard with a flag.
  let released = false;
  const release = () => {
    if (!released) {
      released = true;
      client!.release();
    }
  };
  res.once('finish', release);
  res.once('close',  release);

  next();
}
