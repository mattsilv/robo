---
title: "fix: Re-register device doesn't persist MCP token"
type: fix
status: active
date: 2026-02-14
---

# fix: Re-register device doesn't persist MCP token

## Problem

When a user taps "Re-register Device" in Settings:
1. Device ID gets wiped (replaced with "unregistered")
2. `save()` persists config with `mcpToken=nil` **before** `bootstrap()` runs
3. `bootstrap()` sets `config.id` to "unregistered" which means `isRegistered` is false — so it should proceed to register
4. But if registration fails (network error, timeout), the user is stuck with a wiped device ID AND no token
5. Even on success, there's a window where the old device ID is already gone

**User's old device ID:** `052fa9ba-9d43-4327-94fb-7687626bb235` (lost after re-register)

## Root Cause

`DeviceService.swift:64` — `save()` called before `bootstrap()`:

```swift
func reRegister(apiService: APIService) async {
    config = DeviceConfig(id: "unregistered", ...)
    save()  // ← persists wiped config immediately
    await bootstrap(apiService: apiService)  // ← token fetched here, but save() already ran
}
```

`bootstrap()` does call `save()` again on success (line 31), but if it fails after 3 retries, the user is stuck with a wiped config.

## Fix

### `ios/Robo/Services/DeviceService.swift`

**Change 1:** Don't save the wiped config until bootstrap succeeds. Keep old config as fallback.

```swift
func reRegister(apiService: APIService) async {
    let previousConfig = config
    let savedBaseURL = config.apiBaseURL
    config = DeviceConfig(
        id: DeviceConfig.unregisteredID,
        name: config.name,
        apiBaseURL: savedBaseURL
    )
    // Don't save() here — let bootstrap() save on success
    await bootstrap(apiService: apiService)

    // If bootstrap failed, restore previous config
    if !isRegistered {
        config = previousConfig
        save()
    }
}
```

**Change 2:** Show error in Settings if re-registration failed (already wired — `registrationError` exists but may not display during re-register flow).

### `ios/Robo/Views/SettingsView.swift`

Verify that `registrationError` is displayed near the re-register button so users see feedback on failure.

## Acceptance Criteria

- [ ] Re-register successfully fetches and persists MCP token
- [ ] If re-register fails, old device ID is preserved (not wiped)
- [ ] Error message shown if registration fails
- [ ] MCP token displays in Settings after successful re-register
