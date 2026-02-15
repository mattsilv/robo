import SwiftUI
import RoomPlan
import CoreLocation

struct RoomCaptureViewWrapper: UIViewRepresentable {
    @Binding var stopRequested: Bool
    let onCaptureComplete: (CapturedRoom, Double?) -> Void
    let onCaptureError: (Error) -> Void

    func makeUIView(context: Context) -> RoomCaptureView {
        let captureView = RoomCaptureView(frame: .zero)
        captureView.captureSession.delegate = context.coordinator
        captureView.delegate = context.coordinator
        captureView.captureSession.run(configuration: .init())
        context.coordinator.startHeading()
        return captureView
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {
        if stopRequested {
            uiView.captureSession.stop()
            DispatchQueue.main.async {
                stopRequested = false
            }
        }
    }

    static func dismantleUIView(_ uiView: RoomCaptureView, coordinator: Coordinator) {
        uiView.captureSession.stop()
        coordinator.stopHeading()
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCaptureComplete: onCaptureComplete, onCaptureError: onCaptureError)
    }

    @objc(RoboRoomCaptureCoordinator)
    class Coordinator: NSObject, RoomCaptureSessionDelegate, RoomCaptureViewDelegate, NSCoding, CLLocationManagerDelegate {
        let onCaptureComplete: (CapturedRoom, Double?) -> Void
        let onCaptureError: (Error) -> Void
        private let locationManager = CLLocationManager()
        private var latestHeading: Double?

        init(
            onCaptureComplete: @escaping (CapturedRoom, Double?) -> Void,
            onCaptureError: @escaping (Error) -> Void
        ) {
            self.onCaptureComplete = onCaptureComplete
            self.onCaptureError = onCaptureError
            super.init()
            locationManager.delegate = self
        }

        func startHeading() {
            if CLLocationManager.headingAvailable() {
                locationManager.startUpdatingHeading()
            }
        }

        func stopHeading() {
            locationManager.stopUpdatingHeading()
        }

        // MARK: - CLLocationManagerDelegate

        func locationManager(_ manager: CLLocationManager, didUpdateHeading newHeading: CLHeading) {
            if newHeading.headingAccuracy >= 0 {
                latestHeading = newHeading.magneticHeading
            }
        }

        // MARK: - NSCoding (required by RoomCaptureViewDelegate)

        required init?(coder: NSCoder) {
            fatalError("Not implemented")
        }

        func encode(with coder: NSCoder) {}

        // MARK: - RoomCaptureSessionDelegate

        func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?) {
            // Processing handled by captureView delegate methods below
        }

        // MARK: - RoomCaptureViewDelegate

        func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool {
            // Return true to show Apple's built-in review screen
            return true
        }

        func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {
            if let error {
                onCaptureError(error)
                return
            }
            onCaptureComplete(processedResult, latestHeading)
        }
    }
}
