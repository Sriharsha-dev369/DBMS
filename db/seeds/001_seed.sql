-- Seed 001: Phase 1 baseline data
-- Fixed UUIDs so tests and demos can hardcode references.
-- Safe to re-run — deletes then re-inserts in dependency order.
-- ============================================================
-- Tenant A: a0000000-0000-0000-0000-000000000001  (acme-corp)
-- Tenant B: a0000000-0000-0000-0000-000000000002  (globex-inc)
-- ============================================================

-- ── Teardown (reverse FK order) ───────────────────────────────
DELETE FROM customers     WHERE tenant_id IN (
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000002'
);
DELETE FROM plan_features WHERE tenant_id IN (
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000002'
);
DELETE FROM plans         WHERE tenant_id IN (
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000002'
);
DELETE FROM tenant_users  WHERE tenant_id IN (
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000002'
);
DELETE FROM tenants WHERE id IN (
    'a0000000-0000-0000-0000-000000000001',
    'a0000000-0000-0000-0000-000000000002'
);

-- ── Tenants ───────────────────────────────────────────────────
INSERT INTO tenants (id, name, slug, email, status) VALUES
    ('a0000000-0000-0000-0000-000000000001', 'Acme Corp',  'acme-corp',  'billing@acme.com',   'active'),
    ('a0000000-0000-0000-0000-000000000002', 'Globex Inc', 'globex-inc', 'billing@globex.com', 'active');

-- ── Tenant Users ──────────────────────────────────────────────
-- Passwords are placeholder hashes — real bcrypt hashes added when auth is built.
INSERT INTO tenant_users (id, tenant_id, email, password_hash, name, role) VALUES
    ('u0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'owner@acme.com',   '$2b$10$acme_owner_placeholder_hash_here', 'Alice (Acme)',  'owner'),
    ('u0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'member@acme.com',  '$2b$10$acme_member_placeholder_hash___', 'Bob (Acme)',    'member'),
    ('u0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000002', 'owner@globex.com', '$2b$10$globex_owner_placeholder_hash_', 'Carol (Globex)', 'owner');

-- ── Plans ─────────────────────────────────────────────────────
INSERT INTO plans (id, tenant_id, name, billing_model, base_price, per_seat_price, billing_period, trial_days, is_active) VALUES
    -- Acme Corp plans (4)
    ('p0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'Starter',    'flat_rate', 29.00,  NULL,  'monthly', 14, TRUE),
    ('p0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'Pro',        'per_seat',  49.00,  9.00,  'monthly',  7, TRUE),
    ('p0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'Enterprise', 'per_seat',  199.00, 15.00, 'annual',   0, TRUE),
    ('p0000000-0000-0000-0000-000000000004', 'a0000000-0000-0000-0000-000000000001', 'Legacy',     'flat_rate', 19.00,  NULL,  'monthly',  0, FALSE),
    -- Globex Inc plans (3)
    ('p0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000002', 'Basic',      'flat_rate', 19.00,  NULL,  'monthly', 30, TRUE),
    ('p0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000002', 'Growth',     'per_seat',  39.00,  7.00,  'monthly',  7, TRUE),
    ('p0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000002', 'Scale',      'per_seat',  149.00, 12.00, 'annual',   0, TRUE);

-- ── Plan Features ─────────────────────────────────────────────
INSERT INTO plan_features (plan_id, tenant_id, feature_key, feature_value) VALUES
    ('p0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'max_customers', '100'),
    ('p0000000-0000-0000-0000-000000000001', 'a0000000-0000-0000-0000-000000000001', 'api_access',    'false'),
    ('p0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'max_customers', '1000'),
    ('p0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'api_access',    'true'),
    ('p0000000-0000-0000-0000-000000000002', 'a0000000-0000-0000-0000-000000000001', 'sso',           'false'),
    ('p0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'max_customers', 'unlimited'),
    ('p0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'api_access',    'true'),
    ('p0000000-0000-0000-0000-000000000003', 'a0000000-0000-0000-0000-000000000001', 'sso',           'true'),
    ('p0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000002', 'max_customers', '50'),
    ('p0000000-0000-0000-0000-000000000005', 'a0000000-0000-0000-0000-000000000002', 'api_access',    'false'),
    ('p0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000002', 'max_customers', '500'),
    ('p0000000-0000-0000-0000-000000000006', 'a0000000-0000-0000-0000-000000000002', 'api_access',    'true'),
    ('p0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000002', 'max_customers', 'unlimited'),
    ('p0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000002', 'api_access',    'true'),
    ('p0000000-0000-0000-0000-000000000007', 'a0000000-0000-0000-0000-000000000002', 'sso',           'true');

-- ── Customers: 10 per tenant ──────────────────────────────────
INSERT INTO customers (tenant_id, email, name, status, metadata) VALUES
    -- Acme Corp customers
    ('a0000000-0000-0000-0000-000000000001', 'alice@startup.io',     'Alice Martin',   'active',   '{"company": "Startup IO",    "phone": "+1-555-0101"}'),
    ('a0000000-0000-0000-0000-000000000001', 'bob@techcorp.com',     'Bob Chen',       'active',   '{"company": "Tech Corp",     "phone": "+1-555-0102"}'),
    ('a0000000-0000-0000-0000-000000000001', 'carol@designco.io',    'Carol Smith',    'active',   '{"company": "Design Co",     "phone": "+1-555-0103"}'),
    ('a0000000-0000-0000-0000-000000000001', 'dave@retailhub.com',   'Dave Kumar',     'active',   '{"company": "Retail Hub",    "phone": "+1-555-0104"}'),
    ('a0000000-0000-0000-0000-000000000001', 'eve@cloudbase.io',     'Eve Johnson',    'active',   '{"company": "Cloud Base",    "phone": "+1-555-0105"}'),
    ('a0000000-0000-0000-0000-000000000001', 'frank@mediapro.com',   'Frank Lee',      'active',   '{"company": "Media Pro",     "phone": "+1-555-0106"}'),
    ('a0000000-0000-0000-0000-000000000001', 'grace@fintech.io',     'Grace Park',     'inactive', '{"company": "FinTech IO",    "phone": "+1-555-0107"}'),
    ('a0000000-0000-0000-0000-000000000001', 'henry@logisticx.com',  'Henry Brown',    'active',   '{"company": "LogistiX",      "phone": "+1-555-0108"}'),
    ('a0000000-0000-0000-0000-000000000001', 'iris@healthplus.io',   'Iris Wang',      'active',   '{"company": "Health Plus",   "phone": "+1-555-0109"}'),
    ('a0000000-0000-0000-0000-000000000001', 'jack@edusaas.com',     'Jack Taylor',    'blocked',  '{"company": "EduSaaS",       "phone": "+1-555-0110"}'),
    -- Globex Inc customers
    ('a0000000-0000-0000-0000-000000000002', 'kate@nexustech.com',   'Kate Wilson',    'active',   '{"company": "Nexus Tech",    "region": "us-east"}'),
    ('a0000000-0000-0000-0000-000000000002', 'liam@alphasoft.io',    'Liam Davis',     'active',   '{"company": "Alpha Soft",    "region": "us-west"}'),
    ('a0000000-0000-0000-0000-000000000002', 'mia@betaworks.com',    'Mia Garcia',     'active',   '{"company": "Beta Works",    "region": "eu-west"}'),
    ('a0000000-0000-0000-0000-000000000002', 'noah@gammasys.io',     'Noah Martinez',  'active',   '{"company": "Gamma Sys",     "region": "us-east"}'),
    ('a0000000-0000-0000-0000-000000000002', 'olivia@deltaops.com',  'Olivia Anderson','inactive', '{"company": "Delta Ops",     "region": "ap-south"}'),
    ('a0000000-0000-0000-0000-000000000002', 'peter@epsilonai.io',   'Peter Thompson', 'active',   '{"company": "Epsilon AI",    "region": "us-west"}'),
    ('a0000000-0000-0000-0000-000000000002', 'quinn@zetacloud.com',  'Quinn Harris',   'active',   '{"company": "Zeta Cloud",    "region": "eu-central"}'),
    ('a0000000-0000-0000-0000-000000000002', 'rachel@etaplatform.io','Rachel White',   'active',   '{"company": "Eta Platform",  "region": "us-east"}'),
    ('a0000000-0000-0000-0000-000000000002', 'sam@thetadev.com',     'Sam Lewis',      'active',   '{"company": "Theta Dev",     "region": "ap-east"}'),
    ('a0000000-0000-0000-0000-000000000002', 'tina@iotahub.io',      'Tina Robinson',  'blocked',  '{"company": "Iota Hub",      "region": "us-east"}');
