---
title: "M1 Hardening: MVP Speed to Demo-Ready"
date: 2026-02-10
problem_type: integration_issue
component: workers, ios
root_cause: mvp_speed_tradeoff
severity: high
tags: [cloudflare-workers, hono, swiftui, device-auth, error-handling, hackathon]
issues: [13, 14, 15, 16, 17, 18, 19, 20]
epic: 12
pr: 21
---

# M1 Hardening: MVP Speed to Demo-Ready

## Problem

After shipping barcode scanning E2E in 4 days, the app had 8 reliability/security gaps that would cause first-run failures, confuse reviewers, or block TestFlight submission. Every issue existed because we chose "move fast" over "be complete" — and every fix was surgical (3-30 LOC).

## Symptoms

| What a user/reviewer would hit | Root cause |
|---|---|
| Fresh install → sensor writes fail silently | Device never registered on server; hardcoded UUID in `DeviceConfig.default` |
| `POST /api/sensors/upload` returns URL that 404s | Route handler returned relative path to nonexistent endpoint |
| Any agent can push cards to any device | No device validation on write endpoints |
| Malformed JSON → 500 with raw error message leak | No SyntaxError catch in global error handler |
| `npm run typecheck` fails | `import { randomUUID } from 'node:crypto'` unresolvable in Workers types |
| TestFlight submission rejected | Missing 1024x1024 app icon |
| App Store review risk | Unused `packet-tunnel-provider` Network Extension entitlement |
| New dev can't follow README | Setup steps reference `.env` that nothing consumes |

## Solution: 5 Patterns

### 1. Device Auth Middleware (Hono `createMiddleware`)

**Problem:** Write endpoints accepted any caller-supplied `device_id` with no verification.

**Fix:** Header-based device validation middleware applied selectively to write routes.

```typescript
// workers/src/middleware/deviceAuth.ts
export const deviceAuth = createMiddleware<{ Bindings: Env }>(async (c, next) => {
  const deviceId = c.req.header('X-Device-ID');
  if (!deviceId) return c.json({ error: 'Missing X-Device-ID header' }, 401);

  const device = await c.env.DB.prepare(
    'SELECT id FROM devices WHERE id = ?'
  ).bind(deviceId).first();
  if (!device) return c.json({ error: 'Unknown device' }, 403);

  await next();
});

// workers/src/index.ts — apply selectively
app.post('/api/sensors/data', deviceAuth, submitSensorData);
app.post('/api/inbox/push', deviceAuth, pushCard);
// Registration stays open: app.post('/api/devices/register', registerDevice);
```

**Why this over alternatives:**
- No JWT/OAuth complexity for hackathon scope
- Two-level validation: 401 (missing header) vs 403 (unknown device)
- Composable — add to any route with one argument
- D1 prepared statement prevents SQL injection

### 2. Global JSON Error Handler

**Problem:** `c.req.json()` throws `SyntaxError` on malformed input → caught by `app.onError` → returns 500.

**Fix:** One check in the global error handler, fixes all 6 routes at once.

```typescript
app.onError((err, c) => {
  if (err instanceof SyntaxError && err.message.includes('JSON')) {
    return c.json({ error: 'Malformed JSON in request body' }, 400);
  }
  console.error('Error:', err);
  return c.json({ error: 'Internal Server Error' }, 500);
});
```

**Why global, not per-route:** 6 routes call `c.req.json()`. Wrapping each in try-catch is repetitive. The Hono `onError` hook is the idiomatic solution.

### 3. Workers Global `crypto.randomUUID()` (not node:crypto)

**Problem:** `import { randomUUID } from 'node:crypto'` fails typecheck because `@cloudflare/workers-types` doesn't include Node type declarations.

**Fix:** Use the Workers runtime global instead.

```typescript
// Before (fails typecheck)
import { randomUUID } from 'node:crypto';
const id = randomUUID();

// After (works everywhere)
const id = crypto.randomUUID();
```

**Why:** `crypto` is a global in Cloudflare Workers (like `fetch`). No import needed, no `@types/node` dependency, no `moduleResolution` changes.

### 4. Device Bootstrap with Exponential Backoff (iOS)

**Problem:** `DeviceConfig.default` generated a random UUID client-side that was never registered with the server.

**Fix:** Sentinel value for unregistered state + bootstrap on first launch with 3× retry.

```swift
// DeviceConfig.swift — sentinel value
static let unregisteredID = "unregistered"
var isRegistered: Bool { id != Self.unregisteredID }

// DeviceService.swift — bootstrap with retry
func bootstrap(apiService: APIService) async {
    guard !isRegistered else { return }
    for attempt in 1...3 {
        do {
            let registered = try await apiService.registerDevice(name: UIDevice.current.name)
            self.config = registered
            save()
            return
        } catch {
            if attempt < 3 {
                try? await Task.sleep(for: .seconds(Double(attempt) * 2))
            }
        }
    }
    self.registrationError = "Registration failed"
}

// RoboApp.swift — wire into launch
.task { await deviceService.bootstrap(apiService: apiService) }
```

**Why sentinel over Optional:** `isRegistered` as computed property from sentinel is simpler than optional unwrapping throughout the codebase.

### 5. Remove Lies, Don't Stub Them

**Problem:** `/api/sensors/upload` returned URLs that 404'd. R2 upload is M2 scope.

**Fix:** Delete the endpoint entirely. Don't return 501, don't leave a stub.

```diff
- import { submitSensorData, getUploadUrl } from './routes/sensors';
+ import { submitSensorData } from './routes/sensors';

- app.post('/api/sensors/upload', getUploadUrl);
```

**Why delete over 501:** A 501 stub still appears in API discovery. Removing it means the README and the code tell the same truth.

## Wave Execution Order

```
Wave 1 (parallel, no dependencies):
  #20 typecheck    — crypto.randomUUID() global
  #17 entitlements — remove packet-tunnel-provider
  #18 app icon     — generate 1024x1024 PNG

Wave 2 (parallel, after #20):
  #16 JSON 400s    — global SyntaxError catch
  #14 upload       — delete fake endpoint
  #15 auth         — deviceAuth middleware
  #13 bootstrap    — DeviceService.bootstrap() (after #15)

Wave 3 (after Waves 1+2):
  #19 docs         — README alignment
```

Total: **123 lines added, 65 removed, 14 files, 1 new file (middleware).**

## Prevention

1. **Add `npm run typecheck` to CI** — catches import issues before deploy
2. **Middleware-first auth** — new write endpoints get `deviceAuth` by default
3. **Global error handler** — new error classes get caught centrally, not per-route
4. **Bootstrap before first API call** — `isRegistered` guard prevents silent failures
5. **Don't ship placeholder endpoints** — if it doesn't work, don't expose it

## Cross-References

- Prior solution: [`docs/solutions/build-errors/hono-zod-cloudflare-workers-validation-20260210.md`](../build-errors/hono-zod-cloudflare-workers-validation-20260210.md) — why we use manual Zod `.safeParse()` instead of `@hono/zod-validator`
- Plan: [`plans/hardening-m1-before-judging.md`](../../plans/hardening-m1-before-judging.md)
- PR: [#21](https://github.com/mattsilv/robo/pull/21)
- Epic: [#12](https://github.com/mattsilv/robo/issues/12)

## Meta: The Hackathon Hardening Pattern

This sprint represents a pattern for all hackathon MVPs:

1. **Days 1-4 (Ship):** Remove everything non-essential. Get core flow working.
2. **Day 5 (Test):** Hit the gaps. Categorize by: build blockers, API contract lies, security, docs.
3. **Day 6 (Harden):** Organize into dependency waves. Execute in parallel where possible. Surgical fixes, not rewrites.

Every fix here was 3-30 LOC because the hardening was **targeted**, not a refactor.
