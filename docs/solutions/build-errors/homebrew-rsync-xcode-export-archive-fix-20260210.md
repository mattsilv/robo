---
title: "Homebrew rsync breaks Xcode exportArchive for TestFlight"
category: build-errors
date: 2026-02-10
component: ios-build
tags: [xcode, rsync, homebrew, testflight, export-archive, cli]
severity: critical
symptoms: ["exportArchive Copy failed", "rsync error syntax or usage error", "--extended-attributes unknown option"]
---

# Homebrew rsync breaks Xcode exportArchive for TestFlight

## Problem

`xcodebuild -exportArchive` fails with a "Copy failed" error when trying to export an archive for App Store Connect / TestFlight upload. The archive step succeeds fine — only the export step fails.

## Symptoms

- `xcodebuild -exportArchive` outputs:
  ```
  error: exportArchive Copy failed
  ** EXPORT FAILED **
  ```
- Distribution log shows:
  ```
  rsync error: syntax or usage error (code 1) at main.c(1802) [server=3.4.1]
  rsync: on remote machine: --extended-attributes: unknown option
  ```
- The archive step (`xcodebuild archive`) completes successfully with no issues.
- Only the export/upload step fails.

## Root Cause

Homebrew's rsync (version 3.4.1, installed at `/opt/homebrew/bin/rsync`) conflicts with Apple's openrsync (`/usr/bin/rsync`).

Here is what happens during IPA creation:

1. Xcode uses `/usr/bin/rsync` (Apple's openrsync) as the **client** side of the rsync transfer.
2. The client passes `--extended-attributes`, which is an Apple-specific flag supported by openrsync.
3. When rsync launches the **server** side of the transfer, it searches `PATH` for the `rsync` binary.
4. If Homebrew's rsync comes first in `PATH` (which it does by default on Apple Silicon Macs with Homebrew), the server side runs Homebrew rsync 3.4.1.
5. Homebrew rsync 3.4.1 does **not** understand the `--extended-attributes` flag, so it exits with a syntax/usage error.
6. The copy fails and `xcodebuild -exportArchive` reports `EXPORT FAILED`.

The mismatch between Apple's openrsync (client) and Homebrew's rsync (server) is the core issue.

## Solution

Strip Homebrew from `PATH` when running the export command so that both client and server use Apple's `/usr/bin/rsync`:

```bash
PATH="/usr/bin:/bin:/usr/sbin:/sbin" xcodebuild -exportArchive \
  -archivePath /tmp/Robo.xcarchive \
  -exportPath /tmp/RoboExport \
  -exportOptionsPlist /tmp/ExportOptions.plist \
  -allowProvisioningUpdates
```

This ensures `/usr/bin/rsync` (openrsync) is used for both sides of the transfer, and `--extended-attributes` is understood correctly.

## Full TestFlight CLI Workflow

Complete end-to-end workflow to build, archive, export, and upload to TestFlight from the command line with no Xcode UI:

```bash
# 1. Bump CURRENT_PROJECT_VERSION in project.yml
# 2. Regenerate the Xcode project
cd ios && xcodegen generate

# 3. Archive
xcodebuild archive -scheme Robo -archivePath /tmp/Robo.xcarchive \
  -destination 'generic/platform=iOS' -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=R3Z5CY34Q5

# 4. Export + upload (MUST strip Homebrew from PATH)
PATH="/usr/bin:/bin:/usr/sbin:/sbin" xcodebuild -exportArchive \
  -archivePath /tmp/Robo.xcarchive -exportPath /tmp/RoboExport \
  -exportOptionsPlist /tmp/ExportOptions.plist -allowProvisioningUpdates
```

## ExportOptions.plist

Save this as `/tmp/ExportOptions.plist` (or wherever you prefer):

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>method</key>
  <string>app-store-connect</string>
  <key>teamID</key>
  <string>R3Z5CY34Q5</string>
  <key>signingStyle</key>
  <string>automatic</string>
  <key>destination</key>
  <string>upload</string>
</dict>
</plist>
```

Key points about ExportOptions.plist:
- Use `app-store-connect` (not `app-store`) as the method.
- Do **not** include `uploadBitcode` — it is deprecated and will cause errors.
- `destination: upload` tells Xcode to upload directly to App Store Connect after export.

## Prevention

- **Always** use `PATH="/usr/bin:/bin:/usr/sbin:/sbin"` as a prefix on `xcodebuild -exportArchive` commands.
- Alternatively, uninstall Homebrew rsync if you do not need it: `brew uninstall rsync`.
- Check which rsync is active: `which rsync`. If it shows `/opt/homebrew/bin/rsync`, you will hit this issue.

## How to Find the Error

When `xcodebuild -exportArchive` fails, it prints a path to the distribution logs in its output. Look for something like:

```
/var/folders/.../IDEDistribution/
```

Inside that directory, check `IDEDistributionPipeline.log` and grep for "rsync":

```bash
grep rsync /var/folders/.../IDEDistribution/IDEDistributionPipeline.log
```

This will surface the actual rsync error message showing the version mismatch and the `--extended-attributes: unknown option` failure.

## Environment

- macOS 15 (Sequoia) on Apple Silicon
- Xcode 16+
- Homebrew rsync 3.4.1 at `/opt/homebrew/bin/rsync`
- Apple openrsync at `/usr/bin/rsync`

## Related

- [TestFlight CLI Export Copy Failed](testflight-cli-export-copy-failed-20260210.md) — earlier troubleshooting of the same symptom before root cause was identified
- [App Store Connect New App Setup](app-store-connect-new-app-setup-20260210.md) — setting up the app in ASC for the first time
