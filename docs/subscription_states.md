# Subscription State Machine

## States

| State | Meaning |
|---|---|
| `trialing` | Customer is in a free trial period. No payment taken yet. |
| `active` | Paid and current. Billing runs at `current_period_end`. |
| `past_due` | Payment failed at renewal. Dunning process begins. |
| `paused` | Manually paused by tenant. Billing suspended. Access may be restricted. |
| `cancelled` | **Terminal.** Cancelled by user or dunning exhaustion. No billing. |
| `expired` | **Terminal.** Trial ended without conversion, or dunning exhausted without payment. |

`cancelled` and `expired` are terminal — no transitions out of them.

---

## State Transition Diagram

```
                         ┌─────────────────────────────────────────┐
  New subscription ─────►│              trialing                   │
  (trial_days > 0)        │  trial period active, no charge yet    │
                          └──────┬──────────┬──────────────────────┘
                                 │          │                │
                   trial ends,   │          │ user cancels   │ trial ends,
                   payment ok    │          │ during trial   │ payment fails /
                                 ▼          ▼  no method     ▼
  New subscription ─────►┌─────────┐  ┌───────────┐  ┌──────────┐
  (trial_days = 0) ──────►│ active  │  │ cancelled │  │ expired  │
                          │         │  │ (terminal)│  │(terminal)│
                          └────┬────┘  └───────────┘  └──────────┘
                               │
              ┌────────────────┼───────────────────┐
              │                │                   │
   payment    │   user pauses  │    user cancels   │
   fails at   │                │    (immediately   │
   renewal    ▼                ▼     or at period  │
         ┌──────────┐    ┌──────────┐    end)      │
         │ past_due │    │  paused  │◄─────────────┘
         └────┬─────┘    └────┬─────┘
              │               │
     ┌────────┼──────┐        ├─────────────────┐
     │        │      │        │                 │
  dunning  payment  dunning  user            user
  retry ok  fails   exhausted resumes       cancels
  after     after   (3x)      while paused  while paused
  retry     max                │                │
     │      retries   │        ▼                ▼
     │         │      │   ┌─────────┐    ┌───────────┐
     │         │      │   │ active  │    │ cancelled │
     ▼         ▼      ▼   └─────────┘    │ (terminal)│
  ┌────────┐ ┌─────────┐  └───────────────────────────┘
  │ active │ │ expired │
  └────────┘ │(terminal│
             └─────────┘
```

---

## Valid Transitions (Canonical Table)

| From | To | Trigger |
|---|---|---|
| `trialing` | `active` | Trial period ends, payment succeeds (billing job) |
| `trialing` | `cancelled` | User cancels during trial |
| `trialing` | `expired` | Trial ends, no payment method / payment fails |
| `active` | `past_due` | Payment fails at period renewal |
| `active` | `paused` | Tenant explicitly pauses subscription |
| `active` | `cancelled` | User cancels immediately, or `cancel_at_period_end` fires |
| `past_due` | `active` | Dunning retry payment succeeds |
| `past_due` | `cancelled` | User cancels while past_due |
| `past_due` | `expired` | Dunning exhausted (3 failures, or max dunning days reached) |
| `paused` | `active` | User resumes subscription |
| `paused` | `cancelled` | User cancels while paused |
| `cancelled` | *(none)* | Terminal state |
| `expired` | *(none)* | Terminal state |

---

## Illegal Transitions

| From | To | Why Rejected |
|---|---|---|
| `cancelled` | *any* | Terminal — subscription is dead |
| `expired` | *any* | Terminal — subscription is dead |
| `trialing` | `past_due` | Trials don't bill mid-period; failure → `expired` directly |
| `trialing` | `paused` | No active billing to pause during a trial |
| `active` | `expired` | Must pass through `past_due` → dunning → `expired` |
| `past_due` | `paused` | Cannot pause while payment is overdue |
| `paused` | `past_due` | Billing is suspended while paused; no payment to fail |
| `paused` | `expired` | Must resume → `active` → fail → `past_due` → `expired` |

---

## DB Enforcement Strategy

| Layer | Mechanism |
|---|---|
| Valid values | `CHECK (status IN ('trialing','active','past_due','paused','cancelled','expired'))` |
| One active sub per customer | `UNIQUE INDEX ... WHERE status NOT IN ('cancelled','expired')` |
| Transition guards | Application layer (`subscriptionService.ts`) validates `oldStatus → newStatus` |
| Billing job idempotency | `idempotency_key UUID UNIQUE` on subscriptions table |
| Cancelled timestamp | `CHECK (status NOT IN ('cancelled','expired') OR cancelled_at IS NOT NULL)` |

> **Note:** PostgreSQL CHECK constraints cannot reference the row's previous state (`OLD`), so transition
> legality (e.g. "cannot go from `paused` to `past_due`") is enforced in the service layer, not the DB.
> The DB enforces: valid values, structural invariants (period order, cancelled_at presence), and uniqueness.

---

## `cancel_at_period_end` Flow

```
PATCH /subscriptions/:id/cancel  { immediate: false }
  └─ UPDATE subscriptions
        SET cancel_at_period_end = true,
            cancelled_at = NOW()          ← record intent timestamp
        WHERE id = $1
        (status stays 'active' — customer keeps access until period end)

Billing job runs at current_period_end:
  └─ IF cancel_at_period_end = true
       UPDATE subscriptions SET status = 'cancelled'
       (no new invoice generated)
```
