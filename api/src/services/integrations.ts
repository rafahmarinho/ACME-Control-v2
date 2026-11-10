// Simulated external systems. Nothing here leaves the process: each
// "integration" writes what it would have sent into public.integration_log,
// so the app can show realistic delivery records without real providers.

import type { SupabaseClient } from '@supabase/supabase-js';
import type { Alarm } from '../sim/types.js';

export const SYSTEMS = [
  { id: 'sms_gateway', name: 'SMS paging gateway', vendor: 'Twilio (simulated)', description: 'Pages the on-call supervisor for CRITICAL and HIGH alarms.' },
  { id: 'cmms', name: 'CMMS / work management', vendor: 'SAP PM (simulated)', description: 'Synchronises maintenance work orders and returns notification numbers.' },
  { id: 'historian', name: 'Process historian', vendor: 'AVEVA PI (simulated)', description: 'Receives trend samples in batches after each simulation advance.' },
  { id: 'email', name: 'Email relay', vendor: 'SMTP relay (simulated)', description: 'Sends shift handover and setpoint approval notifications.' },
] as const;

export type SystemId = (typeof SYSTEMS)[number]['id'];

export async function logIntegration(
  db: SupabaseClient,
  entry: { plant_id: string | null; system: SystemId; action: string; message: string; status?: 'delivered' | 'queued' | 'failed'; payload?: Record<string, unknown> },
) {
  const { error } = await db.from('integration_log').insert({ status: 'delivered', payload: {}, ...entry });
  if (error) console.warn('[integrations] log failed', error.message);
}

export async function notifyNewAlarms(db: SupabaseClient, plantId: string, alarms: Alarm[]) {
  const urgent = alarms.filter((a) => a.priority === 'critical' || a.priority === 'high').slice(0, 10);
  for (const a of urgent) {
    await logIntegration(db, {
      plant_id: plantId,
      system: 'sms_gateway',
      action: 'alarm.page',
      message: `Paged on-call supervisor (+1 555-0142): [${a.priority.toUpperCase()}] ${a.tag} — ${a.message}`,
      payload: { alarm_id: a.id, code: a.code },
    });
  }
}

export async function syncWorkOrderToCmms(db: SupabaseClient, order: { id: string; number: string; plant_id: string; external_ref: string | null }) {
  const ref = order.external_ref ?? `SAP-PM-${4000000 + Math.floor(Math.random() * 99999)}`;
  await db.from('maintenance_orders').update({ external_ref: ref }).eq('id', order.id);
  await logIntegration(db, {
    plant_id: order.plant_id,
    system: 'cmms',
    action: 'work_order.sync',
    message: `${order.number} synchronised to SAP PM as notification ${ref.replace('SAP-PM-', '')}.`,
    payload: { order_id: order.id, external_ref: ref },
  });
  return ref;
}

export async function integrationStatus(db: SupabaseClient) {
  const { data } = await db.from('integration_log').select('*').order('created_at', { ascending: false }).limit(200);
  const rows = data ?? [];
  return SYSTEMS.map((s) => {
    const mine = rows.filter((r) => r.system === s.id);
    const failed = mine.slice(0, 20).filter((r) => r.status === 'failed').length;
    return {
      ...s,
      status: failed > 2 ? 'degraded' : 'online',
      latencyMs: 40 + Math.round(Math.random() * 160),
      lastActivityAt: mine[0]?.created_at ?? null,
      lastMessage: mine[0]?.message ?? null,
      messages24h: mine.filter((r) => Date.now() - new Date(r.created_at).getTime() < 86_400_000).length,
    };
  });
}
