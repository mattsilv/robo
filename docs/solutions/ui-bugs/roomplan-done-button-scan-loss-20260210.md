---
title: "RoomPlan: Done button discards scan — proper session stop lifecycle"
category: ui-bugs
component: iOS/LiDAR
date: 2026-02-10
severity: critical
symptoms:
  - "User taps Stop during LiDAR scan, scan data silently lost"
  - "No results screen after stopping scan"
  - "RoomCaptureSession data discarded on dismiss"
related:
  - docs/solutions/build-errors/roomplan-uiviewrepresentable-nscoding-objc-20260210.md
  - docs/solutions/ui-patterns/scanner-as-modal-tab-restructure-20260210.md
  - https://github.com/mattsilv/robo/issues/26
---

# RoomPlan: Done Button Discards Scan — Proper Session Stop Lifecycle

## Problem

User completes a full LiDAR room scan, taps "Stop" in the toolbar expecting to see results. Instead, the view dismisses and all scan data is silently lost — no results, no error, no trace.

## Root Cause

The toolbar button called SwiftUI's `dismiss()` directly, which tears down the view hierarchy without ever calling `RoomCaptureSession.stop()`. RoomPlan requires a specific lifecycle to deliver results:

```
captureSession.stop()
  → captureSession(didEndWith:) delegate
    → captureView(shouldPresent:) — Apple's review screen
      → captureView(didPresent:) — delivers final CapturedRoom
```

Calling `dismiss()` short-circuits this entire chain. The session is abandoned, data is garbage collected.

## Solution

### 1. Rename "Stop" → "Done"

"Stop" is ambiguous (stop what?). "Done" clearly means "I'm finished scanning, show me results."

### 2. Use a Binding to trigger proper session stop

The key insight: a SwiftUI toolbar button can't directly call methods on a UIKit view. Use a `@Binding var stopRequested: Bool` to bridge the gap.

**LiDARScanView.swift** — toolbar:
```swift
if phase == .scanning {
    Button("Done") {
        stopRequested = true  // Don't dismiss!
    }
}
```

**RoomCaptureViewWrapper.swift** — responds to binding:
```swift
@Binding var stopRequested: Bool

func updateUIView(_ uiView: RoomCaptureView, context: Context) {
    if stopRequested {
        uiView.captureSession.stop()  // Proper lifecycle
        DispatchQueue.main.async {
            stopRequested = false
        }
    }
}
```

### 3. Remove cancel from results screen

On the results screen, the user must explicitly choose Save or Discard. No accidental dismissal.

## Pattern: SwiftUI → UIKit Action Bridge

This is a reusable pattern for any UIViewRepresentable where SwiftUI needs to trigger an action on the underlying UIKit view:

```swift
// SwiftUI side: set binding
@State private var actionRequested = false
Button("Action") { actionRequested = true }

// UIViewRepresentable side: observe in updateUIView
func updateUIView(_ uiView: SomeUIView, context: Context) {
    if actionRequested {
        uiView.performAction()
        DispatchQueue.main.async { actionRequested = false }
    }
}
```

## Prevention

- Never call `dismiss()` when a capture session is active
- Always use the framework's proper stop/complete lifecycle
- When wrapping UIKit in SwiftUI, use Bindings to bridge actions (not dismiss)
- Label buttons by their outcome ("Done" = see results) not their mechanism ("Stop" = ambiguous)

## Files

- `ios/Robo/Views/LiDARScanView.swift` — toolbar button + state machine
- `ios/Robo/Views/RoomCaptureViewWrapper.swift` — stopRequested binding
- `ios/Robo/Views/RoomResultView.swift` — explicit Save/Discard choice
