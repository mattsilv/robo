import SwiftUI
import VisionKit

struct BarcodeScannerView: View {
    @Environment(APIService.self) private var apiService
    @Environment(\.dismiss) private var dismiss

    @State private var scannedCode: String?
    @State private var isProcessing = false
    @State private var error: String?
    @State private var showingResult = false

    var body: some View {
        NavigationStack {
            ZStack {
                if DataScannerViewController.isSupported && DataScannerViewController.isAvailable {
                    DataScannerRepresentable(
                        recognizedDataTypes: [.barcode()],
                        onScan: handleScan
                    )
                    .ignoresSafeArea()
                } else {
                    ContentUnavailableView(
                        "Scanner Not Available",
                        systemImage: "barcode.viewfinder",
                        description: Text("This device does not support barcode scanning")
                    )
                }

                if isProcessing {
                    ProgressView("Processing...")
                        .padding()
                        .background(.regularMaterial)
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                }
            }
            .navigationTitle("Barcode Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
            .alert("Scanned Barcode", isPresented: $showingResult) {
                Button("OK") {
                    scannedCode = nil
                }
            } message: {
                if let code = scannedCode {
                    Text("Code: \(code)")
                }
            }
            .alert("Error", isPresented: .constant(error != nil)) {
                Button("OK") {
                    error = nil
                }
            } message: {
                if let error {
                    Text(error)
                }
            }
        }
    }

    private func handleScan(_ result: RecognizedItem) {
        guard case .barcode(let barcode) = result,
              let code = barcode.payloadStringValue,
              !isProcessing else { return }

        // Haptic feedback
        let generator = UINotificationFeedbackGenerator()
        generator.notificationOccurred(.success)

        scannedCode = code
        isProcessing = true

        Task {
            do {
                // Submit to API
                let data: [String: Any] = [
                    "code": code,
                    "type": barcode.observation.symbology.rawValue
                ]

                _ = try await apiService.submitSensorData(
                    sensorType: .barcode,
                    data: data
                )

                showingResult = true
            } catch {
                self.error = error.localizedDescription
            }

            isProcessing = false
        }
    }
}

// MARK: - DataScannerViewController Wrapper

struct DataScannerRepresentable: UIViewControllerRepresentable {
    let recognizedDataTypes: Set<DataScannerViewController.RecognizedDataType>
    let onScan: (RecognizedItem) -> Void

    func makeUIViewController(context: Context) -> DataScannerViewController {
        let scanner = DataScannerViewController(
            recognizedDataTypes: recognizedDataTypes,
            qualityLevel: .balanced,
            isHighlightingEnabled: true
        )
        scanner.delegate = context.coordinator
        return scanner
    }

    func updateUIViewController(_ uiViewController: DataScannerViewController, context: Context) {
        try? uiViewController.startScanning()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onScan: onScan)
    }

    class Coordinator: NSObject, DataScannerViewControllerDelegate {
        let onScan: (RecognizedItem) -> Void

        init(onScan: @escaping (RecognizedItem) -> Void) {
            self.onScan = onScan
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didTapOn item: RecognizedItem
        ) {
            onScan(item)
        }

        func dataScanner(
            _ dataScanner: DataScannerViewController,
            didAdd addedItems: [RecognizedItem],
            allItems: [RecognizedItem]
        ) {
            // Auto-scan the first item
            if let first = addedItems.first {
                onScan(first)
            }
        }
    }
}

#Preview {
    BarcodeScannerView()
        .environment(APIService(deviceService: DeviceService()))
}
