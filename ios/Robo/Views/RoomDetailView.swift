import SwiftUI
import SceneKit

struct RoomDetailView: View {
    let room: RoomScanRecord
    @Environment(\.modelContext) private var modelContext

    @State private var shareURL: URL?
    @State private var show3D = false
    @State private var isEditingName = false
    @State private var editedName = ""

    private var summary: [String: Any]? {
        try? JSONSerialization.jsonObject(with: room.summaryJSON) as? [String: Any]
    }

    var body: some View {
        List {
            Section {
                VStack(spacing: 4) {
                    if isEditingName {
                        HStack {
                            TextField("Room name", text: $editedName)
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: editedName) { _, newValue in
                                    if newValue.count > 100 {
                                        editedName = String(newValue.prefix(100))
                                    }
                                }
                            Button("Done") {
                                let trimmed = editedName.trimmingCharacters(in: .whitespacesAndNewlines)
                                if !trimmed.isEmpty {
                                    room.roomName = trimmed
                                    try? modelContext.save()
                                }
                                isEditingName = false
                            }
                            .fontWeight(.semibold)
                        }
                    } else {
                        HStack {
                            Spacer()
                            Text(room.roomName)
                                .font(.title2.bold())
                            Button {
                                editedName = room.roomName
                                isEditingName = true
                            } label: {
                                Image(systemName: "pencil.circle")
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                        }
                    }
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
        .toolbarBackground(.visible, for: .tabBar)
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
        let hasPolygon = (floorPolygonPoints?.count ?? 0) >= 3
        let hasRect = summary?["room_length_m"] as? Double != nil
        if hasPolygon || hasRect {
            Section("Floor Plan") {
                Picker("View", selection: $show3D) {
                    Text("2D").tag(false)
                    Text("3D").tag(true)
                }
                .pickerStyle(.segmented)

                if show3D {
                    Room3DView(room: room)
                        .frame(height: 300)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                } else if let points = floorPolygonPoints, points.count >= 3 {
                    polygonCanvas(points: points)
                        .frame(height: 240)
                } else if let summary,
                          let lengthM = summary["room_length_m"] as? Double,
                          let widthM = summary["room_width_m"] as? Double {
                    rectangleCanvas(
                        lengthFt: lengthM * RoomDataProcessor.metersToFeet,
                        widthFt: widthM * RoomDataProcessor.metersToFeet
                    )
                    .frame(height: 240)
                }
            }
        }
    }

    private var floorPolygonPoints: [(x: Double, y: Double)]? {
        guard let summary,
              let polygonArray = summary["floor_polygon_2d_ft"] as? [[String: Double]],
              polygonArray.count >= 3 else { return nil }
        let pts = polygonArray.compactMap { dict -> (x: Double, y: Double)? in
            guard let x = dict["x"], let y = dict["y"] else { return nil }
            return (x: x, y: y)
        }
        return pts.count >= 3 ? pts : nil
    }

    private func polygonCanvas(points: [(x: Double, y: Double)]) -> some View {
        Canvas { context, size in
            let padding: CGFloat = 44
            let xs = points.map(\.x)
            let ys = points.map(\.y)
            guard let minX = xs.min(), let maxX = xs.max(),
                  let minY = ys.min(), let maxY = ys.max() else { return }
            let roomW = maxX - minX
            let roomH = maxY - minY

            let available = CGSize(width: size.width - padding * 2, height: size.height - padding * 2)
            let scale = min(
                available.width / CGFloat(max(roomW, 0.1)),
                available.height / CGFloat(max(roomH, 0.1))
            )
            let scaledW = CGFloat(roomW) * scale
            let scaledH = CGFloat(roomH) * scale
            let offsetX = (size.width - scaledW) / 2 - CGFloat(minX) * scale
            let offsetY = (size.height - scaledH) / 2 - CGFloat(minY) * scale

            func tx(_ x: Double) -> CGFloat { CGFloat(x) * scale + offsetX }
            func ty(_ y: Double) -> CGFloat { CGFloat(y) * scale + offsetY }

            // Draw polygon
            var path = Path()
            path.move(to: CGPoint(x: tx(points[0].x), y: ty(points[0].y)))
            for i in 1..<points.count {
                path.addLine(to: CGPoint(x: tx(points[i].x), y: ty(points[i].y)))
            }
            path.closeSubpath()

            context.stroke(path, with: .color(.accentColor), lineWidth: 2)
            context.fill(path, with: .color(.accentColor.opacity(0.08)))

            // Compass rose (bottom-right corner)
            if let heading = summary?["magnetic_heading_degrees"] as? Double {
                let compassRadius: CGFloat = 24
                let compassCenter = CGPoint(
                    x: size.width - compassRadius - 12,
                    y: size.height - compassRadius - 12
                )
                let angleRad = -heading * .pi / 180

                // Background circle
                let circlePath = Path(ellipseIn: CGRect(
                    x: compassCenter.x - compassRadius,
                    y: compassCenter.y - compassRadius,
                    width: compassRadius * 2,
                    height: compassRadius * 2
                ))
                context.fill(circlePath, with: .color(.secondary.opacity(0.12)))
                context.stroke(circlePath, with: .color(.secondary.opacity(0.3)), lineWidth: 1)

                // N pointer (red triangle)
                let nTip = CGPoint(
                    x: compassCenter.x + CGFloat(sin(angleRad)) * (compassRadius - 4),
                    y: compassCenter.y - CGFloat(cos(angleRad)) * (compassRadius - 4)
                )
                let nBase1 = CGPoint(
                    x: compassCenter.x + CGFloat(sin(angleRad + 0.3)) * 6,
                    y: compassCenter.y - CGFloat(cos(angleRad + 0.3)) * 6
                )
                let nBase2 = CGPoint(
                    x: compassCenter.x + CGFloat(sin(angleRad - 0.3)) * 6,
                    y: compassCenter.y - CGFloat(cos(angleRad - 0.3)) * 6
                )
                var nPath = Path()
                nPath.move(to: nTip)
                nPath.addLine(to: nBase1)
                nPath.addLine(to: nBase2)
                nPath.closeSubpath()
                context.fill(nPath, with: .color(.red))

                // S pointer (gray)
                let sTip = CGPoint(
                    x: compassCenter.x - CGFloat(sin(angleRad)) * (compassRadius - 4),
                    y: compassCenter.y + CGFloat(cos(angleRad)) * (compassRadius - 4)
                )
                let sBase1 = CGPoint(
                    x: compassCenter.x - CGFloat(sin(angleRad + 0.3)) * 6,
                    y: compassCenter.y + CGFloat(cos(angleRad + 0.3)) * 6
                )
                let sBase2 = CGPoint(
                    x: compassCenter.x - CGFloat(sin(angleRad - 0.3)) * 6,
                    y: compassCenter.y + CGFloat(cos(angleRad - 0.3)) * 6
                )
                var sPath = Path()
                sPath.move(to: sTip)
                sPath.addLine(to: sBase1)
                sPath.addLine(to: sBase2)
                sPath.closeSubpath()
                context.fill(sPath, with: .color(.secondary.opacity(0.4)))

                // "N" label
                let nLabelOffset: CGFloat = compassRadius + 8
                let nLabelPos = CGPoint(
                    x: compassCenter.x + CGFloat(sin(angleRad)) * nLabelOffset,
                    y: compassCenter.y - CGFloat(cos(angleRad)) * nLabelOffset
                )
                context.draw(
                    Text("N").font(.system(size: 10, weight: .bold)).foregroundColor(.red),
                    at: nLabelPos
                )
            }

            // Edge dimension labels
            let cx = points.reduce(0.0) { $0 + $1.x } / Double(points.count)
            let cy = points.reduce(0.0) { $0 + $1.y } / Double(points.count)

            for i in 0..<points.count {
                let j = (i + 1) % points.count
                let p1 = points[i], p2 = points[j]
                let length = sqrt(pow(p2.x - p1.x, 2) + pow(p2.y - p1.y, 2))
                guard length > 0.3 else { continue }

                let midX = (tx(p1.x) + tx(p2.x)) / 2
                let midY = (ty(p1.y) + ty(p2.y)) / 2

                let edgeMidRealX = (p1.x + p2.x) / 2
                let edgeMidRealY = (p1.y + p2.y) / 2
                let dx = edgeMidRealX - cx
                let dy = edgeMidRealY - cy
                let dist = sqrt(dx * dx + dy * dy)
                let offset: CGFloat = 18
                let ox = dist > 0.01 ? CGFloat(dx / dist) * offset : 0
                let oy = dist > 0.01 ? CGFloat(dy / dist) * offset : 0

                let label = formatFeetInches(length)
                context.draw(
                    Text(label).font(.caption2.bold()).foregroundColor(.primary),
                    at: CGPoint(x: midX + ox, y: midY + oy)
                )
            }
        }
    }

    private func rectangleCanvas(lengthFt: Double, widthFt: Double) -> some View {
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

            let path = Path(roundedRect: rect, cornerRadius: 4)
            context.stroke(path, with: .color(.accentColor), lineWidth: 2)
            context.fill(path, with: .color(.accentColor.opacity(0.08)))

            let lengthLabel = String(format: "%.1f ft", lengthFt)
            context.draw(
                Text(lengthLabel).font(.caption.bold()).foregroundColor(.primary),
                at: CGPoint(x: size.width / 2, y: rect.maxY + 16)
            )

            let widthLabel = String(format: "%.1f ft", widthFt)
            context.draw(
                Text(widthLabel).font(.caption.bold()).foregroundColor(.primary),
                at: CGPoint(x: rect.maxX + 24, y: size.height / 2)
            )
        }
    }

    private func formatHeading(_ degrees: Double) -> String {
        let dirs = ["N", "NE", "E", "SE", "S", "SW", "W", "NW"]
        let idx = Int((degrees + 22.5).truncatingRemainder(dividingBy: 360) / 45)
        return String(format: "%.0f° %@", degrees, dirs[idx])
    }

    private func formatFeetInches(_ feet: Double) -> String {
        let wholeFeet = Int(feet)
        let inches = Int((feet - Double(wholeFeet)) * 12.0 + 0.5)
        if inches == 0 || inches == 12 {
            return "\(inches == 12 ? wholeFeet + 1 : wholeFeet)\u{2032}"
        }
        return "\(wholeFeet)\u{2032}\(inches)\u{2033}"
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
            if let heading = dict["magnetic_heading_degrees"] as? Double {
                LabeledContent("Orientation", value: formatHeading(heading))
            }
        }
    }

    // MARK: - File Sizes

    @ViewBuilder
    private var fileSizeSection: some View {
        Section("Data") {
            LabeledContent("Summary", value: formatBytes(room.summaryJSON.count))
            LabeledContent("Full Room Data", value: formatBytes(room.fullRoomDataJSON.count))
            if let usdzData = room.usdzData {
                LabeledContent("3D Model (USDZ)", value: formatBytes(usdzData.count))
            }
        }
    }

    // MARK: - Actions

    private func exportRoom() {
        // Extract @Model properties before crossing isolation boundary
        let name = room.roomName
        let summary = room.summaryJSON
        let fullData = room.fullRoomDataJSON
        Task.detached {
            do {
                let url = try ExportService.createRoomExportZipFromData(
                    roomName: name,
                    summaryJSON: summary,
                    fullRoomDataJSON: fullData
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
