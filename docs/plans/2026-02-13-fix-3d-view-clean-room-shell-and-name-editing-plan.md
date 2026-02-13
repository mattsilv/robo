---
title: "fix: Clean 3D view to show room shell only + add room name editing"
type: fix
date: 2026-02-13
---

# fix: Clean 3D view to show room shell only + add room name editing

## Overview

The 3D floor plan tab renders detected furniture/objects (beds, tables, chairs, etc.) as colored boxes, cluttering the structural room view. Users sending scan data to AI agents need a clean room shell — floor, walls, ceiling — without furniture noise. Additionally, room names cannot be edited after saving.

## Problem Statement

1. **3D view clutter**: `Room3DView.swift:62-66` renders every detected object as a colored `SCNBox`, making the structural room view hard to read
2. **No post-save name editing**: `RoomDetailView.swift:18` shows `room.roomName` as read-only `Text` — users can only set names during initial scan (before save)
3. **Export context**: AI agents receiving scan exports get object data that distracts from the room dimensions they actually need

## Proposed Solution

### 1. Remove object rendering from 3D view

**File:** `ios/Robo/Views/Room3DView.swift`

- Delete object rendering loop (lines 62-66):
  ```swift
  // DELETE THIS BLOCK
  for obj in objects {
      let objNode = makeObjectNode(object: obj)
      scene.rootNode.addChildNode(objNode)
  }
  ```
- Remove dead code: `makeObjectNode()` (lines 209-227), `colorForCategory()` (lines 310-321), `ObjectInfo` struct (lines 87-94)
- Remove object parsing from `parseSummary()` (lines 128-138) and from `RoomSummary` struct (line 100)
- Result: 3D view shows only floor (blue), walls (gray + dimension labels), ceiling (white transparent)

### 2. Add inline room name editing on detail view

**File:** `ios/Robo/Views/RoomDetailView.swift`

- Add `@Environment(\.modelContext)` to access SwiftData for saving
- Add `@State private var isEditingName = false` and `@State private var editedName = ""`
- Replace read-only `Text(room.roomName)` (line 18) with conditional:
  - **Default**: Room name as `Text` with a pencil button to enter edit mode
  - **Editing**: `TextField` with done/cancel buttons
- On save: update `room.roomName`, call `try? modelContext.save()`
- Validation: prevent empty/whitespace-only names (revert to original if blank)

```swift
// Editing state
@State private var isEditingName = false
@State private var editedName = ""

// In the Section:
if isEditingName {
    HStack {
        TextField("Room name", text: $editedName)
            .textFieldStyle(.roundedBorder)
        Button("Done") {
            let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
            if !trimmed.isEmpty {
                room.roomName = trimmed
                try? modelContext.save()
            }
            isEditingName = false
        }
        .fontWeight(.semibold)
    }
} else {
    HStack {
        Text(room.roomName)
            .font(.title2.bold())
        Spacer()
        Button {
            editedName = room.roomName
            isEditingName = true
        } label: {
            Image(systemName: "pencil.circle")
                .foregroundStyle(.secondary)
        }
    }
}
```

### 3. Keep export JSON unchanged

Objects remain in `room_summary.json` and `room_full.json` for backward compatibility. AI agents that want object data still get it. The visual-only cleanup keeps the 3D preview clean without breaking downstream consumers.

## Acceptance Criteria

- [x] 3D tab shows only floor, walls, ceiling — no furniture/object boxes
- [x] Room name shows edit (pencil) button on detail view
- [x] Tapping edit enters inline TextField; "Done" saves, empty reverts
- [x] Room name persists after editing (SwiftData save)
- [x] 2D floor plan view unaffected
- [x] Export ZIP still includes full object data in JSON
- [x] No dead code left (object rendering helpers removed)
- [x] Build succeeds on device (`xcodebuild -scheme Robo`)

## Files to Modify

| File | Change |
|------|--------|
| `ios/Robo/Views/Room3DView.swift` | Remove object rendering + dead code cleanup |
| `ios/Robo/Views/RoomDetailView.swift` | Add `@Environment(\.modelContext)`, inline name editing UI |

## What's NOT in scope

- **Door/window 3D rendering**: Summary JSON currently lacks position data for doors/windows (only width/height stored at `RoomDataProcessor.swift:39-57`). Adding position extraction + 3D rendering is too complex for the deadline. Structural walls already convey room shape.
- **Object visibility toggle**: No toggle needed — just remove objects. Simplest approach for hackathon.
- **Export format changes**: Keep `objects` array in summary JSON to avoid breaking AI agent integrations.
- **Schema migration**: `roomName` field already exists on `RoomScanRecord` — editing it requires no schema change.

## References

- `Room3DView.swift:62-66` — object rendering loop to remove
- `Room3DView.swift:209-227` — `makeObjectNode()` dead code
- `Room3DView.swift:310-321` — `colorForCategory()` dead code
- `RoomDetailView.swift:18` — read-only room name to replace
- `RoomDataProcessor.swift:59-74` — object data generation (keep for export)
- `docs/solutions/logic-errors/roomplan-floor-area-wrong-axis-dimensions-20260210.md` — axis ambiguity gotcha (not affected by these changes)
