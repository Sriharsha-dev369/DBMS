import { Router, Request, Response } from 'express';
import { protected_ } from '../middleware/protected';
import { AuthRequest } from '../types/auth';
import {
  CreateSubscriptionBody,
  CancelSubscriptionBody,
  UpgradeSubscriptionBody,
} from '../types/api';
import {
  validateTransition,
  computePeriodEnd,
} from '../services/subscriptionService';

const router = Router();
router.use(...protected_);

// ── Columns to return on every subscription response ──────────────
const SUB_COLUMNS = `
  id, customer_id, plan_id, status, seat_count,
  current_period_start, current_period_end, trial_end,
  cancelled_at, cancel_at_period_end, idempotency_key,
  created_at, updated_at
`;

// ── Allowed status values for filtering ───────────────────────────
const VALID_STATUSES = ['trialing', 'active', 'past_due', 'paused', 'cancelled', 'expired'];

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// GET /api/subscriptions — paginated list with optional filters
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
router.get('/', async (req: Request, res: Response): Promise<void> => {
  const { dbClient } = req as AuthRequest;

  const limit  = Math.min(Math.max(parseInt(req.query.limit  as string) || 20, 1), 100);
  const offset = Math.max(parseInt(req.query.offset as string) || 0, 0);
  const status = req.query.status as string | undefined;
  const customerId = req.query.customer_id as string | undefined;

  if (status && !VALID_STATUSES.includes(status)) {
    res.status(400).json({ error: `Invalid status. Must be one of: ${VALID_STATUSES.join(', ')}` });
    return;
  }

  try {
    const conditions: string[] = [];
    const params: unknown[] = [];
    let idx = 1;

    if (status) {
      conditions.push(`status = $${idx++}`);
      params.push(status);
    }
    if (customerId) {
      conditions.push(`customer_id = $${idx++}`);
      params.push(customerId);
    }

    const where = conditions.length > 0 ? `WHERE ${conditions.join(' AND ')}` : '';

    const countResult = await dbClient.query(
      `SELECT COUNT(*) FROM subscriptions ${where}`,
      params,
    );
    const total = parseInt(countResult.rows[0].count, 10);

    const dataResult = await dbClient.query(
      `SELECT ${SUB_COLUMNS}
       FROM   subscriptions ${where}
       ORDER  BY created_at DESC
       LIMIT  $${idx++} OFFSET $${idx++}`,
      [...params, limit, offset],
    );

    res.json({
      subscriptions: dataResult.rows,
      pagination: { total, limit, offset },
    });
  } catch {
    res.status(500).json({ error: 'Failed to fetch subscriptions' });
  }
});

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// GET /api/subscriptions/:id — single subscription
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
router.get('/:id', async (req: Request, res: Response): Promise<void> => {
  const { dbClient } = req as AuthRequest;

  try {
    const result = await dbClient.query(
      `SELECT ${SUB_COLUMNS} FROM subscriptions WHERE id = $1`,
      [req.params.id],
    );
    if (result.rowCount === 0) {
      res.status(404).json({ error: 'Subscription not found' });
      return;
    }
    res.json({ subscription: result.rows[0] });
  } catch {
    res.status(500).json({ error: 'Failed to fetch subscription' });
  }
});

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// POST /api/subscriptions — create subscription
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
router.post('/', async (req: Request, res: Response): Promise<void> => {
  const { dbClient, auth } = req as AuthRequest;
  const body = req.body as CreateSubscriptionBody;

  // ── Validate required fields ────────────────────────────────────
  if (!body.customer_id || !body.plan_id) {
    res.status(400).json({ error: 'customer_id and plan_id are required' });
    return;
  }

  try {
    // ── Look up the plan (RLS auto-scopes to tenant) ──────────────
    const planResult = await dbClient.query(
      `SELECT id, billing_model, base_price, billing_period, trial_days, is_active
       FROM   plans
       WHERE  id = $1`,
      [body.plan_id],
    );
    if (planResult.rowCount === 0) {
      res.status(404).json({ error: 'Plan not found' });
      return;
    }
    const plan = planResult.rows[0];

    if (!plan.is_active) {
      res.status(400).json({ error: 'Cannot subscribe to an inactive plan' });
      return;
    }

    // ── Validate seat_count for per_seat plans ────────────────────
    if (plan.billing_model === 'per_seat') {
      if (!body.seat_count || body.seat_count < 1) {
        res.status(400).json({ error: 'seat_count is required and must be > 0 for per_seat plans' });
        return;
      }
    }

    // ── Verify customer exists and is active under this tenant ───────
    const custResult = await dbClient.query(
      `SELECT id, status FROM customers WHERE id = $1`,
      [body.customer_id],
    );
    if (custResult.rowCount === 0) {
      res.status(404).json({ error: 'Customer not found' });
      return;
    }
    if (custResult.rows[0].status !== 'active') {
      res.status(400).json({ error: 'Cannot create subscription for an inactive or blocked customer' });
      return;
    }

    // ── Compute dates based on trial_days ─────────────────────────
    const now = new Date();
    let status: string;
    let trialEnd: Date | null;
    let periodStart: Date;
    let periodEnd: Date;

    if (plan.trial_days > 0) {
      status     = 'trialing';
      trialEnd   = new Date(now.getTime() + plan.trial_days * 86_400_000);
      periodStart = now;
      periodEnd   = trialEnd;
    } else {
      status     = 'active';
      trialEnd   = null;
      periodStart = now;
      periodEnd   = computePeriodEnd(now, plan.billing_period);
    }

    const seatCount = plan.billing_model === 'per_seat' ? body.seat_count : null;

    // ── INSERT ────────────────────────────────────────────────────
    const result = await dbClient.query(
      `INSERT INTO subscriptions
         (tenant_id, customer_id, plan_id, status, seat_count,
          current_period_start, current_period_end, trial_end)
       VALUES ($1, $2, $3, $4, $5, $6, $7, $8)
       RETURNING ${SUB_COLUMNS}`,
      [auth.tenantId, body.customer_id, body.plan_id, status,
       seatCount, periodStart, periodEnd, trialEnd],
    );

    res.status(201).json({ subscription: result.rows[0] });
  } catch (err: unknown) {
    const msg = err instanceof Error ? err.message : '';
    if (msg.includes('idx_one_active_sub_per_customer') || msg.includes('unique')) {
      res.status(409).json({ error: 'Customer already has an active subscription' });
    } else {
      res.status(500).json({ error: 'Failed to create subscription' });
    }
  }
});

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// POST /api/subscriptions/:id/cancel
// Body: { immediate?: boolean }  (default false = cancel_at_period_end)
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
router.post('/:id/cancel', async (req: Request, res: Response): Promise<void> => {
  const { dbClient } = req as AuthRequest;
  const body = req.body as CancelSubscriptionBody;
  const immediate = body.immediate ?? false;

  try {
    // Fetch current subscription
    const subResult = await dbClient.query(
      `SELECT id, status FROM subscriptions WHERE id = $1`,
      [req.params.id],
    );
    if (subResult.rowCount === 0) {
      res.status(404).json({ error: 'Subscription not found' });
      return;
    }
    const sub = subResult.rows[0];

    // Validate transition
    try {
      validateTransition(sub.status, 'cancelled');
    } catch (err: unknown) {
      res.status(409).json({ error: (err as Error).message });
      return;
    }

    let result;

    // cancel_at_period_end only applies when current status is 'active' and not immediate
    if (!immediate && sub.status === 'active') {
      result = await dbClient.query(
        `UPDATE subscriptions
         SET    cancel_at_period_end = true,
                cancelled_at = NOW()
         WHERE  id = $1
         RETURNING ${SUB_COLUMNS}`,
        [req.params.id],
      );
    } else {
      // Immediate cancel (or non-active states where cancel_at_period_end is meaningless)
      result = await dbClient.query(
        `UPDATE subscriptions
         SET    status = 'cancelled',
                cancelled_at = NOW(),
                cancel_at_period_end = false
         WHERE  id = $1
         RETURNING ${SUB_COLUMNS}`,
        [req.params.id],
      );
    }

    res.json({ subscription: result.rows[0] });
  } catch {
    res.status(500).json({ error: 'Failed to cancel subscription' });
  }
});

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// POST /api/subscriptions/:id/pause — only from 'active'
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
router.post('/:id/pause', async (req: Request, res: Response): Promise<void> => {
  const { dbClient } = req as AuthRequest;

  try {
    const subResult = await dbClient.query(
      `SELECT id, status FROM subscriptions WHERE id = $1`,
      [req.params.id],
    );
    if (subResult.rowCount === 0) {
      res.status(404).json({ error: 'Subscription not found' });
      return;
    }

    try {
      validateTransition(subResult.rows[0].status, 'paused');
    } catch (err: unknown) {
      res.status(409).json({ error: (err as Error).message });
      return;
    }

    const result = await dbClient.query(
      `UPDATE subscriptions SET status = 'paused' WHERE id = $1 RETURNING ${SUB_COLUMNS}`,
      [req.params.id],
    );

    res.json({ subscription: result.rows[0] });
  } catch {
    res.status(500).json({ error: 'Failed to pause subscription' });
  }
});

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// POST /api/subscriptions/:id/resume — only from 'paused'
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
router.post('/:id/resume', async (req: Request, res: Response): Promise<void> => {
  const { dbClient } = req as AuthRequest;

  try {
    const subResult = await dbClient.query(
      `SELECT id, status FROM subscriptions WHERE id = $1`,
      [req.params.id],
    );
    if (subResult.rowCount === 0) {
      res.status(404).json({ error: 'Subscription not found' });
      return;
    }

    try {
      validateTransition(subResult.rows[0].status, 'active');
    } catch (err: unknown) {
      res.status(409).json({ error: (err as Error).message });
      return;
    }

    const result = await dbClient.query(
      `UPDATE subscriptions SET status = 'active' WHERE id = $1 RETURNING ${SUB_COLUMNS}`,
      [req.params.id],
    );

    res.json({ subscription: result.rows[0] });
  } catch {
    res.status(500).json({ error: 'Failed to resume subscription' });
  }
});

// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
// POST /api/subscriptions/:id/upgrade — plan change + proration
// Wraps everything in a transaction with SELECT FOR UPDATE.
// ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
router.post('/:id/upgrade', async (req: Request, res: Response): Promise<void> => {
  const { dbClient } = req as AuthRequest;
  const body = req.body as UpgradeSubscriptionBody;

  if (!body.new_plan_id) {
    res.status(400).json({ error: 'new_plan_id is required' });
    return;
  }

  try {
    await dbClient.query('BEGIN');

    // ── Lock the subscription row ─────────────────────────────────
    const subResult = await dbClient.query(
      `SELECT s.id, s.status, s.plan_id, s.seat_count,
              s.current_period_start, s.current_period_end,
              p.base_price AS old_base_price,
              p.billing_model AS old_billing_model
       FROM   subscriptions s
       JOIN   plans p ON p.id = s.plan_id
       WHERE  s.id = $1
       FOR UPDATE OF s`,
      [req.params.id],
    );

    if (subResult.rowCount === 0) {
      await dbClient.query('ROLLBACK');
      res.status(404).json({ error: 'Subscription not found' });
      return;
    }

    const sub = subResult.rows[0];

    if (sub.status !== 'active') {
      await dbClient.query('ROLLBACK');
      res.status(409).json({ error: 'Can only upgrade active subscriptions' });
      return;
    }

    if (sub.plan_id === body.new_plan_id) {
      await dbClient.query('ROLLBACK');
      res.status(400).json({ error: 'Subscription is already on this plan' });
      return;
    }

    // ── Look up the new plan ──────────────────────────────────────
    const newPlanResult = await dbClient.query(
      `SELECT id, billing_model, base_price, billing_period, is_active
       FROM   plans
       WHERE  id = $1`,
      [body.new_plan_id],
    );

    if (newPlanResult.rowCount === 0) {
      await dbClient.query('ROLLBACK');
      res.status(404).json({ error: 'New plan not found' });
      return;
    }

    const newPlan = newPlanResult.rows[0];

    if (!newPlan.is_active) {
      await dbClient.query('ROLLBACK');
      res.status(400).json({ error: 'Cannot upgrade to an inactive plan' });
      return;
    }

    // ── Validate seat_count for per_seat plans ────────────────────
    if (newPlan.billing_model === 'per_seat') {
      if (!body.new_seat_count || body.new_seat_count < 1) {
        await dbClient.query('ROLLBACK');
        res.status(400).json({ error: 'new_seat_count is required and must be > 0 for per_seat plans' });
        return;
      }
    }

    // ── Calculate proration credit ────────────────────────────────
    // NOW() is stable within a transaction — same timestamp everywhere.
    const prorationResult = await dbClient.query(
      `SELECT calculate_proration($1, $2, $3, NOW()) AS credit`,
      [sub.old_base_price, sub.current_period_start, sub.current_period_end],
    );
    const prorationCredit = prorationResult.rows[0].credit;

    // ── Update subscription to new plan ───────────────────────────
    const newSeatCount = newPlan.billing_model === 'per_seat' ? body.new_seat_count : null;
    const newPeriodEnd = computePeriodEnd(new Date(), newPlan.billing_period);

    const updateResult = await dbClient.query(
      `UPDATE subscriptions
       SET    plan_id = $1,
              seat_count = $2,
              current_period_start = NOW(),
              current_period_end   = $3,
              cancel_at_period_end = false
       WHERE  id = $4
       RETURNING ${SUB_COLUMNS}`,
      [body.new_plan_id, newSeatCount, newPeriodEnd, req.params.id],
    );

    await dbClient.query('COMMIT');

    res.json({
      subscription:     updateResult.rows[0],
      proration_credit: prorationCredit,
    });
  } catch (err: unknown) {
    await dbClient.query('ROLLBACK').catch(() => {});
    const msg = err instanceof Error ? err.message : '';
    if (msg.includes('change_date must be within')) {
      res.status(400).json({ error: 'Proration calculation failed: billing period has already ended' });
    } else {
      res.status(500).json({ error: 'Failed to upgrade subscription' });
    }
  }
});

export default router;
