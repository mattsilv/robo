import type { Context } from 'hono';
import type { Env } from '../types';

function maskKey(keyValue: string): string {
  return keyValue.slice(0, 5) + '••••' + keyValue.slice(-4);
}

export async function listAPIKeys(c: Context<{ Bindings: Env }>) {
  const deviceId = c.req.header('X-Device-ID')!;
  const { results } = await c.env.DB.prepare(
    'SELECT id, label, key_value, created_at FROM api_keys WHERE device_id = ? ORDER BY created_at DESC'
  ).bind(deviceId).all();

  const keys = (results as { id: string; label: string | null; key_value: string; created_at: string }[]).map(r => ({
    id: r.id,
    label: r.label,
    key_hint: maskKey(r.key_value),
    created_at: r.created_at,
  }));
  return c.json({ keys, count: keys.length });
}

export async function createAPIKey(c: Context<{ Bindings: Env }>) {
  const deviceId = c.req.header('X-Device-ID')!;

  const body = await c.req.json().catch(() => ({}));
  const label = body.label || null;

  const id = crypto.randomUUID();
  const keyValue = 'robo_' + [...crypto.getRandomValues(new Uint8Array(16))]
    .map(b => b.toString(16).padStart(2, '0')).join('');

  // Atomic insert — only succeeds if device has fewer than 3 keys
  const result = await c.env.DB.prepare(
    `INSERT INTO api_keys (id, device_id, key_value, label)
     SELECT ?, ?, ?, ?
     WHERE (SELECT COUNT(*) FROM api_keys WHERE device_id = ?) < 3`
  ).bind(id, deviceId, keyValue, label, deviceId).run();

  if (!result.meta.changes) {
    return c.json({ error: 'Maximum 3 API keys per device' }, 400);
  }

  return c.json({ id, key_value: keyValue, label, created_at: new Date().toISOString() }, 201);
}

export async function deleteAPIKey(c: Context<{ Bindings: Env }>) {
  const deviceId = c.req.header('X-Device-ID')!;
  const keyId = c.req.param('key_id');

  const result = await c.env.DB.prepare(
    'DELETE FROM api_keys WHERE id = ? AND device_id = ?'
  ).bind(keyId, deviceId).run();

  if (!result.meta.changes) {
    return c.json({ error: 'API key not found' }, 404);
  }

  return c.json({ deleted: true });
}
