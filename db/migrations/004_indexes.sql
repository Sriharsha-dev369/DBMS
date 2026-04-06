-- Migration 004: Composite and covering indexes
-- Most tenant_id indexes were added in 001-003 alongside their tables.
-- This migration adds the remaining indexes and documents the full index strategy.
--
-- Index inventory after this migration:
--   tenant_users : idx_tenant_users_tenant_id(tenant_id)
--                  UNIQUE → implicit index on (tenant_id, email)
--   plans        : idx_plans_tenant_id(tenant_id)
--                  idx_plans_tenant_active — partial on (tenant_id) WHERE is_active
--                  idx_plans_tenant_is_active — composite (tenant_id, is_active) [new]
--   plan_features: idx_plan_features_plan_id(plan_id)
--   customers    : idx_customers_tenant_id(tenant_id)
--                  UNIQUE → implicit index on (tenant_id, email)
--                  idx_customers_tenant_active — partial on (tenant_id) WHERE status='active'
--                  idx_customers_metadata — GIN on metadata JSONB
-- ============================================================

-- @UP

-- Composite index: (tenant_id, is_active)
-- Use case: "list all plans for tenant X" filtered by active status in a WHERE clause.
-- Different from the partial index (idx_plans_tenant_active) which only contains
-- active=TRUE rows. This composite lets the planner use the index for queries that
-- filter OR sort on is_active regardless of its value.
-- EXPLAIN ANALYZE target: query 2 below.
CREATE INDEX idx_plans_tenant_is_active
    ON plans(tenant_id, is_active);


-- @DOWN

DROP INDEX IF EXISTS idx_plans_tenant_is_active;
