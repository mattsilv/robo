---
title: "Scanner as Modal with Center Create Tab"
category: ui-patterns
component: ios/Views
problem_type: ux_architecture
severity: medium
date_solved: 2026-02-10
tags: [swiftui, tabs, navigation, fullScreenCover, barcode, scanner]
related_issues: [24]
---

# Scanner as Modal — Tab Restructure

## Problem

The barcode scanner was the default landing tab (full-screen camera). Users felt "trapped" — the camera dominated the screen with no obvious "home." The scanner should be something you **go to** and **come back from**, not the permanent home screen.

**Original layout (4 tabs):**
```
[Scan]  [History]  [Send]  [Settings]
  ↑ default — full-screen camera on launch
```

## Investigation

Considered three approaches:

1. **Sheet from History** — 3 tabs, scanner opens as sheet from History's toolbar button. Simple but lost the visual prominence of "create" action.
2. **Center tab intercept** — 4 tabs with a fake "+" tab that intercepts tap to open scanner. Common pattern (Instagram, Twitter). Keeps create action visually prominent.
3. **Floating action button** — Overlay FAB on History tab. Not native iOS pattern.

## Solution

**Center "Create" tab that intercepts to open fullScreenCover:**

```
[Inbox]  [+ Create]  [History]  [Settings]
```

### ContentView.swift — Tab intercept pattern

```swift
@State private var selectedTab = 0
@State private var showingScanner = false

TabView(selection: $selectedTab) {
    InboxView()
        .tabItem { Label("Inbox", systemImage: "tray") }
        .tag(0)

    // Placeholder — tap is intercepted
    Text("")
        .tabItem { Label("Create", systemImage: "plus.circle.fill") }
        .tag(1)

    ScanHistoryView()
        .tabItem { Label("History", systemImage: "clock") }
        .tag(2)

    SettingsView()
        .tabItem { Label("Settings", systemImage: "gearshape") }
        .tag(3)
}
.onChange(of: selectedTab) { _, newValue in
    if newValue == 1 {
        showingScanner = true
        selectedTab = 2  // Snap back so + never stays selected
    }
}
.fullScreenCover(isPresented: $showingScanner) {
    BarcodeScannerView()
}
```

### BarcodeScannerView.swift — Dismiss button

```swift
@Environment(\.dismiss) private var dismiss

.toolbar {
    ToolbarItem(placement: .cancellationAction) {
        Button("Done") { dismiss() }
    }
}
```

### Key decisions

- **`.fullScreenCover` over `.sheet`** — Camera needs full viewport. Sheet would show a distracting partial background.
- **Snap back to History (tag 2)** — After opening scanner, the tab selection returns to History so the "+" tab never appears selected/highlighted.
- **`cancellationAction` placement** — Puts "Done" in top-left, standard iOS dismiss position.

## Prevention / Future

- The "Create" tab will evolve into a **sensor picker** (barcode, LiDAR, camera) rather than going straight to barcode scanner.
- Same `fullScreenCover` pattern works for any sensor — just present different views.
- If adding more creation actions, consider an action sheet before the fullScreenCover.

## Related

- [PR #24](https://github.com/mattsilv/robo/pull/24) — Implementation PR
- [Issue #23](https://github.com/mattsilv/robo/issues/23) — iCloud settings persistence (follow-up)
- `docs/solutions/integration-issues/m1-hardening-mvp-to-demo-ready-20260210.md` — Prior M1 work
