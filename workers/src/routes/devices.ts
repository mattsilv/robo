import type { Context } from 'hono';
import { RegisterDeviceSchema, type Env } from '../types';
import { randomUUID } from 'node:crypto';

export const registerDevice = async (c: Context<{ Bindings: Env }>) => {
  const body = await c.req.json();
  const validated = RegisterDeviceSchema.safeParse(body);

  if (!validated.success) {
    return c.json({ error: 'Invalid request body', issues: validated.error.issues }, 400);
  }

  const { name } = validated.data;
  const deviceId = randomUUID();
  const now = new Date().toISOString();

  try {
    await c.env.DB.prepare(
      'INSERT INTO devices (id, name, registered_at) VALUES (?, ?, ?)'
    )
      .bind(deviceId, name, now)
      .run();

    return c.json({
      id: deviceId,
      name,
      registered_at: now,
      last_seen_at: null,
    }, 201);
  } catch (error) {
    console.error('Failed to register device:', error);
    return c.json({ error: 'Failed to register device' }, 500);
  }
};
