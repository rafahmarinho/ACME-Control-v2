import { ApiError } from './http.js';
import { db } from './supabase.js';
import type { UserRole } from '../sim/types.js';

export interface AuthUser {
  id: string;
  email: string;
  name: string;
  role: UserRole;
}

/** Validates the Supabase access token (Bearer) and loads the caller's role. */
export async function requireUser(req: Request, allowed?: UserRole[]): Promise<AuthUser> {
  const header = req.headers.get('authorization') ?? '';
  const token = header.toLowerCase().startsWith('bearer ') ? header.slice(7).trim() : '';
  if (!token) throw new ApiError(401, 'Sign in required.', 'unauthenticated');

  const { data, error } = await db().auth.getUser(token);
  if (error || !data.user) throw new ApiError(401, 'Your session has expired. Please sign in again.', 'unauthenticated');

  const { data: profile, error: pErr } = await db()
    .from('profiles')
    .select('id, email, full_name, role')
    .eq('id', data.user.id)
    .maybeSingle();
  if (pErr) throw new ApiError(500, pErr.message, 'database_error');
  if (!profile) throw new ApiError(403, 'No profile found for this account.', 'forbidden');

  const user: AuthUser = {
    id: profile.id,
    email: profile.email,
    name: profile.full_name || profile.email,
    role: profile.role,
  };
  if (allowed && !allowed.includes(user.role)) {
    throw new ApiError(403, `Your role (${user.role}) is not allowed to perform this action.`, 'forbidden');
  }
  return user;
}

export const CONTROL_ROLES: UserRole[] = ['operator', 'supervisor'];
export const SIMULATION_ROLES: UserRole[] = ['operator', 'engineer', 'supervisor'];
export const RESET_ROLES: UserRole[] = ['engineer', 'supervisor'];
export const PROPOSE_ROLES: UserRole[] = ['engineer', 'supervisor'];
export const REVIEW_ROLES: UserRole[] = ['supervisor'];
export const LOCKOUT_ROLES: UserRole[] = ['maintenance', 'supervisor'];
