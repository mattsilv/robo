import type { Context } from 'hono';
import type { Env } from '../types';

const KEY_TTL_DAYS = 30;

function maskKey(keyValue: string): string {
  return keyValue.slice(0, 5) + '••••' + keyValue.slice(-4);
}

function expiresAt(createdAt: string): string {
  // Handle both ISO (with Z/timezone) and SQLite datetime format (no timezone, assume UTC)
  const d = new Date(createdAt.includes('T') ? createdAt : createdAt + 'Z');
  d.setDate(d.getDate() + KEY_TTL_DAYS);
  return d.toISOString();
}

export async function listAPIKeys(c: Context<{ Bindings: Env }>) {
  const deviceId = c.req.header('X-Device-ID')!;
  // Only return non-expired keys
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - KEY_TTL_DAYS);
  const { results } = await c.env.DB.prepare(
    `SELECT id, label, key_value, created_at FROM api_keys
     WHERE device_id = ? AND created_at > ?
     ORDER BY created_at DESC`
  ).bind(deviceId, cutoff.toISOString()).all();

  const keys = (results as { id: string; label: string | null; key_value: string; created_at: string }[]).map(r => ({
    id: r.id,
    label: r.label,
    key_hint: maskKey(r.key_value),
    created_at: r.created_at,
    expires_at: expiresAt(r.created_at),
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

  // Compute cutoff date for expiry check
  const cutoff = new Date();
  cutoff.setDate(cutoff.getDate() - KEY_TTL_DAYS);
  const cutoffISO = cutoff.toISOString();

  // Atomic insert — only succeeds if device has fewer than 3 non-expired keys
  const result = await c.env.DB.prepare(
    `INSERT INTO api_keys (id, device_id, key_value, label)
     SELECT ?, ?, ?, ?
     WHERE (SELECT COUNT(*) FROM api_keys WHERE device_id = ? AND created_at > ?) < 3`
  ).bind(id, deviceId, keyValue, label, deviceId, cutoffISO).run();

  if (!result.meta.changes) {
    return c.json({ error: 'Maximum 3 API keys per device' }, 400);
  }

  const createdAt = new Date().toISOString();
  return c.json({ id, key_value: keyValue, label, created_at: createdAt, expires_at: expiresAt(createdAt) }, 201);
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
