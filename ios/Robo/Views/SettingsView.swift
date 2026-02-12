import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(DeviceService.self) private var deviceService
    @AppStorage("scanQuality") private var scanQuality: String = "balanced"
    @State private var apiURL: String = ""
    @State private var showingSaveConfirmation = false
    #if DEBUG
    @AppStorage("dev.syncToCloud") private var debugSyncEnabled = false
    @Query(sort: \RoomScanRecord.capturedAt, order: .reverse) private var roomScans: [RoomScanRecord]
    @State private var fixtureExportURL: URL?
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section("Device") {
                    LabeledContent("Device ID", value: deviceService.config.id)
                    LabeledContent("Device Name", value: deviceService.config.name)
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

                Section("API Configuration") {
                    TextField("API Base URL", text: $apiURL)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)

                    Button("Save") {
                        deviceService.updateAPIBaseURL(apiURL)
                        showingSaveConfirmation = true
                    }
                    .disabled(apiURL == deviceService.config.apiBaseURL)
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
            .alert("Saved", isPresented: $showingSaveConfirmation) {
                Button("OK", role: .cancel) {}
            } message: {
                Text("API URL updated successfully")
            }
            .onAppear {
                apiURL = deviceService.config.apiBaseURL
            }
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
    SettingsView()
        .environment(DeviceService())
}
