---
title: "Crawl Phase: Rate Limiting, Usage Analytics, Tests & MCP Docs"
type: feat
status: completed
date: 2026-02-16
---

# Crawl Phase: Rate Limiting, Usage Analytics, Tests & MCP Docs

## Overview

Minimal "crawl" phase to protect expensive endpoints from abuse, log basic usage data, add test coverage for untested critical paths, and ensure MCP documentation is accurate and points to the remote server.

**Scope:** Simple, pragmatic, D1-only. No Redis, no complex token buckets. Ship today.

## Workstream 1: Basic Rate Limiting

### Approach: Fixed Window Counter in D1

Use a simple fixed-window counter per device per endpoint. One D1 row per (device, endpoint, window). No timestamp arrays, no sliding windows — just a counter and a reset time.

### D1 Migration (`workers/migrations/0009_rate_limits.sql`)

```sql
CREATE TABLE rate_limits (
  device_id TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  window_start TEXT NOT NULL,
  request_count INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (device_id, endpoint, window_start)
);
```

### Middleware (`workers/src/middleware/rateLimit.ts`)

```typescript
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

    // Upsert counter (INSERT OR REPLACE with increment)
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

    // Increment (upsert)
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
```

### Thresholds

| Endpoint | Max Requests | Window | Rationale |
|----------|-------------|--------|-----------|
| `POST /api/chat` | 20 | 5 min | Each request = 2 OpenRouter calls (~$0.002 each) |
| `GET /hit/:id/og.png` | 50 | 5 min | Image generation is CPU-heavy; R2 cache handles repeat requests |

### Wiring (`workers/src/index.ts`)

```typescript
// Add after deviceAuth on chat route
app.post('/api/chat', deviceAuth, rateLimit({ endpoint: 'chat', maxRequests: 20, windowSeconds: 300 }), chatRoute);

// OG images: rate limit by IP (no device auth on this route)
// For OG, deviceId falls back to 'anonymous' — acceptable for crawl phase
// Walk phase: add IP-based limiting via CF-Connecting-IP header
```

**Design decision — OG images:** For crawl phase, OG images already have R2 caching (24h). A cache HIT bypasses generation entirely. Rate limiting only matters for cache misses. Since OG endpoint is unauthenticated, we skip rate limiting it in crawl phase and rely on the R2 cache. Walk phase adds IP-based rate limiting.

### Edge Cases (Accepted in Crawl)

- **Race condition:** Two concurrent requests may both read count=19 and both proceed. Accepted — off by 1 is fine.
- **Stale windows:** Old rows accumulate. Add cleanup in walk phase (DELETE WHERE window_start < 24h ago).
- **Failed OpenRouter calls:** Still count against rate limit. Prevents retry storms.

---

## Workstream 2: Usage Analytics (Event Logging)

### Approach: Async D1 inserts via `waitUntil()`

Never block user requests for logging. Use `c.executionCtx.waitUntil()` for fire-and-forget D1 writes.

### D1 Migration (`workers/migrations/0010_events.sql`)

```sql
CREATE TABLE events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL,          -- chat_request, og_generate, hit_created, mcp_tool_call
  device_id TEXT,              -- NULL for unauthenticated endpoints
  endpoint TEXT NOT NULL,
  status TEXT NOT NULL,        -- success, error, rate_limited
  duration_ms INTEGER,
  metadata TEXT,               -- JSON blob for endpoint-specific data
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_events_type_created ON events (type, created_at);
CREATE INDEX idx_events_device_created ON events (device_id, created_at);
```

### Event Logger (`workers/src/services/eventLogger.ts`)

```typescript
import type { Env } from '../types';

interface LogEvent {
  type: string;
  device_id?: string;
  endpoint: string;
  status: 'success' | 'error' | 'rate_limited';
  duration_ms?: number;
  metadata?: Record<string, unknown>;
}

export function logEvent(env: Env, ctx: ExecutionContext, event: LogEvent) {
  ctx.waitUntil(
    env.DB.prepare(
      `INSERT INTO events (type, device_id, endpoint, status, duration_ms, metadata)
       VALUES (?, ?, ?, ?, ?, ?)`
    ).bind(
      event.type,
      event.device_id ?? null,
      event.endpoint,
      event.status,
      event.duration_ms ?? null,
      event.metadata ? JSON.stringify(event.metadata) : null
    ).run().catch(() => {
      // Silent drop — acceptable for crawl phase
      console.error('Event logging failed:', event.type);
    })
  );
}
```

### What to Log

| Event Type | Where | Metadata |
|-----------|-------|----------|
| `chat_request` | `routes/chat.ts` | `{ model, tool_calls_count, has_tools }` |
| `og_generate` | `routes/ogImage.ts` | `{ hit_id, cache_hit: boolean }` |
| `hit_created` | `routes/hits.ts` | `{ hit_type }` |
| `mcp_tool_call` | `mcp.ts` | `{ tool_name }` |

### Privacy Policy (What We NEVER Log)

- User chat messages or content
- API keys or tokens
- IP addresses
- PII (names, emails)

---

## Workstream 3: Test Coverage

### Current State

Only `workers/src/routes/apikeys.test.ts` exists. Zero coverage for chat, HITs, OG images, rate limiting, or MCP.

### New Test Files

#### `workers/src/middleware/rateLimit.test.ts`

```typescript
// Test cases:
// 1. Requests under limit pass through (200)
// 2. Request at limit returns 429 with Retry-After header
// 3. Different devices have independent limits
// 4. New window resets counter
// 5. X-RateLimit-Remaining decrements correctly
```

#### `workers/src/routes/chat.test.ts`

```typescript
// Test cases:
// 1. Valid chat request returns SSE stream (mock OpenRouter)
// 2. Missing auth returns 401
// 3. Malformed body returns 400
// 4. Rate-limited request returns 429
// 5. OpenRouter timeout returns appropriate error
// 6. Tool call (create_availability_poll) creates HIT in D1
```

#### `workers/src/services/eventLogger.test.ts`

```typescript
// Test cases:
// 1. Event inserted into D1 with correct fields
// 2. Metadata serialized as JSON
// 3. NULL device_id handled correctly
// 4. D1 failure doesn't throw (silent drop)
```

### Test Infrastructure

Tests use existing vitest + `vitest-pool-workers` setup. For chat tests, mock OpenRouter responses using `vi.fn()` on `fetch`.

---

## Workstream 4: MCP Documentation Audit

### Current State

- README.md line 47: `claude mcp add robo --transport http https://mcp.robo.app/mcp` ✅ (correct remote URL)
- MCP endpoint live at `https://mcp.robo.app/mcp` ✅
- Auth: Bearer token from device registration ✅

### Audit Checklist

- [ ] **README.md**: Verify MCP section shows remote URL, not localhost
- [ ] **site/index.html**: Check MCP setup instructions on landing page
- [ ] **iOS app ClaudeCodeConnectionView**: Verify displayed command uses `mcp.robo.app`
- [ ] **CLAUDE.md**: No stale `localhost:8787/mcp` references
- [ ] **docs/solutions/**: Verify MCP solution docs reference remote endpoint
- [ ] **wrangler.toml routes**: Confirm `mcp.robo.app/*` is routed correctly

### Deliverable

Fix any stale references found. No new docs needed — just correctness.

---

## Acceptance Criteria

- [x] `POST /api/chat` returns 429 after 20 requests in 5 minutes (per device)
- [x] Rate limit headers present on all chat responses (`X-RateLimit-Limit`, `X-RateLimit-Remaining`)
- [x] Events table populated with chat/OG/HIT/MCP events (queryable via D1)
- [x] Event logging never blocks user requests (async via `waitUntil`)
- [x] `npm run test` passes with new rate limit + chat + event logger tests
- [x] All MCP docs point to `https://mcp.robo.app/mcp` (no localhost references)
- [x] No user messages or PII logged in events table

## Implementation Order

1. D1 migrations (0009 + 0010) — 10 min
2. Rate limit middleware — 30 min
3. Event logger service — 20 min
4. Wire into chat + OG + HIT + MCP routes — 30 min
5. Write tests (rate limit → chat → event logger) — 1 hr
6. MCP docs audit + fixes — 15 min
7. Deploy + verify — 15 min

**Total estimate: ~3 hours**

## References

- Existing test: `workers/src/routes/apikeys.test.ts` (vitest pattern to follow)
- Device auth: `workers/src/middleware/deviceAuth.ts`
- Chat endpoint: `workers/src/routes/chat.ts`
- MCP server: `workers/src/mcp.ts`
- MCP setup docs: `docs/solutions/integration-issues/mcp-server-cloudflare-workers-claude-code-bridge-20260214.md`
