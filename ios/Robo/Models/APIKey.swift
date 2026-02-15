import Foundation

struct APIKey: Codable, Identifiable {
    let id: String
    let keyValue: String
    let label: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, label
        case keyValue = "key_value"
        case createdAt = "created_at"
    }

    var maskedValue: String {
        let suffix = String(keyValue.suffix(4))
        return "robo_••••\(suffix)"
    }
}

struct APIKeyListResponse: Decodable {
    let keys: [APIKey]
    let count: Int
}
