import { describe, it, expect, beforeAll } from 'vitest';
import { env, createExecutionContext, waitOnExecutionContext } from 'cloudflare:test';
import { SignJWT } from 'jose';
import worker from '../index';

const BASE = 'https://api.robo.app';
const ORIGIN = 'https://app.robo.app';

function req(path: string, options: RequestInit = {}) {
  return new Request(`${BASE}${path}`, options);
}

function post(path: string, body: unknown, extraHeaders: Record<string, string> = {}) {
  return req(path, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json', Origin: ORIGIN, ...extraHeaders },
    body: JSON.stringify(body),
  });
}

beforeAll(async () => {
  await env.DB.prepare(`CREATE TABLE IF NOT EXISTS users (id TEXT PRIMARY KEY, apple_sub TEXT UNIQUE, google_sub TEXT, email TEXT, first_name TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')), updated_at TEXT NOT NULL DEFAULT (datetime('now')))`).run();
  await env.DB.prepare(`CREATE TABLE IF NOT EXISTS devices (id TEXT PRIMARY KEY, name TEXT, mcp_token TEXT, user_id TEXT, created_at TEXT DEFAULT (datetime('now')), last_seen_at TEXT, last_mcp_call_at TEXT, vendor_id TEXT)`).run();
  await env.DB.prepare(`CREATE TABLE IF NOT EXISTS rate_limits (device_id TEXT NOT NULL, endpoint TEXT NOT NULL, window_start TEXT NOT NULL, request_count INTEGER NOT NULL DEFAULT 1, PRIMARY KEY (device_id, endpoint, window_start))`).run();
  await env.DB.prepare(`CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL, device_id TEXT, endpoint TEXT NOT NULL, status TEXT NOT NULL, duration_ms INTEGER, metadata TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')))`).run();
  await env.DB.prepare(`DELETE FROM users`).run();
  await env.DB.prepare(`DELETE FROM devices`).run();
});

async function makeJwt(sub: string) {
  const secret = new TextEncoder().encode(env.JWT_SECRET);
  return new SignJWT({ sub, name: 'Test' })
    .setProtectedHeader({ alg: 'HS256' })
    .setIssuedAt()
    .setExpirationTime('1h')
    .sign(secret);
}

describe('Auth routes', () => {
  describe('POST /api/auth/apple', () => {
    it('rejects missing id_token', async () => {
      const ctx = createExecutionContext();
      const res = await worker.fetch(post('/api/auth/apple', {}), env, ctx);
      await waitOnExecutionContext(ctx);
      expect(res.status).toBe(400);
      const body = await res.json() as { error: string };
      expect(body.error).toBe('Invalid request');
    });

    it('rejects invalid Apple token', async () => {
      const ctx = createExecutionContext();
      const res = await worker.fetch(post('/api/auth/apple', { id_token: 'invalid.jwt.token' }), env, ctx);
      await waitOnExecutionContext(ctx);
      expect(res.status).toBe(401);
      const body = await res.json() as { error: string };
      expect(body.error).toBe('Invalid Apple token');
    });
  });

  describe('CSRF protection', () => {
    it('rejects POST without Origin header', async () => {
      const ctx = createExecutionContext();
      const res = await worker.fetch(
        req('/api/auth/logout', { method: 'POST' }),
        env,
        ctx
      );
      await waitOnExecutionContext(ctx);
      expect(res.status).toBe(403);
      const body = await res.json() as { error: string };
      expect(body.error).toBe('Invalid origin');
    });

    it('rejects POST with wrong Origin', async () => {
      const ctx = createExecutionContext();
      const res = await worker.fetch(
        req('/api/auth/logout', {
          method: 'POST',
          headers: { Origin: 'https://evil.com' },
        }),
        env,
        ctx
      );
      await waitOnExecutionContext(ctx);
      expect(res.status).toBe(403);
    });

    it('allows Bearer token requests without Origin', async () => {
      // Insert user for JWT
      await env.DB.prepare(
        "INSERT OR IGNORE INTO users (id, apple_sub, email, first_name) VALUES (?, ?, ?, ?)"
      ).bind('csrf-test-user', 'apple-csrf', 'csrf@test.com', 'CSRF').run();

      const jwt = await makeJwt('csrf-test-user');
      const ctx = createExecutionContext();
      const res = await worker.fetch(
        req('/api/auth/link-device', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${jwt}` },
          body: JSON.stringify({ device_id: '00000000-0000-0000-0000-000000000099' }),
        }),
        env,
        ctx
      );
      await waitOnExecutionContext(ctx);
      // 404 because device doesn't exist, but NOT 403 — CSRF passed
      expect(res.status).toBe(404);
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
      await env.DB.prepare(
        "INSERT OR IGNORE INTO users (id, apple_sub, email, first_name) VALUES (?, ?, ?, ?)"
      ).bind('test-user-1', 'apple-sub-1', 'test@test.com', 'Test').run();

      const jwt = await makeJwt('test-user-1');
      const ctx = createExecutionContext();
      const res = await worker.fetch(
        req('/api/auth/me', { headers: { Authorization: `Bearer ${jwt}` } }),
        env,
        ctx
      );
      await waitOnExecutionContext(ctx);
      expect(res.status).toBe(200);
      const body = await res.json() as { user: { id: string; first_name: string } };
      expect(body.user.id).toBe('test-user-1');
      expect(body.user.first_name).toBe('Test');
    });
  });

  describe('POST /api/auth/link-device', () => {
    it('rejects unauthenticated requests', async () => {
      const ctx = createExecutionContext();
      const res = await worker.fetch(
        post('/api/auth/link-device', { device_id: '00000000-0000-0000-0000-000000000001' }),
        env,
        ctx
      );
      await waitOnExecutionContext(ctx);
      // Cookie-based request with Origin but no cookie → 401
      expect(res.status).toBe(401);
    });

    it('rejects linking a device owned by another user', async () => {
      // Setup: create two users and a device owned by user-a
      await env.DB.prepare(
        "INSERT OR IGNORE INTO users (id, apple_sub, first_name) VALUES (?, ?, ?)"
      ).bind('user-a', 'apple-a', 'Alice').run();
      await env.DB.prepare(
        "INSERT OR IGNORE INTO users (id, apple_sub, first_name) VALUES (?, ?, ?)"
      ).bind('user-b', 'apple-b', 'Bob').run();
      await env.DB.prepare(
        "INSERT OR IGNORE INTO devices (id, name, user_id) VALUES (?, ?, ?)"
      ).bind('00000000-0000-0000-0000-000000000002', 'Alice Phone', 'user-a').run();

      // user-b tries to claim Alice's device
      const jwt = await makeJwt('user-b');
      const ctx = createExecutionContext();
      const res = await worker.fetch(
        req('/api/auth/link-device', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json', Authorization: `Bearer ${jwt}` },
          body: JSON.stringify({ device_id: '00000000-0000-0000-0000-000000000002' }),
        }),
        env,
        ctx
      );
      await waitOnExecutionContext(ctx);
      expect(res.status).toBe(403);
      const body = await res.json() as { error: string };
      expect(body.error).toBe('Device is already linked to another account');
    });
  });

  describe('POST /api/auth/logout', () => {
    it('clears session cookie', async () => {
      const ctx = createExecutionContext();
      const res = await worker.fetch(
        req('/api/auth/logout', { method: 'POST', headers: { Origin: ORIGIN } }),
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
