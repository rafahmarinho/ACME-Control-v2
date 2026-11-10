// Domain types shared by the simulation engine and the services.
// Column names mirror the Supabase tables (snake_case).

export type EquipmentKind = 'tank' | 'pump' | 'valve' | 'instrument';
export type ControlMode = 'auto' | 'manual';
export type AlarmPriority = 'critical' | 'high' | 'medium' | 'low';
export type AlarmState = 'active' | 'acknowledged' | 'rtn_unack' | 'closed';
export type UserRole = 'operator' | 'engineer' | 'supervisor' | 'maintenance';

export interface Equipment {
  id: string;
  plant_id: string;
  tag: string;
  name: string;
  kind: EquipmentKind;
  area: string;
  control_mode: ControlMode | null;
  requested_state: string | null;
  actual_state: string;
  interlock_reason: string | null;
  in_maintenance: boolean;
  fault_active: boolean;
  level_pct: number | null;
  volume_m3: number | null;
  capacity_m3: number | null;
  rated_flow_m3h: number | null;
  flow_m3h: number | null;
  speed_pct: number | null;
  position_pct: number | null;
  pressure_bar: number | null;
  value: number | null;
  unit: string | null;
  run_hours: number;
  starts_count: number;
  health_pct: number;
  updated_at?: string;
  [extra: string]: unknown;
}

export interface Plant {
  id: string;
  name: string;
  base_inflow_m3h: number;
  base_demand_m3h: number;
}

export interface Scenario {
  id: string;
  name: string;
  inflow_factor: number;
  demand_factor: number;
  fault_tags: string[];
}

export interface PlantState {
  plant_id: string;
  scenario_id: string;
  auto_run: boolean;
  sim_time: string;
  last_tick_at: string;
  last_measurement_at: string | null;
  tick: number;
  inlet_flow_m3h: number;
  transfer_flow_m3h: number;
  distribution_flow_m3h: number;
  demand_m3h: number;
  transfer_pressure_bar: number;
  distribution_pressure_bar: number;
  status: 'normal' | 'warning' | 'alarm';
  updated_at?: string;
}

export type Setpoints = Record<string, number>;

export interface AlarmCondition {
  code: string;
  tag: string;
  message: string;
  priority: AlarmPriority;
  value: number | null;
}

export interface SimEvent {
  category: 'process' | 'alarm' | 'simulation' | 'command';
  severity: 'info' | 'warning' | 'critical';
  message: string;
  tag?: string;
}

export interface Alarm {
  id: string;
  plant_id: string;
  equipment_id: string | null;
  code: string;
  tag: string;
  message: string;
  priority: AlarmPriority;
  state: AlarmState;
  value: number | null;
  raised_at: string;
  sim_raised_at: string | null;
  acknowledged_by: string | null;
  acknowledged_by_name: string | null;
  acknowledged_at: string | null;
  ack_comment: string | null;
  cleared_at: string | null;
}

export const DEFAULT_SETPOINTS: Setpoints = {
  t101_high_close: 90,
  t101_low_stop: 15,
  t102_high_stop: 92,
  t102_low_stop: 12,
  transfer_speed: 85,
  level_alarm_high: 95,
  level_alarm_low: 10,
  pressure_alarm_high: 6,
};

/** Fixed process topology shared by both demo plants. */
export const TOPOLOGY = {
  inletValve: 'XV-101',
  rawTank: 'T-101',
  transferPumps: ['P-101', 'P-102'] as const,
  transferValve: 'XV-102',
  clearwell: 'T-102',
  distPump: 'P-201',
  distValve: 'XV-201',
} as const;

/** Trend tags recorded into public.measurements. */
export const TREND_TAGS = ['LT-101', 'LT-102', 'FT-101', 'FT-102', 'FT-201', 'PT-101', 'PT-201'] as const;
