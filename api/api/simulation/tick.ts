import { z } from 'zod';
import { handler, preflight, readBody } from '../../src/lib/http.js';
import { requireUser } from '../../src/lib/auth.js';
import { db } from '../../src/lib/supabase.js';
import { listPlantIds, tick } from '../../src/services/simulation-service.js';

const Body = z.object({ plantId: z.string().min(1).optional() });

/**
 * POST /api/simulation/tick — advance the live simulation to "now".
 * Called periodically by foreground clients; a no-op within 2 s of the last tick.
 */
export const POST = handler(async (req) => {
  const user = await requireUser(req);
  const { plantId } = await readBody(req, Body);
  const ids = plantId ? [plantId] : await listPlantIds(db());
  const results = [];
  for (const id of ids) results.push(await tick(db(), id, user));
  return plantId ? results[0] : { results };
});
export const OPTIONS = preflight;
