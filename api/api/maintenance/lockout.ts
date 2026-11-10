import { z } from 'zod';
import { handler, preflight, readBody } from '../../src/lib/http.js';
import { LOCKOUT_ROLES, requireUser } from '../../src/lib/auth.js';
import { db } from '../../src/lib/supabase.js';
import { setLockout } from '../../src/services/operations-service.js';

const Body = z.object({ workOrderId: z.uuid(), apply: z.boolean() });

/** POST /api/maintenance/lockout — apply or release LOTO for a work order. */
export const POST = handler(async (req) => {
  const user = await requireUser(req, LOCKOUT_ROLES);
  return setLockout(db(), user, await readBody(req, Body));
});
export const OPTIONS = preflight;
