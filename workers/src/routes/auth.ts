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

// Web app URL for redirects after OAuth
const WEB_APP_URL = 'https://app.robo.app';

/**
 * Verify Apple id_token, upsert user, return JWT + user info.
 * Shared logic used by both the direct POST and the OAuth callback.
 */
async function verifyAndUpsertAppleUser(
  c: Context<{ Bindings: Env }>,
  idToken: string,
  firstName?: string,
) {
  const jwks = createRemoteJWKSet(new URL(APPLE_JWKS_URI));
  // Accept both the iOS bundle ID and the web Services ID
  const { payload } = await jwtVerify(idToken, jwks, {
    issuer: 'https://appleid.apple.com',
    audience: [c.env.APPLE_CLIENT_ID, 'com.silv.Robo.web'],
  });
  const appleSub = payload.sub!;
  const email = payload.email as string | undefined;

  // Upsert user
  const existingUser = await c.env.DB.prepare(
    'SELECT id, first_name FROM users WHERE apple_sub = ?'
  ).bind(appleSub).first<{ id: string; first_name: string | null }>();

  let userId: string;
  let userName: string | null;

  if (existingUser) {
    userId = existingUser.id;
    userName = existingUser.first_name;
    if (firstName || email) {
      await c.env.DB.prepare(
        `UPDATE users SET
          first_name = COALESCE(?, first_name),
          email = COALESCE(?, email),
          updated_at = datetime('now')
        WHERE id = ?`
      ).bind(firstName ?? null, email ?? null, userId).run();
      if (firstName) userName = firstName;
    }
  } else {
    userId = crypto.randomUUID();
    userName = firstName ?? null;
    await c.env.DB.prepare(
      `INSERT INTO users (id, apple_sub, email, first_name) VALUES (?, ?, ?, ?)`
    ).bind(userId, appleSub, email ?? null, firstName ?? null).run();
  }

  // Issue JWT (7-day expiry)
  const secret = new TextEncoder().encode(c.env.JWT_SECRET);
  const jwt = await new SignJWT({ sub: userId, name: userName })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime('7d')
    .sign(secret);

  return { userId, userName, email, jwt };
}

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

  let result;
  try {
    result = await verifyAndUpsertAppleUser(c, id_token, first_name);
  } catch (err) {
    console.error('Apple token verification failed:', err);
    return c.json({ error: 'Invalid Apple token' }, 401);
  }

  const { userId, userName, email, jwt } = result;

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
 * POST /api/auth/apple/callback
 * OAuth callback for Sign in with Apple (web flow).
 * Apple sends application/x-www-form-urlencoded with code + id_token.
 * Sets HttpOnly session cookie and redirects to the web app.
 */
export async function appleAuthCallback(c: Context<{ Bindings: Env }>) {
  const formData = await c.req.parseBody();
  const idToken = formData['id_token'] as string | undefined;

  if (!idToken) {
    return c.html('<h1>Sign in failed</h1><p>No token received from Apple.</p>', 400);
  }

  // Apple sends user info as a JSON string on first authorization only
  let firstName: string | undefined;
  const userStr = formData['user'] as string | undefined;
  if (userStr) {
    try {
      const user = JSON.parse(userStr);
      firstName = user?.name?.firstName;
    } catch { /* ignore parse errors */ }
  }

  let result;
  try {
    result = await verifyAndUpsertAppleUser(c, idToken, firstName);
  } catch (err) {
    console.error('Apple callback token verification failed:', err);
    return c.html('<h1>Sign in failed</h1><p>Could not verify Apple token.</p>', 401);
  }

  // Set session cookie and redirect to web app
  return new Response(null, {
    status: 302,
    headers: {
      'Location': WEB_APP_URL,
      'Set-Cookie': `robo_session=${result.jwt}; HttpOnly; Secure; SameSite=Lax; Path=/; Max-Age=${7 * 24 * 60 * 60}`,
    },
  });
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

  // Verify device exists and check ownership
  const device = await c.env.DB.prepare(
    'SELECT id, user_id FROM devices WHERE id = ?'
  ).bind(device_id).first<{ id: string; user_id: string | null }>();

  if (!device) {
    return c.json({ error: 'Device not found' }, 404);
  }

  // Prevent hijacking: if device is already linked to a different user, reject
  if (device.user_id && device.user_id !== userId) {
    return c.json({ error: 'Device is already linked to another account' }, 403);
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
