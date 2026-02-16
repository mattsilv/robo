import Foundation
import Security

/// Reads DeviceConfig from the shared App Group keychain.
/// Mirrors KeychainHelper but only needs read access.
enum SharedKeychainHelper {
    private static let service = "com.silv.Robo"
    private static let account = "deviceConfig"
    private static let accessGroup = "R3Z5CY34Q5.group.com.silv.Robo"

    static func load() -> SharedDeviceConfig? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]

        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return try? JSONDecoder().decode(SharedDeviceConfig.self, from: data)
    }
}

/// Minimal subset of DeviceConfig needed by the share extension.
struct SharedDeviceConfig: Codable {
    var id: String
    var apiBaseURL: String
}
