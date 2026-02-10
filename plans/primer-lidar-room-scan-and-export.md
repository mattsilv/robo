# Engineering Primer: LiDAR Room Scan + Email/Zip Export

**For:** Another Claude Code agent (or engineer) picking this up cold
**Context:** Robo hackathon app — phone sensors as API endpoints for AI agents
**Deadline:** Mon Feb 16, 3:00 PM EST
**Repo:** `/Users/m/gh/hackathon-cc-2026/robo/` (branch from `main`)

---

## What This App Already Does

Robo is an iOS 17+ SwiftUI app with a Cloudflare Workers backend. Today it:

1. **Registers device** on first launch (`DeviceService.bootstrap()` → `POST /api/devices/register`)
2. **Scans barcodes** via VisionKit `DataScannerViewController`
3. **Submits data** to Workers API with `X-Device-ID` auth header
4. Has a tab bar: **Inbox | Sensors | Settings**

The Sensors tab (`SensorsView.swift`) has three rows:
- Barcode Scanner ✅ (working)
- Camera → placeholder "Coming in M2"
- LiDAR → placeholder "Coming in M3"

## Two Features to Build

### Feature 1: Email/Zip Export (Issue #11) — simpler, do first

**Goal:** After scanning a barcode (or later, a room), user taps "Export" → iOS share sheet → email/AirDrop/Files with a `.zip` containing scan JSON.

**Why it matters:** This is the "free tier" — no backend required, privacy-first.

**Implementation:**

1. Add an "Export" button to the scan result flow in `BarcodeScannerView.swift`
2. Collect scan data as JSON (already have `SensorData` model that's `Codable`)
3. Create a temp `.zip` file on-device using Foundation's `Archive` or just write raw JSON (zip is nice-to-have)
4. Present `UIActivityViewController` via a `UIViewControllerRepresentable` wrapper

**Key files to modify:**
- `ios/Robo/Views/BarcodeScannerView.swift` — add export button after scan
- `ios/Robo/Views/SensorsView.swift` — maybe add export for scan history
- New: `ios/Robo/Services/ExportService.swift` — zip creation + share sheet logic

**Pattern to follow:** Look at how `BarcodeScannerView` wraps UIKit via `UIViewControllerRepresentable`. Do the same for `UIActivityViewController`.

```swift
// Minimal share sheet wrapper
struct ShareSheet: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ uiViewController: UIActivityViewController, context: Context) {}
}
```

**Acceptance:**
- [ ] Tap "Export" after barcode scan → share sheet appears
- [ ] Email attachment contains valid JSON with scan data
- [ ] Works in airplane mode (no network dependency)

---

### Feature 2: LiDAR Room Scan (Issue #7) — the demo wow-factor

**Goal:** User taps "LiDAR" in Sensors tab → guided room scan → structured JSON with wall/door/window dimensions → can export or send to API.

**This is THE killer demo.** "Getting LiDAR data into Claude is impossible today. Robo makes it trivial."

#### Use Apple's RoomPlan Framework (NOT raw ARKit)

RoomPlan gives you everything for free:
- **Guided scanning UI** with AR overlays and instructions (Apple built it)
- **Semantic detection** — walls, doors, windows, 16 furniture categories
- **Structured dimensions** — width/height/depth for every surface
- **Codable output** — `CapturedRoom` encodes directly to JSON
- **Review screen** — user sees 3D miniature before confirming

**Requirements:**
- iOS 16+ (we target 17, so fine)
- **LiDAR hardware required** — iPhone 12 Pro and later Pro models only
- **No simulator support** — must test on physical device
- Camera permission (already in Info.plist)

#### Architecture

```
SensorsView.swift
  └── "LiDAR" row tapped
       └── LiDARScanView.swift (new)
            ├── Availability check (RoomCaptureSession.isSupported)
            ├── RoomCaptureViewWrapper (UIViewRepresentable)
            │    └── Apple's guided scanning UI
            ├── Scan complete → CapturedRoom
            ├── Convert to simplified JSON summary
            └── Two paths:
                 ├── Submit to API (POST /api/sensors/data, sensor_type: "lidar")
                 └── Export via share sheet (reuse ExportService)
```

#### Key Implementation

**New file: `ios/Robo/Views/LiDARScanView.swift`**

```swift
import SwiftUI
import RoomPlan

struct LiDARScanView: View {
    @Environment(APIService.self) private var apiService
    @Environment(\.dismiss) private var dismiss

    @State private var isScanning = true
    @State private var capturedRoom: CapturedRoom?
    @State private var isSubmitting = false

    var body: some View {
        NavigationStack {
            Group {
                if !RoomCaptureSession.isSupported {
                    ContentUnavailableView(
                        "LiDAR Not Available",
                        systemImage: "laser.burst",
                        description: Text("This device doesn't have a LiDAR sensor. Requires iPhone Pro models.")
                    )
                } else if isScanning {
                    RoomCaptureViewWrapper(
                        isScanning: $isScanning,
                        capturedRoom: $capturedRoom
                    )
                    .ignoresSafeArea()
                } else if let room = capturedRoom {
                    RoomResultView(room: room, onSubmit: submitToAPI, onExport: exportJSON)
                }
            }
            .navigationTitle("Room Scanner")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    private func submitToAPI(summary: [String: Any]) async {
        // Submit simplified room data as sensor_type: "lidar"
        _ = try? await apiService.submitSensorData(
            sensorType: .lidar,
            data: summary
        )
    }

    private func exportJSON(room: CapturedRoom) {
        // Use ExportService to create JSON and show share sheet
    }
}
```

**New file: `ios/Robo/Views/RoomCaptureViewWrapper.swift`**

This wraps Apple's `RoomCaptureView` for SwiftUI:

```swift
import SwiftUI
import RoomPlan

struct RoomCaptureViewWrapper: UIViewRepresentable {
    @Binding var isScanning: Bool
    @Binding var capturedRoom: CapturedRoom?

    func makeUIView(context: Context) -> RoomCaptureView {
        let view = RoomCaptureView(frame: .zero)
        view.delegate = context.coordinator
        view.captureSession.run(configuration: .init())
        return view
    }

    func updateUIView(_ uiView: RoomCaptureView, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    class Coordinator: NSObject, RoomCaptureViewDelegate {
        var parent: RoomCaptureViewWrapper
        init(_ parent: RoomCaptureViewWrapper) { self.parent = parent }

        func captureView(shouldPresent roomData: CapturedRoomData, error: Error?) -> Bool {
            return true // Show Apple's review screen
        }

        func captureView(didPresent room: CapturedRoom, error: Error?) {
            parent.capturedRoom = room
            parent.isScanning = false
        }
    }
}
```

**Key: Simplify the CapturedRoom into an AI-friendly JSON summary**

The raw `CapturedRoom` JSON is 200KB-2MB. For the API/Claude, distill it down to ~1KB:

```swift
func summarizeRoom(_ room: CapturedRoom) -> [String: Any] {
    return [
        "walls": room.walls.map { wall in
            [
                "width_m": wall.dimensions.x,
                "height_m": wall.dimensions.y,
                "category": "wall"
            ] as [String: Any]
        },
        "doors": room.doors.map { door in
            [
                "width_m": door.dimensions.x,
                "height_m": door.dimensions.y,
                "category": "door"
            ] as [String: Any]
        },
        "windows": room.windows.map { window in
            [
                "width_m": window.dimensions.x,
                "height_m": window.dimensions.y,
                "category": "window"
            ] as [String: Any]
        },
        "objects": room.objects.map { obj in
            [
                "category": String(describing: obj.category),
                "width_m": obj.dimensions.x,
                "height_m": obj.dimensions.y,
                "depth_m": obj.dimensions.z,
            ] as [String: Any]
        },
        "wall_count": room.walls.count,
        "estimated_floor_area_sqm": estimateFloorArea(room.walls),
    ]
}
```

#### Wire Into Existing App

**Modify `SensorsView.swift`:**
```swift
// Replace the placeholder NavigationLink for LiDAR:
NavigationLink(destination: Text("LiDAR (Coming in M3)")) {
    Label("LiDAR", systemImage: "laser.burst")
}

// With:
Button {
    showingLiDAR = true
} label: {
    Label("LiDAR Room Scanner", systemImage: "laser.burst")
}
// Present as sheet, same pattern as barcode scanner
.sheet(isPresented: $showingLiDAR) {
    LiDARScanView()
}
```

#### Gotchas

1. **`RoomCaptureSession.isSupported`** — MUST check this. Will crash on non-Pro devices otherwise.
2. **No simulator** — must test on physical iPhone Pro with LiDAR.
3. **Device gets hot** — keep scans under 3 minutes.
4. **JSON size** — raw CapturedRoom can be 2MB. Always use the summary for API calls.
5. **CapturedRoomData ≠ CapturedRoom** — the delegate gives you raw data first; use `RoomBuilder` if you need post-processing, but for basic use the `captureView(didPresent:)` callback gives the final `CapturedRoom` directly.
6. **Lighting matters** — scan fails in dark rooms.
7. **`CapturedRoom` is `Codable`** — you can encode the full thing for the zip export even if you send the summary to the API.

---

## Existing Patterns to Follow

| Pattern | Example | Location |
|---------|---------|----------|
| UIKit wrapper | `DataScannerRepresentable` | `BarcodeScannerView.swift:104-151` |
| Environment injection | `@Environment(APIService.self)` | `BarcodeScannerView.swift:5` |
| Sensor data submission | `apiService.submitSensorData()` | `BarcodeScannerView.swift:87` |
| Sheet presentation | `showingScanner` + `.sheet` | `SensorsView.swift:4,24` |
| Availability guard | `DataScannerViewController.isSupported` | `BarcodeScannerView.swift:16` |
| Error/result alerts | `@State error` + `.alert` | `BarcodeScannerView.swift:10,55` |
| Haptic feedback | `UINotificationFeedbackGenerator` | `BarcodeScannerView.swift:73` |

## File Structure for New Code

```
ios/Robo/
├── Views/
│   ├── LiDARScanView.swift          ← NEW: main LiDAR scanning view
│   ├── RoomCaptureViewWrapper.swift  ← NEW: UIViewRepresentable for RoomCaptureView
│   ├── RoomResultView.swift          ← NEW: post-scan results + export/submit
│   ├── SensorsView.swift             ← MODIFY: wire LiDAR button
│   └── BarcodeScannerView.swift      ← MODIFY: add export button
├── Services/
│   └── ExportService.swift           ← NEW: zip/share sheet logic (shared by both features)
```

## Build & Test

```bash
cd ios
xcodegen generate
open Robo.xcodeproj
# Select your iPhone Pro device, hit Run
# Camera permission will prompt on first launch
# Tap Sensors → LiDAR Room Scanner → walk around room slowly
```

**Workers API** is already deployed at `https://robo-api.silv.workers.dev` and accepts `sensor_type: "lidar"` — no backend changes needed.

## Demo Script (30 seconds)

1. Open Robo app on iPhone Pro
2. Tap Sensors → LiDAR Room Scanner
3. Walk around room slowly (Apple's guided UI shows progress)
4. Tap "Done" → review 3D miniature → confirm
5. Tap "Send to Claude" → room dimensions appear in agent
6. Agent says: "Your room is 12ft × 14ft with 2 windows. Here's where that couch would fit..."

**The wow moment:** "Wait, you can get LiDAR data into Claude now?"
