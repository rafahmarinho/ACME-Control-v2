import { z } from 'zod';
import { handler, preflight, readBody } from '../../src/lib/http.js';
import { SIMULATION_ROLES, requireUser } from '../../src/lib/auth.js';
import { db } from '../../src/lib/supabase.js';
import { setAutoRun } from '../../src/services/operations-service.js';

const Body = z.object({ plantId: z.string().min(1), autoRun: z.boolean() });

/** POST /api/simulation/control — pause / resume the live simulation. */
export const POST = handler(async (req) => {
  const user = await requireUser(req, SIMULATION_ROLES);
  return setAutoRun(db(), user, await readBody(req, Body));
});
export const OPTIONS = preflight;
