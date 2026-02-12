import SwiftUI
import SwiftData
import AudioToolbox

struct AgentsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RoomScanRecord.capturedAt, order: .reverse) private var roomScans: [RoomScanRecord]
    @Query(sort: \ScanRecord.capturedAt, order: .reverse) private var scans: [ScanRecord]

    @State private var agents: [AgentConnection] = MockAgentService.loadAgents()
    @State private var showingLiDARScan = false
    @State private var showingPhotoCapture = false
    @State private var showingBarcode = false
    @State private var syncingAgentId: UUID?
    @State private var initialRoomCount = 0
    @State private var activePhotoAgent: AgentConnection?
    @State private var photoCapturedCount = 0
    @State private var initialBarcodeCount = 0

    var body: some View {
        NavigationStack {
            Group {
                if agents.isEmpty {
                    emptyState
                } else {
                    agentsList
                }
            }
            .navigationTitle("Agents")
        }
        .fullScreenCover(isPresented: $showingLiDARScan, onDismiss: handleLiDARDismiss) {
            LiDARScanView(
                agentId: syncingAgentId?.uuidString,
                agentName: agents.first(where: { $0.id == syncingAgentId })?.name,
                suggestedRoomName: agents.first(where: { $0.id == syncingAgentId })?.pendingRequest?.roomNameHint
            )
        }
        .fullScreenCover(isPresented: $showingPhotoCapture, onDismiss: handlePhotoDismiss) {
            if let agent = activePhotoAgent, let request = agent.pendingRequest {
                PhotoCaptureView(
                    agentName: agent.name,
                    checklist: request.photoChecklist ?? [],
                    photoCapturedCount: $photoCapturedCount
                )
            }
        }
        .fullScreenCover(isPresented: $showingBarcode, onDismiss: handleBarcodeDismiss) {
            BarcodeScannerView()
        }
    }

    // MARK: - Agent List

    private var agentsList: some View {
        List {
            let actionNeeded = agents.filter { $0.pendingRequest != nil && $0.status != .syncing }
            let syncing = agents.filter { $0.status == .syncing }
            let connected = agents.filter { $0.pendingRequest == nil && $0.status == .connected }

            if !actionNeeded.isEmpty {
                Section("Action Needed") {
                    ForEach(actionNeeded) { agent in
                        AgentRequestCard(
                            agent: agent,
                            onScanNow: { handleScanNow(agent) }
                        )
                    }
                }
            }

            if !syncing.isEmpty {
                Section {
                    ForEach(syncing) { agent in
                        SyncingAgentRow(agent: agent)
                    }
                }
            }

            if !connected.isEmpty {
                Section("Connected") {
                    ForEach(connected) { agent in
                        ConnectedAgentRow(agent: agent)
                    }
                }
            }
        }
    }

    // MARK: - Empty State

    private var emptyState: some View {
        ContentUnavailableView {
            Label("No Agents Connected", systemImage: "antenna.radiowaves.left.and.right")
        } description: {
            Text("When AI agents need sensor data from your phone, their requests appear here.")
        }
    }

    // MARK: - Actions

    private func handleScanNow(_ agent: AgentConnection) {
        guard let request = agent.pendingRequest else { return }

        switch request.skillType {
        case .lidar:
            initialRoomCount = roomScans.count
            syncingAgentId = agent.id
            showingLiDARScan = true
        case .camera:
            activePhotoAgent = agent
            syncingAgentId = agent.id
            photoCapturedCount = 0
            showingPhotoCapture = true
        case .barcode:
            initialBarcodeCount = scans.count
            syncingAgentId = agent.id
            showingBarcode = true
        case .motion:
            break
        }
    }

    private func handleLiDARDismiss() {
        guard let agentId = syncingAgentId else { return }

        // Check if a new room scan was saved
        if roomScans.count > initialRoomCount {
            triggerSyncAnimation(for: agentId)
        } else {
            syncingAgentId = nil
        }
    }

    private func handlePhotoDismiss() {
        guard let agentId = syncingAgentId else { return }
        if photoCapturedCount > 0 {
            triggerSyncAnimation(for: agentId)
        } else {
            syncingAgentId = nil
        }
        activePhotoAgent = nil
        photoCapturedCount = 0
    }

    private func handleBarcodeDismiss() {
        guard let agentId = syncingAgentId else { return }
        if scans.count > initialBarcodeCount {
            triggerSyncAnimation(for: agentId)
        } else {
            syncingAgentId = nil
        }
    }

    private func triggerSyncAnimation(for agentId: UUID) {
        guard let index = agents.firstIndex(where: { $0.id == agentId }) else { return }

        // Show syncing state
        agents[index].status = .syncing

        // After 2 seconds, mark as synced
        Task {
            try? await Task.sleep(for: .seconds(2))
            guard let idx = agents.firstIndex(where: { $0.id == agentId }) else { return }
            agents[idx].status = .connected
            agents[idx].pendingRequest = nil
            agents[idx].lastSyncDate = Date()
            syncingAgentId = nil

            // Haptic
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            AudioServicesPlaySystemSound(1057)
        }
    }
}

// MARK: - Agent Request Card

private struct AgentRequestCard: View {
    let agent: AgentConnection
    let onScanNow: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: agent.iconSystemName)
                    .font(.title2)
                    .foregroundStyle(agent.accentColor)
                    .frame(width: 40, height: 40)
                    .background(agent.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.headline)
                    if let request = agent.pendingRequest {
                        Text(request.title)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
            }

            if let request = agent.pendingRequest {
                Text(request.description)
                    .font(.callout)
                    .foregroundStyle(.secondary)

                if let checklist = request.photoChecklist, !checklist.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        ForEach(checklist) { task in
                            HStack(spacing: 8) {
                                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(task.isCompleted ? .green : .secondary)
                                    .font(.subheadline)
                                Text(task.label)
                                    .font(.subheadline)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .padding(.leading, 4)
                }

                Button(action: onScanNow) {
                    Label(buttonLabel(for: request.skillType), systemImage: buttonIcon(for: request.skillType))
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                }
                .buttonStyle(.borderedProminent)
                .tint(agent.accentColor)
            }
        }
        .padding(.vertical, 4)
    }

    private func buttonLabel(for skill: AgentRequest.SkillType) -> String {
        switch skill {
        case .lidar: return "Scan Room"
        case .camera: return "Take Photos"
        case .barcode: return "Scan Barcode"
        case .motion: return "Start Capture"
        }
    }

    private func buttonIcon(for skill: AgentRequest.SkillType) -> String {
        switch skill {
        case .lidar: return "camera.metering.spot"
        case .camera: return "camera.fill"
        case .barcode: return "barcode.viewfinder"
        case .motion: return "figure.walk"
        }
    }
}

// MARK: - Syncing Row

private struct SyncingAgentRow: View {
    let agent: AgentConnection

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: agent.iconSystemName)
                .font(.title2)
                .foregroundStyle(agent.accentColor)
                .frame(width: 40, height: 40)
                .background(agent.accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.headline)
                HStack(spacing: 6) {
                    ProgressView()
                        .scaleEffect(0.7)
                    Text("Syncing...")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Connected Agent Row

private struct ConnectedAgentRow: View {
    let agent: AgentConnection

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: agent.iconSystemName)
                .font(.title2)
                .foregroundStyle(agent.accentColor)
                .frame(width: 40, height: 40)
                .background(agent.accentColor.opacity(0.15))
                .clipShape(RoundedRectangle(cornerRadius: 10))

            VStack(alignment: .leading, spacing: 2) {
                Text(agent.name)
                    .font(.headline)
                Text(agent.description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                HStack(spacing: 4) {
                    Circle()
                        .fill(.green)
                        .frame(width: 8, height: 8)
                    Text("Connected")
                        .font(.caption)
                        .foregroundStyle(.green)
                }
                if let lastSync = agent.lastSyncDate {
                    Text(lastSync, style: .relative)
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
        }
        .padding(.vertical, 4)
    }
}

#Preview {
    AgentsView()
        .modelContainer(for: [ScanRecord.self, RoomScanRecord.self], inMemory: true)
}
