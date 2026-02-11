---
title: "SwiftData fatalError on Migration Failure — Resilient 3-Tier Recovery"
date: 2026-02-11
category: database-issues
component: iOS/Models
severity: P0
tags: [swiftdata, migration, data-loss, fatalerror, resilience, schema-versioning]
root_cause: fatalError on ModelContainer init failure with no fallback or backup
related_issues: ["#71"]
related_pr: "#73"
prior_art:
  - swiftdata-persistence-failure-no-save-no-schema-versioning-20260210.md
  - swiftdata-task-detached-isolation-and-delete-save-reliability-20260210.md
---

# SwiftData fatalError on Migration Failure — Resilient 3-Tier Recovery

## Symptom

App crashes on launch with no recovery path when SwiftData schema migration fails. Users permanently lose all stored data (barcodes, room scans, motion records). The crash occurs in `RoboApp.init()`:

```swift
// BEFORE — fatal, unrecoverable
} catch {
    fatalError("Failed to initialize SwiftData: \(error)")
}
```

This happens when:
- User on V1 store, app updates to V3 schema
- Migration state becomes corrupted (partial migration)
- Store file is locked or damaged

## Root Cause

`fatalError()` in a SwiftUI `App.init()` kills the process before any UI renders. There is no opportunity for error display, data backup, or retry. Combined with SwiftData's lightweight migration, any schema incompatibility or file system issue becomes a permanent brick.

Compounding factors:
- No logging before crash — impossible to diagnose in production
- No backup of the store file — data is gone forever
- Orphaned commit `3ceb9d2` attempted a fix but used `deleteStore` as first resort (equally dangerous)

## Solution

Replace `fatalError` with a 3-tier resilient container factory:

```swift
import os

private let logger = Logger(subsystem: "com.silv.Robo", category: "AppInit")

private static func createResilientContainer() -> ModelContainer {
    let schema = Schema(versionedSchema: RoboSchemaV3.self)
    let config = ModelConfiguration(schema: schema)

    // Attempt 1: Normal migration
    do {
        return try ModelContainer(
            for: schema,
            migrationPlan: RoboMigrationPlan.self,
            configurations: [config]
        )
    } catch {
        logger.error("Migration failed: \(error.localizedDescription)")
    }

    // Attempt 2: Retry without migration plan
    do {
        return try ModelContainer(for: schema, configurations: [config])
    } catch {
        logger.error("Retry without migration failed: \(error.localizedDescription)")
    }

    // Attempt 3: Backup store, then create fresh
    let storeURL = config.url
    let backupURL = storeURL.deletingLastPathComponent()
        .appendingPathComponent("default.store.backup-\(Int(Date().timeIntervalSince1970))")
    do {
        if FileManager.default.fileExists(atPath: storeURL.path) {
            try FileManager.default.copyItem(at: storeURL, to: backupURL)
            logger.warning("Backed up corrupt store to \(backupURL.lastPathComponent)")
            try FileManager.default.removeItem(at: storeURL)
            for suffix in ["-wal", "-shm"] {
                let sidecar = URL(fileURLWithPath: storeURL.path + suffix)
                try? FileManager.default.removeItem(at: sidecar)
            }
        }
        return try ModelContainer(for: schema, configurations: [config])
    } catch {
        fatalError(
            "SwiftData unrecoverable after backup+recreate. "
            + "Backup at: \(backupURL.path). Error: \(error)"
        )
    }
}
```

### Key rules

1. **NEVER delete the store without backing it up first** — `copyItem` before `removeItem`
2. **Always remove WAL/SHM sidecar files** when removing the main store
3. **`fatalError` only as absolute last resort** — include backup path in message
4. **Use `os.Logger`** for structured, persistent logging of each failure tier

## Related Fix: Task.detached @Model Isolation

`Task.detached` must NOT capture `@Model` objects — they are not `Sendable`. Extract properties first:

```swift
// BEFORE — unsafe
private func exportRoom() {
    Task.detached {
        let url = try ExportService.createRoomExportZipFromData(
            roomName: room.roomName,       // ← captures @Model
            summaryJSON: room.summaryJSON,
            fullRoomDataJSON: room.fullRoomDataJSON
        )
    }
}

// AFTER — safe
private func exportRoom() {
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

## CI Guardrails

Added to `scripts/validate-build.sh`:

```bash
# Scan for unguarded store deletion
grep -rn "removeItem\|deleteStore\|destroyPersistentStore" ios/Robo/RoboApp.swift \
    | grep -v "backup"  # Lines with "backup" are safe

# Scan for naked fatalError in migration path
grep -n "fatalError.*SwiftData\|fatalError.*migration\|fatalError.*ModelContainer" \
    ios/Robo/RoboApp.swift | grep -v "backup+recreate\|unrecoverable"
```

## Prevention

- Always use the resilient container factory pattern for SwiftData init
- Commit `3ceb9d2` is poison — never cherry-pick it (delete-store-first approach)
- New schema versions must keep all new properties optional or defaulted
- All `@Model` property access in `Task.detached` must extract values first
