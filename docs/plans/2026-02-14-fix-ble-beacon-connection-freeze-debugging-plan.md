---
title: "Fix BLE Beacon Connection Freeze + Add Live Diagnostic Logging"
type: fix
status: active
date: 2026-02-14
---

# Fix BLE Beacon Connection Freeze + Add Live Diagnostic Logging

## Overview

BLE sensor connection shows the device in scan results, but freezes on "Connecting..." state. The 15s timeout is implemented but the user has no visibility into what's happening during the connection attempt. Need to: (1) surface diagnostic logs in real-time so we can see what's failing, and (2) fix the underlying connection issue.

## Problem Statement

- Sensor appears in scan results (discovery works)
- Tapping sensor shows "Connecting..." spinner indefinitely (from user's perspective)
- The 15s timeout should fire, but user may not be waiting long enough OR the timeout isn't reaching the error state
- **Critical gap**: Diagnostic logs are only visible AFTER an error occurs (via ShareLink in error state). There's no way to see logs in real-time during connection.

## Root Cause Hypotheses

Ranked by likelihood:

1. **iOS GATT cache** (most common) — iOS cached stale service data from a previous connection attempt. The connection "succeeds" at the link layer but service discovery silently fails or returns cached data.

2. **Sensor not actually in provisioning mode** — LED may appear to pulse but sensor firmware isn't advertising the provisioning GATT service.

3. **Connection timeout IS firing but user interprets 15s as "frozen"** — 15 seconds feels long when staring at a spinner with no feedback.

4. **Weak signal** — Sensor discovered at edge of range (< -85 dBm), connection attempts fail silently.

5. **State machine race condition** — Possible edge case where state transitions prevent timeout from firing.

## Proposed Solution

### Phase 1: Surface Diagnostic Logs (30 min) — DO THIS FIRST

Make logs visible during ALL states, not just error. This tells us exactly where the connection is failing.

#### 1a. Add live log viewer to AddBeaconSheet

Add a collapsible "Diagnostic Log" section at the bottom of the `AddBeaconSheet` form, visible in ALL states (not just error):

**File:** `ios/Robo/Views/BeaconSettingsView.swift`

```swift
// Add after manualEntrySection in AddBeaconSheet body
Section {
    DisclosureGroup("Diagnostic Log (\(provisioner.diagnosticLog.count))") {
        if provisioner.diagnosticLog.isEmpty {
            Text("No events yet")
                .font(.caption)
                .foregroundStyle(.secondary)
        } else {
            ForEach(provisioner.diagnosticLog.suffix(20)) { entry in
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.event)
                        .font(.caption.weight(.medium))
                    if let detail = entry.detail {
                        Text(detail)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // Share button always visible when there are logs
    if !provisioner.diagnosticLog.isEmpty {
        ShareLink(
            item: provisioner.exportDiagnosticLog(),
            subject: Text("Robo BLE Diagnostic Log"),
            message: Text("BLE diagnostic log from Robo app")
        ) {
            Label("Share Logs", systemImage: "square.and.arrow.up")
                .font(.subheadline)
        }
    }
}
```

#### 1b. Add connection progress feedback to the "Connecting..." state

Instead of just showing "Connecting...", show a countdown and state info:

**File:** `ios/Robo/Views/BeaconSettingsView.swift` (line 302-307)

Replace the static "Connecting..." with:

```swift
case .connecting, .discoveringServices:
    VStack(alignment: .leading, spacing: 8) {
        HStack(spacing: 12) {
            ProgressView()
            VStack(alignment: .leading, spacing: 2) {
                Text(provisioner.state == .connecting ? "Connecting..." : "Discovering services...")
                    .font(.subheadline)
                Text("This may take up to 15 seconds")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }

        Button("Cancel", role: .destructive) {
            provisioner.cancel()
        }
        .font(.subheadline)
    }
```

### Phase 2: Debug + Fix Connection (after logs reveal the issue)

Once we can see the diagnostic logs, we'll know exactly which step fails. Here are the fixes for each likely scenario:

#### 2a. If logs show "Connected" then "Service discovery timeout"

**Cause:** iOS GATT cache. The connection succeeds but service discovery returns stale/empty data.

**Fix:** Force iOS to clear its BLE cache by disconnecting and reconnecting with a fresh `CBCentralManager` instance.

**File:** `ios/Robo/Services/SensorProvisioningManager.swift`

```swift
// Add retry logic: if service discovery fails, try once more with cache hint
func retryConnection() {
    guard let sensor = discoveredSensors.first(where: { $0.peripheral == connectedPeripheral }) else { return }
    log("Retrying connection", detail: "Clearing peripheral reference and reconnecting")
    cancel()
    // Small delay to let BLE stack reset
    Task { @MainActor in
        try? await Task.sleep(for: .seconds(1))
        connect(to: sensor)
    }
}
```

#### 2b. If logs show "Connecting" then "Connection timeout" (no didConnect callback)

**Cause:** Sensor isn't responding to connection requests. Either out of range, not in provisioning mode, or paired to another device.

**Fix:** Add pre-connection signal strength check and clearer error messages:

```swift
func connect(to sensor: DiscoveredSensor) {
    // Warn about weak signal
    if sensor.rssi < -85 {
        log("Weak signal warning", detail: "RSSI \(sensor.rssi) dBm — move closer to sensor")
    }
    // ... existing connection code
}
```

#### 2c. If logs show "Services discovered" but provisioning service not found

**Cause:** Service UUID mismatch between app and sensor firmware.

**Fix:** Log ALL discovered service UUIDs (already done at line 414) so we can compare with the expected `12345678-9ABC-DEF0-1234-000000000001`.

### Phase 3: Quick Wins for UX (optional, 15 min)

- [ ] Show RSSI signal strength on the "Connecting..." screen so user knows if signal is the issue
- [ ] Reduce connection timeout from 15s to 10s (faster feedback)
- [ ] Add "Toggle Bluetooth off/on" as a suggested action in the connecting state (not just error)

## Acceptance Criteria

- [ ] Diagnostic logs visible in real-time during all provisioning states (not just error)
- [ ] Share logs button available at all times (not just error state)
- [ ] "Connecting..." state shows which sub-step is active (connecting vs discovering services)
- [ ] Cancel button available during connection attempt
- [ ] User can share diagnostic log to developer for remote debugging
- [ ] Connection issue root cause identified from logs

## How to Get Logs RIGHT NOW (Before Any Code Changes)

If you want logs immediately without building new code:

### Option A: Xcode Console (requires Mac + USB cable)
1. Connect iPhone to Mac via USB
2. Open Xcode → Window → Devices and Simulators
3. Select your device → click "Open Console"
4. Filter by: `subsystem:com.silv.Robo category:SensorProvisioning`
5. Reproduce the connection attempt — all log entries will stream in real-time

### Option B: Console.app (requires Mac + USB cable)
1. Connect iPhone to Mac
2. Open `/Applications/Utilities/Console.app`
3. Select your iPhone in the sidebar
4. Search filter: `SensorProvisioning`
5. Start the connection attempt

### Option C: Wait for timeout → Share from app
1. Tap the sensor to connect
2. Wait 15 seconds for the timeout error
3. Tap "Share Diagnostic Logs" button (appears in error state)
4. Share via AirDrop/Messages/email

## Dependencies & Risks

- **Risk:** If the sensor firmware is the issue (not the iOS app), no code changes will fix it. Logs will tell us.
- **Risk:** iOS GATT cache is cleared by toggling Bluetooth off/on. If that works, the "fix" is better UX guidance, not code.
- **Fallback:** If BLE provisioning can't be made reliable, keep manual beacon entry (already implemented) as the primary flow and demote BLE discovery to "advanced" option.

## References

- Existing timeout solution: `docs/solutions/runtime-errors/ble-beacon-connection-timeout-missing-20260213.md`
- Protocol mismatch solution: `docs/solutions/integration-issues/ble-sensor-discovery-corebluetooth-vs-ibeacon-20260213.md`
- SensorProvisioningManager: `ios/Robo/Services/SensorProvisioningManager.swift`
- AddBeaconSheet UI: `ios/Robo/Views/BeaconSettingsView.swift:210-602`
