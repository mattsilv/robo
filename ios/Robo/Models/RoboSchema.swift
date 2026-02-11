import Foundation
import SwiftData

// MARK: - Single Source of Truth for All Data Models
// All @Model classes live in this one file.
// Rules:
//   1. ALWAYS call `try modelContext.save()` after insert
//   2. New properties must be optional or have defaults
//   3. Run `scripts/validate-build.sh` before deploying

@Model
final class ScanRecord {
    var barcodeValue: String
    var symbology: String
    var capturedAt: Date

    init(barcodeValue: String, symbology: String) {
        self.barcodeValue = barcodeValue
        self.symbology = symbology
        self.capturedAt = Date()
    }
}

@Model
final class RoomScanRecord {
    var roomName: String
    var capturedAt: Date
    var wallCount: Int
    var floorAreaSqM: Double
    var ceilingHeightM: Double
    var objectCount: Int
    var summaryJSON: Data
    var fullRoomDataJSON: Data

    init(
        roomName: String,
        wallCount: Int,
        floorAreaSqM: Double,
        ceilingHeightM: Double = 0,
        objectCount: Int,
        summaryJSON: Data,
        fullRoomDataJSON: Data
    ) {
        self.roomName = roomName
        self.capturedAt = Date()
        self.wallCount = wallCount
        self.floorAreaSqM = floorAreaSqM
        self.ceilingHeightM = ceilingHeightM
        self.objectCount = objectCount
        self.summaryJSON = summaryJSON
        self.fullRoomDataJSON = fullRoomDataJSON
    }
}
