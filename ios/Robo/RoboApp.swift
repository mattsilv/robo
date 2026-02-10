import SwiftUI

@main
struct RoboApp: App {
    @State private var deviceService = DeviceService()
    @State private var apiService: APIService

    init() {
        let deviceService = DeviceService()
        _deviceService = State(initialValue: deviceService)
        _apiService = State(initialValue: APIService(deviceService: deviceService))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(deviceService)
                .environment(apiService)
                .task {
                    await deviceService.bootstrap(apiService: apiService)
                }
        }
    }
}
