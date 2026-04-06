import bcrypt from 'bcryptjs';
import jwt from 'jsonwebtoken';
import { adminPool, withTransaction } from '../db';
import { JwtPayload, RegisterBody, LoginBody } from '../types/auth';

const JWT_SECRET  = process.env.JWT_SECRET  || 'dev_secret_change_in_production';
const JWT_EXPIRES = process.env.JWT_EXPIRES_IN || '7d';

function signToken(payload: JwtPayload): string {
  return jwt.sign(payload, JWT_SECRET, { expiresIn: JWT_EXPIRES } as jwt.SignOptions);
}

export async function register(body: RegisterBody): Promise<string> {
  const { tenantName, slug, email, name, password } = body;

  // Validate slug format — lowercase letters, numbers, hyphens only
  if (!/^[a-z0-9-]+$/.test(slug)) {
    throw new Error('Slug may only contain lowercase letters, numbers, and hyphens');
  }

  const passwordHash = await bcrypt.hash(password, 10);

  // adminPool: RLS WITH CHECK on tenants blocks INSERT without a tenant context.
  // Registration is the one operation that must run as superuser.
  return withTransaction(async (client) => {
    // Check slug uniqueness explicitly for a clear error message
    const existing = await client.query(
      'SELECT id FROM tenants WHERE slug = $1',
      [slug],
    );
    if (existing.rows.length > 0) {
      throw new Error(`Tenant slug "${slug}" is already taken`);
    }

    const tenantResult = await client.query<{ id: string }>(
      `INSERT INTO tenants (name, slug, email)
       VALUES ($1, $2, $3)
       RETURNING id`,
      [tenantName, slug, email],
    );
    const tenantId = tenantResult.rows[0].id;

    const userResult = await client.query<{ id: string; role: string }>(
      `INSERT INTO tenant_users (tenant_id, email, password_hash, name, role)
       VALUES ($1, $2, $3, $4, 'owner')
       RETURNING id, role`,
      [tenantId, email, passwordHash, name],
    );
    const user = userResult.rows[0];

    return signToken({
      tenantId,
      userId: user.id,
      role:   user.role as 'owner' | 'member',
      email,
    });
  }, true); // true = use adminPool
}

export async function login(body: LoginBody): Promise<string> {
  const { email, password } = body;

  // adminPool: must look up credentials before we know which tenant to scope to.
  // Once verified, subsequent requests use the app pool with RLS.
  const result = await adminPool.query<{
    id:            string;
    tenant_id:     string;
    role:          string;
    password_hash: string;
  }>(
    `SELECT tu.id, tu.tenant_id, tu.role, tu.password_hash
     FROM   tenant_users tu
     JOIN   tenants t ON t.id = tu.tenant_id
     WHERE  tu.email = $1
       AND  t.status = 'active'
     LIMIT 1`,
    [email],
  );

  if (result.rows.length === 0) {
    throw new Error('Invalid email or password');
  }

  const user = result.rows[0];
  const valid = await bcrypt.compare(password, user.password_hash);
  if (!valid) {
    throw new Error('Invalid email or password');
  }

  return signToken({
    tenantId: user.tenant_id,
    userId:   user.id,
    role:     user.role as 'owner' | 'member',
    email,
  });
}

export function verifyToken(token: string): JwtPayload {
  return jwt.verify(token, JWT_SECRET) as JwtPayload;
}
