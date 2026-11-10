import { randomUUID } from 'node:crypto';
import type { Alarm, AlarmCondition, Equipment, SimEvent } from './types.js';

/**
 * In-memory alarm lifecycle (ISA-18.2 style):
 *   active ──ack──▶ acknowledged ──clear──▶ closed
 *     │clear                                   ▲
 *     ▼                                        │
 *   rtn_unack ─────────────ack─────────────────┘
 * A returning condition re-activates an rtn_unack alarm.
 */
export class AlarmTracker {
  private open = new Map<string, Alarm>();
  readonly changed = new Map<string, Alarm>();
  readonly raised: Alarm[] = [];

  constructor(
    private plantId: string,
    existing: Alarm[],
    private equipmentByTag: Map<string, Equipment>,
  ) {
    for (const a of existing) if (a.state !== 'closed') this.open.set(a.code, { ...a });
  }

  apply(conditions: AlarmCondition[], simTime: string, events: SimEvent[]) {
    const now = new Date().toISOString();
    const active = new Set<string>();

    for (const c of conditions) {
      active.add(c.code);
      const existing = this.open.get(c.code);
      if (!existing) {
        const alarm: Alarm = {
          id: randomUUID(),
          plant_id: this.plantId,
          equipment_id: (this.equipmentByTag.get(c.tag)?.id as string | undefined) ?? null,
          code: c.code,
          tag: c.tag,
          message: c.message,
          priority: c.priority,
          state: 'active',
          value: c.value === null ? null : Math.round(c.value * 100) / 100,
          raised_at: now,
          sim_raised_at: simTime,
          acknowledged_by: null,
          acknowledged_by_name: null,
          acknowledged_at: null,
          ack_comment: null,
          cleared_at: null,
        };
        this.open.set(c.code, alarm);
        this.changed.set(alarm.id, alarm);
        this.raised.push(alarm);
        events.push({
          category: 'alarm',
          severity: c.priority === 'critical' || c.priority === 'high' ? 'critical' : 'warning',
          tag: c.tag,
          message: `Alarm raised (${c.priority.toUpperCase()}): ${c.tag} — ${c.message}`,
        });
      } else if (existing.state === 'rtn_unack') {
        existing.state = 'active';
        existing.cleared_at = null;
        existing.message = c.message;
        this.changed.set(existing.id, existing);
        events.push({ category: 'alarm', severity: 'warning', tag: c.tag, message: `Alarm re-activated: ${c.tag} — ${c.message}` });
      }
    }

    for (const [code, a] of this.open) {
      if (active.has(code)) continue;
      if (a.state === 'active') a.state = 'rtn_unack';
      else if (a.state === 'acknowledged') a.state = 'closed';
      else continue;
      a.cleared_at = now;
      this.changed.set(a.id, a);
      if (a.state === 'closed') this.open.delete(code);
      events.push({ category: 'alarm', severity: 'info', tag: a.tag, message: `Alarm cleared: ${a.tag} — ${a.message}` });
    }
  }

  get openAlarms(): Alarm[] {
    return [...this.open.values()];
  }
}
