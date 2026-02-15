import { describe, it, expect, beforeEach } from 'vitest';
import { env, SELF } from 'cloudflare:test';

// Set up the api_keys table + devices table before each test
beforeEach(async () => {
	await env.DB.exec(`CREATE TABLE IF NOT EXISTS devices (id TEXT PRIMARY KEY, name TEXT, mcp_token TEXT, created_at TEXT DEFAULT (datetime('now')), last_mcp_call_at TEXT)`);
	await env.DB.exec(`CREATE TABLE IF NOT EXISTS api_keys (id TEXT PRIMARY KEY, device_id TEXT NOT NULL, key_value TEXT NOT NULL UNIQUE, label TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')))`);
	await env.DB.exec(`DELETE FROM api_keys`);
	await env.DB.exec(`DELETE FROM devices`);
	await env.DB.exec(`INSERT INTO devices (id, name, mcp_token) VALUES ('dev-1', 'Test Device', 'token-abc-123')`);
});

describe('GET /api/keys', () => {
	it('returns empty array when no keys exist', async () => {
		const resp = await SELF.fetch('https://api.robo.app/api/keys', {
			headers: {
				'X-Device-ID': 'dev-1',
				Authorization: 'Bearer token-abc-123',
			},
		});
		expect(resp.status).toBe(200);
		const body = await resp.json() as { keys: unknown[]; count: number };
		expect(body.keys).toEqual([]);
		expect(body.count).toBe(0);
	});

	it('rejects missing auth header', async () => {
		const resp = await SELF.fetch('https://api.robo.app/api/keys', {
			headers: { 'X-Device-ID': 'dev-1' },
		});
		expect(resp.status).toBe(401);
	});

	it('rejects invalid token', async () => {
		const resp = await SELF.fetch('https://api.robo.app/api/keys', {
			headers: {
				'X-Device-ID': 'dev-1',
				Authorization: 'Bearer wrong-token',
			},
		});
		expect(resp.status).toBe(403);
	});
});

describe('POST /api/keys', () => {
	it('creates a key and returns full value', async () => {
		const resp = await SELF.fetch('https://api.robo.app/api/keys', {
			method: 'POST',
			headers: {
				'X-Device-ID': 'dev-1',
				Authorization: 'Bearer token-abc-123',
				'Content-Type': 'application/json',
			},
			body: JSON.stringify({ label: 'My Key' }),
		});
		expect(resp.status).toBe(201);
		const body = await resp.json() as { id: string; key_value: string; label: string };
		expect(body.key_value).toMatch(/^robo_[0-9a-f]{32}$/);
		expect(body.label).toBe('My Key');
	});

	it('enforces max 3 keys per device', async () => {
		const headers = {
			'X-Device-ID': 'dev-1',
			Authorization: 'Bearer token-abc-123',
			'Content-Type': 'application/json',
		};
		for (let i = 0; i < 3; i++) {
			const r = await SELF.fetch('https://api.robo.app/api/keys', {
				method: 'POST', headers, body: '{}',
			});
			expect(r.status).toBe(201);
		}
		// 4th should fail
		const r = await SELF.fetch('https://api.robo.app/api/keys', {
			method: 'POST', headers, body: '{}',
		});
		expect(r.status).toBe(400);
		const body = await r.json() as { error: string };
		expect(body.error).toContain('Maximum');
	});
});

describe('GET /api/keys (list with data)', () => {
	it('returns masked keys, not full values', async () => {
		const headers = {
			'X-Device-ID': 'dev-1',
			Authorization: 'Bearer token-abc-123',
			'Content-Type': 'application/json',
		};
		await SELF.fetch('https://api.robo.app/api/keys', {
			method: 'POST', headers, body: JSON.stringify({ label: 'test' }),
		});
		const resp = await SELF.fetch('https://api.robo.app/api/keys', { headers });
		const body = await resp.json() as { keys: Array<{ key_hint: string; key_value?: string }> };
		expect(body.keys).toHaveLength(1);
		expect(body.keys[0].key_hint).toContain('••••');
		expect(body.keys[0]).not.toHaveProperty('key_value');
	});
});

describe('DELETE /api/keys/:key_id', () => {
	it('deletes own key', async () => {
		const headers = {
			'X-Device-ID': 'dev-1',
			Authorization: 'Bearer token-abc-123',
			'Content-Type': 'application/json',
		};
		const createResp = await SELF.fetch('https://api.robo.app/api/keys', {
			method: 'POST', headers, body: '{}',
		});
		const { id } = await createResp.json() as { id: string };

		const delResp = await SELF.fetch(`https://api.robo.app/api/keys/${id}`, {
			method: 'DELETE', headers,
		});
		expect(delResp.status).toBe(200);

		const listResp = await SELF.fetch('https://api.robo.app/api/keys', { headers });
		const body = await listResp.json() as { count: number };
		expect(body.count).toBe(0);
	});

	it('returns 404 for nonexistent key', async () => {
		const resp = await SELF.fetch('https://api.robo.app/api/keys/nonexistent', {
			method: 'DELETE',
			headers: {
				'X-Device-ID': 'dev-1',
				Authorization: 'Bearer token-abc-123',
			},
		});
		expect(resp.status).toBe(404);
	});
});
