import type { Context } from 'hono';
import type { Env } from '../types';

/**
 * POST /api/screenshots — Upload a screenshot image (multipart/form-data)
 * Auth: Bearer token (preferred, resolves device ID) or X-Device-ID header
 * Body: multipart with "image" file field
 */
export async function uploadScreenshot(c: Context<{ Bindings: Env }>) {
  // Prefer token-resolved device ID (accurate even if X-Device-ID is stale)
  const deviceId = c.get('resolvedDeviceId') ?? c.req.header('X-Device-ID')!;

  let formData: FormData;
  try {
    formData = await c.req.formData();
  } catch {
    return c.json({ error: 'Expected multipart/form-data with an "image" field' }, 400);
  }

  const imageFile = formData.get('image') as File | null;
  if (!imageFile || typeof imageFile === 'string') {
    return c.json({ error: 'Missing "image" file field' }, 400);
  }

  const imageBytes = await imageFile.arrayBuffer();
  if (imageBytes.byteLength === 0) {
    return c.json({ error: 'Empty image file' }, 400);
  }

  // Store in R2
  const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
  const r2Key = `screenshots/${deviceId}/${timestamp}.jpg`;

  await c.env.BUCKET.put(r2Key, imageBytes, {
    httpMetadata: { contentType: 'image/jpeg' },
    customMetadata: {
      device_id: deviceId,
      source: 'share_extension',
      uploaded_at: new Date().toISOString(),
    },
  });

  // Record in D1 sensor_data table
  const metadata = {
    source: 'share_extension',
    r2_key: r2Key,
    file_size: imageBytes.byteLength,
    content_type: imageFile.type || 'image/jpeg',
  };

  await c.env.DB.prepare(
    'INSERT INTO sensor_data (device_id, sensor_type, data, captured_at) VALUES (?, ?, ?, ?)'
  ).bind(
    deviceId,
    'camera',
    JSON.stringify(metadata),
    new Date().toISOString()
  ).run();

  return c.json({
    ok: true,
    r2_key: r2Key,
    file_size: imageBytes.byteLength,
  });
}
