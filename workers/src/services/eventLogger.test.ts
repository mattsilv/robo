import { describe, it, expect, beforeEach } from 'vitest';
import { env } from 'cloudflare:test';
import { logEvent } from './eventLogger';

beforeEach(async () => {
	await env.DB.exec(`CREATE TABLE IF NOT EXISTS events (id INTEGER PRIMARY KEY AUTOINCREMENT, type TEXT NOT NULL, device_id TEXT, endpoint TEXT NOT NULL, status TEXT NOT NULL, duration_ms INTEGER, metadata TEXT, created_at TEXT NOT NULL DEFAULT (datetime('now')))`);
	await env.DB.exec(`DELETE FROM events`);
});

// Minimal ExecutionContext stub for tests
function makeCtx(): ExecutionContext {
	const promises: Promise<unknown>[] = [];
	return {
		waitUntil(p: Promise<unknown>) { promises.push(p); },
		passThroughOnException() {},
		props: {},
		_promises: promises,
	} as unknown as ExecutionContext & { _promises: Promise<unknown>[] };
}

describe('eventLogger', () => {
	it('inserts event into D1 with correct fields', async () => {
		const ctx = makeCtx();
		logEvent(env, ctx, {
			type: 'chat_request',
			device_id: 'dev-1',
			endpoint: '/api/chat',
			status: 'success',
			duration_ms: 1234,
			metadata: { model: 'gemini-flash', has_tools: false },
		});

		// Wait for the async insert
		await Promise.all((ctx as any)._promises);

		const row = await env.DB.prepare('SELECT * FROM events WHERE type = ?')
			.bind('chat_request').first<any>();
		expect(row).toBeTruthy();
		expect(row.device_id).toBe('dev-1');
		expect(row.endpoint).toBe('/api/chat');
		expect(row.status).toBe('success');
		expect(row.duration_ms).toBe(1234);
		expect(JSON.parse(row.metadata)).toEqual({ model: 'gemini-flash', has_tools: false });
	});

	it('handles null device_id correctly', async () => {
		const ctx = makeCtx();
		logEvent(env, ctx, {
			type: 'og_generate',
			endpoint: '/hit/:id/og.png',
			status: 'success',
		});

		await Promise.all((ctx as any)._promises);

		const row = await env.DB.prepare('SELECT * FROM events WHERE type = ?')
			.bind('og_generate').first<any>();
		expect(row).toBeTruthy();
		expect(row.device_id).toBeNull();
		expect(row.duration_ms).toBeNull();
		expect(row.metadata).toBeNull();
	});

	it('serializes metadata as JSON', async () => {
		const ctx = makeCtx();
		logEvent(env, ctx, {
			type: 'mcp_tool_call',
			device_id: 'dev-1',
			endpoint: '/mcp',
			status: 'success',
			metadata: { tool_name: 'get_capture' },
		});

		await Promise.all((ctx as any)._promises);

		const row = await env.DB.prepare('SELECT metadata FROM events WHERE type = ?')
			.bind('mcp_tool_call').first<{ metadata: string }>();
		expect(JSON.parse(row!.metadata)).toEqual({ tool_name: 'get_capture' });
	});
});
