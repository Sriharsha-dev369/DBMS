-- Migration 005: Row Level Security
-- Enforces tenant isolation at the database layer — independent of application code.
-- Every query from the app role automatically filters by the current tenant context.
--
-- How it works:
--   1. App middleware calls: SET app.current_tenant_id = '<uuid>'  (per connection)
--   2. RLS policies read that setting and filter rows automatically
--   3. App role (saasledger_app) is NOT superuser — RLS applies
--   4. postgres superuser bypasses RLS — safe for migrations and admin operations
-- ============================================================

-- @UP

-- ── Helper function ───────────────────────────────────────────
-- Safely extracts the tenant UUID from the session config.
-- Returns NULL (no rows visible) if the setting is absent or malformed.
-- Defined as SECURITY DEFINER so policies can call it without EXECUTE grants.
CREATE OR REPLACE FUNCTION current_tenant_id()
RETURNS UUID AS $$
BEGIN
    RETURN NULLIF(current_setting('app.current_tenant_id', true), '')::UUID;
EXCEPTION WHEN OTHERS THEN
    RETURN NULL;
END;
$$ LANGUAGE plpgsql STABLE SECURITY DEFINER;

-- ── App database role ─────────────────────────────────────────
-- The Node.js connection pool uses this role, not postgres.
-- Because it is NOT superuser, RLS policies are enforced on every query.
DO $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'saasledger_app') THEN
        CREATE ROLE saasledger_app LOGIN PASSWORD 'app_dev_password';
    END IF;
END$$;

GRANT CONNECT ON DATABASE saasledger TO saasledger_app;
GRANT USAGE   ON SCHEMA public        TO saasledger_app;
GRANT SELECT, INSERT, UPDATE, DELETE  ON ALL TABLES    IN SCHEMA public TO saasledger_app;
GRANT USAGE, SELECT                   ON ALL SEQUENCES IN SCHEMA public TO saasledger_app;
GRANT EXECUTE ON FUNCTION current_tenant_id() TO saasledger_app;

-- ── Enable RLS ────────────────────────────────────────────────
ALTER TABLE tenants       ENABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_users  ENABLE ROW LEVEL SECURITY;
ALTER TABLE plans         ENABLE ROW LEVEL SECURITY;
ALTER TABLE plan_features ENABLE ROW LEVEL SECURITY;
ALTER TABLE customers     ENABLE ROW LEVEL SECURITY;

-- ── Policies ──────────────────────────────────────────────────
-- tenants: a tenant can only read their own row.
-- No tenant should be able to enumerate other tenants on the platform.
CREATE POLICY owner_isolation ON tenants
    FOR ALL
    USING     (id = current_tenant_id())
    WITH CHECK (id = current_tenant_id());

-- tenant_users: users only see their own tenant's staff.
CREATE POLICY tenant_isolation ON tenant_users
    FOR ALL
    USING     (tenant_id = current_tenant_id())
    WITH CHECK (tenant_id = current_tenant_id());

-- plans: tenants only see plans they defined.
CREATE POLICY tenant_isolation ON plans
    FOR ALL
    USING     (tenant_id = current_tenant_id())
    WITH CHECK (tenant_id = current_tenant_id());

-- plan_features: scoped to plan owner's tenant.
CREATE POLICY tenant_isolation ON plan_features
    FOR ALL
    USING     (tenant_id = current_tenant_id())
    WITH CHECK (tenant_id = current_tenant_id());

-- customers: the most critical isolation — no cross-tenant customer data leakage.
CREATE POLICY tenant_isolation ON customers
    FOR ALL
    USING     (tenant_id = current_tenant_id())
    WITH CHECK (tenant_id = current_tenant_id());


-- @DOWN

DROP POLICY IF EXISTS tenant_isolation  ON customers;
DROP POLICY IF EXISTS tenant_isolation  ON plan_features;
DROP POLICY IF EXISTS tenant_isolation  ON plans;
DROP POLICY IF EXISTS tenant_isolation  ON tenant_users;
DROP POLICY IF EXISTS owner_isolation   ON tenants;

ALTER TABLE customers     DISABLE ROW LEVEL SECURITY;
ALTER TABLE plan_features DISABLE ROW LEVEL SECURITY;
ALTER TABLE plans         DISABLE ROW LEVEL SECURITY;
ALTER TABLE tenant_users  DISABLE ROW LEVEL SECURITY;
ALTER TABLE tenants       DISABLE ROW LEVEL SECURITY;

REVOKE EXECUTE ON FUNCTION current_tenant_id() FROM saasledger_app;
REVOKE ALL     ON ALL TABLES    IN SCHEMA public FROM saasledger_app;
REVOKE ALL     ON ALL SEQUENCES IN SCHEMA public FROM saasledger_app;
REVOKE USAGE   ON SCHEMA public                  FROM saasledger_app;
REVOKE CONNECT ON DATABASE saasledger            FROM saasledger_app;

DROP ROLE IF EXISTS saasledger_app;
DROP FUNCTION IF EXISTS current_tenant_id();
