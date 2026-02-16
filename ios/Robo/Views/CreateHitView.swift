import SwiftUI

enum HitDistributionMode: String, CaseIterable {
    case individual
    case group
    case open

    var label: String {
        switch self {
        case .individual: return "Individual"
        case .group: return "Group"
        case .open: return "Open"
        }
    }

    var description: String {
        switch self {
        case .individual: return "Separate link per person"
        case .group: return "One link, pick name from list"
        case .open: return "One link, anyone can respond"
        }
    }
}

struct CreateHitView: View {
    @Environment(APIService.self) private var apiService
    @Environment(\.dismiss) private var dismiss

    @State private var distributionMode: HitDistributionMode = .individual
    @State private var taskDescription = ""
    @State private var participantNames = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var createdHitURL: URL?
    @State private var createdHitURLs: [(name: String, url: URL)] = []

    private var participants: [String] {
        participantNames
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }

    private var isValid: Bool {
        let hasDescription = !taskDescription.trimmingCharacters(in: .whitespaces).isEmpty
        switch distributionMode {
        case .individual, .group:
            return hasDescription && !participants.isEmpty
        case .open:
            return hasDescription
        }
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Distribution", selection: $distributionMode) {
                        ForEach(HitDistributionMode.allCases, id: \.self) { mode in
                            Text(mode.label).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)

                    Text(distributionMode.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if distributionMode != .open {
                    Section("Participants") {
                        TextField("Names (comma-separated)", text: $participantNames)
                            .textContentType(.name)
                            .textInputAutocapitalization(.words)

                        if !participants.isEmpty {
                            Text("\(participants.count) participant\(participants.count == 1 ? "" : "s"): \(participants.joined(separator: ", "))")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Section("Task") {
                    TextField("What do you need from them?", text: $taskDescription, axis: .vertical)
                        .lineLimit(3...6)
                }

                Section {
                    Button {
                        Task { await createHit() }
                    } label: {
                        HStack {
                            Spacer()
                            if isLoading {
                                ProgressView()
                            } else {
                                Label("Generate Link\(distributionMode == .individual && participants.count > 1 ? "s" : "")", systemImage: "link.badge.plus")
                            }
                            Spacer()
                        }
                    }
                    .disabled(!isValid || isLoading)
                }

                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                            .font(.caption)
                    }
                }
            }
            .navigationTitle("Create HIT")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .sheet(item: $createdHitURL) { url in
                ShareSheet(activityItems: [url])
            }
        }
    }

    private func createHit() async {
        isLoading = true
        errorMessage = nil

        do {
            let result = try await apiService.createHitWithMode(
                distributionMode: distributionMode.rawValue,
                taskDescription: taskDescription.trimmingCharacters(in: .whitespaces),
                participants: distributionMode != .open ? participants : nil
            )

            // For individual mode, share the first URL (user can see all in list)
            if let urls = result.hits, let first = urls.first, let url = URL(string: first.url) {
                createdHitURL = url
            } else if let urlString = result.url, let url = URL(string: urlString) {
                createdHitURL = url
            }
        } catch {
            errorMessage = "Failed to create HIT: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

// ShareSheet and URL+Identifiable defined in SettingsView.swift
