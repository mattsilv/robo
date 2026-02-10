import SwiftUI
import RoomPlan

struct RoomResultView: View {
    let room: CapturedRoom
    @Binding var roomName: String
    let onSave: () -> Void
    let onDiscard: () -> Void

    @State private var shareURL: URL?
    @State private var isExporting = false
    @State private var exportError: String?

    private var floorArea: Double {
        RoomDataProcessor.estimateFloorArea(room)
    }

    private var floorAreaSqFt: Double {
        floorArea * 10.7639
    }

    private var ceilingHeight: Double {
        RoomDataProcessor.estimateCeilingHeight(room.walls)
    }

    private var ceilingHeightFt: Double {
        ceilingHeight * 3.28084
    }

    private var totalWallArea: Double {
        RoomDataProcessor.computeTotalWallArea(room.walls)
    }

    private var totalWallAreaSqFt: Double {
        totalWallArea * 10.7639
    }

    private var roomDims: (length: Double, width: Double)? {
        RoomDataProcessor.estimateRoomDimensions(room.walls)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 24) {
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)
                    .padding(.top, 24)

                Text("Scan Complete")
                    .font(.title.bold())

                // Room name
                TextField("Room name (optional)", text: $roomName)
                    .textFieldStyle(.roundedBorder)
                    .padding(.horizontal, 24)

                // Room dimensions headline
                if let dims = roomDims {
                    VStack(spacing: 4) {
                        Text(String(format: "%.0fft × %.0fft", dims.length * 3.28084, dims.width * 3.28084))
                            .font(.title.bold())
                        Text(String(format: "%.1f sq ft · %.1fft ceiling",
                                    floorAreaSqFt, ceilingHeightFt))
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .padding()
                    .frame(maxWidth: .infinity)
                    .background(Color.accentColor.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .padding(.horizontal, 24)
                }

                // Stats grid
                LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 16) {
                    statCard(value: "\(room.walls.count)", label: "Walls", icon: "square.split.2x1")
                    statCard(value: "\(room.doors.count)", label: "Doors", icon: "door.left.hand.open")
                    statCard(value: "\(room.windows.count)", label: "Windows", icon: "window.vertical.open")
                    statCard(value: "\(room.objects.count)", label: "Objects", icon: "cube")
                }
                .padding(.horizontal, 24)

                // Detailed metrics
                VStack(spacing: 12) {
                    metricRow(label: "Floor Area",
                              value: String(format: "%.1f sq ft", floorAreaSqFt),
                              detail: String(format: "%.1f m²", floorArea))
                    metricRow(label: "Ceiling Height",
                              value: String(format: "%.1fft", ceilingHeightFt),
                              detail: String(format: "%.2f m", ceilingHeight))
                    metricRow(label: "Wall Area",
                              value: String(format: "%.0f sq ft", totalWallAreaSqFt),
                              detail: String(format: "%.1f m²", totalWallArea))
                    metricRow(label: "Shape",
                              value: RoomDataProcessor.describeRoomShape(room.walls).capitalized,
                              detail: nil)
                }
                .padding()
                .background(.secondary.opacity(0.1))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .padding(.horizontal, 24)

                // Actions
                VStack(spacing: 12) {
                    Button {
                        onSave()
                    } label: {
                        Label("Save to History", systemImage: "square.and.arrow.down")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                    }

                    Button {
                        exportRoom()
                    } label: {
                        HStack {
                            if isExporting {
                                ProgressView()
                                    .tint(.accentColor)
                            } else {
                                Image(systemName: "square.and.arrow.up")
                            }
                            Text("Share as ZIP")
                        }
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .padding()
                        .background(.secondary.opacity(0.15))
                        .foregroundColor(.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                    .disabled(isExporting)

                    Button("Discard", role: .destructive) {
                        onDiscard()
                    }
                    .font(.subheadline)
                    .padding(.top, 4)
                }
                .padding(.horizontal, 40)
                .padding(.bottom, 24)
            }
        }
        .alert("Export Failed", isPresented: .constant(exportError != nil)) {
            Button("OK") { exportError = nil }
        } message: {
            if let exportError {
                Text(exportError)
            }
        }
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let shareURL {
                ActivityView(activityItems: [shareURL])
            }
        }
    }

    private func statCard(value: String, label: String, icon: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.title3)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.title2.bold())
            Text(label)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .background(.secondary.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func metricRow(label: String, value: String, detail: String?) -> some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            VStack(alignment: .trailing, spacing: 2) {
                Text(value)
                    .font(.headline)
                if let detail {
                    Text(detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    private func exportRoom() {
        isExporting = true
        Task.detached {
            do {
                let summary = RoomDataProcessor.summarizeRoom(room)
                let exportable = ExportableRoom(
                    summary: summary,
                    fullRoom: room
                )
                let url = try ExportService.createRoomExportZip(room: exportable)
                await MainActor.run {
                    shareURL = url
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    exportError = error.localizedDescription
                    isExporting = false
                }
            }
        }
    }
}
