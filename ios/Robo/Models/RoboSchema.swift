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

// MARK: - Schema V3 (nutrition data on barcodes)

enum RoboSchemaV3: VersionedSchema {
    static var versionIdentifier = Schema.Version(3, 0, 0)

    static var models: [any PersistentModel.Type] {
        [ScanRecord.self, RoomScanRecord.self, MotionRecord.self]
    }

    @Model
    final class ScanRecord {
        var barcodeValue: String
        var symbology: String
        var capturedAt: Date

        // Nutrition fields (all optional for lightweight migration)
        var foodName: String?
        var brandName: String?
        var calories: Double?
        var protein: Double?
        var totalFat: Double?
        var totalCarbs: Double?
        var dietaryFiber: Double?
        var sugars: Double?
        var sodium: Double?
        var servingQty: Double?
        var servingUnit: String?
        var servingWeightGrams: Double?
        var photoThumbURL: String?
        var photoHighresURL: String?
        var nutritionJSON: Data?
        var nutritionLookedUp: Bool = false

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

// MARK: - Schema V4 (agent linkage)

enum RoboSchemaV4: VersionedSchema {
    static var versionIdentifier = Schema.Version(4, 0, 0)

    static var models: [any PersistentModel.Type] {
        [ScanRecord.self, RoomScanRecord.self, MotionRecord.self]
    }

    @Model
    final class ScanRecord {
        var barcodeValue: String
        var symbology: String
        var capturedAt: Date

        // Nutrition fields
        var foodName: String?
        var brandName: String?
        var calories: Double?
        var protein: Double?
        var totalFat: Double?
        var totalCarbs: Double?
        var dietaryFiber: Double?
        var sugars: Double?
        var sodium: Double?
        var servingQty: Double?
        var servingUnit: String?
        var servingWeightGrams: Double?
        var photoThumbURL: String?
        var photoHighresURL: String?
        var nutritionJSON: Data?
        var nutritionLookedUp: Bool = false

        // Agent linkage (V4)
        var agentId: String?
        var agentName: String?

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

        // Agent linkage (V4)
        var agentId: String?
        var agentName: String?

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

        // Agent linkage (V4)
        var agentId: String?
        var agentName: String?

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

// MARK: - Schema V5 (agent completion records)

enum RoboSchemaV5: VersionedSchema {
    static var versionIdentifier = Schema.Version(5, 0, 0)

    static var models: [any PersistentModel.Type] {
        [ScanRecord.self, RoomScanRecord.self, MotionRecord.self, AgentCompletionRecord.self]
    }

    // Re-export V4 models unchanged
    typealias ScanRecord = RoboSchemaV4.ScanRecord
    typealias RoomScanRecord = RoboSchemaV4.RoomScanRecord
    typealias MotionRecord = RoboSchemaV4.MotionRecord

    @Model
    final class AgentCompletionRecord {
        var agentId: String
        var agentName: String
        var requestId: String
        var skillType: String
        var itemCount: Int
        var completedAt: Date

        init(
            agentId: String,
            agentName: String,
            requestId: String,
            skillType: String,
            itemCount: Int
        ) {
            self.agentId = agentId
            self.agentName = agentName
            self.requestId = requestId
            self.skillType = skillType
            self.itemCount = itemCount
            self.completedAt = Date()
        }
    }
}

// MARK: - Schema V6 (product capture with photos)

enum RoboSchemaV6: VersionedSchema {
    static var versionIdentifier = Schema.Version(6, 0, 0)

    static var models: [any PersistentModel.Type] {
        [ScanRecord.self, RoomScanRecord.self, MotionRecord.self,
         AgentCompletionRecord.self, ProductCaptureRecord.self]
    }

    // Re-export V5 models unchanged
    typealias ScanRecord = RoboSchemaV4.ScanRecord
    typealias RoomScanRecord = RoboSchemaV4.RoomScanRecord
    typealias MotionRecord = RoboSchemaV4.MotionRecord
    typealias AgentCompletionRecord = RoboSchemaV5.AgentCompletionRecord

    @Model
    final class ProductCaptureRecord {
        var id: UUID
        var barcodeValue: String?
        var symbology: String?
        var photoFileNamesJSON: String
        var photoCount: Int
        var capturedAt: Date
        var agentId: String?
        var agentName: String?
        var requestId: String?
        var foodName: String?
        var brandName: String?
        var calories: Double?
        var photoThumbURL: String?
        var nutritionLookedUp: Bool

        init(
            barcodeValue: String? = nil,
            symbology: String? = nil,
            photoFileNames: [String],
            agentId: String? = nil,
            agentName: String? = nil,
            requestId: String? = nil
        ) {
            self.id = UUID()
            self.barcodeValue = barcodeValue
            self.symbology = symbology
            self.photoFileNamesJSON = (try? JSONEncoder().encode(photoFileNames))
                .flatMap { String(data: $0, encoding: .utf8) } ?? "[]"
            self.photoCount = photoFileNames.count
            self.capturedAt = Date()
            self.agentId = agentId
            self.agentName = agentName
            self.requestId = requestId
            self.nutritionLookedUp = false
        }

        var photoFileNames: [String] {
            guard let data = photoFileNamesJSON.data(using: .utf8) else { return [] }
            return (try? JSONDecoder().decode([String].self, from: data)) ?? []
        }
    }
}

// MARK: - Migration Plan

enum RoboMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [RoboSchemaV1.self, RoboSchemaV2.self, RoboSchemaV3.self,
         RoboSchemaV4.self, RoboSchemaV5.self, RoboSchemaV6.self]
    }

    static var stages: [MigrationStage] {
        [migrateV1toV2, migrateV2toV3, migrateV3toV4, migrateV4toV5, migrateV5toV6]
    }

    static let migrateV1toV2 = MigrationStage.lightweight(
        fromVersion: RoboSchemaV1.self,
        toVersion: RoboSchemaV2.self
    )

    static let migrateV2toV3 = MigrationStage.lightweight(
        fromVersion: RoboSchemaV2.self,
        toVersion: RoboSchemaV3.self
    )

    static let migrateV3toV4 = MigrationStage.lightweight(
        fromVersion: RoboSchemaV3.self,
        toVersion: RoboSchemaV4.self
    )

    static let migrateV4toV5 = MigrationStage.lightweight(
        fromVersion: RoboSchemaV4.self,
        toVersion: RoboSchemaV5.self
    )

    static let migrateV5toV6 = MigrationStage.lightweight(
        fromVersion: RoboSchemaV5.self,
        toVersion: RoboSchemaV6.self
    )
}

// MARK: - Type Aliases (so the rest of the app uses simple names)

typealias ScanRecord = RoboSchemaV6.ScanRecord
typealias RoomScanRecord = RoboSchemaV6.RoomScanRecord
typealias MotionRecord = RoboSchemaV6.MotionRecord
typealias AgentCompletionRecord = RoboSchemaV6.AgentCompletionRecord
typealias ProductCaptureRecord = RoboSchemaV6.ProductCaptureRecord
