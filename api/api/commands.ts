import { z } from 'zod';
import { handler, preflight, readBody } from '../src/lib/http.js';
import { CONTROL_ROLES, requireUser } from '../src/lib/auth.js';
import { db } from '../src/lib/supabase.js';
import { executeCommand } from '../src/services/command-service.js';

const Body = z.object({
  plantId: z.string().min(1),
  equipmentId: z.uuid(),
  action: z.enum(['start', 'stop', 'open', 'close', 'set_auto', 'set_manual']),
  note: z.string().max(280).optional(),
});

/** POST /api/commands — operate a pump or valve (operator, supervisor). */
export const POST = handler(async (req) => {
  const user = await requireUser(req, CONTROL_ROLES);
  const body = await readBody(req, Body);
  return executeCommand(db(), user, body);
});
export const OPTIONS = preflight;
