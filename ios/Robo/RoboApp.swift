import SwiftUI
import SwiftData

@main
struct RoboApp: App {
    @State private var deviceService = DeviceService()
    @State private var apiService: APIService

    let modelContainer: ModelContainer

    init() {
        let deviceService = DeviceService()
        _deviceService = State(initialValue: deviceService)
        _apiService = State(initialValue: APIService(deviceService: deviceService))

        // Try to create container; if the store is corrupt or schema changed,
        // delete the old store and retry rather than crashing.
        do {
            modelContainer = try ModelContainer(for: ScanRecord.self, RoomScanRecord.self)
        } catch {
            // Delete corrupt store and retry once
            let url = URL.applicationSupportDirectory
                .appending(path: "default.store")
            try? FileManager.default.removeItem(at: url)

            do {
                modelContainer = try ModelContainer(for: ScanRecord.self, RoomScanRecord.self)
            } catch {
                fatalError("Failed to initialize SwiftData after store reset: \(error)")
            }
        }
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
        .modelContainer(modelContainer)
    }
}
