import type { Context } from 'hono';
import { SignJWT, jwtVerify, createRemoteJWKSet } from 'jose';
import { z } from 'zod';
import type { Env } from '../types';

// Apple's JWKS endpoint for verifying id_tokens
const APPLE_JWKS_URI = 'https://appleid.apple.com/auth/keys';

const AppleAuthSchema = z.object({
  id_token: z.string().min(1),
  first_name: z.string().max(100).optional(),
});

const LinkDeviceSchema = z.object({
  device_id: z.string().uuid(),
});

/**
 * POST /api/auth/apple
 * Validates Apple id_token, upserts user, returns JWT.
 * Web: sets HttpOnly cookie. iOS: returns token in body.
 */
export async function appleAuth(c: Context<{ Bindings: Env }>) {
  const body = await c.req.json().catch(() => null);
  const parsed = AppleAuthSchema.safeParse(body);
  if (!parsed.success) {
    return c.json({ error: 'Invalid request', details: parsed.error.flatten() }, 400);
  }

  const { id_token, first_name } = parsed.data;

  // Verify Apple id_token via JWKS
  let appleSub: string;
  let email: string | undefined;
  try {
    const jwks = createRemoteJWKSet(new URL(APPLE_JWKS_URI));
    const { payload } = await jwtVerify(id_token, jwks, {
      issuer: 'https://appleid.apple.com',
      audience: c.env.APPLE_CLIENT_ID,
    });
    appleSub = payload.sub!;
    email = payload.email as string | undefined;
  } catch (err) {
    console.error('Apple token verification failed:', err);
    return c.json({ error: 'Invalid Apple token' }, 401);
  }

  // Upsert user
  const existingUser = await c.env.DB.prepare(
    'SELECT id, first_name FROM users WHERE apple_sub = ?'
  ).bind(appleSub).first<{ id: string; first_name: string | null }>();

  let userId: string;
  let userName: string | null;

  if (existingUser) {
    userId = existingUser.id;
    userName = existingUser.first_name;
    // Update email/name if provided (Apple only sends name on first auth)
    if (first_name || email) {
      await c.env.DB.prepare(
        `UPDATE users SET
          first_name = COALESCE(?, first_name),
          email = COALESCE(?, email),
          updated_at = datetime('now')
        WHERE id = ?`
      ).bind(first_name ?? null, email ?? null, userId).run();
      if (first_name) userName = first_name;
    }
  } else {
    userId = crypto.randomUUID();
    userName = first_name ?? null;
    await c.env.DB.prepare(
      `INSERT INTO users (id, apple_sub, email, first_name) VALUES (?, ?, ?, ?)`
    ).bind(userId, appleSub, email ?? null, first_name ?? null).run();
  }

  // Issue JWT (7-day expiry)
  const secret = new TextEncoder().encode(c.env.JWT_SECRET);
  const jwt = await new SignJWT({ sub: userId, name: userName })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime('7d')
    .sign(secret);

  // Determine if request is from web (has Origin header) or iOS
  const origin = c.req.header('Origin');
  const headers: Record<string, string> = {};

  if (origin) {
    // Web: set HttpOnly cookie
    headers['Set-Cookie'] = `robo_session=${jwt}; HttpOnly; Secure; SameSite=None; Path=/; Max-Age=${7 * 24 * 60 * 60}`;
  }

  return c.json({
    user: { id: userId, first_name: userName, email },
    token: origin ? undefined : jwt, // Only return token for iOS
  }, 200, headers);
}

/**
 * POST /api/auth/link-device
 * Links a device to the authenticated user.
 * Requires userAuth middleware.
 */
export async function linkDevice(c: Context<{ Bindings: Env }>) {
  const userId = c.get('userId');
  const body = await c.req.json().catch(() => null);
  const parsed = LinkDeviceSchema.safeParse(body);
  if (!parsed.success) {
    return c.json({ error: 'Invalid request', details: parsed.error.flatten() }, 400);
  }

  const { device_id } = parsed.data;

  // Verify device exists
  const device = await c.env.DB.prepare(
    'SELECT id FROM devices WHERE id = ?'
  ).bind(device_id).first();

  if (!device) {
    return c.json({ error: 'Device not found' }, 404);
  }

  await c.env.DB.prepare(
    'UPDATE devices SET user_id = ? WHERE id = ?'
  ).bind(userId, device_id).run();

  return c.json({ linked: true, device_id });
}

/**
 * GET /api/auth/me
 * Returns current user info. Requires userAuth middleware.
 */
export async function getMe(c: Context<{ Bindings: Env }>) {
  const userId = c.get('userId');

  const user = await c.env.DB.prepare(
    'SELECT id, email, first_name, created_at FROM users WHERE id = ?'
  ).bind(userId).first();

  if (!user) {
    return c.json({ error: 'User not found' }, 404);
  }

  // Get linked devices
  const devices = await c.env.DB.prepare(
    'SELECT id, name, last_seen_at FROM devices WHERE user_id = ?'
  ).bind(userId).all();

  return c.json({ user, devices: devices.results });
}

/**
 * POST /api/auth/logout
 * Clears the session cookie (web). iOS just discards the token locally.
 */
export async function logout(c: Context<{ Bindings: Env }>) {
  return c.json({ ok: true }, 200, {
    'Set-Cookie': 'robo_session=; HttpOnly; Secure; SameSite=None; Path=/; Max-Age=0',
  });
}
