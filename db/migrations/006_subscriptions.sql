-- Migration 006: Subscriptions table
-- Implements the subscription state machine (see docs/subscription_states.md).
-- Key DBMS concepts:
--   • CHECK constraint enforces valid status enum values
--   • CONSTRAINT period_order prevents nonsensical billing windows
--   • CONSTRAINT cancelled_at_set enforces that cancellation timestamp is always recorded
--   • RLS policy extends tenant isolation to subscriptions
-- Partial indexes live in migration 007 (idx_one_active_sub_per_customer, idx_active_subs_due).
-- ============================================================

-- @UP

CREATE TABLE subscriptions (
    id                   UUID        NOT NULL DEFAULT gen_random_uuid(),
    tenant_id            UUID        NOT NULL REFERENCES tenants(id)   ON DELETE CASCADE,
    customer_id          UUID        NOT NULL REFERENCES customers(id)  ON DELETE RESTRICT,
    plan_id              UUID        NOT NULL REFERENCES plans(id)      ON DELETE RESTRICT,

    status               VARCHAR(20) NOT NULL DEFAULT 'trialing'
                         CHECK (status IN ('trialing', 'active', 'past_due',
                                           'paused', 'cancelled', 'expired')),

    -- seat_count: required at INSERT when plan.billing_model = 'per_seat' (app-layer rule).
    -- Nullable here because flat_rate and usage_based plans don't use seats.
    seat_count           INTEGER     CHECK (seat_count > 0),

    current_period_start TIMESTAMPTZ NOT NULL,
    current_period_end   TIMESTAMPTZ NOT NULL,

    -- trial_end is set when the plan has trial_days > 0.
    -- NULL means no trial (subscription starts as 'active').
    trial_end            TIMESTAMPTZ,

    -- Populated the moment a cancellation is requested (immediate or at period end).
    -- Structural invariant: always set when status is cancelled or expired.
    cancelled_at         TIMESTAMPTZ,

    -- true  → keep active until current_period_end, then status = 'cancelled'
    -- false → status set to 'cancelled' immediately on cancel request
    cancel_at_period_end BOOLEAN     NOT NULL DEFAULT false,

    -- Prevents the billing job from double-invoicing this subscription in the same cycle.
    -- Generated at INSERT; billing job checks this before creating an invoice.
    idempotency_key      UUID        NOT NULL UNIQUE DEFAULT gen_random_uuid(),

    created_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at           TIMESTAMPTZ NOT NULL DEFAULT NOW(),

    CONSTRAINT subscriptions_pkey
        PRIMARY KEY (id),

    -- A billing window must always be a forward interval.
    CONSTRAINT period_order
        CHECK (current_period_end > current_period_start),

    -- Trial end must be within or just past the start of the billing period.
    CONSTRAINT trial_end_after_start
        CHECK (trial_end IS NULL OR trial_end >= current_period_start),

    -- Whenever a subscription reaches a terminal or cancellation-intent state,
    -- cancelled_at must be recorded so we have an audit-quality timestamp.
    CONSTRAINT cancelled_at_set
        CHECK (
            status NOT IN ('cancelled', 'expired')
            OR cancelled_at IS NOT NULL
        )
);

-- ── Indexes ───────────────────────────────────────────────────

-- Support customer-centric lookups (e.g. GET /customers/:id returns current sub).
CREATE INDEX idx_subscriptions_customer
    ON subscriptions(tenant_id, customer_id);

-- Support plan-centric queries (e.g. "how many active subs on the Pro plan?").
CREATE INDEX idx_subscriptions_plan
    ON subscriptions(tenant_id, plan_id);

-- ── Trigger ───────────────────────────────────────────────────

CREATE TRIGGER set_subscriptions_updated_at
    BEFORE UPDATE ON subscriptions
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- ── RLS ───────────────────────────────────────────────────────

ALTER TABLE subscriptions ENABLE ROW LEVEL SECURITY;

CREATE POLICY tenant_isolation ON subscriptions
    FOR ALL
    USING     (tenant_id = current_tenant_id())
    WITH CHECK (tenant_id = current_tenant_id());

-- Grant app role access (migration 005 granted on ALL TABLES at time of its run;
-- this table was created after, so an explicit grant is required).
GRANT SELECT, INSERT, UPDATE, DELETE ON subscriptions TO saasledger_app;


-- @DOWN

REVOKE ALL ON subscriptions FROM saasledger_app;

DROP POLICY  IF EXISTS tenant_isolation             ON subscriptions;
ALTER TABLE subscriptions DISABLE ROW LEVEL SECURITY;

DROP TRIGGER IF EXISTS set_subscriptions_updated_at ON subscriptions;

DROP INDEX IF EXISTS idx_subscriptions_plan;
DROP INDEX IF EXISTS idx_subscriptions_customer;

DROP TABLE IF EXISTS subscriptions;
