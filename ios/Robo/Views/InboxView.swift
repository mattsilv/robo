import SwiftUI

struct InboxView: View {
    @Environment(APIService.self) private var apiService
    @State private var cards: [InboxCard] = []
    @State private var isLoading = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Group {
                if isLoading {
                    ProgressView("Loading...")
                } else if let error {
                    ContentUnavailableView(
                        "Error Loading Inbox",
                        systemImage: "exclamationmark.triangle",
                        description: Text(error)
                    )
                } else if cards.isEmpty {
                    ContentUnavailableView(
                        "No Cards",
                        systemImage: "tray",
                        description: Text("Your inbox is empty")
                    )
                } else {
                    List(cards) { card in
                        CardRow(card: card)
                    }
                }
            }
            .navigationTitle("Inbox")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        Task { await loadCards() }
                    } label: {
                        Image(systemName: "arrow.clockwise")
                    }
                }
            }
        }
        .task {
            await loadCards()
        }
    }

    private func loadCards() async {
        isLoading = true
        error = nil

        do {
            cards = try await apiService.fetchInbox()
        } catch {
            self.error = error.localizedDescription
        }

        isLoading = false
    }
}

struct CardRow: View {
    let card: InboxCard

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(card.title)
                    .font(.headline)
                Spacer()
                CardTypeBadge(type: card.cardType)
            }

            if let body = card.body {
                Text(body)
                    .font(.body)
                    .foregroundStyle(.secondary)
            }

            Text(card.createdAt, style: .relative)
                .font(.caption)
                .foregroundStyle(.tertiary)
        }
        .padding(.vertical, 4)
    }
}

struct CardTypeBadge: View {
    let type: InboxCard.CardType

    var body: some View {
        Text(type.rawValue.capitalized)
            .font(.caption)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(color.opacity(0.2))
            .foregroundStyle(color)
            .clipShape(Capsule())
    }

    private var color: Color {
        switch type {
        case .decision: return .blue
        case .task: return .orange
        case .info: return .green
        }
    }
}

#Preview {
    InboxView()
        .environment(APIService(deviceService: DeviceService()))
}
