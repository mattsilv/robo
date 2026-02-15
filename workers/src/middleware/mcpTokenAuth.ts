import { createMiddleware } from 'hono/factory';
import type { Env } from '../types';

/**
 * Requires both X-Device-ID and a valid MCP token (Authorization: Bearer <token>).
 * Verifies the token belongs to the claimed device.
 */
export const mcpTokenAuth = createMiddleware<{ Bindings: Env }>(async (c, next) => {
  const deviceId = c.req.header('X-Device-ID');
  if (!deviceId) {
    return c.json({ error: 'Missing X-Device-ID header' }, 401);
  }

  const authHeader = c.req.header('Authorization');
  if (!authHeader?.startsWith('Bearer ')) {
    return c.json({ error: 'Missing Authorization header' }, 401);
  }
  const token = authHeader.slice(7);

  const device = await c.env.DB.prepare(
    'SELECT id FROM devices WHERE id = ? AND mcp_token = ?'
  ).bind(deviceId, token).first();

  if (!device) {
    return c.json({ error: 'Invalid device credentials' }, 403);
  }

  await next();
});
