import { createMiddleware } from 'hono/factory';
import type { Env } from '../types';

export const deviceAuth = createMiddleware<{ Bindings: Env }>(async (c, next) => {
  const deviceId = c.req.header('X-Device-ID');

  if (!deviceId) {
    return c.json({ error: 'Missing X-Device-ID header' }, 401);
  }

  const device = await c.env.DB.prepare(
    'SELECT id FROM devices WHERE id = ?'
  ).bind(deviceId).first();

  if (!device) {
    return c.json({ error: 'Unknown device' }, 403);
  }

  await next();
});
