import type { Context } from 'hono';
import type { Env } from '../types';

export async function listAPIKeys(c: Context<{ Bindings: Env }>) {
  const deviceId = c.req.header('X-Device-ID')!;
  const { results } = await c.env.DB.prepare(
    'SELECT id, device_id, key_value, label, created_at FROM api_keys WHERE device_id = ? ORDER BY created_at DESC'
  ).bind(deviceId).all();
  return c.json({ keys: results, count: results.length });
}

export async function createAPIKey(c: Context<{ Bindings: Env }>) {
  const deviceId = c.req.header('X-Device-ID')!;

  // Enforce max 3 keys per device
  const { results: existing } = await c.env.DB.prepare(
    'SELECT id FROM api_keys WHERE device_id = ?'
  ).bind(deviceId).all();

  if (existing.length >= 3) {
    return c.json({ error: 'Maximum 3 API keys per device' }, 400);
  }

  const body = await c.req.json().catch(() => ({}));
  const label = body.label || null;

  const id = crypto.randomUUID();
  const keyValue = 'robo_' + [...crypto.getRandomValues(new Uint8Array(16))]
    .map(b => b.toString(16).padStart(2, '0')).join('');

  await c.env.DB.prepare(
    'INSERT INTO api_keys (id, device_id, key_value, label) VALUES (?, ?, ?, ?)'
  ).bind(id, deviceId, keyValue, label).run();

  return c.json({ id, device_id: deviceId, key_value: keyValue, label, created_at: new Date().toISOString() }, 201);
}

export async function deleteAPIKey(c: Context<{ Bindings: Env }>) {
  const deviceId = c.req.header('X-Device-ID')!;
  const keyId = c.req.param('key_id');

  const key = await c.env.DB.prepare(
    'SELECT id FROM api_keys WHERE id = ? AND device_id = ?'
  ).bind(keyId, deviceId).first();

  if (!key) {
    return c.json({ error: 'API key not found' }, 404);
  }

  await c.env.DB.prepare('DELETE FROM api_keys WHERE id = ?').bind(keyId).run();
  return c.json({ deleted: true });
}
