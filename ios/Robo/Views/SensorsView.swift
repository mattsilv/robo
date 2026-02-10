import SwiftUI

struct SensorsView: View {
    @State private var showingScanner = false

    var body: some View {
        NavigationStack {
            List {
                Button {
                    showingScanner = true
                } label: {
                    Label("Barcode Scanner", systemImage: "barcode.viewfinder")
                }

                NavigationLink(destination: Text("Camera (Coming in M2)")) {
                    Label("Camera", systemImage: "camera")
                }

                NavigationLink(destination: Text("LiDAR (Coming in M3)")) {
                    Label("LiDAR", systemImage: "laser.burst")
                }
            }
            .navigationTitle("Sensors")
            .sheet(isPresented: $showingScanner) {
                BarcodeScannerView()
            }
        }
    }
}

#Preview {
    SensorsView()
}
