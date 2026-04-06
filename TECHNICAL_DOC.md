# Technical Documentation — Multi-Tenant SaaS Subscription Billing Engine

> **Living Document** — Updated as schema evolves. Always reflects current state.
> Last updated: 2026-04-02 | Phase: Pre-implementation (Planning)

---

## 1. Project Overview

A production-grade subscription billing backend for a B2B SaaS platform. Businesses (tenants) use this platform to manage their customers' subscriptions, generate invoices, and record payments. The system emphasizes database correctness, financial integrity, and strict tenant data isolation.

**This is not a simple CRUD app.** Every feature is designed to exercise a DBMS concept.

---

## 2. Problem Statement

SaaS billing engines must:
- Serve multiple isolated tenants on shared infrastructure
- Maintain financial correctness under concurrent writes (two billing jobs running simultaneously cannot double-invoice)
- Preserve a complete, tamper-evident audit trail
- Handle subscription state machines (active → past_due → cancelled)
- Calculate prorations when plans change mid-cycle
- Retry failed payments through a dunning workflow

---

## 3. Feature Scope

### 3.1 Core Features (v1 — Must Have)

| Feature | DBMS Concept Exercised |
|---|---|
| Tenant onboarding + isolation | RLS policies, `tenant_id` partitioning |
| Plan catalog (flat-rate + per-seat) | CHECK constraints, normalized pricing table |
| Customer management | FK constraints, unique email per-tenant |
| Subscription lifecycle (create, upgrade, downgrade, cancel, pause) | State machine via CHECK constraint, ACID transaction |
| Automated invoice generation | Stored procedure, serializable transaction, idempotency key |
| Manual invoice line items | Normalized line_items table, SUM aggregation |
| Payment recording | FK, balance tracking, trigger-based status update |
| Dunning state management | Enum constraint, scheduled retry logic |
| Proration calculation | PL/pgSQL function, date arithmetic |
| Audit log | INSERT trigger on all business tables |

### 3.2 Reporting Features (v1)

| Report | DBMS Concept |
|---|---|
| MRR (Monthly Recurring Revenue) per tenant | Materialized view, aggregate |
| Invoice aging report | Date diff query, GROUP BY |
| Subscription churn report | LEFT JOIN, status filter |
| Revenue by plan | GROUP BY with ROLLUP |
| Payment success rate | Conditional aggregation |

### 3.3 Advanced Features (v2 — If Time Permits)

- Usage-based billing (metered events table)
- Tax calculation per region
- Multi-currency support
- Webhook event log for payment processor integration
- Customer portal (self-service plan changes)

---

## 4. Technical Architecture

### 4.1 System Architecture

```
┌─────────────────────────────────────────────────────┐
│                    React Frontend                    │
│           (Tenant Dashboard + Admin Panel)           │
└─────────────────────┬───────────────────────────────┘
                      │ REST API (JSON)
┌─────────────────────▼───────────────────────────────┐
│              Express + TypeScript Backend            │
│  ┌──────────┐ ┌───────────┐ ┌────────────────────┐  │
│  │  Routes  │ │ Services  │ │  Billing Job (Cron) │  │
│  └──────────┘ └───────────┘ └────────────────────┘  │
│         Tenant Middleware (sets RLS context)         │
└─────────────────────┬───────────────────────────────┘
                      │ pg (raw SQL)
┌─────────────────────▼───────────────────────────────┐
│                   PostgreSQL                         │
│  ┌─────────┐ ┌──────────┐ ┌────────┐ ┌──────────┐  │
│  │  Tables │ │ Triggers │ │  RLS   │ │  Views   │  │
│  └─────────┘ └──────────┘ └────────┘ └──────────┘  │
└─────────────────────────────────────────────────────┘
```

### 4.2 Multi-Tenancy Design

**Strategy:** Shared schema with `tenant_id` UUID column on all business tables.

**Isolation enforcement:**
- Application layer: JWT carries `tenant_id`, middleware sets `SET app.current_tenant_id = $1` on every connection
- Database layer: RLS policies enforce `tenant_id = current_setting('app.current_tenant_id')::uuid`
- Belt-and-suspenders: Both layers must pass for data access

**Why not schema-per-tenant:** Operational complexity outweighs benefits for this scope. Shared schema lets us demonstrate indexing and RLS in depth.

---

## 5. Database Schema

> **Status: Finalized v1** — Migrations complete. Updated 2026-04-06.

### 5.1 Entity Relationship Overview

```
tenants
  └── tenant_users (owner / member — dashboard login)
  └── plans (each tenant defines their own plans for their customers)
  └── customers
        └── subscriptions → plans
        └── invoices
              └── invoice_line_items
        └── payments → invoices
  └── audit_log (all tables feed here via triggers)
```

### 5.2 Core Tables (Draft)

#### `tenants`
```sql
CREATE TABLE tenants (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    name            VARCHAR(255) NOT NULL,
    slug            VARCHAR(100) NOT NULL UNIQUE,  -- subdomain identifier
    email           VARCHAR(255) NOT NULL UNIQUE,  -- billing contact / owner email
    status          VARCHAR(20) NOT NULL DEFAULT 'active'
                    CHECK (status IN ('active', 'suspended', 'cancelled')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

#### `tenant_users`
```sql
CREATE TABLE tenant_users (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    email           VARCHAR(255) NOT NULL,
    password_hash   TEXT NOT NULL,
    name            VARCHAR(255) NOT NULL,
    role            VARCHAR(20) NOT NULL DEFAULT 'member'
                    CHECK (role IN ('owner', 'member')),
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, email)  -- email unique within tenant, not globally
);
-- owner: full access (manage plans, billing, users)
-- member: read-only access to customers and invoices
```

#### `plans`
```sql
CREATE TABLE plans (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    name            VARCHAR(100) NOT NULL,
    billing_model   VARCHAR(20) NOT NULL
                    CHECK (billing_model IN ('flat_rate', 'per_seat', 'usage_based')),
    base_price      NUMERIC(12,2) NOT NULL CHECK (base_price >= 0),
    per_seat_price  NUMERIC(12,2) CHECK (per_seat_price >= 0),
    billing_period  VARCHAR(10) NOT NULL DEFAULT 'monthly'
                    CHECK (billing_period IN ('monthly', 'annual')),
    trial_days      INTEGER NOT NULL DEFAULT 0 CHECK (trial_days >= 0),
    is_active       BOOLEAN NOT NULL DEFAULT true,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Constraint: per_seat_price required when model is per_seat
    CONSTRAINT per_seat_price_required
        CHECK (billing_model != 'per_seat' OR per_seat_price IS NOT NULL)
);
```

#### `customers`
```sql
CREATE TABLE customers (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    email           VARCHAR(255) NOT NULL,
    name            VARCHAR(255) NOT NULL,
    metadata        JSONB,  -- flexible extra fields per tenant
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    -- Email must be unique within a tenant (not globally)
    UNIQUE (tenant_id, email)
);
```

#### `subscriptions`
```sql
CREATE TABLE subscriptions (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    customer_id     UUID NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
    plan_id         UUID NOT NULL REFERENCES plans(id) ON DELETE RESTRICT,
    status          VARCHAR(20) NOT NULL DEFAULT 'trialing'
                    CHECK (status IN ('trialing', 'active', 'past_due',
                                      'paused', 'cancelled', 'expired')),
    seat_count      INTEGER CHECK (seat_count > 0),
    current_period_start TIMESTAMPTZ NOT NULL,
    current_period_end   TIMESTAMPTZ NOT NULL,
    trial_end       TIMESTAMPTZ,
    cancelled_at    TIMESTAMPTZ,
    cancel_at_period_end BOOLEAN NOT NULL DEFAULT false,
    idempotency_key UUID UNIQUE DEFAULT gen_random_uuid(),  -- prevents double billing
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    CONSTRAINT period_order CHECK (current_period_end > current_period_start)
);
-- Enforced via partial unique index (not table constraint) — see indexes section:
-- CREATE UNIQUE INDEX idx_one_active_sub ON subscriptions(tenant_id, customer_id)
-- WHERE status NOT IN ('cancelled', 'expired');
```

#### `invoices`
```sql
CREATE TABLE invoices (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    customer_id     UUID NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
    subscription_id UUID REFERENCES subscriptions(id) ON DELETE SET NULL,
    invoice_number  VARCHAR(50) NOT NULL,
    status          VARCHAR(20) NOT NULL DEFAULT 'draft'
                    CHECK (status IN ('draft', 'open', 'paid', 'void', 'uncollectible')),
    subtotal        NUMERIC(12,2) NOT NULL DEFAULT 0,
    tax_amount      NUMERIC(12,2) NOT NULL DEFAULT 0,
    total           NUMERIC(12,2) NOT NULL DEFAULT 0,
    amount_due      NUMERIC(12,2) NOT NULL DEFAULT 0,
    amount_paid     NUMERIC(12,2) NOT NULL DEFAULT 0,
    currency        CHAR(3) NOT NULL DEFAULT 'USD',
    due_date        DATE,
    period_start    TIMESTAMPTZ,
    period_end      TIMESTAMPTZ,
    idempotency_key UUID NOT NULL UNIQUE,  -- prevents duplicate invoice generation
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    UNIQUE (tenant_id, invoice_number),
    CONSTRAINT amounts_non_negative CHECK (
        subtotal >= 0 AND tax_amount >= 0 AND total >= 0
        AND amount_due >= 0 AND amount_paid >= 0
    ),
    CONSTRAINT amount_paid_le_total CHECK (amount_paid <= total)
);
```

#### `invoice_line_items`
```sql
CREATE TABLE invoice_line_items (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    invoice_id      UUID NOT NULL REFERENCES invoices(id) ON DELETE CASCADE,
    description     TEXT NOT NULL,
    quantity        NUMERIC(10,4) NOT NULL DEFAULT 1 CHECK (quantity > 0),
    unit_price      NUMERIC(12,2) NOT NULL,
    amount          NUMERIC(12,2) NOT NULL,
    type            VARCHAR(30) NOT NULL DEFAULT 'subscription'
                    CHECK (type IN ('subscription', 'proration', 'addon', 'credit', 'tax')),
    period_start    TIMESTAMPTZ,
    period_end      TIMESTAMPTZ,
    CONSTRAINT amount_matches CHECK (amount = ROUND(quantity * unit_price, 2))
);
```

#### `payments`
```sql
CREATE TABLE payments (
    id              UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    tenant_id       UUID NOT NULL REFERENCES tenants(id) ON DELETE CASCADE,
    customer_id     UUID NOT NULL REFERENCES customers(id) ON DELETE RESTRICT,
    invoice_id      UUID NOT NULL REFERENCES invoices(id) ON DELETE RESTRICT,
    amount          NUMERIC(12,2) NOT NULL CHECK (amount > 0),
    currency        CHAR(3) NOT NULL DEFAULT 'USD',
    status          VARCHAR(20) NOT NULL DEFAULT 'pending'
                    CHECK (status IN ('pending', 'succeeded', 'failed', 'refunded')),
    payment_method  VARCHAR(50),
    processor_ref   VARCHAR(255),  -- external payment processor transaction ID
    failure_reason  TEXT,
    processed_at    TIMESTAMPTZ,
    created_at      TIMESTAMPTZ NOT NULL DEFAULT NOW(),
    updated_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
```

#### `audit_log`
```sql
CREATE TABLE audit_log (
    id              BIGSERIAL PRIMARY KEY,  -- SERIAL ok here, high volume, internal only
    tenant_id       UUID,
    table_name      VARCHAR(100) NOT NULL,
    record_id       UUID NOT NULL,
    operation       CHAR(1) NOT NULL CHECK (operation IN ('I', 'U', 'D')),
    old_data        JSONB,
    new_data        JSONB,
    changed_by      UUID,  -- user/system that made the change
    changed_at      TIMESTAMPTZ NOT NULL DEFAULT NOW()
);
-- RLS enabled: tenants see only their own audit records.
-- System-level operations (no tenant context) use a superuser role that bypasses RLS.
ALTER TABLE audit_log ENABLE ROW LEVEL SECURITY;
CREATE POLICY audit_log_tenant_isolation ON audit_log
    USING (tenant_id = current_setting('app.current_tenant_id', true)::uuid
           OR current_setting('app.current_tenant_id', true) IS NULL);
```

### 5.3 Planned Indexes (Draft)

```sql
-- Tenant isolation (most critical — every query filters by tenant_id)
CREATE INDEX idx_tenant_users_tenant    ON tenant_users(tenant_id);
CREATE INDEX idx_customers_tenant       ON customers(tenant_id);
CREATE INDEX idx_subscriptions_tenant   ON subscriptions(tenant_id);
CREATE INDEX idx_invoices_tenant        ON invoices(tenant_id);
CREATE INDEX idx_payments_tenant        ON payments(tenant_id);

-- Partial unique index: a customer may have only one non-terminal subscription
-- Replaces a table-level UNIQUE constraint (which would be logically wrong)
CREATE UNIQUE INDEX idx_one_active_sub_per_customer
    ON subscriptions(tenant_id, customer_id)
    WHERE status NOT IN ('cancelled', 'expired');

-- Partial index: active subscriptions only — billing job scans this constantly
CREATE INDEX idx_active_subscriptions_due
    ON subscriptions(tenant_id, current_period_end)
    WHERE status = 'active';

-- Covering index: invoice list queries never need to hit the table
CREATE INDEX idx_invoices_customer_status
    ON invoices(tenant_id, customer_id, status)
    INCLUDE (total, amount_due, due_date);

-- Audit log lookups
CREATE INDEX idx_audit_log_table_record ON audit_log(table_name, record_id);
CREATE INDEX idx_audit_log_tenant_time  ON audit_log(tenant_id, changed_at DESC);
```

---

## 6. DBMS Concepts Demonstrated

| Concept | Where Implemented | Depth |
|---|---|---|
| Normalization (3NF) | All tables | Schema design, documented |
| PK / FK Constraints | All relationships | Various ON DELETE behaviors |
| CHECK Constraints | status enums, amount validations, business rules | 10+ constraints |
| UNIQUE Constraints | email per tenant, idempotency keys, invoice numbers | Partial + composite |
| Indexes | All tenant_id columns, partial on active subs | B-tree, partial, covering |
| ACID Transactions | Invoice generation, payment posting | Explicit isolation levels |
| Isolation Levels | Billing job (SERIALIZABLE), reads (READ COMMITTED) | Demonstrated + compared |
| Row Level Security | All business tables | Per-tenant policies |
| Triggers | Audit log, updated_at maintenance, invoice total sync | BEFORE + AFTER triggers |
| Stored Procedures | Invoice generation, proration calc, dunning advance | PL/pgSQL |
| Views | Customer subscription summary | Simple view |
| Materialized Views | MRR report, revenue analytics | With REFRESH strategy |
| EXPLAIN ANALYZE | Index justification | Documented query plans |

---

## 7. API Endpoints (Draft)

### Auth ✓
- `POST /api/auth/register` — tenant signup ✓
- `POST /api/auth/login` — tenant login → JWT ✓
- `POST /api/auth/logout`

### Tenant
- `GET  /api/tenant/me` — current tenant profile
- `PUT  /api/tenant/me` — update settings

### Plans ✓
- `GET    /api/plans` — list plans (query: `?is_active=true|false`) ✓
- `POST   /api/plans` — create plan ✓
- `PATCH  /api/plans/:id` — update plan (soft-mutable fields only, billing_model locked) ✓
- `DELETE /api/plans/:id` — deactivate plan (soft delete: is_active=false) ✓

### Customers ✓
- `GET    /api/customers` — list paginated (query: `?limit&offset&status`) ✓
- `POST   /api/customers` — create ✓
- `GET    /api/customers/:id` — detail + current subscription
- `PATCH  /api/customers/:id` — update ✓
- `DELETE /api/customers/:id` — soft delete (status=inactive) ✓

### Subscriptions
- `POST /api/subscriptions` — create (assigns plan to customer)
- `GET  /api/subscriptions/:id` — detail
- `POST /api/subscriptions/:id/upgrade` — plan change
- `POST /api/subscriptions/:id/cancel` — cancel (immediate or at period end)
- `POST /api/subscriptions/:id/pause` — pause
- `POST /api/subscriptions/:id/resume` — resume

### Invoices
- `GET  /api/invoices` — list (filterable by status, date)
- `GET  /api/invoices/:id` — detail with line items
- `POST /api/invoices/:id/void` — void invoice
- `POST /api/invoices/generate` — manual trigger (also runs on cron)

### Payments
- `GET  /api/payments` — list
- `POST /api/payments` — record payment
- `GET  /api/payments/:id` — detail

### Reports
- `GET  /api/reports/mrr` — monthly recurring revenue
- `GET  /api/reports/churn` — subscription churn
- `GET  /api/reports/aging` — invoice aging
- `GET  /api/reports/revenue` — revenue by plan

---

## 8. Key Technical Decisions & Rationale

| Decision | Rationale |
|---|---|
| Raw SQL over ORM | Forces understanding of indexes, transactions, isolation levels |
| UUID PKs everywhere | Avoids sequential ID enumeration attacks; multi-tenant safe |
| `NUMERIC(12,2)` for money | Never use FLOAT for currency — rounding errors accumulate |
| Idempotency keys on invoices | Billing job can safely retry without double-invoicing |
| RLS + app-layer both | Defense in depth — one layer failing doesn't expose data |
| `TIMESTAMPTZ` not `TIMESTAMP` | Timezone-aware; billing crosses timezones |
| Triggers for audit log | Audit cannot be bypassed by application code |
| SERIALIZABLE for billing job | Prevents phantom reads during concurrent invoice generation |

---

## 9. Open Questions / To Be Decided

- [ ] Tax calculation: flat percentage vs region-based? (default: skip tax for v1, `tax_amount = 0`)
- [ ] Invoice numbering format: `INV-{year}-{seq}` per tenant? (e.g. `INV-2026-0001`)
- [ ] Dunning retry schedule: day 3, day 7, day 14 → uncollectible after 3 failures?
- [ ] Frontend: single dashboard for all tenant management, or separate admin panel?
- [ ] Seed data strategy: realistic demo data for presentation?
