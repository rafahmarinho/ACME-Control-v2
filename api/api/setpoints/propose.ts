import { z } from 'zod';
import { handler, preflight, readBody } from '../../src/lib/http.js';
import { PROPOSE_ROLES, requireUser } from '../../src/lib/auth.js';
import { db } from '../../src/lib/supabase.js';
import { proposeSetpoint } from '../../src/services/operations-service.js';

const Body = z.object({
  setpointId: z.uuid(),
  proposedValue: z.number(),
  reason: z.string().trim().min(10, 'Please explain the reason (at least 10 characters).').max(1000),
});

/** POST /api/setpoints/propose — engineer proposes a setpoint change. */
export const POST = handler(async (req) => {
  const user = await requireUser(req, PROPOSE_ROLES);
  return proposeSetpoint(db(), user, await readBody(req, Body));
});
export const OPTIONS = preflight;
