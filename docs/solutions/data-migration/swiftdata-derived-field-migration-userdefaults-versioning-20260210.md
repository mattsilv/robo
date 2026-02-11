---
title: "SwiftData Derived Field Migration: Re-derive Stale Data with UserDefaults Versioning"
category: data-migration
tags: [swiftdata, migration, data-integrity, ios, roomplan, derived-fields, userdefaults]
severity: high
component: iOS/Models/Services
date: 2026-02-10
root_cause: [bug-fix-in-calculation, stale-derived-data, no-migration-mechanism]
---

# SwiftData Derived Field Migration: Re-derive Stale Data with UserDefaults Versioning

## Problem Symptom

A bug fix is deployed to recalculate derived fields (e.g., floor area) from raw source data stored in the database. However, all existing user records that were saved before the fix still have stale (incorrect) derived values in memory. They never receive the bug fix because there's no mechanism to re-derive them on app launch.

**Observable behavior:**
- Users who upgrade the app see their old room scans display incorrect values (e.g., "0.0 sq ft" floor area)
- New scans use the corrected calculation and show correct values
- Derived fields (`floorAreaSqM`, `wallCount`, `ceilingHeightM`, etc.) in old records are never updated
- The raw source data (`fullRoomDataJSON`) was saved correctly; only the derived summaries are stale

## Root Cause

SwiftData does not provide a built-in mechanism to detect and re-run custom business logic (like `summarizeRoom()`) when that logic changes between app versions. Unlike schema migrations (which handle structural changes to models), data derivation is a behavioral change to a function.

Two approaches exist:

1. **SwiftData schema migration** — too heavyweight for this use case. Requires new `VersionedSchema`, migration stage, and coordination with model structure changes.
2. **UserDefaults version tracking** — lightweight, decoupled from model structure, directly handles "re-derive derived fields when summarization logic changes."

This solution implements approach 2.

## Solution

### Overview

The `SummaryMigrationService` pattern:

1. Track a version number in `UserDefaults` (e.g., `room.summaryVersion`)
2. At app launch, check if the saved version is less than the current version
3. If migration is needed, create an independent `ModelContext`, fetch all records, re-run the derivation function on each, and save
4. Bump the version number to prevent re-running on future launches
5. Dependency-inject `UserDefaults` for testability

### Implementation

#### Step 1: Define SummaryMigrationService

```swift
// ios/Robo/Services/SummaryMigrationService.swift
import Foundation
import SwiftData
import RoomPlan

/// Re-derives summaryJSON and related fields from raw CapturedRoom data when the summary format changes.
/// Uses UserDefaults versioning instead of SwiftData schema migration to avoid complexity.
enum SummaryMigrationService {

    static let currentVersion = 1
    static let versionKey = "room.summaryVersion"

    /// Check if stored version is less than current version
    static func needsMigration(defaults: UserDefaults = .standard) -> Bool {
        defaults.integer(forKey: versionKey) < currentVersion
    }

    /// Run at app launch. Creates its own ModelContext so it's independent of views.
    static func migrateIfNeeded(container: ModelContainer, defaults: UserDefaults = .standard) {
        guard needsMigration(defaults: defaults) else { return }

        let context = ModelContext(container)
        let descriptor = FetchDescriptor<RoomScanRecord>()

        do {
            let records = try context.fetch(descriptor)
            var updated = 0
            for record in records {
                if reprocessRecord(record) {
                    updated += 1
                }
            }
            if updated > 0 {
                try context.save()
            }
            defaults.set(currentVersion, forKey: versionKey)
            #if DEBUG
            print("[SummaryMigration] Migrated \(updated)/\(records.count) records to v\(currentVersion)")
            #endif
        } catch {
            #if DEBUG
            print("[SummaryMigration] Migration failed: \(error)")
            #endif
        }
    }

    /// Decode fullRoomDataJSON → CapturedRoom, re-run summarizeRoom, update derived fields.
    /// Returns true if the record was updated.
    @discardableResult
    static func reprocessRecord(_ record: RoomScanRecord) -> Bool {
        do {
            let room = try JSONDecoder().decode(CapturedRoom.self, from: record.fullRoomDataJSON)
            let summary = RoomDataProcessor.summarizeRoom(room)
            let summaryData = try RoomDataProcessor.encodeSummary(summary)

            // Update all derived fields from the fresh summary
            record.summaryJSON = summaryData
            record.floorAreaSqM = summary["estimated_floor_area_sqm"] as? Double ?? 0
            record.ceilingHeightM = summary["ceiling_height_m"] as? Double ?? 0
            record.wallCount = summary["wall_count"] as? Int ?? 0
            record.objectCount = summary["object_count"] as? Int ?? 0
            return true
        } catch {
            #if DEBUG
            print("[SummaryMigration] Failed to reprocess '\(record.roomName)': \(error)")
            #endif
            return false
        }
    }
}
```

**Key design points:**

- `currentVersion` is a compile-time constant, bumped when `summarizeRoom()` or any derivation logic changes
- `needsMigration()` is a pure function for testing
- `migrateIfNeeded()` creates its own `ModelContext` — doesn't depend on view state or the main context
- `reprocessRecord()` is marked `@discardableResult` — caller doesn't care about the return value, only side effects
- Per-record error handling: one corrupt record doesn't break the entire migration
- Debug logging for visibility into what was migrated

#### Step 2: Hook Into App Launch

```swift
// ios/Robo/RoboApp.swift
@main
struct RoboApp: App {
    @Environment(\.scenePhase) var scenePhase
    let modelContainer: ModelContainer
    let deviceService: DeviceService
    let apiService: APIService

    init() {
        // ... existing modelContainer setup ...
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(deviceService)
                .environment(apiService)
                .task {
                    // Run migration BEFORE bootstrap
                    SummaryMigrationService.migrateIfNeeded(container: modelContainer)
                    await deviceService.bootstrap(apiService: apiService)
                }
        }
        .modelContainer(modelContainer)
    }
}
```

**Why `.task` is the right place:**

- Runs once per window lifecycle (not on every view render)
- Runs before view content is built
- Doesn't block the UI (async context available)
- If the migration takes 500ms for 100 records, the user sees a loading screen or the app bootstraps in the background

#### Step 3: Model Must Have Raw Source Data

The migration only works if the model stores both raw and derived data:

```swift
// ios/Robo/Models/RoomScanRecord.swift
@Model
final class RoomScanRecord {
    var roomName: String
    var timestamp: Date

    // RAW SOURCE DATA — necessary for migration
    var fullRoomDataJSON: Data

    // DERIVED FIELDS — updated by migration
    var summaryJSON: Data
    var floorAreaSqM: Double
    var ceilingHeightM: Double
    var wallCount: Int
    var objectCount: Int

    init(
        roomName: String,
        wallCount: Int,
        floorAreaSqM: Double,
        objectCount: Int,
        summaryJSON: Data,
        fullRoomDataJSON: Data,
        timestamp: Date = Date()
    ) {
        self.roomName = roomName
        self.wallCount = wallCount
        self.floorAreaSqM = floorAreaSqM
        self.objectCount = objectCount
        self.summaryJSON = summaryJSON
        self.fullRoomDataJSON = fullRoomDataJSON
        self.timestamp = timestamp
    }
}
```

### Step 4: Testing

Use isolated `UserDefaults` for each test to avoid interference:

```swift
// ios/RoboTests/SummaryMigrationTests.swift
import Testing
import Foundation
import SwiftData
import RoomPlan
@testable import Robo

@Test func migrationNeededWhenVersionIsZero() {
    // Fresh defaults → migration needed
    let defaults = UserDefaults(suiteName: "test.migration.\(UUID().uuidString)")!
    #expect(SummaryMigrationService.needsMigration(defaults: defaults) == true)
}

@Test func migrationNotNeededWhenVersionIsCurrent() {
    let defaults = UserDefaults(suiteName: "test.migration.\(UUID().uuidString)")!
    defaults.set(SummaryMigrationService.currentVersion, forKey: SummaryMigrationService.versionKey)
    #expect(SummaryMigrationService.needsMigration(defaults: defaults) == false)
}

@Test func migrationReprocessesStaleRecords() throws {
    // Load fixture with CapturedRoom from real LiDAR scan
    guard let fixtureData = loadFixture(named: "captured_room_fixture") else {
        print("Skipping: no fixture in test bundle")
        return
    }

    // Isolated UserDefaults for this test
    let defaults = UserDefaults(suiteName: "test.migration.\(UUID().uuidString)")!

    // In-memory container
    let schema = Schema(versionedSchema: RoboSchemaV1.self)
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [config])
    let context = ModelContext(container)

    // Insert record with stale summary (zero floor area from old bug)
    let staleSummary: [String: Any] = ["estimated_floor_area_sqm": 0.0, "wall_count": 0]
    let staleSummaryData = try JSONSerialization.data(withJSONObject: staleSummary)

    let record = RoomScanRecord(
        roomName: "Test Room",
        wallCount: 0,
        floorAreaSqM: 0,
        objectCount: 0,
        summaryJSON: staleSummaryData,
        fullRoomDataJSON: fixtureData
    )
    context.insert(record)
    try context.save()

    // Run migration (version is 0 in fresh defaults → triggers migration)
    SummaryMigrationService.migrateIfNeeded(container: container, defaults: defaults)

    // Fetch and verify
    let fetched = try context.fetch(FetchDescriptor<RoomScanRecord>())
    let migrated = fetched.first!
    #expect(migrated.floorAreaSqM > 0, "Floor area should be updated after migration")
    #expect(migrated.wallCount > 0, "Wall count should be updated after migration")
}
```

**Test isolation pattern:**

Each test gets a unique `UserDefaults` suite name via UUID. This prevents test A from seeing version flags set by test B.

### Step 5: Version Bump Workflow

When `RoomDataProcessor.summarizeRoom()` is changed (bug fix or new fields):

```swift
// 1. Update the function
static func summarizeRoom(_ room: CapturedRoom) -> [String: Any] {
    // ... new or fixed calculation logic ...
}

// 2. Bump the version number
static let currentVersion = 2  // was 1

// 3. Add comment explaining what changed
// Migration: v1 → v2 recalculates floor area using new polygonArea() logic
```

On the next app launch, all existing records will be re-derived.

## Key Implementation Decisions

### 1. UserDefaults Over SwiftData Schema Migration

**Why not SwiftData schema migration?**

Schema migration handles *structural* changes (adding a column, renaming a field). Re-deriving derived fields is a *behavioral* change (the algorithm changed, not the schema).

Using schema migration for this would require:
- Creating `RoboSchemaV2` with no model changes (confusing)
- Adding an empty migration stage
- Coupling business logic with schema versions

**Benefit of UserDefaults approach:**
- Decoupled from schema versioning
- Can bump version independently when calculation logic changes
- Simpler test setup (no schema, just isolated defaults)
- Lightweight for users

### 2. Independent ModelContext at App Launch

Creating a new `ModelContext(container)` inside `migrateIfNeeded()` instead of using the view's context:

- **Pro:** Migration runs even if views never get a context
- **Pro:** Independent of SwiftUI lifecycle
- **Pro:** Testable in unit tests without SwiftUI

- **Con:** Potential race condition if multiple windows exist simultaneously

This is acceptable for an MVP. If simultaneous multi-window editing becomes critical, add a lock or coordinator pattern.

### 3. Per-Record Error Handling

```swift
for record in records {
    if reprocessRecord(record) {  // returns Bool
        updated += 1
    }
}
```

If one record has corrupt `fullRoomDataJSON`, the migration doesn't crash. That record is skipped, logged, and the rest proceed.

**Alternative:** Throw on first error, stop migration. But that means all subsequent records stay stale because one was corrupt.

### 4. Dependency Injection of UserDefaults

```swift
static func needsMigration(defaults: UserDefaults = .standard) -> Bool {
    defaults.integer(forKey: versionKey) < currentVersion
}

static func migrateIfNeeded(container: ModelContainer, defaults: UserDefaults = .standard) {
    // ...
}
```

The `defaults` parameter has a default value (`.standard`) but can be overridden in tests.

**This enables:**
```swift
// In app
SummaryMigrationService.migrateIfNeeded(container: modelContainer)

// In tests
let testDefaults = UserDefaults(suiteName: UUID().uuidString)!
SummaryMigrationService.migrateIfNeeded(container: container, defaults: testDefaults)
```

### 5. Timing: Before Bootstrap

```swift
.task {
    SummaryMigrationService.migrateIfNeeded(container: modelContainer)
    await deviceService.bootstrap(apiService: apiService)
}
```

Run migration *before* `deviceService.bootstrap()`, so:
- Any code that reads derived fields sees fresh values
- Users see correct data immediately on first view render
- No race condition between migration and view fetches

## Real-World Context: RoomPlan Floor Area Bug Fix

This pattern was implemented to fix a specific bug in the Robo app:

**The bug:** `estimateFloorArea()` used the shoelace formula on unordered wall center positions, producing 0.0 sq ft.

**The fix:** Changed to use `CapturedRoom.floors` (ordered polygon vertices), producing correct areas.

**Migration need:** Existing room scans had `floorAreaSqM = 0` in their summaries. The raw `fullRoomDataJSON` (CapturedRoom) was saved correctly, so re-running `summarizeRoom()` would produce the correct area.

**What happened:**
1. Deploy app with `currentVersion = 1` and fixed calculation logic
2. User upgrades app
3. `RoboApp.init()` → app launch
4. `.task` runs → `SummaryMigrationService.migrateIfNeeded()`
5. UserDefaults has no `room.summaryVersion` key (defaults to 0)
6. `0 < 1` → migration runs
7. All records re-derived with fixed `estimateFloorArea()`
8. Users see old scans with correct floor area values
9. Version bumped to 1 in UserDefaults
10. Next app launch → `1 < 1` is false → no migration

## Prevention: Code Review Checklist

When modifying a derived-field calculation:

- [ ] Is the raw source data being saved to the model? (Can't re-derive without it)
- [ ] Are derived fields always kept in sync with source data on initial save?
- [ ] Does the service have isolated tests using unique UserDefaults suites?
- [ ] Has `currentVersion` been bumped in `SummaryMigrationService`?
- [ ] Is the app launching migration before views render?
- [ ] Have you manually tested upgrading from a previous app build and verified derived fields update?

## Limitations and Future Improvements

1. **No automatic detection of when to migrate**
  - Requires manual `currentVersion` bump
  - Consider adding a hash of the calculation function for auto-detection (future M2 work)

2. **Migration is fire-and-forget**
  - No progress UI for users
  - If migration takes >1s, users might not realize it's happening
  - Could add a progress modal or background refresh for large datasets

3. **Single UserDefaults key tracks all migrations**
  - Works for MVP with one migration
  - Future: track per-field or per-feature for finer control

4. **Re-derives *all* records even if only one function changed**
  - Could optimize to only re-derive affected fields
  - Trade-off: simplicity vs. performance (acceptable for <1000 records)

## Files

- `ios/Robo/Services/SummaryMigrationService.swift` — Core migration logic
- `ios/Robo/RoboApp.swift` — App launch integration (`.task` block)
- `ios/RoboTests/SummaryMigrationTests.swift` — Unit tests with isolated defaults
- `ios/Robo/Services/RoomDataProcessor.swift` — `summarizeRoom()` function being protected
- `ios/Robo/Models/RoomScanRecord.swift` — Model structure

## Related Docs

- [SwiftData Persistence Failure: Missing Explicit Save and Schema Versioning](../database-issues/swiftdata-persistence-failure-no-save-no-schema-versioning-20260210.md) — Schema migration (different from this pattern)
- [RoomPlan Floor Area Zero Fix](../logic-errors/roomplan-floor-area-zero-sqft-fix-20260210.md) — The specific calculation bug that triggered this migration pattern
- [Apple SwiftData Documentation: ModelContext](https://developer.apple.com/documentation/swiftdata/modelcontext)
- [Apple Foundation Documentation: UserDefaults](https://developer.apple.com/documentation/foundation/userdefaults)
