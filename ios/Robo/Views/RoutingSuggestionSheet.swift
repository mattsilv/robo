import SwiftUI

struct RoutingSuggestionSheet: View {
    let routing: CaptureRouting
    let agents: [AgentConnection]
    let onRoute: (UUID) -> Void
    let onSaveLocally: () -> Void

    private var suggestions: [IntentHeuristicService.SuggestedRoute] {
        IntentHeuristicService.suggest(for: routing)
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                // Header
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)

                    Text(captureTitle)
                        .font(.title3.bold())

                    if !suggestions.isEmpty {
                        Text("Where should this data go?")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.top, 8)

                if suggestions.isEmpty {
                    Text("Data saved to My Data.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .padding()

                    Button {
                        onSaveLocally()
                    } label: {
                        Text("Done")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .padding(.horizontal, 24)
                } else {
                    // Agent suggestions
                    VStack(spacing: 12) {
                        ForEach(suggestions) { suggestion in
                            Button {
                                // Find matching agent and route
                                if let agent = agents.first(where: { $0.name == suggestion.agentName }) {
                                    onRoute(agent.id)
                                } else {
                                    onSaveLocally()
                                }
                            } label: {
                                HStack(spacing: 12) {
                                    Image(systemName: suggestion.agentIcon)
                                        .font(.title3)
                                        .foregroundStyle(suggestion.agentColor)
                                        .frame(width: 36, height: 36)
                                        .background(suggestion.agentColor.opacity(0.15))
                                        .clipShape(RoundedRectangle(cornerRadius: 8))

                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(suggestion.agentName)
                                            .font(.subheadline.weight(.semibold))
                                            .foregroundStyle(.primary)
                                        Text(suggestion.reason)
                                            .font(.caption)
                                            .foregroundStyle(.secondary)
                                            .lineLimit(2)
                                    }

                                    Spacer()

                                    Image(systemName: "arrow.right.circle.fill")
                                        .foregroundStyle(suggestion.agentColor)
                                }
                                .padding(12)
                                .background(.secondary.opacity(0.1))
                                .clipShape(RoundedRectangle(cornerRadius: 12))
                            }
                        }
                    }
                    .padding(.horizontal, 24)

                    // Save locally option
                    Button {
                        onSaveLocally()
                    } label: {
                        Text("Save to My Data only")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.top, 4)
                }

                Spacer()
            }
        }
    }

    private var captureTitle: String {
        switch routing.sensorType {
        case .lidar: return "Room scan captured!"
        case .barcode: return "Barcode scanned!"
        case .camera:
            return routing.photoCount == 1 ? "Photo captured!" : "\(routing.photoCount) photos captured!"
        case .productScan: return "Product scanned!"
        case .beacon: return "Beacon event captured!"
        case .motion: return "Motion data captured!"
        case .health: return "Health data captured!"
        }
    }
}
