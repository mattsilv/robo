# Fix CI TestFlight Signing

## Problem

`testflight.yml` archive succeeds but export fails:
```
error: exportArchive Cloud signing permission error
error: exportArchive No profiles for 'com.silv.Robo' were found
```

## Root Cause

Two issues discovered by research agents:

1. **"Cloud signing permission error"** — The App Store Connect API key may not have **Admin** role (required for cloud signing). Developer/App Manager roles fail silently.

2. **Provisioning profile not available** — `-allowProvisioningUpdates` with API key auth is [unreliable on ephemeral CI runners](https://developer.apple.com/forums/thread/688626). Cloud signing works locally because Xcode has a full account session; on CI with just an API key, the export phase frequently can't auto-create/download the distribution profile.

## Fix (Two Steps)

### Step 1: Verify API key has Admin role
- [ ] Go to https://appstoreconnect.apple.com/access/integrations/api
- [ ] Check the API key used for CI has **Admin** access (not Developer or App Manager)
- [ ] If not Admin, create a new key with Admin role and update secrets:
  - `APPSTORE_CONNECT_API_KEY_ID`
  - `APPSTORE_CONNECT_API_PRIVATE_KEY`

### Step 2: Add explicit provisioning profile (belt-and-suspenders)

Even with Admin API key, explicit profile is more reliable on ephemeral runners.

- [ ] Go to https://developer.apple.com/account/resources/profiles/list
- [ ] Create/download **App Store Distribution** profile for `com.silv.Robo`
  - Type: App Store Connect
  - App ID: com.silv.Robo
  - Certificate: Apple Distribution: OtoCo DE LLC (R3Z5CY34Q5)
- [ ] Base64-encode and add as secret:
  ```bash
  base64 -i ~/Downloads/Robo_AppStore.mobileprovision | gh secret set BUILD_PROVISION_PROFILE_BASE64 --repo mattsilv/robo
  ```
- [ ] Add workflow step in `testflight.yml` (after cert install, before archive):
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
- [ ] Add cleanup in the Cleanup step:
  ```yaml
  rm -f ~/Library/MobileDevice/Provisioning\ Profiles/build_pp.mobileprovision
  ```

### Step 3: Test
- [ ] `gh workflow run testflight.yml`
- [ ] Verify export + upload succeeds

## Why Local Deploy Works

| Aspect | Local (works) | CI (fails) |
|--------|--------------|------------|
| Auth | Full Xcode account session | API key only |
| Cloud signing | Xcode session has full access | "Cloud signing permission error" |
| Profile | Auto-created via Xcode session | Can't auto-create with API key |

## Optional: Remove simulator runtime download

The `xcodebuild -downloadPlatform iOS` step adds ~5 min to builds. With `-sdk iphoneos` set, it may no longer be needed. Test removing it after signing is fixed.

## References

- [GitHub Docs: Installing Apple cert on CI](https://docs.github.com/en/actions/deployment/deploying-xcode-applications/installing-an-apple-certificate-on-macos-runners-for-xcode-development)
- [WWDC21: Cloud signing](https://developer.apple.com/videos/play/wwdc2021/10204/)
- [Apple Forums: exportArchive fails on CI](https://developer.apple.com/forums/thread/688626)
- [Fastlane: Cloud signing limitations](https://github.com/fastlane/fastlane/discussions/19973)
