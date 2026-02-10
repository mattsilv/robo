---
title: "RoomPlan UIViewRepresentable: NSCoding + @objc Requirements"
category: build-errors
component: iOS/RoomPlan
date: 2026-02-10
severity: blocking
symptoms:
  - "type 'Coordinator' does not conform to protocol 'NSCoding'"
  - "nested class has an unstable name when archiving via 'NSCoding'"
  - "value of type 'CapturedRoomData' has no member 'finalResults'"
related:
  - docs/solutions/ui-patterns/scanner-as-modal-tab-restructure-20260210.md
  - https://github.com/mattsilv/robo/issues/26
---

# RoomPlan UIViewRepresentable: NSCoding + @objc Requirements

## Problem

Wrapping Apple's `RoomCaptureView` in a SwiftUI `UIViewRepresentable` with a nested `Coordinator` class causes three distinct build errors on the iOS 26 SDK.

## Symptoms

### Error 1: NSCoding conformance
```
error: type 'RoomCaptureViewWrapper.Coordinator' does not conform to protocol 'NSCoding'
```

### Error 2: Unstable archiving name
```
error: nested class 'RoomCaptureViewWrapper.Coordinator' has an unstable name when archiving via 'NSCoding'
```

### Error 3: Non-existent API
```
error: value of type 'CapturedRoomData' has no member 'finalResults'
```

## Root Causes

1. **`RoomCaptureViewDelegate` requires NSCoding.** The protocol inherits an NSCoding requirement even though the delegate callbacks never actually serialize the Coordinator. You must add stub implementations.

2. **Swift name-mangles nested classes.** A `Coordinator` nested inside `RoomCaptureViewWrapper` gets an unstable Objective-C name that breaks NSCoding archiving. Must provide an explicit `@objc("PrefixedName")` annotation.

3. **`CapturedRoomData` has no `.finalResults` property.** The processed `CapturedRoom` is delivered through the `RoomCaptureViewDelegate.captureView(didPresent:error:)` callback, not extracted from the raw session data.

## Solution

### Coordinator class declaration

```swift
@objc(RoboRoomCaptureCoordinator)
class Coordinator: NSObject, RoomCaptureSessionDelegate, RoomCaptureViewDelegate, NSCoding {
```

### NSCoding stubs (required but never called)

```swift
required init?(coder: NSCoder) {
    fatalError("Not implemented")
}

func encode(with coder: NSCoder) {}
```

### Correct delegate flow (two-step)

```swift
// Step 1: Return true to show Apple's built-in review screen
func captureView(shouldPresent roomDataForProcessing: CapturedRoomData, error: (any Error)?) -> Bool {
    return true
}

// Step 2: Receive the final processed CapturedRoom
func captureView(didPresent processedResult: CapturedRoom, error: (any Error)?) {
    if let error {
        onCaptureError(error)
        return
    }
    onCaptureComplete(processedResult)
}
```

### Session delegate (no-op — processing handled by view delegate)

```swift
func captureSession(_ session: RoomCaptureSession, didEndWith data: CapturedRoomData, error: (any Error)?) {
    // Processing handled by captureView delegate methods
}
```

## What NOT to Do

- Do NOT try `CapturedRoomData.finalResults` — it doesn't exist
- Do NOT skip NSCoding conformance — compiler will reject the delegate
- Do NOT skip `@objc` annotation — causes unstable archiving name error
- Do NOT forget `dismantleUIView()` to call `captureSession.stop()`

## Bonus: SwiftUI Color Gotcha

`.foregroundStyle(.accent)` is not valid. Use `.foregroundColor(.accentColor)` instead.

## Prevention

When wrapping any Apple framework delegate that inherits from NSCoding in a UIViewRepresentable Coordinator:

1. Always add `NSCoding` conformance with stubs
2. Always add `@objc("AppPrefixClassName")` to the Coordinator
3. Check Apple's delegate documentation for the actual callback that delivers final results — don't assume raw data objects have convenience properties

## Files

- Working implementation: `ios/Robo/Views/RoomCaptureViewWrapper.swift`
- Consumer view: `ios/Robo/Views/LiDARScanView.swift`
- Similar pattern (barcode): `ios/Robo/Views/BarcodeScannerView.swift`
