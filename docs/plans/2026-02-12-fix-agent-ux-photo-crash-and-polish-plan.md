---
title: "fix: Agent UX — photo capture crash, hide broken agents, polish flows"
type: fix
date: 2026-02-12
---

# Fix: Agent UX — Photo Capture Crash, Hide Broken Agents, Polish Flows

## Overview

Multiple UX issues with the Agents tab discovered during beta testing. The photo capture flow crashes (white screen), and several polish items are needed to make the agent experience demo-ready by the Feb 16 deadline.

## Issues

### 1. Photo capture shows white screen / crash (P0 — blocking)

**Symptom:** Tapping "Take Photos" on Smart Stylist (or any `.camera` agent) opens a white screen.

**Root cause:** `CameraSessionController.setupCamera()` (`PhotoCaptureView.swift:318`) never requests camera permission. It silently fails:

```swift
guard let camera = AVCaptureDevice.default(...),
      let input = try? AVCaptureDeviceInput(device: camera) else { return }
// ← If permission not granted, this guard silently exits.
// No preview layer is created → white UIView background
```

Unlike `DataScannerViewController` (barcode) and `RoomCaptureSession` (LiDAR), which automatically request camera permission, `AVCaptureSession` requires an explicit `AVCaptureDevice.requestAccess(for: .video)` call.

**Secondary concern:** The `fullScreenCover` in `AgentsView.swift:37-46` uses conditional content (`if let agent = activePhotoAgent`). If SwiftUI evaluates the closure before state propagates, it renders `EmptyView` — also a white screen.

**Fix:**
- Add `AVCaptureDevice.requestAccess(for: .video)` in `CameraSessionController.viewDidLoad()` before `setupCamera()`
- Show a permission-denied state if user declines (not just white screen)
- Move from conditional `if let` inside `fullScreenCover` to the `item:` overload pattern for safer presentation

**Files:** `ios/Robo/Views/PhotoCaptureView.swift`, `ios/Robo/Views/AgentsView.swift`

### 2. Hide non-working agents from beta testers (P0 — blocking)

**Symptom:** Beta testers see camera-based agents (Smart Stylist, Playtime Muse, Store Ops) and tap them, hitting the white screen bug.

**Fix:** Add a `supportedSkillTypes` filter in `AgentsView` that only shows agents with working capture flows. Until photo capture is confirmed stable, filter to `[.lidar, .barcode]` only.

This is a temporary guard — once Issue #1 is fixed and verified on-device, re-enable `.camera`. The filter also gives us a pattern for future skill types (`.motion` is already stubbed but not implemented).

**Implementation:**

```swift
// AgentsView.swift — top of file
private let enabledSkillTypes: Set<AgentRequest.SkillType> = [.lidar, .barcode, .camera]

// In agentsList, filter agents:
let displayAgents = agents.filter { agent in
    guard let request = agent.pendingRequest else { return true } // show connected agents
    return enabledSkillTypes.contains(request.skillType)
}
```

Once #1 is verified working, `.camera` stays in the set and this becomes a no-op filter.

**Files:** `ios/Robo/Views/AgentsView.swift`

### 3. Auto-save room name from agent hint — skip results screen naming (P1)

**Symptom:** After LiDAR scanning for Interior Designer (which specifically asked for "master bedroom"), the results screen shows `TextField("Room name (optional)")` pre-filled with "Master Bedroom" but still requires the user to manually tap "Save." The naming field is noise when the agent already provided a `roomNameHint`.

**Fix:** When `captureContext` is present AND `suggestedRoomName` is set, auto-populate `roomName` (already done on line 68-70 of `LiDARScanView.swift`) and make the text field read-only or hidden. The room name is already pre-filled — we just need to de-emphasize it in agent-driven flows.

Approach: When `suggestedRoomName != nil`, replace the editable `TextField` with a non-editable label showing the room name, so the user sees the name but doesn't need to interact with it.

**Files:** `ios/Robo/Views/RoomResultView.swift`

### 4. Completion toast — "Response sent to [Agent Name]" (P1)

**Symptom:** After completing a scan/capture and dismissing, the agent row silently transitions from "Syncing..." to "Connected." No clear signal that the task is done.

**Fix:** Show an ephemeral green toast at the top of the screen after the sync animation completes: "Response sent to Interior Designer" (or whichever agent). Auto-dismiss after 3 seconds.

Reuse the `ScanToast.swift` pattern (`.ultraThinMaterial`, green checkmark, `.transition(.move(edge: .top).combined(with: .opacity))`), but make it a generic `AgentSyncToast` that takes an agent name.

**Implementation:**
- Create a new `AgentSyncToast` view (or generalize `ScanToast`)
- Add `@State private var completedAgentName: String?` to `AgentsView`
- In `triggerSyncAnimation(for:)` after the 2-second delay, set `completedAgentName` to trigger the toast
- Auto-dismiss after 3 seconds with `Task.sleep`
- Overlay the toast at the top of the `NavigationStack`

**Files:** `ios/Robo/Views/AgentsView.swift` (add toast state + overlay), potentially a new `AgentSyncToast` view or inline it

### 5. Rename "Connected" section to "Agents Ready" (P2)

**Symptom:** "Connected" is technical jargon. Beta testers see "Action Needed" vs "Connected" — the latter doesn't convey meaning.

**Fix:** Change the section header from `"Connected"` to `"Agents Ready"` in `AgentsView.swift:79`. One-line change.

**Files:** `ios/Robo/Views/AgentsView.swift:79`

### 6. Add agent detail view for "Ready" agents (P2)

**Symptom:** Tapping a connected/ready agent does nothing. Users expect to see something.

**Fix:** Make `ConnectedAgentRow` tappable with a `NavigationLink` to a simple `AgentDetailView` showing:
- Agent icon + name + description (larger format)
- Status: "Ready — waiting for next request"
- Last sync date (if available): "Last synced 2 hours ago"
- A placeholder: "When [Agent Name] needs something, it'll appear in Action Needed."

Keep it minimal — just enough to not feel broken when tapped.

**Files:** `ios/Robo/Views/AgentsView.swift` (wrap row in `NavigationLink`), new simple `AgentDetailView` (or inline in AgentsView as a private struct)

## Acceptance Criteria

- [x] Tapping "Take Photos" on any camera agent shows camera preview (not white screen)
- [x] Camera permission is properly requested before capture session starts
- [x] If camera permission denied, user sees a clear message (not white screen)
- [x] Non-working skill types are hidden from the agent list until verified
- [x] LiDAR scan from agent flow auto-saves with the suggested room name (no manual naming needed)
- [x] Green "Response sent to [Agent]" toast appears after completing any agent task
- [x] Toast auto-dismisses after ~3 seconds
- [x] "Connected" section renamed to "Agents Ready"
- [x] Tapping a ready agent shows a simple detail view with metadata
- [ ] All changes tested on physical device via TestFlight

## Edge Cases & Decisions

**Camera permission denied:** Check `AVCaptureDevice.authorizationStatus(for: .video)` before presenting the camera. If `.denied` or `.restricted`, show a `ContentUnavailableView` with "Open Settings" button (deep link via `UIApplication.openSettingsURLString`). Never show a white screen.

**Toast on tab switch:** Toast only shows if user is on Agents tab when sync completes. If they switch away, skip the toast (the agent silently moves to "Agents Ready" — acceptable for MVP).

**Multiple toasts:** Latest toast replaces any visible toast. No queuing. One toast visible at a time.

**Empty roomNameHint:** Treat empty string same as `nil` — show editable TextField. Only hide TextField when `suggestedRoomName` has a non-empty trimmed value.

**Filtered agents with pending requests:** Agents whose `skillType` is not in `enabledSkillTypes` are hidden entirely (both their "Action Needed" card and their row). Connected agents with no pending request always show regardless of skill type (they have no skill to filter on).

**Agent detail from "Action Needed":** No detail view — tapping the action button opens the capture flow. Only "Agents Ready" rows are tappable for detail.

## Implementation Order

1. **#2 Hide broken agents** — immediate safety net for beta testers (2 min)
2. **#1 Fix photo capture** — camera permission request + denied state + safer fullScreenCover (15 min)
3. **#5 Rename "Connected"** — one-line change (1 min)
4. **#3 Auto-save room name** — conditional label vs TextField in RoomResultView (5 min)
5. **#4 Completion toast** — new toast overlay in AgentsView (10 min)
6. **#6 Agent detail view** — new minimal view (10 min)
7. Re-enable `.camera` in the filter once #1 is verified on-device
