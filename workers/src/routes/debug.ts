import type { Context } from 'hono';
import type { Env } from '../types';

/**
 * POST /api/debug/sync — Store debug scan data in R2
 * Body: { device_id: string, type: "barcode" | "room", data: any }
 */
export async function debugSync(c: Context<{ Bindings: Env }>) {
  const body = await c.req.json().catch(() => null);
  if (!body || !body.device_id || !body.type || !body.data) {
    return c.json({ error: 'Missing required fields: device_id, type, data' }, 400);
  }

  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const key = `debug/${body.device_id}/${timestamp}-${body.type}.json`;

  await c.env.BUCKET.put(key, JSON.stringify(body.data, null, 2), {
    customMetadata: {
      device_id: body.device_id,
      type: body.type,
      uploaded_at: new Date().toISOString(),
    },
  });

  return c.json({ ok: true, key });
}

/**
 * GET /api/debug/sync/:device_id — List debug payloads for a device
 */
export async function debugList(c: Context<{ Bindings: Env }>) {
  const deviceId = c.req.param('device_id');
  const prefix = `debug/${deviceId}/`;

  const listed = await c.env.BUCKET.list({ prefix, limit: 100 });
  const items = listed.objects.map((obj) => ({
    key: obj.key,
    size: obj.size,
    uploaded: obj.uploaded.toISOString(),
    metadata: obj.customMetadata,
  }));

  return c.json({ device_id: deviceId, count: items.length, items });
}

/**
 * GET /api/debug/sync/:device_id/:key+ — Retrieve a specific debug payload
 */
export async function debugGet(c: Context<{ Bindings: Env }>) {
  const deviceId = c.req.param('device_id');
  const key = c.req.param('key');
  const fullKey = `debug/${deviceId}/${key}`;

  const obj = await c.env.BUCKET.get(fullKey);
  if (!obj) {
    return c.json({ error: 'Not found' }, 404);
  }

  const data = await obj.json();
  return c.json({ key: fullKey, data });
}
