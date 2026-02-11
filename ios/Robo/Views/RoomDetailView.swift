import SwiftUI

struct RoomDetailView: View {
    let room: RoomScanRecord

    @State private var shareURL: URL?

    private var summary: [String: Any]? {
        try? JSONSerialization.jsonObject(with: room.summaryJSON) as? [String: Any]
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 4) {
                    Text(room.roomName)
                        .font(.title2.bold())
                    Text(room.capturedAt, format: .dateTime)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 4)
            }

            floorPlanSection

            metricsSection

            fileSizeSection

            Section {
                Button {
                    exportRoom()
                } label: {
                    Label("Share as ZIP", systemImage: "square.and.arrow.up")
                }
            }
        }
        .navigationTitle("Room Scan")
        .navigationBarTitleDisplayMode(.inline)
        .sheet(isPresented: Binding(
            get: { shareURL != nil },
            set: { if !$0 { shareURL = nil } }
        )) {
            if let shareURL {
                ActivityView(activityItems: [shareURL])
            }
        }
    }

    // MARK: - Floor Plan

    @ViewBuilder
    private var floorPlanSection: some View {
        if let summary,
           let lengthM = summary["room_length_m"] as? Double,
           let widthM = summary["room_width_m"] as? Double {
            let lengthFt = lengthM * RoomDataProcessor.metersToFeet
            let widthFt = widthM * RoomDataProcessor.metersToFeet

            Section("Floor Plan") {
                Canvas { context, size in
                    let padding: CGFloat = 40
                    let available = CGSize(
                        width: size.width - padding * 2,
                        height: size.height - padding * 2
                    )
                    let scale = min(
                        available.width / CGFloat(lengthFt),
                        available.height / CGFloat(widthFt)
                    )
                    let rectW = CGFloat(lengthFt) * scale
                    let rectH = CGFloat(widthFt) * scale
                    let origin = CGPoint(
                        x: (size.width - rectW) / 2,
                        y: (size.height - rectH) / 2
                    )
                    let rect = CGRect(origin: origin, size: CGSize(width: rectW, height: rectH))

                    // Draw room rectangle
                    let path = Path(roundedRect: rect, cornerRadius: 4)
                    context.stroke(path, with: .color(.accentColor), lineWidth: 2)
                    context.fill(path, with: .color(.accentColor.opacity(0.08)))

                    // Length label (bottom)
                    let lengthLabel = String(format: "%.1f ft", lengthFt)
                    context.draw(
                        Text(lengthLabel).font(.caption.bold()).foregroundColor(.primary),
                        at: CGPoint(x: size.width / 2, y: rect.maxY + 16)
                    )

                    // Width label (right)
                    let widthLabel = String(format: "%.1f ft", widthFt)
                    context.draw(
                        Text(widthLabel).font(.caption.bold()).foregroundColor(.primary),
                        at: CGPoint(x: rect.maxX + 24, y: size.height / 2)
                    )
                }
                .frame(height: 200)
            }
        }
    }

    // MARK: - Metrics

    @ViewBuilder
    private var metricsSection: some View {
        let dict = summary ?? [:]
        let floorAreaSqft = room.floorAreaSqM * RoomDataProcessor.sqmToSqft
        let ceilFt = room.ceilingHeightM * RoomDataProcessor.metersToFeet
        let doorCount = dict["door_count"] as? Int ?? 0
        let windowCount = dict["window_count"] as? Int ?? 0

        Section("Metrics") {
            LabeledContent("Floor Area", value: String(format: "%.0f ft\u{00B2}", floorAreaSqft))
            if room.ceilingHeightM > 0 {
                LabeledContent("Ceiling Height", value: String(format: "%.1f ft", ceilFt))
            }
            LabeledContent("Walls", value: "\(room.wallCount)")
            LabeledContent("Doors", value: "\(doorCount)")
            LabeledContent("Windows", value: "\(windowCount)")
            LabeledContent("Objects", value: "\(room.objectCount)")
            if let shape = dict["room_shape"] as? String {
                LabeledContent("Shape", value: shape.capitalized)
            }
        }
    }

    // MARK: - File Sizes

    @ViewBuilder
    private var fileSizeSection: some View {
        Section("Data") {
            LabeledContent("Summary", value: formatBytes(room.summaryJSON.count))
            LabeledContent("Full Room Data", value: formatBytes(room.fullRoomDataJSON.count))
        }
    }

    // MARK: - Actions

    private func exportRoom() {
        Task.detached {
            do {
                let url = try ExportService.createRoomExportZipFromData(
                    roomName: room.roomName,
                    summaryJSON: room.summaryJSON,
                    fullRoomDataJSON: room.fullRoomDataJSON
                )
                await MainActor.run {
                    shareURL = url
                }
            } catch {
                // Silently fail — export is best-effort
            }
        }
    }

    private func formatBytes(_ bytes: Int) -> String {
        if bytes < 1024 {
            return "\(bytes) B"
        } else if bytes < 1024 * 1024 {
            return String(format: "%.1f KB", Double(bytes) / 1024)
        } else {
            return String(format: "%.1f MB", Double(bytes) / (1024 * 1024))
        }
    }
}
