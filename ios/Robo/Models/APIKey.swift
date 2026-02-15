import Foundation

/// Metadata returned by GET /api/keys (key_value is masked server-side)
struct APIKeyMeta: Codable, Identifiable {
    let id: String
    let keyHint: String
    let label: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, label
        case keyHint = "key_hint"
        case createdAt = "created_at"
    }
}

/// Full key returned only on POST /api/keys (one-time visible)
struct APIKeyCreated: Decodable {
    let id: String
    let keyValue: String
    let label: String?
    let createdAt: String

    enum CodingKeys: String, CodingKey {
        case id, label
        case keyValue = "key_value"
        case createdAt = "created_at"
    }
}

struct APIKeyListResponse: Decodable {
    let keys: [APIKeyMeta]
    let count: Int
}
