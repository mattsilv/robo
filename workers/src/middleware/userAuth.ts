import { createMiddleware } from 'hono/factory';
import { jwtVerify } from 'jose';
import type { Env } from '../types';

const ALLOWED_ORIGINS = ['https://app.robo.app', 'https://robo.app', 'http://localhost:5173'];

/**
 * CSRF protection for cookie-authenticated state-changing requests.
 * Validates Origin header matches allowed origins. Bearer-token requests
 * (iOS) are exempt since they aren't vulnerable to CSRF.
 */
export const csrfProtect = createMiddleware<{ Bindings: Env }>(async (c, next) => {
  if (c.req.method === 'GET' || c.req.method === 'HEAD' || c.req.method === 'OPTIONS') {
    return next();
  }
  // Bearer token requests are not CSRF-vulnerable
  const authHeader = c.req.header('Authorization');
  if (authHeader?.startsWith('Bearer ')) {
    return next();
  }
  // Cookie-based requests must have a valid Origin
  const origin = c.req.header('Origin');
  if (!origin || !ALLOWED_ORIGINS.includes(origin)) {
    return c.json({ error: 'Invalid origin' }, 403);
  }
  await next();
});

/**
 * Validates user JWT from:
 * - HttpOnly cookie `robo_session` (web)
 * - Authorization: Bearer <token> header (iOS)
 *
 * Sets c.set('userId') on success. Returns 401 on failure.
 */
export const userAuth = createMiddleware<{ Bindings: Env }>(async (c, next) => {
  // Extract token from cookie or Authorization header
  const cookieHeader = c.req.header('Cookie') ?? '';
  const cookieMatch = cookieHeader.match(/robo_session=([^;]+)/);
  const authHeader = c.req.header('Authorization');

  let token: string | null = null;
  if (cookieMatch) {
    token = cookieMatch[1];
  } else if (authHeader?.startsWith('Bearer ')) {
    token = authHeader.slice(7);
  }

  if (!token) {
    return c.json({ error: 'Authentication required' }, 401);
  }

  try {
    const secret = new TextEncoder().encode(c.env.JWT_SECRET);
    const { payload } = await jwtVerify(token, secret, {
      algorithms: ['HS256'],
    });

    if (!payload.sub) {
      return c.json({ error: 'Invalid token' }, 401);
    }

    c.set('userId', payload.sub);
    await next();
  } catch {
    return c.json({ error: 'Invalid or expired token' }, 401);
  }
});
