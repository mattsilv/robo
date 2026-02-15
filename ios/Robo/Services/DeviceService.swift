import Foundation
import UIKit

/// Protocol for device registration — enables testing without network.
protocol DeviceRegistering {
    func registerDevice(name: String) async throws -> DeviceConfig
}

extension APIService: DeviceRegistering {}

@Observable
class DeviceService {
    private let userDefaultsKey = "deviceConfig"
    var config: DeviceConfig
    var registrationError: String?

    init() {
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode(DeviceConfig.self, from: data) {
            self.config = saved
        } else {
            self.config = .default
            save()
        }
    }

    /// Testable initializer — skips UserDefaults.
    init(config: DeviceConfig) {
        self.config = config
    }

    var isRegistered: Bool { config.isRegistered }

    func bootstrap(apiService: DeviceRegistering) async {
        guard !isRegistered else { return }

        var lastError: Error?
        for attempt in 1...3 {
            do {
                let registered = try await apiService.registerDevice(name: UIDevice.current.name)
                self.config = registered
                self.registrationError = nil
                save()
                return
            } catch {
                lastError = error
                if attempt < 3 {
                    try? await Task.sleep(for: .seconds(Double(attempt) * 2))
                }
            }
        }

        self.registrationError = "Registration failed: \(lastError?.localizedDescription ?? "Unknown error")"
    }

    func save() {
        if let encoded = try? JSONEncoder().encode(config) {
            UserDefaults.standard.set(encoded, forKey: userDefaultsKey)
        }
    }

    func updateAPIBaseURL(_ url: String) {
        config.apiBaseURL = url
        save()
    }

    /// Clear local config and re-register to get a fresh device with MCP token.
    /// Use when the device was registered before auth existed.
    func reRegister(apiService: DeviceRegistering) async {
        let previousConfig = config
        let savedBaseURL = config.apiBaseURL
        config = DeviceConfig(
            id: DeviceConfig.unregisteredID,
            name: config.name,
            apiBaseURL: savedBaseURL
        )
        // Don't save yet — let bootstrap() save on success
        await bootstrap(apiService: apiService)

        // If bootstrap failed, restore previous config
        if !isRegistered {
            config = previousConfig
            save()
        }
    }
}
