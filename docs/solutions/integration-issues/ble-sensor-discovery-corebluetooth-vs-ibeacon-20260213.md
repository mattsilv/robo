---
title: "BLE Sensor Discovery in Provisioning Mode — CoreBluetooth vs iBeacon"
date: 2026-02-13
category: integration-issues
tags:
  - iOS
  - CoreBluetooth
  - CoreLocation
  - BLE
  - iBeacon
  - sensor-provisioning
  - race-condition
severity: high
component: Beacon/Sensor Provisioning
symptoms:
  - "iOS app cannot discover BLE sensors in provisioning mode"
  - "iBeacon ranging code finds nothing when sensor LED is pulsing white"
  - "Service UUID filter returns zero results during BLE scan"
  - "Monitoring silently fails on fresh install (permission race condition)"
root_cause: "App used CoreLocation iBeacon ranging (CLBeaconRegion) but sensors in provisioning mode advertise as generic BLE peripherals, not iBeacons. Additionally, service UUID is absent from advertisement data, and startMonitoring() was called before async permission grant completed."
resolution: "Created CoreBluetooth SensorProvisioningManager that scans with nil services and filters by name. Fixed permission race condition with pendingMonitorAfterAuth flag."
time_to_resolve: "~2 hours"
prevention_possible: true
related:
  - docs/solutions/logic-errors/bluetooth-beacon-proximity-review-findings-20260212.md
  - docs/plans/2026-02-12-feat-bluetooth-beacon-proximity-webhook-plan.md
  - docs/plans/2026-02-13-feat-beacon-registration-and-sensor-data-plan.md
pr: "#117"
---

# BLE Sensor Discovery in Provisioning Mode — CoreBluetooth vs iBeacon

## Root Cause

The iOS app couldn't discover BLE sensors in provisioning mode due to a **protocol mismatch**:

- Sensors in provisioning mode advertise as **generic BLE peripherals** with local name `"Robo Sensor"`
- The app only had CoreLocation's `CLBeaconRegion` ranging, which detects the **iBeacon protocol** — a specific Apple BLE advertisement format with UUID/major/minor fields
- These are fundamentally different protocols. `CLBeaconRegion` can never find a device that isn't advertising in iBeacon format

**Secondary issue — service UUID not in advertisement data:**
Engineers confirmed the provisioning service UUID (`12345678-9ABC-DEF0-1234-000000000001`) is NOT included in the BLE advertisement packets. This means `scanForPeripherals(withServices: [serviceUUID])` also won't find the device. Must scan with `nil` services and filter by peripheral name.

**Tertiary issue — CoreLocation permission race condition:**
`requestPermissions()` and `startMonitoring()` were called back-to-back in `BeaconMonitorView`, but authorization is an async process (user taps "Allow"). Monitoring started before the OS granted authorization, causing silent failure.

## Solution

Three coordinated changes:

### 1. New `SensorProvisioningManager` (CoreBluetooth)

Created `ios/Robo/Services/SensorProvisioningManager.swift` — an `@Observable` class handling the full provisioning workflow.

**Scanning** — uses `nil` services with name filtering:

```swift
func startScanning() {
    guard centralManager.state == .poweredOn else {
        pendingScan = true  // Defer until Bluetooth is ready
        state = .scanning
        return
    }

    state = .scanning
    centralManager.scanForPeripherals(
        withServices: nil,  // No service filter — UUID not in advertisement
        options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
    )
}
```

**Name-based filtering** in the discovery callback:

```swift
func centralManager(_ central: CBCentralManager,
                     didDiscover peripheral: CBPeripheral,
                     advertisementData: [String: Any],
                     rssi RSSI: NSNumber) {
    let advName = advertisementData[CBAdvertisementDataLocalNameKey] as? String
        ?? peripheral.name
    guard let name = advName, name == "Robo Sensor" else { return }
    // ... add to discoveredSensors
}
```

**Write completion tracking** — counts completed writes, sends SAVE after all 4:

```swift
func peripheral(_ peripheral: CBPeripheral,
                 didWriteValueFor characteristic: CBCharacteristic,
                 error: Error?) {
    guard characteristic.uuid != SensorUUID.command else { return }
    completedWriteCount += 1
    if completedWriteCount >= pendingWriteCount {
        sendSaveCommand()
    }
}
```

### 2. Permission Race Condition Fix

Added `pendingMonitorAfterAuth` flag to `BeaconService.swift`:

```swift
func requestPermissionsAndMonitor() {
    let status = manager.authorizationStatus
    if status == .authorizedAlways || status == .authorizedWhenInUse {
        startMonitoring()
    } else {
        pendingMonitorAfterAuth = true
        requestPermissions()
    }
}

func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
    // ... existing code ...
    if pendingMonitorAfterAuth,
       manager.authorizationStatus == .authorizedAlways ||
       manager.authorizationStatus == .authorizedWhenInUse {
        pendingMonitorAfterAuth = false
        startMonitoring()
    }
}
```

### 3. UI Redesign

Redesigned `AddBeaconSheet` in `BeaconSettingsView.swift`:
- **Discover Sensors** is now the primary action (was secondary)
- **Manual Entry** is collapsed/secondary
- Full provisioning UI: scan → select sensor → WiFi + room form → save → verify

## What Didn't Work

The old `CLBeaconRegion` approach:

```swift
// This ONLY works after provisioning, when the sensor broadcasts iBeacon format
let region = CLBeaconRegion(uuid: iBeaconUUID, major: 1, identifier: "...")
manager.startMonitoring(for: region)
manager.startRangingBeacons(satisfying: constraint)
```

This failed because:
1. `CLBeaconRegion` only matches iBeacon advertisement packets — provisioning sensors don't use this format
2. You can't filter `CLBeaconRegion` by local name or custom advertisement fields
3. Even `CBCentralManager.scanForPeripherals(withServices: [uuid])` fails because the service UUID isn't in the advertisement data

## Two-Protocol Architecture

The solution uses a **two-protocol system**:

| Phase | Framework | Protocol | Purpose |
|-------|-----------|----------|---------|
| Provisioning | CoreBluetooth | Generic BLE GATT | Discover + configure sensors |
| Monitoring | CoreLocation | iBeacon | Efficient background presence detection |

After provisioning, the sensor reboots and switches from generic BLE to iBeacon mode. CoreLocation takes over for ongoing room detection.

## Prevention Strategies

### Protocol Selection Audit
Before implementing BLE features, document which advertisement format the device uses. iBeacon is just one format — many BLE devices don't use it. Verify with nRF Connect or LightBlue before writing code.

### Advertisement Data Validation
Never assume service UUIDs are in advertisement packets. Test with `nil` services filter first, then narrow if possible. Log raw advertisement data during development.

### Async Permission Guards
Never call permission-dependent operations immediately after requesting permission. Always use delegate callbacks or async/await wrappers with explicit state tracking:

```
requestPermissions() → delegate callback → check flag → startMonitoring()
```

### Checklist for Future BLE Features

- [ ] Confirm device's actual BLE advertisement format (iBeacon vs generic GATT)
- [ ] Verify which UUIDs appear in advertisement data vs only in GATT service discovery
- [ ] Check both Bluetooth AND Location authorization before operations
- [ ] Use delegate callbacks for permission state, never assume synchronous
- [ ] Test with physical device (simulator BLE support is limited)
- [ ] Test permission denied + late grant scenarios
- [ ] Document protocol choice in code comments

## Files Changed

| File | Action | Description |
|------|--------|-------------|
| `ios/Robo/Services/SensorProvisioningManager.swift` | Created | CoreBluetooth BLE provisioning manager |
| `ios/Robo/Services/BeaconService.swift` | Modified | Added `requestPermissionsAndMonitor()` |
| `ios/Robo/Views/BeaconSettingsView.swift` | Modified | Redesigned AddBeaconSheet, renamed labels |
| `ios/Robo/Views/BeaconMonitorView.swift` | Modified | Fixed race condition, renamed labels |

## Related

- [Beacon proximity review findings (6 bugs)](../logic-errors/bluetooth-beacon-proximity-review-findings-20260212.md)
- [Beacon proximity webhook plan](../../plans/2026-02-12-feat-bluetooth-beacon-proximity-webhook-plan.md)
- [Beacon registration and sensor data plan](../../plans/2026-02-13-feat-beacon-registration-and-sensor-data-plan.md)
- PR #117
