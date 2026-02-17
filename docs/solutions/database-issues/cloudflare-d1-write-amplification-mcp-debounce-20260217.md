---
title: D1 Write Amplification from MCP Hot Path (560K writes/day from heartbeats + event logging)
date: 2026-02-17
category: database-issues
severity: high
status: resolved
project: robo
component: workers/src/mcp.ts, workers/migrations
symptoms:
  - 560K D1 writes/day with no corresponding increase in user-facing activity
  - logEvent() firing on every MCP call (362K writes/day)
  - Unconditional last_mcp_call_at heartbeat update on every request (197K writes/day)
  - Full table scan on devices.mcp_token auth lookup (~33 rows/call × 197K calls/day)
root_cause: Overly aggressive event logging and unconditional heartbeat updates in MCP hot path; missing index on auth lookup column
solution_type: code-removal, query-optimization, schema-change
tags:
  - cloudflare-d1
  - cloudflare-workers
  - mcp
  - write-amplification
  - debouncing
  - indexing
  - cost-optimization
related_issues:
  - https://github.com/mattsilv/robo/issues/235
  - https://github.com/mattsilv/robo/pull/236
time_to_resolve: 2 hours
---

## Symptoms

- Unexpected D1 write costs (~$5/month) despite low user-facing activity
- `wrangler d1 insights robo-db` showing 560K writes/day to robo-db
- No corresponding spike in user-triggered features or data collection
- D1 free tier (25M reads + 100K writes/day) being blown through by internal tooling

## Investigation

Used `wrangler d1 insights robo-db` to identify the top queries by write volume:

| Query | Runs/24h | Writes/24h | Issue |
|-------|----------|------------|-------|
| `INSERT INTO events` (MCP call logging) | 90,686 | 362,744 | Logging every single API call |
| `UPDATE devices SET last_mcp_call_at` | 197,402 | 197,402 | Updating timestamp on every call |
| `SELECT ... FROM devices WHERE mcp_token = ?` | 196,462 | 0 (6.6M reads) | Auth lookup scanning ~33 rows/call |

Cross-referenced with application code in `workers/src/mcp.ts` — both the heartbeat update and `logEvent()` call were in the hot path that fires on every single MCP request, unconditionally.

## Root Cause

Three separate issues compounded to create excessive write load:

**Issue 1: Event logging in hot path (362K writes/day)**
`logEvent()` was called inside `handleMcpRequest()` for every successful MCP request, inserting a row into the append-only `events` table. With Claude agents polling MCP frequently, this generated one D1 write per request with no throttling.

**Issue 2: Unconditional heartbeat updates (197K writes/day)**
Every MCP auth check executed `UPDATE devices SET last_mcp_call_at = NOW() WHERE id = ?` unconditionally. Even requests arriving 100ms apart from the same device triggered separate writes — no debouncing, no minimum interval.

**Issue 3: Missing index on `devices.mcp_token` (read amplifier)**
The `devices` table had no index on `mcp_token`. Every auth check required a full table scan across all devices (~33 rows). This multiplied the 197K heartbeat updates into ~6.5M row scans per day and inflated the cost calculation.

## Solution

Three targeted fixes, all deployed in PR #236:

### Fix 1: Debounce the heartbeat update

Add a conditional `WHERE` clause so D1 only actually modifies a row when the value is stale by more than 1 minute. D1 only bills for rows that are actually written — if the `WHERE` clause filters out the row, no write occurs.

**`workers/src/mcp.ts` — Before:**
```typescript
// Record heartbeat timestamp + event log (fire-and-forget)
if (ctx) {
  ctx.waitUntil(
    env.DB.prepare('UPDATE devices SET last_mcp_call_at = ? WHERE id = ?')
      .bind(new Date().toISOString(), device.id).run()
  );
  logEvent(env, ctx, {
    type: 'mcp_tool_call', device_id: device.id, endpoint: '/mcp', status: 'success',
  });
}
```

**`workers/src/mcp.ts` — After:**
```typescript
// Debounced heartbeat: only write to D1 if last_mcp_call_at is >1 minute stale.
// Skips the write if already recent, reducing from ~197K writes/day to ~1/device/min.
if (ctx) {
  ctx.waitUntil(
    env.DB.prepare(
      `UPDATE devices SET last_mcp_call_at = ?
       WHERE id = ? AND (last_mcp_call_at IS NULL OR last_mcp_call_at < datetime('now', '-1 minute'))`
    ).bind(new Date().toISOString(), device.id).run()
  );
}
```

### Fix 2: Remove `logEvent` from MCP success path

Success event logging for every MCP call is low-value — no dashboard or alerting consumed it — but generated 362K writes/day. Removed entirely from the MCP handler. Error logging in `chat.ts` and `ogImage.ts` is unaffected.

The import was also removed from `mcp.ts` since it was the only call site in that file.

### Fix 3: Add index on `devices.mcp_token`

**`workers/migrations/0012_mcp_token_index.sql` (new file):**
```sql
-- Add index on devices.mcp_token to eliminate full table scans on every auth lookup.
-- Without this index, each MCP auth check scanned the entire devices table (~33 rows/call).
CREATE UNIQUE INDEX idx_devices_mcp_token ON devices (mcp_token) WHERE mcp_token IS NOT NULL;
```

The partial index (`WHERE mcp_token IS NOT NULL`) is a minor optimization to skip null entries.

## Deployment Steps

```bash
# Apply migration to production
cd workers
wrangler d1 migrations apply robo-db --remote

# Deploy updated worker
npm run deploy

# Verify index exists
wrangler d1 execute robo-db --remote --command \
  "SELECT name FROM sqlite_master WHERE type='index' AND name LIKE '%mcp_token%'"
```

## Impact

| Source | Before | After | Reduction |
|--------|--------|-------|-----------|
| `INSERT INTO events` (MCP calls) | 362K writes/day | 0 | 100% |
| `UPDATE devices SET last_mcp_call_at` | 197K writes/day | ~1/device/min | ~99% |
| Auth lookup row scans | ~33 rows/call | 1 row/call | 97% |
| **Total writes/day** | **~560K** | **<5K** | **>99%** |
| Estimated monthly D1 cost | ~$5 | ~$0.02 | ~99% |

## Related Documentation

- [D1 Rate Limit Race Condition & Atomic Upsert](../concurrency-issues/d1-rate-limit-race-condition-atomic-upsert-20260216.md) — related D1 concurrency pattern
- [Cloudflare Resources Inventory](../../cloudflare-resources.md) — D1 database schema and table inventory
- GitHub Issue: https://github.com/mattsilv/robo/issues/235
- PR: https://github.com/mattsilv/robo/pull/236

## Prevention Strategies

### Index every auth column before launch
Any column used in `WHERE` on a hot-path auth check must have an index. Missing indexes on auth columns are a silent cost multiplier — the query still works, just expensively.

### Debounce all heartbeat/timestamp writes
Use a conditional `WHERE old_value < datetime('now', '-N minutes')` pattern for any "last active at" style updates. D1 only charges for rows actually modified — a no-op UPDATE is free.

```sql
-- Pattern: only write if stale
UPDATE table SET timestamp = ? WHERE id = ?
  AND (timestamp IS NULL OR timestamp < datetime('now', '-1 minute'))
```

### Reserve D1 event logging for errors and meaningful events
Append-only success logging in D1 for every request is expensive at scale. Options:
- Log only errors (`status: 'error'`)
- Sample (e.g., 1-in-100 requests)
- Use Workers Analytics Engine for high-frequency observability instead of D1

### Checklist before adding D1 writes to a hot path

- [ ] Estimated calls/day × rows written/call = projected writes/day — acceptable?
- [ ] Is this observability (metrics/logs) or operational state (config/auth)? Observability belongs outside D1.
- [ ] Is there a debouncing strategy (conditional WHERE, TTL cache, batching)?
- [ ] Does every WHERE/JOIN column have an index?
- [ ] Is the write deferred via `ctx.waitUntil()` to avoid blocking response latency?

### Warning signs of write amplification

- A single endpoint accounts for >50% of daily writes
- Write volume spikes without corresponding user activity increase
- `wrangler d1 insights` shows identical queries running hundreds of thousands of times/day
- Heartbeat/health-check endpoints that unconditionally update timestamps
