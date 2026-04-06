-- Migration 007: Partial indexes on subscriptions
-- Two partial indexes with very different purposes — both are classic DBMS exam material.
--
-- INDEX 1 — Partial UNIQUE (business constraint)
--   idx_one_active_sub_per_customer
--   Enforces that a customer can hold at most ONE non-terminal subscription at a time.
--   A table-level UNIQUE would wrongly prevent multiple cancelled/expired rows,
--   which must be preserved as billing history.
--   Predicate: WHERE status NOT IN ('cancelled', 'expired')
--
-- INDEX 2 — Partial covering index (query performance)
--   idx_active_subs_due
--   The billing job's hot path: "find all active subscriptions whose period ends
--   on or before NOW()". Only ~active rows need to be in this index. Skipping
--   cancelled/expired rows keeps the index small and highly selective.
--   INCLUDE columns let the billing job read plan_id, seat_count, and
--   idempotency_key without a heap fetch (index-only scan).
--   Predicate: WHERE status = 'active'
--
-- EXPLAIN ANALYZE validation queries are at the bottom (run after seeding subs).
-- ============================================================

-- @UP

-- ── Index 1: Partial UNIQUE ───────────────────────────────────
-- Business invariant: one live subscription per customer.
-- UNIQUE partial index is the only correct tool here — a table constraint
-- cannot express "unique only among non-terminal rows".
CREATE UNIQUE INDEX idx_one_active_sub_per_customer
    ON subscriptions(tenant_id, customer_id)
    WHERE status NOT IN ('cancelled', 'expired');

-- ── Index 2: Partial covering index ──────────────────────────
-- Billing job query pattern:
--   SELECT id, plan_id, seat_count, idempotency_key, current_period_end
--   FROM   subscriptions
--   WHERE  tenant_id = $1
--     AND  status = 'active'
--     AND  current_period_end <= NOW()
--
-- The WHERE clause on status = 'active' matches the index predicate exactly,
-- so PostgreSQL can use this index and serve plan_id / seat_count / idempotency_key
-- from the index leaf pages alone (Index Only Scan).
CREATE INDEX idx_active_subs_due
    ON subscriptions(tenant_id, current_period_end)
    INCLUDE (plan_id, seat_count, idempotency_key)
    WHERE status = 'active';


-- ── EXPLAIN ANALYZE validation ────────────────────────────────
-- Run these after seeding subscriptions in various states.
-- Expected plan for Q1: "Index Only Scan using idx_one_active_sub_per_customer"
-- Expected plan for Q2: "Index Only Scan using idx_active_subs_due"

-- Q1 — Uniqueness check (triggered on every INSERT into subscriptions):
--   EXPLAIN (ANALYZE, BUFFERS)
--   SELECT 1
--   FROM   subscriptions
--   WHERE  tenant_id   = 'a0000000-0000-0000-0000-000000000001'
--     AND  customer_id = '<any customer uuid>'
--     AND  status NOT IN ('cancelled', 'expired');

-- Q2 — Billing job scan (runs every hour on cron):
--   EXPLAIN (ANALYZE, BUFFERS)
--   SELECT id, plan_id, seat_count, idempotency_key, current_period_end
--   FROM   subscriptions
--   WHERE  tenant_id         = 'a0000000-0000-0000-0000-000000000001'
--     AND  status            = 'active'
--     AND  current_period_end <= NOW();


-- @DOWN

DROP INDEX IF EXISTS idx_active_subs_due;
DROP INDEX IF EXISTS idx_one_active_sub_per_customer;
