import Foundation
import UIKit

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

    var isRegistered: Bool { config.isRegistered }

    func bootstrap(apiService: APIService) async {
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
}
