import { Router, Request, Response } from 'express';
import { protected_ } from '../middleware/protected';
import { AuthRequest } from '../types/auth';
import { CreatePlanBody, UpdatePlanBody } from '../types/api';

const router = Router();
router.use(...protected_);

// GET /api/plans
// Returns all plans for the authenticated tenant.
// Query param: ?is_active=true|false  (omit → return all)
router.get('/', async (req: Request, res: Response): Promise<void> => {
  const { dbClient } = req as AuthRequest;

  let query = `
    SELECT id, name, billing_model, base_price, per_seat_price,
           billing_period, trial_days, is_active, created_at, updated_at
    FROM   plans
  `;
  const params: unknown[] = [];

  if (req.query.is_active !== undefined) {
    query += ' WHERE is_active = $1';
    params.push(req.query.is_active === 'true');
  }

  query += ' ORDER BY created_at';

  try {
    const result = await dbClient.query(query, params);
    res.json({ plans: result.rows });
  } catch {
    res.status(500).json({ error: 'Failed to fetch plans' });
  }
});

// POST /api/plans
// Creates a new plan for the authenticated tenant.
router.post('/', async (req: Request, res: Response): Promise<void> => {
  const { dbClient, auth } = req as AuthRequest;
  const body = req.body as CreatePlanBody;

  // Required field validation
  if (!body.name || !body.billing_model || body.base_price === undefined) {
    res.status(400).json({ error: 'name, billing_model, and base_price are required' });
    return;
  }

  const VALID_MODELS  = ['flat_rate', 'per_seat', 'usage_based'] as const;
  const VALID_PERIODS = ['monthly', 'annual'] as const;

  if (!VALID_MODELS.includes(body.billing_model)) {
    res.status(400).json({ error: `billing_model must be one of: ${VALID_MODELS.join(', ')}` });
    return;
  }
  if (body.billing_period && !VALID_PERIODS.includes(body.billing_period)) {
    res.status(400).json({ error: `billing_period must be 'monthly' or 'annual'` });
    return;
  }
  if (typeof body.base_price !== 'number' || body.base_price < 0) {
    res.status(400).json({ error: 'base_price must be a non-negative number' });
    return;
  }
  if (body.billing_model === 'per_seat' && body.per_seat_price === undefined) {
    res.status(400).json({ error: 'per_seat_price is required when billing_model is per_seat' });
    return;
  }
  if (body.per_seat_price !== undefined && (typeof body.per_seat_price !== 'number' || body.per_seat_price < 0)) {
    res.status(400).json({ error: 'per_seat_price must be a non-negative number' });
    return;
  }
  if (body.trial_days !== undefined && (!Number.isInteger(body.trial_days) || body.trial_days < 0)) {
    res.status(400).json({ error: 'trial_days must be a non-negative integer' });
    return;
  }

  try {
    const result = await dbClient.query(
      `INSERT INTO plans
         (tenant_id, name, billing_model, base_price, per_seat_price, billing_period, trial_days)
       VALUES ($1, $2, $3, $4, $5, $6, $7)
       RETURNING id, name, billing_model, base_price, per_seat_price,
                 billing_period, trial_days, is_active, created_at`,
      [
        auth.tenantId,
        body.name,
        body.billing_model,
        body.base_price,
        body.per_seat_price ?? null,
        body.billing_period ?? 'monthly',
        body.trial_days    ?? 0,
      ],
    );
    res.status(201).json({ plan: result.rows[0] });
  } catch (err) {
    const message = err instanceof Error ? err.message : '';
    if (message.includes('violates check constraint')) {
      res.status(400).json({ error: 'Plan data violates a database constraint' });
    } else {
      res.status(500).json({ error: 'Failed to create plan' });
    }
  }
});

// PATCH /api/plans/:id
// Updates mutable fields on a plan. billing_model cannot be changed.
router.patch('/:id', async (req: Request, res: Response): Promise<void> => {
  const { dbClient } = req as AuthRequest;
  const body = req.body as UpdatePlanBody;

  // Validate updatable fields if present
  if (body.base_price !== undefined && (typeof body.base_price !== 'number' || body.base_price < 0)) {
    res.status(400).json({ error: 'base_price must be a non-negative number' });
    return;
  }
  if (body.per_seat_price !== undefined && (typeof body.per_seat_price !== 'number' || body.per_seat_price < 0)) {
    res.status(400).json({ error: 'per_seat_price must be a non-negative number' });
    return;
  }
  if (body.billing_period !== undefined && !['monthly', 'annual'].includes(body.billing_period)) {
    res.status(400).json({ error: `billing_period must be 'monthly' or 'annual'` });
    return;
  }
  if (body.trial_days !== undefined && (!Number.isInteger(body.trial_days) || body.trial_days < 0)) {
    res.status(400).json({ error: 'trial_days must be a non-negative integer' });
    return;
  }

  // Build dynamic SET clause — only update fields that were sent
  const ALLOWED_FIELDS = ['name', 'base_price', 'per_seat_price', 'billing_period', 'trial_days', 'is_active'] as const;
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
    UPDATE plans
    SET    ${sets.join(', ')}
    WHERE  id = $${i}
    RETURNING id, name, billing_model, base_price, per_seat_price,
              billing_period, trial_days, is_active, updated_at
  `;

  try {
    const result = await dbClient.query(query, values);
    if (result.rowCount === 0) {
      res.status(404).json({ error: 'Plan not found' });
      return;
    }
    res.json({ plan: result.rows[0] });
  } catch (err) {
    const message = err instanceof Error ? err.message : '';
    if (message.includes('violates check constraint')) {
      res.status(400).json({ error: 'Plan data violates a database constraint' });
    } else {
      res.status(500).json({ error: 'Failed to update plan' });
    }
  }
});

// DELETE /api/plans/:id
// Soft-deletes a plan by setting is_active = false.
// Hard delete is unsafe — subscriptions may reference this plan (ON DELETE RESTRICT).
router.delete('/:id', async (req: Request, res: Response): Promise<void> => {
  const { dbClient } = req as AuthRequest;

  try {
    const result = await dbClient.query(
      `UPDATE plans
       SET    is_active = FALSE
       WHERE  id = $1
       RETURNING id, name, is_active`,
      [req.params.id],
    );
    if (result.rowCount === 0) {
      res.status(404).json({ error: 'Plan not found' });
      return;
    }
    res.json({ plan: result.rows[0] });
  } catch {
    res.status(500).json({ error: 'Failed to deactivate plan' });
  }
});

export default router;
