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
    @State private var mcpStatus: MCPConnectionStatus = .unknown
    @State private var pollingTask: Task<Void, Never>?
    #if DEBUG
    @AppStorage("dev.syncToCloud") private var debugSyncEnabled = false
    @Query(sort: \RoomScanRecord.capturedAt, order: .reverse) private var roomScans: [RoomScanRecord]
    @State private var fixtureExportURL: URL?
    #endif

    var body: some View {
        NavigationStack {
            Form {
                Section("My Mobile Device") {
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

                    HStack {
                        Text("MCP Status")
                        Spacer()
                        HStack(spacing: 6) {
                            Circle()
                                .fill(mcpStatus.color)
                                .frame(width: 8, height: 8)
                            Text(mcpStatus.label)
                                .foregroundStyle(.secondary)
                        }
                    }

                    Text("Updates when Claude Code uses MCP tools")
                        .font(.caption)
                        .foregroundStyle(.tertiary)

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

                    if let error = deviceService.registrationError {
                        Text(error)
                            .foregroundStyle(.red)
                            .font(.caption)

                        if let detail = deviceService.registrationErrorDetail {
                            Button {
                                UIPasteboard.general.string = detail
                            } label: {
                                Label("Copy Error Details", systemImage: "doc.on.clipboard")
                                    .font(.caption)
                            }
                        }
                    }
                }

                Section("Barcode Scanner") {
                    Picker("Scan Quality", selection: $scanQuality) {
                        Text("Fast").tag("fast")
                        Text("Balanced").tag("balanced")
                    }
                    .pickerStyle(.menu)
                }

                Section("Bluetooth Beacons") {
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
                    LabeledContent("Build", value: Self.buildString)

                    Link(destination: URL(string: "https://www.robo.app")!) {
                        HStack {
                            Label("Website", systemImage: "globe")
                            Spacer()
                            Text("robo.app")
                                .foregroundStyle(.secondary)
                        }
                    }

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
            .onAppear {
                startPolling()
            }
            .onDisappear {
                pollingTask?.cancel()
            }
            #if DEBUG
            .sheet(item: $fixtureExportURL) { url in
                ShareSheet(activityItems: [url])
            }
            #endif
        }
    }

    static var buildString: String {
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"
        #if DEBUG
        return "\(build)-debug"
        #else
        if Bundle.main.appStoreReceiptURL?.lastPathComponent == "sandboxReceipt" {
            return "\(build)-testflight"
        }
        return "\(build)-release"
        #endif
    }
}

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

// MARK: - MCP Status Polling

extension SettingsView {
    func startPolling() {
        pollingTask?.cancel()
        pollingTask = Task {
            while !Task.isCancelled {
                await pollMCPStatus()
                try? await Task.sleep(for: .seconds(30))
            }
        }
    }

    func pollMCPStatus() async {
        do {
            let device = try await apiService.fetchDevice()
            if let lastCall = device.lastMcpCallAt {
                let formatter = ISO8601DateFormatter()
                if let date = formatter.date(from: lastCall) {
                    let elapsed = Date().timeIntervalSince(date)
                    if elapsed < 60 {
                        mcpStatus = .connected
                    } else if elapsed < 300 {
                        mcpStatus = .recent
                    } else {
                        mcpStatus = .notConnected
                    }
                } else {
                    mcpStatus = .notConnected
                }
            } else {
                mcpStatus = .notConnected
            }
        } catch {
            // Keep last known state on network failure
        }
    }
}

// MARK: - MCP Connection Status

enum MCPConnectionStatus {
    case connected
    case recent
    case notConnected
    case unknown

    var label: String {
        switch self {
        case .connected: "Connected"
        case .recent: "Recent"
        case .notConnected: "Not connected"
        case .unknown: "Not connected"
        }
    }

    var color: Color {
        switch self {
        case .connected: .green
        case .recent: .yellow
        case .notConnected: .gray
        case .unknown: .gray
        }
    }
}

#Preview {
    let deviceService = DeviceService()
    SettingsView()
        .environment(deviceService)
        .environment(APIService(deviceService: deviceService))
}
