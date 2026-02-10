import Foundation

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

    private static func formatSymbology(_ raw: String) -> String {
        raw.replacingOccurrences(of: "VNBarcodeSymbology", with: "")
            .lowercased()
    }
}
