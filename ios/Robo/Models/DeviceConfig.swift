import Foundation
import UIKit

struct DeviceConfig: Codable {
    let id: String
    let name: String
    var apiBaseURL: String

    static let `default` = DeviceConfig(
        id: UUID().uuidString,
        name: UIDevice.current.name,
        apiBaseURL: "https://robo-api.silv.workers.dev"
    )
}
