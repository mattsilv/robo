---
title: "SwiftData Schema Drift and Inconsistent Agent Context Threading"
date: 2026-02-12
category: architecture-issues
tags: [swiftdata, schema-migration, ios, swiftui, agent-context, single-source-of-truth]
severity: medium
component: ios/Robo
trigger: pr-review
resolution_time: ~30min
---

# SwiftData Schema Drift and Inconsistent Agent Context Threading

PR #94 revealed four interconnected architectural issues in the Robo iOS app: SwiftData ModelContainer initialization referenced an outdated V3 schema while type aliases pointed to V4 models, creating migration drift; only the LiDAR capture path persisted agent context (agentId/agentName) on records while barcode and motion paths failed to tag captures; photo completion state existed only in-memory as a binding without any durable SwiftData record; and agent display metadata was resolved inconsistently across views.

## Root Cause

### 1. Schema Version Mismatch

`RoboApp.swift` initialized ModelContainer with `RoboSchemaV3.self`, but type aliases pointed to `RoboSchemaV4` models containing `agentId` and `agentName` fields. The container was unaware of these fields, causing silent data loss.

### 2. Inconsistent Agent Context

Only `LiDARScanView` set `record.agentId` and `record.agentName` after saving. `BarcodeScannerView` and `MotionCaptureView` created records without agent context, even when launched from the Agents tab for a specific request.

### 3. Ephemeral Photo Completion

Photo capture detection relied on `@Binding var photoCapturedCount: Int` state. On app restart, this state was lost. No persistent SwiftData record existed for photo work, making the "By Agent" history view unable to display photo history.

### 4. Scattered Metadata Resolution

`ScanHistoryView` maintained a private `agentMetaLookup` dictionary from `MockAgentService.loadAgents()` while also reading denormalized `agentName` from records — two sources of truth for the same data.

## Solution

### 1. Fixed Schema Version (RoboApp.swift)

Changed ModelContainer initialization to match the latest schema:

```swift
// Before (broken)
let schema = Schema(versionedSchema: RoboSchemaV3.self)

// After (fixed)
let schema = Schema(versionedSchema: RoboSchemaV5.self)
```

### 2. Shared CaptureContext Through All Paths (AgentConnection.swift)

Created a single struct to carry agent identity through all capture flows:

```swift
struct CaptureContext {
    let agentId: String
    let agentName: String
    let requestId: UUID
}
```

All capture views accept optional context and tag records at save time:

```swift
struct BarcodeScannerView: View {
    var captureContext: CaptureContext? = nil

    // ... in handleScan():
    let record = ScanRecord(barcodeValue: code, symbology: symbology)
    record.agentId = captureContext?.agentId
    record.agentName = captureContext?.agentName
}
```

AgentsView builds the context from current state:

```swift
private var activeCaptureContext: CaptureContext? {
    guard let agentId = syncingAgentId,
          let agent = agents.first(where: { $0.id == agentId }),
          let request = agent.pendingRequest else { return nil }
    return CaptureContext(agentId: agentId.uuidString, agentName: agent.name, requestId: request.id)
}
```

### 3. Durable AgentCompletionRecord (RoboSchemaV5)

Added a new model for persisting completion events (especially for photos which have no other record):

```swift
@Model final class AgentCompletionRecord {
    var agentId: String
    var agentName: String
    var requestId: String
    var skillType: String      // "camera", "lidar", "barcode", "motion"
    var itemCount: Int
    var completedAt: Date
}
```

`PhotoCaptureView` persists this on "Done" tap. History view queries it alongside other record types.

### 4. Centralized AgentStore (AgentStore.swift)

Replaced scattered lookups with a single enum:

```swift
enum AgentStore {
    static func name(for agentId: String, fallback: String?) -> String
    static func icon(for agentId: String) -> String
    static func color(for agentId: String) -> Color
}
```

`ScanHistoryView` resolves all display metadata via AgentStore. Records store stable `agentId` only; the denormalized `agentName` field serves as a fallback if the agent is no longer registered.

## Prevention

### Schema Version Consistency

When adding a new schema version:

- [ ] Update `ModelContainer` initialization with the new version
- [ ] Update all type aliases to reference the latest schema
- [ ] Update migration plan's `schemas` and `stages` arrays
- [ ] Run `grep -r "SchemaV[0-9]"` to find all hardcoded version references
- [ ] Test on fresh install AND on existing data

### Shared Context for Cross-View Data

When multiple views need the same contextual data:

- [ ] Define ONE struct and thread it through all paths
- [ ] Don't use loose parameters that are easy to forget in new paths
- [ ] Document all capture paths in codebase; verify each receives context
- [ ] PRs modifying capture flows must update ALL paths or document why one is excluded

### Persistence Over Ephemeral Bindings

For state that affects other views (like completion status):

- [ ] Store in SwiftData, not `@Binding` or `@State`
- [ ] Update the record immediately after successful capture
- [ ] Verify state persists across app backgrounding/foregrounding
- [ ] Flag any `@Binding` read by sibling views as a refactoring candidate

### Single Source of Truth for Metadata

For display data like agent names, icons, and colors:

- [ ] Create a centralized store (AgentStore)
- [ ] Store only stable identifiers in records
- [ ] Resolve display metadata at render time from the store
- [ ] Never denormalize metadata fields into data records

## Related Documentation

- [SwiftData Persistence Failure](../database-issues/swiftdata-persistence-failure-no-save-no-schema-versioning-20260210.md) — explicit `modelContext.save()` and VersionedSchema
- [SwiftData Migration Crash Recovery](../database-issues/swiftdata-fatalerror-migration-crash-resilient-recovery-20260211.md) — resilient container factory
- [SwiftData Derived Field Migration](../data-migration/swiftdata-derived-field-migration-userdefaults-versioning-20260210.md) — UserDefaults versioning for recalculations
- [SwiftData Task.detached Isolation](../database-issues/swiftdata-task-detached-isolation-and-delete-save-reliability-20260210.md) — concurrency safety
- [Agent-Driven Capture Plan](../../plans/2026-02-12-feat-agent-driven-capture-auto-complete-plan.md) — feature plan this implements
- GitHub PR: [#94](https://github.com/mattsilv/robo/pull/94)
