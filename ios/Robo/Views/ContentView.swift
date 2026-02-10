import SwiftUI

struct ContentView: View {
    @Environment(DeviceService.self) private var deviceService
    @Environment(APIService.self) private var apiService

    @State private var selectedTab = 0
    @State private var showingSensorPicker = false

    var body: some View {
        TabView(selection: $selectedTab) {
            InboxView()
                .tabItem {
                    Label(AppStrings.Tabs.inbox, systemImage: "tray")
                }
                .tag(0)

            // Placeholder view — tap is intercepted to open sensor picker
            Text("")
                .tabItem {
                    Label(AppStrings.Tabs.gather, systemImage: "plus.circle.fill")
                }
                .tag(1)

            ScanHistoryView()
                .tabItem {
                    Label(AppStrings.Tabs.history, systemImage: "clock")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label(AppStrings.Tabs.settings, systemImage: "gearshape")
                }
                .tag(3)
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == 1 {
                showingSensorPicker = true
                // Snap back to previous tab so + never stays selected
                selectedTab = 2
            }
        }
        .sheet(isPresented: $showingSensorPicker) {
            SensorPickerView()
        }
    }
}

#Preview {
    ContentView()
        .environment(DeviceService())
        .environment(APIService(deviceService: DeviceService()))
        .modelContainer(for: [ScanRecord.self, RoomScanRecord.self], inMemory: true)
}
