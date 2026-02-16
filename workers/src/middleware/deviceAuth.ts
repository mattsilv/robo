import { createMiddleware } from 'hono/factory';
import type { Env } from '../types';

/**
 * Authenticates requests via X-Device-ID header.
 * If a Bearer token is also present, resolves the device ID from the token
 * and stores it in context as 'resolvedDeviceId'. This allows the Share
 * Extension to use Bearer auth (resilient to stale device IDs in keychain).
 */
export const deviceAuth = createMiddleware<{ Bindings: Env }>(async (c, next) => {
  let deviceId = c.req.header('X-Device-ID');

  // If Bearer token is present, resolve the canonical device ID from it.
  // This takes precedence over X-Device-ID (which may be stale).
  const authHeader = c.req.header('Authorization');
  if (authHeader?.startsWith('Bearer ')) {
    const token = authHeader.slice(7);
    const tokenDevice = await c.env.DB.prepare(
      'SELECT id FROM devices WHERE mcp_token = ?'
    ).bind(token).first<{ id: string }>();

    if (tokenDevice) {
      c.set('resolvedDeviceId', tokenDevice.id);
      // If no X-Device-ID header, use the token-resolved ID for backward compat
      if (!deviceId) {
        deviceId = tokenDevice.id;
      }
      await next();
      return;
    }
    // Invalid token — fall through to X-Device-ID check
  }

  if (!deviceId) {
    return c.json({ error: 'Missing X-Device-ID header' }, 401);
  }

  const device = await c.env.DB.prepare(
    'SELECT id FROM devices WHERE id = ?'
  ).bind(deviceId).first();

  if (!device) {
    return c.json({ error: 'Unknown device' }, 403);
  }

  c.set('resolvedDeviceId', deviceId);
  await next();
});
