---
title: "feat: Beacon Registration with Configurable UUID and Sensor Data Display"
type: feat
date: 2026-02-13
deadline: 2026-02-16T15:00:00-05:00
---

# feat: Beacon Registration with Configurable UUID and Sensor Data Display

## Overview

The beacon feature is fully implemented but **won't detect real hardware** because the UUID is hardcoded to a test value (`FDA50693-A4E2-4FB1-AFCF-C0A36F4E4339`). The user's actual beacons broadcast `12345678-9ABC-DEF0-1234-56789ABCDEF0`. This issue makes the UUID configurable, improves the beacon registration UX, and enhances the sensor data display.

## Problem Statement

1. **UUID mismatch** — hardcoded UUID doesn't match real hardware, so no beacons are ever detected
2. **No UUID configuration** — user can't enter their beacon's UUID anywhere in the app
3. **Sensor data display** — monitoring view shows basic info but could surface richer proximity/RSSI data for testing

## Acceptance Criteria

- [ ] User can configure beacon UUID in Settings → Beacons (default: `12345678-9ABC-DEF0-1234-56789ABCDEF0`)
- [ ] BeaconService reads UUID from config instead of hardcoded constant
- [ ] BeaconMonitorView shows live RSSI, distance, and proximity for each detected beacon
- [ ] "Add Beacon" discovery scan uses the configured UUID
- [ ] User's 6 beacons (Office, Kitchen, Bedroom, Living Room, Garage, Bathroom) can be registered
- [ ] Supported Devices sheet reflects configurable UUID
- [ ] Builds cleanly for physical device

## Implementation

### 1. `BeaconConfigStore` — Add UUID storage (`ios/Robo/Views/BeaconSettingsView.swift:417`)

```swift
// Add to BeaconConfigStore enum
private static let uuidKey = "beaconUUID"
static let defaultUUID = "12345678-9ABC-DEF0-1234-56789ABCDEF0"

static func loadUUID() -> UUID {
    let stored = UserDefaults.standard.string(forKey: uuidKey) ?? defaultUUID
    return UUID(uuidString: stored) ?? UUID(uuidString: defaultUUID)!
}

static func saveUUID(_ uuidString: String) {
    UserDefaults.standard.set(uuidString, forKey: uuidKey)
}
```

### 2. `BeaconService.swift` — Use configurable UUID (`ios/Robo/Services/BeaconService.swift:13`)

Replace hardcoded UUID:
```swift
// Before
static let beaconUUID = UUID(uuidString: "FDA50693-A4E2-4FB1-AFCF-C0A36F4E4339")!

// After
static var beaconUUID: UUID { BeaconConfigStore.loadUUID() }
```

### 3. `BeaconSettingsView.swift` — Add UUID configuration field

Add a new section above the beacons list:
```swift
Section {
    TextField("Beacon UUID", text: $beaconUUID)
        .font(.caption.monospaced())
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .onChange(of: beaconUUID) { _, newValue in
            BeaconConfigStore.saveUUID(newValue)
        }
} header: {
    Text("Beacon UUID")
} footer: {
    Text("All your beacons must share this UUID. Default matches Robo firmware.")
}
```

### 4. `BeaconMonitorView.swift` — Enhance sensor data in `BeaconRow`

The existing `BeaconRow` already shows Minor, distance, RSSI, and proximity badge. Enhance with:
- Signal strength bar visualization (based on RSSI)
- Distance in feet alongside meters
- Update frequency indicator

### 5. `SupportedDevicesSheet` — Show actual configured UUID

Replace hardcoded "FDA50693-..." with live value from `BeaconConfigStore.loadUUID()`.

## Files Modified

| File | Change |
|------|--------|
| `ios/Robo/Services/BeaconService.swift` | Replace hardcoded UUID with configurable read |
| `ios/Robo/Views/BeaconSettingsView.swift` | Add UUID config section, update BeaconConfigStore |
| `ios/Robo/Views/BeaconMonitorView.swift` | Enhanced sensor data display in BeaconRow |

## Context

- User has 6 ESP32-S3 beacons: Major=1, Minor=1-6 (Office, Kitchen, Bedroom, Living Room, Garage, Bathroom)
- Beacon UUID: `12345678-9ABC-DEF0-1234-56789ABCDEF0`
- TX Power calibrated at -59 dBm
- Previous plan: `docs/plans/2026-02-12-feat-bluetooth-beacon-proximity-webhook-plan.md`
- Review findings: `docs/solutions/logic-errors/bluetooth-beacon-proximity-review-findings-20260212.md`

## References

- Issue #114 (closed — research)
- `BeaconService.swift:13` — hardcoded UUID to replace
- `BeaconConfigStore` (line 417 in BeaconSettingsView.swift) — persistence layer to extend
