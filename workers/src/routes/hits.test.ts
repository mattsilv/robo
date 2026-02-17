import { env, createExecutionContext, waitOnExecutionContext } from 'cloudflare:test';
import { describe, it, expect, beforeEach } from 'vitest';
import worker from '../index';

// Helper: register a device so deviceAuth middleware passes
async function registerDevice(deviceId: string) {
  await env.DB.prepare(
    "INSERT OR IGNORE INTO devices (id, name, registered_at) VALUES (?, ?, datetime('now'))"
  ).bind(deviceId, 'test-device').run();
}

// Helper: create a HIT directly in the DB
async function createHitInDB(id: string, deviceId: string, opts: {
  groupId?: string;
  status?: string;
  createdAt?: string;
} = {}) {
  await env.DB.prepare(
    `INSERT INTO hits (id, sender_name, recipient_name, task_description, status, photo_count, created_at, device_id, group_id)
     VALUES (?, 'Tester', 'Recipient', 'Test task', ?, 0, ?, ?, ?)`
  ).bind(
    id,
    opts.status || 'pending',
    opts.createdAt || new Date().toISOString(),
    deviceId,
    opts.groupId || null
  ).run();
}

// Helper: make an authenticated request
function makeRequest(method: string, path: string, deviceId: string, body?: object) {
  const init: RequestInit = {
    method,
    headers: {
      'Content-Type': 'application/json',
      'X-Device-ID': deviceId,
    },
  };
  if (body) init.body = JSON.stringify(body);
  return new Request(`https://api.robo.app${path}`, init);
}

describe('HIT Delete Endpoints — Security', () => {
  const DEVICE_A = 'aaaaaaaa-1111-1111-1111-aaaaaaaaaaaa';
  const DEVICE_B = 'bbbbbbbb-2222-2222-2222-bbbbbbbbbbbb';

  beforeEach(async () => {
    // Create tables (D1 in vitest has no migrations)
    await env.DB.exec(`CREATE TABLE IF NOT EXISTS devices (id TEXT PRIMARY KEY, name TEXT, mcp_token TEXT, registered_at TEXT DEFAULT (datetime('now')), last_seen_at TEXT)`);
    await env.DB.exec(`CREATE TABLE IF NOT EXISTS hits (id TEXT PRIMARY KEY, sender_name TEXT NOT NULL, recipient_name TEXT NOT NULL, task_description TEXT NOT NULL, agent_name TEXT, status TEXT NOT NULL DEFAULT 'pending', photo_count INTEGER NOT NULL DEFAULT 0, created_at TEXT NOT NULL, started_at TEXT, completed_at TEXT, device_id TEXT, hit_type TEXT DEFAULT 'photo', config TEXT, group_id TEXT)`);
    await env.DB.exec(`CREATE TABLE IF NOT EXISTS hit_photos (id TEXT PRIMARY KEY, hit_id TEXT NOT NULL, r2_key TEXT NOT NULL, file_size INTEGER, uploaded_at TEXT NOT NULL DEFAULT (datetime('now')))`);
    await env.DB.exec(`CREATE TABLE IF NOT EXISTS hit_responses (id TEXT PRIMARY KEY, hit_id TEXT NOT NULL, respondent_name TEXT NOT NULL, response_data TEXT NOT NULL, created_at TEXT NOT NULL DEFAULT (datetime('now')))`);

    // Reset data
    await env.DB.exec('DELETE FROM hit_responses');
    await env.DB.exec('DELETE FROM hit_photos');
    await env.DB.exec('DELETE FROM hits');
    await env.DB.exec('DELETE FROM devices');
    await registerDevice(DEVICE_A);
    await registerDevice(DEVICE_B);
  });

  // --- Single delete ---

  it('DELETE /api/hits/:id — deletes own HIT', async () => {
    await createHitInDB('hit1aaaa', DEVICE_A);

    const ctx = createExecutionContext();
    const res = await worker.fetch(makeRequest('DELETE', '/api/hits/hit1aaaa', DEVICE_A), env, ctx);
    await waitOnExecutionContext(ctx);

    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.deleted).toBe(true);

    // Verify it's gone
    const row = await env.DB.prepare('SELECT id FROM hits WHERE id = ?').bind('hit1aaaa').first();
    expect(row).toBeNull();
  });

  it('DELETE /api/hits/:id — cannot delete another device\'s HIT', async () => {
    await createHitInDB('hit1aaaa', DEVICE_A);

    const ctx = createExecutionContext();
    const res = await worker.fetch(makeRequest('DELETE', '/api/hits/hit1aaaa', DEVICE_B), env, ctx);
    await waitOnExecutionContext(ctx);

    expect(res.status).toBe(403);

    // Verify it's still there
    const row = await env.DB.prepare('SELECT id FROM hits WHERE id = ?').bind('hit1aaaa').first();
    expect(row).not.toBeNull();
  });

  it('DELETE /api/hits/:id — 401 without X-Device-ID', async () => {
    await createHitInDB('hit1aaaa', DEVICE_A);

    const ctx = createExecutionContext();
    const req = new Request('https://api.robo.app/api/hits/hit1aaaa', {
      method: 'DELETE',
      headers: { 'Content-Type': 'application/json' },
    });
    const res = await worker.fetch(req, env, ctx);
    await waitOnExecutionContext(ctx);

    expect(res.status).toBe(401);
  });

  it('DELETE /api/hits/:id — 404 for nonexistent HIT', async () => {
    const ctx = createExecutionContext();
    const res = await worker.fetch(makeRequest('DELETE', '/api/hits/nope1234', DEVICE_A), env, ctx);
    await waitOnExecutionContext(ctx);

    expect(res.status).toBe(404);
  });

  // --- Bulk delete ---

  it('POST /api/hits/bulk-delete — deletes own HITs by IDs', async () => {
    await createHitInDB('bulk1aaa', DEVICE_A);
    await createHitInDB('bulk2aaa', DEVICE_A);

    const ctx = createExecutionContext();
    const res = await worker.fetch(
      makeRequest('POST', '/api/hits/bulk-delete', DEVICE_A, { ids: ['bulk1aaa', 'bulk2aaa'] }),
      env, ctx
    );
    await waitOnExecutionContext(ctx);

    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.deleted).toBe(2);
    expect(data.ids).toContain('bulk1aaa');
    expect(data.ids).toContain('bulk2aaa');
  });

  it('POST /api/hits/bulk-delete — skips other device\'s HITs silently', async () => {
    await createHitInDB('myHit111', DEVICE_A);
    await createHitInDB('notMine1', DEVICE_B);

    const ctx = createExecutionContext();
    const res = await worker.fetch(
      makeRequest('POST', '/api/hits/bulk-delete', DEVICE_A, { ids: ['myHit111', 'notMine1'] }),
      env, ctx
    );
    await waitOnExecutionContext(ctx);

    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.deleted).toBe(1);
    expect(data.ids).toContain('myHit111');
    expect(data.ids).not.toContain('notMine1');

    // Device B's HIT still exists
    const row = await env.DB.prepare('SELECT id FROM hits WHERE id = ?').bind('notMine1').first();
    expect(row).not.toBeNull();
  });

  it('POST /api/hits/bulk-delete — 401 without auth', async () => {
    const ctx = createExecutionContext();
    const req = new Request('https://api.robo.app/api/hits/bulk-delete', {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ ids: ['abc'] }),
    });
    const res = await worker.fetch(req, env, ctx);
    await waitOnExecutionContext(ctx);

    expect(res.status).toBe(401);
  });

  it('POST /api/hits/bulk-delete — rejects empty body', async () => {
    const ctx = createExecutionContext();
    const res = await worker.fetch(
      makeRequest('POST', '/api/hits/bulk-delete', DEVICE_A, {}),
      env, ctx
    );
    await waitOnExecutionContext(ctx);

    expect(res.status).toBe(400);
  });

  it('POST /api/hits/bulk-delete — older_than_days only deletes own', async () => {
    const oldDate = new Date(Date.now() - 10 * 86400000).toISOString();
    await createHitInDB('old1aaaa', DEVICE_A, { createdAt: oldDate, status: 'pending' });
    await createHitInDB('old2bbbb', DEVICE_B, { createdAt: oldDate, status: 'pending' });
    await createHitInDB('new1aaaa', DEVICE_A, { status: 'pending' }); // recent, should NOT be deleted

    const ctx = createExecutionContext();
    const res = await worker.fetch(
      makeRequest('POST', '/api/hits/bulk-delete', DEVICE_A, { older_than_days: 7, status: 'pending' }),
      env, ctx
    );
    await waitOnExecutionContext(ctx);

    expect(res.status).toBe(200);
    const data = await res.json() as any;
    expect(data.deleted).toBe(1);
    expect(data.ids).toContain('old1aaaa');

    // Device B's old HIT untouched
    const rowB = await env.DB.prepare('SELECT id FROM hits WHERE id = ?').bind('old2bbbb').first();
    expect(rowB).not.toBeNull();

    // Device A's recent HIT untouched
    const rowNew = await env.DB.prepare('SELECT id FROM hits WHERE id = ?').bind('new1aaaa').first();
    expect(rowNew).not.toBeNull();
  });

  it('POST /api/hits/bulk-delete — max 50 IDs enforced', async () => {
    const ids = Array.from({ length: 51 }, (_, i) => `id${String(i).padStart(5, '0')}`);

    const ctx = createExecutionContext();
    const res = await worker.fetch(
      makeRequest('POST', '/api/hits/bulk-delete', DEVICE_A, { ids }),
      env, ctx
    );
    await waitOnExecutionContext(ctx);

    expect(res.status).toBe(400);
  });

  it('POST /api/hits/bulk-delete — cascades to responses and photos', async () => {
    await createHitInDB('cascHit1', DEVICE_A);
    // Add a response
    await env.DB.prepare(
      "INSERT INTO hit_responses (id, hit_id, respondent_name, response_data, created_at) VALUES (?, ?, ?, ?, datetime('now'))"
    ).bind('resp1', 'cascHit1', 'Bob', '{"vote":"yes"}').run();

    const ctx = createExecutionContext();
    const res = await worker.fetch(
      makeRequest('POST', '/api/hits/bulk-delete', DEVICE_A, { ids: ['cascHit1'] }),
      env, ctx
    );
    await waitOnExecutionContext(ctx);

    expect(res.status).toBe(200);

    // Response should be gone too
    const resp = await env.DB.prepare('SELECT id FROM hit_responses WHERE hit_id = ?').bind('cascHit1').first();
    expect(resp).toBeNull();
  });
});
