# M1 Hardening Before Judging

**Epic:** #12 | **Deadline:** Mon Feb 16, 3:00 PM EST
**Goal:** Eliminate first-run failures, ensure truthful API contracts, add auth guardrails, unblock TestFlight.

---

## Execution Order

Issues are grouped into 3 waves by dependency. Work within each wave can be parallelized.

### Wave 1: Foundation (no dependencies, unblocks everything)

#### #20 — Restore passing Workers local typecheck
**Root cause:** `import { randomUUID } from 'node:crypto'` in `devices.ts:3` and `inbox.ts:3` fails because `tsconfig.json` uses `moduleResolution: "node"` and `types` only includes `@cloudflare/workers-types` — no Node type declarations.

**Fix:**
- `workers/tsconfig.json`: change `moduleResolution` from `"node"` to `"bundler"`
- `workers/package.json`: add `"typecheck": "tsc --noEmit"` to scripts
- Alternative (simpler): replace `import { randomUUID } from 'node:crypto'` with `crypto.randomUUID()` which is a Cloudflare Workers global — no import needed, no type issue
- Run `npm run typecheck` and confirm 0 errors

**Files:** `workers/tsconfig.json`, `workers/package.json`, `workers/src/routes/devices.ts`, `workers/src/routes/inbox.ts`

**Acceptance:**
- [x] `cd workers && npm run typecheck` exits 0
- [ ] `wrangler deploy` still works

---

#### #17 — Remove unused iOS Network Extension entitlement
**Root cause:** `Robo.entitlements` declares `packet-tunnel-provider` capability. No VPN/tunnel code exists. This adds signing complexity and App Store review risk.

**Fix:**
- `ios/Robo/Robo.entitlements`: remove the `com.apple.developer.networking.networkextension` key entirely, leaving an empty dict
- `ios/project.yml`: verify `CODE_SIGN_ENTITLEMENTS` still points to the file (it can remain with empty dict), or remove the entitlements reference entirely if no other entitlements are needed

**Files:** `ios/Robo/Robo.entitlements`, `ios/project.yml`

**Acceptance:**
- [x] Entitlements file has no network extension capability
- [ ] `xcodegen generate` succeeds
- [ ] Build succeeds without code signing errors

---

#### #18 — Add required 1024x1024 app icon asset for TestFlight ⛔ GATE
**Root cause:** `AppIcon.appiconset/Contents.json` references `Icon-1024.png` but the file doesn't exist. TestFlight submission will reject the archive.

**Fix:**
- Generate a 1024x1024 PNG app icon (can use a simple placeholder: robot emoji on blue gradient, or use SF Symbols)
- Save as `ios/Robo/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png`
- Verify `Contents.json` already references it correctly (it does — `"filename": "Icon-1024.png"`)

**Files:** `ios/Robo/Resources/Assets.xcassets/AppIcon.appiconset/Icon-1024.png`

**Acceptance:**
- [x] `Icon-1024.png` exists, is exactly 1024x1024, no alpha channel
- [ ] Xcode build succeeds without asset catalog warnings
- [ ] Archive builds and validates for App Store submission

---

### Wave 2: API Hardening (depends on #20 passing typecheck)

#### #16 — Standardize malformed JSON handling to 400 responses
**Root cause:** Every route calls `await c.req.json()` without try-catch. On malformed JSON, this throws a `SyntaxError` which hits `app.onError` in `index.ts:41` and returns 500 with the raw error message. Should be 400.

**Fix — Global approach (one change, fixes all routes):**
- `workers/src/index.ts`: update `app.onError` to detect JSON parse errors:

```typescript
app.onError((err, c) => {
  // Malformed JSON → 400
  if (err instanceof SyntaxError && err.message.includes('JSON')) {
    return c.json({ error: 'Malformed JSON in request body' }, 400);
  }
  console.error('Error:', err);
  return c.json({ error: 'Internal Server Error' }, 500);
});
```

**Why global, not per-route:** There are 6 routes that call `c.req.json()`. Wrapping each one in try-catch is repetitive. The global error handler is the Hono-idiomatic solution.

**Files:** `workers/src/index.ts`

**Acceptance:**
- [x] `POST /api/devices/register` with body `{invalid json` returns 400 `{"error":"Malformed JSON in request body"}`
- [x] `POST /api/sensors/data` with body `not json` returns 400
- [x] Valid JSON requests still work as before
- [x] Internal errors still return 500 (no error message leak)

---

#### #14 — Fix /api/sensors/upload contract so returned URLs are valid ⛔ GATE
**Root cause:** `sensors.ts:57` returns `upload_url: '/api/sensors/upload/${key}'` — a relative path to a route that doesn't exist. No PUT handler is registered in `index.ts` for `/api/sensors/upload/:key`.

**Decision: Simplify (R2 is deferred to M2)**
Since M1 scope excludes R2, the simplest fix is to make the endpoint honest:

**Option A (Recommended — Remove fake endpoint):**
- Remove `getUploadUrl` export from `sensors.ts`
- Remove the `app.post('/api/sensors/upload', getUploadUrl)` route from `index.ts`
- Document in README that file upload is M2

**Option B (Keep stub, return 501):**
- Replace `getUploadUrl` body with: `return c.json({ error: 'File upload available in M2', status: 'not_implemented' }, 501)`

**Files:** `workers/src/routes/sensors.ts`, `workers/src/index.ts`

**Acceptance:**
- [x] No endpoint returns URLs that 404
- [ ] Deploy succeeds
- [x] README reflects actual available endpoints

---

#### #15 — Add lightweight auth guardrails for write endpoints ⛔ GATE
**Root cause:** All write endpoints accept any caller-supplied `device_id` with no verification. `pushCard` is especially dangerous — any external agent can push cards to any device.

**Fix — Hono middleware approach (minimal, hackathon-safe):**

1. Add `X-Device-ID` header requirement for write endpoints via middleware
2. Middleware validates: header present, UUID format, device exists in D1
3. Apply to: `POST /api/sensors/data`, `POST /api/inbox/push`, `POST /api/inbox/:card_id/respond`
4. Leave `POST /api/devices/register` and `GET /api/inbox/:device_id` unprotected (registration must be open; reads are harmless for demo)

```typescript
// workers/src/middleware/deviceAuth.ts
import { createMiddleware } from 'hono/factory';
import type { Env } from '../types';

export const deviceAuth = createMiddleware<{ Bindings: Env }>(async (c, next) => {
  const deviceId = c.req.header('X-Device-ID');
  if (!deviceId) {
    return c.json({ error: 'Missing X-Device-ID header' }, 401);
  }
  const device = await c.env.DB.prepare(
    'SELECT id FROM devices WHERE id = ?'
  ).bind(deviceId).first();
  if (!device) {
    return c.json({ error: 'Unknown device' }, 403);
  }
  await next();
});
```

5. In `index.ts`, apply selectively:
```typescript
import { deviceAuth } from './middleware/deviceAuth';

app.post('/api/sensors/data', deviceAuth, submitSensorData);
app.post('/api/inbox/push', deviceAuth, pushCard);
app.post('/api/inbox/:card_id/respond', deviceAuth, respondToCard);
```

6. Update iOS `APIService.swift` to send `X-Device-ID` header on all requests

**Files:** `workers/src/middleware/deviceAuth.ts` (new), `workers/src/index.ts`, `ios/Robo/Services/APIService.swift`

**Acceptance:**
- [x] `POST /api/sensors/data` without `X-Device-ID` header → 401
- [x] `POST /api/sensors/data` with unregistered UUID → 403
- [x] `POST /api/sensors/data` with valid device ID → works as before
- [x] `POST /api/devices/register` works without header (open)
- [x] iOS app sends header and works end-to-end

---

#### #13 — Device bootstrap registration + unknown device handling ⛔ GATE
**Root cause:** `DeviceService.swift` loads from UserDefaults or falls back to `DeviceConfig.default` — a hardcoded UUID that's never registered on the server. First sensor write will succeed (no device validation) but the device won't be in D1.

**Fix (iOS side):**
1. On first launch (no saved config), call `POST /api/devices/register` with device name
2. Save the server-returned `id` to UserDefaults
3. Add retry logic (3 attempts with exponential backoff) for network failures
4. Show clear error state in UI if registration fails
5. Guard all sensor/inbox calls behind `isRegistered` check

```swift
// DeviceService.swift additions
var isRegistered: Bool { config.id != DeviceConfig.default.id }

func bootstrap(apiService: APIService) async throws {
    guard !isRegistered else { return }
    let registered = try await apiService.registerDevice(name: UIDevice.current.name)
    self.config = registered
    save()
}
```

**Fix (Workers side):**
- After #15 middleware is applied, unregistered devices get 401/403 automatically
- `devices.ts`: add `GET /api/devices/:id` route to let iOS check registration status

**Files:** `ios/Robo/Services/DeviceService.swift`, `ios/Robo/Services/APIService.swift`, `ios/Robo/RoboApp.swift` (or wherever app launch happens), `workers/src/routes/devices.ts`, `workers/src/index.ts`

**Acceptance:**
- [x] Fresh app install → device registers on server before any sensor calls
- [x] Registered device ID persists across app restarts
- [x] Network failure during registration → retry, show error state
- [x] Submitting sensor data with registered device works end-to-end

---

### Wave 3: Polish (depends on Waves 1 + 2)

#### #19 — Align setup docs with actual configuration flow
**Root cause:** README step 2 says `cp .env.example .env` but `.env` isn't consumed by xcodegen or wrangler. The Apple Team ID is hardcoded in `project.yml:11` and `ExportOptions.plist:8`. Cloudflare config is in `wrangler.toml`.

**Fix:**
- Remove the `.env` setup step from README (or make it accurate)
- Document actual config flow:
  1. Workers: edit `wrangler.toml` with your D1 database ID
  2. iOS: edit `project.yml` line 11 with your Apple Team ID
  3. Or, if `.env` is actually desired: add a script that reads `.env` and patches `project.yml`
- Audit `.env.example` — if it's not consumed by anything, delete it or add tooling that uses it

**Files:** `README.md`, `.env.example`

**Acceptance:**
- [x] A new developer can follow README to build and deploy from scratch
- [x] No setup steps reference files/env vars that aren't consumed
- [x] Cloudflare resource IDs are documented or discoverable

---

## Dependency Graph

```
Wave 1 (parallel):
  #20 typecheck ─┐
  #17 entitlements ─┤
  #18 app icon ─────┤
                    ▼
Wave 2 (parallel, after #20):
  #16 JSON 400s ─────┐
  #14 upload contract ─┤
  #15 auth middleware ──┤
                        ▼
  #13 device bootstrap (after #15) ──┐
                                     ▼
Wave 3:
  #19 docs alignment
```

## Estimated LOC by Issue

| Issue | Files Changed | Lines Added | Lines Removed | Complexity |
|-------|:---:|:---:|:---:|:---:|
| #20 typecheck | 4 | ~5 | ~5 | Low |
| #17 entitlements | 2 | 0 | ~5 | Low |
| #18 app icon | 1 | 1 binary | 0 | Low |
| #16 JSON 400s | 1 | ~5 | ~2 | Low |
| #14 upload contract | 2 | ~3 | ~25 | Low |
| #15 auth middleware | 3 | ~30 | ~3 | Medium |
| #13 device bootstrap | 5 | ~50 | ~10 | Medium |
| #19 docs alignment | 2 | ~15 | ~15 | Low |

**Total: ~110 lines added, ~65 removed across ~15 files**

## Risk Notes

- **#15 + #13 are tightly coupled**: Auth middleware must land before bootstrap is meaningful. Implement #15 first.
- **#18 app icon**: Need actual PNG file. Can generate with `sips` or use a placeholder during development.
- **#14**: Removing the upload endpoint is a breaking API change — but since it never worked, nothing depends on it.
- **#20**: Using `crypto.randomUUID()` global is the simplest fix and avoids adding `@types/node` dependency.
