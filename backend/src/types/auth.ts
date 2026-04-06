import { Request } from 'express';
import { PoolClient } from 'pg';

export interface JwtPayload {
  tenantId: string;
  userId:   string;
  role:     'owner' | 'member';
  email:    string;
}

// All authenticated routes get both auth context and a scoped DB client.
// dbClient has app.current_tenant_id set — RLS filters automatically.
export interface AuthRequest extends Request {
  auth:     JwtPayload;
  dbClient: PoolClient;
}

export interface RegisterBody {
  tenantName: string;
  slug:       string;
  email:      string;  // owner's login email
  name:       string;  // owner's display name
  password:   string;
}

export interface LoginBody {
  email:    string;
  password: string;
}
