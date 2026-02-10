import Foundation
import SwiftData

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
