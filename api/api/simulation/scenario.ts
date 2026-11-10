import { z } from 'zod';
import { handler, preflight, readBody } from '../../src/lib/http.js';
import { SIMULATION_ROLES, requireUser } from '../../src/lib/auth.js';
import { db } from '../../src/lib/supabase.js';
import { changeScenario } from '../../src/services/operations-service.js';

const Body = z.object({ plantId: z.string().min(1), scenarioId: z.string().min(1) });

/** POST /api/simulation/scenario — switch the operating scenario of a plant. */
export const POST = handler(async (req) => {
  const user = await requireUser(req, SIMULATION_ROLES);
  return changeScenario(db(), user, await readBody(req, Body));
});
export const OPTIONS = preflight;
