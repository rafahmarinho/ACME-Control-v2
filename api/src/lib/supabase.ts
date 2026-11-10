import { createClient, type SupabaseClient } from '@supabase/supabase-js';
import { ApiError } from './http.js';

let admin: SupabaseClient | null = null;

/** Service-role client. Never expose this key to the Flutter app. */
export function db(): SupabaseClient {
  if (admin) return admin;
  const url = process.env.SUPABASE_URL;
  const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
  if (!url || !key) {
    throw new ApiError(500, 'Server is missing SUPABASE_URL or SUPABASE_SERVICE_ROLE_KEY.', 'misconfigured');
  }
  admin = createClient(url, key, {
    auth: { persistSession: false, autoRefreshToken: false },
  });
  return admin;
}

/** Throws ApiError on a PostgREST error and returns data otherwise. */
export function must<T>(res: { data: T; error: { message: string } | null }, what: string): NonNullable<T> {
  if (res.error) throw new ApiError(500, `${what}: ${res.error.message}`, 'database_error');
  if (res.data === null) throw new ApiError(404, `${what}: not found`, 'not_found');
  return res.data as NonNullable<T>;
}
