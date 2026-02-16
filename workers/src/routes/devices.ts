import type { Context } from 'hono';
import { z } from 'zod';
import { RegisterDeviceSchema, type Env, type Device } from '../types';

const APNsTokenSchema = z.object({
  token: z.string().min(1).max(200),
});

export const registerDevice = async (c: Context<{ Bindings: Env }>) => {
  const body = await c.req.json();
  const validated = RegisterDeviceSchema.safeParse(body);

  if (!validated.success) {
    return c.json({ error: 'Invalid request body', issues: validated.error.issues }, 400);
  }

  const { name, vendor_id, regenerate_token } = validated.data;
  const now = new Date().toISOString();

  try {
    // If vendor_id provided, check for existing device (idempotent registration)
    if (vendor_id) {
      const existing = await c.env.DB.prepare(
        'SELECT id, name, mcp_token, registered_at, last_seen_at FROM devices WHERE vendor_id = ?'
      ).bind(vendor_id).first<Device & { mcp_token: string }>();

      if (existing) {
        let mcpToken = existing.mcp_token;

        if (regenerate_token) {
          // Re-register: new MCP token, same device identity
          mcpToken = [...crypto.getRandomValues(new Uint8Array(24))]
            .map(b => b.toString(16).padStart(2, '0')).join('');
          await c.env.DB.prepare(
            'UPDATE devices SET name = ?, mcp_token = ?, last_seen_at = ? WHERE id = ?'
          ).bind(name, mcpToken, now, existing.id).run();
        } else {
          await c.env.DB.prepare(
            'UPDATE devices SET name = ?, last_seen_at = ? WHERE id = ?'
          ).bind(name, now, existing.id).run();
        }

        return c.json({
          id: existing.id,
          name,
          mcp_token: mcpToken,
          registered_at: existing.registered_at,
          last_seen_at: now,
        }, 200);
      }
    }

    // Before creating a new device, check if there's a legacy device with matching
    // X-Device-ID but null vendor_id (pre-vendor_id migration). If so, adopt it
    // instead of creating a duplicate.
    if (vendor_id) {
      const existingDeviceId = c.req.header('X-Device-ID');
      if (existingDeviceId) {
        const legacy = await c.env.DB.prepare(
          'SELECT id, mcp_token FROM devices WHERE id = ? AND vendor_id IS NULL'
        ).bind(existingDeviceId).first<{ id: string; mcp_token: string }>();

        if (legacy) {
          // Adopt legacy device: set its vendor_id so future lookups work
          await c.env.DB.prepare(
            'UPDATE devices SET vendor_id = ?, name = ?, last_seen_at = ? WHERE id = ?'
          ).bind(vendor_id, name, now, legacy.id).run();

          return c.json({
            id: legacy.id,
            name,
            mcp_token: legacy.mcp_token,
            registered_at: now,
            last_seen_at: now,
          }, 200);
        }
      }
    }

    // New device — create fresh record
    const deviceId = crypto.randomUUID();
    const mcpToken = [...crypto.getRandomValues(new Uint8Array(24))]
      .map(b => b.toString(16).padStart(2, '0')).join('');

    await c.env.DB.prepare(
      'INSERT INTO devices (id, name, mcp_token, vendor_id, registered_at) VALUES (?, ?, ?, ?, ?)'
    )
      .bind(deviceId, name, mcpToken, vendor_id ?? null, now)
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
      'SELECT id, name, registered_at, last_seen_at, last_mcp_call_at FROM devices WHERE id = ?'
    ).bind(deviceId).first<Device & { last_mcp_call_at: string | null }>();

    if (!device) {
      return c.json({ error: 'Device not found' }, 404);
    }

    return c.json(device, 200);
  } catch (error) {
    console.error('Failed to get device:', error);
    return c.json({ error: 'Failed to get device' }, 500);
  }
};

/**
 * POST /api/devices/:device_id/apns-token — Save APNs push token
 */
export const saveAPNsToken = async (c: Context<{ Bindings: Env }>) => {
  // Use authenticated device ID from header, not path param (prevents cross-device overwrite)
  const deviceId = c.req.header('X-Device-ID')!;

  const body = await c.req.json().catch(() => null);
  if (!body) {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const validated = APNsTokenSchema.safeParse(body);
  if (!validated.success) {
    return c.json({ error: 'Invalid request body', issues: validated.error.issues }, 400);
  }

  const { token } = validated.data;
  const now = new Date().toISOString();

  try {
    const result = await c.env.DB.prepare(
      'UPDATE devices SET apns_token = ?, apns_token_updated_at = ? WHERE id = ?'
    ).bind(token, now, deviceId).run();

    if (!result.meta.changes) {
      return c.json({ error: 'Device not found' }, 404);
    }

    return c.json({ status: 'ok', updated_at: now }, 200);
  } catch (error) {
    console.error('Failed to save APNs token:', error);
    return c.json({ error: 'Failed to save APNs token' }, 500);
  }
};
