import { z } from 'zod';
import { handler, preflight, readBody } from '../../src/lib/http.js';
import { REVIEW_ROLES, requireUser } from '../../src/lib/auth.js';
import { db } from '../../src/lib/supabase.js';
import { reviewProposal } from '../../src/services/operations-service.js';

const Body = z.object({
  proposalId: z.uuid(),
  decision: z.enum(['approve', 'reject']),
  note: z.string().trim().max(1000).optional(),
});

/** POST /api/setpoints/review — supervisor approves or rejects a proposal. */
export const POST = handler(async (req) => {
  const user = await requireUser(req, REVIEW_ROLES);
  return reviewProposal(db(), user, await readBody(req, Body));
});
export const OPTIONS = preflight;
