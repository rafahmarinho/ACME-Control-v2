import { handler, preflight } from '../../src/lib/http.js';
import { requireUser } from '../../src/lib/auth.js';
import { db } from '../../src/lib/supabase.js';
import { integrationStatus } from '../../src/services/integrations.js';

/** GET /api/integrations/status — health of the simulated external systems. */
export const GET = handler(async (req) => {
  await requireUser(req);
  return { systems: await integrationStatus(db()) };
});
export const OPTIONS = preflight;
