// Creates (or updates) the four demo accounts and assigns their roles, then
// regenerates demo data so records are attributed to these users.
// Usage: pnpm seed:users   (requires SUPABASE_URL + SUPABASE_SERVICE_ROLE_KEY)

import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
const password = process.env.DEMO_PASSWORD ?? 'AcmeDemo!2026';
const domain = process.env.DEMO_EMAIL_DOMAIN ?? 'acme-control.test';

if (!url || !key) {
  console.error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in api/.env first.');
  process.exit(1);
}

const db = createClient(url, key, { auth: { persistSession: false, autoRefreshToken: false } });

const users = [
  { email: `operator@${domain}`, full_name: 'Olivia Carter', role: 'operator', job_title: 'Control Room Operator', phone: '+1 555-0101' },
  { email: `engineer@${domain}`, full_name: 'Ethan Brooks', role: 'engineer', job_title: 'Process Engineer', phone: '+1 555-0102' },
  { email: `supervisor@${domain}`, full_name: 'Sofia Ramirez', role: 'supervisor', job_title: 'Shift Supervisor', phone: '+1 555-0142' },
  { email: `maintenance@${domain}`, full_name: 'Marcus Lee', role: 'maintenance', job_title: 'Maintenance Technician', phone: '+1 555-0104' },
] as const;

async function findUserId(email: string): Promise<string | null> {
  for (let page = 1; page < 20; page++) {
    const { data, error } = await db.auth.admin.listUsers({ page, perPage: 200 });
    if (error) throw error;
    const hit = data.users.find((u) => u.email?.toLowerCase() === email.toLowerCase());
    if (hit) return hit.id;
    if (data.users.length < 200) return null;
  }
  return null;
}

for (const u of users) {
  let id = await findUserId(u.email);
  if (!id) {
    const { data, error } = await db.auth.admin.createUser({
      email: u.email,
      password,
      email_confirm: true,
      user_metadata: { full_name: u.full_name },
    });
    if (error) throw error;
    id = data.user.id;
    console.log(`created  ${u.email}`);
  } else {
    await db.auth.admin.updateUserById(id, { password });
    console.log(`exists   ${u.email} (password reset to demo password)`);
  }
  const { error } = await db
    .from('profiles')
    .upsert({ id, email: u.email, full_name: u.full_name, role: u.role, job_title: u.job_title, phone: u.phone });
  if (error) throw error;
}

const { error } = await db.rpc('acme_reset_demo');
if (error) throw error;
console.log('\nDemo data regenerated. Sign in with any account above and the demo password.');
