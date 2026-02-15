import SwiftUI

struct ContentView: View {
    @Environment(DeviceService.self) private var deviceService
    @Environment(APIService.self) private var apiService

    @State private var selectedTab = 0
    @State private var deepLinkHitId: String?
    @State private var hitBadgeCount = 0

    var body: some View {
        TabView(selection: $selectedTab) {
            CaptureHomeView()
                .tabItem {
                    Label(AppStrings.Tabs.capture, systemImage: "sensor.fill")
                }
                .tag(0)

            ScanHistoryView()
                .tabItem {
                    Label(AppStrings.Tabs.history, systemImage: "archivebox")
                }
                .tag(1)

            HitListView(deepLinkHitId: $deepLinkHitId)
                .tabItem {
                    Label("HITs", systemImage: "link.badge.plus")
                }
                .tag(2)
                .badge(hitBadgeCount)

            ChatTabView()
                .tabItem {
                    Label(AppStrings.Tabs.chat, systemImage: "bubble.left.and.bubble.right")
                }
                .tag(3)

            SettingsView()
                .tabItem {
                    Label(AppStrings.Tabs.settings, systemImage: "gearshape")
                }
                .tag(4)
        }
        .onReceive(NotificationCenter.default.publisher(for: .hitCompletedNotification)) { notification in
            if let hitId = notification.userInfo?["hit_id"] as? String {
                deepLinkHitId = hitId
                selectedTab = 2
                hitBadgeCount = 0
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .hitResponseNotification)) { _ in
            if selectedTab != 2 {
                hitBadgeCount += 1
            }
        }
        .onChange(of: selectedTab) { _, newTab in
            if newTab == 2 { hitBadgeCount = 0 }
        }
    }
}

#Preview {
    ContentView()
        .environment(DeviceService())
        .environment(APIService(deviceService: DeviceService()))
        .modelContainer(for: [ScanRecord.self, RoomScanRecord.self], inMemory: true)
}
