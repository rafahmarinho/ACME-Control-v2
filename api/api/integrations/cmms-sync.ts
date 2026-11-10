import { z } from 'zod';
import { handler, preflight, readBody } from '../../src/lib/http.js';
import { requireUser } from '../../src/lib/auth.js';
import { db } from '../../src/lib/supabase.js';
import { cmmsSync } from '../../src/services/operations-service.js';

const Body = z.object({ workOrderId: z.uuid() });

/** POST /api/integrations/cmms-sync — push a work order to the simulated CMMS. */
export const POST = handler(async (req) => {
  const user = await requireUser(req);
  const { workOrderId } = await readBody(req, Body);
  return cmmsSync(db(), user, workOrderId);
});
export const OPTIONS = preflight;
