/**
 * Subscription state machine + business logic helpers.
 * Pure functions — no DB imports. SQL stays in route handlers.
 */

// ── Valid state transitions (see docs/subscription_states.md) ─────
const VALID_TRANSITIONS: Record<string, string[]> = {
  trialing: ['active', 'cancelled', 'expired'],
  active:   ['past_due', 'paused', 'cancelled'],
  past_due: ['active', 'cancelled', 'expired'],
  paused:   ['active', 'cancelled'],
  cancelled: [],
  expired:   [],
};

export function validateTransition(currentStatus: string, newStatus: string): void {
  const allowed = VALID_TRANSITIONS[currentStatus];
  if (!allowed) {
    throw new Error(`Unknown subscription status: ${currentStatus}`);
  }
  if (!allowed.includes(newStatus)) {
    throw new Error(
      `Invalid transition: ${currentStatus} → ${newStatus}`
    );
  }
}

export function isTerminalStatus(status: string): boolean {
  return status === 'cancelled' || status === 'expired';
}

// ── Billing period helpers ────────────────────────────────────────
export const BILLING_PERIOD_DAYS: Record<string, number> = {
  monthly: 30,
  annual:  365,
};

export function computePeriodEnd(start: Date, billingPeriod: string): Date {
  const days = BILLING_PERIOD_DAYS[billingPeriod] ?? 30;
  return new Date(start.getTime() + days * 86_400_000);
}
