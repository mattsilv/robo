import SwiftUI
import RoomPlan

struct RoomCaptureViewWrapper: UIViewRepresentable {
    @Binding var stopRequested: Bool
    let onCaptureComplete: (CapturedRoom) -> Void
    let onCaptureError: (Error) -> Void

    func makeUIView(context: Context) -> RoomCaptureView {
        let captureView = RoomCaptureView(frame: .zero)
        captureView.captureSession.delegate = context.coordinator
        captureView.delegate = context.coordinator
        captureView.captureSession.run(configuration: .init())
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
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onCaptureComplete: onCaptureComplete, onCaptureError: onCaptureError)
    }

    @objc(RoboRoomCaptureCoordinator)
    class Coordinator: NSObject, RoomCaptureSessionDelegate, RoomCaptureViewDelegate, NSCoding {
        let onCaptureComplete: (CapturedRoom) -> Void
        let onCaptureError: (Error) -> Void

        init(
            onCaptureComplete: @escaping (CapturedRoom) -> Void,
            onCaptureError: @escaping (Error) -> Void
        ) {
            self.onCaptureComplete = onCaptureComplete
            self.onCaptureError = onCaptureError
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
            onCaptureComplete(processedResult)
        }
    }
}
