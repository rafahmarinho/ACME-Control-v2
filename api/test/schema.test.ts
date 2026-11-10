// Applies the Supabase migrations + seed to an in-memory Postgres (PGlite)
// with minimal stubs for the Supabase-managed schemas (auth, storage, realtime).
import { readFileSync, readdirSync } from 'node:fs';
import { join } from 'node:path';
import { PGlite } from '@electric-sql/pglite';
import { beforeAll, describe, expect, it } from 'vitest';

const supabaseDir = join(import.meta.dirname, '..', '..', 'supabase');

const STUBS = `
  create role anon nologin; create role authenticated nologin; create role service_role nologin bypassrls;
  create schema auth;
  create table auth.users (id uuid primary key default gen_random_uuid(), email text, raw_user_meta_data jsonb default '{}'::jsonb);
  create function auth.uid() returns uuid language sql stable as $$ select nullif(current_setting('request.jwt.claim.sub', true), '')::uuid $$;
  create schema storage;
  create table storage.buckets (id text primary key, name text, public boolean, file_size_limit bigint);
  create table storage.objects (id uuid primary key default gen_random_uuid(), bucket_id text, name text, owner uuid);
  alter table storage.objects enable row level security;
  create function storage.foldername(name text) returns text[] language sql as $$ select string_to_array(name, '/') $$;
  create publication supabase_realtime;
  grant usage on schema public, auth, storage to anon, authenticated, service_role;
  alter default privileges in schema public grant all on tables to anon, authenticated, service_role;
  alter default privileges in schema public grant all on sequences to anon, authenticated, service_role;
  grant all on all tables in schema storage to authenticated;
`;

let pg: PGlite;

beforeAll(async () => {
  pg = new PGlite();
  await pg.exec(STUBS);
  for (const f of readdirSync(join(supabaseDir, 'migrations')).sort()) {
    await pg.exec(readFileSync(join(supabaseDir, 'migrations', f), 'utf8'));
  }
  // Demo users (normally created by scripts/seed-users.ts)
  const users = [
    ['11111111-1111-1111-1111-111111111111', 'operator@acme-control.test', 'operator', 'Olivia Carter'],
    ['22222222-2222-2222-2222-222222222222', 'engineer@acme-control.test', 'engineer', 'Ethan Brooks'],
    ['33333333-3333-3333-3333-333333333333', 'supervisor@acme-control.test', 'supervisor', 'Sofia Ramirez'],
    ['44444444-4444-4444-4444-444444444444', 'maintenance@acme-control.test', 'maintenance', 'Marcus Lee'],
  ];
  for (const [id, email, role, name] of users) {
    await pg.query(`insert into auth.users (id, email, raw_user_meta_data) values ($1, $2, jsonb_build_object('full_name', $3::text))`, [id, email, name]);
    await pg.query(`update public.profiles set role = $2 where id = $1`, [id, role]);
  }
  await pg.exec(readFileSync(join(supabaseDir, 'seed.sql'), 'utf8'));
}, 60_000);

async function asUser<T>(uid: string, fn: () => Promise<T>): Promise<T> {
  await pg.exec(`set role authenticated; select set_config('request.jwt.claim.sub', '${uid}', false);`);
  try {
    return await fn();
  } finally {
    await pg.exec(`reset role; select set_config('request.jwt.claim.sub', '', false);`);
  }
}

describe('database schema and demo data', () => {
  it('creates profiles for new auth users via trigger', async () => {
    const r = await pg.query<{ n: number }>(`select count(*)::int as n from profiles`);
    expect(r.rows[0].n).toBe(4);
  });

  it('seeds two plants with 15 assets each', async () => {
    const r = await pg.query<{ plant_id: string; n: number }>(`select plant_id, count(*)::int n from equipment group by 1 order by 1`);
    expect(r.rows).toEqual([{ plant_id: 'harbor-point', n: 15 }, { plant_id: 'north-valley', n: 15 }]);
  });

  it('seeds trend history, setpoints, scenarios and work orders', async () => {
    const q = async (sql: string) => (await pg.query<{ n: number }>(sql)).rows[0].n;
    expect(await q(`select count(*)::int n from measurements`)).toBeGreaterThan(4000);
    expect(await q(`select count(*)::int n from setpoints`)).toBe(16);
    expect(await q(`select count(*)::int n from scenarios`)).toBe(6);
    expect(await q(`select count(*)::int n from maintenance_orders`)).toBe(5);
    expect(await q(`select count(*)::int n from setpoint_proposals where status = 'pending'`)).toBe(2);
    const wo = await pg.query<{ created_by_name: string }>(`select created_by_name from maintenance_orders where number = 'WO-24003'`);
    expect(wo.rows[0].created_by_name).toBe('Sofia Ramirez');
  });

  it('new work orders continue the WO number sequence', async () => {
    await pg.exec(`insert into maintenance_orders (plant_id, title) values ('north-valley', 'Seq test')`);
    const r = await pg.query<{ number: string }>(`select number from maintenance_orders where title = 'Seq test'`);
    expect(r.rows[0].number).toBe('WO-24006');
  });

  it('reset is repeatable', async () => {
    await pg.exec(`select public.acme_reset_demo(); select public.acme_reset_demo();`);
    const r = await pg.query<{ n: number }>(`select count(*)::int n from plants`);
    expect(r.rows[0].n).toBe(2);
  });

  it('acknowledge_alarms RPC acknowledges and logs an event', async () => {
    await pg.exec(`insert into alarms (plant_id, code, tag, message, priority) values ('north-valley', 'T-101.HIGH', 'T-101', 'Raw Water Tank level high', 'high')`);
    const id = (await pg.query<{ id: string }>(`select id from alarms where code = 'T-101.HIGH' and state = 'active'`)).rows[0].id;
    const n = await asUser('11111111-1111-1111-1111-111111111111', async () =>
      (await pg.query<{ n: number }>(`select public.acknowledge_alarms(array[$1]::uuid[], 'Checked locally') n`, [id])).rows[0].n,
    );
    expect(n).toBe(1);
    const a = await pg.query<{ state: string; acknowledged_by_name: string }>(`select state, acknowledged_by_name from alarms where id = $1`, [id]);
    expect(a.rows[0]).toEqual({ state: 'acknowledged', acknowledged_by_name: 'Olivia Carter' });
  });

  it('RLS: users cannot change their own role', async () => {
    await expect(
      asUser('11111111-1111-1111-1111-111111111111', () => pg.query(`update profiles set role = 'supervisor' where id = auth.uid()`)),
    ).rejects.toThrow(/permission denied/);
    await asUser('11111111-1111-1111-1111-111111111111', () => pg.query(`update profiles set phone = '+1 555-9999' where id = auth.uid()`));
    const r = await pg.query<{ role: string; phone: string }>(`select role, phone from profiles where id = '11111111-1111-1111-1111-111111111111'`);
    expect(r.rows[0]).toEqual({ role: 'operator', phone: '+1 555-9999' });
  });

  it('RLS: clients cannot write equipment or commands directly', async () => {
    const r = await asUser('33333333-3333-3333-3333-333333333333', () =>
      pg.query(`update equipment set actual_state = 'running' where tag = 'P-102' returning id`),
    );
    expect(r.rows).toHaveLength(0);
  });

  it('RLS: operators can only raise maintenance requests; maintenance can plan', async () => {
    const op = '11111111-1111-1111-1111-111111111111';
    await asUser(op, () => pg.query(`insert into maintenance_orders (plant_id, title, status, created_by) values ('north-valley', 'Noise on P-201', 'requested', $1)`, [op]));
    await expect(
      asUser(op, () => pg.query(`insert into maintenance_orders (plant_id, title, status, created_by) values ('north-valley', 'x', 'scheduled', $1)`, [op])),
    ).rejects.toThrow(/row-level security/);
    const mnt = '44444444-4444-4444-4444-444444444444';
    const upd = await asUser(mnt, () => pg.query(`update maintenance_orders set status = 'scheduled' where title = 'Noise on P-201' returning id`));
    expect(upd.rows).toHaveLength(1);
    await expect(
      asUser(mnt, () => pg.query(`update maintenance_orders set lockout_applied = true where title = 'Noise on P-201'`)),
    ).rejects.toThrow(/permission denied/);
  });

  it('RLS: handover must be acknowledged by someone other than the author', async () => {
    const id = (await pg.query<{ id: string; author_id: string }>(`select id, author_id from shift_handovers where status = 'submitted' limit 1`)).rows[0].id;
    const self = await asUser('11111111-1111-1111-1111-111111111111', () =>
      pg.query(`update shift_handovers set status = 'acknowledged', acknowledged_by = auth.uid() where id = $1 returning id`, [id]),
    );
    expect(self.rows).toHaveLength(0);
    const sup = await asUser('33333333-3333-3333-3333-333333333333', () =>
      pg.query(`update shift_handovers set status = 'acknowledged', acknowledged_by = auth.uid(), acknowledged_at = now() where id = $1 returning id`, [id]),
    );
    expect(sup.rows).toHaveLength(1);
  });
});
