---
title: "RoomPlan floor area returns 0.0 sq ft — shoelace formula on unordered wall positions"
category: logic-errors
date: 2026-02-10
component: ios-lidar
tags: [roomplan, lidar, floor-area, shoelace-formula, capturedroom, ios17]
severity: high
symptoms: ["0.0 sq ft", "floor area zero", "area calculation wrong"]
---

# RoomPlan Floor Area Returns 0.0 sq ft — Shoelace Formula on Unordered Wall Positions

## Problem

After completing a LiDAR room scan, the scan results screen displays "0.0 sq ft (0.0 m2)" for floor area even though walls, doors, windows, and objects are all detected correctly.

## Symptoms

- Floor area displays as "0.0 sq ft" on the scan results screen
- Wall count, door count, window count, and object count are all correct
- Ceiling height may also show 0 if it was derived from the floor area calculation
- The bug only manifests with real LiDAR scans, not mock/test data

## Root Cause

The original `estimateFloorArea()` function used the shoelace formula on wall center positions (`transform.columns.3`), treating them as ordered polygon vertices. This is fundamentally wrong because RoomPlan wall surfaces are NOT ordered as a polygon -- they are individual surfaces floating in 3D space with no guaranteed ordering.

The shoelace formula requires vertices to be ordered sequentially around a polygon perimeter. When applied to unordered wall center points, the formula produces near-zero or wildly incorrect areas because the "polygon" it traces crosses over itself repeatedly, with positive and negative area contributions canceling out.

### Why it produces exactly 0.0

With unordered points, the shoelace formula traces a self-intersecting path. The positive and negative area contributions from the crossing edges nearly cancel out, resulting in a value very close to zero. After `abs()` and rounding for display, this shows as "0.0 sq ft".

## Original Broken Code

In `RoomDataProcessor.swift`:

```swift
static func estimateFloorArea(_ walls: [CapturedRoom.Surface]) -> Double {
    guard walls.count >= 4 else {
        let perimeter = walls.reduce(0.0) { $0 + Double($1.dimensions.x) }
        let side = perimeter / 4.0
        return side * side
    }
    let points = walls.map { wall -> (Double, Double) in
        let col3 = wall.transform.columns.3  // Wall CENTER position
        return (Double(col3.x), Double(col3.z))
    }
    // Shoelace formula on UNORDERED points = wrong!
    var area = 0.0
    for i in 0..<points.count {
        let j = (i + 1) % points.count
        area += points[i].0 * points[j].1
        area -= points[j].0 * points[i].1
    }
    return abs(area) / 2.0
}
```

The critical flaw: `walls.map { ... }` iterates walls in whatever order RoomPlan returns them, which is NOT a polygon traversal order. The shoelace formula then connects these arbitrary points in sequence, forming a self-intersecting shape with near-zero net area.

## Fixed Code

Three-tier approach per Apple RoomPlan documentation:

```swift
static func estimateFloorArea(_ room: CapturedRoom) -> Double {
    // Best: use actual floor surfaces (iOS 17+)
    if !room.floors.isEmpty {
        return room.floors.reduce(0.0) { total, floor in
            let corners = floor.polygonCorners
            if corners.count >= 3 {
                return total + polygonArea(corners)
            }
            return total + Double(floor.dimensions.x) * Double(floor.dimensions.z)
        }
    }
    // Fallback: bounding box from wall positions
    if let dims = estimateRoomDimensions(room.walls) {
        return dims.length * dims.width
    }
    // Last resort: assume square from perimeter
    let perimeter = room.walls.reduce(0.0) { $0 + Double($1.dimensions.x) }
    let side = perimeter / 4.0
    return side * side
}

private static func polygonArea(_ corners: [simd_float3]) -> Double {
    var area = 0.0
    for i in 0..<corners.count {
        let j = (i + 1) % corners.count
        area += Double(corners[i].x) * Double(corners[j].z)
        area -= Double(corners[j].x) * Double(corners[i].z)
    }
    return abs(area) / 2.0
}
```

### Why this works

1. **Tier 1 -- `room.floors`**: RoomPlan on iOS 17+ detects floor surfaces directly. `Surface.polygonCorners` returns the actual polygon vertices of the floor in local plane coordinates, already ordered correctly. The shoelace formula works correctly on these ordered vertices.

2. **Tier 2 -- Bounding box**: If no floor surfaces are detected, compute the axis-aligned bounding box from wall positions. This gives a rectangular approximation (length x width) which is reasonable for most rooms.

3. **Tier 3 -- Square from perimeter**: Last resort fallback. Sum all wall widths to get the perimeter, assume a square room, and compute area. This is the least accurate but always produces a non-zero result.

### Key signature change

The function signature changed from taking `[CapturedRoom.Surface]` (just walls) to taking `CapturedRoom` (the full room). This is necessary to access `room.floors`, which is the primary data source for floor area.

## Key RoomPlan API Insights

From Apple documentation:

- **`CapturedRoom.floors`** (iOS 17+): Array of floor surfaces detected by RoomPlan. This is the best and most direct source for floor area calculation.

- **`Surface.polygonCorners`** (iOS 17+): Returns the actual polygon vertices of a surface in local plane coordinates. These vertices ARE ordered correctly for the shoelace formula, unlike wall center positions.

- **`Surface.dimensions`**: The bounding box of the surface as a `simd_float3` (width x height x depth). Useful as a fallback when `polygonCorners` is unavailable or has fewer than 3 points.

- **`Surface.transform.columns.3`**: The surface's position in world space. Useful for computing bounding boxes and relative positions, but NOT suitable as polygon vertices for area calculation.

- **Wall ordering**: RoomPlan does not guarantee any particular ordering of walls in the `CapturedRoom.walls` array. Walls may be returned in detection order, spatial clustering order, or any other internal ordering. Never assume they form a polygon perimeter.

## Prevention

- **Always prefer `CapturedRoom.floors`** over computing area from walls. Apple provides floor detection specifically for this purpose.

- **When using the shoelace formula**, ensure the input points are ordered polygon vertices (like `polygonCorners`), not arbitrary positions extracted from unrelated surfaces.

- **Test with real LiDAR scans, not just mock data.** The 0.0 bug only appears with real RoomPlan data because mock data often uses conveniently ordered wall positions that happen to produce correct results.

- **Validate area results against expected ranges.** A room with 4+ detected walls should never have a floor area of 0.0. Add a sanity check or log a warning when the computed area is suspiciously low relative to the detected wall count.

## Files

- `ios/Robo/Services/RoomDataProcessor.swift` -- `estimateFloorArea()` and `polygonArea()` functions
