-- Migration 002: plans + plan_features
-- Tenant-defined pricing tiers and their feature sets.
-- ============================================================

-- @UP

CREATE TABLE plans (
    id             UUID          NOT NULL DEFAULT gen_random_uuid(),
    tenant_id      UUID          NOT NULL,
    name           VARCHAR(100)  NOT NULL,
    billing_model  VARCHAR(20)   NOT NULL
                   CHECK (billing_model IN ('flat_rate', 'per_seat', 'usage_based')),
    base_price     NUMERIC(12,2) NOT NULL
                   CHECK (base_price >= 0),
    per_seat_price NUMERIC(12,2)
                   CHECK (per_seat_price IS NULL OR per_seat_price >= 0),
    billing_period VARCHAR(10)   NOT NULL DEFAULT 'monthly'
                   CHECK (billing_period IN ('monthly', 'annual')),
    trial_days     INTEGER       NOT NULL DEFAULT 0
                   CHECK (trial_days >= 0),
    is_active      BOOLEAN       NOT NULL DEFAULT TRUE,
    created_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    updated_at     TIMESTAMPTZ   NOT NULL DEFAULT NOW(),
    CONSTRAINT plans_pkey                    PRIMARY KEY (id),
    CONSTRAINT plans_tenant_fkey             FOREIGN KEY (tenant_id)
                                             REFERENCES tenants(id) ON DELETE CASCADE,
    -- per_seat_price must be supplied when billing model requires it.
    -- This is a cross-column CHECK — demonstrates multi-column constraint design.
    CONSTRAINT plans_per_seat_price_required
        CHECK (billing_model != 'per_seat' OR per_seat_price IS NOT NULL)
);

CREATE TRIGGER trg_plans_updated_at
    BEFORE UPDATE ON plans
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Composite index: tenant scoping is always the outer filter.
CREATE INDEX idx_plans_tenant_id ON plans(tenant_id);

-- Partial index: billing jobs and plan selectors only care about active plans.
-- Smaller index, faster scans — demonstrates partial index value.
CREATE INDEX idx_plans_tenant_active
    ON plans(tenant_id)
    WHERE is_active = TRUE;

-- plan_features: each row is one key-value feature belonging to a plan.
-- Normalized — avoids wide sparse columns like has_api_access, has_sso, max_seats etc.
-- Demonstrates 1NF (no repeating groups) and justified table decomposition.
CREATE TABLE plan_features (
    id            UUID         NOT NULL DEFAULT gen_random_uuid(),
    tenant_id     UUID         NOT NULL,
    plan_id       UUID         NOT NULL,
    feature_key   VARCHAR(100) NOT NULL,
    feature_value VARCHAR(255) NOT NULL,
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT plan_features_pkey          PRIMARY KEY (id),
    CONSTRAINT plan_features_tenant_fkey   FOREIGN KEY (tenant_id)
                                           REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT plan_features_plan_fkey     FOREIGN KEY (plan_id)
                                           REFERENCES plans(id) ON DELETE CASCADE,
    -- A plan cannot have two values for the same feature key.
    CONSTRAINT plan_features_plan_key_unique UNIQUE (plan_id, feature_key)
);

-- plan_id index: features are always fetched by plan.
CREATE INDEX idx_plan_features_plan_id ON plan_features(plan_id);


-- @DOWN

DROP INDEX   IF EXISTS idx_plan_features_plan_id;
DROP TABLE   IF EXISTS plan_features;
DROP INDEX   IF EXISTS idx_plans_tenant_active;
DROP INDEX   IF EXISTS idx_plans_tenant_id;
DROP TRIGGER IF EXISTS trg_plans_updated_at ON plans;
DROP TABLE   IF EXISTS plans;
