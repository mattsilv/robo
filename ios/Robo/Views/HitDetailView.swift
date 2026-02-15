import SwiftUI

struct HitDetailView: View {
    @Environment(APIService.self) private var apiService

    let hitId: String

    @State private var hit: HitSummary?
    @State private var photos: [HitPhotoItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if let hit {
                List {
                    Section("Details") {
                        LabeledContent("Recipient", value: hit.recipientName)
                        LabeledContent("Status", value: hit.status.capitalized)
                        LabeledContent("Created", value: hit.createdAt.formatted)
                        if let completed = hit.completedAt {
                            LabeledContent("Completed", value: completed.formatted)
                        }
                    }

                    Section("Task") {
                        Text(hit.taskDescription)
                    }

                    if hit.photoCount > 0 {
                        Section("Photos (\(hit.photoCount))") {
                            if photos.isEmpty {
                                Text("Loading photos...")
                                    .foregroundStyle(.secondary)
                            } else {
                                ForEach(photos) { photo in
                                    HStack {
                                        Image(systemName: "photo")
                                            .foregroundStyle(.blue)
                                        Text(photo.r2Key.components(separatedBy: "/").last ?? photo.id)
                                            .font(.caption)
                                        Spacer()
                                        if let size = photo.fileSize {
                                            Text(ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                                                .font(.caption2)
                                                .foregroundStyle(.secondary)
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            } else if let errorMessage {
                ContentUnavailableView {
                    Label("Error", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(errorMessage)
                }
            } else {
                ContentUnavailableView {
                    Label("HIT Not Found", systemImage: "questionmark.circle")
                } description: {
                    Text("This HIT may have been deleted.")
                }
            }
        }
        .navigationTitle(hit?.recipientName ?? "HIT")
        .navigationBarTitleDisplayMode(.inline)
        .task { await loadHit() }
    }

    private func loadHit() async {
        isLoading = true
        do {
            hit = try await apiService.fetchHit(id: hitId)
            if let hit, hit.photoCount > 0 {
                photos = try await apiService.fetchHitPhotos(hitId: hitId)
            }
        } catch {
            errorMessage = error.localizedDescription
        }
        isLoading = false
    }
}

// MARK: - Date Formatting Helper

private extension String {
    var formatted: String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: self) else { return self }
        let display = DateFormatter()
        display.dateStyle = .medium
        display.timeStyle = .short
        return display.string(from: date)
    }
}
