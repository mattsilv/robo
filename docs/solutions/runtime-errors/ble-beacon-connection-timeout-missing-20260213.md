---
title: "BLE beacon connection spinning indefinitely with no timeout"
date: 2026-02-13
category: runtime-errors
tags: [bluetooth, ble, corebluetooth, timeout, gatt-cache, diagnostics]
component: SensorProvisioningManager.swift
severity: critical
symptoms: "Connecting to beacon via 'Add Beacon' showed 'Connecting' spinner forever with no error or completion"
root_cause: "CBCentralManager.connect() and GATT discovery had no timeouts; iOS BLE cache can return stale service data causing silent failures"
---

# BLE Beacon Connection Spinning Indefinitely

## Symptom

When a user tapped "Connect" on a discovered Robo Sensor in the Add Beacon sheet, the UI showed a "Connecting..." spinner that never resolved. No error, no timeout, no way to diagnose what went wrong.

## Root Cause

`CBCentralManager.connect()` has **no built-in timeout**. If the peripheral doesn't respond, iOS will wait indefinitely. The same applies to service discovery and characteristic discovery — none of the CoreBluetooth delegate callbacks are guaranteed to fire.

Additionally, iOS aggressively caches GATT (Generic Attribute Profile) service data. If the sensor's service definitions changed during development, iOS would try to use stale cached services and silently fail during discovery.

## Solution

Added timeouts at every stage of the BLE connection lifecycle, structured diagnostic logging, and a shareable log export for user debugging.

### 1. Timeout Constants

```swift
private enum BLETimeout {
    static let connection: TimeInterval = 15
    static let serviceDiscovery: TimeInterval = 10
    static let characteristicDiscovery: TimeInterval = 10
    static let saveCommand: TimeInterval = 10
}
```

### 2. Timeout Implementation (Connection Example)

```swift
private func startConnectionTimeout() {
    connectionTimeoutTask?.cancel()
    connectionTimeoutTask = Task { @MainActor [weak self] in
        try? await Task.sleep(for: .seconds(BLETimeout.connection))
        guard !Task.isCancelled, let self else { return }
        guard case .connecting = self.state else { return }
        self.log("Connection timeout", detail: "No response after 15s")
        self.state = .error("Connection timed out (15s). Try toggling Bluetooth off/on in Settings.")
        if let peripheral = self.connectedPeripheral {
            self.centralManager.cancelPeripheralConnection(peripheral)
        }
    }
}
```

Key design decisions:
- **State guard**: Each timeout checks the state hasn't changed (prevents races if success arrives just as timeout fires)
- **Actionable error**: Messages tell users what to try ("toggle Bluetooth off/on") rather than just "timed out"
- **Cleanup**: Cancels the peripheral connection to free resources

### 3. Cancel Timeouts on Success

```swift
func centralManager(_ central: CBCentralManager, didConnect peripheral: CBPeripheral) {
    connectionTimeoutTask?.cancel()  // Cancel — connection succeeded
    connectionTimeoutTask = nil
    state = .discoveringServices
    peripheral.discoverServices([SensorUUID.provisioningService])
    startServiceDiscoveryTimeout()  // Start next stage timeout
}
```

### 4. Diagnostic Log Buffer

```swift
struct BLEDiagnosticEntry: Identifiable {
    let id = UUID()
    let timestamp: Date
    let event: String
    let detail: String?
}

// Every state transition is logged:
private func log(_ event: String, detail: String? = nil) {
    let entry = BLEDiagnosticEntry(timestamp: Date(), event: event, detail: detail)
    diagnosticLog.append(entry)
    logger.info("[\(event)] \(detail ?? "")")
}
```

### 5. Shareable Log Export

```swift
func exportDiagnosticLog() -> String {
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    var lines = ["Robo BLE Diagnostic Log", "=======================", ""]
    for entry in diagnosticLog {
        let ts = formatter.string(from: entry.timestamp)
        lines.append("[\(ts)] \(entry.event): \(entry.detail ?? "")")
    }
    lines.append("")
    lines.append("iOS \(UIDevice.current.systemVersion), \(UIDevice.current.model)")
    return lines.joined(separator: "\n")
}
```

### 6. UI: Share Diagnostic Logs Button

Added to the error state in `BeaconSettingsView.swift`:

```swift
ShareLink(
    item: provisioner.exportDiagnosticLog(),
    subject: Text("Robo BLE Diagnostic Log"),
    message: Text("Connection diagnostic log from Robo app")
) {
    Label("Share Diagnostic Logs", systemImage: "square.and.arrow.up")
        .font(.subheadline)
}
```

## iOS BLE Debugging Checklist

When BLE connections fail, check these in order:

1. **iOS GATT cache** (most common): Toggle Bluetooth off/on in iOS Settings, or forget the device
2. **peripheral.delegate = self**: Must be set before calling `discoverServices` (we already do this)
3. **Service UUID match**: Verify the sensor advertises the expected service UUID
4. **Provisioning mode**: Sensor LED should be pulsing white
5. **Distance**: Move within 10 feet of the sensor

## Prevention

### Code Review Checklist for BLE/Async Operations

- [ ] Every async BLE operation has a timeout
- [ ] Timeout task is cancelled on success callback
- [ ] Diagnostic logging at every state transition
- [ ] Error messages include actionable troubleshooting steps
- [ ] `cancelAllTimeouts()` called in `cancel()` and `cleanup()`

### Testing

CoreBluetooth doesn't work in the iOS simulator. Manual testing checklist:

- [ ] Connect to sensor within 10 seconds (happy path)
- [ ] Timeout fires after 15 seconds with actionable error message
- [ ] Diagnostic log shows every step with timestamps
- [ ] "Share Diagnostic Logs" produces readable, complete output
- [ ] Toggle Bluetooth off during connection produces clean error
- [ ] Reconnect after timeout works without hanging

## Related

- Commit: `5d9b4bf` — fix(ble): add connection timeouts and diagnostic logging
- Solution: `docs/solutions/logic-errors/bluetooth-beacon-proximity-review-findings-20260212.md`
- Plan: `docs/plans/2026-02-12-feat-bluetooth-beacon-proximity-webhook-plan.md`
- PR: [#121](https://github.com/mattsilv/robo/pull/121)
