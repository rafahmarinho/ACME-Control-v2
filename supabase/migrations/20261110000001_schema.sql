-- ACME Control — core schema
-- Water treatment plant monitoring & control (simulated process).

-- gen_random_uuid() is built into PostgreSQL 13+, no extension required.

-- ---------------------------------------------------------------------------
-- Types
-- ---------------------------------------------------------------------------
create type public.user_role as enum ('operator', 'engineer', 'supervisor', 'maintenance');
create type public.equipment_kind as enum ('tank', 'pump', 'valve', 'instrument');

-- ---------------------------------------------------------------------------
-- Profiles (1:1 with auth.users)
-- ---------------------------------------------------------------------------
create table public.profiles (
  id          uuid primary key references auth.users (id) on delete cascade,
  email       text not null,
  full_name   text not null default '',
  role        public.user_role not null default 'operator',
  job_title   text,
  phone       text,
  avatar_url  text,
  preferences jsonb not null default '{}'::jsonb,
  created_at  timestamptz not null default now(),
  updated_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Plants, scenarios and live process state
-- ---------------------------------------------------------------------------
create table public.scenarios (
  id            text primary key,
  name          text not null,
  description   text not null,
  inflow_factor numeric not null default 1,
  demand_factor numeric not null default 1,
  fault_tags    text[] not null default '{}',
  sort_order    int not null default 0
);

create table public.plants (
  id                  text primary key,
  name                text not null,
  code                text not null unique,
  location            text not null,
  description         text,
  timezone            text not null default 'UTC',
  design_capacity_m3h numeric not null,
  base_inflow_m3h     numeric not null,
  base_demand_m3h     numeric not null,
  latitude            numeric,
  longitude           numeric,
  commissioned_on     date,
  created_at          timestamptz not null default now()
);

create table public.plant_state (
  plant_id                  text primary key references public.plants (id) on delete cascade,
  scenario_id               text not null default 'normal' references public.scenarios (id),
  auto_run                  boolean not null default true,
  sim_time                  timestamptz not null default now(),
  last_tick_at              timestamptz not null default now(),
  last_measurement_at       timestamptz,
  tick                      bigint not null default 0,
  inlet_flow_m3h            numeric not null default 0,
  transfer_flow_m3h         numeric not null default 0,
  distribution_flow_m3h     numeric not null default 0,
  demand_m3h                numeric not null default 0,
  transfer_pressure_bar     numeric not null default 0,
  distribution_pressure_bar numeric not null default 0,
  status                    text not null default 'normal' check (status in ('normal', 'warning', 'alarm')),
  updated_at                timestamptz not null default now()
);

create table public.equipment (
  id               uuid primary key default gen_random_uuid(),
  plant_id         text not null references public.plants (id) on delete cascade,
  tag              text not null,
  name             text not null,
  kind             public.equipment_kind not null,
  area             text not null,
  description      text,
  manufacturer     text,
  model            text,
  serial_number    text,
  installed_on     date,
  control_mode     text check (control_mode in ('auto', 'manual')),
  requested_state  text,
  actual_state     text not null default 'normal',
  interlock_reason text,
  in_maintenance   boolean not null default false,
  fault_active     boolean not null default false,
  level_pct        numeric,
  volume_m3        numeric,
  capacity_m3      numeric,
  rated_flow_m3h   numeric,
  flow_m3h         numeric,
  speed_pct        numeric,
  position_pct     numeric,
  pressure_bar     numeric,
  value            numeric,
  unit             text,
  run_hours        numeric not null default 0,
  starts_count     int not null default 0,
  health_pct       numeric not null default 100,
  sort_order       int not null default 0,
  updated_at       timestamptz not null default now(),
  unique (plant_id, tag)
);
create index equipment_plant_idx on public.equipment (plant_id, sort_order);

create table public.measurements (
  id       bigint generated always as identity primary key,
  plant_id text not null references public.plants (id) on delete cascade,
  tag      text not null,
  value    numeric not null,
  ts       timestamptz not null
);
create index measurements_lookup_idx on public.measurements (plant_id, tag, ts desc);

-- ---------------------------------------------------------------------------
-- Alarms & commands
-- ---------------------------------------------------------------------------
create table public.alarms (
  id                   uuid primary key default gen_random_uuid(),
  plant_id             text not null references public.plants (id) on delete cascade,
  equipment_id         uuid references public.equipment (id) on delete set null,
  code                 text not null,
  tag                  text not null,
  message              text not null,
  priority             text not null check (priority in ('critical', 'high', 'medium', 'low')),
  state                text not null default 'active' check (state in ('active', 'acknowledged', 'rtn_unack', 'closed')),
  value                numeric,
  raised_at            timestamptz not null default now(),
  sim_raised_at        timestamptz,
  acknowledged_by      uuid references public.profiles (id) on delete set null,
  acknowledged_by_name text,
  acknowledged_at      timestamptz,
  ack_comment          text,
  cleared_at           timestamptz
);
create index alarms_plant_state_idx on public.alarms (plant_id, state, raised_at desc);

create table public.commands (
  id                uuid primary key default gen_random_uuid(),
  plant_id          text not null references public.plants (id) on delete cascade,
  equipment_id      uuid references public.equipment (id) on delete cascade,
  tag               text not null,
  action            text not null check (action in ('start', 'stop', 'open', 'close', 'set_auto', 'set_manual')),
  requested_state   text,
  status            text not null default 'pending'
                    check (status in ('pending', 'in_progress', 'completed', 'blocked', 'rejected', 'failed')),
  result_message    text,
  requested_by      uuid references public.profiles (id) on delete set null,
  requested_by_name text,
  created_at        timestamptz not null default now(),
  completed_at      timestamptz
);
create index commands_plant_idx on public.commands (plant_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Setpoints & change proposals
-- ---------------------------------------------------------------------------
create table public.setpoints (
  id              uuid primary key default gen_random_uuid(),
  plant_id        text not null references public.plants (id) on delete cascade,
  key             text not null,
  name            text not null,
  description     text,
  category        text not null default 'Control',
  unit            text not null,
  value           numeric not null,
  min_value       numeric not null,
  max_value       numeric not null,
  step            numeric not null default 1,
  updated_by_name text,
  updated_at      timestamptz not null default now(),
  unique (plant_id, key)
);

create table public.setpoint_proposals (
  id               uuid primary key default gen_random_uuid(),
  setpoint_id      uuid not null references public.setpoints (id) on delete cascade,
  plant_id         text not null references public.plants (id) on delete cascade,
  setpoint_name    text not null,
  unit             text not null,
  current_value    numeric not null,
  proposed_value   numeric not null,
  reason           text not null,
  status           text not null default 'pending' check (status in ('pending', 'approved', 'rejected', 'withdrawn')),
  proposed_by      uuid references public.profiles (id) on delete set null,
  proposed_by_name text,
  reviewed_by      uuid references public.profiles (id) on delete set null,
  reviewed_by_name text,
  review_note      text,
  created_at       timestamptz not null default now(),
  reviewed_at      timestamptz
);
create index proposals_plant_idx on public.setpoint_proposals (plant_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Maintenance
-- ---------------------------------------------------------------------------
create sequence public.maintenance_order_seq start 24001;

create table public.maintenance_orders (
  id                uuid primary key default gen_random_uuid(),
  number            text not null unique default ('WO-' || nextval('public.maintenance_order_seq')::text),
  plant_id          text not null references public.plants (id) on delete cascade,
  equipment_id      uuid references public.equipment (id) on delete set null,
  equipment_tag     text,
  title             text not null,
  description       text,
  type              text not null default 'corrective' check (type in ('corrective', 'preventive', 'inspection')),
  priority          text not null default 'medium' check (priority in ('low', 'medium', 'high', 'urgent')),
  status            text not null default 'requested'
                    check (status in ('requested', 'scheduled', 'in_progress', 'completed', 'cancelled')),
  requires_lockout  boolean not null default false,
  lockout_applied   boolean not null default false,
  assigned_to       uuid references public.profiles (id) on delete set null,
  assigned_to_name  text,
  created_by        uuid references public.profiles (id) on delete set null,
  created_by_name   text,
  due_date          date,
  started_at        timestamptz,
  completed_at      timestamptz,
  completion_notes  text,
  external_ref      text,
  created_at        timestamptz not null default now(),
  updated_at        timestamptz not null default now()
);
create index maintenance_plant_idx on public.maintenance_orders (plant_id, status, created_at desc);

create table public.maintenance_attachments (
  id           uuid primary key default gen_random_uuid(),
  order_id     uuid not null references public.maintenance_orders (id) on delete cascade,
  file_path    text not null,
  file_name    text not null,
  size_bytes   bigint,
  content_type text,
  uploaded_by  uuid references public.profiles (id) on delete set null,
  uploaded_by_name text,
  created_at   timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Shift handover
-- ---------------------------------------------------------------------------
create table public.shift_handovers (
  id                   uuid primary key default gen_random_uuid(),
  plant_id             text not null references public.plants (id) on delete cascade,
  shift                text not null check (shift in ('day', 'evening', 'night')),
  shift_date           date not null default current_date,
  author_id            uuid references public.profiles (id) on delete set null,
  author_name          text,
  summary              text not null,
  open_issues          text,
  safety_notes         text,
  equipment_notes      text,
  snapshot             jsonb not null default '{}'::jsonb,
  status               text not null default 'submitted' check (status in ('submitted', 'acknowledged')),
  acknowledged_by      uuid references public.profiles (id) on delete set null,
  acknowledged_by_name text,
  acknowledged_at      timestamptz,
  created_at           timestamptz not null default now()
);
create index handovers_plant_idx on public.shift_handovers (plant_id, created_at desc);

-- ---------------------------------------------------------------------------
-- Event log & simulated external integrations
-- ---------------------------------------------------------------------------
create table public.events (
  id         bigint generated always as identity primary key,
  plant_id   text references public.plants (id) on delete cascade,
  category   text not null check (category in ('command', 'alarm', 'process', 'simulation', 'setpoint', 'maintenance', 'handover', 'integration', 'system')),
  severity   text not null default 'info' check (severity in ('info', 'warning', 'critical')),
  message    text not null,
  actor_id   uuid references public.profiles (id) on delete set null,
  actor_name text,
  payload    jsonb not null default '{}'::jsonb,
  sim_time   timestamptz,
  created_at timestamptz not null default now()
);
create index events_plant_idx on public.events (plant_id, created_at desc);

create table public.integration_log (
  id         bigint generated always as identity primary key,
  plant_id   text references public.plants (id) on delete cascade,
  system     text not null check (system in ('sms_gateway', 'cmms', 'historian', 'email')),
  action     text not null,
  message    text not null,
  status     text not null default 'delivered' check (status in ('delivered', 'queued', 'failed')),
  payload    jsonb not null default '{}'::jsonb,
  created_at timestamptz not null default now()
);
create index integration_log_idx on public.integration_log (created_at desc);

-- ---------------------------------------------------------------------------
-- Triggers
-- ---------------------------------------------------------------------------
create or replace function public.touch_updated_at()
returns trigger language plpgsql as $$
begin
  new.updated_at := now();
  return new;
end $$;

create trigger profiles_touch before update on public.profiles
  for each row execute function public.touch_updated_at();
create trigger maintenance_touch before update on public.maintenance_orders
  for each row execute function public.touch_updated_at();

-- New auth user -> profile. Role always starts as 'operator'; elevated roles
-- are granted server-side only (see api/scripts/seed-users.ts).
create or replace function public.handle_new_user()
returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, email, full_name)
  values (
    new.id,
    new.email,
    coalesce(new.raw_user_meta_data ->> 'full_name', split_part(new.email, '@', 1))
  )
  on conflict (id) do nothing;
  return new;
end $$;

create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function public.current_user_role()
returns public.user_role language sql stable security definer set search_path = public as $$
  select role from public.profiles where id = auth.uid()
$$;

create or replace function public.current_user_name()
returns text language sql stable security definer set search_path = public as $$
  select coalesce(nullif(full_name, ''), email) from public.profiles where id = auth.uid()
$$;

-- Acknowledge one or more alarms (any authenticated role).
create or replace function public.acknowledge_alarms(p_ids uuid[], p_comment text default null)
returns int language plpgsql security definer set search_path = public as $$
declare
  v_count int;
  v_name text := public.current_user_name();
begin
  if auth.uid() is null then
    raise exception 'Not authenticated' using errcode = '42501';
  end if;

  with upd as (
    update public.alarms a
       set state = case when a.state = 'active' then 'acknowledged' else 'closed' end,
           acknowledged_by = auth.uid(),
           acknowledged_by_name = v_name,
           acknowledged_at = now(),
           ack_comment = p_comment
     where a.id = any (p_ids)
       and a.state in ('active', 'rtn_unack')
    returning a.*
  ), ev as (
    insert into public.events (plant_id, category, severity, message, actor_id, actor_name, payload)
    select plant_id, 'alarm', 'info',
           'Alarm acknowledged: ' || tag || ' — ' || message,
           auth.uid(), v_name, jsonb_build_object('alarm_id', id, 'comment', p_comment)
      from upd
    returning 1
  )
  select count(*) into v_count from upd;

  return v_count;
end $$;

revoke execute on function public.acknowledge_alarms(uuid[], text) from public, anon;
grant execute on function public.acknowledge_alarms(uuid[], text) to authenticated;
