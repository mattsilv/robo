---
title: "feat: HIT Push Notifications, MCP Status Indicator, HIT Creation UI"
type: feat
status: completed
date: 2026-02-15
issues: ["#135", "#136", "#137"]
---

# HIT Push Notifications, MCP Status Indicator, HIT Creation UI

Three independent fast-follow features that close the HIT feedback loop, add MCP connection visibility, and bring HIT creation into the iOS app.

## Overview

| # | Feature | Issue | Effort | Key Risk |
|---|---------|-------|--------|----------|
| 1 | Push on HIT completion | #136 | Medium | APNs p8 key prerequisite |
| 2 | MCP connection status | #135 | Small | None — pure addition |
| 3 | HIT creation in iOS | #137 | Medium | Photo URL display in detail view |

All three are independent and can be worked in parallel. #136 and #137 share APNs infrastructure so doing #136 first makes #137's push integration trivial.

---

## Feature 1: Push Notifications via APNs (#136)

### Problem
When a HIT recipient completes a task, the requesting user has no way to know — they'd have to manually poll the app. Push notifications close this feedback loop instantly.

### Proposed Solution

#### Backend (Workers)

**Migration `0004_apns_token.sql`:**
```sql
ALTER TABLE devices ADD COLUMN apns_token TEXT;
ALTER TABLE devices ADD COLUMN apns_token_updated_at TEXT;
```

**New endpoint in `workers/src/routes/devices.ts`:**
```
POST /api/devices/:id/apns-token
Body: { "token": "<hex-encoded APNs device token>" }
Auth: X-Device-ID header (deviceAuth middleware)
```

Follow existing pattern from `devices.ts` — Zod validation, D1 upsert, 200 response. This endpoint should be idempotent (re-registering the same token is a no-op, new token overwrites old).

**APNs sender utility (`workers/src/services/apns.ts` — new file):**
- Sign JWT with ES256 using `crypto.subtle` (Workers have WebCrypto)
- JWT header: `{"alg":"ES256","kid":"${APNS_KEY_ID}"}`
- JWT payload: `{"iss":"R3Z5CY34Q5","iat":timestamp}`
- POST to `https://api.push.apple.com/3/device/{token}` with Bearer JWT
- Cache JWT for ~50 minutes (APNs tokens valid for 1 hour)

**Modify `completeHit()` in `workers/src/routes/hits.ts`:**
After marking HIT complete, fire-and-forget push via `ctx.waitUntil()`:
1. Look up `device_id` from the HIT row
2. Get `apns_token` from devices table
3. If token exists → send push; if NULL → skip silently (no crash)

**Push payload:**
```json
{
  "aps": {
    "alert": {
      "title": "HIT Completed",
      "body": "{recipient_name} completed your request"
    },
    "sound": "default"
  },
  "hit_id": "abc123"
}
```

**Worker secrets needed (via `wrangler secret put`):**
- `APNS_AUTH_KEY` — p8 file contents (PEM-encoded ES256 private key)
- `APNS_KEY_ID` — 10-char key ID from App Store Connect

**Update `workers/src/types.ts` Env interface:**
Add `APNS_AUTH_KEY: string` and `APNS_KEY_ID: string`.

#### iOS

**Push registration in `RoboApp.swift`:**
```swift
@UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
```

Add `.task` in body to request permission:
```swift
.task {
    let center = UNUserNotificationCenter.current()
    let granted = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    if granted == true {
        await MainActor.run { UIApplication.shared.registerForRemoteNotifications() }
    }
}
```

**New file `ios/Robo/AppDelegate.swift`:**
- `UIApplicationDelegate` + `UNUserNotificationCenterDelegate`
- `didRegisterForRemoteNotificationsWithDeviceToken:` → hex-encode token → POST to `/api/devices/:id/apns-token`
- `didFailToRegisterForRemoteNotificationsWithError:` → log error
- `userNotificationCenter(_:didReceive:)` → extract `hit_id` → deep link to HIT detail
- Foreground push: show in-app banner via `willPresent` delegate (show `.banner, .sound`)

**New method in `APIService.swift`:**
```swift
func registerAPNsToken(_ token: String) async throws { ... }
```
Follow existing `post()` pattern with `X-Device-ID` header.

**Entitlements updates:**
- `ios/Robo/Robo.entitlements`: add `aps-environment` = `development`
- `ios/project.yml`: add `remote-notification` to `UIBackgroundModes`

#### Key Files to Touch

| File | Change |
|------|--------|
| `workers/migrations/0004_apns_token.sql` | **New** — add columns |
| `workers/src/routes/devices.ts` | Add `POST /api/devices/:id/apns-token` |
| `workers/src/services/apns.ts` | **New** — JWT signing + push sender |
| `workers/src/routes/hits.ts` | Trigger push in `completeHit()` via `ctx.waitUntil()` |
| `workers/src/types.ts` | Add `APNS_AUTH_KEY`, `APNS_KEY_ID` to Env |
| `workers/src/index.ts` | Register new route |
| `ios/Robo/RoboApp.swift` | Add `@UIApplicationDelegateAdaptor`, permission request |
| `ios/Robo/AppDelegate.swift` | **New** — token handling + deep link |
| `ios/Robo/Services/APIService.swift` | Add `registerAPNsToken()` |
| `ios/Robo/Robo.entitlements` | Add `aps-environment` |
| `ios/project.yml` | Add `remote-notification` background mode |

#### Edge Cases & MVP Decisions

| Edge Case | MVP Decision |
|-----------|-------------|
| `apns_token` is NULL when HIT completes | Skip push silently — no crash |
| Token POST fails (network) | Log error; user can re-trigger by restarting app (token re-registers on every launch) |
| Token expires after reinstall | iOS calls `didRegisterForRemoteNotificationsWithDeviceToken` on every launch → token auto-refreshes |
| Permission denied then re-enabled in Settings | On next app foreground, check `UNUserNotificationCenter.current().notificationSettings()` and re-register if authorized |
| Push received while app in foreground | Show in-app banner via `UNUserNotificationCenterDelegate.willPresent` |
| Deep link to deleted HIT | Show "HIT not found" error in detail view |

#### Prerequisites
- **APNs auth key (p8)** from App Store Connect → `wrangler secret put APNS_AUTH_KEY`
- **APNs Key ID** → `wrangler secret put APNS_KEY_ID`
- Push notification capability in Apple Developer portal

---

## Feature 2: Live MCP Connection Status (#135)

### Problem
MCP is stateless HTTP — users have no way to know if Claude Code is actively connected. A simple heartbeat indicator provides reassurance.

### Proposed Solution

#### Backend (Workers)

**Migration `0005_last_mcp_call.sql`:**
```sql
ALTER TABLE devices ADD COLUMN last_mcp_call_at TEXT;
```

**One-line addition in `workers/src/mcp.ts`:**
After successful Bearer token auth (where `device` is already resolved), add:
```typescript
ctx.waitUntil(
  env.DB.prepare('UPDATE devices SET last_mcp_call_at = ? WHERE id = ?')
    .bind(new Date().toISOString(), device.id).run()
);
```
Fire-and-forget — does not block MCP response.

**`GET /api/devices/:id` response update (`workers/src/routes/devices.ts`):**
Include `last_mcp_call_at` in the device response object. Already returns device fields — just add this column to the SELECT.

#### iOS

**Status indicator in `SettingsView.swift`:**
Add to the "Device" section (after MCP Token row):

```
Within 60s  → 🟢 "Connected"
Within 5min → 🟡 "Recent"
Otherwise   → ⚪ "Not connected"
NULL        → ⚪ "Not connected" (never used MCP)
```

**Polling logic:**
- `@State private var lastMcpCallAt: Date?`
- `.task` modifier with `Timer.publish(every: 30)` or async `Task` loop
- Fetch `GET /api/devices/{id}` every 30s
- Parse `last_mcp_call_at` ISO 8601 → compare to `Date.now`
- On network failure: keep last known state (don't flash to "Not connected")

**Helper text:**
Below the indicator, show small gray text: "Updates when Claude Code uses MCP tools" — explains what "Connected" means without jargon.

#### Key Files to Touch

| File | Change |
|------|--------|
| `workers/migrations/0005_last_mcp_call.sql` | **New** — add column |
| `workers/src/mcp.ts` | One-line `waitUntil` timestamp update |
| `workers/src/routes/devices.ts` | Include `last_mcp_call_at` in GET response |
| `ios/Robo/Views/SettingsView.swift` | Status indicator + polling logic |

#### Edge Cases

| Edge Case | MVP Decision |
|-----------|-------------|
| Polling fails (network) | Keep last known state; retry on next 30s tick |
| First launch (never connected) | Show gray "Not connected" + helper text |
| Multiple consecutive failures | After 3 failures, show subtle "Check connection" note |

---

## Feature 3: HIT Creation Flow in iOS (#137)

### Problem
Backend fully supports HIT creation, but users must use the API directly. A native creation flow with recipient name as a required field enables the core HIT use case.

### Proposed Solution

#### iOS Views

**`CreateHitView.swift` (new):**
- `Form` with sections:
  - **Recipient** section: `TextField("Name", text: $recipientName)` with `.textContentType(.name)` — required, validated client-side (non-empty, max 50 chars)
  - **Task** section: `TextField("What do you need?", text: $taskDescription, axis: .vertical)` — multi-line
  - **Options** section (optional): HIT type picker (photo/poll/text), agent context selector
- "Generate Link" button — disabled until `recipientName` is non-empty
- On success: present `ShareLink` / `UIActivityViewController` with HIT URL
- On error: show inline alert with error message
- Loading state: button shows spinner, disable form during submission

**`HitListView.swift` (new):**
- `List` with `ForEach` over fetched HITs
- Each row: recipient name, task description (truncated), status badge (pending/completed), relative timestamp
- Pull-to-refresh via `.refreshable`
- Empty state: "No HITs yet. Create one to get started."
- Tap row → navigate to `HitDetailView`

**`HitDetailView.swift` (new):**
- Header: recipient name, status, created/completed timestamps
- Task description section
- If completed: show responses and photos
- Photos: fetch from `GET /api/hits/:id/photos` → display image URLs via `AsyncImage`
- Responses: fetch from `GET /api/hits/:id/responses` → display as list

**Entry point:**
Add "HITs" section to `CaptureHomeView` or add a floating "+" button in agents tab. Simplest approach: add a `NavigationLink` in the existing Capture tab leading to `HitListView`, with a toolbar `+` button to `CreateHitView`.

#### APIService Methods

Add to `APIService.swift`:
```swift
func createHit(recipientName: String, taskDescription: String, hitType: String? = nil) async throws -> HitResponse
func fetchHits() async throws -> [HitSummary]
func fetchHit(id: String) async throws -> HitDetail
func fetchHitPhotos(hitId: String) async throws -> [HitPhoto]
func fetchHitResponses(hitId: String) async throws -> [HitResponse]
```

Follow existing pattern: private response models with `CodingKeys` for snake_case mapping, `X-Device-ID` header, `APIError` for failures.

**Response models (private structs in APIService.swift):**
```swift
private struct HitResponse: Decodable {
    let id: String
    let url: String
    let status: String
    let recipientName: String
    let taskDescription: String
    let createdAt: String
    enum CodingKeys: String, CodingKey {
        case id, url, status
        case recipientName = "recipient_name"
        case taskDescription = "task_description"
        case createdAt = "created_at"
    }
}
```

#### Key Files to Touch

| File | Change |
|------|--------|
| `ios/Robo/Views/CreateHitView.swift` | **New** — creation form |
| `ios/Robo/Views/HitListView.swift` | **New** — list view |
| `ios/Robo/Views/HitDetailView.swift` | **New** — detail view |
| `ios/Robo/Services/APIService.swift` | Add HIT API methods + response models |
| `ios/Robo/Views/CaptureHomeView.swift` | Add entry point to HIT list |

#### Backend
No changes needed — all endpoints exist:
- `POST /api/hits` (create)
- `GET /api/hits` (list by device)
- `GET /api/hits/:id` (detail)
- `GET /api/hits/:id/photos` (photos)
- `GET /api/hits/:id/responses` (responses)

#### Edge Cases

| Edge Case | MVP Decision |
|-----------|-------------|
| Empty recipient name | Disable "Generate Link" button; show inline validation |
| Network failure on create | Show alert; don't retry automatically (prevents duplicates) |
| Share sheet dismissed without sharing | HIT exists in backend as `pending` — acceptable for MVP |
| No photos on completed HIT | Show "No photos" placeholder in detail view |
| Photo URLs from R2 | Use existing photo endpoint URLs directly via `AsyncImage` |

---

## Migration Order

Run migrations in sequence before deploying updated Workers code:

```bash
cd workers
wrangler d1 migrations apply robo-db  # Applies 0004 + 0005
wrangler deploy                        # Deploy updated code
```

Verify:
```bash
wrangler d1 execute robo-db --remote \
  --command "SELECT sql FROM sqlite_master WHERE name='devices';"
```

---

## Acceptance Criteria

### #136 — Push Notifications
- [ ] `POST /api/devices/:id/apns-token` saves token to D1
- [ ] `completeHit()` sends push to device when `apns_token` exists
- [ ] iOS requests notification permission on first launch
- [ ] iOS registers APNs token and sends to backend
- [ ] Tapping push notification opens HIT detail view
- [ ] No crash when `apns_token` is NULL

### #135 — MCP Connection Status
- [ ] `last_mcp_call_at` updates on every MCP request (via `waitUntil`)
- [ ] `GET /api/devices/:id` returns `last_mcp_call_at`
- [ ] SettingsView shows green/yellow/gray indicator based on recency
- [ ] Polls every 30s without blocking UI
- [ ] Helper text explains what "Connected" means

### #137 — HIT Creation UI
- [ ] CreateHitView validates recipient name is non-empty
- [ ] Successful creation opens share sheet with HIT URL
- [ ] HitListView shows all device HITs with status badges
- [ ] HitDetailView shows responses and photos for completed HITs
- [ ] Entry point is discoverable from main app navigation

---

## Testing Plan

### Push Notifications (#136)
- [ ] Deploy migration + updated Workers
- [ ] Add APNs secrets: `wrangler secret put APNS_AUTH_KEY` and `APNS_KEY_ID`
- [ ] Build to physical device (push requires real device)
- [ ] Grant notification permission → verify token POST in Workers logs
- [ ] Create HIT → complete via browser → verify push received
- [ ] Tap push → verify deep link to HIT detail
- [ ] Deny permission → complete HIT → verify no crash

### MCP Status (#135)
- [ ] Deploy migration + updated Workers
- [ ] Make MCP call via Claude Code → verify `last_mcp_call_at` updates
- [ ] Open SettingsView → verify green indicator within 60s of MCP call
- [ ] Wait 5+ minutes → verify transitions to gray
- [ ] Kill network → verify indicator doesn't flash/crash

### HIT Creation (#137)
- [ ] Open CreateHitView → verify recipient name required
- [ ] Create HIT → verify share sheet shows correct URL
- [ ] Open HitListView → verify HIT appears with "pending" status
- [ ] Complete HIT via browser → refresh list → verify "completed" status
- [ ] Open HitDetailView → verify photos/responses load

---

## References

- **Primer:** `docs/plans/2026-02-15-fast-follow-hits-push-mcp-status.md`
- **MCP implementation:** `docs/solutions/integration-issues/mcp-server-cloudflare-workers-claude-code-bridge-20260214.md`
- **MCP auth:** `docs/security/mcp-device-scoped-auth-bearer-token-20260214.md`
- **HIT backend:** `workers/src/routes/hits.ts`
- **D1 deployment gotchas:** `docs/solutions/integration-issues/cloudflare-multi-service-deployment-hit-system-20260212.md`
- [APNs HTTP/2 API](https://developer.apple.com/documentation/usernotifications/sending-notification-requests-to-apns)
