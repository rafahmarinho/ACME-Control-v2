import type { SupabaseClient } from '@supabase/supabase-js';
import { ApiError } from '../lib/http.js';
import { must } from '../lib/supabase.js';
import type { AuthUser } from '../lib/auth.js';
import { runSimulation, summary } from './simulation-service.js';
import { logIntegration, syncWorkOrderToCmms } from './integrations.js';
import type { Scenario } from '../sim/types.js';

async function logEvent(
  db: SupabaseClient,
  e: { plant_id: string | null; category: string; severity?: string; message: string; actor?: AuthUser | null; payload?: Record<string, unknown> },
) {
  await db.from('events').insert({
    plant_id: e.plant_id,
    category: e.category,
    severity: e.severity ?? 'info',
    message: e.message,
    actor_id: e.actor?.id ?? null,
    actor_name: e.actor?.name ?? 'System',
    payload: e.payload ?? {},
  });
}

// ---------------------------------------------------------------------------
// Setpoint proposals
// ---------------------------------------------------------------------------

export async function proposeSetpoint(
  db: SupabaseClient,
  user: AuthUser,
  input: { setpointId: string; proposedValue: number; reason: string },
) {
  const spRow = must(await db.from('setpoints').select('*').eq('id', input.setpointId).maybeSingle(), 'Setpoint');
  const min = Number(spRow.min_value);
  const max = Number(spRow.max_value);
  const current = Number(spRow.value);
  if (input.proposedValue < min || input.proposedValue > max) {
    throw new ApiError(422, `Value must be between ${min} and ${max} ${spRow.unit}.`, 'out_of_range');
  }
  if (input.proposedValue === current) throw new ApiError(422, 'The proposed value equals the current value.', 'no_change');

  const pending = await db.from('setpoint_proposals').select('id').eq('setpoint_id', spRow.id).eq('status', 'pending');
  if ((pending.data ?? []).length > 0) {
    throw new ApiError(409, 'There is already a pending proposal for this setpoint. Wait for the supervisor review.', 'duplicate');
  }

  const row = must(
    await db
      .from('setpoint_proposals')
      .insert({
        setpoint_id: spRow.id,
        plant_id: spRow.plant_id,
        setpoint_name: spRow.name,
        unit: spRow.unit,
        current_value: current,
        proposed_value: input.proposedValue,
        reason: input.reason,
        proposed_by: user.id,
        proposed_by_name: user.name,
      })
      .select('*')
      .single(),
    'Create proposal',
  );
  await logEvent(db, {
    plant_id: spRow.plant_id, category: 'setpoint', actor: user,
    message: `Setpoint change proposed: ${spRow.name} ${current} → ${input.proposedValue} ${spRow.unit}`,
    payload: { proposal_id: row.id },
  });
  await logIntegration(db, {
    plant_id: spRow.plant_id, system: 'email', action: 'proposal.notify',
    message: `Emailed shift supervisors: review requested for "${spRow.name}" (${current} → ${input.proposedValue} ${spRow.unit}).`,
  });
  return row;
}

export async function reviewProposal(
  db: SupabaseClient,
  user: AuthUser,
  input: { proposalId: string; decision: 'approve' | 'reject'; note?: string },
) {
  const p = must(await db.from('setpoint_proposals').select('*').eq('id', input.proposalId).maybeSingle(), 'Proposal');
  if (p.status !== 'pending') throw new ApiError(409, `This proposal was already ${p.status}.`, 'already_reviewed');
  if (p.proposed_by === user.id) throw new ApiError(403, 'You cannot review your own proposal (four-eyes principle).', 'forbidden');
  if (input.decision === 'reject' && !input.note?.trim()) {
    throw new ApiError(422, 'A note explaining the rejection is required.', 'note_required');
  }

  const now = new Date().toISOString();
  const status = input.decision === 'approve' ? 'approved' : 'rejected';

  // Guard against a race with another reviewer.
  const upd = await db
    .from('setpoint_proposals')
    .update({ status, reviewed_by: user.id, reviewed_by_name: user.name, review_note: input.note ?? null, reviewed_at: now })
    .eq('id', p.id)
    .eq('status', 'pending')
    .select('*');
  if (upd.error) throw new ApiError(500, upd.error.message, 'database_error');
  if (!upd.data?.length) throw new ApiError(409, 'This proposal was reviewed by someone else.', 'already_reviewed');

  if (status === 'approved') {
    const res = await db.from('setpoints').update({ value: p.proposed_value, updated_by_name: user.name, updated_at: now }).eq('id', p.setpoint_id);
    if (res.error) throw new ApiError(500, res.error.message, 'database_error');
  }
  await logEvent(db, {
    plant_id: p.plant_id, category: 'setpoint', actor: user,
    severity: status === 'approved' ? 'warning' : 'info',
    message: status === 'approved'
      ? `Setpoint changed: ${p.setpoint_name} ${p.current_value} → ${p.proposed_value} ${p.unit} (approved)`
      : `Setpoint proposal rejected: ${p.setpoint_name} ${p.current_value} → ${p.proposed_value} ${p.unit}`,
    payload: { proposal_id: p.id, note: input.note ?? null },
  });
  return upd.data[0];
}

// ---------------------------------------------------------------------------
// Maintenance lockout (LOTO)
// ---------------------------------------------------------------------------

export async function setLockout(db: SupabaseClient, user: AuthUser, input: { workOrderId: string; apply: boolean }) {
  const wo = must(await db.from('maintenance_orders').select('*').eq('id', input.workOrderId).maybeSingle(), 'Work order');
  if (!wo.equipment_id) throw new ApiError(422, 'This work order is not linked to equipment.', 'no_equipment');
  if (input.apply && ['completed', 'cancelled'].includes(wo.status)) {
    throw new ApiError(422, 'Cannot apply a lockout on a closed work order.', 'closed');
  }
  const eq = must(await db.from('equipment').select('tag, kind').eq('id', wo.equipment_id).maybeSingle(), 'Equipment');

  if (input.apply) {
    const other = await db
      .from('maintenance_orders')
      .select('number')
      .eq('equipment_id', wo.equipment_id)
      .eq('lockout_applied', true)
      .neq('id', wo.id);
    if (other.data?.length) {
      throw new ApiError(409, `${eq.tag} is already locked out by ${other.data[0].number}.`, 'already_locked');
    }
  }

  const result = await runSimulation(db, wo.plant_id, {
    seconds: 1,
    actor: user,
    mutate: ({ model }) => {
      const e = model.equipment.get(eq.tag)!;
      e.in_maintenance = input.apply;
      e.interlock_reason = input.apply ? `Locked out for maintenance (${wo.number})` : null;
      // Leave the asset in a safe state when it is handed back.
      if (e.kind === 'pump') e.requested_state = 'stopped';
    },
  });

  const res = await db
    .from('maintenance_orders')
    .update({
      lockout_applied: input.apply,
      ...(input.apply && wo.status !== 'in_progress' ? { status: 'in_progress', started_at: new Date().toISOString() } : {}),
    })
    .eq('id', wo.id);
  if (res.error) throw new ApiError(500, res.error.message, 'database_error');

  await logEvent(db, {
    plant_id: wo.plant_id, category: 'maintenance', severity: 'warning', actor: user,
    message: input.apply ? `Lockout applied on ${eq.tag} for ${wo.number}.` : `Lockout released on ${eq.tag} (${wo.number}). Equipment returned to service.`,
    payload: { work_order_id: wo.id },
  });
  return { workOrder: wo.number, tag: eq.tag, lockoutApplied: input.apply, equipment: result.model.equipment.get(eq.tag) };
}

export async function cmmsSync(db: SupabaseClient, user: AuthUser, workOrderId: string) {
  const wo = must(await db.from('maintenance_orders').select('id, number, plant_id, external_ref').eq('id', workOrderId).maybeSingle(), 'Work order');
  const ref = await syncWorkOrderToCmms(db, wo);
  await logEvent(db, { plant_id: wo.plant_id, category: 'integration', actor: user, message: `${wo.number} synchronised with CMMS (${ref}).` });
  return { externalRef: ref };
}

// ---------------------------------------------------------------------------
// Simulation control
// ---------------------------------------------------------------------------

export async function changeScenario(db: SupabaseClient, user: AuthUser, input: { plantId: string; scenarioId: string }) {
  const scenario = must(await db.from('scenarios').select('*').eq('id', input.scenarioId).maybeSingle(), 'Scenario') as Scenario;
  const result = await runSimulation(db, input.plantId, {
    seconds: 1,
    actor: user,
    extraEvents: [{ category: 'simulation', severity: 'warning', message: `Scenario changed to "${scenario.name}"` }],
    mutate: ({ model }) => {
      model.state.scenario_id = scenario.id;
      model.scenario = { ...scenario, inflow_factor: Number(scenario.inflow_factor), demand_factor: Number(scenario.demand_factor) };
      for (const e of model.equipment.values()) {
        if (e.kind === 'pump' || e.kind === 'valve') e.fault_active = scenario.fault_tags.includes(e.tag);
      }
    },
  });
  return summary(result);
}

export async function advance(db: SupabaseClient, user: AuthUser, input: { plantId: string; minutes: number }) {
  const result = await runSimulation(db, input.plantId, {
    seconds: input.minutes * 60,
    stepSec: input.minutes > 60 ? 15 : 10,
    measurementEverySec: input.minutes > 30 ? 60 : 20,
    actor: user,
    extraEvents: [{ category: 'simulation', severity: 'info', message: `Simulation advanced by ${input.minutes} min` }],
  });
  if (result.measurementsRecorded > 0) {
    await logIntegration(db, {
      plant_id: input.plantId, system: 'historian', action: 'batch.upload',
      message: `Uploaded ${result.measurementsRecorded.toLocaleString('en-US')} samples to the plant historian.`,
    });
  }
  return summary(result);
}

export async function setAutoRun(db: SupabaseClient, user: AuthUser, input: { plantId: string; autoRun: boolean }) {
  const res = await db
    .from('plant_state')
    .update({ auto_run: input.autoRun, last_tick_at: new Date().toISOString() })
    .eq('plant_id', input.plantId)
    .select('*');
  if (res.error) throw new ApiError(500, res.error.message, 'database_error');
  if (!res.data?.length) throw new ApiError(404, 'Plant not found.', 'not_found');
  await logEvent(db, {
    plant_id: input.plantId, category: 'simulation', actor: user,
    message: input.autoRun ? 'Live simulation resumed' : 'Live simulation paused',
  });
  return res.data[0];
}

export async function resetDemo(db: SupabaseClient, user: AuthUser) {
  const res = await db.rpc('acme_reset_demo');
  if (res.error) throw new ApiError(500, `Reset failed: ${res.error.message}`, 'database_error');
  await logEvent(db, { plant_id: null, category: 'system', severity: 'warning', actor: user, message: `Demo data reset by ${user.name}.` });
  return { ok: true, resetAt: new Date().toISOString() };
}
