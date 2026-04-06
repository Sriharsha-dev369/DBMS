# App Flow — Multi-Tenant SaaS Billing Engine

Mental map of the full system: entry point → auth → tenant context → RLS → business logic.

---

## 1. Entry Point

```
npm run dev
  └─ tsx watch src/index.ts
       ├─ dotenv.config('../.env')          loads DB creds, JWT_SECRET, PORT
       ├─ Pool(saasledger_app)              app pool — RLS enforced (max 20 clients)
       ├─ Pool(postgres)                   admin pool — bypasses RLS  (max  5 clients)
       ├─ app.use(cors(), express.json())
       ├─ app.use('/api/auth',      authRoutes)      public
       ├─ app.use('/api/plans',     planRoutes)      protected (auth + RLS)
       ├─ app.use('/api/customers', customerRoutes)  protected (auth + RLS)
       └─ app.listen(3000)
```

Two pools are created once and shared for the lifetime of the process.  
`saasledger_app` is a non-superuser role — PostgreSQL enforces RLS on every query.  
`postgres` (admin) bypasses RLS — used only for registration and login credential lookup.

---

## 2. Auth Flow

### 2a. Register

```
POST /api/auth/register  { tenantName, slug, email, name, password }
  │
  routes/auth.ts
    ├─ validate required fields + password length (≥8)
    └─ authService.register()
         │
         withTransaction(fn, useAdmin=true)   ← adminPool (bypasses RLS)
           │  BEGIN
           ├─ INSERT INTO tenants (id, name, slug, email)
           │    └─ RETURNING id  → tenantId
           ├─ bcrypt.hash(password, 10)  → passwordHash
           ├─ INSERT INTO tenant_users (tenant_id, email, password_hash, name, role='owner')
           │    └─ RETURNING id  → userId
           ├─ signToken({ tenantId, userId, role, email })
           │    └─ jwt.sign(payload, JWT_SECRET, { expiresIn: '7d' })
           │  COMMIT
           └─ return token

  Response 201: { token }
  Error 409:    slug already taken  (unique constraint on tenants.slug)
  Error 400:    missing fields / password too short
```

Why `adminPool`? The `tenants` table has RLS policy `id = current_tenant_id()`.  
A brand-new tenant has no context yet — the INSERT would be rejected by the WITH CHECK.  
The postgres superuser bypasses RLS, making the bootstrap safe.

---

### 2b. Login

```
POST /api/auth/login  { email, password }
  │
  routes/auth.ts
    ├─ validate email + password present
    └─ authService.login()
         │
         adminPool.query(
           SELECT u.id, u.password_hash, u.role, t.id AS tenant_id, t.status
           FROM   tenant_users u JOIN tenants t ON t.id = u.tenant_id
           WHERE  u.email = $1
         )
           ├─ no rows → throw (→ 401)
           ├─ tenant.status !== 'active' → throw (→ 401)
           ├─ bcrypt.compare(password, password_hash)
           │    └─ false → throw (→ 401)
           └─ signToken({ tenantId, userId, role, email }) → return token

  Response 200: { token }
  Error 401:    always "Invalid email or password"  (no hint whether email exists)
```

Login also uses `adminPool` to look up credentials across all tenants without a context.

---

## 3. JWT Structure

```
Header:  { alg: "HS256", typ: "JWT" }

Payload: {
  tenantId:  "018704f9-dcf3-4361-a828-a3a8daa3e3c6",  ← UUID
  userId:    "94327431-6e0c-4c72-beb7-a9fe2f4ce4a8",   ← UUID
  role:      "owner" | "member",
  email:     "owner@test.co",
  iat:       1775463894,
  exp:       1776068694                                  ← 7d from issue
}

Signed with: JWT_SECRET (≥32 chars)
```

The token carries everything the app needs to isolate the request — no session store, no DB lookup on every request.

---

## 4. Protected Request Lifecycle

Every route under `/api/plans` and `/api/customers` passes through this stack:

```
Incoming request
  │
  middleware/auth.ts → authenticate()
    ├─ req.headers.authorization missing or not "Bearer ..."?
    │    └─ 401 "Missing or malformed Authorization header"
    ├─ jwt.verify(token, JWT_SECRET) → throws on invalid/expired
    │    └─ 401 "Invalid or expired token"
    └─ (req as AuthRequest).auth = { tenantId, userId, role, email }
         └─ next()
  │
  middleware/tenantContext.ts → tenantContext()
    ├─ pool.connect()  → checks out a PoolClient from saasledger_app pool
    │    └─ failure → 503 "Database unavailable"
    ├─ setTenantContext(client, req.auth.tenantId)
    │    └─ SELECT set_config('app.current_tenant_id', tenantId, false)
    │         is_local=false → persists for this connection's session
    ├─ req.dbClient = client     ← route handler uses this directly
    ├─ released = false
    ├─ res.once('finish', release)   ← normal response sent
    ├─ res.once('close',  release)   ← socket closed / aborted
    │    Both events can fire — flag ensures client.release() called exactly once
    └─ next()
  │
  Route handler
    ├─ uses req.dbClient for all queries
    ├─ RLS auto-filters every query: tenant_id = current_tenant_id()
    └─ returns response → triggers res.finish → pool client released
```

---

## 5. RLS — How Tenant Isolation Works at the DB Layer

```
PostgreSQL session:
  SET app.current_tenant_id = '018704f9-...'   ← set by tenantContext middleware

RLS helper function (005_rls.sql):
  current_tenant_id() → NULLIF(current_setting('app.current_tenant_id', true), '')::UUID
    ├─ missing → NULL (no rows visible — safe default)
    └─ present → UUID

Every table policy (e.g. plans):
  POLICY tenant_isolation FOR ALL
    USING     (tenant_id = current_tenant_id())   ← SELECT / UPDATE / DELETE filter
    WITH CHECK (tenant_id = current_tenant_id())  ← INSERT / UPDATE guard

Effect:
  SELECT * FROM plans
  → PostgreSQL rewrites to:
    SELECT * FROM plans WHERE tenant_id = '018704f9-...'
  → Tenant B can never see Tenant A's plans, even if the app forgot a WHERE clause
```

Two isolation layers:
- **App layer**: JWT carries `tenantId`, middleware sets the context
- **DB layer**: RLS rejects any query where `tenant_id ≠ current_tenant_id()`

Both must pass. A bug in one doesn't leak data through the other.

---

## 6. Plans CRUD Flow

### GET /api/plans

```
req.dbClient.query(
  SELECT id, name, billing_model, base_price, per_seat_price,
         billing_period, trial_days, is_active, created_at, updated_at
  FROM   plans
  [WHERE is_active = $1]   ← optional query param ?is_active=true|false
  ORDER BY created_at
)
  └─ RLS rewrites to: ...WHERE tenant_id = current_tenant_id() [AND is_active = $1]
  Response: { plans: [...] }
```

### POST /api/plans

```
Validation (app layer):
  ├─ name, billing_model, base_price required
  ├─ billing_model ∈ { flat_rate, per_seat, usage_based }
  ├─ billing_period ∈ { monthly, annual }  if provided
  ├─ base_price ≥ 0 (number)
  ├─ per_seat_price required when billing_model = 'per_seat'
  └─ trial_days is non-negative integer if provided

DB layer constraints (catch-all for anything app missed):
  ├─ CHECK (billing_model IN ('flat_rate','per_seat','usage_based'))
  ├─ CHECK (base_price >= 0)
  ├─ CHECK (plans_per_seat_price_required): billing_model!='per_seat' OR per_seat_price IS NOT NULL
  └─ RLS WITH CHECK: tenant_id = current_tenant_id()

INSERT INTO plans (tenant_id, name, billing_model, base_price, ...)
  └─ tenant_id = auth.tenantId (from JWT)
  Response 201: { plan: { id, name, ... } }
  Error 400:    constraint violation
```

### PATCH /api/plans/:id

```
Allowed fields: name, base_price, per_seat_price, billing_period, trial_days, is_active
Locked fields:  billing_model  (changing breaks per_seat constraint + active subscriptions)

Dynamic SET clause built from request body:
  UPDATE plans
  SET    name = $1, base_price = $2, ...   ← only supplied fields
  WHERE  id = $N
  ← RLS USING clause silently scopes this to current tenant
     rowCount = 0 → 404 (id not found OR belongs to another tenant — same response)
```

### DELETE /api/plans/:id

```
Soft delete — sets is_active = FALSE
  ← Hard delete unsafe: Phase 2 subscriptions reference plans (ON DELETE RESTRICT)

UPDATE plans SET is_active = FALSE WHERE id = $1
  rowCount = 0 → 404
  Response: { plan: { id, name, is_active: false } }
```

---

## 7. Customers CRUD Flow

### GET /api/customers

```
Two queries on req.dbClient:

1. COUNT(*) FROM customers [WHERE status = $1]
   → RLS adds: AND tenant_id = current_tenant_id()
   → total for pagination metadata

2. SELECT id, email, name, status, metadata, created_at, updated_at
   FROM customers
   [WHERE status = $1]
   ORDER BY created_at DESC
   LIMIT $N OFFSET $M

Response: {
  customers: [...],
  pagination: { total, limit, offset }
}

Query params:
  limit   default 20, max 100 (capped)
  offset  default 0
  status  optional — active | inactive | blocked
```

### POST /api/customers

```
Validation:
  ├─ email and name required
  ├─ email contains '@' (basic format)
  └─ metadata is a plain object if provided (not array)

INSERT INTO customers (tenant_id, email, name, metadata)
  ├─ RLS WITH CHECK: tenant_id = current_tenant_id()
  └─ DB UNIQUE (tenant_id, email): same email allowed across tenants, unique within one

  Response 201: { customer: { id, email, name, status: 'active', metadata, created_at } }
  Error 409:    email already exists in this tenant
```

### PATCH /api/customers/:id

```
Allowed fields: name, email, status, metadata
  status values: active | inactive | blocked

UPDATE customers
SET    <dynamic fields>
WHERE  id = $N
  ← RLS USING scopes to current tenant

  Error 409: duplicate email (unique constraint on tenant_id, email)
  Error 404: id not found (or belongs to another tenant — indistinguishable by design)
```

### DELETE /api/customers/:id

```
Soft delete — sets status = 'inactive'
  ← Phase 2 subscriptions will reference customers (ON DELETE RESTRICT)
  ← Hard delete would fail at DB level once subscriptions exist

UPDATE customers SET status = 'inactive' WHERE id = $1
  Response: { customer: { id, email, name, status: 'inactive' } }
```

---

## 8. Database Layer Architecture

```
                     ┌─────────────────────────────┐
                     │        Node.js Process        │
                     │                               │
  Authenticated      │  pool (saasledger_app, max=20)│
  requests ──────────│→ checkout PoolClient          │
                     │  SET app.current_tenant_id    │
                     │  → query (RLS auto-filters)   │
                     │  → release on res.finish/close│
                     │                               │
  Auth endpoints     │  adminPool (postgres, max=5)  │
  (register/login) ──│→ checkout → query → release   │
                     │  (no RLS — superuser)          │
                     └──────────────┬────────────────┘
                                    │ TCP (172.30.64.1:5432)
                     ┌──────────────▼────────────────┐
                     │         PostgreSQL              │
                     │  saasledger_app role:           │
                     │   ├─ RLS enforced on all tables │
                     │   └─ GRANT SELECT/INSERT/       │
                     │      UPDATE/DELETE on all tables│
                     │                                 │
                     │  postgres superuser:            │
                     │   └─ bypasses RLS               │
                     └─────────────────────────────────┘
```

### Connection lifecycle (per authenticated request)

```
tenantContext middleware:
  pool.connect()                          ← waits if all 20 clients are checked out
    └─ SET app.current_tenant_id = $1     ← session-level config (is_local=false)

Route handler executes N queries:
  All run on the same client with the same tenant context.
  RLS is applied automatically by PostgreSQL on every query.

Response sent (res.emit('finish') or 'close'):
  released = true
  client.release()                        ← returns client to pool
    └─ PostgreSQL session remains open but context persists
       (next checkout will overwrite it with SET in tenantContext)
```

---

## 9. Transaction Patterns

Three patterns are available in `db.ts`:

```
withTransaction(fn, useAdmin=false)
  ├─ BEGIN (READ COMMITTED — default PostgreSQL isolation)
  ├─ fn(client) — your logic
  ├─ COMMIT
  └─ ROLLBACK on throw
  Used for: tenant registration (useAdmin=true), future write operations

withSerializableTransaction(fn)
  ├─ BEGIN ISOLATION LEVEL SERIALIZABLE
  ├─ fn(client)
  ├─ COMMIT
  └─ ROLLBACK on throw
  Used for: billing job (Phase 3) — prevents phantom reads during concurrent invoice generation

Direct req.dbClient.query()
  ├─ Autocommit (each query is its own transaction)
  └─ Used for: all CRUD routes in Phase 1 — single-statement operations
```

---

## 10. Error Handling Strategy

```
HTTP status  Meaning
──────────────────────────────────────────────────────
400          Missing required field, invalid type, constraint violation
401          Missing/invalid JWT, wrong credentials
                └─ Auth failures never reveal whether the email exists
403          (future) Role-based access — owner-only operations
404          Record not found OR belongs to another tenant
                └─ Both cases return 404 — don't leak existence of other tenants' data
409          Unique constraint violated (duplicate slug, email)
503          Database unavailable (pool connection failed)
500          Unexpected server error — generic message, real error logged server-side
```

Database constraint errors are caught and translated to typed HTTP responses.  
The raw `err.message` is never sent to the client — only to server logs.

---

## 11. File → Responsibility Map

```
backend/src/
  index.ts                  Server bootstrap, route mounting
  db.ts                     Pool setup, setTenantContext, withTransaction helpers

  middleware/
    auth.ts                 JWT verification → req.auth
    tenantContext.ts        Pool checkout → SET context → req.dbClient → release
    protected.ts            [authenticate, tenantContext] array — imported by routers

  routes/
    auth.ts                 POST /register, POST /login  (public)
    plans.ts                GET/POST/PATCH/DELETE /plans (protected)
    customers.ts            GET/POST/PATCH/DELETE /customers (protected)

  services/
    authService.ts          register(), login(), verifyToken()

  types/
    auth.ts                 JwtPayload, AuthRequest, RegisterBody, LoginBody
    api.ts                  CreatePlanBody, UpdatePlanBody, CreateCustomerBody, UpdateCustomerBody

db/
  migrations/
    001_tenants.sql         tenants, tenant_users tables + set_updated_at() trigger fn
    002_plans.sql           plans, plan_features tables
    003_customers.sql       customers table
    004_indexes.sql         Additional composite/partial indexes
    005_rls.sql             current_tenant_id() fn, saasledger_app role, all RLS policies

  seeds/
    001_seed.sql            2 tenants, 7 plans, 20 customers (placeholder password hashes)
    001_phase1_seed.sql     (alternate seed file)
```

---

## 12. What's Built vs What's Not

| Area | Status | Notes |
|---|---|---|
| Tenant registration + login | ✓ Done | JWT, bcrypt, admin pool bootstrap |
| JWT middleware | ✓ Done | Bearer token, typed payload |
| Tenant context + RLS | ✓ Done | Pool client per request, session SET |
| Plans CRUD | ✓ Done | Soft delete, billing_model locked on PATCH |
| Customers CRUD | ✓ Done | Pagination, soft delete, duplicate email 409 |
| Subscriptions | Phase 2 | State machine, partial unique index, proration fn |
| Invoices + billing job | Phase 3 | SERIALIZABLE tx, idempotency key, cron |
| Payments | Phase 3 | AFTER trigger → invoice status update |
| Audit log | Phase 3 | AFTER trigger on subscriptions/invoices/payments |
| Reports (MRR, churn) | Phase 4 | Materialized views, window functions |
| Frontend dashboard | Phase 5 | React + React Query + Tailwind |
| Seed user passwords | Bug | Placeholder hashes — run bcrypt update before testing seed logins |
