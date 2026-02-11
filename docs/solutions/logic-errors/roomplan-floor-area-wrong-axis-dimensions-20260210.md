---
title: "RoomPlan floor area incorrect — Surface.dimensions axis ambiguity"
category: logic-errors
date: 2026-02-10
component: ios-lidar
tags: [roomplan, lidar, floor-area, capturedroom, surface-dimensions, coordinate-system]
severity: high
symptoms:
  - "Floor area wildly incorrect (off by 10x-100x)"
  - "Rectangular fallback produces near-zero area"
  - "dimensions.z is ~0.01 for floor surfaces"
---

# RoomPlan Floor Area Incorrect — Surface.dimensions Axis Ambiguity

## Problem

After LiDAR room scanning, the floor area calculation returns wildly incorrect values (e.g., 2 sq ft for a 150 sq ft room). This occurs when the scan produces floor surfaces with polygon corners that have fewer than 3 points, triggering the rectangular fallback path.

## Symptoms

- Floor area is orders of magnitude too small
- Happens intermittently (depends on scan quality / number of polygon corners returned)
- Wall count, ceiling height, and other metrics are correct
- The rectangular fallback path fires instead of the shoelace formula path

## Root Cause

The rectangular fallback calculated floor area as:

```swift
floor.dimensions.x * floor.dimensions.z  // WRONG
```

For `CapturedRoom.Surface` objects of category `.floor`, Apple's `dimensions` property (`simd_float3`) does **not** map to a consistent coordinate system across surface categories:

| Surface Category | dimensions.x | dimensions.y | dimensions.z |
|-----------------|-------------|-------------|-------------|
| Wall | width | height | thickness (~0.01) |
| Floor | extent A | thickness (~0.01) | extent B |
| *(varies)* | *(inconsistent)* | *(inconsistent)* | *(inconsistent)* |

**The z-axis for floor surfaces often represents surface thickness (~0.01m), not a planar extent.** Apple's documentation does not clarify which axis maps to which physical dimension for each surface category.

## Solution

Instead of hardcoding axis pairs, take the **two largest** of the three dimension values:

```swift
// Before (broken):
let area = Double(floor.dimensions.x) * Double(floor.dimensions.z)

// After (correct):
let w = Double(floor.dimensions.x)
let h = Double(floor.dimensions.y)
let d = Double(floor.dimensions.z)
let sorted = [w, h, d].sorted().reversed()
let dim1 = sorted[sorted.startIndex]
let dim2 = sorted[sorted.index(after: sorted.startIndex)]
let area = dim1 * dim2
```

This works regardless of which axis Apple assigns to thickness, because the thickness value (~0.01m) will always sort last.

## Testing Strategy

`CapturedRoom` and `CapturedRoom.Surface` have **no public initializers**, making direct unit testing impossible. The fix is to extract pure math functions that accept primitive types:

```swift
// Testable: accepts primitives, not CapturedRoom types
static func polygonArea(_ corners: [simd_float3]) -> Double { ... }
static func boundingBoxDimensions(_ positions: [(x: Double, z: Double)]) -> (length: Double, width: Double)? { ... }
static func perimeterSquareArea(_ wallWidths: [Double]) -> Double { ... }
```

Then test with known geometric shapes:

```swift
@Test func polygonAreaSquare10x10() {
    let corners: [simd_float3] = [
        simd_float3(0, 0, 0), simd_float3(10, 0, 0),
        simd_float3(10, 0, 10), simd_float3(0, 0, 10)
    ]
    #expect(abs(RoomDataProcessor.polygonArea(corners) - 100.0) < 0.01)
}
```

## Prevention

1. **Never hardcode axis pairs** for RoomPlan surface dimensions — Apple may change the mapping
2. **Always use axis-agnostic math** (sort and take largest N values)
3. **Add diagnostic logging** in DEBUG builds to catch axis issues early:
   ```swift
   #if DEBUG
   print("[FloorArea] floor dims: x=\(floor.dimensions.x) y=\(floor.dimensions.y) z=\(floor.dimensions.z)")
   #endif
   ```

## Related

- [roomplan-floor-area-zero-sqft-fix](roomplan-floor-area-zero-sqft-fix-20260210.md) — Different bug: shoelace formula on unordered wall positions producing 0.0
- [Issue #28](https://github.com/mattsilv/robo/issues/28) — LiDAR post-processing: dimensions, ceiling height, sq ft
- [Apple RoomPlan docs](https://developer.apple.com/documentation/roomplan/capturedroom/surface)
