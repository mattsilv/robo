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

        do {
            let schema = Schema(versionedSchema: RoboSchemaV3.self)
            let config = ModelConfiguration(schema: schema)
            modelContainer = try ModelContainer(
                for: schema,
                migrationPlan: RoboMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            fatalError("Failed to initialize SwiftData: \(error)")
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(deviceService)
                .environment(apiService)
                .task {
                    SummaryMigrationService.migrateIfNeeded(container: modelContainer)
                    await deviceService.bootstrap(apiService: apiService)
                }
        }
        .modelContainer(modelContainer)
    }
}
