-- ACME Control — demo data generator.
-- public.acme_reset_demo() wipes all operational data and recreates two demo
-- plants with equipment, setpoints, 12 h of trend history, alarms, work
-- orders, handovers and events. It is used by supabase/seed.sql and by the
-- API endpoint POST /api/simulation/reset. User accounts are never touched.

create or replace function public.acme_reset_demo()
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_now  timestamptz := now();
  v_op   uuid; v_op_name  text := 'System';
  v_eng  uuid; v_eng_name text := 'System';
  v_sup  uuid; v_sup_name text := 'System';
  v_mnt  uuid; v_mnt_name text := 'System';
  p      record;
  v_sp   uuid;
begin
  select id, full_name into v_op,  v_op_name  from profiles where role = 'operator'    order by created_at limit 1;
  select id, full_name into v_eng, v_eng_name from profiles where role = 'engineer'    order by created_at limit 1;
  select id, full_name into v_sup, v_sup_name from profiles where role = 'supervisor'  order by created_at limit 1;
  select id, full_name into v_mnt, v_mnt_name from profiles where role = 'maintenance' order by created_at limit 1;
  v_op_name  := coalesce(v_op_name,  'System');
  v_eng_name := coalesce(v_eng_name, 'System');
  v_sup_name := coalesce(v_sup_name, 'System');
  v_mnt_name := coalesce(v_mnt_name, 'System');

  -- Wipe ---------------------------------------------------------------------
  delete from integration_log where true;
  delete from events where true;
  delete from measurements where true;
  delete from alarms where true;
  delete from commands where true;
  delete from setpoint_proposals where true;
  delete from maintenance_attachments where true;
  delete from maintenance_orders where true;
  delete from shift_handovers where true;
  delete from setpoints where true;
  delete from equipment where true;
  delete from plant_state where true;
  delete from plants where true;
  delete from scenarios where true;
  perform setval('public.maintenance_order_seq', 24005, true);

  -- Scenarios ----------------------------------------------------------------
  insert into scenarios (id, name, description, inflow_factor, demand_factor, fault_tags, sort_order) values
    ('normal', 'Normal operation',
     'Nominal raw-water inflow and a typical diurnal demand curve. All equipment healthy.', 1.0, 1.0, '{}', 1),
    ('high_demand', 'High demand (heat wave)',
     'Distribution demand rises 60% above normal. The clearwell drains and low-level alarms may appear.', 1.0, 1.6, '{}', 2),
    ('low_inflow', 'Low raw-water inflow (drought)',
     'The river intake delivers only 30% of nominal inflow. The raw water tank drains and transfer pumps hit the low-suction interlock.', 0.3, 1.0, '{}', 3),
    ('storm_surge', 'Storm surge inflow',
     'Raw-water inflow rises 80%. The raw water tank fills quickly; the inlet valve must throttle to avoid overflow.', 1.8, 0.9, '{}', 4),
    ('pump_failure', 'Duty transfer pump failure',
     'Transfer pump P-101 trips on motor overload. In AUTO the standby pump P-102 takes over (unless it is locked out).', 1.0, 1.0, '{P-101}', 5),
    ('distribution_trip', 'Distribution pump trip',
     'Distribution pump P-201 trips on high winding temperature. Header pressure collapses and the clearwell fills.', 1.0, 1.0, '{P-201}', 6);

  -- Plants -------------------------------------------------------------------
  insert into plants (id, name, code, location, description, timezone, design_capacity_m3h,
                      base_inflow_m3h, base_demand_m3h, latitude, longitude, commissioned_on) values
    ('north-valley', 'North Valley Water Treatment Plant', 'NVW', 'Cedar Falls, Oregon',
     'Conventional surface-water plant supplying the Cedar Falls municipal network (approx. 48,000 residents).',
     'America/Los_Angeles', 300, 210, 190, 44.0521, -123.0868, '2009-05-14'),
    ('harbor-point', 'Harbor Point Water Treatment Plant', 'HPW', 'Port Halden, Maine',
     'Compact coastal plant feeding the Port Halden harbor district and industrial park.',
     'America/New_York', 220, 150, 140, 43.6591, -70.2568, '2014-09-02');

  insert into plant_state (plant_id, scenario_id, auto_run, sim_time, last_tick_at, last_measurement_at, tick,
                           inlet_flow_m3h, transfer_flow_m3h, distribution_flow_m3h, demand_m3h,
                           transfer_pressure_bar, distribution_pressure_bar, status) values
    ('north-valley', 'normal', true, v_now, v_now, v_now, 0, 210, 204, 188, 188, 3.3, 4.2, 'normal'),
    ('harbor-point', 'normal', true, v_now, v_now, v_now, 0, 150, 145, 139, 139, 3.2, 4.1, 'warning');

  -- Equipment ----------------------------------------------------------------
  for p in
    select * from (values
      ('north-valley', 500.0, 800.0, 240.0, 260.0, 62.0, 71.0, 'Grundfos', 'NKG 150-125-315', 'Flowserve', 'Valtek Mark One'),
      ('harbor-point', 350.0, 600.0, 170.0, 190.0, 48.0, 57.0, 'KSB',      'Etanorm 125-250', 'Emerson',   'Fisher V250')
    ) as t(plant_id, t1cap, t2cap, trated, drated, l1, l2, pmfr, pmodel, vmfr, vmodel)
  loop
    insert into equipment (plant_id, tag, name, kind, area, description, manufacturer, model, serial_number, installed_on,
                           control_mode, requested_state, actual_state, level_pct, volume_m3, capacity_m3,
                           rated_flow_m3h, flow_m3h, speed_pct, position_pct, pressure_bar, value, unit,
                           run_hours, starts_count, health_pct, sort_order) values
      (p.plant_id, 'XV-101', 'Raw Water Inlet Valve', 'valve', 'Intake',
       'Motorized butterfly valve isolating the river intake line.', p.vmfr, p.vmodel, 'VX-' || upper(left(p.plant_id, 2)) || '-1101', '2019-03-11',
       'auto', 'open', 'open', null, null, null, null, 205, null, 100, null, null, null, 0, 412, 97, 10),
      (p.plant_id, 'T-101', 'Raw Water Tank', 'tank', 'Intake',
       'Raw water buffer tank upstream of coagulation and filtration.', 'CST Industries', 'Aquastore 8m', 'TK-' || upper(left(p.plant_id, 2)) || '-101', '2009-04-02',
       null, null, 'normal', p.l1, p.t1cap * p.l1 / 100, p.t1cap, null, null, null, null, null, null, null, 0, 0, 100, 20),
      (p.plant_id, 'P-101', 'Transfer Pump 1 (Duty)', 'pump', 'Transfer',
       'Horizontal end-suction pump transferring filtered water to the clearwell.', p.pmfr, p.pmodel, 'PU-' || upper(left(p.plant_id, 2)) || '-101', '2016-08-19',
       'auto', 'running', 'running', null, null, null, p.trated, p.trated * 0.85, 85, null, 3.3, null, null, 18342, 1290, 92, 30),
      (p.plant_id, 'P-102', 'Transfer Pump 2 (Standby)', 'pump', 'Transfer',
       'Standby transfer pump, starts automatically when the duty pump is unavailable.', p.pmfr, p.pmodel, 'PU-' || upper(left(p.plant_id, 2)) || '-102', '2016-08-19',
       'auto', 'stopped', 'stopped', null, null, null, p.trated, 0, 0, null, 0.3, null, null, 9411, 734, 88, 40),
      (p.plant_id, 'XV-102', 'Transfer Discharge Valve', 'valve', 'Transfer',
       'Discharge isolation valve on the common transfer header.', p.vmfr, p.vmodel, 'VX-' || upper(left(p.plant_id, 2)) || '-1102', '2019-03-11',
       'auto', 'open', 'open', null, null, null, null, p.trated * 0.85, null, 100, null, null, null, 0, 388, 95, 50),
      (p.plant_id, 'T-102', 'Clearwell Reservoir', 'tank', 'Treated Water',
       'Treated water storage providing chlorine contact time before distribution.', 'CST Industries', 'Aquastore 12m', 'TK-' || upper(left(p.plant_id, 2)) || '-102', '2009-04-02',
       null, null, 'normal', p.l2, p.t2cap * p.l2 / 100, p.t2cap, null, null, null, null, null, null, null, 0, 0, 100, 60),
      (p.plant_id, 'P-201', 'Distribution Pump', 'pump', 'Distribution',
       'Vertical turbine high-lift pump feeding the distribution network.', p.pmfr, 'HL-' || p.pmodel, 'PU-' || upper(left(p.plant_id, 2)) || '-201', '2017-02-07',
       'auto', 'running', 'running', null, null, null, p.drated, p.drated * 0.72, 100, null, 4.2, null, null, 22018, 811, 94, 70),
      (p.plant_id, 'XV-201', 'Distribution Outlet Valve', 'valve', 'Distribution',
       'Outlet valve to the municipal distribution main.', p.vmfr, p.vmodel, 'VX-' || upper(left(p.plant_id, 2)) || '-1201', '2019-03-11',
       'auto', 'open', 'open', null, null, null, null, p.drated * 0.72, null, 100, null, null, null, 0, 297, 98, 80),
      (p.plant_id, 'LT-101', 'Raw Water Tank Level', 'instrument', 'Intake', 'Radar level transmitter on T-101.',
       'Endress+Hauser', 'Micropilot FMR20', 'IN-' || upper(left(p.plant_id, 2)) || '-L101', '2020-06-01',
       null, null, 'normal', null, null, null, null, null, null, null, null, p.l1, '%', 0, 0, 100, 100),
      (p.plant_id, 'LT-102', 'Clearwell Level', 'instrument', 'Treated Water', 'Radar level transmitter on T-102.',
       'Endress+Hauser', 'Micropilot FMR20', 'IN-' || upper(left(p.plant_id, 2)) || '-L102', '2020-06-01',
       null, null, 'normal', null, null, null, null, null, null, null, null, p.l2, '%', 0, 0, 100, 110),
      (p.plant_id, 'FT-101', 'Raw Water Inflow', 'instrument', 'Intake', 'Electromagnetic flow meter on the intake line.',
       'Siemens', 'SITRANS FM MAG 5100W', 'IN-' || upper(left(p.plant_id, 2)) || '-F101', '2018-10-15',
       null, null, 'normal', null, null, null, null, null, null, null, null, 205, 'm³/h', 0, 0, 100, 120),
      (p.plant_id, 'FT-102', 'Transfer Flow', 'instrument', 'Transfer', 'Electromagnetic flow meter on the transfer header.',
       'Siemens', 'SITRANS FM MAG 5100W', 'IN-' || upper(left(p.plant_id, 2)) || '-F102', '2018-10-15',
       null, null, 'normal', null, null, null, null, null, null, null, null, p.trated * 0.85, 'm³/h', 0, 0, 100, 130),
      (p.plant_id, 'FT-201', 'Distribution Flow', 'instrument', 'Distribution', 'Electromagnetic flow meter on the distribution main.',
       'Siemens', 'SITRANS FM MAG 5100W', 'IN-' || upper(left(p.plant_id, 2)) || '-F201', '2018-10-15',
       null, null, 'normal', null, null, null, null, null, null, null, null, p.drated * 0.72, 'm³/h', 0, 0, 100, 140),
      (p.plant_id, 'PT-101', 'Transfer Discharge Pressure', 'instrument', 'Transfer', 'Pressure transmitter downstream of P-101/P-102.',
       'WIKA', 'S-20', 'IN-' || upper(left(p.plant_id, 2)) || '-P101', '2021-01-20',
       null, null, 'normal', null, null, null, null, null, null, null, null, 3.3, 'bar', 0, 0, 100, 150),
      (p.plant_id, 'PT-201', 'Distribution Header Pressure', 'instrument', 'Distribution', 'Pressure transmitter on the distribution header.',
       'WIKA', 'S-20', 'IN-' || upper(left(p.plant_id, 2)) || '-P201', '2021-01-20',
       null, null, 'normal', null, null, null, null, null, null, null, null, 4.2, 'bar', 0, 0, 100, 160);

    -- Setpoints
    insert into setpoints (plant_id, key, name, description, category, unit, value, min_value, max_value, step, updated_by_name) values
      (p.plant_id, 't101_high_close', 'T-101 inlet close level', 'Inlet valve XV-101 closes (AUTO) when the raw water tank reaches this level; re-opens 10% below.', 'Level control', '%', 90, 60, 98, 1, 'Commissioning'),
      (p.plant_id, 't101_low_stop', 'T-101 transfer stop level', 'Transfer pumps stop (AUTO) when the raw water tank falls to this level; restart 10% above.', 'Level control', '%', 15, 5, 40, 1, 'Commissioning'),
      (p.plant_id, 't102_high_stop', 'T-102 transfer stop level', 'Transfer pumps stop (AUTO) when the clearwell reaches this level; restart 8% below.', 'Level control', '%', 92, 60, 98, 1, 'Commissioning'),
      (p.plant_id, 't102_low_stop', 'T-102 distribution stop level', 'Distribution pump P-201 stops (AUTO) when the clearwell falls to this level; restart 8% above.', 'Level control', '%', 12, 5, 40, 1, 'Commissioning'),
      (p.plant_id, 'transfer_speed', 'Transfer pump speed', 'VFD speed reference for the running transfer pump.', 'Pump control', '%', 85, 40, 100, 1, 'Commissioning'),
      (p.plant_id, 'level_alarm_high', 'High level alarm limit', 'Tank level that raises a HIGH alarm.', 'Alarm limits', '%', 95, 80, 99, 1, 'Commissioning'),
      (p.plant_id, 'level_alarm_low', 'Low level alarm limit', 'Tank level that raises a LOW alarm.', 'Alarm limits', '%', 10, 2, 30, 1, 'Commissioning'),
      (p.plant_id, 'pressure_alarm_high', 'High pressure alarm limit', 'Discharge pressure that raises a HIGH PRESSURE alarm.', 'Alarm limits', 'bar', 6, 4.5, 9, 0.1, 'Commissioning');

    -- 12 h of trend history at 2-minute resolution
    insert into measurements (plant_id, tag, value, ts)
    select p.plant_id, t.tag,
      round((case t.tag
        when 'LT-101' then p.l1 + 7 * sin(extract(epoch from g) / 3600 * 2 * pi() / 5) + random() * 1.2
        when 'LT-102' then p.l2 + 5 * sin(extract(epoch from g) / 3600 * 2 * pi() / 7 + 1) + random() * 0.8
        when 'FT-101' then (case when p.plant_id = 'north-valley' then 210 else 150 end) * (0.97 + random() * 0.06)
        when 'FT-102' then p.trated * 0.85 * (0.96 + random() * 0.05)
        when 'FT-201' then (case when p.plant_id = 'north-valley' then 190 else 140 end)
                           * (1 + 0.22 * sin(2 * pi() * (extract(hour from g) + extract(minute from g) / 60 - 9) / 12))
                           * (0.97 + random() * 0.06)
        when 'PT-101' then 3.25 + random() * 0.2
        when 'PT-201' then 4.05 + random() * 0.3
      end)::numeric, 2),
      g
    from generate_series(v_now - interval '12 hours', v_now - interval '2 minutes', interval '2 minutes') g
    cross join (values ('LT-101'), ('LT-102'), ('FT-101'), ('FT-102'), ('FT-201'), ('PT-101'), ('PT-201')) t(tag);
  end loop;

  -- Harbor Point: P-102 is locked out for a seal replacement, XV-201 in MANUAL.
  update equipment
     set in_maintenance = true, actual_state = 'locked_out', requested_state = 'stopped',
         interlock_reason = 'Locked out for maintenance (WO-24003)', health_pct = 61
   where plant_id = 'harbor-point' and tag = 'P-102';
  update equipment set control_mode = 'manual' where plant_id = 'harbor-point' and tag = 'XV-201';

  -- Setpoint proposals ---------------------------------------------------------
  select id into v_sp from setpoints where plant_id = 'north-valley' and key = 't102_high_stop';
  insert into setpoint_proposals (setpoint_id, plant_id, setpoint_name, unit, current_value, proposed_value, reason, status,
                                  proposed_by, proposed_by_name, created_at)
  values (v_sp, 'north-valley', 'T-102 transfer stop level', '%', 92, 94,
          'Increase clearwell buffer ahead of the forecast heat wave (NWS advisory for Thursday–Saturday).', 'pending',
          v_eng, v_eng_name, v_now - interval '40 minutes');

  select id into v_sp from setpoints where plant_id = 'harbor-point' and key = 'transfer_speed';
  insert into setpoint_proposals (setpoint_id, plant_id, setpoint_name, unit, current_value, proposed_value, reason, status,
                                  proposed_by, proposed_by_name, reviewed_by, reviewed_by_name, review_note, created_at, reviewed_at)
  values (v_sp, 'harbor-point', 'Transfer pump speed', '%', 90, 85,
          'Reduce energy use during off-peak tariff; clearwell level stays above 50% at 85% speed.', 'approved',
          v_eng, v_eng_name, v_sup, v_sup_name, 'Approved — monitor clearwell level during morning peak.',
          v_now - interval '2 days', v_now - interval '2 days' + interval '3 hours');

  select id into v_sp from setpoints where plant_id = 'harbor-point' and key = 'level_alarm_low';
  insert into setpoint_proposals (setpoint_id, plant_id, setpoint_name, unit, current_value, proposed_value, reason, status,
                                  proposed_by, proposed_by_name, created_at)
  values (v_sp, 'harbor-point', 'Low level alarm limit', '%', 10, 15,
          'Earlier warning for operators while P-102 is out of service and there is no standby transfer capacity.', 'pending',
          v_eng, v_eng_name, v_now - interval '3 hours');

  -- Maintenance orders -----------------------------------------------------------
  insert into maintenance_orders (number, plant_id, equipment_id, equipment_tag, title, description, type, priority, status,
                                  requires_lockout, lockout_applied, assigned_to, assigned_to_name, created_by, created_by_name,
                                  due_date, started_at, completed_at, completion_notes, external_ref, created_at)
  values
    ('WO-24001', 'north-valley', (select id from equipment where plant_id = 'north-valley' and tag = 'P-101'), 'P-101',
     'Quarterly vibration analysis', 'Collect vibration spectra on motor and pump bearings (DE/NDE). Compare against baseline from Q2.',
     'preventive', 'medium', 'scheduled', false, false, v_mnt, v_mnt_name, v_sup, v_sup_name,
     (v_now + interval '5 days')::date, null, null, null, 'SAP-PM-4000871', v_now - interval '6 days'),
    ('WO-24002', 'north-valley', (select id from equipment where plant_id = 'north-valley' and tag = 'XV-102'), 'XV-102',
     'Positioner feedback hunting', 'Operator reports XV-102 position feedback oscillating ±3% when fully open. Check positioner calibration.',
     'corrective', 'low', 'requested', false, false, null, null, v_op, v_op_name,
     (v_now + interval '10 days')::date, null, null, null, null, v_now - interval '1 day'),
    ('WO-24003', 'harbor-point', (select id from equipment where plant_id = 'harbor-point' and tag = 'P-102'), 'P-102',
     'Replace mechanical seal — leak at drive end', 'Visible leak at the drive-end mechanical seal (approx. 20 drops/min). Replace seal kit and check shaft sleeve for wear.',
     'corrective', 'high', 'in_progress', true, true, v_mnt, v_mnt_name, v_sup, v_sup_name,
     (v_now + interval '1 day')::date, v_now - interval '2 hours', null, null, 'SAP-PM-4000874', v_now - interval '1 day'),
    ('WO-24004', 'harbor-point', (select id from equipment where plant_id = 'harbor-point' and tag = 'T-102'), 'T-102',
     'Annual clearwell inspection', 'Drain-down not required. ROV inspection of walls, baffles and sediment. Report coating condition.',
     'inspection', 'medium', 'scheduled', false, false, v_mnt, v_mnt_name, v_eng, v_eng_name,
     (v_now + interval '14 days')::date, null, null, null, 'SAP-PM-4000879', v_now - interval '3 days'),
    ('WO-24005', 'north-valley', (select id from equipment where plant_id = 'north-valley' and tag = 'LT-101'), 'LT-101',
     'Level transmitter drift check', 'Compare LT-101 reading with manual dip measurement.',
     'inspection', 'low', 'completed', false, false, v_mnt, v_mnt_name, v_eng, v_eng_name,
     (v_now - interval '2 days')::date, v_now - interval '3 days', v_now - interval '3 days' + interval '1 hour',
     'Deviation 0.4% (within ±1% tolerance). No adjustment required.', 'SAP-PM-4000862', v_now - interval '5 days');

  -- Alarms (history + current) ----------------------------------------------------
  insert into alarms (plant_id, equipment_id, code, tag, message, priority, state, value, raised_at, sim_raised_at,
                      acknowledged_by, acknowledged_by_name, acknowledged_at, cleared_at)
  values
    ('harbor-point', (select id from equipment where plant_id = 'harbor-point' and tag = 'P-102'), 'P-102.LOTO', 'P-102',
     'P-102 locked out for maintenance — no standby transfer capacity', 'low', 'acknowledged', null,
     v_now - interval '2 hours', v_now - interval '2 hours', v_op, v_op_name, v_now - interval '110 minutes', null),
    ('north-valley', (select id from equipment where plant_id = 'north-valley' and tag = 'T-102'), 'T-102.LOW', 'T-102',
     'Clearwell level low', 'medium', 'closed', 9.6,
     v_now - interval '9 hours', v_now - interval '9 hours', v_op, v_op_name, v_now - interval '9 hours' + interval '4 minutes', v_now - interval '8 hours'),
    ('north-valley', (select id from equipment where plant_id = 'north-valley' and tag = 'PT-201'), 'PT-201.HP', 'PT-201',
     'Distribution header pressure high', 'high', 'closed', 6.4,
     v_now - interval '5 hours', v_now - interval '5 hours', v_sup, v_sup_name, v_now - interval '5 hours' + interval '2 minutes', v_now - interval '5 hours' + interval '6 minutes'),
    ('harbor-point', (select id from equipment where plant_id = 'harbor-point' and tag = 'P-102'), 'P-102.FAULT', 'P-102',
     'P-102 fault — seal leak detected by moisture probe', 'critical', 'closed', null,
     v_now - interval '26 hours', v_now - interval '26 hours', v_op, v_op_name, v_now - interval '26 hours' + interval '1 minute', v_now - interval '24 hours');

  -- Commands history ----------------------------------------------------------------
  insert into commands (plant_id, equipment_id, tag, action, requested_state, status, result_message, requested_by, requested_by_name, created_at, completed_at)
  values
    ('north-valley', (select id from equipment where plant_id = 'north-valley' and tag = 'P-102'), 'P-102', 'start', 'running', 'completed',
     'P-102 running (manual test run).', v_op, v_op_name, v_now - interval '7 hours', v_now - interval '7 hours' + interval '3 seconds'),
    ('north-valley', (select id from equipment where plant_id = 'north-valley' and tag = 'P-102'), 'P-102', 'stop', 'stopped', 'completed',
     'P-102 stopped.', v_op, v_op_name, v_now - interval '6 hours 45 minutes', v_now - interval '6 hours 45 minutes' + interval '2 seconds'),
    ('harbor-point', (select id from equipment where plant_id = 'harbor-point' and tag = 'XV-201'), 'XV-201', 'set_manual', null, 'completed',
     'XV-201 switched to MANUAL.', v_sup, v_sup_name, v_now - interval '3 hours', v_now - interval '3 hours'),
    ('harbor-point', (select id from equipment where plant_id = 'harbor-point' and tag = 'P-102'), 'P-102', 'start', 'running', 'blocked',
     'P-102 did not start: locked out for maintenance (WO-24003).', v_op, v_op_name, v_now - interval '90 minutes', v_now - interval '90 minutes');

  -- Shift handovers ------------------------------------------------------------------
  insert into shift_handovers (plant_id, shift, shift_date, author_id, author_name, summary, open_issues, safety_notes, equipment_notes,
                               snapshot, status, acknowledged_by, acknowledged_by_name, acknowledged_at, created_at)
  values
    ('north-valley', 'night', (v_now - interval '1 day')::date, v_op, v_op_name,
     'Stable night. Demand followed the normal curve; clearwell dipped to 9.6% around 03:00 during the filter backwash and recovered.',
     'XV-102 position feedback hunting slightly — WO-24002 raised.', 'No incidents. Chlorine room ventilation checked OK.',
     'P-102 test-run for 15 min at 01:10, no abnormal noise.',
     jsonb_build_object('active_alarms', 0, 't101_level', 61.8, 't102_level', 70.4, 'running_pumps', 2),
     'acknowledged', v_sup, v_sup_name, (v_now - interval '1 day') + interval '8 hours', (v_now - interval '1 day') + interval '7 hours 50 minutes'),
    ('harbor-point', 'day', v_now::date, v_op, v_op_name,
     'P-102 isolated and locked out for seal replacement (WO-24003). Running on P-101 only. XV-201 left in MANUAL for the valve exercise.',
     'No standby transfer capacity until WO-24003 is closed. Return XV-201 to AUTO after the exercise.',
     'LOTO tags applied on P-102 MCC bucket and suction/discharge valves (lock #17).',
     'P-101 bearing temperature 61 °C, trending stable.',
     jsonb_build_object('active_alarms', 1, 't101_level', 48.2, 't102_level', 57.1, 'running_pumps', 2),
     'submitted', null, null, null, v_now - interval '35 minutes');

  -- Events -----------------------------------------------------------------------------
  insert into events (plant_id, category, severity, message, actor_id, actor_name, created_at) values
    (null, 'system', 'info', 'Demo data initialised (2 plants, 30 assets, 12 h of history).', null, 'System', v_now),
    ('north-valley', 'command', 'info', 'P-102 start requested (manual test run).', v_op, v_op_name, v_now - interval '7 hours'),
    ('north-valley', 'command', 'info', 'P-102 stop requested.', v_op, v_op_name, v_now - interval '6 hours 45 minutes'),
    ('north-valley', 'alarm', 'warning', 'Alarm raised: PT-201 — Distribution header pressure high', null, 'System', v_now - interval '5 hours'),
    ('north-valley', 'setpoint', 'info', 'Setpoint change proposed: T-102 transfer stop level 92 → 94 %', v_eng, v_eng_name, v_now - interval '40 minutes'),
    ('harbor-point', 'maintenance', 'warning', 'Lockout applied on P-102 for WO-24003.', v_mnt, v_mnt_name, v_now - interval '2 hours'),
    ('harbor-point', 'command', 'warning', 'P-102 start blocked: locked out for maintenance.', v_op, v_op_name, v_now - interval '90 minutes'),
    ('harbor-point', 'handover', 'info', 'Day shift handover submitted.', v_op, v_op_name, v_now - interval '35 minutes');

  insert into integration_log (plant_id, system, action, message, status, created_at) values
    ('harbor-point', 'cmms', 'work_order.sync', 'WO-24003 synchronised to SAP PM as notification 4000874.', 'delivered', v_now - interval '1 day'),
    ('harbor-point', 'sms_gateway', 'alarm.page', 'Paged on-call supervisor: P-102 fault — seal leak detected.', 'delivered', v_now - interval '26 hours'),
    ('north-valley', 'historian', 'batch.upload', 'Uploaded 2,520 samples to the plant historian (OSIsoft PI, simulated).', 'delivered', v_now - interval '1 hour');
end;
$$;

revoke execute on function public.acme_reset_demo() from public, anon, authenticated;
grant execute on function public.acme_reset_demo() to service_role;
