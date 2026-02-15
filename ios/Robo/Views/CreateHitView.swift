import SwiftUI

struct CreateHitView: View {
    @Environment(APIService.self) private var apiService
    @Environment(\.dismiss) private var dismiss

    @State private var recipientName = ""
    @State private var taskDescription = ""
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var createdHitURL: URL?

    private var isValid: Bool {
        !recipientName.trimmingCharacters(in: .whitespaces).isEmpty
        && !taskDescription.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section("Recipient") {
                    TextField("Name (e.g. Sarah, Mom)", text: $recipientName)
                        .textContentType(.name)
                        .textInputAutocapitalization(.words)
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
                                Label("Generate Link", systemImage: "link.badge.plus")
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
            let hit = try await apiService.createHit(
                recipientName: recipientName.trimmingCharacters(in: .whitespaces),
                taskDescription: taskDescription.trimmingCharacters(in: .whitespaces)
            )
            if let url = URL(string: hit.url) {
                createdHitURL = url
            }
        } catch {
            errorMessage = "Failed to create HIT: \(error.localizedDescription)"
        }

        isLoading = false
    }
}

// ShareSheet and URL+Identifiable defined in SettingsView.swift
