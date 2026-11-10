// Restores the demo dataset without touching user accounts.
// Usage: pnpm reset:demo
import 'dotenv/config';
import { createClient } from '@supabase/supabase-js';

const url = process.env.SUPABASE_URL;
const key = process.env.SUPABASE_SERVICE_ROLE_KEY;
if (!url || !key) {
  console.error('Set SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in api/.env first.');
  process.exit(1);
}
const db = createClient(url, key, { auth: { persistSession: false } });
const { error } = await db.rpc('acme_reset_demo');
if (error) {
  console.error('Reset failed:', error.message);
  process.exit(1);
}
console.log('Demo data restored.');
