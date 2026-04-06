-- Migration 001: tenants + tenant_users
-- Creates the root entity and the updated_at trigger function used by all tables.
-- ============================================================

-- @UP

-- Reusable trigger function — attached to every table with updated_at.
-- Defined here (migration 001) because it must exist before any trigger uses it.
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = NOW();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TABLE tenants (
    id         UUID         NOT NULL DEFAULT gen_random_uuid(),
    name       VARCHAR(255) NOT NULL,
    slug       VARCHAR(100) NOT NULL,
    email      VARCHAR(255) NOT NULL,
    status     VARCHAR(20)  NOT NULL DEFAULT 'active'
               CHECK (status IN ('active', 'suspended', 'cancelled')),
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT tenants_pkey        PRIMARY KEY (id),
    CONSTRAINT tenants_slug_key    UNIQUE (slug),
    CONSTRAINT tenants_email_key   UNIQUE (email)
);

CREATE TRIGGER trg_tenants_updated_at
    BEFORE UPDATE ON tenants
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- tenant_users: people who log into the dashboard.
-- Email is unique per-tenant, not globally — two tenants can have staff with the same email.
CREATE TABLE tenant_users (
    id            UUID         NOT NULL DEFAULT gen_random_uuid(),
    tenant_id     UUID         NOT NULL,
    email         VARCHAR(255) NOT NULL,
    password_hash TEXT         NOT NULL,
    name          VARCHAR(255) NOT NULL,
    role          VARCHAR(20)  NOT NULL DEFAULT 'member'
                  CHECK (role IN ('owner', 'member')),
    created_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at    TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT tenant_users_pkey             PRIMARY KEY (id),
    CONSTRAINT tenant_users_tenant_fkey      FOREIGN KEY (tenant_id)
                                             REFERENCES tenants(id) ON DELETE CASCADE,
    CONSTRAINT tenant_users_tenant_email_key UNIQUE (tenant_id, email)
);

CREATE TRIGGER trg_tenant_users_updated_at
    BEFORE UPDATE ON tenant_users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- tenant_id index: every query against tenant_users filters by tenant_id first.
CREATE INDEX idx_tenant_users_tenant_id ON tenant_users(tenant_id);


-- @DOWN

DROP TRIGGER IF EXISTS trg_tenant_users_updated_at ON tenant_users;
DROP TRIGGER IF EXISTS trg_tenants_updated_at       ON tenants;
DROP INDEX   IF EXISTS idx_tenant_users_tenant_id;
DROP TABLE   IF EXISTS tenant_users;
DROP TABLE   IF EXISTS tenants;
DROP FUNCTION IF EXISTS set_updated_at();
