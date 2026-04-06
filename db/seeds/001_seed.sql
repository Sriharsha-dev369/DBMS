-- Seed 001: Phase 1 + Phase 2 baseline data
-- Two tenants, realistic plans + features, 10 named customers each, subscriptions in all 6 states.
-- Passwords: all seed users log in with "password123"
-- Fixed UUIDs so demos and future test scripts can hardcode references.
-- Safe to re-run — wipes then re-inserts in FK dependency order.
--
-- Tenant A : a0000000-0000-0000-0000-000000000001  (acme-corp)
-- Tenant B : a0000000-0000-0000-0000-000000000002  (globex-inc)
-- Plans    : b0000000-0000-0000-0000-00000000000[1-8] (Acme:1-4,8 Globex:5-7)
-- Users    : c0000000-0000-0000-0000-00000000000[1-3]
-- Customers: d0000000-0000-0000-0000-00000000000[1-20] (Acme:1-10, Globex:11-20)
-- Subs     : e0000000-0000-0000-0000-00000000000[1-12]
-- ============================================================

-- ── Teardown (reverse FK order) ───────────────────────────────
-- subscriptions before customers (ON DELETE RESTRICT on customer_id)
DELETE FROM subscriptions WHERE tenant_id IN (
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000002');
DELETE FROM customers     WHERE tenant_id IN (
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000002');
DELETE FROM plan_features WHERE tenant_id IN (
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000002');
DELETE FROM plans         WHERE tenant_id IN (
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000002');
DELETE FROM tenant_users  WHERE tenant_id IN (
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000002');
DELETE FROM tenants WHERE id IN (
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000002');

-- ── Tenants ───────────────────────────────────────────────────
INSERT INTO tenants (id, name, slug, email, status) VALUES
    ('a0000000-0000-0000-0000-000000000001', 'Acme Corp',  'acme-corp',  'billing@acme.com',   'active'),
    ('a0000000-0000-0000-0000-000000000002', 'Globex Inc', 'globex-inc', 'billing@globex.com', 'active');

-- ── Tenant Users ──────────────────────────────────────────────
-- All passwords: "password123"
-- Hashes generated with bcryptjs rounds=10
INSERT INTO tenant_users (id, tenant_id, email, password_hash, name, role) VALUES
    ('c0000000-0000-0000-0000-000000000001',
     'a0000000-0000-0000-0000-000000000001',
     'owner@acme.com',
     '$2a$10$TNe7WGvm6BVEC1EnAtzst.60129jMuwfPbz0Su2tpnw76vneo6Pie',
     'Alice (Acme)', 'owner'),

    ('c0000000-0000-0000-0000-000000000002',
     'a0000000-0000-0000-0000-000000000001',
     'member@acme.com',
     '$2a$10$Aai/tfnzLVKuVsZfakp.hOEZunS6A6qC0jh.NyMCJw3i9tlw1u4F6',
     'Bob (Acme)', 'member'),

    ('c0000000-0000-0000-0000-000000000003',
     'a0000000-0000-0000-0000-000000000002',
     'owner@globex.com',
     '$2a$10$QBF0.TgLooM3uX9WDuJnReiqkx0qRNnnfLwDdTU/VM26In4OjN9iu',
     'Carol (Globex)', 'owner');

-- ── Plans ─────────────────────────────────────────────────────
INSERT INTO plans (id, tenant_id, name, billing_model, base_price, per_seat_price, billing_period, trial_days, is_active) VALUES
    -- Acme Corp: 4 active plans + 1 inactive legacy
    --   flat_rate  → base_price only, per_seat_price NULL
    --   per_seat   → per_seat_price required (cross-column CHECK enforced by DB)
    --   usage_based→ base_price is platform fee; metered events billed in Phase 3
    --   is_active=FALSE on Legacy → exercises idx_plans_tenant_active partial index
    ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Starter',    'flat_rate',   29.00,  NULL,  'monthly', 14, TRUE),
    ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Pro',        'per_seat',    49.00,  9.00,  'monthly',  7, TRUE),
    ('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Enterprise', 'per_seat',   199.00, 15.00, 'annual',   0, TRUE),
    ('b0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'Metered',    'usage_based',  0.00,  NULL,  'monthly',  0, TRUE),
    ('b0000000-0000-0000-0000-000000000008', 'a0000000-0000-0000-0000-000000000001', 'Legacy',     'flat_rate',   19.00,  NULL,  'monthly',  0, FALSE),
    -- Globex Inc: 3 plans
    ('b0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000002', 'Basic',      'flat_rate',   19.00,  NULL,  'monthly', 30, TRUE),
    ('b0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000002', 'Growth',     'per_seat',    39.00,  7.00,  'monthly',  7, TRUE),
    ('b0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000002', 'Scale',      'per_seat',   149.00, 12.00, 'annual',   0, TRUE);

-- ── Plan Features ─────────────────────────────────────────────
-- Normalized key-value — demonstrates 1NF and justified table decomposition.
INSERT INTO plan_features (plan_id, tenant_id, feature_key, feature_value) VALUES
    -- Acme Starter
    ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'max_customers', '100'),
    ('b0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'api_access',    'false'),
    -- Acme Pro
    ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'max_customers', '1000'),
    ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'api_access',    'true'),
    ('b0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'sso',           'false'),
    -- Acme Enterprise
    ('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'max_customers', 'unlimited'),
    ('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'api_access',    'true'),
    ('b0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'sso',           'true'),
    -- Globex Basic
    ('b0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000002', 'max_customers', '50'),
    ('b0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000002', 'api_access',    'false'),
    -- Globex Growth
    ('b0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000002', 'max_customers', '500'),
    ('b0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000002', 'api_access',    'true'),
    -- Globex Scale
    ('b0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000002', 'max_customers', 'unlimited'),
    ('b0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000002', 'api_access',    'true'),
    ('b0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000002', 'sso',           'true');

-- ── Customers: 10 per tenant (fixed UUIDs for subscription references) ────
-- Mix of statuses: 8 active, 1 inactive, 1 blocked per tenant.
-- JSONB metadata demonstrates flexible per-tenant fields (Acme: phone, Globex: region).
-- Composite UNIQUE proof: alice@startup.io appears in BOTH tenants.
-- d0000000-...-[01-10] = Acme, [11-20] = Globex
INSERT INTO customers (id, tenant_id, email, name, status, metadata) VALUES
    -- Acme Corp (d...01 - d...10)
    ('d0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'alice@startup.io',     'Alice Martin',    'active',   '{"company": "Startup IO",   "phone": "+1-555-0101"}'),
    ('d0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'bob@techcorp.com',     'Bob Chen',        'active',   '{"company": "Tech Corp",    "phone": "+1-555-0102"}'),
    ('d0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'carol@designco.io',    'Carol Smith',     'active',   '{"company": "Design Co",    "phone": "+1-555-0103"}'),
    ('d0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'dave@retailhub.com',   'Dave Kumar',      'active',   '{"company": "Retail Hub",   "phone": "+1-555-0104"}'),
    ('d0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000001', 'eve@cloudbase.io',     'Eve Johnson',     'active',   '{"company": "Cloud Base",   "phone": "+1-555-0105"}'),
    ('d0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000001', 'frank@mediapro.com',   'Frank Lee',       'active',   '{"company": "Media Pro",    "phone": "+1-555-0106"}'),
    ('d0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000001', 'grace@fintech.io',     'Grace Park',      'active',   '{"company": "FinTech IO",   "phone": "+1-555-0107"}'),
    ('d0000000-0000-0000-0000-000000000008', 'a0000000-0000-0000-0000-000000000001', 'henry@logisticx.com',  'Henry Brown',     'active',   '{"company": "LogistiX",     "phone": "+1-555-0108"}'),
    ('d0000000-0000-0000-0000-000000000009', 'a0000000-0000-0000-0000-000000000001', 'iris@healthplus.io',   'Iris Wang',       'inactive', '{"company": "Health Plus",  "phone": "+1-555-0109"}'),
    ('d0000000-0000-0000-0000-000000000010', 'a0000000-0000-0000-0000-000000000001', 'jack@edusaas.com',     'Jack Taylor',     'blocked',  '{"company": "EduSaaS",      "phone": "+1-555-0110"}'),
    -- Globex Inc (d...11 - d...20)
    -- alice@startup.io also exists in Acme — same email, different tenant_id: UNIQUE(tenant_id,email) allows it
    ('d0000000-0000-0000-0000-000000000011', 'a0000000-0000-0000-0000-000000000002', 'alice@startup.io',     'Alice at Globex', 'active',   '{"company": "Startup IO",   "region": "us-west"}'),
    ('d0000000-0000-0000-0000-000000000012', 'a0000000-0000-0000-0000-000000000002', 'kate@nexustech.com',   'Kate Wilson',     'active',   '{"company": "Nexus Tech",   "region": "us-east"}'),
    ('d0000000-0000-0000-0000-000000000013', 'a0000000-0000-0000-0000-000000000002', 'liam@alphasoft.io',    'Liam Davis',      'active',   '{"company": "Alpha Soft",   "region": "us-west"}'),
    ('d0000000-0000-0000-0000-000000000014', 'a0000000-0000-0000-0000-000000000002', 'mia@betaworks.com',    'Mia Garcia',      'active',   '{"company": "Beta Works",   "region": "eu-west"}'),
    ('d0000000-0000-0000-0000-000000000015', 'a0000000-0000-0000-0000-000000000002', 'noah@gammasys.io',     'Noah Martinez',   'active',   '{"company": "Gamma Sys",    "region": "us-east"}'),
    ('d0000000-0000-0000-0000-000000000016', 'a0000000-0000-0000-0000-000000000002', 'olivia@deltaops.com',  'Olivia Anderson', 'active',   '{"company": "Delta Ops",    "region": "ap-south"}'),
    ('d0000000-0000-0000-0000-000000000017', 'a0000000-0000-0000-0000-000000000002', 'peter@epsilonai.io',   'Peter Thompson',  'active',   '{"company": "Epsilon AI",   "region": "us-west"}'),
    ('d0000000-0000-0000-0000-000000000018', 'a0000000-0000-0000-0000-000000000002', 'quinn@zetacloud.com',  'Quinn Harris',    'active',   '{"company": "Zeta Cloud",   "region": "eu-central"}'),
    ('d0000000-0000-0000-0000-000000000019', 'a0000000-0000-0000-0000-000000000002', 'rachel@etaplatform.io','Rachel White',    'active',   '{"company": "Eta Platform", "region": "us-east"}'),
    ('d0000000-0000-0000-0000-000000000020', 'a0000000-0000-0000-0000-000000000002', 'sam@thetadev.com',     'Sam Lewis',       'inactive', '{"company": "Theta Dev",    "region": "ap-east"}');

-- ── Subscriptions ─────────────────────────────────────────────
-- All 6 statuses represented. Constraints exercised:
--   • period_order: current_period_end > current_period_start (every row)
--   • cancelled_at_set: cancelled_at NOT NULL when status IN ('cancelled','expired')
--   • trial_end_after_start: trial_end >= current_period_start (trialing rows)
--   • idx_one_active_sub_per_customer: only one non-terminal sub per customer (verified below)
--   • seat_count > 0 for per_seat plans
-- e0000000-...-[01-12]
INSERT INTO subscriptions
    (id, tenant_id, customer_id, plan_id, status, seat_count,
     current_period_start, current_period_end, trial_end,
     cancelled_at, cancel_at_period_end)
VALUES
    -- ── Acme Corp ──────────────────────────────────────────────

    -- active: Alice on Pro (per_seat), mid-period
    ('e0000000-0000-0000-0000-000000000001',
     'a0000000-0000-0000-0000-000000000001',
     'd0000000-0000-0000-0000-000000000001',
     'b0000000-0000-0000-0000-000000000002',
     'active', 5,
     NOW() - INTERVAL '15 days', NOW() + INTERVAL '15 days',
     NULL, NULL, FALSE),

    -- trialing: Bob on Starter (flat_rate, trial_days=14)
    ('e0000000-0000-0000-0000-000000000002',
     'a0000000-0000-0000-0000-000000000001',
     'd0000000-0000-0000-0000-000000000002',
     'b0000000-0000-0000-0000-000000000001',
     'trialing', NULL,
     NOW() - INTERVAL '3 days', NOW() + INTERVAL '11 days',
     NOW() + INTERVAL '11 days', NULL, FALSE),

    -- past_due: Carol on Enterprise (per_seat), payment failed
    ('e0000000-0000-0000-0000-000000000003',
     'a0000000-0000-0000-0000-000000000001',
     'd0000000-0000-0000-0000-000000000003',
     'b0000000-0000-0000-0000-000000000003',
     'past_due', 10,
     NOW() - INTERVAL '35 days', NOW() - INTERVAL '5 days',
     NULL, NULL, FALSE),

    -- paused: Dave on Starter, billing suspended
    ('e0000000-0000-0000-0000-000000000004',
     'a0000000-0000-0000-0000-000000000001',
     'd0000000-0000-0000-0000-000000000004',
     'b0000000-0000-0000-0000-000000000001',
     'paused', NULL,
     NOW() - INTERVAL '20 days', NOW() + INTERVAL '10 days',
     NULL, NULL, FALSE),

    -- cancelled (terminal): Eve on Pro, cancelled_at required by DB constraint
    ('e0000000-0000-0000-0000-000000000005',
     'a0000000-0000-0000-0000-000000000001',
     'd0000000-0000-0000-0000-000000000005',
     'b0000000-0000-0000-0000-000000000002',
     'cancelled', NULL,
     NOW() - INTERVAL '60 days', NOW() - INTERVAL '30 days',
     NULL, NOW() - INTERVAL '35 days', FALSE),

    -- active: Frank on Metered (usage_based), no seat_count
    ('e0000000-0000-0000-0000-000000000006',
     'a0000000-0000-0000-0000-000000000001',
     'd0000000-0000-0000-0000-000000000006',
     'b0000000-0000-0000-0000-000000000004',
     'active', NULL,
     NOW() - INTERVAL '5 days', NOW() + INTERVAL '25 days',
     NULL, NULL, FALSE),

    -- expired (terminal): Grace on Starter, trial ended without conversion
    ('e0000000-0000-0000-0000-000000000007',
     'a0000000-0000-0000-0000-000000000001',
     'd0000000-0000-0000-0000-000000000007',
     'b0000000-0000-0000-0000-000000000001',
     'expired', NULL,
     NOW() - INTERVAL '45 days', NOW() - INTERVAL '31 days',
     NOW() - INTERVAL '31 days', NOW() - INTERVAL '31 days', FALSE),

    -- active: Henry on Enterprise (per_seat), cancel_at_period_end=TRUE
    -- Status stays 'active' until period ends — billing job will set to 'cancelled'
    ('e0000000-0000-0000-0000-000000000008',
     'a0000000-0000-0000-0000-000000000001',
     'd0000000-0000-0000-0000-000000000008',
     'b0000000-0000-0000-0000-000000000003',
     'active', 20,
     NOW() - INTERVAL '10 days', NOW() + INTERVAL '355 days',
     NULL, NOW() - INTERVAL '1 day', TRUE),

    -- ── Globex Inc ─────────────────────────────────────────────

    -- active: Alice@Globex on Basic (flat_rate)
    ('e0000000-0000-0000-0000-000000000009',
     'a0000000-0000-0000-0000-000000000002',
     'd0000000-0000-0000-0000-000000000011',
     'b0000000-0000-0000-0000-000000000005',
     'active', NULL,
     NOW() - INTERVAL '8 days', NOW() + INTERVAL '22 days',
     NULL, NULL, FALSE),

    -- trialing: Kate on Growth (per_seat, trial_days=7)
    ('e0000000-0000-0000-0000-000000000010',
     'a0000000-0000-0000-0000-000000000002',
     'd0000000-0000-0000-0000-000000000012',
     'b0000000-0000-0000-0000-000000000006',
     'trialing', 3,
     NOW() - INTERVAL '2 days', NOW() + INTERVAL '5 days',
     NOW() + INTERVAL '5 days', NULL, FALSE),

    -- active: Liam on Scale (per_seat, annual)
    ('e0000000-0000-0000-0000-000000000011',
     'a0000000-0000-0000-0000-000000000002',
     'd0000000-0000-0000-0000-000000000013',
     'b0000000-0000-0000-0000-000000000007',
     'active', 15,
     NOW() - INTERVAL '30 days', NOW() + INTERVAL '335 days',
     NULL, NULL, FALSE),

    -- cancelled (terminal): Mia on Basic
    ('e0000000-0000-0000-0000-000000000012',
     'a0000000-0000-0000-0000-000000000002',
     'd0000000-0000-0000-0000-000000000014',
     'b0000000-0000-0000-0000-000000000005',
     'cancelled', NULL,
     NOW() - INTERVAL '40 days', NOW() - INTERVAL '10 days',
     NULL, NOW() - INTERVAL '15 days', FALSE);

-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
-- INVALID TRANSITION TEST (commented — run manually to demo)
-- The partial unique index idx_one_active_sub_per_customer rejects
-- creating a second non-terminal subscription for the same customer.
-- The cancelled_at_set CHECK rejects setting status='cancelled'
-- without also setting cancelled_at.
--
-- Test 1: Duplicate active sub (rejected by partial unique index)
-- INSERT INTO subscriptions
--     (tenant_id, customer_id, plan_id, status,
--      current_period_start, current_period_end)
-- VALUES (
--     'a0000000-0000-0000-0000-000000000001',
--     'd0000000-0000-0000-0000-000000000001',  -- Alice already has active sub e...01
--     'b0000000-0000-0000-0000-000000000001',
--     'active',
--     NOW(), NOW() + INTERVAL '30 days'
-- );
-- → ERROR: duplicate key value violates unique constraint "idx_one_active_sub_per_customer"
--
-- Test 2: Set cancelled without cancelled_at (rejected by CHECK constraint)
-- UPDATE subscriptions SET status = 'cancelled'
-- WHERE id = 'e0000000-0000-0000-0000-000000000001';
-- → ERROR: new row for relation "subscriptions" violates check constraint "cancelled_at_set"
-- ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
