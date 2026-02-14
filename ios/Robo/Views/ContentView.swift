import SwiftUI

struct ContentView: View {
    @Environment(DeviceService.self) private var deviceService
    @Environment(APIService.self) private var apiService

    var body: some View {
        TabView {
            CaptureHomeView()
                .tabItem {
                    Label(AppStrings.Tabs.capture, systemImage: "sensor.fill")
                }

            ScanHistoryView()
                .tabItem {
                    Label(AppStrings.Tabs.history, systemImage: "archivebox")
                }

            ChatTabView()
                .tabItem {
                    Label(AppStrings.Tabs.chat, systemImage: "bubble.left.and.bubble.right")
                }

            SettingsView()
                .tabItem {
                    Label(AppStrings.Tabs.settings, systemImage: "gearshape")
                }
        }
    }
}

#Preview {
    ContentView()
        .environment(DeviceService())
        .environment(APIService(deviceService: DeviceService()))
        .modelContainer(for: [ScanRecord.self, RoomScanRecord.self], inMemory: true)
}
