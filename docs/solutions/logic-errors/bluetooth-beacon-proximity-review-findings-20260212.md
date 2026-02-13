---
title: "Bluetooth iBeacon Proximity — 6 Review Findings (Dismiss, Config, Retry, Export, Duration)"
category: logic-errors
component: ios-beacon
date: 2026-02-12
tags: [bluetooth, ibeacon, corelocation, webhooks, export, config, retry-backoff, beacon-service, webhook-service]
severity: [P1, P2]
related_issues: ["#101"]
pr: "#102"
symptoms:
  - "Cancelled beacon setup marked as complete in agent UX"
  - "Beacon events fired regardless of enable/disable toggle"
  - "Failed webhook retry queue never drained"
  - "Retry backoff 45s delay never executes (off-by-one)"
  - "Beacon events counted in export UI but not in exported ZIP"
  - "Exit duration computed but dropped before persistence/webhook"
files_modified:
  - ios/Robo/Views/AgentsView.swift
  - ios/Robo/Services/BeaconService.swift
  - ios/Robo/Services/WebhookService.swift
  - ios/Robo/Views/BeaconMonitorView.swift
  - ios/Robo/Views/ScanHistoryView.swift
  - ios/Robo/Services/ExportService.swift
---

# Bluetooth iBeacon Proximity — 6 Review Findings

Static code review of PR #102 (iBeacon proximity webhooks) surfaced 3 P1 and 3 P2 bugs. All fixed in commit `fb96375`.

---

## Fix 1 [P1]: handleBeaconDismiss marks complete on cancel

### Problem
`handleBeaconDismiss()` in AgentsView unconditionally called `triggerSyncAnimation()`, clearing the agent request even when the user tapped Cancel from the instructions screen without starting monitoring.

### Root Cause
Missing guard check. Other dismiss handlers (LiDAR, barcode, photo, product) all check item count against a baseline before triggering sync. The beacon handler skipped this pattern.

### Solution
Added `@Query` for `BeaconEventRecord`, `@State private var initialBeaconCount`, and count-based guard:

```swift
// AgentsView.swift
@Query(sort: \BeaconEventRecord.capturedAt, order: .reverse) private var beaconEvents: [BeaconEventRecord]
@State private var initialBeaconCount = 0

// In handleScanNow(.beacon):
case .beacon:
    initialBeaconCount = beaconEvents.count
    syncingAgentId = agent.id
    showingBeaconMonitor = true

// In handleBeaconDismiss():
private func handleBeaconDismiss() {
    guard let agentId = syncingAgentId else { return }
    if beaconEvents.count > initialBeaconCount {
        triggerSyncAnimation(for: agentId)
    } else {
        syncingAgentId = nil
    }
}
```

### Pattern
**Every new capture flow dismiss handler MUST follow the count-check pattern.** Grep for `triggerSyncAnimation` — every call site should be behind an `if newCount > initialCount` guard.

---

## Fix 2 [P1]: Beacon config active filter not enforced

### Problem
`BeaconService` ranging callback fired events for ALL detected beacons, ignoring the `isActive` toggle from `BeaconConfigStore`. Toggling a beacon off in Settings had no effect.

### Root Cause
No filtering logic in the ranging delegate. The config was written (UI) but never read (detection pipeline).

### Solution
Added active minor filtering in the ranging callback. If no beacons are configured, allow all (discovery mode):

```swift
// BeaconService.swift — locationManager(_:didRange:satisfying:)
let configured = BeaconConfigStore.loadBeacons()
let activeMinors: Set<Int>? = configured.isEmpty ? nil : Set(configured.filter(\.isActive).map(\.minor))

for beacon in beacons where beacon.proximity != .unknown {
    let minor = beacon.minor.intValue

    // Skip beacons not in active config (when config exists)
    if let activeMinors, !activeMinors.contains(minor) {
        continue
    }
    // ... fire event
}
```

### Pattern
**Every user-facing toggle must have both a write site (UI) and a read site (enforcement).** When reviewing config properties, grep for the property name — it should appear in at least 2 contexts.

---

## Fix 3 [P1]: Failed webhook retry queue never drained

### Problem
`WebhookService.retryPending()` was fully implemented (with 24h TTL, queue cap) but had zero call sites in the entire codebase. Failed webhooks accumulated permanently.

### Root Cause
The retry API was built but the call site was never wired up — classic dead code from incremental development.

### Solution
Added retry call when monitoring starts:

```swift
// BeaconMonitorView.swift — startMonitoring()
let secret = UserDefaults.standard.string(forKey: "beaconWebhookSecret")
Task {
    await WebhookService.retryPending(secret: secret)
}
```

### Pattern
**Every public/static function should have at least one call site in the same PR that adds it.** If a function is scaffolding for a future phase, mark it explicitly with `// TODO: Phase 2 — wire up in [location]`.

---

## Fix 4 [P2]: Retry backoff 45s delay never executes

### Problem
`retryDelays = [5, 15, 45]` with `for (attempt, delay) in retryDelays.enumerated()` made 3 attempts. Sleep condition `if attempt < retryDelays.count - 1` skipped the 45s delay because `2 < 2` is false.

### Root Cause
Off-by-one: N delays used for N attempts gives N-1 sleep gaps. The last delay is never used.

### Solution
Restructured to 1 initial attempt + 3 retries, sleeping BEFORE each retry:

```swift
// WebhookService.swift
let maxAttempts = retryDelays.count + 1 // 4 total: 1 initial + 3 retries

for attempt in 0..<maxAttempts {
    if attempt > 0 {
        try? await Task.sleep(for: .seconds(retryDelays[attempt - 1]))
    }
    // ... make request
}
```

### Pattern
**Manual trace the loop with real values during review:**
- attempt=0: no sleep, try
- attempt=1: sleep(5s), try
- attempt=2: sleep(15s), try
- attempt=3: sleep(45s), try

Verify the last delay value is actually reached.

---

## Fix 5 [P2]: Beacon events counted in export but not exported

### Problem
`totalItemCount` included `beaconEvents.count`, but:
- Export button disable condition only checked scans/rooms/motion
- `exportAll()` only called `createCombinedExportZip` with barcode/room/motion data

### Root Cause
Incomplete feature integration — new data type added to count/UI but not wired into the export pipeline.

### Solution
1. Added `ExportableBeaconEvent` Sendable struct to ExportService
2. Added `beaconEvents` parameter to `createCombinedExportZip`
3. Wrote beacon JSON + CSV in `beacons/` subdirectory
4. Updated disable condition and `exportAll()` caller:

```swift
// ScanHistoryView.swift
.disabled(isExporting || (scans.isEmpty && roomScans.isEmpty && motionRecords.isEmpty && beaconEvents.isEmpty))

let beaconData = beaconEvents.map {
    ExportableBeaconEvent(eventType: $0.eventType, beaconMinor: $0.beaconMinor, ...)
}
let url = try ExportService.createCombinedExportZip(
    scans: barcodeData, rooms: roomData, motionRecords: motionData, beaconEvents: beaconData
)
```

### Pattern
**New data types must flow through all 5 layers:** Model → Detection → UI Display → Persistence → Export. Missing one layer = incomplete integration.

---

## Fix 6 [P2]: Exit duration computed but dropped

### Problem
`BeaconService.didExitRegion` computed `let duration = Int(Date().timeIntervalSince(enterTime))` but the `BeaconEvent` struct had no `durationSeconds` field. The value was discarded.

### Root Cause
Incomplete data struct — the intermediate transfer type was missing a field for a computed value.

### Solution
Added `durationSeconds: Int?` to `BeaconEvent`, populated on exit events, and propagated through:

```swift
// BeaconService.swift — BeaconEvent struct
struct BeaconEvent {
    // ... existing fields ...
    let durationSeconds: Int? // Only on exit events
}

// Exit handler:
let event = BeaconEvent(
    type: "exit", minor: minor, ...,
    durationSeconds: Int(Date().timeIntervalSince(enterTime)),
    source: "background_monitor", timestamp: Date()
)

// BeaconMonitorView → record + webhook payload:
let record = BeaconEventRecord(..., durationSeconds: event.durationSeconds, ...)
let payload = BeaconWebhookPayload(..., durationSeconds: event.durationSeconds, ...)
```

### Pattern
**When data flows from one struct to another, verify all computed fields appear in the destination.** Swift's memberwise init catches missing stored properties at compile time — leverage this by requiring all fields in init rather than using defaults.

---

## Prevention Strategies Summary

| Bug Category | Prevention | Automatable? |
|---|---|---|
| Incomplete dismiss handler | Count-check pattern required for all capture flows | Custom lint rule |
| Config toggle not enforced | Bidirectional trace: write (UI) + read (enforcement) | Property usage analysis |
| Dead code / unused API | Every public function needs a call site in same PR | `-Wunused-function` |
| Off-by-one retry loop | Manual loop trace during review | Unit test on delays |
| Incomplete data integration | 5-layer checklist: Model → Detect → UI → Persist → Export | CI registry check |
| Missing struct field | Explicit all-field initializers, no defaults for critical data | Compiler enforcement |

## Related Documentation

- Plan: `docs/plans/2026-02-12-feat-bluetooth-beacon-proximity-webhook-plan.md`
- Architecture: `docs/solutions/architecture-patterns/compound-multi-sensor-capture-flow-pattern-20260212.md`
- SwiftData: `docs/solutions/database-issues/swiftdata-persistence-failure-no-save-no-schema-versioning-20260210.md`
- Agent context: `docs/solutions/architecture-issues/swiftdata-schema-drift-agent-context-threading-20260212.md`
