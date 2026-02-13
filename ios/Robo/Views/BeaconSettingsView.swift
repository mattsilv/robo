import SwiftUI
import CoreLocation

struct BeaconSettingsView: View {
    @State private var beacons: [BeaconConfigStore.BeaconConfig] = BeaconConfigStore.loadBeacons()
    @State private var webhookURL: String = UserDefaults.standard.string(forKey: "beaconWebhookURL") ?? ""
    @State private var webhookSecret: String = UserDefaults.standard.string(forKey: "beaconWebhookSecret") ?? ""
    @State private var showingAddBeacon = false
    @State private var showingDeviceInfo = false
    @State private var testWebhookResult: String?
    @State private var isTesting = false

    @Environment(DeviceService.self) private var deviceService

    var body: some View {
        Form {
            // Configured Beacons
            Section {
                if beacons.isEmpty {
                    HStack {
                        Spacer()
                        VStack(spacing: 8) {
                            Image(systemName: "sensor.tag.radiowaves.forward")
                                .font(.title)
                                .foregroundStyle(.secondary)
                            Text("No beacons configured")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 8)
                } else {
                    ForEach(beacons) { beacon in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(beacon.roomName)
                                    .font(.subheadline.weight(.medium))
                                Text("Minor: \(beacon.minor)")
                                    .font(.caption.monospaced())
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Toggle("", isOn: Binding(
                                get: { beacon.isActive },
                                set: { newValue in
                                    BeaconConfigStore.updateBeacon(id: beacon.id, isActive: newValue)
                                    beacons = BeaconConfigStore.loadBeacons()
                                }
                            ))
                            .labelsHidden()
                        }
                    }
                    .onDelete(perform: deleteBeacons)
                }

                Button {
                    showingAddBeacon = true
                } label: {
                    Label("Add Beacon", systemImage: "plus.circle")
                }
            } header: {
                Text("Beacons")
            } footer: {
                Text("Assign room names to beacon Minor values. Beacons use iBeacon UUID: FDA50693-...")
            }

            // Webhook Configuration
            Section {
                TextField("Webhook URL", text: $webhookURL)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .onChange(of: webhookURL) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "beaconWebhookURL")
                    }

                TextField("Webhook Secret (optional)", text: $webhookSecret)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .onChange(of: webhookSecret) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "beaconWebhookSecret")
                    }

                Button {
                    testWebhook()
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.8)
                                .padding(.trailing, 4)
                        }
                        Text("Test Webhook")
                    }
                }
                .disabled(webhookURL.isEmpty || isTesting)

                if let result = testWebhookResult {
                    Text(result)
                        .font(.caption)
                        .foregroundStyle(result.contains("Success") ? .green : .red)
                }
            } header: {
                Text("Webhook")
            } footer: {
                Text("Enter/exit events will POST to this URL. Optionally sign payloads with HMAC-SHA256.")
            }

            // Supported Devices
            Section {
                Button {
                    showingDeviceInfo = true
                } label: {
                    Label("Supported Beacon Devices", systemImage: "info.circle")
                }
            }
        }
        .navigationTitle("Beacons")
        .sheet(isPresented: $showingAddBeacon) {
            AddBeaconSheet(onAdd: { minor, name in
                BeaconConfigStore.addBeacon(minor: minor, roomName: name)
                beacons = BeaconConfigStore.loadBeacons()
            })
        }
        .sheet(isPresented: $showingDeviceInfo) {
            SupportedDevicesSheet()
        }
    }

    private func deleteBeacons(at offsets: IndexSet) {
        for index in offsets {
            BeaconConfigStore.removeBeacon(id: beacons[index].id)
        }
        beacons = BeaconConfigStore.loadBeacons()
    }

    private func testWebhook() {
        guard let url = URL(string: webhookURL) else {
            testWebhookResult = "Invalid URL"
            return
        }

        isTesting = true
        testWebhookResult = nil

        let formatter = ISO8601DateFormatter()
        let payload = BeaconWebhookPayload(
            event: "test",
            beaconMinor: 0,
            roomName: "Test",
            proximity: "near",
            rssi: -50,
            distanceMeters: 2.0,
            durationSeconds: nil,
            timestamp: formatter.string(from: Date()),
            deviceId: deviceService.config.id,
            source: "test"
        )

        Task {
            let secret = webhookSecret.isEmpty ? nil : webhookSecret
            let result = await WebhookService.send(payload: payload, to: url, secret: secret)
            await MainActor.run {
                isTesting = false
                switch result {
                case .success(let code):
                    testWebhookResult = "Success (\(code))"
                case .failure(let error):
                    testWebhookResult = "Failed: \(error.localizedDescription)"
                }
            }
        }
    }
}

// MARK: - Add Beacon Sheet

private struct AddBeaconSheet: View {
    let onAdd: (Int, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var minorText = ""
    @State private var roomName = ""

    // For scanning nearby beacons
    @State private var beaconService = BeaconService()
    @State private var isScanning = false

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Room Name", text: $roomName)
                    TextField("Minor Value (1-65535)", text: $minorText)
                        .keyboardType(.numberPad)
                } header: {
                    Text("Manual Entry")
                }

                Section {
                    if isScanning {
                        if beaconService.detectedBeacons.isEmpty {
                            HStack(spacing: 12) {
                                ProgressView()
                                Text("Scanning for beacons...")
                                    .foregroundStyle(.secondary)
                            }
                        } else {
                            ForEach(beaconService.detectedBeacons, id: \.minor) { beacon in
                                Button {
                                    minorText = "\(beacon.minor)"
                                    if roomName.isEmpty {
                                        roomName = "Room \(beacon.minor)"
                                    }
                                } label: {
                                    HStack {
                                        VStack(alignment: .leading) {
                                            Text("Minor: \(beacon.minor)")
                                                .font(.subheadline.monospaced())
                                            Text("RSSI: \(beacon.rssi)")
                                                .font(.caption)
                                                .foregroundStyle(.secondary)
                                        }
                                        Spacer()
                                        if minorText == "\(beacon.minor)" {
                                            Image(systemName: "checkmark.circle.fill")
                                                .foregroundStyle(.green)
                                        }
                                    }
                                }
                                .foregroundStyle(.primary)
                            }
                        }
                    } else {
                        Button("Scan for Nearby Beacons") {
                            beaconService.requestPermissions()
                            beaconService.startMonitoring()
                            isScanning = true
                        }
                    }
                } header: {
                    Text("Or Discover")
                }
            }
            .navigationTitle("Add Beacon")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        beaconService.stopMonitoring()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        guard let minor = Int(minorText), minor >= 1, minor <= 65535 else { return }
                        beaconService.stopMonitoring()
                        onAdd(minor, roomName.isEmpty ? "Room \(minor)" : roomName)
                        dismiss()
                    }
                    .disabled(minorText.isEmpty || Int(minorText) == nil)
                }
            }
        }
    }
}
