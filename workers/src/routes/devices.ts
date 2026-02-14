import type { Context } from 'hono';
import { RegisterDeviceSchema, type Env, type Device } from '../types';

export const registerDevice = async (c: Context<{ Bindings: Env }>) => {
  const body = await c.req.json();
  const validated = RegisterDeviceSchema.safeParse(body);

  if (!validated.success) {
    return c.json({ error: 'Invalid request body', issues: validated.error.issues }, 400);
  }

  const { name } = validated.data;
  const deviceId = crypto.randomUUID();
  const mcpToken = [...crypto.getRandomValues(new Uint8Array(24))]
    .map(b => b.toString(16).padStart(2, '0')).join('');
  const now = new Date().toISOString();

  try {
    await c.env.DB.prepare(
      'INSERT INTO devices (id, name, mcp_token, registered_at) VALUES (?, ?, ?, ?)'
    )
      .bind(deviceId, name, mcpToken, now)
      .run();

    return c.json({
      id: deviceId,
      name,
      mcp_token: mcpToken,
      registered_at: now,
      last_seen_at: null,
    }, 201);
  } catch (error) {
    console.error('Failed to register device:', error);
    return c.json({ error: 'Failed to register device' }, 500);
  }
};

export const getDevice = async (c: Context<{ Bindings: Env }>) => {
  const deviceId = c.req.param('device_id');

  try {
    const device = await c.env.DB.prepare(
      'SELECT id, name, registered_at, last_seen_at FROM devices WHERE id = ?'
    ).bind(deviceId).first<Device>();

    if (!device) {
      return c.json({ error: 'Device not found' }, 404);
    }

    return c.json(device, 200);
  } catch (error) {
    console.error('Failed to get device:', error);
    return c.json({ error: 'Failed to get device' }, 500);
  }
};
