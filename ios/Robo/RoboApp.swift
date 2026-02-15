import SwiftUI
import SwiftData
import UserNotifications
import os

private let logger = Logger(subsystem: "com.silv.Robo", category: "AppInit")

@main
struct RoboApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @State private var deviceService = DeviceService()
    @State private var apiService: APIService

    let modelContainer: ModelContainer

    init() {
        let deviceService = DeviceService()
        _deviceService = State(initialValue: deviceService)
        _apiService = State(initialValue: APIService(deviceService: deviceService))

        modelContainer = Self.createResilientContainer()
    }

    /// Attempts to create a ModelContainer with migration, falling back to a
    /// backup-and-recreate strategy. NEVER deletes the store without backing up first.
    private static func createResilientContainer() -> ModelContainer {
        let schema = Schema(versionedSchema: RoboSchemaV9.self)
        let config = ModelConfiguration(schema: schema)

        // Attempt 1: Normal migration
        do {
            return try ModelContainer(
                for: schema,
                migrationPlan: RoboMigrationPlan.self,
                configurations: [config]
            )
        } catch {
            logger.error("Migration failed: \(error.localizedDescription)")
        }

        // Attempt 2: Retry without migration plan (handles corrupted migration state)
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            logger.error("Retry without migration failed: \(error.localizedDescription)")
        }

        // Attempt 3: Backup the store, then create fresh
        let storeURL = config.url
        let backupURL = storeURL.deletingLastPathComponent()
            .appendingPathComponent("default.store.backup-\(Int(Date().timeIntervalSince1970))")
        do {
            if FileManager.default.fileExists(atPath: storeURL.path) {
                try FileManager.default.copyItem(at: storeURL, to: backupURL)
                // Also backup WAL/SHM sidecars for complete recovery
                for suffix in ["-wal", "-shm"] {
                    let sidecar = URL(fileURLWithPath: storeURL.path + suffix)
                    let sidecarBackup = URL(fileURLWithPath: backupURL.path + suffix)
                    try? FileManager.default.copyItem(at: sidecar, to: sidecarBackup)
                }
                logger.warning("Backed up corrupt store to \(backupURL.lastPathComponent)")
                // Remove originals only AFTER successful backup
                try FileManager.default.removeItem(at: storeURL)
                for suffix in ["-wal", "-shm"] {
                    let sidecar = URL(fileURLWithPath: storeURL.path + suffix)
                    try? FileManager.default.removeItem(at: sidecar)
                }
            }
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            // Last resort: truly unrecoverable — crash with context
            fatalError(
                "SwiftData unrecoverable after backup+recreate. "
                + "Backup at: \(backupURL.path). Error: \(error)"
            )
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(deviceService)
                .environment(apiService)
                .modifier(CaptureCoordinatorModifier())
                .task {
                    SummaryMigrationService.migrateIfNeeded(container: modelContainer)
                    await deviceService.bootstrap(apiService: apiService)

                    // Wire AppDelegate to services for push token registration
                    appDelegate.apiService = apiService
                    appDelegate.deviceService = deviceService

                    // Request push notification permission
                    await requestPushPermission()
                }
        }
        .modelContainer(modelContainer)
    }

    private func requestPushPermission() async {
        do {
            let center = UNUserNotificationCenter.current()
            let granted = try await center.requestAuthorization(options: [.alert, .sound, .badge])
            if granted {
                await MainActor.run {
                    UIApplication.shared.registerForRemoteNotifications()
                }
                logger.info("Push notification permission granted")
            } else {
                logger.info("Push notification permission denied")
            }
        } catch {
            logger.error("Push permission request failed: \(error.localizedDescription)")
        }
    }
}
