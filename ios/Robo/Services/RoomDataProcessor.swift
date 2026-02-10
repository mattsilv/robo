import Foundation
import RoomPlan

enum RoomDataProcessor {

    private static let metersToFeet = 3.28084
    private static let sqmToSqft = 10.7639

    // MARK: - Summary

    /// Creates an AI-friendly summary from a CapturedRoom.
    /// Includes both metric and imperial, plus computed insights.
    static func summarizeRoom(_ room: CapturedRoom) -> [String: Any] {
        let ceilingHeight = estimateCeilingHeight(room.walls)
        let floorArea = estimateFloorArea(room.walls)
        let totalWallArea = computeTotalWallArea(room.walls)
        let volume = floorArea * ceilingHeight

        let wallData = room.walls.map { surface -> [String: Any] in
            let dims = surface.dimensions
            let w = Double(dims.x)
            let h = Double(dims.y)
            return [
                "width_m": r2(w),
                "height_m": r2(h),
                "width_ft": r2(w * metersToFeet),
                "height_ft": r2(h * metersToFeet),
                "area_sqm": r2(w * h),
                "area_sqft": r2(w * h * sqmToSqft)
            ]
        }

        let doorData = room.doors.map { surface -> [String: Any] in
            let dims = surface.dimensions
            let w = Double(dims.x)
            let h = Double(dims.y)
            return [
                "width_m": r2(w), "height_m": r2(h),
                "width_ft": r2(w * metersToFeet), "height_ft": r2(h * metersToFeet)
            ]
        }

        let windowData = room.windows.map { surface -> [String: Any] in
            let dims = surface.dimensions
            let w = Double(dims.x)
            let h = Double(dims.y)
            return [
                "width_m": r2(w), "height_m": r2(h),
                "width_ft": r2(w * metersToFeet), "height_ft": r2(h * metersToFeet)
            ]
        }

        let objectData = room.objects.map { object -> [String: Any] in
            let dims = object.dimensions
            let w = Double(dims.x)
            let d = Double(dims.y)
            let h = Double(dims.z)
            return [
                "category": cleanCategory(object.category),
                "width_m": r2(w), "depth_m": r2(d), "height_m": r2(h),
                "width_ft": r2(w * metersToFeet),
                "depth_ft": r2(d * metersToFeet),
                "height_ft": r2(h * metersToFeet)
            ]
        }

        let wallWidths = room.walls.map { Double($0.dimensions.x) }
        let longestWall = wallWidths.max() ?? 0
        let shortestWall = wallWidths.min() ?? 0

        var summary: [String: Any] = [
            "wall_count": room.walls.count,
            "door_count": room.doors.count,
            "window_count": room.windows.count,
            "object_count": room.objects.count,
            "ceiling_height_m": r2(ceilingHeight),
            "ceiling_height_ft": r2(ceilingHeight * metersToFeet),
            "estimated_floor_area_sqm": r2(floorArea),
            "estimated_floor_area_sqft": r2(floorArea * sqmToSqft),
            "total_wall_area_sqm": r2(totalWallArea),
            "total_wall_area_sqft": r2(totalWallArea * sqmToSqft),
            "volume_m3": r2(volume),
            "volume_ft3": r2(volume * metersToFeet * metersToFeet * metersToFeet),
            "longest_wall_m": r2(longestWall),
            "longest_wall_ft": r2(longestWall * metersToFeet),
            "shortest_wall_m": r2(shortestWall),
            "shortest_wall_ft": r2(shortestWall * metersToFeet),
            "room_shape": describeRoomShape(room.walls),
            "walls": wallData,
            "doors": doorData,
            "windows": windowData,
            "objects": objectData
        ]

        // Approximate room dimensions (bounding box)
        let dims = estimateRoomDimensions(room.walls)
        if let dims {
            summary["room_length_m"] = r2(dims.length)
            summary["room_width_m"] = r2(dims.width)
            summary["room_length_ft"] = r2(dims.length * metersToFeet)
            summary["room_width_ft"] = r2(dims.width * metersToFeet)
        }

        return summary
    }

    // MARK: - Metrics

    /// Ceiling height derived from the tallest wall surface.
    static func estimateCeilingHeight(_ walls: [CapturedRoom.Surface]) -> Double {
        walls.map { Double($0.dimensions.y) }.max() ?? 0
    }

    /// Floor area from wall positions using the shoelace formula.
    static func estimateFloorArea(_ walls: [CapturedRoom.Surface]) -> Double {
        guard walls.count >= 4 else {
            let perimeter = walls.reduce(0.0) { $0 + Double($1.dimensions.x) }
            let side = perimeter / 4.0
            return side * side
        }

        let points = walls.map { wall -> (Double, Double) in
            let col3 = wall.transform.columns.3
            return (Double(col3.x), Double(col3.z))
        }

        var area = 0.0
        for i in 0..<points.count {
            let j = (i + 1) % points.count
            area += points[i].0 * points[j].1
            area -= points[j].0 * points[i].1
        }
        return abs(area) / 2.0
    }

    /// Sum of individual wall areas (width x height).
    static func computeTotalWallArea(_ walls: [CapturedRoom.Surface]) -> Double {
        walls.reduce(0.0) { $0 + Double($1.dimensions.x) * Double($1.dimensions.y) }
    }

    /// Bounding-box room dimensions (length x width) from wall center positions.
    static func estimateRoomDimensions(_ walls: [CapturedRoom.Surface]) -> (length: Double, width: Double)? {
        guard walls.count >= 3 else { return nil }
        let xs = walls.map { Double($0.transform.columns.3.x) }
        let zs = walls.map { Double($0.transform.columns.3.z) }
        guard let minX = xs.min(), let maxX = xs.max(),
              let minZ = zs.min(), let maxZ = zs.max() else { return nil }
        let dx = maxX - minX
        let dz = maxZ - minZ
        return (length: max(dx, dz), width: min(dx, dz))
    }

    /// Describe room shape based on wall count and arrangement.
    static func describeRoomShape(_ walls: [CapturedRoom.Surface]) -> String {
        switch walls.count {
        case 0...2: return "partial"
        case 3: return "triangular"
        case 4: return "rectangular"
        case 5: return "pentagonal"
        case 6: return "L-shaped or hexagonal"
        default: return "irregular (\(walls.count) walls)"
        }
    }

    // MARK: - Encoding

    /// Encodes the full CapturedRoom to JSON via Codable.
    static func encodeFullRoom(_ room: CapturedRoom) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(room)
    }

    /// Encodes the summary dictionary to JSON Data.
    static func encodeSummary(_ summary: [String: Any]) throws -> Data {
        return try JSONSerialization.data(withJSONObject: summary, options: [.prettyPrinted, .sortedKeys])
    }

    // MARK: - Helpers

    /// Round to 2 decimal places.
    private static func r2(_ value: Double) -> Double {
        (value * 100).rounded() / 100
    }

    /// Clean verbose RoomPlan category names to simple labels.
    private static func cleanCategory(_ category: CapturedRoom.Object.Category) -> String {
        // String(describing:) gives e.g. "table" for known categories
        let raw = String(describing: category)
        // Strip any enum-style prefix if present
        if let dot = raw.lastIndex(of: ".") {
            return String(raw[raw.index(after: dot)...])
        }
        return raw
    }
}
