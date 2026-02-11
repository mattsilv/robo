---
title: "SwiftData Task.detached Isolation Violations and Delete-Path Save Reliability"
category: database-issues
component: ios
tags: [swiftdata, concurrency, task-detached, sendable, persistence, delete]
severity: P1
date: 2026-02-10
related_issues: ["#37", "#38"]
pr: "#42"
prior_art: "swiftdata-persistence-failure-no-save-no-schema-versioning-20260210.md"
---

# SwiftData Task.detached Isolation Violations and Delete-Path Save Reliability

## Problem

Two related reliability issues in the iOS app's data layer:

### 1. Delete operations relied on non-deterministic autosave

After the initial persistence fix (explicit `save()` after inserts), **delete paths were missed**. Swipe-to-delete, bulk clear, and inline delete all called `modelContext.delete()` without a subsequent `modelContext.save()`, relying on SwiftData's autosave — which is non-deterministic and races with navigation/dismiss.

**Symptom:** Deleted records could reappear after app restart.

### 2. Task.detached captured SwiftData @Model properties across isolation boundaries

`ScanHistoryView.exportRoom()` passed a `RoomScanRecord` (SwiftData `@Model`) into a `Task.detached` closure, then accessed `.roomName`, `.summaryJSON`, `.fullRoomDataJSON` inside the detached task. SwiftData models are **not Sendable** — accessing them off the main actor is undefined behavior.

Similarly, `RoomResultView.exportRoom()` captured a `CapturedRoom` (RoomPlan class, not Sendable) directly in `Task.detached`.

**Symptom:** Potential crashes, data corruption, or silent data races under concurrency.

## Root Cause

### Delete save gap
The prior fix (PR #34) correctly added `try modelContext.save()` after **inserts** but missed **deletes**. SwiftData's autosave has no guaranteed timing — it batches writes and may not flush before the user navigates away or the app backgrounds.

### Concurrency isolation
Swift's structured concurrency requires all data crossing isolation boundaries to be `Sendable`. SwiftData `@Model` objects and RoomPlan's `CapturedRoom` are **not Sendable**. Capturing them in `Task.detached` creates a data race: the main actor may mutate or deallocate the object while the detached task reads it.

## Solution

### Fix 1: Explicit save after every delete operation

```swift
// Before — relied on autosave
private func deleteBarcodeScans(at offsets: IndexSet) {
    for index in offsets {
        modelContext.delete(scans[index])
    }
}

// After — deterministic save
private func deleteBarcodeScans(at offsets: IndexSet) {
    for index in offsets {
        modelContext.delete(scans[index])
    }
    try? modelContext.save()
}
```

Applied to all delete paths: `deleteBarcodeScans`, `deleteRoomScans`, `clearAll`, and inline swipe-delete button.

### Fix 2: Extract @Model properties before crossing isolation

```swift
// Before — captures SwiftData model in detached task
private func exportRoom(_ room: RoomScanRecord) {
    Task.detached {
        let url = try ExportService.createRoomExportZipFromData(
            roomName: room.roomName,          // ← @Model access off main actor
            summaryJSON: room.summaryJSON,     // ← @Model access off main actor
            fullRoomDataJSON: room.fullRoomDataJSON
        )
    }
}

// After — extract before crossing boundary
private func exportRoom(_ room: RoomScanRecord) {
    let name = room.roomName
    let summary = room.summaryJSON
    let fullData = room.fullRoomDataJSON
    Task.detached {
        let url = try ExportService.createRoomExportZipFromData(
            roomName: name,
            summaryJSON: summary,
            fullRoomDataJSON: fullData
        )
    }
}
```

### Fix 3: Encode non-Sendable objects on main actor

```swift
// Before — CapturedRoom (not Sendable) in detached task
private func exportRoom() {
    Task.detached {
        let summary = RoomDataProcessor.summarizeRoom(room)  // ← room is CapturedRoom
        let exportable = ExportableRoom(summary: summary, fullRoom: room)
        let url = try ExportService.createRoomExportZip(room: exportable)
    }
}

// After — encode to Data (Sendable) on main actor first
private func exportRoom() {
    do {
        let summaryData = try RoomDataProcessor.encodeSummary(
            RoomDataProcessor.summarizeRoom(room)
        )
        let fullData = try RoomDataProcessor.encodeFullRoom(room)
        Task.detached {
            let url = try ExportService.createRoomExportZipFromData(
                roomName: "",
                summaryJSON: summaryData,      // ← Data is Sendable
                fullRoomDataJSON: fullData      // ← Data is Sendable
            )
        }
    } catch { ... }
}
```

### Fix 4: Surface save errors to user

```swift
// Before — error swallowed
try? modelContext.save()

// After — error surfaced in barcode flow
do {
    try modelContext.save()
} catch {
    self.error = "Failed to save scan: \(error.localizedDescription)"
}
```

## Prevention

### Rule: Every `modelContext.delete()` must be followed by `modelContext.save()`

Just like the insert rule from the prior fix. The complete rule:

> **Every SwiftData mutation (insert or delete) must be followed by an explicit `try modelContext.save()`.**

### Rule: Never pass @Model or non-Sendable objects into Task.detached

Extract all needed properties to local `let` bindings (value types / `Sendable` types) before the `Task.detached` block. For complex objects, encode to `Data` first.

**Pattern:**
```swift
// 1. Extract on main actor
let value1 = model.property1
let value2 = model.property2

// 2. Only Sendable values cross the boundary
Task.detached {
    doWork(value1, value2)
}
```

### Existing good pattern: SendView

`SendView.exportScans()` already followed the correct pattern — it maps SwiftData models to `ExportableScan` (a `Sendable` struct) before the detached task. This is the model to follow.

## Files Changed

| File | Change |
|------|--------|
| `BarcodeScannerView.swift` | `try?` → `do/catch` with error alert |
| `ScanHistoryView.swift` | Explicit saves after deletes; extract model props before `Task.detached` |
| `RoomResultView.swift` | Encode CapturedRoom on main actor; reuse `createRoomExportZipFromData` |

## Cross-References

- [SwiftData Persistence Failure — No Save, No Schema Versioning](swiftdata-persistence-failure-no-save-no-schema-versioning-20260210.md) — predecessor fix covering inserts + schema
- PR #42 — implementation
- Issues #37, #38 — sprint tracking
