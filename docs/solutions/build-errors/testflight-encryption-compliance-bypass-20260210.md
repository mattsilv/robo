---
title: "TestFlight: Skip Encryption Compliance Dialog via Info.plist"
category: build-errors
date: 2026-02-10
tags: [testflight, encryption, compliance, info-plist, app-store-connect]
component: ios-deployment
severity: minor
resolution_time: 2min
---

# TestFlight: Skip Encryption Compliance Dialog via Info.plist

## Problem

Every time a new build is uploaded to App Store Connect for TestFlight, Apple presents an "App Encryption Documentation" dialog that must be manually answered in App Store Connect before the build becomes available for testing.

This blocks testers from accessing new builds immediately and slows down the feedback loop during development.

## Symptoms

- Build shows "Missing Compliance" status after upload
- Build doesn't appear in TestFlight app until manual action is taken
- App Store Connect displays: "What type of encryption does your app implement?"
- Options shown: proprietary encryption, standard encryption, both, or none
- Dialog must be answered before build reaches "Ready to Test" state

## Root Cause / Explanation

Apple requires all apps distributed on iOS to declare encryption usage for US export compliance (ITAR/EAR regulations). This is a legal requirement for apps handling cryptographic technology.

By default, App Store Connect requires a manual declaration for each build. However, if an app only uses standard HTTPS encryption (provided by URLSession) and doesn't implement custom encryption beyond Apple's built-in security frameworks (CommonCrypto, Security.framework), you can declare this at build time via Info.plist, eliminating the manual dialog.

## Solution

Add the `ITSAppUsesNonExemptEncryption` key to `Info.plist` and set it to `false`:

```xml
<key>ITSAppUsesNonExemptEncryption</key>
<false/>
```

**Location:** `ios/Robo/Resources/Info.plist` (or your app's Info.plist)

**Example in context:**
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleName</key>
    <string>$(PRODUCT_NAME)</string>
    <key>CFBundlePackageType</key>
    <string>$(PRODUCT_BUNDLE_PACKAGE_TYPE)</string>

    <!-- Encryption compliance: set to false if app only uses standard HTTPS -->
    <key>ITSAppUsesNonExemptEncryption</key>
    <false/>

    <!-- ... rest of keys ... -->
</dict>
</plist>
```

**Result:** When you upload the next build to App Store Connect, the encryption compliance dialog is skipped automatically, and the build moves directly to "Ready to Test" status.

## When to Use `false` vs `true`

### Use `false` if your app:
- Only uses standard HTTPS for API calls (URLSession)
- Uses Apple's built-in security APIs (CommonCrypto, Security.framework)
- Doesn't implement custom encryption algorithms
- Doesn't use third-party crypto libraries (like `CryptoKit` beyond standard use)

### Use `true` if your app:
- Implements custom encryption algorithms
- Uses third-party cryptographic libraries
- Needs to provide encryption documentation to Apple
- Has specific export compliance requirements

For the Robo app in M1, `false` is correct since all network calls use standard URLSession with HTTPS.

## Prevention

Always add `ITSAppUsesNonExemptEncryption` to Info.plist at project setup time. This is especially important for hackathon/rapid development workflows where you're uploading builds frequently to TestFlight.

**Pro tip:** If using xcodegen, add this to your `project.yml` under the target's info dictionary:
```yaml
targets:
  Robo:
    info:
      ITSAppUsesNonExemptEncryption: false
```

This ensures the key is generated consistently across all builds.

## Related Docs

- [TestFlight: CLI Export Copy Failed](testflight-cli-export-copy-failed-20260210.md)
- [App Store Connect: New App Setup](app-store-connect-new-app-setup-20260210.md)
