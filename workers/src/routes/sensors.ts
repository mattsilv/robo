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
