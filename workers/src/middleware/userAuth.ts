import { createMiddleware } from 'hono/factory';
import { jwtVerify } from 'jose';
import type { Env } from '../types';

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
