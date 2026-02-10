import Foundation
import SwiftData

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
