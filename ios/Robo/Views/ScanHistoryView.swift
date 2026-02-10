import SwiftUI
import SwiftData

struct ScanHistoryView: View {
    @Query(sort: \ScanRecord.capturedAt, order: .reverse)
    private var scans: [ScanRecord]
    @Query(sort: \RoomScanRecord.capturedAt, order: .reverse)
    private var roomScans: [RoomScanRecord]
    @Environment(\.modelContext) private var modelContext

    @State private var selectedSegment = 0
    @State private var showingClearConfirmation = false
    @State private var copiedToastVisible = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("History", selection: $selectedSegment) {
                    Text("Barcodes").tag(0)
                    Text("Rooms").tag(1)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.vertical, 8)

                Group {
                    if selectedSegment == 0 {
                        barcodeList
                    } else {
                        roomList
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                if selectedSegment == 0 && !scans.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear All", role: .destructive) {
                            showingClearConfirmation = true
                        }
                    }
                }
                if selectedSegment == 1 && !roomScans.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear All", role: .destructive) {
                            showingClearConfirmation = true
                        }
                    }
                }
            }
            .confirmationDialog(
                "Clear All?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All", role: .destructive) {
                    clearAll()
                }
            } message: {
                if selectedSegment == 0 {
                    Text("This will permanently delete \(scans.count) scan\(scans.count == 1 ? "" : "s").")
                } else {
                    Text("This will permanently delete \(roomScans.count) room scan\(roomScans.count == 1 ? "" : "s").")
                }
            }
            .overlay(alignment: .bottom) {
                if copiedToastVisible {
                    Text("Copied to clipboard")
                        .font(.caption)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 6)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                        .padding(.bottom, 8)
                        .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .animation(.easeInOut(duration: 0.2), value: copiedToastVisible)
        }
    }

    // MARK: - Barcode List

    @ViewBuilder
    private var barcodeList: some View {
        if scans.isEmpty {
            ContentUnavailableView(
                "No Scans Yet",
                systemImage: "barcode.viewfinder",
                description: Text("Tap \(AppStrings.Tabs.gather) to scan a barcode.")
            )
        } else {
            List {
                ForEach(scans) { scan in
                    ScanRow(scan: scan)
                        .contentShape(Rectangle())
                        .onTapGesture {
                            copyToClipboard(scan.barcodeValue)
                        }
                }
                .onDelete(perform: deleteBarcodeScans)
            }
        }
    }

    // MARK: - Room List

    @ViewBuilder
    private var roomList: some View {
        if roomScans.isEmpty {
            ContentUnavailableView(
                "No Room Scans Yet",
                systemImage: "camera.metering.spot",
                description: Text("Tap \(AppStrings.Tabs.gather) to scan a room with LiDAR.")
            )
        } else {
            List {
                ForEach(roomScans) { room in
                    RoomScanRow(room: room)
                }
                .onDelete(perform: deleteRoomScans)
            }
        }
    }

    // MARK: - Actions

    private func deleteBarcodeScans(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(scans[index])
        }
    }

    private func deleteRoomScans(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(roomScans[index])
        }
    }

    private func clearAll() {
        if selectedSegment == 0 {
            for scan in scans {
                modelContext.delete(scan)
            }
        } else {
            for room in roomScans {
                modelContext.delete(room)
            }
        }
    }

    private func copyToClipboard(_ value: String) {
        UIPasteboard.general.string = value
        copiedToastVisible = true
        Task {
            try? await Task.sleep(for: .seconds(1.5))
            copiedToastVisible = false
        }
    }
}

// MARK: - Scan Row

private struct ScanRow: View {
    let scan: ScanRecord

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text(scan.barcodeValue)
                    .font(.subheadline.monospaced())
                    .lineLimit(1)

                Text(scan.capturedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Text(formatSymbology(scan.symbology))
                .font(.caption2)
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(.secondary.opacity(0.15))
                .clipShape(Capsule())
        }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Barcode \(scan.barcodeValue), scanned \(scan.capturedAt, style: .relative) ago")
        .accessibilityHint("Tap to copy to clipboard")
    }

    private func formatSymbology(_ raw: String) -> String {
        raw.replacingOccurrences(of: "VNBarcodeSymbology", with: "")
    }
}

// MARK: - Room Scan Row

private struct RoomScanRow: View {
    let room: RoomScanRecord

    var body: some View {
        HStack {
            Image(systemName: "camera.metering.spot")
                .font(.title3)
                .foregroundColor(.accentColor)
                .frame(width: 32)

            VStack(alignment: .leading, spacing: 4) {
                Text(room.roomName)
                    .font(.subheadline)
                    .lineLimit(1)

                HStack(spacing: 8) {
                    Label("\(room.wallCount) walls", systemImage: "square.split.2x1")
                    Text(String(format: "%.0f ft\u{00B2}", room.floorAreaSqM * 10.7639))
                    if room.ceilingHeightM > 0 {
                        Text(String(format: "%.1fft ceil", room.ceilingHeightM * 3.28084))
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            Spacer()

            Text(room.capturedAt, style: .relative)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    ScanHistoryView()
        .modelContainer(for: [ScanRecord.self, RoomScanRecord.self], inMemory: true)
}
