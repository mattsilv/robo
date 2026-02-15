import SwiftUI

struct HitListView: View {
    @Environment(APIService.self) private var apiService

    @Binding var deepLinkHitId: String?

    @State private var hits: [HitSummary] = []
    @State private var isLoading = false
    @State private var showingCreate = false
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
                        Text("Create a HIT to request photos, polls, or data from anyone.")
                    } actions: {
                        Button("Create HIT") { showingCreate = true }
                            .buttonStyle(.borderedProminent)
                            .tint(Color(red: 0.15, green: 0.39, blue: 0.92))
                    }
                } else {
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(hits) { hit in
                                NavigationLink(value: hit.id) {
                                    HitCard(hit: hit)
                                }
                                .buttonStyle(.plain)
                            }
                        }
                        .padding(.horizontal)
                        .padding(.top, 8)
                    }
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
                        showingCreate = true
                    } label: {
                        Image(systemName: "plus.circle.fill")
                            .foregroundStyle(Color(red: 0.15, green: 0.39, blue: 0.92))
                    }
                }
            }
            .sheet(isPresented: $showingCreate, onDismiss: { Task { await loadHits() } }) {
                CreateHitView()
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
