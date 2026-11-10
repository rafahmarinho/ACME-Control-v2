import { z } from 'zod';
import { handler, preflight, readBody } from '../../src/lib/http.js';
import { SIMULATION_ROLES, requireUser } from '../../src/lib/auth.js';
import { db } from '../../src/lib/supabase.js';
import { advance } from '../../src/services/operations-service.js';

const Body = z.object({ plantId: z.string().min(1), minutes: z.number().int().min(1).max(240) });

/** POST /api/simulation/advance — fast-forward the plant by N minutes. */
export const POST = handler(async (req) => {
  const user = await requireUser(req, SIMULATION_ROLES);
  return advance(db(), user, await readBody(req, Body));
});
export const OPTIONS = preflight;
