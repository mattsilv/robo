---
title: "Compound Multi-Sensor Capture Flow Pattern for iOS Agent Requests"
date: 2026-02-12
category: architecture-patterns
tags: [swift, swiftui, swiftdata, multi-step-flow, compound-capture, agent-request, ios]
component: ios/Views/ProductScanFlowView
severity: n/a
problem_type: architecture_pattern
resolution_time: ~2 hours
---

# Compound Multi-Sensor Capture Flow Pattern

## Problem Summary

The Robo iOS app needed to support agent requests that combine multiple sensor inputs (barcode scan + multi-photo capture) in a single guided flow. The existing architecture only supported single-sensor requests — each `AgentRequest.SkillType` mapped 1:1 to a separate capture view via independent `.fullScreenCover` bindings. Photos from `PhotoCaptureView` were in-memory only (lost on dismiss), and there was no data model for products with optional barcodes.

## Root Cause

The architecture couldn't support compound flows because:

1. **Single `fullScreenCover` per skill type** — Each skill (barcode, camera, LiDAR) was presented independently. No mechanism to chain captures into a single atomic transaction.
2. **No flow state machine** — Without internal phase management, the app dismissed and reset state between steps.
3. **Untracked intermediate data** — Barcode scans and photos saved immediately to the database, but no way to batch them or roll back on cancel.
4. **File orphaning risk** — Captured photos with no associated database record if the user canceled mid-flow.

## Solution

**Single compound view with internal phase state machine.** Instead of multiple `fullScreenCover` bindings, `ProductScanFlowView` is a unified container with a `FlowPhase` enum managing barcode → photo → review transitions.

### Architecture Pattern

```swift
struct ProductScanFlowView: View {
    enum FlowPhase {
        case barcodeScan    // Phase 1: scan or skip
        case photoCapture   // Phase 2: take 1-3 photos
        case review         // Phase 3: confirm or retake
    }

    @State private var phase: FlowPhase = .barcodeScan
    @State private var scannedBarcode: String?
    @State private var capturedPhotos: [(image: UIImage, filename: String)] = []

    var body: some View {
        NavigationStack {
            Group {
                switch phase {
                case .barcodeScan:  barcodeScanPhase
                case .photoCapture: photoCapturePhase
                case .review:       reviewPhase
                }
            }
        }
    }
}
```

### Single-Scan Barcode Mode

Stops accepting input after first detection:

```swift
class Coordinator: NSObject, DataScannerViewControllerDelegate {
    private var hasScanned = false

    func dataScanner(..., didAdd addedItems: [RecognizedItem], ...) {
        guard !hasScanned, let first = addedItems.first else { return }
        hasScanned = true
        dataScanner.stopScanning()
        onScanned(code, symbology)
    }
}
```

### Immediate Disk Persistence + Atomic Cleanup

Photos saved to disk on capture (resilient to interruption), cleaned up on cancel:

```swift
// Save immediately on shutter press
private func handlePhotoCaptured(_ image: UIImage) {
    guard let filename = PhotoStorageService.save(image) else { return }
    capturedPhotos.append((image: image, filename: filename))
}

// Cleanup on cancel — no orphaned files
private func cleanupAndDismiss() {
    PhotoStorageService.delete(capturedPhotos.map(\.filename))
    dismiss()
}
```

### Batch Database Save on Confirmation

SwiftData record created only when user taps "Done" in review:

```swift
private func saveAndDismiss() {
    let record = ProductCaptureRecord(
        barcodeValue: scannedBarcode,
        photoFileNames: capturedPhotos.map(\.filename),
        agentId: captureContext?.agentId
    )
    modelContext.insert(record)
    try? modelContext.save()  // Explicit save before dismiss
    dismiss()
}
```

### Dispatch from AgentsView

Single `fullScreenCover` binding, completion detected via record count:

```swift
case .productScan:
    initialProductCount = productCaptures.count
    syncingAgentId = agent.id
    showingProductScan = true

// On dismiss:
private func handleProductScanDismiss() {
    if productCaptures.count > initialProductCount {
        triggerSyncAnimation(for: agentId)
    }
}
```

## Key Design Decisions

| Decision | Reasoning |
|---|---|
| **Single `.fullScreenCover`** (not chained covers) | Nested covers create unpredictable SwiftUI dismissal behavior. Internal phase switching is synchronous and predictable. |
| **Single-scan barcode mode** | UX clarity — user knows exactly one barcode is captured. Prevents accidental re-scans. Fast auto-advance (800ms) keeps momentum. |
| **Immediate disk persistence** | Memory efficiency for 3+ full-res photos. Thumbnails generated at save time. Resilient to app crash. Explicit cleanup on cancel. |
| **No back-navigation** | Hackathon simplicity. Cancel is the escape hatch. "Retake" returns to camera without confusing state resets. |
| **Batch DB save on review** | Atomicity — cancel means nothing in database. All metadata saved together. Parent monitors count for sync animation. |

## Files Changed

| File | Change |
|---|---|
| `ios/Robo/Views/ProductScanFlowView.swift` | **New.** Compound flow with `FlowPhase` state machine, `SingleScanRepresentable`, `ProductPhotoCaptureView`, `ProductCameraController`. |
| `ios/Robo/Services/PhotoStorageService.swift` | **New.** JPEG persistence to Application Support + 400px thumbnail generation. UUID filenames. Atomic cleanup. |
| `ios/Robo/Models/RoboSchema.swift` | V6 schema with `ProductCaptureRecord` (optional barcode, photo filenames as JSON, agent linkage, nutrition fields). |
| `ios/Robo/RoboApp.swift` | Updated ModelContainer to V6. |
| `ios/Robo/Models/AgentConnection.swift` | Added `.productScan` to `SkillType` enum. |
| `ios/Robo/Services/MockAgentService.swift` | Chef agent updated with pending `.productScan` request + photo checklist. |
| `ios/Robo/Views/AgentsView.swift` | Dispatch + dismiss handler + `fullScreenCover` for `ProductScanFlowView`. |
| `ios/Robo/Views/ScanHistoryView.swift` | `ProductCaptureRow` with photo thumbnails. `ProductCaptureRecord` query in By Agent mode. |
| `ios/Robo/Views/ProductDetailView.swift` | **New.** Photo gallery, barcode info, nutrition data, agent attribution, delete action. |
| `ios/Robo/Services/NutritionService.swift` | Added `lookupForProduct()` for `ProductCaptureRecord`. |

## Gotchas

1. **Early database writes** — Don't create SwiftData records until user confirms. Otherwise cancel leaves orphaned records.
2. **Photo cleanup before dismiss** — Call `PhotoStorageService.delete()` **before** `dismiss()`, not after. View teardown can race with cleanup.
3. **Barcode scanner doesn't stop automatically** — Must explicitly call `stopScanning()` and guard with `hasScanned` flag.
4. **Schema version in RoboApp** — Must update `createResilientContainer()` to reference new schema version (V6) or container creation silently uses wrong schema.
5. **Photo file names as JSON string** — SwiftData doesn't support `[String]` arrays directly in lightweight migrations. Serialize as JSON string with computed property for access.
6. **`modelContext.save()` before dismiss** — SwiftData autosave is unreliable during view dismissal. Always explicit save.

## Testing Checklist

- [ ] Chef agent card appears in "Action Needed" with "Scan Product" button
- [ ] Barcode scan detects code, auto-advances after brief toast
- [ ] "Skip" button advances directly to photo capture
- [ ] Photos saved to disk and visible in review screen (thumbnails)
- [ ] "Done" creates `ProductCaptureRecord`, triggers sync animation
- [ ] "Cancel" at any phase cleans up photos from disk, no orphaned records
- [ ] Product appears in My Data > By Agent > Practical Chef
- [ ] Tapping product shows `ProductDetailView` with photo gallery
- [ ] 0 photos + "Done" stays in capture (doesn't complete task)
- [ ] Nutrition lookup populates product name/calories in history
- [ ] App backgrounded mid-flow resumes correctly

## Prevention / When to Use This Pattern

Use for any agent request that sequences multiple sensors or capture steps:
- Steps are sequential and optionally skippable
- Intermediate data needs review before committing
- File cleanup on cancel is critical
- Single agent request triggers the entire flow

**Core principle:** Persist to disk immediately, commit to database only on final confirmation.

## Future Considerations

- **M2:** Back-navigation between phases (re-scan barcode from review)
- **M2:** Retry nutrition lookup with manual entry fallback
- **M2:** R2 photo sync (background upload after save)
- **M3:** Compound skill chaining (product → nutrition → price history)
- **M3:** Photo deduplication via SHA256 hash

## Related Documentation

- [SwiftData Schema Drift and Agent Context Threading](../architecture-issues/swiftdata-schema-drift-agent-context-threading-20260212.md) — CaptureContext pattern, schema version consistency
- [SwiftData Persistence Failure: Missing Explicit Save](../database-issues/swiftdata-persistence-failure-no-save-no-schema-versioning-20260210.md) — Why explicit `modelContext.save()` is required
- [Scanner as Modal Tab Restructure](../ui-patterns/scanner-as-modal-tab-restructure-20260210.md) — `fullScreenCover` patterns for capture views
- [Nutritionix API Proxy: Barcode Nutrition Lookup](../integration-issues/nutritionix-api-proxy-barcode-nutrition-lookup-20260211.md) — Fire-and-forget nutrition enrichment pattern

## Related Issues

- #95 — Agent Demo: Chef — barcode scan + multi-photo capture
- #96 — PR implementing this pattern
- #88 — Agent Demo: Contractor — multi-photo capture (similar pattern)
- #84 — Reframe Inbox to Agents: The Agentic Inbox (core architecture)
