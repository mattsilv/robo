---
title: "feat: Add Bluetooth iBeacon Proximity Sensor with Webhook Triggers"
type: feat
date: 2026-02-12
deadline: 2026-02-16T15:00:00-05:00
---

# feat: Add Bluetooth iBeacon Proximity Sensor with Webhook Triggers

## Overview

Add BLE iBeacon proximity detection as a new sensor type in the Robo app. ESP32-S3 beacons placed in rooms broadcast iBeacon signals. The iOS app passively listens and fires webhooks on enter/exit events. Simple use cases: "remind me to move the laundry," "log when I enter the garage," etc.

This is the first **always-on background sensor** in Robo — existing sensors (barcode, camera, LiDAR, motion) are all one-shot captures. This distinction drives several architectural decisions.

## Problem Statement / Motivation

Robo turns phone sensors into APIs for AI agents — but currently all sensors require active user interaction (open app → capture → done). BLE beacons enable **passive, location-aware automation** without the user touching their phone. This unlocks a new category of agent capabilities: context-aware triggers based on physical presence.

**Why it matters for the hackathon demo:** A live demo where walking near a beacon triggers an agent notification is visceral and memorable. It shows Robo isn't just a capture tool — it's an ambient sensor platform.

## Key Design Decisions

### 1. Background dwell-time is NOT possible on iOS

**The user's wish:** "When someone comes within 5 feet and stays for 5+ seconds, fire the webhook."

**Reality:** iOS background beacon monitoring only provides binary enter/exit region events — no proximity, no RSSI, no distance, no dwell time. Ranging (which gives proximity data) only works in foreground or for ~10 seconds after a background region event.

**Decision:** Fire webhooks on raw **enter/exit events** in background. When the app is foregrounded, enrich events with proximity/distance data. Dwell-time filtering (e.g., "only trigger if in room for 5+ seconds") is a **backend/agent concern**, not an iOS concern — the backend receives `enter` at T=0 and `exit` at T=N, and can apply duration thresholds.

### 2. Webhooks go direct from device (not through Workers backend)

For MVP, the iOS app POSTs directly to the user-configured webhook URL. Reasons:
- Simpler architecture (no backend relay)
- Works offline-first (queue locally, retry later)
- User controls where their data goes (privacy-first, matches Robo's philosophy)
- Backend receives a copy via the existing `/api/sensors/data` endpoint for history/analytics

### 3. Beacon management lives in Settings

Beacon monitoring is an always-on background service, not a one-shot capture. It doesn't fit the Agents tab's "request → capture → dismiss" pattern. Beacons get a dedicated section in Settings with a NavigationLink to `BeaconSettingsView`.

However, agents CAN request beacon setup (`.beacon` skill type) which opens the beacon config flow — this is the bridge between the agent system and the always-on sensor.

### 4. `device_id` not `user_id`

The existing app has no user authentication — devices are identified by UUID via `DeviceService`. Webhook payloads use `device_id` for consistency.

### 5. Hardcoded UUID, auto-discover beacons

The app ships with a hardcoded iBeacon UUID (`FDA50693-A4E2-4FB1-AFCF-C0A36F4E4339` — a well-known test UUID, or generate a Robo-specific one). Users flash this UUID to their ESP32-S3 beacons. The app scans for beacons with this UUID and lets users name discovered Minor values as rooms.

## Architecture

```
┌──────────────────────────────────────────────────┐
│  ESP32-S3 Beacons (in each room)                 │
│  Broadcast iBeacon: UUID + Major=1 + Minor=N     │
└──────────────────┬───────────────────────────────┘
                   │ BLE radio (passive, no pairing)
┌──────────────────▼───────────────────────────────┐
│  iOS App                                         │
│  ├── BeaconService (CLLocationManager)           │
│  │   ├── Region Monitoring (background, 24/7)    │
│  │   └── Beacon Ranging (foreground, 1Hz)        │
│  ├── WebhookService                              │
│  │   ├── Direct POST to user-configured URL      │
│  │   ├── Local queue + retry on failure          │
│  │   └── Optional HMAC signature                 │
│  ├── SwiftData (BeaconEventRecord)               │
│  │   └── Local history for My Data tab           │
│  └── APIService (existing)                       │
│       └── Copy to Workers backend for analytics  │
└──────────────────┬───────────────────────────────┘
                   │ HTTPS POST (webhook)
┌──────────────────▼───────────────────────────────┐
│  User's Webhook Consumer (any HTTP endpoint)     │
│  ├── Agent backend                               │
│  ├── Zapier / Make / n8n                         │
│  ├── Home Assistant                              │
│  └── Custom server                               │
└──────────────────────────────────────────────────┘
```

## Webhook Payload

```json
{
  "event": "enter",
  "beacon_minor": 1,
  "room_name": "laundry",
  "proximity": "near",
  "rssi": -42,
  "distance_meters": 1.8,
  "timestamp": "2026-02-12T14:30:00Z",
  "duration_seconds": null,
  "device_id": "550e8400-e29b-41d4-a716-446655440000",
  "source": "foreground_ranging"
}
```

| Field | Type | Notes |
|-------|------|-------|
| `event` | `"enter"` \| `"exit"` | Always present |
| `beacon_minor` | `Int` | Minor value (1-65535), identifies the room |
| `room_name` | `String?` | User-assigned name, null if unnamed |
| `proximity` | `String?` | `"immediate"`, `"near"`, `"far"` — **null in background** |
| `rssi` | `Int?` | Raw signal strength — **null in background** |
| `distance_meters` | `Float?` | Estimated distance — **null in background** |
| `timestamp` | `String` | ISO 8601 UTC |
| `duration_seconds` | `Int?` | Only on `exit` events (includes ~30s iOS exit delay) |
| `device_id` | `String` | Device UUID from `DeviceService` |
| `source` | `String` | `"background_monitor"` or `"foreground_ranging"` |

## Implementation Phases

### Phase 1: Core iOS Beacon Detection (MVP — Demo-Ready)

**Goal:** Detect beacons, fire webhooks, show in history. Enough for the hackathon demo.

**Estimated scope:** ~8 new/modified files

#### New Files

**`ios/Robo/Services/BeaconService.swift`** — Core beacon detection service
- `@Observable class` (not stateless enum — needs to hold CLLocationManager state)
- CLLocationManager delegate for region monitoring + beacon ranging
- Hardcoded iBeacon UUID constant
- `startMonitoring()` / `stopMonitoring()` lifecycle
- Publishes detected beacons, enter/exit events
- Handles permission requests (Always Authorization)
- Debouncing: suppress duplicate enter events for same Minor within 60 seconds

```swift
// Key API surface
@Observable
class BeaconService: NSObject, CLLocationManagerDelegate {
    private let manager = CLLocationManager()
    private(set) var isMonitoring = false
    private(set) var detectedBeacons: [CLBeacon] = []
    private(set) var authorizationStatus: CLAuthorizationStatus = .notDetermined

    static let beaconUUID = UUID(uuidString: "FDA50693-A4E2-4FB1-AFCF-C0A36F4E4339")!

    func requestPermissions() { ... }
    func startMonitoring() { ... }
    func stopMonitoring() { ... }
}
```

**`ios/Robo/Services/WebhookService.swift`** — Webhook delivery with retry
- Fire-and-forget POST to user-configured URL
- Local queue (in-memory array + UserDefaults persistence for pending events)
- Retry: 3 attempts with 5s/15s/45s backoff
- Optional HMAC-SHA256 signature header (`X-Robo-Signature`)

```swift
enum WebhookService {
    static func send(event: BeaconWebhookPayload, to url: URL, secret: String?) async -> WebhookResult
    static func retryPending() async
}
```

**`ios/Robo/Views/BeaconMonitorView.swift`** — Beacon monitoring UI
- Follows existing capture view pattern: instructions → active monitoring → results
- Instructions phase: tipRows explaining what beacons are, permission requirements
- Active phase: real-time list of detected beacons with proximity indicators
- Info button (ℹ️) with sheet showing supported devices (ESP32-S3, hardware links)
- Uses `ContentUnavailableView` when Bluetooth is off or permissions denied

**`ios/Robo/Views/BeaconSettingsView.swift`** — Beacon configuration in Settings
- List of configured beacons (room name, Minor value, active/inactive toggle)
- "Add Beacon" button → scans for nearby beacons, user selects and names one
- Webhook URL text field
- Optional webhook secret field
- "Test Webhook" button → sends test payload
- "Supported Devices" info section

**`ios/Robo/Views/BeaconDetailView.swift`** — Event history detail view
- Shows beacon event timeline for a specific room
- Enter/exit events with timestamps and duration
- Webhook delivery status (success/failed/pending)

#### Modified Files

**`ios/Robo/Models/RoboSchema.swift`** — Add V7 with BeaconEventRecord
```swift
enum RoboSchemaV7: VersionedSchema {
    static var versionIdentifier: Schema.Version = .init(0, 7, 0)
    static var models: [any PersistentModel.Type] = [
        // ... existing models ...
        BeaconEventRecord.self
    ]

    @Model
    final class BeaconEventRecord {
        var eventType: String          // "enter" or "exit"
        var beaconMinor: Int           // Minor value (room ID)
        var roomName: String?          // User-assigned name
        var proximity: String?         // "immediate", "near", "far"
        var rssi: Int?                 // Raw signal strength
        var distanceMeters: Double?    // Estimated distance
        var durationSeconds: Int?      // Only on exit events
        var source: String             // "background_monitor" or "foreground_ranging"
        var webhookStatus: String      // "pending", "sent", "failed"
        var webhookURL: String?        // Where it was sent
        var capturedAt: Date
        var agentId: String?
        var agentName: String?
    }
}
```

**`ios/Robo/Models/AgentConnection.swift`** — Add `.beacon` to SkillType enum (line ~29)
```swift
enum SkillType {
    case lidar, barcode, camera, motion, productScan, beacon
}
```

**`ios/Robo/Models/SensorData.swift`** — Add `.beacon` to SensorType enum (line ~10)
```swift
enum SensorType: String, Codable {
    case barcode, camera, lidar, motion, beacon
}
```

**`ios/Robo/Views/AgentsView.swift`** — Wire up beacon skill
- Add `.beacon` to `enabledSkillTypes` set
- Add case to `handleScanNow()` switch → present `BeaconMonitorView` via `.fullScreenCover`
- Add `buttonLabel` and `buttonIcon` for `.beacon` skill

**`ios/Robo/Views/ScanHistoryView.swift`** — Add beacon events to history
- Add `@Query` for `BeaconEventRecord`
- Add `BeaconEventRow` component
- Add "Beacons" segment to "By Type" picker
- Add navigation destination to `BeaconDetailView`

**`ios/Robo/Views/ContentView.swift`** or **`ios/Robo/Views/SettingsView.swift`** — Add beacon settings section
- NavigationLink to `BeaconSettingsView` in Settings tab
- Show beacon monitoring status indicator

**`ios/project.yml`** — Add permission keys (NOT Info.plist directly — xcodegen overwrites it!)
```yaml
info:
  properties:
    NSLocationWhenInUseUsageDescription: "Robo uses your location to detect nearby Bluetooth beacons for room-based automations."
    NSLocationAlwaysAndWhenInUseUsageDescription: "Robo needs background location access to detect beacons when the app is closed, triggering room-based automations."
    NSBluetoothAlwaysUsageDescription: "Robo uses Bluetooth to detect nearby iBeacon devices for room-aware automations."
    UIBackgroundModes:
      - location
      - bluetooth-central
```

**`workers/src/types.ts`** — Add `'beacon'` to sensor_type enum (line ~42)
```typescript
sensor_type: z.enum(['barcode', 'camera', 'lidar', 'motion', 'beacon']),
```

#### Info Icon / Supported Devices Sheet

Present as a `.sheet` from an info button (ℹ️) on both `BeaconMonitorView` and `BeaconSettingsView`:

```
┌─────────────────────────────────┐
│  Supported Beacon Devices       │
│                                 │
│  ● ESP32-S3-WROOM-1            │
│    ~$5/unit, USB-C powered     │
│    Flash with Robo iBeacon     │
│    firmware                     │
│                                 │
│  ● Any iBeacon-compatible      │
│    device (Estimote, Kontakt,  │
│    RadBeacon, etc.)            │
│                                 │
│  Requirements:                  │
│  • Apple iBeacon protocol       │
│  • UUID: FDA50693-...           │
│  • Major: 1                     │
│  • Minor: 1-65535 (room ID)     │
│                                 │
│  📖 Setup Guide →               │
│                                 │
│          [ Done ]               │
└─────────────────────────────────┘
```

### Phase 2: Polish & Robustness (Post-Demo)

**Goal:** Production-grade reliability and UX.

- [ ] Webhook retry queue with persistent storage (survive app termination)
- [ ] Per-beacon webhook URL configuration (not just global)
- [ ] HMAC-SHA256 webhook signatures (`X-Robo-Signature` header)
- [ ] Local notification on background beacon events (configurable per beacon)
- [ ] Battery usage monitoring and optimization
- [ ] Beacon health indicators (last seen, signal strength history)
- [ ] Export beacon event data (CSV/JSON)
- [ ] Rate limiting: max 1 webhook per beacon per 60 seconds (configurable)

### Phase 3: Agent Integration (Post-Demo)

**Goal:** Agents can request and consume beacon data natively.

- [ ] Mock agent demo: "Laundry Reminder Agent" with pending `.beacon` skill request
- [ ] Agent-configured webhook URLs (agent provides its callback URL)
- [ ] Backend `/api/beacon/events` endpoint for agent consumption
- [ ] Beacon event streaming via WebSocket or SSE
- [ ] Agent can configure trigger rules (dwell time, time-of-day, room combinations)

## Acceptance Criteria

### Phase 1 (MVP — Must Have for Demo)

- [ ] App detects iBeacon broadcasts from ESP32-S3 hardware
- [ ] Background region monitoring fires enter/exit events when app is backgrounded/killed
- [ ] Foreground ranging shows real-time proximity to detected beacons
- [ ] Webhook fires on enter/exit events to user-configured URL
- [ ] Beacon events stored in SwiftData and visible in My Data tab
- [ ] User can name beacons (assign room names to Minor values)
- [ ] User can configure webhook URL in Settings
- [ ] Info icon shows supported beacon devices
- [ ] Instructions screen with tips before starting monitoring
- [ ] Permission flow handles Bluetooth + Location Always authorization
- [ ] `ContentUnavailableView` when Bluetooth off or permissions denied
- [ ] Works after force-quitting app (region monitoring survives)
- [ ] `.beacon` skill type wired into agent system

### Non-Functional

- [ ] No force-unwraps in production code
- [ ] All async functions use `async/await`
- [ ] Permission keys in `project.yml` (not Info.plist directly)
- [ ] Schema migration from V6 → V7 with lightweight migration
- [ ] Debouncing prevents webhook flood at range boundaries

## Dependencies & Prerequisites

| Dependency | Status | Notes |
|------------|--------|-------|
| ESP32-S3 hardware flashed with iBeacon firmware | ✅ Done | User confirmed device is on and communicating |
| Physical iPhone for testing | Required | No simulator support for BLE beacons |
| iPhone model with BLE 4.0+ | Required | Any iPhone 5s or later (all modern iPhones) |
| CoreLocation framework | Available | System framework, no SPM dependency needed |
| CoreBluetooth framework | Available | System framework, no SPM dependency needed |
| Cloudflare Workers running | ✅ Running | For optional backend copy of events |

## Risk Analysis & Mitigation

| Risk | Likelihood | Impact | Mitigation |
|------|-----------|--------|------------|
| "Always" location permission denied by user | High | Blocks background monitoring | Clear permission rationale, fallback to foreground-only mode |
| Webhook endpoint unreachable | Medium | Events lost | Local queue + retry, SwiftData persistence |
| Background execution window too short for webhook | Low | Webhook not sent | Use `URLSession` background transfer (survives app suspension) |
| Rapid enter/exit flapping at range boundary | Medium | Webhook flood | 60-second debounce per beacon Minor |
| App Store rejection for background location | Low | Blocks release | Clear Info.plist descriptions, only request when user enables beacons |
| Exit event ~30s delay confuses duration calculations | Medium | Inaccurate data | Document in webhook payload docs, backend adjusts |

## Key Gotchas (from Local Research)

1. **NEVER edit Info.plist directly** — xcodegen overwrites it. Add all permission keys to `project.yml` under `targets.Robo.info.properties`. Verify with `xcodegen generate && grep NSBluetooth ios/Robo/Info.plist`.

2. **CLLocationManager delegates may need NSCoding stubs** — If wrapping in UIViewRepresentable, add `required init?(coder:)` and `encode(with:)` stubs. Use `@objc("RoboBeaconCoordinator")` annotation.

3. **Explicit `modelContext.save()` before dismiss** — SwiftData autosave is unreliable during view dismissal. Always save explicitly.

4. **Schema versioning is mandatory** — Create `RoboSchemaV7`, add migration stage. Don't modify V6.

5. **Exit events take ~30 seconds** — iOS waits 30 seconds of no signal before firing `didExitRegion`. This is by design to prevent flapping. Document this for webhook consumers.

6. **Background ranging is limited to ~10 seconds** — After a region enter event wakes the app in background, you get ~10 seconds of ranging before iOS suspends you again. Use this window to identify the specific Minor value and fire the webhook.

7. **Request "Always" authorization properly** — Must call `requestWhenInUseAuthorization()` first, wait for grant, then call `requestAlwaysAuthorization()`. iOS only shows the "Always" upgrade prompt once; after that, user must go to Settings.

## Testing Plan

- [ ] Beacon detected in foreground — correct Minor value and proximity
- [ ] Proximity values update as you move closer/farther from beacon
- [ ] Background monitoring fires `didEnterRegion` when app is backgrounded
- [ ] Webhook fires on enter with correct `beacon_minor` and `timestamp`
- [ ] Webhook fires on exit with correct `duration_seconds`
- [ ] Works after force-quitting app (region monitoring survives)
- [ ] App launch triggers `didDetermineState` with current region state
- [ ] Permission denied → `ContentUnavailableView` with Settings link
- [ ] Bluetooth off → appropriate error UI
- [ ] Webhook failure → event queued locally, retry on next opportunity
- [ ] Multiple beacons → correct room identification by Minor value
- [ ] Debouncing → rapid enter/exit at range boundary doesn't flood webhooks
- [ ] Info icon → shows supported devices sheet
- [ ] My Data tab → beacon events appear with correct data
- [ ] Settings → can configure webhook URL and beacon names

## References

### Internal
- Existing sensor patterns: `ios/Robo/Views/BarcodeScannerView.swift`, `LiDARScanView.swift`, `PhotoCaptureView.swift`, `MotionCaptureView.swift`
- Service pattern: `ios/Robo/Services/MotionService.swift` (stateless enum), `APIService.swift` (observable class)
- Schema versioning: `ios/Robo/Models/RoboSchema.swift` (V6 current)
- Agent skill registration: `ios/Robo/Models/AgentConnection.swift:29` (SkillType enum)
- Backend sensor types: `workers/src/types.ts:42` (Zod enum)
- xcodegen Info.plist gotcha: `docs/solutions/build-errors/xcodegen-drops-info-plist-keys-testflight-compliance-20260210.md`
- Compound capture flow pattern: `docs/solutions/architecture-patterns/compound-multi-sensor-capture-flow-pattern-20260212.md`

### External
- Apple iBeacon docs: `CLLocationManager`, `CLBeaconRegion`, `CLBeaconIdentityConstraint`
- User's hardware research: `/Users/m/gh/sensors/docs/ios-integration-primer.md`
- ESP32-S3-WROOM-1 datasheet (beacon hardware)

### RSSI to Distance Reference (from hardware testing)

| RSSI | Approx Distance | CLProximity |
|------|-----------------|-------------|
| -10 to -30 | Touching / inches | .immediate |
| -30 to -50 | Same desk / few feet | .immediate / .near |
| -50 to -70 | Same room | .near |
| -70 to -85 | Adjacent room | .far |
| > -85 | Far / unreliable | .unknown |
