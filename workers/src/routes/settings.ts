import type { Context } from 'hono';
import { UserSettingsSchema } from '@robo/shared';
import type { Env } from '../types';

/**
 * GET /api/settings
 * Returns user settings: first_name + linked devices with MCP tokens.
 * Requires userAuth middleware.
 */
export async function getSettings(c: Context<{ Bindings: Env }>) {
  const userId = c.get('userId');

  const user = await c.env.DB.prepare(
    'SELECT first_name FROM users WHERE id = ?'
  ).bind(userId).first<{ first_name: string | null }>();

  if (!user) {
    return c.json({ error: 'User not found' }, 404);
  }

  const devices = await c.env.DB.prepare(
    'SELECT id, name, mcp_token, last_seen_at FROM devices WHERE user_id = ?'
  ).bind(userId).all<{ id: string; name: string; mcp_token: string; last_seen_at: string | null }>();

  return c.json({
    first_name: user.first_name,
    mcp_tokens: (devices.results ?? []).map((d) => ({
      device_id: d.id,
      token: d.mcp_token,
      label: d.name,
      last_seen_at: d.last_seen_at,
    })),
  });
}

/**
 * PATCH /api/settings
 * Updates user settings (currently first_name).
 * Validates with UserSettingsSchema from @robo/shared.
 * Requires userAuth middleware.
 */
export async function updateSettings(c: Context<{ Bindings: Env }>) {
  const userId = c.get('userId');

  const body = await c.req.json().catch(() => null);
  const parsed = UserSettingsSchema.safeParse(body);
  if (!parsed.success) {
    return c.json({ error: 'Invalid request', details: parsed.error.flatten() }, 400);
  }

  const { first_name } = parsed.data;

  if (first_name !== undefined) {
    await c.env.DB.prepare(
      `UPDATE users SET first_name = ?, updated_at = datetime('now') WHERE id = ?`
    ).bind(first_name, userId).run();
  }

  return c.json({ ok: true, first_name });
}
