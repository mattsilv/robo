import type { Env } from '../types';

export interface LogEvent {
  type: string;
  device_id?: string;
  endpoint: string;
  status: 'success' | 'error' | 'rate_limited';
  duration_ms?: number;
  metadata?: Record<string, unknown>;
}

export function logEvent(env: Env, ctx: ExecutionContext, event: LogEvent) {
  ctx.waitUntil(
    env.DB.prepare(
      `INSERT INTO events (type, device_id, endpoint, status, duration_ms, metadata)
       VALUES (?, ?, ?, ?, ?, ?)`
    ).bind(
      event.type,
      event.device_id ?? null,
      event.endpoint,
      event.status,
      event.duration_ms ?? null,
      event.metadata ? JSON.stringify(event.metadata) : null
    ).run().catch(() => {
      console.error('Event logging failed:', event.type);
    })
  );
}
