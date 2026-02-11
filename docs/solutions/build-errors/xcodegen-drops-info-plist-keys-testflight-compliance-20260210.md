---
title: "xcodegen drops Info.plist keys — TestFlight Missing Compliance"
category: build-errors
date: 2026-02-10
component: ios-build
tags: [xcodegen, info-plist, testflight, encryption-compliance, project-yml]
severity: high
symptoms: ["Missing Compliance in TestFlight", "ITSAppUsesNonExemptEncryption missing", "TestFlight build stuck"]
---

# xcodegen drops Info.plist keys — TestFlight Missing Compliance

## Problem

After uploading builds to TestFlight, they show "Missing Compliance" status and can't be distributed to testers. This happened even though the encryption compliance key was previously added to Info.plist in PR #32.

## Symptoms

- TestFlight dashboard shows "Missing Compliance" with a yellow warning triangle
- Build uploads succeed but get stuck at compliance step
- Clicking "Manage" requires manually answering encryption questions each time
- The `ITSAppUsesNonExemptEncryption` key exists in the git-committed Info.plist but disappears after building

## Root Cause

When using xcodegen, the `Info.plist` file is **regenerated from `project.yml`** every time `xcodegen generate` runs. Any keys added directly to Info.plist (outside of project.yml) are silently dropped.

PR #32 added `ITSAppUsesNonExemptEncryption` directly to `ios/Robo/Info.plist`, but the very next `xcodegen generate` overwrote it with a freshly generated Info.plist that only contained keys defined in `project.yml`.

**The trap**: The key existed in git, so it appeared to be committed. But xcodegen overwrites Info.plist on every generation, making direct edits ephemeral.

## Solution

Add the key to `project.yml` under `info.properties` so xcodegen always includes it:

```yaml
# ios/project.yml
targets:
  Robo:
    info:
      path: Robo/Info.plist
      properties:
        ITSAppUsesNonExemptEncryption: false   # <-- Add here, NOT in Info.plist directly
        NSCameraUsageDescription: "..."
        # ... other keys
```

After this change, `xcodegen generate` will always produce an Info.plist that includes the encryption compliance key.

## Prevention

1. **NEVER edit Info.plist directly** when using xcodegen — always edit `project.yml`
2. Info.plist is a generated artifact; treat it like a build output
3. To verify: run `xcodegen generate` then `grep ITSApp ios/Robo/Info.plist` — if the key is missing, it's not in project.yml
4. Consider adding a CI check: after `xcodegen generate`, verify critical keys exist in the output Info.plist

## Context from Apple Docs

The `ITSAppUsesNonExemptEncryption` key set to `false` tells App Store Connect that the app doesn't use non-exempt encryption, bypassing the manual compliance questionnaire. Without it, every build requires manual intervention in App Store Connect before it can be distributed via TestFlight.

## Related Docs

- [testflight-encryption-compliance-bypass-20260210.md](testflight-encryption-compliance-bypass-20260210.md)
- [homebrew-rsync-xcode-export-archive-fix-20260210.md](homebrew-rsync-xcode-export-archive-fix-20260210.md)
