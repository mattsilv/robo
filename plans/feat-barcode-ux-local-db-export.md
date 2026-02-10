# feat: Barcode UX overhaul — local DB, history, tab redesign, export

## Overview

Improve the barcode scanning experience based on user testing feedback. Remove the blocking alert modal, add local persistence with SwiftData, show scan history, redesign the tab bar, and add zip/email export — all on-device, no backend required.

## Barcode Scanner Confirmation

**Apple VisionKit `DataScannerViewController` is the correct choice.** Already implemented in `BarcodeScannerView.swift`. It is:
- Free, built into iOS 16+ (no third-party dependency)
- Supports all standard symbologies (QR, EAN-13, UPC-A/E, Code 128, Code 39, PDF417, Data Matrix, Aztec, etc.)
- Faster than ZXing/ZBar (which are unmaintained) for QR codes
- Only commercial SDKs (Scandit, $$$) beat it for 1D barcode speed, but those are incompatible with open source

No change needed. Keep what we have.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Local DB | SwiftData (`@Model`) | iOS 17+ native, zero deps, `@Query` auto-updates views |
| API calls on scan | Remove for M1 | "Free tier, no backend required" per CLAUDE.md scope |
| Toast style | Single replacing toast, 2s | Non-blocking, auto-dismiss, replaces on rapid scan |
| Deduplication | 3-second same-value debounce | Prevents duplicate saves while camera stares at one barcode |
| Tab layout | Scan / History / Send / Settings | Scanner is hero feature, History replaces Inbox, Send is new |
| Export format | ZIP containing `scans.json` + `scans.csv` | Both formats for maximum agent compatibility |
| ZIP creation | `NSFileCoordinator` (Foundation) | Zero dependencies, built into iOS |
| Share mechanism | `UIActivityViewController` | More reliable than `ShareLink` for file exports on iOS 17 |
| Inbox tab | Remove from tab bar (keep code) | Conflicts with "no backend required" M1 scope |

## Tab Bar Redesign

```
Current:  [Inbox]  [Sensors]  [Settings]
Proposed: [Scan]   [History]  [Send]     [Settings]
```

| Tab | Label | SF Symbol | View | Purpose |
|-----|-------|-----------|------|---------|
| 1 (default) | Scan | `barcode.viewfinder` | `BarcodeScannerView` (full-screen) | Primary capture experience |
| 2 | History | `clock` | `ScanHistoryView` (new) | Browse local scan records |
| 3 | Send | `square.and.arrow.up` | `SendView` (new) | Export data via email/share |
| 4 | Settings | `gearshape` | `SettingsView` (existing) | Device config, about |

The scanner becomes a **full tab** (not a sheet), making it the hero experience on launch. When M2 adds camera/LiDAR, the Scan tab can evolve into a sensor picker or segmented view.

## SwiftData Model

```swift
// ios/Robo/Models/ScanRecord.swift (NEW)
import SwiftData

@Model
final class ScanRecord {
    var barcodeValue: String      // The decoded barcode string
    var symbology: String         // e.g. "VNBarcodeSymbologyEAN13"
    var capturedAt: Date          // Timestamp of scan

    init(barcodeValue: String, symbology: String) {
        self.barcodeValue = barcodeValue
        self.symbology = symbology
        self.capturedAt = Date()
    }
}
```

Keep it minimal for M1. No metadata dictionary (avoids SwiftData complexity with `[String: Any]`). Add fields in M2 as needed.

## Changes By File

### Modified Files

**`ios/Robo/RoboApp.swift`**
- Add `.modelContainer(for: ScanRecord.self)` to WindowGroup
- Keep `DeviceService` and `APIService` injection (Settings still uses them)

**`ios/Robo/Views/ContentView.swift`**
- Replace 3-tab layout with 4-tab layout: Scan, History, Send, Settings
- Remove `InboxView` tab (keep file for M2)
- Make `BarcodeScannerView` a direct tab (not a sheet from SensorsView)

**`ios/Robo/Views/BarcodeScannerView.swift`**
- Remove `.alert("Scanned Barcode", ...)` modifier (lines 46-54)
- Remove `showingResult` state variable
- Remove `APIService` dependency and API submission code
- Add `@Environment(\.modelContext)` for SwiftData
- Add toast overlay (ZStack) for scan feedback
- Add 3-second deduplication: track `lastScannedCode` + `lastScanTime`
- Add `AudioServicesPlaySystemSound(1057)` for scan confirmation sound
- Save `ScanRecord` to SwiftData on each scan

**`ios/Robo/Views/SettingsView.swift`**
- No changes needed

### New Files

**`ios/Robo/Models/ScanRecord.swift`**
- SwiftData `@Model` class (see schema above)

**`ios/Robo/Views/ScanHistoryView.swift`**
- `@Query(sort: \ScanRecord.capturedAt, order: .reverse)` for all scans
- `List` with rows showing: barcode value (headline), symbology badge, relative timestamp
- Tap row → copy barcode value to clipboard (with brief toast)
- Swipe-to-delete on individual rows
- Empty state: "No scans yet. Use the Scan tab to get started."
- Toolbar button: "Clear All" (with confirmation)

**`ios/Robo/Views/SendView.swift`**
- Shows scan count summary: "47 barcode scans ready to export"
- "Export All" button (disabled when count is 0)
- On tap: creates temp directory → writes `scans.json` + `scans.csv` → zips with `NSFileCoordinator` → presents `UIActivityViewController`
- Empty state: "Nothing to export yet."

**`ios/Robo/Views/ScanToast.swift`**
- Reusable toast component: green checkmark + barcode value (truncated 30 chars) + symbology badge
- `.ultraThinMaterial` background, rounded corners, shadow
- Slide-up animation, auto-dismiss after 2 seconds
- Replaced (not stacked) when a new scan arrives

**`ios/Robo/Services/ExportService.swift`**
- `static func createExportZip(scans: [ScanRecord]) throws -> URL`
- Writes `scans.json` (array of objects: `value`, `symbology`, `scanned_at` ISO 8601)
- Writes `scans.csv` (headers: `value,symbology,scanned_at`)
- Zips directory with `NSFileCoordinator(readingItemAt:options:.forUploading)`
- Returns URL to zip file in temp directory

### Files to Leave Alone (M2)

- `ios/Robo/Views/InboxView.swift` — Keep for M2 when backend sync returns
- `ios/Robo/Views/SensorsView.swift` — Keep for M2 multi-sensor picker
- `ios/Robo/Models/InboxCard.swift` — Keep for M2
- `ios/Robo/Models/SensorData.swift` — Keep for M2 API sync
- `ios/Robo/Services/APIService.swift` — Keep for M2, still used by Settings

## Export Format Spec

### scans.json
```json
[
  {
    "value": "4006381333931",
    "symbology": "ean13",
    "scanned_at": "2026-02-10T14:30:00Z"
  },
  {
    "value": "https://robo.app",
    "symbology": "qr",
    "scanned_at": "2026-02-10T14:31:05Z"
  }
]
```

### scans.csv
```csv
value,symbology,scanned_at
4006381333931,ean13,2026-02-10T14:30:00Z
https://robo.app,qr,2026-02-10T14:31:05Z
```

### Zip filename
`robo-scans-{yyyy-MM-dd-HHmmss}.zip`

## Scan Flow (After Changes)

```
User opens app → lands on Scan tab (full-screen camera)
  → Barcode recognized → didAdd fires
  → Check dedup: same value within 3 seconds? Skip.
  → Haptic (success) + system sound
  → Save ScanRecord to SwiftData
  → Toast slides up: "✓ 4006381333931 [EAN-13]"
  → Toast auto-dismisses after 2 seconds
  → Scanner stays live, ready for next barcode
```

## Edge Cases to Handle

| Case | Behavior |
|------|----------|
| Camera permission denied | Show "Camera access required" with Settings link (not "device not supported") |
| Hardware not supported | Show "This device does not support barcode scanning" |
| Rapid-fire scanning (same code) | 3-second debounce, skip duplicate |
| Rapid-fire scanning (different codes) | Each saves, toast replaces previous |
| 0 scans → Export | Export button disabled, empty state message |
| 10,000+ scans → Export | `List` is lazy by default; zip creation runs on background thread |
| App backgrounded during scan | Camera session pauses, resumes on foreground |
| SwiftData write failure | Log error, show error toast (should be extremely rare) |

## Implementation Order

1. **SwiftData model + container** — `ScanRecord.swift`, update `RoboApp.swift`
2. **Toast component** — `ScanToast.swift`
3. **Update BarcodeScannerView** — Remove alert, add toast + dedup + local save
4. **Scan history view** — `ScanHistoryView.swift`
5. **Export service** — `ExportService.swift`
6. **Send view** — `SendView.swift`
7. **Tab bar redesign** — Update `ContentView.swift`
8. **Camera permission fix** — Split error messages in `BarcodeScannerView.swift`

## Acceptance Criteria

- [x] Scanning a barcode shows a non-blocking toast (no alert/OK button)
- [x] Each scan is saved to local SwiftData database
- [x] Same barcode scanned within 3 seconds does not create duplicate
- [x] History tab shows all scans sorted newest-first
- [x] Tapping a history row copies barcode value to clipboard
- [x] Swipe-to-delete works on history rows
- [x] Send tab shows scan count and Export button
- [x] Export creates a ZIP with `scans.json` and `scans.csv`
- [x] System share sheet appears for email/AirDrop/Files
- [x] Export button disabled when no scans exist
- [x] Tab bar shows: Scan, History, Send, Settings
- [x] Scan tab is the default landing tab
- [x] Camera permission denied shows appropriate message with Settings link
- [x] No API calls are made during barcode scanning (local-only M1)
