import SwiftUI
import SwiftData
import AudioToolbox

struct CaptureHomeView: View {
    @AppStorage("userName") private var userName = ""
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \RoomScanRecord.capturedAt, order: .reverse) private var roomScans: [RoomScanRecord]
    @Query(sort: \ScanRecord.capturedAt, order: .reverse) private var scans: [ScanRecord]
    @Query(sort: \ProductCaptureRecord.capturedAt, order: .reverse) private var productCaptures: [ProductCaptureRecord]
    @Query(sort: \BeaconEventRecord.capturedAt, order: .reverse) private var beaconEvents: [BeaconEventRecord]

    @State private var agents: [AgentConnection] = MockAgentService.loadAgents()

    // Capture presentation state
    @State private var showingLiDARScan = false
    @State private var showingBarcode = false
    @State private var showingProductScan = false
    @State private var showingBeaconMonitor = false
    @State private var showingMotionCapture = false
    @State private var showingHealthCapture = false
    @State private var activePhotoAgent: AgentConnection?
    @State private var showingZeroContextPhoto = false

    // Agent-initiated tracking
    @State private var syncingAgentId: UUID?
    @State private var initialRoomCount = 0
    @State private var initialBarcodeCount = 0
    @State private var initialProductCount = 0
    @State private var initialBeaconCount = 0
    @State private var photoCapturedCount = 0
    @State private var completedAgentName: String?

    // Post-capture routing
    @State private var pendingRouting: CaptureRouting?

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    shortcutsSection

                    captureGrid
                }
                .padding()
            }
            .navigationTitle(userName.isEmpty ? "Capture" : "Hi, \(userName)")
            .overlay(alignment: .top) {
                if let name = completedAgentName {
                    successToast(name: name)
                }
            }
        }
        // Zero-context captures (no agent)
        .fullScreenCover(isPresented: $showingLiDARScan, onDismiss: handleZeroContextLiDARDismiss) {
            LiDARScanView(captureContext: activeCaptureContext, suggestedRoomName: activeSuggestedRoomName)
        }
        .fullScreenCover(isPresented: $showingZeroContextPhoto, onDismiss: handleZeroContextPhotoDismiss) {
            PhotoCaptureView(
                captureContext: activeCaptureContext,
                agentName: activeCaptureContext?.agentName ?? "Photos",
                checklist: activePhotoChecklist,
                photoCapturedCount: $photoCapturedCount
            )
        }
        .fullScreenCover(item: $activePhotoAgent, onDismiss: handleAgentPhotoDismiss) { agent in
            PhotoCaptureView(
                captureContext: activeCaptureContext,
                agentName: agent.name,
                checklist: agent.pendingRequest?.photoChecklist ?? [],
                photoCapturedCount: $photoCapturedCount
            )
        }
        .fullScreenCover(isPresented: $showingBarcode, onDismiss: handleZeroContextBarcodeDismiss) {
            BarcodeScannerView(captureContext: activeCaptureContext)
        }
        .fullScreenCover(isPresented: $showingProductScan, onDismiss: handleZeroContextProductDismiss) {
            ProductScanFlowView(captureContext: activeCaptureContext)
        }
        .fullScreenCover(isPresented: $showingBeaconMonitor, onDismiss: handleZeroContextBeaconDismiss) {
            BeaconMonitorView(captureContext: activeCaptureContext)
        }
        .fullScreenCover(isPresented: $showingMotionCapture, onDismiss: handleMotionDismiss) {
            MotionCaptureView(captureContext: activeCaptureContext)
        }
        .fullScreenCover(isPresented: $showingHealthCapture, onDismiss: handleHealthDismiss) {
            HealthCaptureView(captureContext: activeCaptureContext)
        }
        .sheet(item: $pendingRouting) { routing in
            RoutingSuggestionSheet(
                routing: routing,
                agents: agents,
                onRoute: { agentId in
                    pendingRouting = nil
                },
                onSaveLocally: {
                    pendingRouting = nil
                }
            )
            .presentationDetents([.medium])
        }
    }

    // MARK: - Shortcuts Section

    @ViewBuilder
    private var shortcutsSection: some View {
        VStack(spacing: 12) {
            // Claude Code screenshot shortcut — always visible
            NavigationLink {
                ShareScreenshotGuideView()
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "terminal")
                        .font(.title3)
                        .foregroundStyle(.orange)
                        .frame(width: 36, height: 36)
                        .background(.orange.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 8))

                    VStack(alignment: .leading, spacing: 2) {
                        Text("Send Screenshot to Claude Code")
                            .font(.subheadline.weight(.semibold))
                            .foregroundStyle(.primary)
                        Text("Share your screen with Claude via the iOS Share Sheet")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }

                    Spacer()

                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(12)
                .background(.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }

            // Interior Designer agent banner (if pending)
            let pendingAgents = agents.filter { $0.name != "Claude Code" && $0.pendingRequest != nil && $0.status != .syncing }
            if !pendingAgents.isEmpty {
                HStack {
                    Text("Agent Requests")
                        .font(.headline)
                    Spacer()
                    Text("\(pendingAgents.count)")
                        .font(.caption.bold())
                        .padding(.horizontal, 8)
                        .padding(.vertical, 2)
                        .background(.orange.opacity(0.2))
                        .foregroundStyle(.orange)
                        .clipShape(Capsule())
                }

                ForEach(pendingAgents) { agent in
                    AgentRequestBanner(agent: agent) {
                        handleAgentScanNow(agent)
                    }
                }
            }
        }
    }

    // MARK: - Capture Grid

    private var captureGrid: some View {
        LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
            CaptureButton(icon: "camera.fill", label: "Photos", color: .blue) {
                photoCapturedCount = 0
                showingZeroContextPhoto = true
            }

            CaptureButton(icon: "camera.metering.spot", label: "Room Scan", color: .purple) {
                initialRoomCount = roomScans.count
                showingLiDARScan = true
            }

            CaptureButton(icon: "barcode.viewfinder", label: "Product Scan", color: .orange) {
                initialProductCount = productCaptures.count
                showingProductScan = true
            }

            CaptureButton(icon: "figure.walk.motion", label: "Motion &\nHealth", color: .green) {
                showingMotionCapture = true
            }

            CaptureButton(icon: "barcode", label: "Barcode", color: .red) {
                initialBarcodeCount = scans.count
                showingBarcode = true
            }

            CaptureButton(icon: "sensor.tag.radiowaves.forward", label: "Beacon", color: .indigo) {
                initialBeaconCount = beaconEvents.count
                showingBeaconMonitor = true
            }

        }
    }

    // MARK: - Capture Context

    private var activeCaptureContext: CaptureContext? {
        guard let agentId = syncingAgentId,
              let agent = agents.first(where: { $0.id == agentId }),
              let request = agent.pendingRequest else { return nil }
        return CaptureContext(agentId: agentId.uuidString, agentName: agent.name, requestId: request.id)
    }

    private var activeSuggestedRoomName: String? {
        guard let agentId = syncingAgentId else { return nil }
        return agents.first(where: { $0.id == agentId })?.pendingRequest?.roomNameHint
    }

    private var activePhotoChecklist: [PhotoTask] {
        guard let agentId = syncingAgentId,
              let agent = agents.first(where: { $0.id == agentId }) else { return [] }
        return agent.pendingRequest?.photoChecklist ?? []
    }

    // MARK: - Agent-Initiated Scan

    private func handleAgentScanNow(_ agent: AgentConnection) {
        guard let request = agent.pendingRequest else { return }

        switch request.skillType {
        case .lidar:
            initialRoomCount = roomScans.count
            syncingAgentId = agent.id
            showingLiDARScan = true
        case .camera:
            syncingAgentId = agent.id
            photoCapturedCount = 0
            activePhotoAgent = agent
        case .barcode:
            initialBarcodeCount = scans.count
            syncingAgentId = agent.id
            showingBarcode = true
        case .productScan:
            initialProductCount = productCaptures.count
            syncingAgentId = agent.id
            showingProductScan = true
        case .beacon:
            initialBeaconCount = beaconEvents.count
            syncingAgentId = agent.id
            showingBeaconMonitor = true
        case .motion:
            syncingAgentId = agent.id
            showingMotionCapture = true
        case .health:
            syncingAgentId = agent.id
            showingHealthCapture = true
        }
    }

    // MARK: - Zero-Context Dismiss Handlers

    private func handleZeroContextLiDARDismiss() {
        if syncingAgentId != nil {
            handleAgentDismiss(dataWasCaptured: roomScans.count > initialRoomCount)
        } else if roomScans.count > initialRoomCount {
            pendingRouting = CaptureRouting(sensorType: .lidar)
        }
    }

    private func handleZeroContextPhotoDismiss() {
        if syncingAgentId != nil {
            handleAgentDismiss(dataWasCaptured: photoCapturedCount > 0)
        } else if photoCapturedCount > 0 {
            pendingRouting = CaptureRouting(sensorType: .camera, photoCount: photoCapturedCount)
        }
        photoCapturedCount = 0
    }

    private func handleAgentPhotoDismiss() {
        if syncingAgentId != nil {
            handleAgentDismiss(dataWasCaptured: photoCapturedCount > 0)
        }
        activePhotoAgent = nil
        photoCapturedCount = 0
    }

    private func handleZeroContextBarcodeDismiss() {
        if syncingAgentId != nil {
            handleAgentDismiss(dataWasCaptured: scans.count > initialBarcodeCount)
        } else if scans.count > initialBarcodeCount {
            pendingRouting = CaptureRouting(sensorType: .barcode)
        }
    }

    private func handleZeroContextProductDismiss() {
        if syncingAgentId != nil {
            handleAgentDismiss(dataWasCaptured: productCaptures.count > initialProductCount)
        } else if productCaptures.count > initialProductCount {
            pendingRouting = CaptureRouting(sensorType: .productScan)
        }
    }

    private func handleZeroContextBeaconDismiss() {
        if syncingAgentId != nil {
            handleAgentDismiss(dataWasCaptured: beaconEvents.count > initialBeaconCount)
        } else if beaconEvents.count > initialBeaconCount {
            pendingRouting = CaptureRouting(sensorType: .beacon)
        }
    }

    private func handleMotionDismiss() {
        if syncingAgentId != nil {
            // Motion always captures data on success
            handleAgentDismiss(dataWasCaptured: true)
        }
        // No routing for motion — save locally by default
    }

    private func handleHealthDismiss() {
        if syncingAgentId != nil {
            handleAgentDismiss(dataWasCaptured: true)
        }
    }

    // MARK: - Agent Sync Animation

    private func handleAgentDismiss(dataWasCaptured: Bool) {
        guard let agentId = syncingAgentId else { return }
        if dataWasCaptured {
            triggerSyncAnimation(for: agentId)
        } else {
            syncingAgentId = nil
        }
    }

    private func triggerSyncAnimation(for agentId: UUID) {
        guard let index = agents.firstIndex(where: { $0.id == agentId }) else { return }

        agents[index].status = .syncing

        Task {
            try? await Task.sleep(for: .seconds(2))
            guard let idx = agents.firstIndex(where: { $0.id == agentId }) else { return }
            let agentName = agents[idx].name
            agents[idx].status = .connected
            agents[idx].pendingRequest = nil
            agents[idx].lastSyncDate = Date()
            syncingAgentId = nil

            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
            AudioServicesPlaySystemSound(1057)

            withAnimation(.spring(duration: 0.4)) {
                completedAgentName = agentName
            }
            try? await Task.sleep(for: .seconds(3))
            withAnimation(.spring(duration: 0.3)) {
                completedAgentName = nil
            }
        }
    }

    // MARK: - Success Toast

    private func successToast(name: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(.green)
                .font(.title3)
            Text("Response sent to \(name)")
                .font(.subheadline.weight(.medium))
            Spacer()
        }
        .padding()
        .background(.ultraThinMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
        .padding(.horizontal)
        .transition(.move(edge: .top).combined(with: .opacity))
    }
}

// MARK: - Capture Button

private struct CaptureButton: View {
    let icon: String
    let label: String
    let color: Color
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 12) {
                Image(systemName: icon)
                    .font(.system(size: 32))
                    .foregroundStyle(color)

                Text(label)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.primary)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity)
            .frame(height: 120)
            .background(color.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 16))
        }
    }
}

// MARK: - Agent Request Banner

private struct AgentRequestBanner: View {
    let agent: AgentConnection
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            HStack(spacing: 12) {
                Image(systemName: agent.iconSystemName)
                    .font(.title3)
                    .foregroundStyle(agent.accentColor)
                    .frame(width: 36, height: 36)
                    .background(agent.accentColor.opacity(0.15))
                    .clipShape(RoundedRectangle(cornerRadius: 8))

                VStack(alignment: .leading, spacing: 2) {
                    Text(agent.name)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.primary)
                    if let request = agent.pendingRequest {
                        Text(request.title)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding(12)
            .background(.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

// MARK: - Capture Routing Model

struct CaptureRouting: Identifiable {
    let id = UUID()
    let sensorType: AgentRequest.SkillType
    var photoCount: Int = 0
}

#Preview {
    CaptureHomeView()
        .modelContainer(for: [ScanRecord.self, RoomScanRecord.self, BeaconEventRecord.self], inMemory: true)
}
