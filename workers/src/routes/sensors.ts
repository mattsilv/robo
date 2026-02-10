import { zValidator } from '@hono/zod-validator';
import type { Context } from 'hono';
import { SensorDataSchema, type Env } from '../types';

export const submitSensorData = async (c: Context<{ Bindings: Env }>) => {
  const body = await c.req.json();
  const validated = SensorDataSchema.safeParse(body);

  if (!validated.success) {
    return c.json({ error: 'Invalid request body', issues: validated.error.issues }, 400);
  }

  const { device_id, sensor_type, data } = validated.data;
  const now = new Date().toISOString();

  try {
    // Update last_seen_at for device
    await c.env.DB.prepare('UPDATE devices SET last_seen_at = ? WHERE id = ?')
      .bind(now, device_id)
      .run();

    // Insert sensor data
    const result = await c.env.DB.prepare(
      'INSERT INTO sensor_data (device_id, sensor_type, data, captured_at) VALUES (?, ?, ?, ?)'
    )
      .bind(device_id, sensor_type, JSON.stringify(data), now)
      .run();

    return c.json({
      id: result.meta.last_row_id,
      device_id,
      sensor_type,
      data,
      captured_at: now,
    }, 201);
  } catch (error) {
    console.error('Failed to submit sensor data:', error);
    return c.json({ error: 'Failed to submit sensor data' }, 500);
  }
};

export const getUploadUrl = async (c: Context<{ Bindings: Env }>) => {
  const body = await c.req.json();
  const { device_id, sensor_type, content_type } = body;

  if (!device_id || !sensor_type || !content_type) {
    return c.json({ error: 'Missing required fields: device_id, sensor_type, content_type' }, 400);
  }

  try {
    const key = `${device_id}/${sensor_type}/${Date.now()}-${Math.random().toString(36).slice(2)}`;

    // For R2 presigned URLs, we'll use a simplified approach
    // In a real implementation, you'd generate a presigned URL
    // For now, return the key for direct upload via Workers
    return c.json({
      upload_url: `/api/sensors/upload/${key}`,
      key,
      expires_at: new Date(Date.now() + 3600000).toISOString(), // 1 hour
    }, 200);
  } catch (error) {
    console.error('Failed to generate upload URL:', error);
    return c.json({ error: 'Failed to generate upload URL' }, 500);
  }
};
