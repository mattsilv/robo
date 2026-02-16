import { createMiddleware } from 'hono/factory';
import type { Env } from '../types';

interface RateLimitConfig {
  endpoint: string;
  maxRequests: number;
  windowSeconds: number;
}

export function rateLimit(config: RateLimitConfig) {
  return createMiddleware<{ Bindings: Env }>(async (c, next) => {
    const deviceId = c.get('resolvedDeviceId') || c.req.header('X-Device-ID') || 'anonymous';
    const now = new Date();
    const windowStart = new Date(
      Math.floor(now.getTime() / (config.windowSeconds * 1000)) * (config.windowSeconds * 1000)
    ).toISOString();

    const row = await c.env.DB.prepare(
      'SELECT request_count FROM rate_limits WHERE device_id = ? AND endpoint = ? AND window_start = ?'
    ).bind(deviceId, config.endpoint, windowStart).first<{ request_count: number }>();

    const count = row?.request_count ?? 0;

    if (count >= config.maxRequests) {
      const windowEnd = new Date(new Date(windowStart).getTime() + config.windowSeconds * 1000);
      const retryAfter = Math.ceil((windowEnd.getTime() - now.getTime()) / 1000);
      c.header('Retry-After', String(retryAfter));
      c.header('X-RateLimit-Limit', String(config.maxRequests));
      c.header('X-RateLimit-Remaining', '0');
      return c.json({ error: 'Too many requests', retry_after: retryAfter }, 429);
    }

    await c.env.DB.prepare(
      `INSERT INTO rate_limits (device_id, endpoint, window_start, request_count)
       VALUES (?, ?, ?, 1)
       ON CONFLICT (device_id, endpoint, window_start)
       DO UPDATE SET request_count = request_count + 1`
    ).bind(deviceId, config.endpoint, windowStart).run();

    c.header('X-RateLimit-Limit', String(config.maxRequests));
    c.header('X-RateLimit-Remaining', String(config.maxRequests - count - 1));
    await next();
  });
}
