---
title: "Agent-Driven Capture with Auto-Complete and Real History"
type: feat
date: 2026-02-12
deadline: 2026-02-16
---

# Agent-Driven Capture with Auto-Complete and Real History

## Overview

Connect the existing agent-driven scanning flow end-to-end: when Interior Designer asks for a floor plan, tapping "Scan Room" opens LiDAR, saving the scan auto-completes the agent's request, and the floor plan appears in History under that agent — with full export. Future phase adds webhook + AI processing.

## Current State (What Already Works)

The app is **90% there** — the agent-driven model is already in place:

- **3-tab structure**: Agents | My Data | Settings (no sensor-specific tabs)
- **Agent request cards**: Interior Designer shows "Send me the floor plan of your master bedroom" with "Scan Room" CTA
- **Scanner launch**: Tapping CTA opens LiDARScanView full-screen with guided capture tips
- **Post-scan sync**: AgentsView detects new `roomScans.count > initialRoomCount`, triggers 2s sync animation, marks agent as connected
- **Data persistence**: Room scans save to SwiftData with full JSON, visible in My Data > By Type > Rooms
- **Export**: Individual room share + "Export All" ZIP

## Gaps to Close

| Gap | Impact | Fix Complexity |
|-----|--------|----------------|
| `RoomScanRecord` has no `agentId` field | Can't show rooms under their requesting agent in History | SwiftData V4 migration (lightweight, add 2 optional String fields) |
| `LiDARScanView` doesn't receive agent context | Saved records are untagged, room name defaults to timestamp | Pass `agentName` + `agentId` as init params |
| History "By Agent" view uses `mockAgentData()` | Shows fake hardcoded data instead of real scans | Replace with SwiftData query grouped by `agentId` |
| Room name defaults to "Room Scan Feb 12, 3:45 PM" | Should be "Master Bedroom" when agent provides context | Pre-fill from agent request title |

## Proposed Solution

### Phase 1: Wire the POC Flow (Priority: Hackathon Demo)

The Interior Designer asks → user taps Scan Room → LiDAR opens → scan + save → auto-complete → shows in history under that agent.

#### 1.1 Add Agent Context to SwiftData Schema

**File: `ios/Robo/Models/RoboSchema.swift`**

Add V4 schema with two optional fields on `RoomScanRecord`:

```swift
// New optional fields (lightweight migration, no data loss)
var agentId: String?       // UUID string of the requesting agent
var agentName: String?     // "Interior Designer" (denormalized for display)
```

Also add to `ScanRecord` and `MotionRecord` for consistency — the app has agent-initiated flows for barcode and camera too, and without these fields those captures can't appear in the "By Agent" history view.

Optionally add `syncStatus: String?` (nil/pending/synced/failed) to all record types now to avoid a V5 migration when the webhook phase arrives.

Migration: `RoboSchemaV3` → `RoboSchemaV4`, lightweight (all new fields are optional).

#### 1.2 Pass Agent Context Through Scanner Launch

**File: `ios/Robo/Views/InboxView.swift` (AgentsView)**

When launching LiDARScanView from an agent request, pass the agent's ID and request title:

```swift
// Current:
.fullScreenCover(isPresented: $showingLiDARScan, onDismiss: handleLiDARDismiss) {
    LiDARScanView()
}

// After:
.fullScreenCover(isPresented: $showingLiDARScan, onDismiss: handleLiDARDismiss) {
    LiDARScanView(
        agentId: syncingAgentId?.uuidString,
        agentName: agents.first(where: { $0.id == syncingAgentId })?.name,
        suggestedRoomName: agents.first(where: { $0.id == syncingAgentId })?.pendingRequest?.title
    )
}
```

**File: `ios/Robo/Views/LiDARScanView.swift`**

Accept optional agent context:

```swift
struct LiDARScanView: View {
    var agentId: String? = nil
    var agentName: String? = nil
    var suggestedRoomName: String? = nil
    // ... existing properties
}
```

In `saveRoom()`, tag the record:

```swift
let record = RoomScanRecord(
    roomName: name,
    wallCount: room.walls.count,
    // ...existing fields...
)
record.agentId = agentId
record.agentName = agentName
```

Pre-fill room name from agent request. Add a `roomNameHint` field to `AgentRequest` in `MockAgentService` (e.g., "Master Bedroom") rather than parsing the full request title:

```swift
// In MockAgentService, add to AgentRequest:
let roomNameHint: String?  // "Master Bedroom"

// In LiDARScanView:
@State private var roomName = ""

.onAppear {
    if let suggested = suggestedRoomName, roomName.isEmpty {
        roomName = suggested
    }
}
```

#### 1.3 Auto-Complete Agent Request After Save

This **already works** via `handleLiDARDismiss()` which checks `roomScans.count > initialRoomCount` and calls `triggerSyncAnimation(for:)`. No changes needed here — the sync animation correctly:
1. Sets agent status to `.syncing`
2. After 2 seconds, marks as `.connected`
3. Clears `pendingRequest`
4. Sets `lastSyncDate = Date()`
5. Plays haptic + sound

The only improvement: make the default room name contextual (done in 1.2).

### Phase 2: Real History "By Agent" View

**File: `ios/Robo/Views/ScanHistoryView.swift`**

Replace `mockAgentData()` with real SwiftData queries:

```swift
// Instead of hardcoded mock data, query SwiftData for agent-tagged records
private var agentDataList: some View {
    let agentRooms = Dictionary(grouping: roomScans.filter { $0.agentId != nil }) { $0.agentName ?? "Unknown" }
    let agentBarcodes = Dictionary(grouping: scans.filter { $0.agentId != nil }) { $0.agentName ?? "Unknown" }
    // Merge all agent names, build sections from real data
    // ...
}
```

**Design:**

```
┌─────────────────────────────────────┐
│  My Data                            │
│  [By Agent] [By Type]               │
│─────────────────────────────────────│
│                                     │
│  ☐ Interior Designer                │
│  ┌─────────────────────────────────┐│
│  │ 📐 Master Bedroom               ││
│  │    Room scan — 12ft x 14ft      ││
│  │    4 walls · 2 min ago          ││
│  └─────────────────────────────────┘│
│                                     │
│  ☐ Practical Chef                   │
│  ┌─────────────────────────────────┐│
│  │ 🔍 Chickpeas (071524017...)     ││
│  │    Barcode · 5 min ago          ││
│  └─────────────────────────────────┘│
│                                     │
│  ☐ Unlinked Scans                   │
│  ┌─────────────────────────────────┐│
│  │ 📐 Living Room                  ││
│  │    Room scan — captured directly ││
│  └─────────────────────────────────┘│
│                                     │
│  ┌─────────────────────────────────┐│
│  │ + Scan Room   + Scan Barcode    ││
│  │       (direct capture CTAs)     ││
│  └─────────────────────────────────┘│
└─────────────────────────────────────┘
```

- Each agent section shows its icon, color, and name as section header
- Items are real SwiftData records **wrapped in NavigationLink** to existing detail views (RoomDetailView, BarcodeDetailView, MotionDetailView)
- "Unlinked Scans" section for data captured without agent context
- Only agents with at least one linked record appear (no empty agent sections)
- Bottom CTAs for direct capture without an agent request
- Agent metadata (icon, color) looked up from `MockAgentService` by agentId; unrecognized IDs show as "Unknown Agent"

### Phase 3: History Direct Capture CTAs

The "By Type" view **already has CTAs** for empty states:
- "Scan Barcode" on empty barcodes list
- "Scan Room" on empty rooms list
- "Capture Motion" on empty motion list

Add similar CTAs to the "By Agent" view:

**At the bottom of the agent data list**, add a section with quick-capture buttons:

```swift
Section("Quick Capture") {
    Button { showingLiDARScanner = true } label: {
        Label("Scan Room", systemImage: "camera.metering.spot")
    }
    Button { showingBarcodeScanner = true } label: {
        Label("Scan Barcode", systemImage: "barcode.viewfinder")
    }
}
```

These launch scanners without agent context (data saves as "unlinked").

### Phase 4: Cleanup Orphaned Views

Remove dead code that's no longer part of the navigation tree:

| File | Status | Action |
|------|--------|--------|
| `SensorsView.swift` | Orphaned, not in any tab | Delete |
| `SensorPickerView.swift` | Orphaned, not referenced | Delete |
| `SendView.swift` | Orphaned, not referenced from tabs | Delete |
| `CameraPreviewView.swift` | Appears unused (PhotoCaptureView has its own) | Delete |

Also:
- Rename `InboxView.swift` to `AgentsView.swift` (struct inside is already `AgentsView`)

### Phase 5 (Future): Webhook + AI Processing

After the demo POC works, add webhook integration:

1. **After sync animation completes** in `triggerSyncAnimation(for:)`, POST the floor plan data to the demo API
2. **Workers endpoint**: `POST /api/agent-response` receives room scan JSON
3. **AI processing**: Workers calls an AI API with the room dimensions + objects
4. **Response**: Returns furniture layout suggestions, rendered as a new card in the Agents tab

```
User saves scan → Sync animation → POST to webhook
                                      ↓
                              Workers processes with AI
                                      ↓
                              Push response as new InboxCard
                                      ↓
                              Agent card shows AI analysis
```

This phase is deferred until the core capture flow is solid.

## Acceptance Criteria

### Phase 1 (Demo-Ready POC)
- [ ] Interior Designer agent card shows in Agents tab with "Send me the floor plan..." request
- [ ] Tapping "Scan Room" opens LiDARScanView full-screen
- [ ] Room name pre-fills with agent request context (not timestamp)
- [ ] After saving scan, room record has `agentId` and `agentName` set
- [ ] AgentsView detects new scan, shows sync animation, marks request complete
- [ ] Saved room appears in My Data > By Type > Rooms with export functionality

### Phase 2 (Real History)
- [ ] My Data > By Agent shows real SwiftData records grouped by agent
- [ ] Each agent section uses the agent's icon and color
- [ ] Tapping items navigates to existing detail views (RoomDetailView, etc.)
- [ ] "Unlinked Scans" section shows data captured without agent context

### Phase 3 (Direct CTAs)
- [ ] Quick Capture buttons at bottom of "By Agent" view
- [ ] Direct captures save without agent tagging

### Phase 4 (Cleanup)
- [ ] Orphaned views removed
- [ ] InboxView.swift renamed to AgentsView.swift

## Implementation Order

For the hackathon deadline (Feb 16):

1. **Phase 1** (1-2 hours): Schema V4 + pass agent context + pre-fill room name. This is the demo.
2. **Phase 2** (1 hour): Replace mock history with real data. Makes the demo flow complete.
3. **Phase 4** (15 min): Cleanup. Quick wins.
4. **Phase 3** (30 min): Direct CTAs. Nice-to-have.
5. **Phase 5** (post-deadline): Webhook + AI. Future work.

## Known Bugs to Fix (from SpecFlow Analysis)

1. **Photo dismiss false positive**: `handlePhotoDismiss()` always triggers sync animation even if zero photos were captured. Fix: only trigger sync if photos were actually taken (requires `PhotoCaptureView` to communicate result back via a binding or callback).

2. **Barcode agent flow missing dismiss handler**: `showingBarcode` fullScreenCover has no `onDismiss` handler, so the sync animation never fires for barcode agent requests. Fix: add `handleBarcodeDismiss()` similar to `handleLiDARDismiss()`.

3. **Motion agent flow is a no-op**: `case .motion: break` in `handleScanNow`. Out of scope for this POC but should be addressed before demo.

These are pre-existing bugs, not introduced by this feature. Fix #1 and #2 as part of Phase 1 polish; defer #3.

## Edge Cases Considered

- **User cancels scan**: No new room saved → `roomScans.count` unchanged → sync not triggered → agent request stays pending. Correct behavior.
- **Scan fails mid-capture**: Error alert shown, phase resets to instructions. Agent request stays pending.
- **Multiple scans from same agent**: Each gets tagged with the agent's ID. All show in History under that agent.
- **Direct capture (no agent)**: `agentId` is nil → shows in "Unlinked Scans" section in History.
- **App crash during scan**: SwiftData only persists on `modelContext.save()` which happens after scan completes. No partial data corruption.
- **LiDAR not available**: ContentUnavailableView shown with explanation. Agent request stays pending.

## Files to Modify

| File | Changes |
|------|---------|
| `ios/Robo/Models/RoboSchema.swift` | Add V4 schema with agentId/agentName on all record types |
| `ios/Robo/Views/LiDARScanView.swift` | Accept agent context params, pre-fill room name, tag saved record |
| `ios/Robo/Views/InboxView.swift` | Pass agent context when launching LiDARScanView |
| `ios/Robo/Views/ScanHistoryView.swift` | Replace mockAgentData() with real SwiftData queries |
| `ios/Robo/Views/SensorsView.swift` | Delete (orphaned) |
| `ios/Robo/Views/SensorPickerView.swift` | Delete (orphaned) |
| `ios/Robo/Views/SendView.swift` | Delete (orphaned) |
| `ios/Robo/Views/CameraPreviewView.swift` | Delete (orphaned) |

## References

- LiDAR Done button safety: `docs/solutions/ui-bugs/roomplan-done-button-scan-loss-20260210.md`
- Scanner modal pattern: `docs/solutions/ui-patterns/scanner-as-modal-tab-restructure-20260210.md`
- Agent workflow UX: `docs/use-cases.md` (Demo Scenario section)
- SwiftData migration pattern: `docs/solutions/data-migration/PATTERN_SUMMARY.md`
