import SwiftUI
import SwiftData

struct ScanHistoryView: View {
    @Query(sort: \ScanRecord.capturedAt, order: .reverse)
    private var scans: [ScanRecord]
    @Environment(\.modelContext) private var modelContext

    @State private var showingClearConfirmation = false
    @State private var copiedToastVisible = false

    var body: some View {
        NavigationStack {
            Group {
                if scans.isEmpty {
                    ContentUnavailableView(
                        "No Scans Yet",
                        systemImage: "barcode.viewfinder",
                        description: Text("Tap Create to scan a barcode.")
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
                        .onDelete(perform: deleteScans)
                    }
                }
            }
            .navigationTitle("History")
            .toolbar {
                if !scans.isEmpty {
                    ToolbarItem(placement: .destructiveAction) {
                        Button("Clear All", role: .destructive) {
                            showingClearConfirmation = true
                        }
                    }
                }
            }
            .confirmationDialog(
                "Clear All Scans?",
                isPresented: $showingClearConfirmation,
                titleVisibility: .visible
            ) {
                Button("Delete All Scans", role: .destructive) {
                    clearAll()
                }
            } message: {
                Text("This will permanently delete \(scans.count) scan\(scans.count == 1 ? "" : "s").")
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

    private func deleteScans(at offsets: IndexSet) {
        for index in offsets {
            modelContext.delete(scans[index])
        }
    }

    private func clearAll() {
        for scan in scans {
            modelContext.delete(scan)
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

#Preview {
    ScanHistoryView()
        .modelContainer(for: ScanRecord.self, inMemory: true)
}
