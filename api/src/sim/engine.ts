// Water treatment plant process simulation.
//
//   River ──XV-101──▶ [T-101 Raw Water] ──P-101/P-102──XV-102──▶ [T-102 Clearwell] ──P-201──XV-201──▶ Network
//
// The engine is a pure, deterministic-per-RNG function over an in-memory
// model. It applies AUTO control logic, interlocks, valve travel, mass
// balance on both tanks and computes pressures, then reports events and the
// set of alarm conditions that are currently true.

import {
  type AlarmCondition,
  type Equipment,
  type Plant,
  type PlantState,
  type Scenario,
  type Setpoints,
  type SimEvent,
  DEFAULT_SETPOINTS,
  TOPOLOGY,
} from './types.js';

export interface SimModel {
  plant: Plant & { timezone?: string };
  scenario: Scenario;
  setpoints: Setpoints;
  state: PlantState;
  equipment: Map<string, Equipment>;
}

export const VALVE_TRAVEL_PCT_PER_SEC = 20; // full stroke in 5 s
const EMPTY_LEVEL_PCT = 1;
const RESTART_LEVEL_PCT = 5;

const clamp = (v: number, lo: number, hi: number) => Math.min(hi, Math.max(lo, v));
const round = (v: number, d = 2) => Math.round(v * 10 ** d) / 10 ** d;

export function sp(model: SimModel, key: string): number {
  const v = model.setpoints[key];
  return typeof v === 'number' && Number.isFinite(v) ? v : DEFAULT_SETPOINTS[key];
}

function eq(model: SimModel, tag: string): Equipment {
  const e = model.equipment.get(tag);
  if (!e) throw new Error(`Equipment ${tag} missing in plant ${model.plant.id}`);
  return e;
}

/** Diurnal demand multiplier: morning (~07:00) and evening (~19:00) peaks. */
export function diurnalFactor(simTime: Date, timeZone?: string): number {
  let hour = simTime.getUTCHours() + simTime.getUTCMinutes() / 60;
  if (timeZone) {
    try {
      const parts = new Intl.DateTimeFormat('en-US', {
        timeZone,
        hour: 'numeric',
        minute: 'numeric',
        hourCycle: 'h23',
      }).formatToParts(simTime);
      const h = Number(parts.find((p) => p.type === 'hour')?.value ?? hour);
      const m = Number(parts.find((p) => p.type === 'minute')?.value ?? 0);
      hour = h + m / 60;
    } catch {
      /* fall back to UTC */
    }
  }
  const peaks = 0.2 * Math.sin((2 * Math.PI * (hour - 4)) / 12);
  const night = hour < 5 ? -0.15 : 0;
  return 1 + peaks + night;
}

/** Whether a pump can actually run, and why not. */
export function pumpAvailability(
  pump: Equipment,
  suctionTank: Equipment,
): { ok: boolean; state: string; reason: string | null } {
  if (pump.in_maintenance) {
    return { ok: false, state: 'locked_out', reason: pump.interlock_reason?.startsWith('Locked out') ? pump.interlock_reason : 'Locked out for maintenance' };
  }
  if (pump.fault_active) return { ok: false, state: 'fault', reason: 'Motor protection trip — reset required' };
  // Hysteresis: once interlocked, the pump needs RESTART_LEVEL_PCT to restart (prevents chattering).
  const minLevel = pump.actual_state === 'interlocked' ? RESTART_LEVEL_PCT : EMPTY_LEVEL_PCT;
  if ((suctionTank.level_pct ?? 0) <= minLevel) {
    return { ok: false, state: 'interlocked', reason: `Low suction level — ${suctionTank.tag} empty` };
  }
  return { ok: true, state: 'running', reason: null };
}

function isPumpUsable(p: Equipment) {
  return !p.in_maintenance && !p.fault_active;
}

/** AUTO control logic: computes requested_state for every equipment in AUTO. */
export function applyAutoLogic(model: SimModel) {
  const t101 = eq(model, TOPOLOGY.rawTank);
  const t102 = eq(model, TOPOLOGY.clearwell);
  const l1 = t101.level_pct ?? 0;
  const l2 = t102.level_pct ?? 0;

  // Inlet valve with 10% hysteresis.
  const xv101 = eq(model, TOPOLOGY.inletValve);
  if (xv101.control_mode === 'auto') {
    const hi = sp(model, 't101_high_close');
    if (l1 >= hi) xv101.requested_state = 'closed';
    else if (l1 <= hi - 10) xv101.requested_state = 'open';
  }

  // Transfer pumps (duty/standby).
  const pumps = TOPOLOGY.transferPumps.map((t) => eq(model, t));
  const anyTransferRequested = pumps.some((p) => p.requested_state === 'running');
  const lowStop = sp(model, 't101_low_stop');
  const highStop = sp(model, 't102_high_stop');
  const stopCond = l1 <= lowStop || l2 >= highStop;
  const startCond = l1 >= lowStop + 10 && l2 <= highStop - 8;
  const transferWanted = anyTransferRequested ? !stopCond : startCond;

  const manualRunning = pumps.some((p) => p.control_mode === 'manual' && p.requested_state === 'running');
  let dutyAssigned = manualRunning; // a manual pump already covers the duty
  for (const p of pumps) {
    if (p.control_mode !== 'auto') continue;
    if (transferWanted && !dutyAssigned && isPumpUsable(p)) {
      p.requested_state = 'running';
      dutyAssigned = true;
    } else {
      p.requested_state = 'stopped';
    }
  }

  const xv102 = eq(model, TOPOLOGY.transferValve);
  if (xv102.control_mode === 'auto') {
    xv102.requested_state = pumps.some((p) => p.requested_state === 'running') ? 'open' : 'closed';
  }

  // Distribution pump with 8% hysteresis.
  const p201 = eq(model, TOPOLOGY.distPump);
  if (p201.control_mode === 'auto') {
    const lo = sp(model, 't102_low_stop');
    if (!isPumpUsable(p201)) p201.requested_state = 'stopped';
    else if (p201.requested_state === 'running') p201.requested_state = l2 <= lo ? 'stopped' : 'running';
    else p201.requested_state = l2 >= lo + 8 ? 'running' : 'stopped';
  }

  const xv201 = eq(model, TOPOLOGY.distValve);
  if (xv201.control_mode === 'auto') {
    xv201.requested_state = p201.requested_state === 'running' ? 'open' : 'closed';
  }
}

function stepValve(v: Equipment, dt: number, events: SimEvent[]) {
  const prev = v.actual_state;
  const pos = v.position_pct ?? 0;
  if (v.in_maintenance) {
    v.actual_state = 'locked_out';
    v.interlock_reason = 'Locked out for maintenance';
    return;
  }
  if (v.fault_active) {
    v.actual_state = 'fault';
    v.interlock_reason = 'Actuator fault';
    return;
  }
  v.interlock_reason = null;
  const target = v.requested_state === 'open' ? 100 : 0;
  const delta = VALVE_TRAVEL_PCT_PER_SEC * dt;
  const next = target > pos ? Math.min(target, pos + delta) : Math.max(target, pos - delta);
  v.position_pct = round(next, 1);
  v.actual_state = next >= 100 ? 'open' : next <= 0 ? 'closed' : target > pos ? 'opening' : 'closing';
  if (prev !== v.actual_state && (v.actual_state === 'open' || v.actual_state === 'closed')) {
    events.push({
      category: 'process',
      severity: 'info',
      tag: v.tag,
      message: `${v.tag} ${v.actual_state === 'open' ? 'fully open' : 'closed'}${v.control_mode === 'auto' ? ' (auto)' : ''}`,
    });
  }
}

function stepPump(p: Equipment, suction: Equipment, dt: number, speedPct: number, events: SimEvent[]) {
  const prev = p.actual_state;
  const wantsRun = p.requested_state === 'running';
  const avail = pumpAvailability(p, suction);

  if (!avail.ok && (wantsRun || avail.state === 'locked_out' || avail.state === 'fault')) {
    p.actual_state = avail.state;
    p.interlock_reason = avail.reason;
  } else if (wantsRun) {
    p.actual_state = 'running';
    p.interlock_reason = null;
  } else {
    p.actual_state = 'stopped';
    p.interlock_reason = null;
  }

  p.speed_pct = p.actual_state === 'running' ? speedPct : 0;
  if (p.actual_state === 'running') p.run_hours = round((p.run_hours ?? 0) + dt / 3600, 3);

  if (prev !== p.actual_state) {
    const auto = p.control_mode === 'auto' ? ' (auto)' : '';
    if (p.actual_state === 'running') {
      p.starts_count = (p.starts_count ?? 0) + 1;
      events.push({ category: 'process', severity: 'info', tag: p.tag, message: `${p.tag} started${auto}` });
    } else if (p.actual_state === 'stopped') {
      events.push({ category: 'process', severity: 'info', tag: p.tag, message: `${p.tag} stopped${auto}` });
    } else if (p.actual_state === 'fault') {
      events.push({ category: 'process', severity: 'critical', tag: p.tag, message: `${p.tag} tripped — ${p.interlock_reason}` });
    } else if (p.actual_state === 'interlocked') {
      events.push({ category: 'process', severity: 'warning', tag: p.tag, message: `${p.tag} start inhibited — ${p.interlock_reason}` });
    } else if (p.actual_state === 'locked_out' && wantsRun) {
      events.push({ category: 'process', severity: 'warning', tag: p.tag, message: `${p.tag} cannot run — locked out for maintenance` });
    }
  }
}

function tankState(level: number, hi: number, lo: number) {
  if (level >= 99.5) return 'overflow';
  if (level >= hi) return 'high';
  if (level <= EMPTY_LEVEL_PCT) return 'empty';
  if (level <= lo) return 'low';
  return 'normal';
}

/**
 * Advances the model by dt seconds (in place). Returns process events.
 * `rand` is injectable for deterministic tests.
 */
export function simulateStep(model: SimModel, dt: number, rand: () => number = Math.random): SimEvent[] {
  const events: SimEvent[] = [];
  const noise = (amp: number) => 1 + (rand() * 2 - 1) * amp;

  const xv101 = eq(model, TOPOLOGY.inletValve);
  const t101 = eq(model, TOPOLOGY.rawTank);
  const pumps = TOPOLOGY.transferPumps.map((t) => eq(model, t));
  const xv102 = eq(model, TOPOLOGY.transferValve);
  const t102 = eq(model, TOPOLOGY.clearwell);
  const p201 = eq(model, TOPOLOGY.distPump);
  const xv201 = eq(model, TOPOLOGY.distValve);

  applyAutoLogic(model);

  // Actuators
  for (const v of [xv101, xv102, xv201]) stepValve(v, dt, events);
  const transferSpeed = clamp(sp(model, 'transfer_speed'), 0, 100);
  for (const p of pumps) stepPump(p, t101, dt, transferSpeed, events);
  stepPump(p201, t102, dt, 100, events);

  // Flows (m³/h)
  const simTime = new Date(model.state.sim_time);
  const inflowAvail = model.plant.base_inflow_m3h * model.scenario.inflow_factor * noise(0.03);
  const inlet = inflowAvail * ((xv101.position_pct ?? 0) / 100);

  const running = pumps.filter((p) => p.actual_state === 'running');
  const transferCapacity = running.reduce((s, p) => s + (p.rated_flow_m3h ?? 0) * ((p.speed_pct ?? 0) / 100), 0);
  const xv102Open = (xv102.position_pct ?? 0) / 100;
  const v1 = t101.volume_m3 ?? 0;
  let transfer = transferCapacity * xv102Open * noise(0.02);
  transfer = Math.min(transfer, (v1 * 3600) / dt + inlet); // cannot pump more than is available

  const demand =
    model.plant.base_demand_m3h *
    model.scenario.demand_factor *
    diurnalFactor(simTime, model.plant.timezone) *
    noise(0.04);
  const p201Running = p201.actual_state === 'running';
  const xv201Open = (xv201.position_pct ?? 0) / 100;
  const v2 = t102.volume_m3 ?? 0;
  let distribution = p201Running ? Math.min(demand, p201.rated_flow_m3h ?? demand) * xv201Open : 0;
  distribution = Math.min(distribution, (v2 * 3600) / dt + transfer);

  // Mass balance
  const cap1 = t101.capacity_m3 ?? 1;
  const cap2 = t102.capacity_m3 ?? 1;
  t101.volume_m3 = round(clamp(v1 + ((inlet - transfer) * dt) / 3600, 0, cap1), 3);
  t102.volume_m3 = round(clamp(v2 + ((transfer - distribution) * dt) / 3600, 0, cap2), 3);
  t101.level_pct = round((t101.volume_m3 / cap1) * 100, 2);
  t102.level_pct = round((t102.volume_m3 / cap2) * 100, 2);

  const hi = sp(model, 'level_alarm_high');
  const lo = sp(model, 'level_alarm_low');
  t101.actual_state = tankState(t101.level_pct, hi, lo);
  t102.actual_state = tankState(t102.level_pct, hi, lo);

  // Pressures (bar)
  const transferDeadhead = running.length > 0 && xv102Open < 0.05;
  const transferPressure =
    running.length === 0 ? 0.3 : transferDeadhead ? 6.8 * noise(0.02) : (2.4 + 1.1 * (transferSpeed / 100)) * noise(0.02);
  const distDeadhead = p201Running && xv201Open < 0.05;
  const distRatio = (p201.rated_flow_m3h ?? 1) > 0 ? distribution / (p201.rated_flow_m3h ?? 1) : 0;
  const distPressure = !p201Running ? 0.4 : distDeadhead ? 7.2 * noise(0.02) : (4.8 - 0.9 * distRatio) * noise(0.02);

  // Per-asset readings
  xv101.flow_m3h = round(inlet, 1);
  xv102.flow_m3h = round(transfer, 1);
  xv201.flow_m3h = round(distribution, 1);
  for (const p of pumps) {
    p.flow_m3h = p.actual_state === 'running' ? round(transfer / Math.max(running.length, 1), 1) : 0;
    p.pressure_bar = p.actual_state === 'running' ? round(transferPressure, 2) : 0.3;
  }
  p201.flow_m3h = round(distribution, 1);
  p201.pressure_bar = round(distPressure, 2);

  const instruments: Record<string, number> = {
    'LT-101': t101.level_pct,
    'LT-102': t102.level_pct,
    'FT-101': round(inlet, 1),
    'FT-102': round(transfer, 1),
    'FT-201': round(distribution, 1),
    'PT-101': round(transferPressure, 2),
    'PT-201': round(distPressure, 2),
  };
  for (const [tag, value] of Object.entries(instruments)) {
    const inst = model.equipment.get(tag);
    if (inst) inst.value = value;
  }

  // Plant state
  const s = model.state;
  s.sim_time = new Date(simTime.getTime() + dt * 1000).toISOString();
  s.inlet_flow_m3h = round(inlet, 1);
  s.transfer_flow_m3h = round(transfer, 1);
  s.distribution_flow_m3h = round(distribution, 1);
  s.demand_m3h = round(demand, 1);
  s.transfer_pressure_bar = round(transferPressure, 2);
  s.distribution_pressure_bar = round(distPressure, 2);

  return events;
}

/** Alarm conditions that are currently true for the model. */
export function evaluateAlarms(model: SimModel): AlarmCondition[] {
  const out: AlarmCondition[] = [];
  const hi = sp(model, 'level_alarm_high');
  const lo = sp(model, 'level_alarm_low');
  const hp = sp(model, 'pressure_alarm_high');

  for (const tag of [TOPOLOGY.rawTank, TOPOLOGY.clearwell]) {
    const t = eq(model, tag);
    const l = t.level_pct ?? 0;
    if (l >= 99.5) out.push({ code: `${tag}.OVERFLOW`, tag, priority: 'critical', value: l, message: `${t.name} overflowing` });
    else if (l >= hi) out.push({ code: `${tag}.HIGH`, tag, priority: 'high', value: l, message: `${t.name} level high` });
    if (l <= EMPTY_LEVEL_PCT) out.push({ code: `${tag}.EMPTY`, tag, priority: 'high', value: l, message: `${t.name} empty` });
    else if (l <= lo) out.push({ code: `${tag}.LOW`, tag, priority: 'medium', value: l, message: `${t.name} level low` });
  }

  for (const tag of [...TOPOLOGY.transferPumps, TOPOLOGY.distPump]) {
    const p = eq(model, tag);
    if (p.actual_state === 'fault') {
      out.push({ code: `${tag}.FAULT`, tag, priority: 'critical', value: null, message: `${tag} fault — ${p.interlock_reason ?? 'trip'}` });
    }
    if (p.actual_state === 'interlocked') {
      out.push({ code: `${tag}.INTERLOCK`, tag, priority: 'high', value: null, message: `${tag} start inhibited — ${p.interlock_reason}` });
    }
    if (p.in_maintenance) {
      const extra = TOPOLOGY.transferPumps.includes(tag as never) ? ' — no standby transfer capacity' : '';
      out.push({ code: `${tag}.LOTO`, tag, priority: 'low', value: null, message: `${tag} locked out for maintenance${extra}` });
    }
  }

  const pt101 = model.equipment.get('PT-101')?.value ?? 0;
  const pt201 = model.equipment.get('PT-201')?.value ?? 0;
  if (pt101 >= hp) out.push({ code: 'PT-101.HP', tag: 'PT-101', priority: 'high', value: pt101, message: 'Transfer discharge pressure high — check XV-102' });
  if (pt201 >= hp) out.push({ code: 'PT-201.HP', tag: 'PT-201', priority: 'high', value: pt201, message: 'Distribution header pressure high — check XV-201' });

  // Demand not met (distribution stopped while there is demand)
  const p201 = eq(model, TOPOLOGY.distPump);
  if (p201.actual_state !== 'running' && model.state.demand_m3h > 0) {
    out.push({ code: 'PT-201.LP', tag: 'PT-201', priority: 'high', value: pt201, message: 'Distribution pressure low — network demand not supplied' });
  }

  return out;
}

export function plantStatus(conditions: AlarmCondition[]): PlantState['status'] {
  if (conditions.some((c) => c.priority === 'critical' || c.priority === 'high')) return 'alarm';
  if (conditions.length > 0) return 'warning';
  return 'normal';
}
