import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(DeviceService.self) private var deviceService
    @Environment(APIService.self) private var apiService
    @AppStorage("scanQuality") private var scanQuality: String = "balanced"
    @State private var copiedDeviceID = false
    @State private var copiedMCPToken = false
    @State private var showingReRegisterConfirm = false
    @State private var isReRegistering = false
    #if DEBUG
    @AppStorage("dev.syncToCloud") private var debugSyncEnabled = false
    @Query(sort: \RoomScanRecord.capturedAt, order: .reverse) private var roomScans: [RoomScanRecord]
    @State private var fixtureExportURL: URL?
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section("Device") {
                    Button {
                        UIPasteboard.general.string = deviceService.config.id
                        copiedDeviceID = true
                        DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedDeviceID = false }
                    } label: {
                        LabeledContent("Device ID") {
                            HStack(spacing: 4) {
                                Text(deviceService.config.id)
                                    .foregroundStyle(.secondary)
                                Image(systemName: copiedDeviceID ? "checkmark" : "doc.on.doc")
                                    .foregroundStyle(copiedDeviceID ? .green : .accentColor)
                                    .font(.caption)
                            }
                        }
                    }
                    .tint(.primary)

                    LabeledContent("Device Name", value: deviceService.config.name)

                    if let token = deviceService.config.mcpToken {
                        Button {
                            UIPasteboard.general.string = token
                            copiedMCPToken = true
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { copiedMCPToken = false }
                        } label: {
                            LabeledContent("MCP Token") {
                                HStack(spacing: 4) {
                                    Text("••••\(String(token.suffix(4)))")
                                        .foregroundStyle(.secondary)
                                    Image(systemName: copiedMCPToken ? "checkmark" : "doc.on.doc")
                                        .foregroundStyle(copiedMCPToken ? .green : .accentColor)
                                        .font(.caption)
                                }
                            }
                        }
                        .tint(.primary)
                    } else {
                        LabeledContent("MCP Token") {
                            Text("Missing — re-register below")
                                .foregroundStyle(.orange)
                                .font(.caption)
                        }
                    }

                    Button {
                        showingReRegisterConfirm = true
                    } label: {
                        HStack {
                            Label("Re-register Device", systemImage: "arrow.triangle.2.circlepath")
                            if isReRegistering {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(isReRegistering)
                    .confirmationDialog(
                        "Re-register Device?",
                        isPresented: $showingReRegisterConfirm,
                        titleVisibility: .visible
                    ) {
                        Button("Re-register", role: .destructive) {
                            isReRegistering = true
                            Task {
                                await deviceService.reRegister(apiService: apiService)
                                isReRegistering = false
                            }
                        }
                    } message: {
                        Text("This creates a new device ID and MCP token. Previous scan history will not carry over.")
                    }
                }

                Section("Scanner") {
                    Picker("Scan Quality", selection: $scanQuality) {
                        Text("Fast").tag("fast")
                        Text("Balanced").tag("balanced")
                    }
                    .pickerStyle(.menu)
                }

                Section("Beacons") {
                    NavigationLink {
                        BeaconSettingsView()
                    } label: {
                        HStack {
                            Label("Beacon Configuration", systemImage: "sensor.tag.radiowaves.forward")
                            Spacer()
                            let beaconCount = BeaconConfigStore.loadBeacons().count
                            if beaconCount > 0 {
                                Text("\(beaconCount)")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }

                #if DEBUG
                Section("Developer") {
                    Toggle("Sync to Cloud", isOn: $debugSyncEnabled)
                    if debugSyncEnabled {
                        Text("Scan data uploads to debug endpoint after each save")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    if let latest = roomScans.first {
                        Button("Export Test Fixture") {
                            let tempURL = FileManager.default.temporaryDirectory
                                .appendingPathComponent("captured_room_fixture.json")
                            try? latest.fullRoomDataJSON.write(to: tempURL)
                            fixtureExportURL = tempURL
                        }
                        Text("\(latest.roomName) — \(ByteCountFormatter.string(fromByteCount: Int64(latest.fullRoomDataJSON.count), countStyle: .file))")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No room scans to export")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                #endif

                Section("About") {
                    LabeledContent("Version", value: "1.0 (M1)")
                    LabeledContent("Build", value: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—")

                    HStack {
                        Text("Built by")
                        Link("Matt Silverman", destination: URL(string: "https://silv.app")!)
                        Text("and")
                        Link("Claude Code", destination: URL(string: "https://claude.ai/code")!)
                    }
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                }
            }
            .navigationTitle("Settings")
            #if DEBUG
            .sheet(item: $fixtureExportURL) { url in
                ShareSheet(activityItems: [url])
            }
            #endif
        }
    }
}

#if DEBUG
extension URL: @retroactive Identifiable {
    public var id: String { absoluteString }
}

struct ShareSheet: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
#endif

#Preview {
    let deviceService = DeviceService()
    SettingsView()
        .environment(deviceService)
        .environment(APIService(deviceService: deviceService))
}
