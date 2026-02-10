import SwiftUI

struct SensorsView: View {
    var body: some View {
        NavigationStack {
            List {
                NavigationLink(destination: Text("Barcode Scanner (Coming in Issue #4)")) {
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
        }
    }
}

#Preview {
    SensorsView()
}
