# Project Plan — Multi-Tenant SaaS Billing Engine

> Iterative foundation. We plan as we go — this doc tracks direction, not a rigid schedule.
> Updated at the start of each phase.

---

## Guiding Principles

- **Ship working database schema first.** Frontend can wait. DBMS concepts are the core.
- **Every feature needs a DBMS concept.** If you're writing a feature without exercising a constraint, index, or transaction — ask why.
- **Vertical slices over horizontal layers.** One complete flow (tenant → customer → subscription → invoice) is better than all tables with no logic.
- **Demo-ready at all times.** Each phase should produce something runnable and showable.

---

## Current Status

**Active Phase:** 0 — Environment Setup
**Last Updated:** 2026-04-02

---

## Phase 0 — Environment Setup

**Goal:** Working local development environment. Nothing blocking. Can run migrations.

### Tasks
- [ ] Initialize backend: `npm init`, TypeScript config, Express setup
- [ ] Initialize frontend: `create-react-app` or Vite with TypeScript
- [ ] Set up PostgreSQL locally (Docker Compose preferred)
- [ ] Database connection + migration runner setup (raw SQL files, not ORM migrations)
- [ ] `.env` file structure (DB credentials, JWT secret)
- [ ] Basic folder structure matching `CLAUDE.md` convention
- [ ] Git repo initialized with `.gitignore`

### Deliverable
`docker-compose up` → Postgres running. `npm run migrate` → empty schema created. `npm run dev` → Express server responds on port 3000.

---

## Phase 1 — Core Schema & Tenant Foundation

**Goal:** Database schema for tenants, plans, customers. RLS working. Can seed test data.

### Tasks
- [ ] Migration 001: `tenants` table + indexes
- [ ] Migration 002: `plans` + `plan_features` tables
- [ ] Migration 003: `customers` table + indexes
- [ ] Migration 004: Enable RLS, write isolation policies on all tables
- [ ] Migration 005: `updated_at` trigger function (applied to all tables)
- [ ] Seed file: 2 tenants, 3-4 plans each, 10 customers each
- [ ] API: POST /auth/register, POST /auth/login (JWT)
- [ ] Middleware: extract tenant from JWT, set `app.current_tenant_id` in Postgres session
- [ ] API: CRUD for /plans, /customers
- [ ] Verify RLS works: login as Tenant A, cannot see Tenant B's customers

### DBMS Concepts Introduced
- 3NF schema design
- FK constraints with ON DELETE behaviors
- CHECK constraints (status enums, price validations)
- Composite UNIQUE constraint (email per tenant)
- B-tree indexes on tenant_id columns
- Row Level Security (first policies)
- BEFORE UPDATE trigger for `updated_at`

### Deliverable
API running. Two tenants fully isolated. Plans and customers manageable via Postman/API client. Data visible in pgAdmin with RLS clearly working.

---

## Phase 2 — Subscription Lifecycle

**Goal:** Customers can be subscribed to plans. Subscription state machine works correctly.

### Tasks
- [ ] Migration 006: `subscriptions` table with all constraints
- [ ] Migration 007: Partial unique index (one active sub per customer)
- [ ] Partial index: `WHERE status = 'active'` on subscriptions
- [ ] API: POST /subscriptions (create with trial period logic)
- [ ] API: POST /subscriptions/:id/cancel (immediate vs at_period_end)
- [ ] API: POST /subscriptions/:id/pause and /resume
- [ ] API: POST /subscriptions/:id/upgrade (plan change + proration trigger)
- [ ] PL/pgSQL function: `calculate_proration(plan_price, period_start, period_end, change_date)`
- [ ] Subscription state machine diagram (document valid transitions)
- [ ] Seed: subscriptions in various states for testing

### DBMS Concepts Introduced
- Partial indexes (active subscriptions only)
- State machine via CHECK constraint
- PL/pgSQL scalar function
- ACID transaction for plan upgrade (change plan + record proration credit atomically)
- READ COMMITTED vs REPEATABLE READ for subscription reads

### Deliverable
Can create, upgrade, pause, cancel subscriptions. State transitions enforced at DB level (invalid transitions rejected by CHECK). Proration amount calculated correctly.

---

## Phase 3 — Billing Engine (Invoice + Payment)

**Goal:** Invoices generated correctly. Payments recorded. Financial integrity maintained.

### Tasks
- [ ] Migration 008: `invoices` table with idempotency key
- [ ] Migration 009: `invoice_line_items` table
- [ ] Migration 010: `payments` table
- [ ] Migration 011: Covering indexes for invoice queries
- [ ] Audit trigger: apply `log_audit_event()` to subscriptions, invoices, payments
- [ ] Stored procedure: `generate_invoice(subscription_id, period_start, period_end)` — SERIALIZABLE transaction
- [ ] Cron job (Node): runs every minute in dev, queries for due subscriptions, calls generate_invoice
- [ ] Payment API: POST /payments (record payment, update invoice.amount_paid via trigger)
- [ ] Trigger: AFTER INSERT on payments → update invoice status to 'paid' if fully covered
- [ ] API: GET /invoices, GET /invoices/:id (with line items)
- [ ] Demonstrate: run billing job twice for same subscription → idempotency prevents duplicate invoice

### DBMS Concepts Introduced
- SERIALIZABLE transaction (billing job)
- Idempotency key (UNIQUE constraint prevents double invoice)
- Covering index (invoice list query)
- AFTER trigger (payment → invoice status update)
- `SELECT ... FOR UPDATE` (payment posting)
- Audit trail via triggers
- EXPLAIN ANALYZE: show index usage on invoice queries

### Deliverable
Run billing cron → invoices generated. Post payment → invoice marked paid. Running cron twice → no duplicate invoices. Full audit log populated. EXPLAIN ANALYZE showing index scans.

---

## Phase 4 — DBMS Deep Dives (The Impressive Part)

**Goal:** Demonstrate depth. Isolation levels, query optimization, materialized views.

### Tasks
- [ ] Isolation level demo script: phantom read scenario + SERIALIZABLE fix (with documented output)
- [ ] Materialized view: `mrr_by_tenant` — MRR calculation
- [ ] Materialized view: refresh strategy + CONCURRENTLY
- [ ] View: `customer_subscription_summary`
- [ ] Report API: GET /reports/mrr, GET /reports/churn, GET /reports/aging, GET /reports/revenue
- [ ] Query optimization: pick 3 slow queries, add indexes, document EXPLAIN ANALYZE before/after
- [ ] Dunning: add `dunning_state` to subscriptions, stored procedure to advance dunning
- [ ] Document: normalization decisions with justification for each denormalization
- [ ] Document: index strategy with EXPLAIN output for each index

### DBMS Concepts Introduced
- Materialized views with CONCURRENTLY refresh
- Isolation level comparison (written demonstration)
- EXPLAIN ANALYZE deep dive
- Window functions for reports
- ROLLUP for revenue aggregation
- Advisory locks (dunning job coordination)

### Deliverable
All reports working from materialized views. Written document showing phantom read demo. EXPLAIN ANALYZE output saved for at least 3 queries. Dunning flow complete.

---

## Phase 5 — Frontend Dashboard

**Goal:** Visual interface that makes the database work visible and impressive.

### Pages
- [ ] Auth: Login / Register (tenant signup)
- [ ] Dashboard: MRR widget, active subscriptions count, recent invoices, churn rate
- [ ] Customers: Table with search, subscription status badge
- [ ] Customer Detail: Subscription info, invoice history, payment history
- [ ] Plans: List, create/edit form
- [ ] Invoices: List with filters (status, date range), detail view
- [ ] Payments: List, record payment form
- [ ] Reports: Charts for MRR trend, revenue by plan, churn

### Tech Notes
- React + TypeScript + React Query (for data fetching)
- Tailwind CSS or shadcn/ui for components
- Chart library: Recharts or Chart.js
- No complex state management needed — React Query handles it

### Deliverable
Full UI working against real backend. Dashboard shows live data. Can create customer → subscribe → generate invoice → record payment entirely through UI.

---

## Phase 6 — Polish & Demo Prep

**Goal:** Presentation-ready project.

### Tasks
- [ ] Realistic seed data (demo tenant with 50+ customers, 6 months of invoices)
- [ ] Error handling: proper HTTP status codes, typed error responses
- [ ] Input validation: Zod schemas on all API inputs
- [ ] API documentation: README with setup steps and endpoint list
- [ ] Database diagram: generated from live schema (pgAdmin or dbdiagram.io)
- [ ] Demo script: 5-minute walkthrough of key DBMS concepts with live evidence
- [ ] Performance: check all N+1 query problems in frontend
- [ ] Security review: RLS bypass attempts, JWT edge cases

---

## Feature Backlog (Not Planned — Just Ideas)

These are only if Phase 1-4 are completely done and time remains:

- Usage-based billing (metered events)
- Multi-currency (currency conversion rates table)
- Webhook event log (outbound events to payment processor)
- Customer self-service portal
- Tax calculation by region
- Subscription discounts / coupon codes
- Plan add-ons / feature flags per subscription

---

## Decision Log

| Date | Decision | Rationale |
|---|---|---|
| 2026-04-02 | Shared schema multi-tenancy | Best for demonstrating RLS and indexing depth |
| 2026-04-02 | Raw SQL over ORM | Maximize visibility of DBMS concepts |
| 2026-04-02 | UUID PKs everywhere | Multi-tenant safety, avoids sequential enumeration |
| 2026-04-02 | NUMERIC(12,2) for money | Never FLOAT for currency |
| 2026-04-02 | PostgreSQL as RDBMS | RLS, JSONB, partial indexes, PL/pgSQL |
| 2026-04-02 | TypeScript full stack | Type safety across API boundary |

---

## Questions to Revisit Later

- Invoice number format (auto-sequence per tenant: `INV-2026-0001`?)
- Dunning retry schedule (3 attempts: day 3, day 7, day 14 before uncollectible?)
- Frontend charting library choice
- Whether to mock a payment processor or just record payments manually
