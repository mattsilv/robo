import Foundation

@Observable
class DeviceService {
    private let userDefaultsKey = "deviceConfig"
    var config: DeviceConfig

    init() {
        // Load from UserDefaults or use default
        if let data = UserDefaults.standard.data(forKey: userDefaultsKey),
           let saved = try? JSONDecoder().decode(DeviceConfig.self, from: data) {
            self.config = saved
        } else {
            self.config = .default
            save()
        }
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
