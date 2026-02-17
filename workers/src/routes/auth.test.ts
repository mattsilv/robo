import { describe, it, expect, beforeAll } from 'vitest';
import { env, createExecutionContext, waitOnExecutionContext } from 'cloudflare:test';
import { SignJWT } from 'jose';
import worker from '../index';

const BASE = 'https://api.robo.app';

function req(path: string, options: RequestInit = {}) {
  return new Request(`${BASE}${path}`, options);
}

beforeAll(async () => {
  await env.DB.prepare(`CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, apple_sub TEXT UNIQUE, google_sub TEXT, email TEXT, first_name TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')), updated_at TEXT NOT NULL DEFAULT (datetime('now')))`).run();
  await env.DB.prepare(`CREATE TABLE IF NOT EXISTS devices (id TEXT PRIMARY KEY, name TEXT, mcp_token TEXT, user_id TEXT, created_at TEXT DEFAULT (datetime('now')), last_seen_at TEXT, last_mcp_call_at TEXT, vendor_id TEXT)`).run();
  await env.DB.prepare(`CREATE TABLE IF NOT EXISTS rate_limits (device_id TEXT NOT NULL, endpoint TEXT NOT NULL, window_start TEXT NOT NULL, request_count INTEGER NOT NULL DEFAULT 1, PRIMARY KEY (device_id, endpoint, window_start))`).run();
  await env.DB.prepare(`CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL, device_id TEXT, endpoint TEXT NOT NULL, status TEXT NOT NULL, duration_ms INTEGER, metadata TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')))`).run();
  await env.DB.prepare(`DELETE FROM users`).run();
  await env.DB.prepare(`DELETE FROM devices`).run();
});

describe('Auth routes', () => {
  describe('POST /api/auth/apple', () => {
    it('rejects missing id_token', async () => {
      const ctx = createExecutionContext();
      const res = await worker.fetch(
        req('/api/auth/apple', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({}),
        }),
        env,
        ctx
      );
      await waitOnExecutionContext(ctx);
      expect(res.status).toBe(400);
      const body = await res.json() as any;
      expect(body.error).toBe('Invalid request');
    });

    it('rejects invalid Apple token', async () => {
      const ctx = createExecutionContext();
      const res = await worker.fetch(
        req('/api/auth/apple', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ id_token: 'invalid.jwt.token' }),
        }),
        env,
        ctx
      );
      await waitOnExecutionContext(ctx);
      expect(res.status).toBe(401);
      const body = await res.json() as any;
      expect(body.error).toBe('Invalid Apple token');
    });
  });

  describe('GET /api/auth/me', () => {
    it('rejects unauthenticated requests', async () => {
      const ctx = createExecutionContext();
      const res = await worker.fetch(req('/api/auth/me'), env, ctx);
      await waitOnExecutionContext(ctx);
      expect(res.status).toBe(401);
    });

    it('returns user info with valid JWT', async () => {
      // First, insert a test user directly
      await env.DB.prepare(
        "INSERT INTO users (id, apple_sub, email, first_name) VALUES (?, ?, ?, ?)"
      ).bind('test-user-1', 'apple-sub-1', 'test@test.com', 'Test').run();

      // Create a valid JWT
      const secret = new TextEncoder().encode(env.JWT_SECRET);
      const jwt = await new SignJWT({ sub: 'test-user-1', name: 'Test' })
        .setProtectedHeader({ alg: 'HS256' })
        .setIssuedAt()
        .setExpirationTime('1h')
        .sign(secret);

      const ctx = createExecutionContext();
      const res = await worker.fetch(
        req('/api/auth/me', {
          headers: { Authorization: `Bearer ${jwt}` },
        }),
        env,
        ctx
      );
      await waitOnExecutionContext(ctx);
      expect(res.status).toBe(200);
      const body = await res.json() as any;
      expect(body.user.id).toBe('test-user-1');
      expect(body.user.first_name).toBe('Test');
    });
  });

  describe('POST /api/auth/link-device', () => {
    it('rejects unauthenticated requests', async () => {
      const ctx = createExecutionContext();
      const res = await worker.fetch(
        req('/api/auth/link-device', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ device_id: '00000000-0000-0000-0000-000000000001' }),
        }),
        env,
        ctx
      );
      await waitOnExecutionContext(ctx);
      expect(res.status).toBe(401);
    });
  });

  describe('POST /api/auth/logout', () => {
    it('clears session cookie', async () => {
      const ctx = createExecutionContext();
      const res = await worker.fetch(
        req('/api/auth/logout', { method: 'POST' }),
        env,
        ctx
      );
      await waitOnExecutionContext(ctx);
      expect(res.status).toBe(200);
      const setCookie = res.headers.get('Set-Cookie');
      expect(setCookie).toContain('Max-Age=0');
    });
  });
});
