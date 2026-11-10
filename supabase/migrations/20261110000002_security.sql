-- ACME Control — Row Level Security, storage buckets and realtime.
--
-- Principle: every authenticated user can READ plant data. Control actions
-- (commands, simulation, setpoint review, lockout) are executed by the
-- TypeScript API with the service role after it validates the caller's role.
-- A few collaborative records (maintenance orders, handovers, profile) are
-- written directly by the client and guarded by the policies below.

alter table public.profiles               enable row level security;
alter table public.scenarios              enable row level security;
alter table public.plants                 enable row level security;
alter table public.plant_state            enable row level security;
alter table public.equipment              enable row level security;
alter table public.measurements           enable row level security;
alter table public.alarms                 enable row level security;
alter table public.commands               enable row level security;
alter table public.setpoints              enable row level security;
alter table public.setpoint_proposals     enable row level security;
alter table public.maintenance_orders     enable row level security;
alter table public.maintenance_attachments enable row level security;
alter table public.shift_handovers        enable row level security;
alter table public.events                 enable row level security;
alter table public.integration_log        enable row level security;

-- Read access for signed-in users -------------------------------------------
do $$
declare t text;
begin
  foreach t in array array[
    'profiles', 'scenarios', 'plants', 'plant_state', 'equipment', 'measurements',
    'alarms', 'commands', 'setpoints', 'setpoint_proposals', 'maintenance_orders',
    'maintenance_attachments', 'shift_handovers', 'events', 'integration_log'
  ] loop
    execute format('create policy "%s_read" on public.%I for select to authenticated using (true)', t, t);
  end loop;
end $$;

-- Profiles: users edit their own non-privileged columns ---------------------
create policy "profiles_update_own" on public.profiles
  for update to authenticated
  using (id = auth.uid())
  with check (id = auth.uid());

revoke update on public.profiles from authenticated, anon;
grant update (full_name, job_title, phone, avatar_url, preferences) on public.profiles to authenticated;
revoke insert, delete on public.profiles from authenticated, anon;

-- Maintenance orders ----------------------------------------------------------
-- Anyone can raise a request; planners (maintenance/engineer/supervisor) can
-- create scheduled orders and update them.
create policy "maintenance_insert" on public.maintenance_orders
  for insert to authenticated
  with check (
    created_by = auth.uid()
    and lockout_applied = false
    and (status = 'requested' or public.current_user_role() in ('maintenance', 'engineer', 'supervisor'))
  );

create policy "maintenance_update" on public.maintenance_orders
  for update to authenticated
  using (public.current_user_role() in ('maintenance', 'engineer', 'supervisor'))
  with check (public.current_user_role() in ('maintenance', 'engineer', 'supervisor'));

-- lockout_applied / external_ref are controlled exclusively by the API
-- (they change equipment state or come from the simulated CMMS).
revoke update on public.maintenance_orders from authenticated, anon;
grant update (
  title, description, type, priority, status, requires_lockout, assigned_to, assigned_to_name,
  equipment_id, equipment_tag, due_date, started_at, completed_at, completion_notes
) on public.maintenance_orders to authenticated;

create policy "attachments_insert" on public.maintenance_attachments
  for insert to authenticated
  with check (uploaded_by = auth.uid());

create policy "attachments_delete_own" on public.maintenance_attachments
  for delete to authenticated
  using (uploaded_by = auth.uid() or public.current_user_role() = 'supervisor');

-- Shift handovers ---------------------------------------------------------------
create policy "handover_insert" on public.shift_handovers
  for insert to authenticated
  with check (
    author_id = auth.uid()
    and status = 'submitted'
    and public.current_user_role() in ('operator', 'supervisor', 'maintenance')
  );

-- The incoming shift (someone other than the author) acknowledges.
create policy "handover_acknowledge" on public.shift_handovers
  for update to authenticated
  using (status = 'submitted' and author_id is distinct from auth.uid())
  with check (status = 'acknowledged' and acknowledged_by = auth.uid());

revoke update on public.shift_handovers from authenticated, anon;
grant update (status, acknowledged_by, acknowledged_by_name, acknowledged_at) on public.shift_handovers to authenticated;

-- Events: clients may log their own maintenance / handover actions -----------
create policy "events_insert_own" on public.events
  for insert to authenticated
  with check (actor_id = auth.uid() and category in ('maintenance', 'handover'));

-- Storage -------------------------------------------------------------------------
insert into storage.buckets (id, name, public, file_size_limit)
values
  ('avatars', 'avatars', true, 2097152),
  ('maintenance-files', 'maintenance-files', false, 10485760)
on conflict (id) do nothing;

create policy "avatars_public_read" on storage.objects
  for select using (bucket_id = 'avatars');

create policy "avatars_owner_write" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars_owner_update" on storage.objects
  for update to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "avatars_owner_delete" on storage.objects
  for delete to authenticated
  using (bucket_id = 'avatars' and (storage.foldername(name))[1] = auth.uid()::text);

create policy "maint_files_read" on storage.objects
  for select to authenticated
  using (bucket_id = 'maintenance-files');

create policy "maint_files_insert" on storage.objects
  for insert to authenticated
  with check (bucket_id = 'maintenance-files');

create policy "maint_files_delete_own" on storage.objects
  for delete to authenticated
  using (bucket_id = 'maintenance-files' and owner = auth.uid());

-- Realtime -------------------------------------------------------------------------
alter publication supabase_realtime add table
  public.plant_state,
  public.equipment,
  public.alarms,
  public.commands,
  public.setpoints,
  public.setpoint_proposals,
  public.maintenance_orders,
  public.shift_handovers,
  public.events,
  public.integration_log;
