import { Router, Request, Response } from 'express';
import { protected_ } from '../middleware/protected';
import { AuthRequest } from '../types/auth';
import { CreateCustomerBody, UpdateCustomerBody } from '../types/api';

const router = Router();
router.use(...protected_);

// GET /api/customers
// Returns paginated customers for the authenticated tenant.
// Query params: limit (default 20, max 100), offset (default 0), status (optional filter)
router.get('/', async (req: Request, res: Response): Promise<void> => {
  const { dbClient } = req as AuthRequest;

  const limit  = Math.min(parseInt(String(req.query.limit  ?? 20)),  100);
  const offset = Math.max(parseInt(String(req.query.offset ?? 0)),   0);

  if (isNaN(limit) || isNaN(offset)) {
    res.status(400).json({ error: 'limit and offset must be integers' });
    return;
  }

  const VALID_STATUSES = ['active', 'inactive', 'blocked'];
  const statusFilter   = req.query.status as string | undefined;

  if (statusFilter && !VALID_STATUSES.includes(statusFilter)) {
    res.status(400).json({ error: `status must be one of: ${VALID_STATUSES.join(', ')}` });
    return;
  }

  try {
    // Count query for pagination metadata
    const countQuery = statusFilter
      ? 'SELECT COUNT(*) FROM customers WHERE status = $1'
      : 'SELECT COUNT(*) FROM customers';
    const countParams = statusFilter ? [statusFilter] : [];
    const countResult = await dbClient.query(countQuery, countParams);
    const total = parseInt(countResult.rows[0].count);

    // Data query
    let dataQuery = `
      SELECT id, email, name, status, metadata, created_at, updated_at
      FROM   customers
    `;
    const dataParams: unknown[] = [];
    let   paramIdx = 1;

    if (statusFilter) {
      dataQuery += ` WHERE status = $${paramIdx++}`;
      dataParams.push(statusFilter);
    }

    dataQuery += ` ORDER BY created_at DESC LIMIT $${paramIdx++} OFFSET $${paramIdx}`;
    dataParams.push(limit, offset);

    const dataResult = await dbClient.query(dataQuery, dataParams);

    res.json({
      customers: dataResult.rows,
      pagination: { total, limit, offset },
    });
  } catch {
    res.status(500).json({ error: 'Failed to fetch customers' });
  }
});

// POST /api/customers
// Creates a new customer within the authenticated tenant.
router.post('/', async (req: Request, res: Response): Promise<void> => {
  const { dbClient, auth } = req as AuthRequest;
  const body = req.body as CreateCustomerBody;

  if (!body.email || !body.name) {
    res.status(400).json({ error: 'email and name are required' });
    return;
  }
  // Basic email format check — full validation is DB-level (FK + unique constraint)
  if (!body.email.includes('@')) {
    res.status(400).json({ error: 'Invalid email format' });
    return;
  }
  if (body.metadata !== undefined && (typeof body.metadata !== 'object' || Array.isArray(body.metadata))) {
    res.status(400).json({ error: 'metadata must be a JSON object' });
    return;
  }

  try {
    const result = await dbClient.query(
      `INSERT INTO customers (tenant_id, email, name, metadata)
       VALUES ($1, $2, $3, $4)
       RETURNING id, email, name, status, metadata, created_at`,
      [auth.tenantId, body.email, body.name, body.metadata ?? null],
    );
    res.status(201).json({ customer: result.rows[0] });
  } catch (err) {
    const message = err instanceof Error ? err.message : '';
    if (message.includes('unique') || message.includes('duplicate')) {
      res.status(409).json({ error: 'A customer with that email already exists' });
    } else {
      res.status(500).json({ error: 'Failed to create customer' });
    }
  }
});

// PATCH /api/customers/:id
// Updates mutable fields on a customer.
router.patch('/:id', async (req: Request, res: Response): Promise<void> => {
  const { dbClient } = req as AuthRequest;
  const body = req.body as UpdateCustomerBody;

  if (body.email !== undefined && !body.email.includes('@')) {
    res.status(400).json({ error: 'Invalid email format' });
    return;
  }
  if (body.status !== undefined && !['active', 'inactive', 'blocked'].includes(body.status)) {
    res.status(400).json({ error: `status must be one of: active, inactive, blocked` });
    return;
  }
  if (body.metadata !== undefined && (typeof body.metadata !== 'object' || Array.isArray(body.metadata))) {
    res.status(400).json({ error: 'metadata must be a JSON object' });
    return;
  }

  const ALLOWED_FIELDS = ['name', 'email', 'status', 'metadata'] as const;
  const sets: string[] = [];
  const values: unknown[] = [];
  let i = 1;

  for (const field of ALLOWED_FIELDS) {
    if (body[field] !== undefined) {
      sets.push(`${field} = $${i++}`);
      values.push(body[field]);
    }
  }

  if (sets.length === 0) {
    res.status(400).json({ error: 'No updatable fields provided' });
    return;
  }

  values.push(req.params.id);
  const query = `
    UPDATE customers
    SET    ${sets.join(', ')}
    WHERE  id = $${i}
    RETURNING id, email, name, status, metadata, updated_at
  `;

  try {
    const result = await dbClient.query(query, values);
    if (result.rowCount === 0) {
      res.status(404).json({ error: 'Customer not found' });
      return;
    }
    res.json({ customer: result.rows[0] });
  } catch (err) {
    const message = err instanceof Error ? err.message : '';
    if (message.includes('unique') || message.includes('duplicate')) {
      res.status(409).json({ error: 'A customer with that email already exists' });
    } else {
      res.status(500).json({ error: 'Failed to update customer' });
    }
  }
});

// DELETE /api/customers/:id
// Soft-deletes by setting status = 'inactive'.
// Hard delete would fail once subscriptions exist (ON DELETE RESTRICT in Phase 2).
router.delete('/:id', async (req: Request, res: Response): Promise<void> => {
  const { dbClient } = req as AuthRequest;

  try {
    const result = await dbClient.query(
      `UPDATE customers
       SET    status = 'inactive'
       WHERE  id = $1
       RETURNING id, email, name, status`,
      [req.params.id],
    );
    if (result.rowCount === 0) {
      res.status(404).json({ error: 'Customer not found' });
      return;
    }
    res.json({ customer: result.rows[0] });
  } catch {
    res.status(500).json({ error: 'Failed to delete customer' });
  }
});

export default router;
