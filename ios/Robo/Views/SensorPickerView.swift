import SwiftUI
import RoomPlan

struct SensorPickerView: View {
    @Environment(\.dismiss) private var dismiss

    @State private var showingBarcode = false
    @State private var showingLiDAR = false

    private var lidarSupported: Bool {
        RoomCaptureSession.isSupported
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                Spacer()

                Text("Choose Sensor")
                    .font(.title.bold())

                Text("What would you like to capture?")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)

                VStack(spacing: 16) {
                    sensorButton(
                        icon: "barcode.viewfinder",
                        title: "Barcode Scanner",
                        subtitle: "Scan barcodes and QR codes",
                        badge: nil
                    ) {
                        showingBarcode = true
                    }

                    sensorButton(
                        icon: "camera.metering.spot",
                        title: "LiDAR Room Scanner",
                        subtitle: "3D room scanning with guided capture",
                        badge: lidarSupported ? nil : "Requires iPhone Pro"
                    ) {
                        showingLiDAR = true
                    }
                }
                .padding(.horizontal, 24)

                Spacer()
                Spacer()
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showingBarcode) {
                BarcodeScannerView()
            }
            .fullScreenCover(isPresented: $showingLiDAR) {
                LiDARScanView()
            }
        }
    }

    private func sensorButton(
        icon: String,
        title: String,
        subtitle: String,
        badge: String?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: icon)
                    .font(.title)
                    .foregroundColor(.accentColor)
                    .frame(width: 44)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(title)
                            .font(.headline)
                            .foregroundStyle(.primary)

                        if let badge {
                            Text(badge)
                                .font(.caption2)
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(.orange.opacity(0.2))
                                .foregroundStyle(.orange)
                                .clipShape(Capsule())
                        }
                    }

                    Text(subtitle)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                Image(systemName: "chevron.right")
                    .foregroundStyle(.secondary)
            }
            .padding()
            .background(.secondary.opacity(0.1))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

#Preview {
    SensorPickerView()
        .modelContainer(for: ScanRecord.self, inMemory: true)
}
