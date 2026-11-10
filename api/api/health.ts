import { handler, preflight } from '../src/lib/http.js';

/** GET /api/health — liveness probe. */
export const GET = handler(async () => ({
  status: 'ok',
  service: 'acme-control-api',
  version: '1.0.0',
  time: new Date().toISOString(),
  supabaseConfigured: Boolean(process.env.SUPABASE_URL && process.env.SUPABASE_SERVICE_ROLE_KEY),
}));
export const OPTIONS = preflight;
