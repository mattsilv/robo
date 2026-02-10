---
title: "TestFlight CLI Export: Copy Failed at IPA Creation"
category: build-errors
date: 2026-02-10
tags: [testflight, xcodebuild, codesign, distribution-certificate, cli]
component: ios-build
severity: blocking
resolution_time: 20min
---

# TestFlight CLI Export: Copy Failed at IPA Creation

## Problem

`xcodebuild -exportArchive` fails with "Copy failed" at the `IDEDistributionCreateIPAStep` when trying to export an archive for App Store Connect / TestFlight upload via CLI.

## Symptoms

- `error: exportArchive Copy failed` with no other useful error message
- Distribution logs show `IDEDistributionPackagingStep` or `IDEDistributionCreateIPAStep` failing
- Codesign step succeeds (app is signed) but IPA creation fails
- The `ExportOptions.plist` method `app-store` is deprecated (should be `app-store-connect`)

## Root Cause

No Apple Distribution certificate installed in the local keychain. Only Apple Development certificates were present. The CLI export process attempts cloud signing but fails silently at the IPA packaging step. The error message "Copy failed" is misleading — it's actually a signing/packaging issue.

## Investigation Steps

1. Checked distribution logs at `/var/folders/.../Robo_*.xcdistributionlogs/`
2. Found `IDEDistributionCreateIPAStep` failing after successful codesign
3. Ran `security find-identity -v -p codesigning` — only Development certs, no Distribution cert
4. The verbose log showed Xcode found "Apple Distribution: OtoCo DE LLC" via cloud signing but the local packaging step still failed

## Solution

Use Xcode Organizer GUI instead of CLI for TestFlight uploads when no local Distribution certificate is installed:

```bash
# Build the archive via CLI (this works fine with Development cert)
cd ios
xcodebuild archive \
  -scheme Robo -configuration Release \
  -archivePath ./build/Robo.xcarchive \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=R3Z5CY34Q5

# Open in Xcode Organizer (handles cloud signing automatically)
open ./build/Robo.xcarchive

# Then: Distribute App → TestFlight Internal Testing → Distribute
```

## Alternative Fix (For Full CLI Automation)

Install an Apple Distribution certificate locally:

1. Go to https://developer.apple.com/account/resources/certificates/add
2. Create "Apple Distribution" certificate
3. Download and double-click to install in Keychain
4. Then `xcodebuild -exportArchive` will work via CLI

## Also Fix: Update ExportOptions.plist

The `app-store` method is deprecated, use `app-store-connect`:

```xml
<key>method</key>
<string>app-store-connect</string>
```

And remove `uploadBitcode` key (deprecated in Xcode 16+).

## Prevention

- Always verify `security find-identity -v -p codesigning` includes a Distribution cert before attempting CLI export
- Use Xcode Organizer as fallback — it handles cloud signing seamlessly
- Keep ExportOptions.plist up to date with current Xcode conventions

## Related Issues

- This is common when working on a new machine or after a fresh macOS install
- Cloud signing works great in Xcode GUI but has limitations with CLI workflows
- The misleading "Copy failed" error masks the real signing/certificate issue
