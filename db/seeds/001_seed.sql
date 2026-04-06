-- Seed 001: Phase 1 baseline data
-- Two tenants, realistic plans + features, 10 named customers each.
-- Passwords: all seed users log in with "password123"
-- Fixed UUIDs so demos and future test scripts can hardcode references.
-- Safe to re-run — wipes then re-inserts in FK dependency order.
--
-- Tenant A : a0000000-0000-0000-0000-000000000001  (acme-corp)
-- Tenant B : a0000000-0000-0000-0000-000000000002  (globex-inc)
-- Plans    : b0000000-0000-0000-0000-00000000000[1-8] (Acme:1-4,8 Globex:5-7)
-- Users    : c0000000-0000-0000-0000-00000000000[1-3]
-- ============================================================

-- ── Teardown (reverse FK order) ───────────────────────────────
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
    -- Acme Corp: 4 plans
    --   flat_rate  → base_price only, per_seat_price NULL (CHECK: billing_model!='per_seat' OR ... satisfied)
    --   per_seat   → per_seat_price required (cross-column CHECK enforced by DB)
    --   usage_based→ base_price is the platform fee; per_seat_price NULL (metered events billed in Phase 3)
    --   is_active=FALSE on Legacy → exercises the partial index idx_plans_tenant_active
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

-- ── Customers: 10 per tenant ──────────────────────────────────
-- Mix of statuses: 8 active, 1 inactive, 1 blocked per tenant.
-- JSONB metadata demonstrates flexible per-tenant fields (Acme: phone, Globex: region).
--
-- Composite UNIQUE proof: alice@startup.io appears in BOTH tenants.
-- The constraint is UNIQUE(tenant_id, email) — not just UNIQUE(email).
-- Two rows with the same email are legal as long as tenant_id differs.
INSERT INTO customers (tenant_id, email, name, status, metadata) VALUES
    -- Acme Corp
    ('a0000000-0000-0000-0000-000000000001', 'alice@startup.io',     'Alice Martin',    'active',   '{"company": "Startup IO",   "phone": "+1-555-0101"}'),
    ('a0000000-0000-0000-0000-000000000001', 'bob@techcorp.com',     'Bob Chen',        'active',   '{"company": "Tech Corp",    "phone": "+1-555-0102"}'),
    ('a0000000-0000-0000-0000-000000000001', 'carol@designco.io',    'Carol Smith',     'active',   '{"company": "Design Co",    "phone": "+1-555-0103"}'),
    ('a0000000-0000-0000-0000-000000000001', 'dave@retailhub.com',   'Dave Kumar',      'active',   '{"company": "Retail Hub",   "phone": "+1-555-0104"}'),
    ('a0000000-0000-0000-0000-000000000001', 'eve@cloudbase.io',     'Eve Johnson',     'active',   '{"company": "Cloud Base",   "phone": "+1-555-0105"}'),
    ('a0000000-0000-0000-0000-000000000001', 'frank@mediapro.com',   'Frank Lee',       'active',   '{"company": "Media Pro",    "phone": "+1-555-0106"}'),
    ('a0000000-0000-0000-0000-000000000001', 'grace@fintech.io',     'Grace Park',      'active',   '{"company": "FinTech IO",   "phone": "+1-555-0107"}'),
    ('a0000000-0000-0000-0000-000000000001', 'henry@logisticx.com',  'Henry Brown',     'active',   '{"company": "LogistiX",     "phone": "+1-555-0108"}'),
    ('a0000000-0000-0000-0000-000000000001', 'iris@healthplus.io',   'Iris Wang',       'inactive', '{"company": "Health Plus",  "phone": "+1-555-0109"}'),
    ('a0000000-0000-0000-0000-000000000001', 'jack@edusaas.com',     'Jack Taylor',     'blocked',  '{"company": "EduSaaS",      "phone": "+1-555-0110"}'),
    -- Globex Inc
    -- alice@startup.io also exists in Acme — same email, different tenant_id: UNIQUE(tenant_id,email) allows it
    ('a0000000-0000-0000-0000-000000000002', 'alice@startup.io',     'Alice at Globex', 'active',   '{"company": "Startup IO",   "region": "us-west"}'),
    ('a0000000-0000-0000-0000-000000000002', 'kate@nexustech.com',   'Kate Wilson',     'active',   '{"company": "Nexus Tech",   "region": "us-east"}'),
    ('a0000000-0000-0000-0000-000000000002', 'liam@alphasoft.io',    'Liam Davis',      'active',   '{"company": "Alpha Soft",   "region": "us-west"}'),
    ('a0000000-0000-0000-0000-000000000002', 'mia@betaworks.com',    'Mia Garcia',      'active',   '{"company": "Beta Works",   "region": "eu-west"}'),
    ('a0000000-0000-0000-0000-000000000002', 'noah@gammasys.io',     'Noah Martinez',   'active',   '{"company": "Gamma Sys",    "region": "us-east"}'),
    ('a0000000-0000-0000-0000-000000000002', 'olivia@deltaops.com',  'Olivia Anderson', 'active',   '{"company": "Delta Ops",    "region": "ap-south"}'),
    ('a0000000-0000-0000-0000-000000000002', 'peter@epsilonai.io',   'Peter Thompson',  'active',   '{"company": "Epsilon AI",   "region": "us-west"}'),
    ('a0000000-0000-0000-0000-000000000002', 'quinn@zetacloud.com',  'Quinn Harris',    'active',   '{"company": "Zeta Cloud",   "region": "eu-central"}'),
    ('a0000000-0000-0000-0000-000000000002', 'rachel@etaplatform.io','Rachel White',    'active',   '{"company": "Eta Platform", "region": "us-east"}'),
    ('a0000000-0000-0000-0000-000000000002', 'sam@thetadev.com',     'Sam Lewis',       'inactive', '{"company": "Theta Dev",    "region": "ap-east"}');
