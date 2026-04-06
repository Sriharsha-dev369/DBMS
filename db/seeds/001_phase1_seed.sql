-- Seed: Phase 1 test data for EXPLAIN ANALYZE demonstration
-- Creates 2 tenants, 4 plans each, 60 customers each (120 total).
-- Run AFTER all migrations: psql -h <host> -U postgres -d saasledger -f db/seeds/001_phase1_seed.sql
-- ============================================================

-- Wipe existing seed data (safe to re-run)
DELETE FROM customers    WHERE tenant_id IN (SELECT id FROM tenants WHERE slug IN ('acme-corp', 'globex-inc'));
DELETE FROM plan_features WHERE plan_id  IN (SELECT id FROM plans WHERE tenant_id IN (SELECT id FROM tenants WHERE slug IN ('acme-corp', 'globex-inc')));
DELETE FROM plans        WHERE tenant_id IN (SELECT id FROM tenants WHERE slug IN ('acme-corp', 'globex-inc'));
DELETE FROM tenant_users WHERE tenant_id IN (SELECT id FROM tenants WHERE slug IN ('acme-corp', 'globex-inc'));
DELETE FROM tenants      WHERE slug IN ('acme-corp', 'globex-inc');

-- ── Tenants ──────────────────────────────────────────────────
INSERT INTO tenants (id, name, slug, email, status) VALUES
    ('a0000000-0000-0000-0000-000000000001', 'Acme Corp',   'acme-corp',  'admin@acme.com',   'active'),
    ('a0000000-0000-0000-0000-000000000002', 'Globex Inc',  'globex-inc', 'admin@globex.com', 'active');

-- ── Tenant Users ─────────────────────────────────────────────
INSERT INTO tenant_users (tenant_id, email, password_hash, name, role) VALUES
    ('a0000000-0000-0000-0000-000000000001', 'owner@acme.com',   '$2b$10$placeholder_hash_acme',   'Acme Owner',   'owner'),
    ('a0000000-0000-0000-0000-000000000001', 'member@acme.com',  '$2b$10$placeholder_hash_acme2',  'Acme Member',  'member'),
    ('a0000000-0000-0000-0000-000000000002', 'owner@globex.com', '$2b$10$placeholder_hash_globex', 'Globex Owner', 'owner');

-- ── Plans ────────────────────────────────────────────────────
INSERT INTO plans (id, tenant_id, name, billing_model, base_price, per_seat_price, billing_period, trial_days, is_active) VALUES
    -- Acme plans
    ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Starter',    'flat_rate', 29.00,  NULL,  'monthly', 14, TRUE),
    ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Pro',        'per_seat',  49.00,  9.00,  'monthly',  7, TRUE),
    ('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Enterprise', 'per_seat',  199.00, 15.00, 'annual',   0, TRUE),
    ('b0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'Legacy',     'flat_rate', 19.00,  NULL,  'monthly',  0, FALSE),
    -- Globex plans
    ('b0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000002', 'Basic',      'flat_rate', 19.00,  NULL,  'monthly', 30, TRUE),
    ('b0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000002', 'Growth',     'per_seat',  39.00,  7.00,  'monthly',  7, TRUE),
    ('b0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000002', 'Scale',      'per_seat',  99.00,  12.00, 'annual',   0, TRUE),
    ('b0000000-0000-0000-0000-000000000008', 'a0000000-0000-0000-0000-000000000002', 'Deprecated', 'flat_rate', 9.00,   NULL,  'monthly',  0, FALSE);

-- ── Plan Features ────────────────────────────────────────────
INSERT INTO plan_features (plan_id, tenant_id, feature_key, feature_value) VALUES
    ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'max_customers', '100'),
    ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'api_access',    'false'),
    ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'max_customers', '1000'),
    ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'api_access',    'true'),
    ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'sso',           'false'),
    ('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'max_customers', 'unlimited'),
    ('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'api_access',    'true'),
    ('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'sso',           'true');

-- ── Customers: 60 per tenant (generated) ─────────────────────
INSERT INTO customers (tenant_id, email, name, status, metadata)
SELECT
    'a0000000-0000-0000-0000-000000000001',
    'customer' || n || '@acme-client.com',
    'Acme Customer ' || n,
    CASE WHEN n % 10 = 0 THEN 'inactive' ELSE 'active' END,
    jsonb_build_object('company', 'Client Co ' || n, 'plan_tier', 'standard')
FROM generate_series(1, 60) AS n;

INSERT INTO customers (tenant_id, email, name, status, metadata)
SELECT
    'a0000000-0000-0000-0000-000000000002',
    'customer' || n || '@globex-client.com',
    'Globex Customer ' || n,
    CASE WHEN n % 8 = 0 THEN 'blocked' WHEN n % 5 = 0 THEN 'inactive' ELSE 'active' END,
    jsonb_build_object('company', 'Partner Ltd ' || n, 'region', 'us-east')
FROM generate_series(1, 60) AS n;
