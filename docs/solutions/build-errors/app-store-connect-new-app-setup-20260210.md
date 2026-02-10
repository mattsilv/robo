---
title: "App Store Connect: New App Setup for TestFlight"
category: build-errors
date: 2026-02-10
tags: [app-store-connect, testflight, bundle-id, apple-developer]
component: ios-deployment
severity: blocking
resolution_time: 15min
---

# App Store Connect: New App Setup for TestFlight

**Problem:** Cannot create a new app in App Store Connect because the Bundle ID dropdown is empty — the Bundle ID must be registered separately in the Apple Developer portal first.

**Symptoms:**
- App Store Connect → My Apps → New App shows "Choose" in Bundle ID dropdown
- No option to type a custom Bundle ID

**Solution — Step by Step:**

## 1. Register Bundle ID (Apple Developer Portal)
Go to https://developer.apple.com/account/resources/identifiers/add/bundleId

- Platform: iOS, iPadOS, macOS, tvOS, watchOS, visionOS (default)
- Description: `Robo`
- Bundle ID: Explicit → `com.silv.Robo`
- Capabilities: Leave defaults (Camera access is via Info.plist, not App ID capabilities)
- Click Continue → Register

## 2. Create App Record (App Store Connect)
Go to https://appstoreconnect.apple.com → My Apps → "+"

- Platform: iOS
- Name: Must be unique on App Store (we used "ROBO.APP" since "Robo" was taken)
- Primary Language: English (U.S.)
- Bundle ID: Select `com.silv.Robo` from dropdown (now appears after step 1)
- SKU: `robo` (internal identifier, never shown to users)
- User Access: Full Access

## 3. Generate App-Specific Password (for CLI uploads)
Go to https://account.apple.com → Sign-In and Security → App-Specific Passwords → "+"

- Name it descriptively (e.g., "robo-upload")
- Save the password securely (shown once)

## Key Details for Robo
- **App Name:** ROBO.APP
- **App ID:** 6759011077
- **Bundle ID:** com.silv.Robo
- **SKU:** robo
- **Apple ID:** matt@argentlabs.xyz
- **Team:** OtoCo DE LLC (R3Z5CY34Q5)
- **Dashboard:** https://appstoreconnect.apple.com/apps/6759011077/distribution/ios/version/inflight

## Common Gotchas
- Bundle ID registration is in the **Apple Developer portal** (developer.apple.com), NOT App Store Connect (appstoreconnect.apple.com) — they're separate sites
- Camera/sensor permissions are configured via Info.plist, not App ID capabilities
- App name must be globally unique on the App Store
- SKU is just an internal identifier — use something simple like the app name

## Related Resources
- [Apple Developer Portal](https://developer.apple.com/account/)
- [App Store Connect](https://appstoreconnect.apple.com/)
- [TestFlight Documentation](https://developer.apple.com/testflight/)
