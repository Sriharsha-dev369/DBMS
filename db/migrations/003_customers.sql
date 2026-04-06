-- Migration 003: customers
-- End-users within a tenant's context. Not dashboard users — those are tenant_users.
-- ============================================================

-- @UP

CREATE TABLE customers (
    id         UUID         NOT NULL DEFAULT gen_random_uuid(),
    tenant_id  UUID         NOT NULL,
    email      VARCHAR(255) NOT NULL,
    name       VARCHAR(255) NOT NULL,
    status     VARCHAR(20)  NOT NULL DEFAULT 'active'
               CHECK (status IN ('active', 'inactive', 'blocked')),
    metadata   JSONB,
    created_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMPTZ  NOT NULL DEFAULT NOW(),
    CONSTRAINT customers_pkey             PRIMARY KEY (id),
    CONSTRAINT customers_tenant_fkey      FOREIGN KEY (tenant_id)
                                          REFERENCES tenants(id) ON DELETE CASCADE,
    -- Same email can exist across tenants. Within one tenant it must be unique.
    -- Composite UNIQUE enforces this without a global constraint.
    CONSTRAINT customers_tenant_email_key UNIQUE (tenant_id, email)
);

CREATE TRIGGER trg_customers_updated_at
    BEFORE UPDATE ON customers
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();

-- Tenant scoping index — present on every table that has tenant_id.
CREATE INDEX idx_customers_tenant_id ON customers(tenant_id);

-- Partial index on active customers only.
-- Inactive/blocked customers are rarely queried — excluding them keeps this index tight.
CREATE INDEX idx_customers_tenant_active
    ON customers(tenant_id)
    WHERE status = 'active';

-- GIN index on metadata JSONB.
-- Enables fast key/value lookups inside the metadata blob (e.g. metadata->>'company').
-- Only indexed when metadata is present — avoids indexing nulls.
CREATE INDEX idx_customers_metadata
    ON customers USING GIN (metadata)
    WHERE metadata IS NOT NULL;


-- @DOWN

DROP INDEX   IF EXISTS idx_customers_metadata;
DROP INDEX   IF EXISTS idx_customers_tenant_active;
DROP INDEX   IF EXISTS idx_customers_tenant_id;
DROP TRIGGER IF EXISTS trg_customers_updated_at ON customers;
DROP TABLE   IF EXISTS customers;
