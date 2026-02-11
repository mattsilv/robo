import SwiftUI

struct BarcodeDetailView: View {
    let scan: ScanRecord

    @State private var copiedToastVisible = false

    var body: some View {
        List {
            Section {
                Text(scan.barcodeValue)
                    .font(.title2.monospaced())
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 8)
            }

            Section {
                LabeledContent("Symbology", value: formatSymbology(scan.symbology))
                LabeledContent("Scanned") {
                    Text(scan.capturedAt, format: .dateTime)
                }
            }

            Section {
                Button {
                    UIPasteboard.general.string = scan.barcodeValue
                    copiedToastVisible = true
                    Task {
                        try? await Task.sleep(for: .seconds(1.5))
                        copiedToastVisible = false
                    }
                } label: {
                    Label("Copy to Clipboard", systemImage: "doc.on.doc")
                }
            }
        }
        .navigationTitle("Barcode")
        .navigationBarTitleDisplayMode(.inline)
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

    private func formatSymbology(_ raw: String) -> String {
        raw.replacingOccurrences(of: "VNBarcodeSymbology", with: "")
    }
}
