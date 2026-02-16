---
title: "feat: iOS Share Extension — Screenshot to Agent"
type: feat
status: completed
date: 2026-02-15
---

# iOS Share Extension — Screenshot to Agent

## Overview

Add an iOS Share Extension so users can share screenshots directly to their AI agent via the iOS share sheet. User takes a screenshot, taps Share, selects "Robo", and the image is optimized and sent to their connected agent. No need to open the Robo app.

**Core UX:** Screenshot → Share Sheet → "Robo" → optimized image → AI agent

## Problem Statement

Getting a screenshot from your phone to an AI agent today requires: open Robo → navigate to capture → take photo or import from gallery. For quick screenshots (error messages, product labels, UI mockups), this is too many steps. The iOS share sheet is the native, zero-friction path.

## Proposed Solution

A lightweight Share Extension target (`RoboShare`) that:

1. Accepts images from the iOS share sheet
2. Downsamples to reduce AI context window usage (max 1536px longest edge, JPEG quality 0.7)
3. Sends the optimized image to the user's primary connected agent via the Robo API
4. Shows brief success/error feedback, then dismisses

### Architecture

```
┌─────────────────┐     ┌──────────────────┐     ┌─────────────────┐
│  iOS Share Sheet │────▸│  RoboShare Ext    │────▸│  Workers API    │
│  (any app)       │     │  - Downsample     │     │  POST /api/...  │
│                  │     │  - Read App Group  │     │  - Store in R2  │
│                  │     │  - Upload JPEG     │     │  - Link to agent│
└─────────────────┘     └──────────────────┘     └─────────────────┘
                              │
                              │ App Group (group.com.silv.Robo)
                              │ - device_id, agent_id, api_url
                              ▼
                        ┌──────────────────┐
                        │  Robo Main App    │
                        │  (writes config)  │
                        └──────────────────┘
```

### Image Optimization Strategy

**Goal:** Minimize tokens consumed in the AI agent's context window while preserving readability.

| Parameter | Value | Rationale |
|-----------|-------|-----------|
| Max dimension | 1536px (longest edge) | Claude/GPT vision sweet spot — readable text, reasonable tokens |
| JPEG quality | 0.7 | Good balance of size vs. clarity for screenshots |
| Target file size | ~100-200KB | Typical optimized screenshot |
| Max file size | 1MB hard limit | Reject if still too large after compression |
| Method | `CGImageSourceCreateThumbnailAtIndex` | Memory-efficient — no intermediate UIImage allocation |

**Why `CGImageSource` over `UIGraphicsBeginImageContext`:** Share extensions have a 120MB memory limit. `CGImageSource` downsamples directly from the file URL without loading the full-resolution image into memory. This is critical for large screenshots from Pro Max devices (2796x1290, ~8MB uncompressed).

```swift
func downsample(imageAt url: URL, maxDimension: CGFloat = 1536) -> Data? {
    let options: [CFString: Any] = [
        kCGImageSourceCreateThumbnailFromImageAlways: true,
        kCGImageSourceCreateThumbnailWithTransform: true,
        kCGImageSourceThumbnailMaxPixelSize: maxDimension
    ]
    guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
          let cgImage = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    else { return nil }

    let uiImage = UIImage(cgImage: cgImage)
    return uiImage.jpegData(compressionQuality: 0.7)
}
```

## Technical Approach

### 1. New Xcode Target via xcodegen

Add `RoboShare` target to `ios/project.yml`:

```yaml
RoboShare:
  type: app-extension
  platform: iOS
  deploymentTarget: "17.0"
  sources:
    - path: RoboShare
  entitlements:
    path: RoboShare/RoboShare.entitlements
    properties:
      com.apple.security.application-groups:
        - group.com.silv.Robo
  settings:
    base:
      PRODUCT_BUNDLE_IDENTIFIER: com.silv.Robo.ShareExtension
      PRODUCT_MODULE_NAME: RoboShare  # CRITICAL: must be unique per target
      DEVELOPMENT_TEAM: R3Z5CY34Q5
      INFOPLIST_FILE: RoboShare/Info.plist
      CODE_SIGN_ENTITLEMENTS: RoboShare/RoboShare.entitlements
  info:
    path: RoboShare/Info.plist
    properties:
      CFBundleDisplayName: Robo
      NSExtension:
        NSExtensionPointIdentifier: com.apple.share-services
        NSExtensionPrincipalClass: $(PRODUCT_MODULE_NAME).ShareViewController
        NSExtensionAttributes:
          NSExtensionActivationRule:
            NSExtensionActivationSupportsImageWithMaxCount: 1
```

**Also update main `Robo` target:**
- Add `com.apple.security.application-groups: [group.com.silv.Robo]` to entitlements
- Add dependency: `dependencies: [{target: RoboShare, embed: true}]` (Xcode embeds extension in app bundle)

### 2. App Group Shared State

Main app writes agent config to shared `UserDefaults` on launch and after agent changes:

```swift
// Shared/AppGroupConfig.swift (accessible to both targets)
struct AppGroupConfig: Codable {
    let deviceId: String
    let agentId: String?
    let agentName: String?
    let apiBaseURL: String  // e.g., "https://api.robo.app"
}

extension AppGroupConfig {
    static let suiteName = "group.com.silv.Robo"

    static func load() -> AppGroupConfig? {
        guard let data = UserDefaults(suiteName: suiteName)?.data(forKey: "config") else { return nil }
        return try? JSONDecoder().decode(AppGroupConfig.self, from: data)
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults(suiteName: Self.suiteName)?.set(data, forKey: "config")
    }
}
```

### 3. Share Extension UI (SwiftUI via UIHostingController)

Minimal UI — show image thumbnail, agent name, send button:

**Files to create:**

- `ios/RoboShare/ShareViewController.swift` — UIViewController host, loads NSExtensionItem
- `ios/RoboShare/ShareView.swift` — SwiftUI view (thumbnail + agent name + send/cancel)
- `ios/RoboShare/ImageOptimizer.swift` — CGImageSource downsampling
- `ios/RoboShare/ShareUploadService.swift` — POST to API
- `ios/RoboShare/RoboShare.entitlements` — App Groups entitlement
- `ios/Robo/Shared/AppGroupConfig.swift` — Shared config (both targets)

### 4. Upload Flow

Extension uploads optimized JPEG to existing photo upload infrastructure:

```
POST /api/hits/{deviceHitId}/upload
Content-Type: image/jpeg
Body: <raw JPEG bytes>
```

Or if we want a dedicated endpoint:

```
POST /api/captures/screenshot
Content-Type: multipart/form-data
X-Device-ID: {deviceId}

image: <JPEG file>
source: share_extension
agent_id: {agentId}
```

**Decision needed:** Reuse HIT photo upload endpoint or create dedicated screenshot endpoint. Leaning toward reuse — less new code.

### 5. TestFlight / CI

The `testflight.yml` workflow needs to handle the new target. Since xcodegen generates both targets from `project.yml`, the existing `xcodebuild archive` command should pick up the extension automatically (it's embedded in the app bundle). No CI changes expected.

## Acceptance Criteria

- [x] Share Extension appears in iOS share sheet when sharing an image
- [x] Extension name shows "Robo" with the app icon
- [x] Only activates for images (not URLs, text, PDFs, etc.)
- [x] Image is downsampled to max 1536px and JPEG compressed before upload
- [x] Optimized image is sent to the user's primary connected agent
- [x] Success feedback shown before dismissal (checkmark + agent name)
- [x] Error shown if: no agent configured, no network, upload fails
- [ ] "Open Robo" action shown when app not configured
- [x] Works when main app is backgrounded or not running
- [ ] Memory stays under 120MB (profile with Instruments)
- [x] Builds and archives correctly via `xcodegen generate && xcodebuild archive`

## Known Gotchas (from institutional learnings)

1. **`PRODUCT_MODULE_NAME` must be unique** — Set to `RoboShare`, not inherited from project `PRODUCT_NAME: Robo`. Otherwise duplicate `.swiftmodule` build errors. ([docs/solutions/build-errors/xcodegen-test-target-duplicate-swiftmodule-20260210.md](../solutions/build-errors/xcodegen-test-target-duplicate-swiftmodule-20260210.md))

2. **Never edit Info.plist directly** — All keys go in `project.yml` under `info.properties`. xcodegen regenerates Info.plist on every run. ([docs/solutions/build-errors/xcodegen-drops-info-plist-keys-testflight-compliance-20260210.md](../solutions/build-errors/xcodegen-drops-info-plist-keys-testflight-compliance-20260210.md))

3. **Entitlements declared in two places** — Both `project.yml` (under `entitlements.properties`) AND the `.entitlements` plist file. ([docs/solutions/integration-issues/ble-provisioning-wifi-integration-20260214.md](../solutions/integration-issues/ble-provisioning-wifi-integration-20260214.md))

4. **Explicit `modelContext.save()` before dismissal** — If SwiftData is used, autosave races with extension lifecycle. Always call `try modelContext.save()` before `completeRequest()`. ([docs/solutions/database-issues/swiftdata-persistence-failure-no-save-no-schema-versioning-20260210.md](../solutions/database-issues/swiftdata-persistence-failure-no-save-no-schema-versioning-20260210.md))

5. **`NSExtensionActivationRule` must not be `TRUEPREDICATE`** — App Store rejects it. Use specific activation keys like `NSExtensionActivationSupportsImageWithMaxCount: 1`.

6. **120MB memory limit** — Use `CGImageSourceCreateThumbnailAtIndex` for downsampling, never load full-res UIImage.

## Design Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| Agent routing | Always primary agent | MVP simplicity; agent picker in M2 |
| Image format | JPEG 0.7 quality | Best size/quality for screenshots with text |
| Max dimension | 1536px longest edge | Claude vision sweet spot |
| Offline handling | Fail with error message | No queue — extension lifecycle too short for retry |
| Multi-image | Single image only | `NSExtensionActivationSupportsImageWithMaxCount: 1` |
| Success feedback | Brief toast ("Sent to AgentName") | User needs confirmation it worked |
| SwiftData in extension | No — use App Group UserDefaults only | Avoids schema sync complexity, extension only needs device/agent config |
| Network timeout | 15 seconds | Balance between slow networks and user patience in share sheet |

## Implementation Phases

### Phase 1: Extension Skeleton + Image Optimization
- Add `RoboShare` target to `project.yml`
- Create entitlements with App Groups for both targets
- Implement `ShareViewController` + `ShareView` (SwiftUI)
- Implement `ImageOptimizer` with CGImageSource downsampling
- Verify builds with `xcodegen generate && xcodebuild`

### Phase 2: App Group Config + Upload
- Add `AppGroupConfig` shared struct
- Main app writes config on launch/agent change
- Extension reads config and uploads optimized image
- Wire up to existing API endpoint (or create `/api/captures/screenshot`)
- Success/error UI

### Phase 3: Polish + TestFlight
- Test on physical device (extension requires real device)
- Profile memory with Instruments
- Verify TestFlight build includes extension
- Clean stale DerivedData before device install

## File Changes Summary

### New Files
| File | Purpose |
|------|---------|
| `ios/RoboShare/ShareViewController.swift` | Extension entry point, UIHostingController host |
| `ios/RoboShare/ShareView.swift` | SwiftUI UI (thumbnail, agent name, send/cancel) |
| `ios/RoboShare/ImageOptimizer.swift` | CGImageSource downsampling + JPEG compression |
| `ios/RoboShare/ShareUploadService.swift` | URLSession upload to API |
| `ios/RoboShare/RoboShare.entitlements` | App Groups entitlement |
| `ios/Robo/Shared/AppGroupConfig.swift` | Shared config struct (both targets read/write) |

### Modified Files
| File | Change |
|------|--------|
| `ios/project.yml` | Add `RoboShare` target, add App Groups to `Robo` entitlements, add embed dependency |
| `ios/Robo/Robo.entitlements` | Add `com.apple.security.application-groups` |
| `ios/Robo/RoboApp.swift` (or DeviceService) | Write AppGroupConfig on launch |

### Possibly Modified
| File | Change |
|------|--------|
| `workers/src/routes/` | New endpoint or reuse existing for screenshot upload |
| `.github/workflows/testflight.yml` | Verify extension is included in archive (likely automatic) |

## References

- [iOS Share Extension with SwiftUI and SwiftData — Sam Merrell](https://www.merrell.dev/ios-share-extension-with-swiftui-and-swiftdata/)
- [Memory limits in iOS app extensions — Igor Kulman](https://blog.kulman.sk/dealing-with-memory-limits-in-app-extensions/)
- [Apple: App Extension Programming Guide](https://developer.apple.com/library/archive/documentation/General/Conceptual/ExtensibilityPG/ExtensionScenarios.html)
- [XcodeGen ProjectSpec](https://github.com/yonaskolb/XcodeGen/blob/master/Docs/ProjectSpec.md)
