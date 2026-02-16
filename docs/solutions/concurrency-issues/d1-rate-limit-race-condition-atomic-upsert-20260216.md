---
title: "Non-Atomic Rate-Limit Check Bypassed Under Concurrency"
category: concurrency-issues
tags:
  - cloudflare-workers
  - hono
  - d1-sqlite
  - rate-limiting
  - atomicity
severity: high
stack:
  - Cloudflare Workers
  - Hono
  - D1 (SQLite)
  - TypeScript
date: 2026-02-16
status: documented
files:
  - workers/src/middleware/rateLimit.ts
  - workers/src/routes/chat.ts
---

# Non-Atomic Rate-Limit Check Bypassed Under Concurrency

## Symptom

Rate limiter on `/api/chat` (20 req / 5 min per device) could be bypassed by concurrent requests. Two requests arriving simultaneously could both read `count = 19` and both proceed, exceeding the limit.

## Root Cause

The middleware used a **read-then-write** pattern — a SELECT to check the count, followed by a separate INSERT/UPDATE to increment. The gap between the two statements created a race window.

## Before (Vulnerable)

```typescript
// Step 1: Read current count
const row = await c.env.DB.prepare(
  'SELECT request_count FROM rate_limits WHERE device_id = ? AND endpoint = ? AND window_start = ?'
).bind(deviceId, config.endpoint, windowStart).first();

const count = row?.request_count ?? 0;

if (count >= config.maxRequests) {
  return c.json({ error: 'Too many requests' }, 429);
}

// Step 2: Increment (separate statement — race condition here)
await c.env.DB.prepare(
  `INSERT INTO rate_limits ... ON CONFLICT DO UPDATE SET request_count = request_count + 1`
).bind(...).run();
```

## After (Atomic)

```typescript
// Single atomic statement: increment first, then check the returned count
const result = await c.env.DB.prepare(
  `INSERT INTO rate_limits (device_id, endpoint, window_start, request_count)
   VALUES (?, ?, ?, 1)
   ON CONFLICT (device_id, endpoint, window_start)
   DO UPDATE SET request_count = request_count + 1
   RETURNING request_count`
).bind(deviceId, config.endpoint, windowStart).first<{ request_count: number }>();

const count = result?.request_count ?? 1;

if (count > config.maxRequests) {
  return c.json({ error: 'Too many requests' }, 429);
}
```

## Key Insight

D1/SQLite supports `RETURNING` on `INSERT...ON CONFLICT`, making the entire check-and-increment atomic in one database round trip. The DB increments first, then returns the new count — no race window.

Note the comparison changed from `>=` to `>` because the count is now post-increment.

## Additional Fixes (Same PR)

1. **Missing event logging on tool-call followup failure** (`chat.ts:270-275`): When the second OpenRouter call (after tool execution) failed, no `logEvent` was emitted. Added error logging with `phase: 'tool_followup'` metadata.

2. **Inconsistent device ID for analytics** (`chat.ts:175`): Chat route read `X-Device-ID` header directly instead of using `c.get('resolvedDeviceId')` from the auth middleware. This caused mismatches when bearer-token-only auth was used. Fixed to prefer `resolvedDeviceId`.

## Prevention

- For any counter/limit pattern in D1, always use `INSERT...ON CONFLICT...RETURNING` instead of read-then-write.
- When adding event logging to a route, audit all exit paths (success, error, fallback) to ensure complete coverage.
- Use the authenticated identity from middleware context (`resolvedDeviceId`), not raw headers, for any downstream logging or business logic.

## Related

- [Gemini rate limits via OpenRouter](../integration-issues/gemini-image-generation-rate-limits-openrouter-20260210.md)
- [Multi-service deployment & D1 verification](../integration-issues/cloudflare-multi-service-deployment-hit-system-20260212.md)
- Migration: `workers/migrations/0009_rate_limits.sql`
- PR: #215
