import Foundation
import SwiftData

// MARK: - Schema V1 (initial release)
// All model definitions live here as the single source of truth.
// When you need to change a model, create V2 and add a migration stage.

enum RoboSchemaV1: VersionedSchema {
    static var versionIdentifier = Schema.Version(1, 0, 0)

    static var models: [any PersistentModel.Type] {
        [ScanRecord.self, RoomScanRecord.self]
    }

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
}

// MARK: - Schema V2 (motion sensor)

enum RoboSchemaV2: VersionedSchema {
    static var versionIdentifier = Schema.Version(2, 0, 0)

    static var models: [any PersistentModel.Type] {
        [ScanRecord.self, RoomScanRecord.self, MotionRecord.self]
    }

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

    @Model
    final class MotionRecord {
        var capturedAt: Date
        var stepCount: Int
        var distanceMeters: Double
        var floorsAscended: Int
        var floorsDescended: Int
        var activityJSON: Data

        init(
            stepCount: Int,
            distanceMeters: Double,
            floorsAscended: Int,
            floorsDescended: Int,
            activityJSON: Data
        ) {
            self.capturedAt = Date()
            self.stepCount = stepCount
            self.distanceMeters = distanceMeters
            self.floorsAscended = floorsAscended
            self.floorsDescended = floorsDescended
            self.activityJSON = activityJSON
        }
    }
}

// MARK: - Migration Plan

enum RoboMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [RoboSchemaV1.self, RoboSchemaV2.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: RoboSchemaV1.self,
        toVersion: RoboSchemaV2.self
    )
}

// MARK: - Type Aliases (so the rest of the app uses simple names)

typealias ScanRecord = RoboSchemaV2.ScanRecord
typealias RoomScanRecord = RoboSchemaV2.RoomScanRecord
typealias MotionRecord = RoboSchemaV2.MotionRecord
