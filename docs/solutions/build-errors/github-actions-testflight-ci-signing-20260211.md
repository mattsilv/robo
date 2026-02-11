---
title: "GitHub Actions TestFlight CI: Archive + Export Signing Failures"
category: build-errors
component: ci/cd
date: 2026-02-11
symptoms:
  - "CompileAssetCatalog: No simulator runtime version available"
  - "exportArchive Cloud signing permission error"
  - "exportArchive No profiles for 'com.silv.Robo' were found"
root_causes:
  - Xcode 16.2 actool requires simulator runtime even for device archives
  - App Store Connect API key lacks Admin role for cloud signing
  - "-allowProvisioningUpdates unreliable on ephemeral CI runners"
resolution: install-simulator-runtime, explicit-provisioning-profile, admin-api-key
---

# GitHub Actions TestFlight CI: Archive + Export Signing Failures

## Problem

Three cascading failures when setting up `testflight.yml` on GitHub Actions with `macos-15` runner + Xcode 16.2:

### Failure 1: Asset Catalog SDK Mismatch (Archive)
```
error: No simulator runtime version from [22F77, 22G86, 23B86, 23C54]
available to use with iphonesimulator SDK version 22C146
```

### Failure 2: Cloud Signing Permission (Export)
```
error: exportArchive Cloud signing permission error
```

### Failure 3: Missing Provisioning Profile (Export)
```
error: exportArchive No profiles for 'com.silv.Robo' were found
```

## Root Causes

| Failure | Root Cause |
|---------|-----------|
| Asset catalog | `actool` resolves simulator SDKs even for device builds; `macos-15` runner's pre-installed runtimes don't match Xcode 16.2's SDK |
| Cloud signing | API key had Developer role, not Admin (required for cloud signing) |
| No profiles | `-allowProvisioningUpdates` is [unreliable on ephemeral runners](https://developer.apple.com/forums/thread/688626) — can't auto-create distribution profiles with API-key-only auth |

### Why Local Deploy Works But CI Doesn't

| Aspect | Local | CI |
|--------|-------|-----|
| Auth | Full Xcode account session | API key (.p8) only |
| Cloud signing | Xcode session has full access | Fails without Admin key |
| Profile creation | Auto-created via Xcode session | Can't auto-create on ephemeral runner |
| Simulator runtimes | All installed with Xcode | Mismatched on `macos-15` runner |

## Solution

### Fix 1: Install iOS Simulator Runtime
```yaml
- name: Install iOS simulator runtime
  run: xcodebuild -downloadPlatform iOS -quiet || true
```
Plus add `-sdk iphoneos` to the `xcodebuild archive` command.

### Fix 2: Create Admin API Key
1. Go to https://appstoreconnect.apple.com/access/integrations/api
2. Create new key with **Admin** role
3. Download `.p8` immediately (only available once)
4. Update secrets: `APPSTORE_CONNECT_API_KEY_ID`, `APPSTORE_CONNECT_API_PRIVATE_KEY`

### Fix 3: Install Explicit Provisioning Profile
1. Create App Store Distribution profile at https://developer.apple.com/account/resources/profiles/list
2. Base64-encode and upload:
   ```bash
   base64 -i profile.mobileprovision | gh secret set BUILD_PROVISION_PROFILE_BASE64
   ```
3. Add workflow step:
   ```yaml
   - name: Install provisioning profile
     env:
       BUILD_PROVISION_PROFILE_BASE64: ${{ secrets.BUILD_PROVISION_PROFILE_BASE64 }}
     run: |
       PP_PATH=$RUNNER_TEMP/build_pp.mobileprovision
       echo -n "$BUILD_PROVISION_PROFILE_BASE64" | base64 --decode -o "$PP_PATH"
       mkdir -p ~/Library/MobileDevice/Provisioning\ Profiles
       cp "$PP_PATH" ~/Library/MobileDevice/Provisioning\ Profiles
   ```

### Required Secrets (7 total)
| Secret | Purpose |
|--------|---------|
| `BUILD_CERTIFICATE_BASE64` | Apple Distribution cert (.p12), base64 |
| `P12_PASSWORD` | Password for the .p12 file |
| `KEYCHAIN_PASSWORD` | Temp keychain password (any value) |
| `BUILD_PROVISION_PROFILE_BASE64` | App Store provisioning profile, base64 |
| `APPSTORE_CONNECT_API_KEY_ID` | API key ID (must be Admin role) |
| `APPSTORE_CONNECT_API_ISSUER_ID` | Issuer UUID from App Store Connect |
| `APPSTORE_CONNECT_API_PRIVATE_KEY` | Contents of AuthKey_*.p8 file |

## Investigation Timeline

1. `xcpretty || true` masked real errors — replaced with `tee` + `tail` for raw logs
2. `-sdk iphoneos` didn't fix actool alone — needed simulator runtime install too
3. Archive passed after runtime fix — export then failed with new signing errors
4. Distribution cert uploaded — export still failed (cloud signing permission)
5. Provisioning profile added + Admin API key — **build succeeded**

## Prevention

- Always use explicit provisioning profile on CI (don't rely on `-allowProvisioningUpdates` for export)
- API keys for CI must have **Admin** role
- Never pipe xcodebuild through `xcpretty || true` — it swallows errors
- Store `.p8` keys in `.gitignore` (`**/*.p8`, `private_keys/`)

## Related Docs

- [homebrew-rsync-xcode-export-archive-fix](homebrew-rsync-xcode-export-archive-fix-20260210.md) — PATH stripping for local exports
- [testflight-cli-export-copy-failed](testflight-cli-export-copy-failed-20260210.md) — Missing distribution cert locally
- [testflight-encryption-compliance-bypass](testflight-encryption-compliance-bypass-20260210.md) — ITSAppUsesNonExemptEncryption

## References

- [GitHub Docs: Installing Apple cert on CI](https://docs.github.com/en/actions/deployment/deploying-xcode-applications/installing-an-apple-certificate-on-macos-runners-for-xcode-development)
- [WWDC21: Cloud signing](https://developer.apple.com/videos/play/wwdc2021/10204/)
- [Apple Forums: exportArchive fails on CI](https://developer.apple.com/forums/thread/688626)
- [Fastlane: Cloud signing limitations](https://github.com/fastlane/fastlane/discussions/19973)
