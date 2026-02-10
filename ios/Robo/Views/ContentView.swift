import SwiftUI

struct ContentView: View {
    @Environment(DeviceService.self) private var deviceService
    @Environment(APIService.self) private var apiService

    @State private var selectedTab = 0
    @State private var showingScanner = false

    var body: some View {
        TabView(selection: $selectedTab) {
            InboxView()
                .tabItem {
                    Label("Inbox", systemImage: "tray")
                }
                .tag(0)

            // Placeholder view — tap is intercepted to open scanner
            Text("")
                .tabItem {
                    Label("Create", systemImage: "plus.circle.fill")
                }
                .tag(1)

            ScanHistoryView()
                .tabItem {
                    Label("History", systemImage: "clock")
                }
                .tag(2)

            SettingsView()
                .tabItem {
                    Label("Settings", systemImage: "gearshape")
                }
                .tag(3)
        }
        .onChange(of: selectedTab) { _, newValue in
            if newValue == 1 {
                showingScanner = true
                // Snap back to previous tab so + never stays selected
                selectedTab = 2
            }
        }
        .fullScreenCover(isPresented: $showingScanner) {
            BarcodeScannerView()
        }
    }
}

#Preview {
    ContentView()
        .environment(DeviceService())
        .environment(APIService(deviceService: DeviceService()))
        .modelContainer(for: ScanRecord.self, inMemory: true)
}
