---
title: "BLE Beacon Provisioning: WiFi Optional, Sensor WiFi Scan, and Deletion UX"
type: integration-issues
date: 2026-02-14
tags: [ble, wifi, ios, provisioning, ux, corebluetooth, networkextension]
component: beacon-provisioning
symptom: |
  WiFi provisioning was mandatory to save a BLE beacon — users could not register a beacon without
  entering WiFi SSID and password. No auto-detection of current WiFi network. Sensor's WiFi radio
  was not leveraged for network scanning. Beacon deletion via swipe was implemented but undiscoverable
  (no Edit button).
root_cause: |
  UI flow conflated beacon registration (essential) with WiFi network configuration (optional).
  iOS lacks a general-purpose WiFi scanning API, but the sensor hardware has a WiFi radio that
  was not being used. NEHotspotNetwork API for current SSID detection was not integrated.
  SwiftUI .onDelete requires an Edit button for discoverability.
---

# BLE Beacon Provisioning: WiFi Optional, Sensor WiFi Scan, and Deletion UX

## Problem

Four related issues in the BLE beacon provisioning flow:

1. **WiFi was mandatory** — "Save Configuration" button disabled until both SSID and password entered, even though WiFi config is logically separate from beacon registration
2. **No SSID auto-detection** — user had to manually type their WiFi network name (error-prone)
3. **Sensor WiFi radio unused** — the BLE sensor has a WiFi chip but the app never asked it to scan nearby networks
4. **Beacon deletion hidden** — `.onDelete` was wired up but no `EditButton` in the toolbar, so users couldn't discover swipe-to-delete

## Solution

### 1. Made WiFi provisioning optional

Restructured the provisioning form so the primary action is **"Save Beacon"** (room + minor ID only). WiFi fields moved into a collapsible `DisclosureGroup("WiFi Configuration (Optional)")` with a separate "Save with WiFi" button inside.

**File:** `ios/Robo/Views/BeaconSettingsView.swift`

```swift
// Primary action — saves beacon without WiFi
Button {
    let room = roomPresets[selectedRoomIndex]
    onAdd(Int(room.minorID), room.name)
    dismiss()
} label: {
    Text("Save Beacon")
}

// Optional WiFi in disclosure group
DisclosureGroup("WiFi Configuration (Optional)") {
    // SSID picker or text field
    // Password field
    // "Save with WiFi" button
}
```

### 2. Added BLE WiFi scan characteristic

New UUID `12345678-9ABC-DEF0-1234-000000000008` for sensor-powered WiFi scanning. iOS writes `"SCAN"`, sensor scans nearby networks and notifies back with `SSID,RSSI` per line.

**File:** `ios/Robo/Services/SensorProvisioningManager.swift`

```swift
// New UUID
enum SensorUUID {
    static let wifiScan = CBUUID(string: "12345678-9ABC-DEF0-1234-000000000008")
}

// Data model
struct DiscoveredWiFiNetwork: Identifiable, Comparable {
    let ssid: String
    let rssi: Int
    static func < (lhs: Self, rhs: Self) -> Bool { lhs.rssi > rhs.rssi }
}

// Trigger scan
func scanWiFiNetworks() {
    peripheral.setNotifyValue(true, for: wifiChar)
    peripheral.writeValue("SCAN".data(using: .utf8)!, for: wifiChar, type: .withResponse)
    // 5s timeout
}

// Parse response: "MyWifi,-45\nNeighbor,-67\n"
private func parseWiFiScanResponse(_ response: String) { ... }
```

**BLE protocol spec (for firmware):**
- Write `"SCAN"` to characteristic UUID `...0008`
- Sensor returns via notify: one line per network, `SSID,RSSI` format
- Sort by signal strength, limit to 10 networks, 32-char SSID max
- Fits in single 512-byte BLE MTU packet
- `MORE` / `END` markers for multi-packet responses

### 3. NEHotspotNetwork fallback for SSID auto-detect

When sensor firmware doesn't support WiFi scanning, falls back to iOS `NEHotspotNetwork.fetchCurrent()` to pre-fill the current WiFi SSID.

```swift
private func fetchCurrentSSID() {
    NEHotspotNetwork.fetchCurrent { network in
        DispatchQueue.main.async {
            if let ssid = network?.ssid, !ssid.isEmpty {
                wifiSSID = ssid
            }
        }
    }
}
```

Required adding `com.apple.developer.networking.wifi-info` entitlement to `Robo.entitlements` and `project.yml`. This entitlement does **not** require special Apple approval — any paid developer account can use it. Requires location permission (already granted for beacon monitoring).

### 4. Edit button for beacon deletion

Added `EditButton()` to the `BeaconSettingsView` toolbar so users can see delete buttons next to each beacon.

```swift
.toolbar {
    if !beacons.isEmpty {
        EditButton()
    }
}
```

## Files Modified

| File | Change |
|------|--------|
| `ios/Robo/Services/SensorProvisioningManager.swift` | New `wifiScan` UUID, `DiscoveredWiFiNetwork` model, `scanWiFiNetworks()`, `parseWiFiScanResponse()`, `hasWiFiScanSupport` |
| `ios/Robo/Views/BeaconSettingsView.swift` | Optional WiFi DisclosureGroup, WiFi network Picker, `fetchCurrentSSID()`, signal strength icons, Edit button |
| `ios/Robo/Robo.entitlements` | Added `com.apple.developer.networking.wifi-info` |
| `ios/project.yml` | Added wifi-info entitlement to xcodegen config |

## Prevention & Best Practices

### Separate required from optional configuration
Always categorize provisioning steps as required (M0) vs optional (M1). A beacon should be usable immediately after pairing — WiFi is an enhancement, not a prerequisite.

### Leverage device hardware capabilities
If your BLE peripheral has a WiFi radio, use it for network discovery. iOS cannot scan WiFi networks (no public API), but the sensor can scan and send results over BLE. This is the standard IoT provisioning pattern (ESP-IDF WiFi Provisioning, Matter/Thread).

### BLE MTU budget
512-byte limit per notification. WiFi list at ~38 bytes/network (32 SSID + comma + 4 RSSI + newline) means ~13 networks max. Sort by signal, cap at 10 for UX clarity and MTU headroom.

### SwiftUI deletion discoverability
Every `List` with `.onDelete()` needs an `EditButton()` in the toolbar. Swipe-to-delete is a hidden gesture — the Edit button is the standard iOS affordance.

### iOS WiFi info API
`NEHotspotNetwork.fetchCurrent()` requires:
- `com.apple.developer.networking.wifi-info` entitlement (no special approval)
- Location permission (WhenInUse or Always)
- Returns only the currently connected network (cannot scan)

## Related Documentation

- [BLE Sensor Discovery: CoreBluetooth vs iBeacon](ble-sensor-discovery-corebluetooth-vs-ibeacon-20260213.md) — Two-protocol architecture
- [BLE Beacon Connection Timeout](../runtime-errors/ble-beacon-connection-timeout-missing-20260213.md) — Timeout handling at each BLE lifecycle stage
- [Bluetooth iBeacon Proximity Review Findings](../logic-errors/bluetooth-beacon-proximity-review-findings-20260212.md) — 6 review bugs in beacon event handling
- PR #123: Implementation PR
- PR #121: Earlier BLE connection timeout fix
