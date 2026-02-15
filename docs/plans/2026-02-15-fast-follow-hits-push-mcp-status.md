# Fast Follow Primer: HIT Push Notifications, MCP Status, HIT Creation

**Date:** 2026-02-15
**Issues:** #133, #135, #136, #137

---

## Priority Order

| # | Feature | Issue | Effort | Impact |
|---|---------|-------|--------|--------|
| 1 | Push on HIT completion | [#136](https://github.com/mattsilv/robo/issues/136) | Medium | High — closes the feedback loop |
| 2 | MCP connection status | [#135](https://github.com/mattsilv/robo/issues/135) | Small | Medium — feels magical |
| 3 | HIT creation in iOS | [#137](https://github.com/mattsilv/robo/issues/137) | Medium | High — but browser works for now |

**Note:** #133 covers the combined HIT improvements (recipient name + push). #136 and #137 break it into plannable units.

---

## 1. Push Notifications on HIT Completion (#136)

### Current State
- Backend HIT flow is complete (`workers/src/routes/hits.ts`)
- `recipient_name` already required in `CreateHitSchema`
- No push notification infrastructure exists (iOS or backend)

### Backend (Workers)

**New migration** `0004_apns_token.sql`:
```sql
ALTER TABLE devices ADD COLUMN apns_token TEXT;
```

**New endpoint:**
```
POST /api/devices/:id/apns-token
Body: { "token": "<hex-encoded APNs device token>" }
```

**Modify `completeHit()`** in `workers/src/routes/hits.ts`:
```
After marking HIT complete:
1. Look up device_id on the HIT row
2. Get apns_token from devices table
3. Send push via APNs HTTP/2 REST API (https://api.push.apple.com)
```

APNs from Workers uses `fetch()` with HTTP/2. Auth via JWT signed with the APNs auth key (p8 file stored as Worker secret).

**Push payload:**
```json
{
  "aps": {
    "alert": {
      "title": "HIT Completed",
      "body": "Sarah sent 3 photos of the living room"
    },
    "sound": "default"
  },
  "hit_id": "abc123"
}
```

### iOS

**Registration flow:**
1. `RoboApp.swift` — call `UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])`
2. On grant: `UIApplication.shared.registerForRemoteNotifications()`
3. `AppDelegate` adapter — `didRegisterForRemoteNotificationsWithDeviceToken:` → POST hex token to `/api/devices/:id/apns-token`

**Deep linking:**
- Parse `hit_id` from push payload → navigate to HIT detail view

### Key Files to Touch
| File | Change |
|------|--------|
| `workers/migrations/0004_apns_token.sql` | New column |
| `workers/src/routes/devices.ts` | New APNs token endpoint |
| `workers/src/routes/hits.ts` | Trigger push in `completeHit()` |
| `workers/wrangler.toml` | Add `APNS_KEY_ID`, `APNS_TEAM_ID` secrets |
| `ios/Robo/RoboApp.swift` | Push registration |
| `ios/Robo/Services/PushService.swift` | **New** — token management + deep link handling |

### Prerequisites
- APNs auth key (p8) from App Store Connect → add as Worker secret
- Push notification entitlement in `project.yml`
- `aps-environment` entitlement for production

---

## 2. Live Claude Code Connection Status (#135)

### Current State
- MCP is stateless HTTP (no persistent connection)
- No way for the app to know if Claude Code is active

### Approach: Heartbeat Timestamp (cheapest)

**Backend — one-line change:**

New migration `0005_last_mcp_call.sql`:
```sql
ALTER TABLE devices ADD COLUMN last_mcp_call_at TEXT;
```

In `handleMcpRequest()` (`workers/src/mcp.ts`), after successful Bearer token auth:
```typescript
// Fire-and-forget — don't block MCP response
ctx.waitUntil(
  env.DB.prepare('UPDATE devices SET last_mcp_call_at = ? WHERE id = ?')
    .bind(new Date().toISOString(), device.id).run()
);
```

Return `last_mcp_call_at` in `GET /api/devices/:id` response (already exists in `devices.ts`).

### iOS — Status Indicator

Poll `GET /api/devices/{id}` every 30s from SettingsView:

```
Within 60s  → green dot + "Connected"
Within 5min → yellow dot + "Recent"
Otherwise   → gray dot + "Not connected"
```

### Key Files to Touch
| File | Change |
|------|--------|
| `workers/migrations/0005_last_mcp_call.sql` | New column |
| `workers/src/mcp.ts` | One-line timestamp update after auth |
| `workers/src/routes/devices.ts` | Include `last_mcp_call_at` in GET response |
| `ios/Robo/Views/SettingsView.swift` | Status indicator in Device section |

---

## 3. HIT Creation Flow in iOS (#137)

### Current State
- Backend fully supports HIT creation (`POST /api/hits` with Zod validation)
- `recipient_name` is already required: `z.string().min(1).max(50)`
- No iOS views or APIService methods for HITs

### UX Flow
1. Tap "Create HIT" (from agents tab or dedicated section)
2. **Required:** Recipient name — single text field ("Sarah", "Mom", "John from 4B")
3. Task description — what you need from them
4. Optional: agent context, HIT type (photo/poll/availability)
5. "Generate Link" → `POST /api/hits` → share sheet with URL

### iOS Implementation

**APIService.swift — new methods:**
```swift
func createHit(recipientName: String, taskDescription: String, agentName: String? = nil) async throws -> Hit
func fetchHits() async throws -> [Hit]
func fetchHitPhotos(hitId: String) async throws -> [HitPhoto]
func fetchHitResponses(hitId: String) async throws -> [HitResponse]
```

**New views:**
| View | Purpose |
|------|---------|
| `CreateHitView.swift` | Form: recipient name (required), task description, generate button |
| `HitListView.swift` | List of sent HITs with status badges (pending/completed) |
| `HitDetailView.swift` | View responses, photos, completion time |

### Backend Endpoints (all ready)
```
POST   /api/hits              — create (recipient_name, task_description required)
GET    /api/hits              — list by device (X-Device-ID header)
GET    /api/hits/:id          — detail
GET    /api/hits/:id/photos   — photos
GET    /api/hits/:id/responses— responses
```

---

## Dependencies Between Features

```
#136 (Push)  ← independent, can start immediately
#135 (MCP Status) ← independent, can start immediately
#137 (HIT Creation) ← independent, but benefits from #136 (push on completion)
```

All three can be worked on in parallel. #136 and #137 share the APNs infrastructure, so doing #136 first makes #137's push integration trivial.

---

## Secrets & Config Needed

| Secret | Where | Purpose |
|--------|-------|---------|
| APNs Auth Key (p8) | Worker secret `APNS_AUTH_KEY` | Sign JWT for push delivery |
| APNs Key ID | Worker secret `APNS_KEY_ID` | JWT header |
| Apple Team ID | Already have: `R3Z5CY34Q5` | JWT claim |
| App Bundle ID | `com.silv.Robo` | APNs topic |
