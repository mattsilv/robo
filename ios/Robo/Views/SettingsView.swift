import SwiftUI

struct SettingsView: View {
    @Environment(DeviceService.self) private var deviceService
    @AppStorage("scanQuality") private var scanQuality: String = "balanced"
    @State private var apiURL: String = ""
    @State private var showingSaveConfirmation = false

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
        }
    }
}

#Preview {
    SettingsView()
        .environment(DeviceService())
}
