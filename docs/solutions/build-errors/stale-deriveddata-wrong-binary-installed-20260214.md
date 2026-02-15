---
title: Stale DerivedData from Multiple Branches Deployed via CLI Install
date: 2026-02-14
category: build-errors
severity: high
component: iOS CLI deployment (xcodebuild + devicectl)
tags:
  - xcodebuild
  - DerivedData
  - device-install
  - nondeterministic-behavior
  - branch-switching
related_issues:
  - fix/registration-error-diagnostics
symptoms:
  - App on device shows old UI despite current source code changes
  - Build succeeds but changes don't appear on device
  - Behavior varies randomly between install attempts
root_cause: "Multiple Robo-* DerivedData directories from different branches accumulated; nondeterministic find | head -1 picked stale builds instead of current branch's latest"
---

# Stale DerivedData — Wrong Binary Installed on Physical Device

## Problem Statement

iOS app installed on physical device displayed outdated UI despite correct source code on the active branch. Edits to `SettingsView.swift` (section renames: "Device" to "My Mobile Device", "Scanner" to "Barcode Scanner", "Beacons" to "Bluetooth Beacons", plus new build string and website link) were not reflected on the device after a successful build and install.

## Investigation Steps

1. **Verified source code** — confirmed all changes present on the `fix/registration-error-diagnostics` branch
2. **Build succeeded** — `xcodebuild` completed with no errors
3. **Discovered 8 DerivedData directories** — `ls ~/Library/Developer/Xcode/DerivedData/Robo-*` revealed 8 separate directories with unique hash suffixes
4. **Identified stale artifact selection** — the install command used `find ... | head -1` which picked a `.app` bundle from an older branch's build
5. **Confirmed root cause** — after cleaning DerivedData and rebuilding, the correct UI appeared

## Root Cause Analysis

Xcode creates uniquely-hashed DerivedData directories for each project configuration (branch, worktree, scheme variation). These directories accumulate over time and are **never automatically cleaned**. The install command:

```bash
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Robo-*/Build/Products/Debug-iphoneos -name "Robo.app" -maxdepth 1 | head -1)
```

`find | head -1` returns results in **arbitrary order** — when multiple matching `.app` bundles exist, it often returns an older build rather than the freshly-compiled one.

## Working Solution

```bash
# Step 1: Remove all stale Robo DerivedData directories
rm -rf ~/Library/Developer/Xcode/DerivedData/Robo-*

# Step 2: Regenerate Xcode project from project.yml
cd ios && xcodegen generate

# Step 3: Build fresh from clean state
xcodebuild -scheme Robo -configuration Debug \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  CODE_SIGN_IDENTITY="Apple Development" \
  DEVELOPMENT_TEAM=R3Z5CY34Q5

# Step 4: Install using modification-time-sorted path (newest first)
APP_PATH=$(ls -dt ~/Library/Developer/Xcode/DerivedData/Robo-*/Build/Products/Debug-iphoneos/Robo.app | head -1)
xcrun devicectl device install app --device $DEVICE_ID "$APP_PATH"

# Step 5: Launch
xcrun devicectl device process launch --device $DEVICE_ID com.silv.Robo
```

### Key Fix

Replace nondeterministic `find | head -1` with `ls -dt | head -1`. The `-dt` flags sort by modification time (newest first), so `head -1` reliably returns the most recently built `.app` bundle.

## Prevention Strategies

### Immediate (applied)

- Updated `CLAUDE.md` build commands with explicit `rm -rf` cleanup step
- Fixed install command to use `ls -dt` (newest first) instead of `find | head -1`
- Added gotcha to Critical Gotchas section

### Process

- **Before every device build after branch switch:** run `rm -rf ~/Library/Developer/Xcode/DerivedData/Robo-*`
- **Standard sequence:** xcodegen generate -> clean DerivedData -> build -> install

### Detection Signals

| Signal | Interpretation |
|--------|----------------|
| UI doesn't match source code after install | Stale binary installed |
| Build succeeds but changes don't appear | Old artifact picked up |
| Multiple `Robo-*` dirs in DerivedData | Cleanup overdue |
| App behavior contradicts recent commits | Almost certainly stale binary |

**Quick check:** `ls -dt ~/Library/Developer/Xcode/DerivedData/Robo-* | wc -l` — if >1, cleanup is needed.

### Verification After Fix

```bash
# Confirm only one DerivedData directory exists
ls ~/Library/Developer/Xcode/DerivedData/Robo-* 2>/dev/null | wc -l  # Should be 1

# Check .app modification timestamp matches build time
ls -la ~/Library/Developer/Xcode/DerivedData/Robo-*/Build/Products/Debug-iphoneos/Robo.app
```

## Related Documentation

- [homebrew-rsync-xcode-export-archive-fix-20260210.md](homebrew-rsync-xcode-export-archive-fix-20260210.md) — another build artifact issue (rsync version mismatch breaks export)
- [post-merge-url-migration-issue-triage-20260214.md](../integration-issues/post-merge-url-migration-issue-triage-20260214.md) — stale URL references across codebase (similar "stale data" pattern)
- CLAUDE.md Critical Gotchas section — documents this fix inline with build commands
