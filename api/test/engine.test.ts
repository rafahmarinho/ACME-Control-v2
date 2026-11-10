import { describe, expect, it } from 'vitest';
import { evaluateAlarms, simulateStep, type SimModel } from '../src/sim/engine.js';
import { AlarmTracker } from '../src/sim/alarm-tracker.js';
import { DEFAULT_SETPOINTS, type Equipment, type SimEvent } from '../src/sim/types.js';

const rand = () => 0.5; // no noise

function eq(tag: string, kind: Equipment['kind'], extra: Partial<Equipment> = {}): Equipment {
  return {
    id: `id-${tag}`, plant_id: 'p1', tag, name: tag, kind, area: 'A',
    control_mode: kind === 'pump' || kind === 'valve' ? 'auto' : null,
    requested_state: null, actual_state: 'normal', interlock_reason: null,
    in_maintenance: false, fault_active: false,
    level_pct: null, volume_m3: null, capacity_m3: null, rated_flow_m3h: null, flow_m3h: null,
    speed_pct: null, position_pct: null, pressure_bar: null, value: null, unit: null,
    run_hours: 0, starts_count: 0, health_pct: 100,
    ...extra,
  };
}

function tank(tag: string, cap: number, level: number) {
  return eq(tag, 'tank', { capacity_m3: cap, level_pct: level, volume_m3: (cap * level) / 100 });
}

function model(overrides: { t1?: number; t2?: number } = {}): SimModel {
  const items = [
    eq('XV-101', 'valve', { requested_state: 'open', actual_state: 'open', position_pct: 100 }),
    tank('T-101', 500, overrides.t1 ?? 60),
    eq('P-101', 'pump', { rated_flow_m3h: 240, requested_state: 'running', actual_state: 'running' }),
    eq('P-102', 'pump', { rated_flow_m3h: 240, requested_state: 'stopped', actual_state: 'stopped' }),
    eq('XV-102', 'valve', { requested_state: 'open', actual_state: 'open', position_pct: 100 }),
    tank('T-102', 800, overrides.t2 ?? 60),
    eq('P-201', 'pump', { rated_flow_m3h: 260, requested_state: 'running', actual_state: 'running' }),
    eq('XV-201', 'valve', { requested_state: 'open', actual_state: 'open', position_pct: 100 }),
    ...['LT-101', 'LT-102', 'FT-101', 'FT-102', 'FT-201', 'PT-101', 'PT-201'].map((t) => eq(t, 'instrument')),
  ];
  return {
    plant: { id: 'p1', name: 'Test', base_inflow_m3h: 200, base_demand_m3h: 180, timezone: 'UTC' },
    scenario: { id: 'normal', name: 'Normal', inflow_factor: 1, demand_factor: 1, fault_tags: [] },
    setpoints: { ...DEFAULT_SETPOINTS },
    state: {
      plant_id: 'p1', scenario_id: 'normal', auto_run: true, sim_time: '2026-11-10T12:00:00Z',
      last_tick_at: '2026-11-10T12:00:00Z', last_measurement_at: null, tick: 0,
      inlet_flow_m3h: 0, transfer_flow_m3h: 0, distribution_flow_m3h: 0, demand_m3h: 0,
      transfer_pressure_bar: 0, distribution_pressure_bar: 0, status: 'normal',
    },
    equipment: new Map(items.map((e) => [e.tag, e])),
  };
}

const get = (m: SimModel, tag: string) => m.equipment.get(tag)!;
const run = (m: SimModel, seconds: number, dt = 5) => {
  const events: SimEvent[] = [];
  for (let t = 0; t < seconds; t += dt) events.push(...simulateStep(m, dt, rand));
  return events;
};

describe('process simulation', () => {
  it('raw water tank fills when inlet is open and transfer is stopped', () => {
    const m = model({ t1: 40 });
    for (const t of ['P-101', 'P-102']) {
      get(m, t).control_mode = 'manual';
      get(m, t).requested_state = 'stopped';
    }
    const before = get(m, 'T-101').level_pct!;
    run(m, 600);
    expect(get(m, 'T-101').level_pct!).toBeGreaterThan(before + 5);
  });

  it('raw water tank drains when the inlet valve is closed manually', () => {
    const m = model({ t1: 50 });
    const xv = get(m, 'XV-101');
    xv.control_mode = 'manual';
    xv.requested_state = 'closed';
    run(m, 600);
    expect(xv.actual_state).toBe('closed');
    expect(get(m, 'T-101').level_pct!).toBeLessThan(50);
  });

  it('valves travel over several seconds (requested vs actual)', () => {
    const m = model();
    const xv = get(m, 'XV-201');
    xv.control_mode = 'manual';
    xv.requested_state = 'closed';
    simulateStep(m, 2, rand);
    expect(xv.actual_state).toBe('closing');
    expect(xv.position_pct).toBe(60);
    simulateStep(m, 5, rand);
    expect(xv.actual_state).toBe('closed');
  });

  it('a pump does not run when its suction tank is empty', () => {
    const m = model({ t1: 0.5 });
    const p = get(m, 'P-101');
    p.control_mode = 'manual';
    p.requested_state = 'running';
    get(m, 'XV-101').control_mode = 'manual';
    get(m, 'XV-101').requested_state = 'closed';
    get(m, 'XV-101').position_pct = 0;
    simulateStep(m, 5, rand);
    expect(p.requested_state).toBe('running');
    expect(p.actual_state).toBe('interlocked');
    expect(p.interlock_reason).toMatch(/empty/i);
    expect(p.flow_m3h).toBe(0);
    expect(evaluateAlarms(m).map((a) => a.code)).toContain('P-101.INTERLOCK');
  });

  it('an interlocked pump restarts only after the suction tank recovers (hysteresis)', () => {
    const m = model({ t1: 0.5 });
    const p = get(m, 'P-101');
    p.control_mode = 'manual';
    p.requested_state = 'running';
    simulateStep(m, 1, rand);
    expect(p.actual_state).toBe('interlocked');
    const t = get(m, 'T-101');
    t.level_pct = 3;
    t.volume_m3 = 15;
    simulateStep(m, 1, rand);
    expect(p.actual_state).toBe('interlocked'); // 3 % < restart level
    t.level_pct = 6;
    t.volume_m3 = 30;
    simulateStep(m, 1, rand);
    expect(p.actual_state).toBe('running');
  });

  it('a pump in maintenance is locked out even when start is requested', () => {
    const m = model();
    const p = get(m, 'P-101');
    p.control_mode = 'manual';
    p.requested_state = 'running';
    p.in_maintenance = true;
    simulateStep(m, 5, rand);
    expect(p.actual_state).toBe('locked_out');
    expect(p.flow_m3h).toBe(0);
  });

  it('standby pump takes over in AUTO when the duty pump faults', () => {
    const m = model({ t1: 60, t2: 50 });
    get(m, 'P-101').fault_active = true;
    const events = run(m, 10);
    expect(get(m, 'P-101').actual_state).toBe('fault');
    expect(get(m, 'P-102').actual_state).toBe('running');
    expect(events.some((e) => e.message.includes('P-101 tripped'))).toBe(true);
    expect(evaluateAlarms(m).map((a) => a.code)).toContain('P-101.FAULT');
  });

  it('AUTO stops transfer when the clearwell reaches its high setpoint', () => {
    const m = model({ t2: 93 });
    simulateStep(m, 5, rand);
    expect(get(m, 'P-101').requested_state).toBe('stopped');
    expect(get(m, 'P-101').actual_state).toBe('stopped');
  });

  it('closing the discharge valve on a running pump deadheads it (high pressure alarm)', () => {
    const m = model();
    const xv = get(m, 'XV-102');
    xv.control_mode = 'manual';
    xv.requested_state = 'closed';
    get(m, 'P-101').control_mode = 'manual';
    run(m, 10);
    expect(get(m, 'PT-101').value!).toBeGreaterThan(6);
    expect(evaluateAlarms(m).map((a) => a.code)).toContain('PT-101.HP');
  });

  it('mass balance: clearwell drains when distribution exceeds transfer', () => {
    const m = model({ t2: 50 });
    m.scenario.demand_factor = 1.6;
    for (const t of ['P-101', 'P-102']) {
      get(m, t).control_mode = 'manual';
      get(m, t).requested_state = 'stopped';
    }
    run(m, 900);
    expect(get(m, 'T-102').level_pct!).toBeLessThan(50);
  });
});

describe('alarm lifecycle', () => {
  it('raises, returns-to-normal and closes after acknowledgement', () => {
    const m = model();
    const tracker = new AlarmTracker('p1', [], m.equipment);
    const events: SimEvent[] = [];
    tracker.apply([{ code: 'T-101.HIGH', tag: 'T-101', priority: 'high', message: 'High', value: 96 }], m.state.sim_time, events);
    expect(tracker.raised).toHaveLength(1);
    const a = tracker.openAlarms[0];
    expect(a.state).toBe('active');
    tracker.apply([], m.state.sim_time, events);
    expect(a.state).toBe('rtn_unack');
    // condition returns → re-activated
    tracker.apply([{ code: 'T-101.HIGH', tag: 'T-101', priority: 'high', message: 'High', value: 96 }], m.state.sim_time, events);
    expect(a.state).toBe('active');
    a.state = 'acknowledged';
    tracker.apply([], m.state.sim_time, events);
    expect(a.state).toBe('closed');
    expect(tracker.openAlarms).toHaveLength(0);
  });
});
