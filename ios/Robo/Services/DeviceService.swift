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
    var registrationErrorDetail: String?

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
                self.registrationErrorDetail = nil
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
        self.registrationErrorDetail = buildErrorDetail(lastError, baseURL: config.apiBaseURL)
    }

    private func buildErrorDetail(_ error: Error?, baseURL: String) -> String {
        guard let error else { return "No error captured" }
        var lines = [
            "URL: \(baseURL)/api/devices/register",
            "Error type: \(type(of: error))",
            "Description: \(error.localizedDescription)",
        ]
        if let apiError = error as? APIError {
            switch apiError {
            case .httpError(let code, let message):
                lines.append("HTTP status: \(code)")
                lines.append("Response: \(String(message.prefix(500)))")
            case .requestFailed(let underlying):
                lines.append("Underlying: \(type(of: underlying)) — \(underlying.localizedDescription)")
                lines.append("Debug: \(String(describing: underlying))")
            case .decodingError(let underlying):
                lines.append("Decoding: \(underlying)")
            default:
                break
            }
        } else {
            lines.append("Raw: \(String(describing: error))")
        }
        lines.append("Time: \(ISO8601DateFormatter().string(from: Date()))")
        return lines.joined(separator: "\n")
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
        self.registrationError = nil
        self.registrationErrorDetail = nil
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
