---
title: "App Store Connect rejects TestFlight builds: missing NSHealthUpdateUsageDescription"
category: build-errors
tags: [ios, healthkit, app-store-connect, testflight, info-plist, ci-cd]
severity: high
date_solved: "2026-02-14"
components: [iOS, HealthKit, App Store Connect, TestFlight, CI/CD]
symptoms:
  - All TestFlight uploads rejected since build #95
  - "Validation failed. Missing purpose string in Info.plist"
  - "NSHealthUpdateUsageDescription key with a user-facing purpose string"
root_cause: "App Store Connect requires NSHealthUpdateUsageDescription even when HealthKit toShare is empty"
---

# App Store Connect Rejects TestFlight: Missing NSHealthUpdateUsageDescription

## Problem

Every TestFlight build since #95 failed at the "Export and upload" step with:

```
Validation failed
Missing purpose string in Info.plist. Your app's code references one or more APIs
that access sensitive user data... The Info.plist file for the "Robo.app" bundle
should contain a NSHealthUpdateUsageDescription key with a user-facing purpose string
explaining clearly and completely why your app needs the data.
```

Builds compiled fine locally and in CI — the failure only appeared during App Store Connect validation after the archive was uploaded.

## Investigation

1. `gh run list --workflow=testflight.yml` showed all recent runs as `failure`
2. `gh run view <id> --log-failed` revealed the exact error in the export step
3. Searched codebase for HealthKit usage:
   - `HealthKitService.swift:36` calls `store.requestAuthorization(toShare: [], read: readTypes)`
   - The `toShare: []` means **no write access** is requested
4. Checked `Info.plist` — had `NSHealthShareUsageDescription` (read) but **not** `NSHealthUpdateUsageDescription` (write)

## Root Cause

App Store Connect's binary validation requires `NSHealthUpdateUsageDescription` even when the app passes an empty `toShare` set to `requestAuthorization(toShare:read:)`. The validator sees that the binary links HealthKit and the method signature includes `toShare`, so it demands the key regardless of runtime behavior.

This is a known Apple quirk — the validator is static, not runtime-aware.

## Solution

Added the missing key to both files (both must be updated since xcodegen regenerates Info.plist from project.yml):

**`ios/Robo/Info.plist`:**
```xml
<key>NSHealthUpdateUsageDescription</key>
<string>Robo does not write health data, but HealthKit requires this description.</string>
```

**`ios/project.yml`:**
```yaml
NSHealthUpdateUsageDescription: "Robo does not write health data, but HealthKit requires this description."
```

> **Important:** Never edit only Info.plist when using xcodegen — changes are overwritten on next `xcodegen generate`. Always update `project.yml` as the source of truth. See [xcodegen-drops-info-plist-keys](xcodegen-drops-info-plist-keys-testflight-compliance-20260210.md).

Commits: `e7791f5` (fix), `8a58730` (prevention)

## Prevention

Added automated validation of all required Info.plist privacy keys in two places:

**Local: `scripts/validate-build.sh`**
```bash
REQUIRED_PLIST_KEYS=(
    "NSCameraUsageDescription"
    "NSPhotoLibraryUsageDescription"
    "NSMotionUsageDescription"
    "NSHealthShareUsageDescription"
    "NSHealthUpdateUsageDescription"
    "NSBluetoothAlwaysUsageDescription"
    "NSLocationWhenInUseUsageDescription"
    "NSLocationAlwaysAndWhenInUseUsageDescription"
)
for KEY in "${REQUIRED_PLIST_KEYS[@]}"; do
    if ! grep -q "$KEY" "$PLIST_FILE"; then
        echo "FAIL: Missing $KEY in Info.plist (App Store will reject)"
    fi
done
```

**CI: `.github/workflows/testflight.yml`** (same check in "Validate build prerequisites" step)

This fails fast before the build+archive cycle, saving ~3 minutes of CI time per failure.

## Key Takeaway

When using HealthKit on iOS, **always include both** privacy keys in Info.plist:
- `NSHealthShareUsageDescription` — required for reading health data
- `NSHealthUpdateUsageDescription` — required even if `toShare` is empty (`[]`)

App Store Connect validates statically based on framework linkage, not runtime authorization parameters.

## Related

- [xcodegen drops Info.plist keys](xcodegen-drops-info-plist-keys-testflight-compliance-20260210.md) — always edit project.yml, not Info.plist directly
- [TestFlight encryption compliance bypass](testflight-encryption-compliance-bypass-20260210.md) — similar Info.plist key requirement
- [GitHub Actions TestFlight CI signing](github-actions-testflight-ci-signing-20260211.md) — CI pipeline setup
- GitHub Issue #5 — Deploy + TestFlight: first build submission
