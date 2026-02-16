import SwiftUI

struct HitListView: View {
    @Environment(APIService.self) private var apiService

    @Binding var deepLinkHitId: String?

    @State private var hits: [HitSummary] = []
    @State private var isLoading = false
    @State private var showingCreateInfo = false
    @State private var navigationPath = NavigationPath()

    var body: some View {
        NavigationStack(path: $navigationPath) {
            Group {
                if isLoading && hits.isEmpty {
                    ProgressView("Loading HITs...")
                } else if hits.isEmpty {
                    ContentUnavailableView {
                        Label("No HITs Yet", systemImage: "link.badge.plus")
                    } description: {
                        Text("Use the Chat tab to create HITs.\nTry: \"Plan a dinner with Sarah and Mike\"")
                    } actions: {
                        Button("Open Chat") {
                            NotificationCenter.default.post(name: .switchToChat, object: nil)
                        }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.15, green: 0.39, blue: 0.92))
                    }
                } else {
                    List {
                        ForEach(hits) { hit in
                            NavigationLink(value: hit.id) {
                                HitCard(hit: hit)
                            }
                            .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                            .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                Button(role: .destructive) {
                                    Task { await deleteHit(hit) }
                                } label: {
                                    Label("Delete", systemImage: "trash")
                                }
                            }
                        }
                    }
                    .listStyle(.plain)
                    .refreshable { await loadHits() }
                }
            }
            .navigationTitle("HITs")
            .navigationDestination(for: String.self) { hitId in
                HitDetailView(hitId: hitId)
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        NotificationCenter.default.post(name: .switchToChat, object: nil)
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color(red: 0.15, green: 0.39, blue: 0.92))
                    }
                }
            }
            .task { await loadHits() }
            .onChange(of: deepLinkHitId) { _, hitId in
                if let hitId {
                    navigationPath.append(hitId)
                    deepLinkHitId = nil
                }
            }
        }
    }

    private func deleteHit(_ hit: HitSummary) async {
        do {
            try await apiService.deleteHit(id: hit.id)
            withAnimation { hits.removeAll { $0.id == hit.id } }
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
        } catch {
            // Silently fail — user can retry
        }
    }

    private func loadHits() async {
        isLoading = true
        do {
            hits = try await apiService.fetchHits()
        } catch {
            // Silently fail — user can pull to refresh
        }
        isLoading = false
    }
}

// MARK: - HIT Card

private struct HitCard: View {
    let hit: HitSummary
    private let roboBlue = Color(red: 0.15, green: 0.39, blue: 0.92)

    private var typeIcon: String {
        switch hit.hitType {
        case "group_poll": return "chart.bar.fill"
        case "availability": return "calendar"
        case "photo": return "camera.fill"
        default: return "link"
        }
    }

    private var typeLabel: String {
        switch hit.hitType {
        case "group_poll": return "POLL"
        case "availability": return "AVAIL"
        case "photo": return "PHOTO"
        default: return "HIT"
        }
    }

    private var statusColor: Color {
        switch hit.status {
        case "completed": return .green
        case "in_progress": return .orange
        case "expired": return .red
        default: return .gray
        }
    }

    private var statusLabel: String {
        switch hit.status {
        case "completed": return "DONE"
        case "in_progress": return "ACTIVE"
        case "expired": return "EXPIRED"
        default: return "PENDING"
        }
    }

    private var relativeTime: String {
        let formatter = ISO8601DateFormatter()
        guard let date = formatter.date(from: hit.createdAt) else { return "" }
        let interval = Date().timeIntervalSince(date)
        if interval < 60 { return "now" }
        if interval < 3600 { return "\(Int(interval / 60))m ago" }
        if interval < 86400 { return "\(Int(interval / 3600))h ago" }
        let days = Int(interval / 86400)
        if days == 1 { return "1d ago" }
        return "\(days)d ago"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            // Top row: type badge + status + time
            HStack(spacing: 8) {
                // Type icon + label
                HStack(spacing: 4) {
                    Image(systemName: typeIcon)
                        .font(.caption2)
                    Text(typeLabel)
                        .font(.caption2.bold())
                        .tracking(0.5)
                }
                .foregroundStyle(roboBlue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(roboBlue.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 6))

                Spacer()

                // Status dot + label
                HStack(spacing: 4) {
                    Circle()
                        .fill(statusColor)
                        .frame(width: 6, height: 6)
                    Text(statusLabel)
                        .font(.caption2.bold())
                        .tracking(0.3)
                        .foregroundStyle(statusColor)
                }

                Text(relativeTime)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            // Recipient name
            Text(hit.recipientName)
                .font(.headline)
                .foregroundStyle(.primary)
                .lineLimit(1)

            // Task description
            Text(hit.taskDescription)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .lineLimit(2)

            // Bottom row: photo count or poll progress
            HStack(spacing: 12) {
                if hit.photoCount > 0 {
                    HStack(spacing: 4) {
                        Image(systemName: "photo.fill")
                            .font(.caption2)
                        Text("\(hit.photoCount)")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(.secondary)
                }

                // Response progress for group polls
                if let responseCount = hit.responseCount, responseCount > 0 {
                    let config = hit.config != nil ? (try? JSONSerialization.jsonObject(with: Data((hit.config ?? "{}").utf8)) as? [String: Any]) ?? [:] : [:]
                    let participants = config["participants"] as? [String] ?? []
                    let total = participants.isEmpty ? responseCount : participants.count
                    HStack(spacing: 4) {
                        Image(systemName: "person.2.fill")
                            .font(.caption2)
                        Text("\(responseCount)/\(total) responded")
                            .font(.caption.bold())
                    }
                    .foregroundStyle(responseCount >= total ? .green : .orange)
                }

                // Short ID
                Text(hit.id)
                    .font(.system(.caption2, design: .monospaced))
                    .foregroundStyle(.tertiary)

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
