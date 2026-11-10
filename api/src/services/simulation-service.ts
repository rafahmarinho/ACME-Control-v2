import type { SupabaseClient } from '@supabase/supabase-js';
import { ApiError, } from '../lib/http.js';
import { must } from '../lib/supabase.js';
import { AlarmTracker } from '../sim/alarm-tracker.js';
import { evaluateAlarms, plantStatus, simulateStep, type SimModel } from '../sim/engine.js';
import {
  type Alarm,
  type Equipment,
  type Plant,
  type PlantState,
  type Scenario,
  type SimEvent,
  TREND_TAGS,
} from '../sim/types.js';
import type { AuthUser } from '../lib/auth.js';
import { notifyNewAlarms } from './integrations.js';

export interface LoadedPlant {
  model: SimModel;
  alarms: Alarm[];
  originalTick: number;
}

const num = (v: unknown) => (v === null || v === undefined ? null : Number(v));

function normalizeEquipment(row: Record<string, unknown>): Equipment {
  const e = { ...row } as Equipment;
  for (const k of ['level_pct', 'volume_m3', 'capacity_m3', 'rated_flow_m3h', 'flow_m3h', 'speed_pct', 'position_pct', 'pressure_bar', 'value'] as const) {
    (e as Record<string, unknown>)[k] = num(row[k]);
  }
  e.run_hours = Number(row.run_hours ?? 0);
  e.starts_count = Number(row.starts_count ?? 0);
  e.health_pct = Number(row.health_pct ?? 100);
  return e;
}

export async function loadPlant(db: SupabaseClient, plantId: string): Promise<LoadedPlant> {
  const [plantRes, stateRes, eqRes, spRes, alarmRes] = await Promise.all([
    db.from('plants').select('*').eq('id', plantId).maybeSingle(),
    db.from('plant_state').select('*').eq('plant_id', plantId).maybeSingle(),
    db.from('equipment').select('*').eq('plant_id', plantId),
    db.from('setpoints').select('key, value').eq('plant_id', plantId),
    db.from('alarms').select('*').eq('plant_id', plantId).neq('state', 'closed'),
  ]);
  const plantRow = plantRes.data;
  if (!plantRow) throw new ApiError(404, `Plant "${plantId}" not found.`, 'not_found');
  const stateRow = must(stateRes, 'Load plant state') as PlantState;
  const scenario = must(
    await db.from('scenarios').select('*').eq('id', stateRow.scenario_id).maybeSingle(),
    'Load scenario',
  ) as Scenario;

  const plant: Plant & { timezone?: string } = {
    id: plantRow.id,
    name: plantRow.name,
    base_inflow_m3h: Number(plantRow.base_inflow_m3h),
    base_demand_m3h: Number(plantRow.base_demand_m3h),
    timezone: plantRow.timezone,
  };
  const state: PlantState = {
    ...stateRow,
    tick: Number(stateRow.tick),
    inlet_flow_m3h: Number(stateRow.inlet_flow_m3h),
    transfer_flow_m3h: Number(stateRow.transfer_flow_m3h),
    distribution_flow_m3h: Number(stateRow.distribution_flow_m3h),
    demand_m3h: Number(stateRow.demand_m3h),
    transfer_pressure_bar: Number(stateRow.transfer_pressure_bar),
    distribution_pressure_bar: Number(stateRow.distribution_pressure_bar),
  };
  const equipment = new Map<string, Equipment>();
  for (const row of must(eqRes, 'Load equipment')) equipment.set(row.tag, normalizeEquipment(row));
  const setpoints: Record<string, number> = {};
  for (const r of must(spRes, 'Load setpoints')) setpoints[r.key] = Number(r.value);

  return {
    model: {
      plant,
      scenario: { ...scenario, inflow_factor: Number(scenario.inflow_factor), demand_factor: Number(scenario.demand_factor) },
      setpoints,
      state,
      equipment,
    },
    alarms: (must(alarmRes, 'Load alarms') as Alarm[]),
    originalTick: state.tick,
  };
}

export interface RunOptions {
  /** Total simulated seconds. 0 = apply mutation only (one tiny step). */
  seconds: number;
  /** Step size in seconds. */
  stepSec?: number;
  /** Minimum simulated seconds between recorded trend samples. */
  measurementEverySec?: number;
  /** Changes applied to the in-memory model before stepping (commands, scenarios…). */
  mutate?: (loaded: LoadedPlant) => void | Promise<void>;
  actor?: AuthUser | null;
  /** Extra events logged with the run (e.g. "Scenario changed"). */
  extraEvents?: SimEvent[];
}

export interface RunResult {
  plantId: string;
  stepsRun: number;
  simulatedSeconds: number;
  state: PlantState;
  equipment: Equipment[];
  events: SimEvent[];
  alarmsRaised: number;
  alarmsChanged: number;
  measurementsRecorded: number;
  model: SimModel;
}

class TickConflict extends Error {}

const MAX_EVENTS_PER_RUN = 150;

async function runOnce(db: SupabaseClient, plantId: string, opts: RunOptions): Promise<RunResult> {
  const loaded = await loadPlant(db, plantId);
  const { model } = loaded;
  if (opts.mutate) await opts.mutate(loaded);

  const total = Math.max(0, opts.seconds);
  const stepSec = opts.stepSec ?? 5;
  const steps = total <= 0 ? 1 : Math.max(1, Math.ceil(total / stepSec));
  const dt = total <= 0 ? 0.5 : total / steps;
  const measureEvery = opts.measurementEverySec ?? 10;

  const tracker = new AlarmTracker(plantId, loaded.alarms, model.equipment);
  const events: SimEvent[] = [...(opts.extraEvents ?? [])];
  const measurements: { plant_id: string; tag: string; value: number; ts: string }[] = [];
  let lastMeasure = model.state.last_measurement_at ? new Date(model.state.last_measurement_at).getTime() : 0;
  let lastConditions = evaluateAlarms(model);

  for (let i = 0; i < steps; i++) {
    events.push(...simulateStep(model, dt));
    lastConditions = evaluateAlarms(model);
    tracker.apply(lastConditions, model.state.sim_time, events);

    const simMs = new Date(model.state.sim_time).getTime();
    if (simMs - lastMeasure >= measureEvery * 1000) {
      lastMeasure = simMs;
      for (const tag of TREND_TAGS) {
        const v = model.equipment.get(tag)?.value;
        if (typeof v === 'number') measurements.push({ plant_id: plantId, tag, value: v, ts: model.state.sim_time });
      }
    }
  }

  const nowIso = new Date().toISOString();
  const s = model.state;
  s.status = plantStatus(lastConditions);
  const statePatch = {
    scenario_id: s.scenario_id,
    auto_run: s.auto_run,
    sim_time: s.sim_time,
    last_tick_at: nowIso,
    last_measurement_at: lastMeasure ? new Date(lastMeasure).toISOString() : s.last_measurement_at,
    tick: loaded.originalTick + 1,
    inlet_flow_m3h: s.inlet_flow_m3h,
    transfer_flow_m3h: s.transfer_flow_m3h,
    distribution_flow_m3h: s.distribution_flow_m3h,
    demand_m3h: s.demand_m3h,
    transfer_pressure_bar: s.transfer_pressure_bar,
    distribution_pressure_bar: s.distribution_pressure_bar,
    status: s.status,
    updated_at: nowIso,
  };

  // Optimistic concurrency: only one writer per tick wins.
  const cas = await db
    .from('plant_state')
    .update(statePatch)
    .eq('plant_id', plantId)
    .eq('tick', loaded.originalTick)
    .select('*');
  if (cas.error) throw new ApiError(500, `Update plant state: ${cas.error.message}`, 'database_error');
  if (!cas.data || cas.data.length === 0) throw new TickConflict();
  Object.assign(s, statePatch);

  const equipmentRows = [...model.equipment.values()].map((e) => ({ ...e, updated_at: nowIso }));
  const eqUp = await db.from('equipment').upsert(equipmentRows, { onConflict: 'id' });
  if (eqUp.error) throw new ApiError(500, `Update equipment: ${eqUp.error.message}`, 'database_error');

  if (tracker.changed.size > 0) {
    const res = await db.from('alarms').upsert([...tracker.changed.values()], { onConflict: 'id' });
    if (res.error) throw new ApiError(500, `Update alarms: ${res.error.message}`, 'database_error');
  }

  for (let i = 0; i < measurements.length; i += 1000) {
    const res = await db.from('measurements').insert(measurements.slice(i, i + 1000));
    if (res.error) throw new ApiError(500, `Insert measurements: ${res.error.message}`, 'database_error');
  }

  const logged = events.length > MAX_EVENTS_PER_RUN
    ? [
        ...events.slice(0, MAX_EVENTS_PER_RUN - 1),
        { category: 'simulation', severity: 'info', message: `${events.length - MAX_EVENTS_PER_RUN + 1} further process events omitted from this run.` } as SimEvent,
      ]
    : events;
  if (logged.length > 0) {
    const res = await db.from('events').insert(
      logged.map((e) => ({
        plant_id: plantId,
        category: e.category,
        severity: e.severity,
        message: e.message,
        actor_id: e.category === 'process' || e.category === 'alarm' ? null : opts.actor?.id ?? null,
        actor_name: e.category === 'process' || e.category === 'alarm' ? 'Process' : opts.actor?.name ?? 'System',
        payload: e.tag ? { tag: e.tag } : {},
        sim_time: s.sim_time,
      })),
    );
    if (res.error) console.warn('[sim] events insert failed', res.error.message);
  }

  if (tracker.raised.length > 0) await notifyNewAlarms(db, plantId, tracker.raised);
  await resolveInProgressCommands(db, plantId, model);

  return {
    plantId,
    stepsRun: steps,
    simulatedSeconds: total,
    state: s,
    equipment: [...model.equipment.values()],
    events,
    alarmsRaised: tracker.raised.length,
    alarmsChanged: tracker.changed.size,
    measurementsRecorded: measurements.length,
    model,
  };
}

/** Runs the simulation with retry on concurrent ticks. */
export async function runSimulation(db: SupabaseClient, plantId: string, opts: RunOptions): Promise<RunResult> {
  for (let attempt = 0; attempt < 4; attempt++) {
    try {
      return await runOnce(db, plantId, opts);
    } catch (err) {
      if (!(err instanceof TickConflict)) throw err;
      await new Promise((r) => setTimeout(r, 80 + Math.random() * 120));
    }
  }
  throw new ApiError(409, 'The plant is being updated by another request. Please retry.', 'conflict');
}

/** Valve commands complete once travel finishes; resolve them on later ticks. */
async function resolveInProgressCommands(db: SupabaseClient, plantId: string, model: SimModel) {
  const { data } = await db.from('commands').select('id, tag, requested_state').eq('plant_id', plantId).eq('status', 'in_progress');
  for (const c of data ?? []) {
    const e = model.equipment.get(c.tag);
    if (!e) continue;
    if (e.actual_state === c.requested_state) {
      await db
        .from('commands')
        .update({ status: 'completed', result_message: `${c.tag} ${e.actual_state}.`, completed_at: new Date().toISOString() })
        .eq('id', c.id);
    } else if (['locked_out', 'fault'].includes(e.actual_state) || e.requested_state !== c.requested_state) {
      await db
        .from('commands')
        .update({
          status: 'blocked',
          result_message: `${c.tag} did not reach ${c.requested_state}: ${e.interlock_reason ?? 'superseded by a newer request'}.`,
          completed_at: new Date().toISOString(),
        })
        .eq('id', c.id);
    }
  }
}

/** Real-time tick: catches the plant up with wall-clock time (max 30 min). */
export async function tick(db: SupabaseClient, plantId: string, actor: AuthUser | null) {
  const { data: st, error } = await db.from('plant_state').select('auto_run, last_tick_at, tick').eq('plant_id', plantId).maybeSingle();
  if (error) throw new ApiError(500, error.message, 'database_error');
  if (!st) throw new ApiError(404, `Plant "${plantId}" not found.`, 'not_found');
  const elapsed = (Date.now() - new Date(st.last_tick_at).getTime()) / 1000;

  if (!st.auto_run) {
    // Paused: keep the clock anchored so resuming does not replay paused time.
    if (elapsed > 5) await db.from('plant_state').update({ last_tick_at: new Date().toISOString() }).eq('plant_id', plantId).eq('tick', st.tick);
    return { skipped: true, reason: 'paused' as const };
  }
  if (elapsed < 2) return { skipped: true, reason: 'too_soon' as const };

  const seconds = Math.min(elapsed, 1800);
  const result = await runSimulation(db, plantId, { seconds, stepSec: 5, measurementEverySec: 10, actor });
  return { skipped: false, ...summary(result) };
}

export function summary(r: RunResult) {
  return {
    plantId: r.plantId,
    stepsRun: r.stepsRun,
    simulatedSeconds: Math.round(r.simulatedSeconds),
    simTime: r.state.sim_time,
    status: r.state.status,
    alarmsRaised: r.alarmsRaised,
    measurementsRecorded: r.measurementsRecorded,
    events: r.events.slice(-20).map((e) => e.message),
  };
}

export async function listPlantIds(db: SupabaseClient): Promise<string[]> {
  const { data, error } = await db.from('plants').select('id').order('id');
  if (error) throw new ApiError(500, error.message, 'database_error');
  return (data ?? []).map((p) => p.id);
}
