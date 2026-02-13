---
title: "3D view clutter — remove detected objects, show clean room shell"
category: ui-patterns
date: 2026-02-13
component: ios-lidar
tags: [roomplan, scenekit, 3d-view, objects, furniture, room-shell, export, ai-agents]
severity: medium
symptoms:
  - "3D floor plan tab shows colored boxes for furniture/objects"
  - "Room structure hard to read due to object clutter"
  - "AI agents receiving exports get unnecessary object noise"
related_prs: [105]
---

# 3D View Clutter — Remove Detected Objects, Show Clean Room Shell

## Problem

The 3D floor plan tab renders every detected furniture/object (beds, tables, chairs, etc.) as colored `SCNBox` nodes, cluttering the structural room view. Users sending scan data to AI agents need a clean room shell — floor, walls, ceiling — without furniture noise distracting from the room dimensions.

## Symptoms

- 3D view is visually noisy with colored boxes for every detected object
- Structural room shape (walls, floor, ceiling) hard to discern
- AI agents receiving export data get object arrays they don't need for room dimension analysis

## Root Cause

`Room3DView.swift` parsed objects from summary JSON and rendered each one as a colored `SCNBox` positioned in 3D space. This was a direct port of all RoomPlan data into SceneKit without filtering for what's actually useful in a room dimension context.

The rendering loop:
```swift
// Room3DView.swift — REMOVED
for obj in objects {
    let objNode = makeObjectNode(object: obj)
    scene.rootNode.addChildNode(objNode)
}
```

## Solution

**Remove all object rendering from the 3D view.** The simplest approach — no toggle, no settings. The 3D tab now shows only structural elements: floor (blue), walls (gray with dimension labels), ceiling (white transparent).

### What was removed from `Room3DView.swift`:

| Code | Lines | Purpose |
|------|-------|---------|
| `ObjectInfo` struct | ~8 lines | Data model for parsed objects |
| `objects` field on `RoomSummary` | 1 line | Stored parsed objects |
| Object parsing in `parseSummary()` | ~11 lines | Parsed object JSON into ObjectInfo |
| Object rendering loop in `buildScene()` | ~5 lines | Added SCNBox nodes to scene |
| `makeObjectNode()` | ~19 lines | Created colored SCNBox from ObjectInfo |
| `colorForCategory()` | ~12 lines | Mapped object categories to colors |

**Total: ~56 lines removed, 0 lines added** (net reduction).

### What remains in the 3D view:

- Floor polygon (SCNShape from `floor_polygon_2d_ft`, blue transparent)
- Walls (SCNBox per wall entry, gray with dimension labels)
- Ceiling (SCNShape at ceiling height, white transparent)
- Camera and lighting

### Export unchanged

Objects remain in `room_summary.json` and `room_full.json` exports for backward compatibility. AI agents that want object data still get it in the JSON. The visual-only cleanup keeps the 3D preview clean without breaking downstream consumers.

## Key Decision

**No toggle.** We considered adding a "Show Objects" toggle but decided against it for hackathon simplicity. The 3D view's purpose is room structure visualization for dimension context — objects add no value there. If object visualization is needed later, it can be added back as a toggle without breaking anything.

## Prevention Pattern

When rendering 3D scenes from sensor data, filter for the user's actual need:
- **Room dimensions?** → Walls, floor, ceiling only
- **Interior layout?** → Add objects, doors, windows
- **Navigation?** → Add openings, pathways

Don't render everything just because the data is available.

## Related

- `Room3DView.swift` — the cleaned-up 3D view
- `RoomDataProcessor.swift:59-74` — object data generation (kept for export)
- `docs/solutions/logic-errors/roomplan-floor-area-wrong-axis-dimensions-20260210.md` — axis ambiguity gotcha (unaffected)
- PR #105
