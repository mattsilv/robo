---
title: "SwiftData Persistence Failure: Missing Explicit Save and Schema Versioning"
category: database-issues
tags: [swiftdata, persistence, ios, schema-migration, data-loss, versionedschema]
severity: critical
component: iOS/Models
date: 2026-02-10
root_cause: [missing-explicit-save, missing-schema-versioning]
---

# SwiftData Persistence Failure: Missing Explicit Save and Schema Versioning

## Symptom

Users scan a room with LiDAR, tap "Save to History", and the History tab shows "No Room Scans Yet." Data appears to save successfully (no error shown) but never persists. Additionally, all previously saved data is lost between TestFlight build updates.

## Investigation

1. Checked `LiDARScanView.saveRoom()` — calls `modelContext.insert(record)` then immediately `dismiss()`
2. Checked `BarcodeScannerView.handleScan()` — same pattern: `modelContext.insert(record)` with no explicit save
3. Checked `RoboApp.swift` — uses bare `.modelContainer(for:)` with no `VersionedSchema` or `SchemaMigrationPlan`
4. Confirmed `RoomScanRecord` had `ceilingHeightM` property added between builds without any migration plan

## Root Cause (Two Issues)

### 1. No Explicit `modelContext.save()` After Insert

SwiftData's `autosaveEnabled` is `true` by default on the main context, but autosave fires **asynchronously** — it does not guarantee a synchronous write after `insert()`. When `dismiss()` is called immediately after `insert()`, the view hierarchy tears down before autosave can fire. Data stays in memory but never reaches disk.

**Key insight from Apple docs:** "The context calls save() after you make changes... The context also calls save() at various times during the lifecycle of windows, scenes, views, and sheets." The word "various" is the problem — it's not deterministic, and sheet dismissal can race against it.

### 2. No Schema Versioning

When `ceilingHeightM: Double` was added to `RoomScanRecord` between TestFlight builds, the on-disk schema no longer matched the in-memory schema. Without a `VersionedSchema` and `SchemaMigrationPlan`, SwiftData cannot perform a lightweight migration. It silently creates a **new empty store**, destroying all existing user data.

## Solution

### Fix 1: Explicit Save After Every Insert

```swift
// LiDARScanView.swift — saveRoom()
modelContext.insert(record)
try modelContext.save()  // Explicit save before dismiss
dismiss()

// BarcodeScannerView.swift — handleScan()
modelContext.insert(record)
try? modelContext.save()  // try? because scans happen rapidly
```

### Fix 2: VersionedSchema as Single Source of Truth

Created `RoboSchema.swift` — all model definitions live in one file:

```swift
enum RoboSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)
    static var models: [any PersistentModel.Type] {
        [ScanRecord.self, RoomScanRecord.self]
    }

    @Model
    final class ScanRecord { /* ... */ }

    @Model
    final class RoomScanRecord { /* ... */ }
}

enum RoboMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] { [RoboSchemaV1.self] }
    static var stages: [MigrationStage] { [] }
}

// Type aliases so the rest of the app uses simple names
typealias ScanRecord = RoboSchemaV1.ScanRecord
typealias RoomScanRecord = RoboSchemaV1.RoomScanRecord
```

### Fix 3: Explicit ModelContainer Initialization

```swift
// RoboApp.swift
let schema = Schema(versionedSchema: RoboSchemaV1.self)
let config = ModelConfiguration(schema: schema)
modelContainer = try ModelContainer(
    for: schema,
    migrationPlan: RoboMigrationPlan.self,
    configurations: [config]
)
```

### Fix 4: Pre-Deploy Validation Script

`scripts/validate-build.sh` checks:
- Encryption compliance key in project.yml
- Version bumped from main
- Explicit `modelContext.save()` in LiDAR and Barcode views
- VersionedSchema defined in RoboSchema.swift
- No bare @Model files outside RoboSchema.swift
- Build succeeds

## Prevention

### SwiftData Rules (Always Follow)

1. **Always call `try modelContext.save()` explicitly after `insert()`** — never rely on autosave, especially before `dismiss()` or navigation changes
2. **All @Model classes must live inside a VersionedSchema enum** — no bare @Model files
3. **Use typealiases** so the rest of the app references simple names (`ScanRecord` not `RoboSchemaV1.ScanRecord`)
4. **New properties must be optional or have defaults** for lightweight migration
5. **When changing models, create a new schema version** (V2) and add a migration stage

### Adding a New Model Property (Future Workflow)

```swift
// 1. Create V2 in RoboSchema.swift
enum RoboSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)
    // ... models with new property (must be optional or have default)
}

// 2. Add migration stage
enum RoboMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [RoboSchemaV1.self, RoboSchemaV2.self]  // chronological order
    }
    static var stages: [MigrationStage] {
        [MigrationStage.lightweight(fromVersion: RoboSchemaV1.self, toVersion: RoboSchemaV2.self)]
    }
}

// 3. Update typealiases to V2
typealias ScanRecord = RoboSchemaV2.ScanRecord
```

### Code Review Checklist for SwiftData Changes

- [ ] Every `modelContext.insert()` is followed by `try modelContext.save()`
- [ ] No bare `@Model` classes exist outside `RoboSchema.swift`
- [ ] New properties are optional or have default values
- [ ] Schema version bumped if models changed
- [ ] Migration stage added for schema changes
- [ ] `scripts/validate-build.sh` passes

## Related Docs

- [RoomPlan Floor Area Zero Fix](../logic-errors/roomplan-floor-area-zero-sqft-fix-20260210.md) — Related floor area calculation fix in same PR
- [RoomPlan Done Button Scan Loss](../ui-bugs/roomplan-done-button-scan-loss-20260210.md) — Another data loss issue (different cause)
- [xcodegen Drops Info.plist Keys](../build-errors/xcodegen-drops-info-plist-keys-testflight-compliance-20260210.md) — Similar "single source of truth" pattern
- [Apple SwiftData Docs: ModelContext.save()](https://developer.apple.com/documentation/swiftdata/modelcontext/save())
- [Apple SwiftData Docs: VersionedSchema](https://developer.apple.com/documentation/swiftdata/versionedschema)
