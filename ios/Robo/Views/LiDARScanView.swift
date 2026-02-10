import SwiftUI
import RoomPlan
import AudioToolbox

struct LiDARScanView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    @State private var phase: ScanPhase = .instructions
    @State private var capturedRoom: CapturedRoom?
    @State private var error: String?

    private enum ScanPhase {
        case instructions
        case scanning
        case results
    }

    var body: some View {
        NavigationStack {
            Group {
                if !RoomCaptureSession.isSupported {
                    ContentUnavailableView(
                        "LiDAR Not Available",
                        systemImage: "camera.metering.unknown",
                        description: Text("LiDAR room scanning requires an iPhone Pro or iPad Pro with a LiDAR sensor.")
                    )
                } else {
                    switch phase {
                    case .instructions:
                        instructionsView
                    case .scanning:
                        scanningView
                    case .results:
                        if let capturedRoom {
                            RoomResultView(room: capturedRoom, onSave: saveRoom, onDiscard: {
                                dismiss()
                            })
                        }
                    }
                }
            }
            .navigationTitle(navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(phase == .scanning ? "Stop" : "Cancel") {
                        if phase == .scanning {
                            // Stopping handled by RoomCaptureView's built-in Done button
                            dismiss()
                        } else {
                            dismiss()
                        }
                    }
                }
            }
            .alert("Scan Error", isPresented: .constant(error != nil)) {
                Button("OK") {
                    error = nil
                    phase = .instructions
                }
            } message: {
                if let error {
                    Text(error)
                }
            }
        }
    }

    private var navigationTitle: String {
        switch phase {
        case .instructions: return "Room Scanner"
        case .scanning: return "Scanning..."
        case .results: return "Scan Results"
        }
    }

    // MARK: - Pre-Scan Instructions (Guided Capture)

    private var instructionsView: some View {
        VStack(spacing: 32) {
            Spacer()

            Image(systemName: "camera.metering.spot")
                .font(.system(size: 64))
                .foregroundColor(.accentColor)

            Text("Scan Your Room")
                .font(.title.bold())

            VStack(alignment: .leading, spacing: 16) {
                tipRow(icon: "sun.max", text: "Ensure good lighting — scanning fails in dark rooms")
                tipRow(icon: "figure.walk", text: "Walk slowly around the entire room perimeter")
                tipRow(icon: "arrow.up.and.down", text: "Point camera at walls, floor to ceiling")
                tipRow(icon: "clock", text: "Takes 2–3 minutes — keep the phone moving steadily")
            }
            .padding(.horizontal, 24)

            Spacer()

            Button {
                phase = .scanning
            } label: {
                Text("Start Scanning")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.accentColor)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            .padding(.horizontal, 40)
            .padding(.bottom, 40)
        }
    }

    private func tipRow(icon: String, text: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
                .frame(width: 28)
            Text(text)
                .font(.subheadline)
        }
    }

    // MARK: - Scanning

    private var scanningView: some View {
        RoomCaptureViewWrapper(
            onCaptureComplete: { room in
                // Haptic feedback
                let generator = UINotificationFeedbackGenerator()
                generator.notificationOccurred(.success)
                AudioServicesPlaySystemSound(1057)

                capturedRoom = room
                phase = .results
            },
            onCaptureError: { err in
                error = err.localizedDescription
            }
        )
        .ignoresSafeArea()
    }

    // MARK: - Save

    private func saveRoom() {
        guard let room = capturedRoom else { return }

        let summary = RoomDataProcessor.summarizeRoom(room)

        do {
            let summaryData = try RoomDataProcessor.encodeSummary(summary)
            let fullData = try RoomDataProcessor.encodeFullRoom(room)

            let formatter = DateFormatter()
            formatter.dateFormat = "MMM d, h:mm a"
            let name = "Room Scan \(formatter.string(from: Date()))"

            let record = RoomScanRecord(
                roomName: name,
                wallCount: room.walls.count,
                floorAreaSqM: summary["estimated_floor_area_sqm"] as? Double ?? 0,
                objectCount: room.objects.count,
                summaryJSON: summaryData,
                fullRoomDataJSON: fullData
            )
            modelContext.insert(record)

            dismiss()
        } catch {
            self.error = "Failed to save: \(error.localizedDescription)"
        }
    }
}

#Preview {
    LiDARScanView()
        .modelContainer(for: RoomScanRecord.self, inMemory: true)
}
