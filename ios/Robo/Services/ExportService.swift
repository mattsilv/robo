import Foundation
import RoomPlan

struct ExportableScan: Sendable {
    let barcodeValue: String
    let symbology: String
    let capturedAt: Date
}

enum ExportService {
    /// Creates a ZIP file containing scans.json and scans.csv.
    static func createExportZip(scans: [ExportableScan]) throws -> URL {
        let fm = FileManager.default
        let exportDir = fm.temporaryDirectory
            .appendingPathComponent("robo-export-\(UUID().uuidString)")
        try fm.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        // Write scans.json
        let jsonRecords = scans.map { scan in
            [
                "value": scan.barcodeValue,
                "symbology": formatSymbology(scan.symbology),
                "scanned_at": formatter.string(from: scan.capturedAt)
            ]
        }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let jsonData = try encoder.encode(jsonRecords)
        try jsonData.write(to: exportDir.appendingPathComponent("scans.json"))

        // Write scans.csv
        var csv = "value,symbology,scanned_at\n"
        for scan in scans {
            let value = scan.barcodeValue.contains(",")
                ? "\"\(scan.barcodeValue)\""
                : scan.barcodeValue
            csv += "\(value),\(formatSymbology(scan.symbology)),\(formatter.string(from: scan.capturedAt))\n"
        }
        try csv.write(
            to: exportDir.appendingPathComponent("scans.csv"),
            atomically: true,
            encoding: .utf8
        )

        // ZIP using NSFileCoordinator (zero dependencies)
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let zipName = "robo-scans-\(dateFormatter.string(from: Date())).zip"
        let zipURL = fm.temporaryDirectory.appendingPathComponent(zipName)

        // Remove existing zip if present
        if fm.fileExists(atPath: zipURL.path) {
            try fm.removeItem(at: zipURL)
        }

        var coordinatorError: NSError?
        var moveError: Error?

        NSFileCoordinator().coordinate(
            readingItemAt: exportDir,
            options: [.forUploading],
            error: &coordinatorError
        ) { tempZipURL in
            do {
                try fm.copyItem(at: tempZipURL, to: zipURL)
            } catch {
                moveError = error
            }
        }

        // Clean up export directory
        try? fm.removeItem(at: exportDir)

        if let coordinatorError {
            throw coordinatorError
        }
        if let moveError {
            throw moveError
        }

        return zipURL
    }

    // MARK: - Room Export

    /// Creates a ZIP file containing room_summary.json and room_full.json.
    static func createRoomExportZip(room: ExportableRoom) throws -> URL {
        let fm = FileManager.default
        let exportDir = fm.temporaryDirectory
            .appendingPathComponent("robo-room-\(UUID().uuidString)")
        try fm.createDirectory(at: exportDir, withIntermediateDirectories: true)

        // Write room_summary.json
        let summaryData = try JSONSerialization.data(
            withJSONObject: room.summary,
            options: [.prettyPrinted, .sortedKeys]
        )
        try summaryData.write(to: exportDir.appendingPathComponent("room_summary.json"))

        // Write room_full.json
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let fullData = try encoder.encode(room.fullRoom)
        try fullData.write(to: exportDir.appendingPathComponent("room_full.json"))

        // ZIP
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let zipName = "robo-room-\(dateFormatter.string(from: Date())).zip"
        let zipURL = fm.temporaryDirectory.appendingPathComponent(zipName)

        if fm.fileExists(atPath: zipURL.path) {
            try fm.removeItem(at: zipURL)
        }

        var coordinatorError: NSError?
        var moveError: Error?

        NSFileCoordinator().coordinate(
            readingItemAt: exportDir,
            options: [.forUploading],
            error: &coordinatorError
        ) { tempZipURL in
            do {
                try fm.copyItem(at: tempZipURL, to: zipURL)
            } catch {
                moveError = error
            }
        }

        try? fm.removeItem(at: exportDir)

        if let coordinatorError {
            throw coordinatorError
        }
        if let moveError {
            throw moveError
        }

        return zipURL
    }

    /// Creates a ZIP from already-serialized room data (for exporting from history).
    static func createRoomExportZipFromData(
        roomName: String,
        summaryJSON: Data,
        fullRoomDataJSON: Data
    ) throws -> URL {
        let fm = FileManager.default
        let exportDir = fm.temporaryDirectory
            .appendingPathComponent("robo-room-\(UUID().uuidString)")
        try fm.createDirectory(at: exportDir, withIntermediateDirectories: true)

        try summaryJSON.write(to: exportDir.appendingPathComponent("room_summary.json"))
        try fullRoomDataJSON.write(to: exportDir.appendingPathComponent("room_full.json"))

        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let safeName = roomName.isEmpty ? "room" : roomName
            .replacingOccurrences(of: " ", with: "-")
            .lowercased()
        let zipName = "robo-\(safeName)-\(dateFormatter.string(from: Date())).zip"
        let zipURL = fm.temporaryDirectory.appendingPathComponent(zipName)

        if fm.fileExists(atPath: zipURL.path) {
            try fm.removeItem(at: zipURL)
        }

        var coordinatorError: NSError?
        var moveError: Error?

        NSFileCoordinator().coordinate(
            readingItemAt: exportDir,
            options: [.forUploading],
            error: &coordinatorError
        ) { tempZipURL in
            do {
                try fm.copyItem(at: tempZipURL, to: zipURL)
            } catch {
                moveError = error
            }
        }

        try? fm.removeItem(at: exportDir)

        if let coordinatorError { throw coordinatorError }
        if let moveError { throw moveError }

        return zipURL
    }

    // MARK: - Combined Export

    /// Creates a ZIP containing all barcodes and rooms in subdirectories.
    static func createCombinedExportZip(
        scans: [ExportableScan],
        rooms: [(name: String, summaryJSON: Data, fullRoomDataJSON: Data)]
    ) throws -> URL {
        let fm = FileManager.default
        let exportDir = fm.temporaryDirectory
            .appendingPathComponent("robo-combined-\(UUID().uuidString)")
        try fm.createDirectory(at: exportDir, withIntermediateDirectories: true)

        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]

        // Barcodes subdirectory
        if !scans.isEmpty {
            let barcodesDir = exportDir.appendingPathComponent("barcodes")
            try fm.createDirectory(at: barcodesDir, withIntermediateDirectories: true)

            let jsonRecords = scans.map { scan in
                [
                    "value": scan.barcodeValue,
                    "symbology": formatSymbology(scan.symbology),
                    "scanned_at": formatter.string(from: scan.capturedAt)
                ]
            }
            let encoder = JSONEncoder()
            encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            let jsonData = try encoder.encode(jsonRecords)
            try jsonData.write(to: barcodesDir.appendingPathComponent("scans.json"))

            var csv = "value,symbology,scanned_at\n"
            for scan in scans {
                let value = scan.barcodeValue.contains(",")
                    ? "\"\(scan.barcodeValue)\""
                    : scan.barcodeValue
                csv += "\(value),\(formatSymbology(scan.symbology)),\(formatter.string(from: scan.capturedAt))\n"
            }
            try csv.write(
                to: barcodesDir.appendingPathComponent("scans.csv"),
                atomically: true,
                encoding: .utf8
            )
        }

        // Rooms subdirectory
        if !rooms.isEmpty {
            let roomsDir = exportDir.appendingPathComponent("rooms")
            try fm.createDirectory(at: roomsDir, withIntermediateDirectories: true)

            var usedNames = Set<String>()
            for room in rooms {
                var safeName = room.name.isEmpty ? "room" : room.name
                    .replacingOccurrences(of: " ", with: "-")
                    .lowercased()

                // Handle duplicate names
                let baseName = safeName
                var counter = 2
                while usedNames.contains(safeName) {
                    safeName = "\(baseName)-\(counter)"
                    counter += 1
                }
                usedNames.insert(safeName)

                let roomDir = roomsDir.appendingPathComponent(safeName)
                try fm.createDirectory(at: roomDir, withIntermediateDirectories: true)
                try room.summaryJSON.write(to: roomDir.appendingPathComponent("room_summary.json"))
                try room.fullRoomDataJSON.write(to: roomDir.appendingPathComponent("room_full.json"))
            }
        }

        // ZIP
        let dateFormatter = DateFormatter()
        dateFormatter.dateFormat = "yyyy-MM-dd-HHmmss"
        let zipName = "robo-export-\(dateFormatter.string(from: Date())).zip"
        let zipURL = fm.temporaryDirectory.appendingPathComponent(zipName)

        if fm.fileExists(atPath: zipURL.path) {
            try fm.removeItem(at: zipURL)
        }

        var coordinatorError: NSError?
        var moveError: Error?

        NSFileCoordinator().coordinate(
            readingItemAt: exportDir,
            options: [.forUploading],
            error: &coordinatorError
        ) { tempZipURL in
            do {
                try fm.copyItem(at: tempZipURL, to: zipURL)
            } catch {
                moveError = error
            }
        }

        try? fm.removeItem(at: exportDir)

        if let coordinatorError { throw coordinatorError }
        if let moveError { throw moveError }

        return zipURL
    }

    private static func formatSymbology(_ raw: String) -> String {
        raw.replacingOccurrences(of: "VNBarcodeSymbology", with: "")
            .lowercased()
    }
}

struct ExportableRoom {
    let summary: [String: Any]
    let fullRoom: CapturedRoom
}
