import SwiftUI

struct HitDetailView: View {
    @Environment(APIService.self) private var apiService

    let hitId: String

    @State private var hit: HitSummary?
    @State private var photos: [HitPhotoItem] = []
    @State private var responses: [HitResponseItem] = []
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var copiedUrl: String?

    var body: some View {
        Group {
            if isLoading {
                ProgressView("Loading...")
            } else if let hit {
                List {
                    Section("Details") {
                        LabeledContent("Recipient", value: hit.recipientName)
                        LabeledContent("Status", value: hit.status.capitalized)
                        LabeledContent("Type", value: (hit.hitType ?? "photo").capitalized)
                        LabeledContent("Created", value: hit.createdAt.formatted)
                        if let completed = hit.completedAt {
                            LabeledContent("Completed", value: completed.formatted)
                        }
                    }

                    Section("Task") {
                        Text(hit.taskDescription)
                    }

                    // Copy link section
                    Section {
                        let url = "https://robo.app/hit/\(hit.id)"
                        Button {
                            UIPasteboard.general.string = url
                            copiedUrl = url
                            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
                            DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
                                copiedUrl = nil
                            }
                        } label: {
                            HStack {
                                Image(systemName: copiedUrl == url ? "checkmark.circle.fill" : "link")
                                    .foregroundStyle(copiedUrl == url ? .green : .blue)
                                Text(copiedUrl == url ? "Copied!" : "Copy HIT Link")
                                Spacer()
                            }
                        }
                    }

                    // Availability results
                    if hit.hitType == "availability" && !responses.isEmpty {
                        availabilityResultsSection
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
        .refreshable { await loadHit() }
        .task { await loadHit() }
    }

    // MARK: - Availability Results

    private var availabilityResultsSection: some View {
        Section("Responses (\(responses.count))") {
            // Tally votes per slot
            let tallies = computeSlotTallies()

            if !tallies.isEmpty {
                ForEach(tallies, id: \.slot) { tally in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(tally.slot)
                                .font(.subheadline)
                                .fontWeight(.medium)
                            Text(tally.voters.joined(separator: ", "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("\(tally.count)")
                            .font(.title3)
                            .fontWeight(.bold)
                            .foregroundStyle(.blue)
                    }
                }
            }

            // Participant list
            ForEach(responses) { response in
                HStack {
                    Image(systemName: "person.circle.fill")
                        .foregroundStyle(.green)
                    Text(response.respondentName)
                    Spacer()
                    Text(response.createdAt.formatted)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Helpers

    private struct SlotTally {
        let slot: String
        let count: Int
        let voters: [String]
    }

    private func computeSlotTallies() -> [SlotTally] {
        var slotVoters: [String: [String]] = [:]

        for response in responses {
            if let slots = response.responseData["available_slots"]?.value as? [[String: Any]] {
                for slot in slots {
                    if let date = slot["date"] as? String, let time = slot["time"] as? String {
                        let key = "\(formatDate(date)) \(time)"
                        slotVoters[key, default: []].append(response.respondentName)
                    }
                }
            }
        }

        return slotVoters
            .map { SlotTally(slot: $0.key, count: $0.value.count, voters: $0.value) }
            .sorted { $0.count > $1.count }
    }

    private func formatDate(_ iso: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        guard let date = formatter.date(from: iso) else { return iso }
        let display = DateFormatter()
        display.dateFormat = "EEE MMM d"
        return display.string(from: date)
    }

    private func loadHit() async {
        isLoading = true
        do {
            hit = try await apiService.fetchHit(id: hitId)
            if let hit {
                if hit.photoCount > 0 {
                    photos = try await apiService.fetchHitPhotos(hitId: hitId)
                }
                if hit.hitType == "availability" {
                    responses = try await apiService.fetchHitResponses(hitId: hitId)
                }
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
