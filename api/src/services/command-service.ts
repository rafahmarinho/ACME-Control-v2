import type { SupabaseClient } from '@supabase/supabase-js';
import { ApiError } from '../lib/http.js';
import type { AuthUser } from '../lib/auth.js';
import { runSimulation } from './simulation-service.js';
import type { Equipment } from '../sim/types.js';

export type CommandAction = 'start' | 'stop' | 'open' | 'close' | 'set_auto' | 'set_manual';

const ACTIONS_BY_KIND: Record<string, CommandAction[]> = {
  pump: ['start', 'stop', 'set_auto', 'set_manual'],
  valve: ['open', 'close', 'set_auto', 'set_manual'],
};

const REQUESTED: Partial<Record<CommandAction, string>> = {
  start: 'running',
  stop: 'stopped',
  open: 'open',
  close: 'closed',
};

const LABEL: Record<CommandAction, string> = {
  start: 'Start',
  stop: 'Stop',
  open: 'Open',
  close: 'Close',
  set_auto: 'Switch to AUTO',
  set_manual: 'Switch to MANUAL',
};

export interface CommandOutcome {
  id: string;
  status: 'completed' | 'in_progress' | 'blocked' | 'rejected';
  message: string;
  requestedState: string | null;
  actualState: string;
  equipment: Equipment | null;
}

export async function executeCommand(
  db: SupabaseClient,
  user: AuthUser,
  input: { plantId: string; equipmentId: string; action: CommandAction; note?: string },
): Promise<CommandOutcome> {
  const { data: eq, error } = await db.from('equipment').select('*').eq('id', input.equipmentId).maybeSingle();
  if (error) throw new ApiError(500, error.message, 'database_error');
  if (!eq || eq.plant_id !== input.plantId) throw new ApiError(404, 'Equipment not found in this plant.', 'not_found');

  const allowed = ACTIONS_BY_KIND[eq.kind];
  if (!allowed) throw new ApiError(422, `${eq.tag} (${eq.kind}) cannot be operated remotely.`, 'not_controllable');
  if (!allowed.includes(input.action)) throw new ApiError(422, `Action "${input.action}" is not valid for ${eq.kind} ${eq.tag}.`, 'invalid_action');

  const requestedState = REQUESTED[input.action] ?? null;
  const ins = await db
    .from('commands')
    .insert({
      plant_id: input.plantId,
      equipment_id: eq.id,
      tag: eq.tag,
      action: input.action,
      requested_state: requestedState,
      status: 'pending',
      requested_by: user.id,
      requested_by_name: user.name,
    })
    .select('id')
    .single();
  if (ins.error) throw new ApiError(500, ins.error.message, 'database_error');
  const commandId: string = ins.data.id;

  const finish = async (status: CommandOutcome['status'], message: string, equipment: Equipment | null) => {
    await db
      .from('commands')
      .update({ status, result_message: message, completed_at: status === 'in_progress' ? null : new Date().toISOString() })
      .eq('id', commandId);
    return {
      id: commandId,
      status,
      message,
      requestedState,
      actualState: equipment?.actual_state ?? eq.actual_state,
      equipment,
    } satisfies CommandOutcome;
  };

  // Operating commands are only accepted in MANUAL mode.
  if (requestedState && eq.control_mode === 'auto') {
    const msg = `${eq.tag} is in AUTO mode. Switch it to MANUAL before issuing "${LABEL[input.action]}".`;
    await db.from('events').insert({
      plant_id: input.plantId, category: 'command', severity: 'warning',
      message: `Command rejected: ${LABEL[input.action]} ${eq.tag} — equipment in AUTO`,
      actor_id: user.id, actor_name: user.name, payload: { command_id: commandId },
    });
    return finish('rejected', msg, null);
  }

  // Apply the request and let the process respond (interlocks decide the actual state).
  const { data: st } = await db.from('plant_state').select('auto_run, last_tick_at').eq('plant_id', input.plantId).single();
  const elapsed = st?.auto_run ? Math.min(1800, Math.max(0, (Date.now() - new Date(st.last_tick_at).getTime()) / 1000)) : 0;

  const result = await runSimulation(db, input.plantId, {
    seconds: Math.max(elapsed, 1),
    stepSec: 5,
    actor: user,
    extraEvents: [{
      category: 'command',
      severity: 'info',
      tag: eq.tag,
      message: `${LABEL[input.action]} ${eq.tag} requested${input.note ? ` — ${input.note}` : ''}`,
    }],
    mutate: ({ model }) => {
      const e = model.equipment.get(eq.tag)!;
      if (input.action === 'set_auto') e.control_mode = 'auto';
      else if (input.action === 'set_manual') e.control_mode = 'manual';
      else e.requested_state = requestedState;
    },
  });

  const after = result.model.equipment.get(eq.tag)!;
  if (input.action === 'set_auto' || input.action === 'set_manual') {
    return finish('completed', `${eq.tag} switched to ${after.control_mode?.toUpperCase()}.`, after);
  }
  if (after.actual_state === requestedState) {
    return finish('completed', `${eq.tag} ${after.actual_state}.`, after);
  }
  if (after.actual_state === 'opening' || after.actual_state === 'closing') {
    return finish('in_progress', `${eq.tag} ${after.actual_state} (${after.position_pct ?? 0}%).`, after);
  }
  if (requestedState === 'stopped' && after.actual_state !== 'running') {
    return finish('completed', `${eq.tag} not running (${after.actual_state.replace('_', ' ')}).`, after);
  }
  return finish(
    'blocked',
    `${eq.tag} did not reach "${requestedState}": ${after.interlock_reason ?? `actual state is ${after.actual_state}`}.`,
    after,
  );
}
