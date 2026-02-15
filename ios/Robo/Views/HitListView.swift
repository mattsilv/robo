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
                    }
                } else {
                    List(hits) { hit in
                        NavigationLink(value: hit.id) {
                            HitRow(hit: hit)
                        }
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
                        Image(systemName: "plus")
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

// MARK: - Hit Row

private struct HitRow: View {
    let hit: HitSummary

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(hit.recipientName)
                    .font(.headline)
                Text(hit.taskDescription)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            StatusBadge(status: hit.status)
        }
        .padding(.vertical, 2)
    }
}

// MARK: - Status Badge

private struct StatusBadge: View {
    let status: String

    private var color: Color {
        switch status {
        case "completed": .green
        case "in_progress": .orange
        case "expired": .red
        default: .gray
        }
    }

    private var label: String {
        switch status {
        case "completed": "Done"
        case "in_progress": "Active"
        case "expired": "Expired"
        default: "Pending"
        }
    }

    var body: some View {
        Text(label)
            .font(.caption.bold())
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(color.opacity(0.15))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }
}
