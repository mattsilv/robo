# SwiftData Derived Field Migration Pattern — Quick Reference

## One-Sentence Summary

Use `UserDefaults` versioning + independent `ModelContext` to re-derive stale database fields when calculation logic changes.

## When to Use This Pattern

- ✅ A bug fix changed how a derived field is calculated (e.g., `estimateFloorArea()` improved)
- ✅ Existing user records have stale values, but raw source data is correct
- ✅ You need to re-run business logic on all records at app launch

- ❌ Don't use for schema changes (adding/removing fields) — use SwiftData schema migration instead
- ❌ Don't use if raw source data wasn't saved — you can't re-derive anything

## Implementation Checklist

```swift
// 1. Create migration service
enum SummaryMigrationService {
    static let currentVersion = 1  // Bump when logic changes
    static let versionKey = "room.summaryVersion"

    static func needsMigration(defaults: UserDefaults = .standard) -> Bool {
        defaults.integer(forKey: versionKey) < currentVersion
    }

    static func migrateIfNeeded(container: ModelContainer, defaults: UserDefaults = .standard) {
        guard needsMigration(defaults: defaults) else { return }
        let context = ModelContext(container)
        // Fetch, reprocess, save, bump version
    }
}

// 2. Hook into app launch (before bootstrap)
.task {
    SummaryMigrationService.migrateIfNeeded(container: modelContainer)
    await deviceService.bootstrap()
}

// 3. Test with isolated defaults
let testDefaults = UserDefaults(suiteName: UUID().uuidString)!
SummaryMigrationService.migrateIfNeeded(container: container, defaults: testDefaults)
```

## Code Pattern (Copy-Paste Template)

```swift
enum SummaryMigrationService {
    static let currentVersion = 1
    static let versionKey = "room.summaryVersion"

    static func needsMigration(defaults: UserDefaults = .standard) -> Bool {
        defaults.integer(forKey: versionKey) < currentVersion
    }

    static func migrateIfNeeded(container: ModelContainer, defaults: UserDefaults = .standard) {
        guard needsMigration(defaults: defaults) else { return }
        let context = ModelContext(container)
        do {
            let records = try context.fetch(FetchDescriptor<RoomScanRecord>())
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
        } catch {
            print("[Migration] Failed: \(error)")
        }
    }

    @discardableResult
    static func reprocessRecord(_ record: RoomScanRecord) -> Bool {
        do {
            let room = try JSONDecoder().decode(CapturedRoom.self, from: record.fullRoomDataJSON)
            let summary = RoomDataProcessor.summarizeRoom(room)  // Call the function
            record.floorAreaSqM = summary["estimated_floor_area_sqm"] as? Double ?? 0
            // ... update other derived fields ...
            return true
        } catch {
            return false
        }
    }
}
```

## Key Design Points

| Aspect | Why |
|--------|-----|
| **UserDefaults, not schema migration** | UserDefaults tracks behavioral changes; schema migration tracks structural changes |
| **Independent `ModelContext`** | Runs even if views don't exist; testable without SwiftUI |
| **Per-record error handling** | One corrupt record doesn't crash the entire migration |
| **Dependency-injected UserDefaults** | Can override with test suite in unit tests |
| **Before bootstrap** | Ensures derived fields are fresh before any view reads them |

## Migration Workflow

**When calculating logic changes:**

1. Fix the calculation function (e.g., `RoomDataProcessor.summarizeRoom()`)
2. Bump `currentVersion` in `SummaryMigrationService`
3. Deploy app
4. Users upgrade → app launch → migration runs → all old records re-derived

**Verify:**
```
# Check migration ran — look for "[SummaryMigration]" in Xcode console output
```

## Testing

```swift
@Test func migrationReprocessesStaleRecords() throws {
    let defaults = UserDefaults(suiteName: UUID().uuidString)!  // ISOLATED
    let schema = Schema(versionedSchema: RoboSchemaV1.self)
    let config = ModelConfiguration(isStoredInMemoryOnly: true)
    let container = try ModelContainer(for: schema, configurations: [config])

    let context = ModelContext(container)
    let record = RoomScanRecord(
        roomName: "Test",
        wallCount: 0,
        floorAreaSqM: 0,  // STALE
        objectCount: 0,
        summaryJSON: staleSummaryData,
        fullRoomDataJSON: fixtureData  // RAW DATA PRESERVED
    )
    context.insert(record)
    try context.save()

    SummaryMigrationService.migrateIfNeeded(container: container, defaults: defaults)

    let fetched = try context.fetch(FetchDescriptor<RoomScanRecord>())
    #expect(fetched.first!.floorAreaSqM > 0)  // UPDATED
}
```

## Common Pitfalls

| Pitfall | Fix |
|---------|-----|
| Using shared UserDefaults in tests | Use `UserDefaults(suiteName: UUID().uuidString)` per test |
| Running migration after views render | Call in `.task` before `bootstrap()` |
| Crashing if one record is corrupt | Add `try? reprocessRecord()` or catch-return false |
| Forgetting to bump version | Automation: check PR has version bump vs. previous commit |

## Related Docs

- Full deep-dive: `swiftdata-derived-field-migration-userdefaults-versioning-20260210.md`
- RoomPlan bug it fixed: `../logic-errors/roomplan-floor-area-zero-sqft-fix-20260210.md`
- SwiftData persistence: `../database-issues/swiftdata-persistence-failure-no-save-no-schema-versioning-20260210.md`
