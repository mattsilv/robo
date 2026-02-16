import { describe, it, expect, beforeEach } from 'vitest';
import { env, SELF } from 'cloudflare:test';

beforeEach(async () => {
	await env.DB.exec(`CREATE TABLE IF NOT EXISTS devices (id TEXT PRIMARY KEY, name TEXT, mcp_token TEXT, created_at TEXT DEFAULT (datetime('now')), last_mcp_call_at TEXT, vendor_id TEXT)`);
	await env.DB.exec(`CREATE TABLE IF NOT EXISTS rate_limits (device_id TEXT NOT NULL, endpoint TEXT NOT NULL, window_start TEXT NOT NULL, request_count INTEGER NOT NULL DEFAULT 1, PRIMARY KEY (device_id, endpoint, window_start))`);
	await env.DB.exec(`CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL, device_id TEXT, endpoint TEXT NOT NULL, status TEXT NOT NULL, duration_ms INTEGER, metadata TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')))`);
	await env.DB.exec(`DELETE FROM rate_limits`);
	await env.DB.exec(`DELETE FROM devices`);
	await env.DB.exec(`INSERT INTO devices (id, name, mcp_token) VALUES ('dev-1', 'Test Device', 'token-abc-123')`);
	await env.DB.exec(`INSERT INTO devices (id, name, mcp_token) VALUES ('dev-2', 'Other Device', 'token-def-456')`);
});

const authedHeaders = (deviceId = 'dev-1', token = 'token-abc-123') => ({
	'X-Device-ID': deviceId,
	'Authorization': `Bearer ${token}`,
	'Content-Type': 'application/json',
});

const chatBody = JSON.stringify({
	messages: [{ role: 'user', content: 'hi' }],
});

describe('Rate limiting on /api/chat', () => {
	it('allows requests under the limit', async () => {
		const resp = await SELF.fetch('https://api.robo.app/api/chat', {
			method: 'POST',
			headers: authedHeaders(),
			body: chatBody,
		});
		// May be 502 (no OpenRouter key in test) but NOT 429
		expect(resp.status).not.toBe(429);
		expect(resp.headers.get('X-RateLimit-Limit')).toBe('20');
	});

	it('returns 429 after exceeding limit', async () => {
		// Seed rate_limits to simulate 20 requests already made in this window
		const now = new Date();
		const windowStart = new Date(
			Math.floor(now.getTime() / (300 * 1000)) * (300 * 1000)
		).toISOString();
		await env.DB.prepare(
			`INSERT INTO rate_limits (device_id, endpoint, window_start, request_count) VALUES (?, ?, ?, ?)`
		).bind('dev-1', 'chat', windowStart, 20).run();

		const resp = await SELF.fetch('https://api.robo.app/api/chat', {
			method: 'POST',
			headers: authedHeaders(),
			body: chatBody,
		});
		expect(resp.status).toBe(429);
		const body = await resp.json() as { error: string; retry_after: number };
		expect(body.error).toBe('Too many requests');
		expect(body.retry_after).toBeGreaterThan(0);
		expect(resp.headers.get('Retry-After')).toBeTruthy();
		expect(resp.headers.get('X-RateLimit-Remaining')).toBe('0');
	});

	it('isolates rate limits between devices', async () => {
		// Exhaust dev-1's limit
		const now = new Date();
		const windowStart = new Date(
			Math.floor(now.getTime() / (300 * 1000)) * (300 * 1000)
		).toISOString();
		await env.DB.prepare(
			`INSERT INTO rate_limits (device_id, endpoint, window_start, request_count) VALUES (?, ?, ?, ?)`
		).bind('dev-1', 'chat', windowStart, 20).run();

		// dev-1 should be blocked
		const resp1 = await SELF.fetch('https://api.robo.app/api/chat', {
			method: 'POST',
			headers: authedHeaders('dev-1', 'token-abc-123'),
			body: chatBody,
		});
		expect(resp1.status).toBe(429);

		// dev-2 should still work (not 429)
		const resp2 = await SELF.fetch('https://api.robo.app/api/chat', {
			method: 'POST',
			headers: authedHeaders('dev-2', 'token-def-456'),
			body: chatBody,
		});
		expect(resp2.status).not.toBe(429);
	});

	it('decrements X-RateLimit-Remaining correctly', async () => {
		const resp = await SELF.fetch('https://api.robo.app/api/chat', {
			method: 'POST',
			headers: authedHeaders(),
			body: chatBody,
		});
		expect(resp.headers.get('X-RateLimit-Remaining')).toBe('19');
	});
});
