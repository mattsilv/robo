import SwiftUI

struct ContentView: View {
    @Environment(DeviceService.self) private var deviceService
    @Environment(APIService.self) private var apiService

    var body: some View {
        TabView {
            AgentsView()
                .tabItem {
                    Label(AppStrings.Tabs.agents, systemImage: "tray.fill")
                }

            ScanHistoryView()
                .tabItem {
                    Label(AppStrings.Tabs.history, systemImage: "archivebox")
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
