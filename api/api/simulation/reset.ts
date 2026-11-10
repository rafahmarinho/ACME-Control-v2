import { handler, preflight } from '../../src/lib/http.js';
import { RESET_ROLES, requireUser } from '../../src/lib/auth.js';
import { db } from '../../src/lib/supabase.js';
import { resetDemo } from '../../src/services/operations-service.js';

/** POST /api/simulation/reset — restore all demo data (engineer, supervisor). */
export const POST = handler(async (req) => {
  const user = await requireUser(req, RESET_ROLES);
  return resetDemo(db(), user);
});
export const OPTIONS = preflight;
