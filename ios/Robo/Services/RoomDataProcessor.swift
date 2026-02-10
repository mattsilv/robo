import Foundation
import RoomPlan

enum RoomDataProcessor {

    /// Creates an AI-friendly summary (~1KB) from a CapturedRoom.
    static func summarizeRoom(_ room: CapturedRoom) -> [String: Any] {
        let walls = room.walls.map { surface -> [String: Any] in
            let dims = surface.dimensions
            return [
                "width_m": round(dims.x * 100) / 100,
                "height_m": round(dims.y * 100) / 100
            ]
        }

        let doors = room.doors.map { surface -> [String: Any] in
            let dims = surface.dimensions
            return [
                "width_m": round(dims.x * 100) / 100,
                "height_m": round(dims.y * 100) / 100
            ]
        }

        let windows = room.windows.map { surface -> [String: Any] in
            let dims = surface.dimensions
            return [
                "width_m": round(dims.x * 100) / 100,
                "height_m": round(dims.y * 100) / 100
            ]
        }

        let objects = room.objects.map { object -> [String: Any] in
            let dims = object.dimensions
            return [
                "category": String(describing: object.category),
                "width_m": round(dims.x * 100) / 100,
                "depth_m": round(dims.y * 100) / 100,
                "height_m": round(dims.z * 100) / 100
            ]
        }

        let floorArea = estimateFloorArea(room.walls)

        return [
            "wall_count": room.walls.count,
            "door_count": room.doors.count,
            "window_count": room.windows.count,
            "object_count": room.objects.count,
            "estimated_floor_area_sqm": round(floorArea * 100) / 100,
            "walls": walls,
            "doors": doors,
            "windows": windows,
            "objects": objects
        ]
    }

    /// Estimates floor area from wall surfaces using perimeter approximation.
    static func estimateFloorArea(_ walls: [CapturedRoom.Surface]) -> Double {
        guard walls.count >= 4 else {
            // Fallback: sum of wall widths / 4 squared (assume square room)
            let perimeter = walls.reduce(0.0) { $0 + Double($1.dimensions.x) }
            let side = perimeter / 4.0
            return side * side
        }

        // Use wall positions to compute a polygon area via the shoelace formula
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
}
