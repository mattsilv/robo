import SwiftUI
import SwiftData

struct SendView: View {
    @Query(sort: \ScanRecord.capturedAt, order: .reverse)
    private var scans: [ScanRecord]

    @State private var isExporting = false
    @State private var exportError: String?
    @State private var shareURL: URL?

    var body: some View {
        NavigationStack {
            Group {
                if scans.isEmpty {
                    ContentUnavailableView(
                        "Nothing to Export",
                        systemImage: "tray",
                        description: Text("Scan some barcodes first, then come back here to export.")
                    )
                } else {
                    VStack(spacing: 24) {
                        Spacer()

                        Image(systemName: "doc.zipper")
                            .font(.system(size: 64))
                            .foregroundStyle(.secondary)

                        Text("\(scans.count) barcode scan\(scans.count == 1 ? "" : "s") ready to export")
                            .font(.title3)
                            .multilineTextAlignment(.center)

                        Text("Creates a ZIP file with scans.json and scans.csv")
                            .font(.caption)
                            .foregroundStyle(.secondary)

                        Button {
                            exportScans()
                        } label: {
                            HStack {
                                if isExporting {
                                    ProgressView()
                                        .tint(.white)
                                } else {
                                    Image(systemName: "square.and.arrow.up")
                                }
                                Text("Export All")
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor)
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                        }
                        .disabled(isExporting)
                        .padding(.horizontal, 40)

                        Spacer()
                    }
                }
            }
            .navigationTitle("Send")
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
    }

    private func exportScans() {
        isExporting = true
        let exportable = scans.map {
            ExportableScan(barcodeValue: $0.barcodeValue, symbology: $0.symbology, capturedAt: $0.capturedAt, foodName: $0.foodName, brandName: $0.brandName, calories: $0.calories, protein: $0.protein, totalFat: $0.totalFat, totalCarbs: $0.totalCarbs, dietaryFiber: $0.dietaryFiber, sugars: $0.sugars, sodium: $0.sodium, servingQty: $0.servingQty, servingUnit: $0.servingUnit, servingWeightGrams: $0.servingWeightGrams)
        }
        Task.detached {
            do {
                let url = try ExportService.createExportZip(scans: exportable)
                await MainActor.run {
                    self.shareURL = url
                    self.isExporting = false
                }
            } catch {
                await MainActor.run {
                    self.exportError = error.localizedDescription
                    self.isExporting = false
                }
            }
        }
    }
}

// MARK: - UIActivityViewController Wrapper

struct ActivityView: UIViewControllerRepresentable {
    let activityItems: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: activityItems, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}

#Preview {
    SendView()
        .modelContainer(for: ScanRecord.self, inMemory: true)
}
