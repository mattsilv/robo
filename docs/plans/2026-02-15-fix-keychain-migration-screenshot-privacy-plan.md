---
title: "fix: Keychain migration backwards compat + screenshot R2 auto-expiry"
type: fix
status: active
date: 2026-02-15
---

# fix: Keychain migration backwards compat + screenshot R2 auto-expiry

## Overview

Three related issues surfaced after PR #179 (Share Extension):

1. **Keychain migration bug**: Adding `kSecAttrAccessGroup` to `KeychainHelper` made pre-163 keychain entries invisible, causing the app to re-register with a new device ID instead of preserving the existing one. MCP still uses the old device ID → screenshots uploaded by the share extension are invisible to agents.
2. **No tests for keychain migration**: The migration path (keychain access group change) has no test coverage.
3. **Screenshot privacy**: Screenshots stored in R2 persist forever. User explicitly doesn't want liability for people's private data on the cloud — screenshots should auto-expire.

## Problem Analysis

### Root Cause: Device ID Mismatch

```
Before build 163:
  KeychainHelper.save() → kSecClassGenericPassword (NO access group)
  KeychainHelper.load() → queries WITHOUT access group → finds entry ✓

After build 163 (PR #179):
  KeychainHelper.save() → kSecClassGenericPassword + accessGroup "R3Z5CY34Q5.group.com.silv.Robo"
  KeychainHelper.load() → queries WITH access group → old entry invisible ✗
  → Falls to UserDefaults → loads config → save() writes NEW keychain entry with access group
  → BUT if UserDefaults was stale/missing, falls to .default → bootstrap() → NEW device ID
```

The user's phone went: keychain miss → UserDefaults miss (or stale) → `.default` → `bootstrap()` → new UUID `a6fd7c15`. Meanwhile MCP token in Claude still points to old device `9a9064d9`.

### Fix Strategy

`KeychainHelper.load()` must try **with** access group first, then fall back to **without** access group (same pattern already implemented in `SharedKeychainHelper` in the worktree). If found via legacy path, immediately re-save with the new access group (migrate in place).

## Acceptance Criteria

### Phase 1: Keychain Migration Fix
- [ ] `KeychainHelper.load()` tries with access group, then without (backwards compat) — `ios/Robo/Services/KeychainHelper.swift`
- [ ] When legacy entry found, re-save with access group (migrate in place)
- [ ] Delete legacy entry after successful migration to avoid duplicates
- [ ] `SharedKeychainHelper.load()` already has fallback (confirmed in worktree) — commit it

### Phase 2: Tests
- [ ] Add `KeychainMigrationTests.swift` testing:
  - Legacy keychain entry (no access group) is found and migrated
  - Device ID is preserved through migration (not re-registered)
  - Post-migration, entry is readable with access group
  - Fresh install (no legacy entry) still works
- [ ] Add test to `DeviceServiceTests.swift`:
  - `init()` with keychain miss but UserDefaults hit preserves device ID
  - `init()` with both miss creates default (unregistered)

### Phase 3: Screenshot R2 Auto-Expiry
- [ ] Add R2 lifecycle rule: prefix `screenshots/` → delete after 7 days
- [ ] Add cleanup of D1 `sensor_data` rows for expired screenshots (Workers cron or on-read check)
- [ ] Document: screenshots are transient, not permanent storage
- [ ] Consider: save screenshot locally on device (app sandbox) if user wants to keep it

## Technical Approach

### KeychainHelper Migration (`ios/Robo/Services/KeychainHelper.swift`)

```swift
static func load() -> DeviceConfig? {
    // Try with access group first (build 163+)
    if let config = query(accessGroup: accessGroup) {
        return config
    }
    // Fallback: try without access group (pre-163 keychain entries)
    if let config = query(accessGroup: nil) {
        // Migrate: re-save with access group, delete legacy
        save(config)
        deleteLegacy()
        return config
    }
    return nil
}

private static func query(accessGroup: String?) -> DeviceConfig? {
    var q: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        kSecReturnData as String: true,
        kSecMatchLimit as String: kSecMatchLimitOne,
    ]
    if let accessGroup { q[kSecAttrAccessGroup as String] = accessGroup }
    var result: AnyObject?
    guard SecItemCopyMatching(q as CFDictionary, &result) == errSecSuccess,
          let data = result as? Data else { return nil }
    return try? JSONDecoder().decode(DeviceConfig.self, from: data)
}

private static func deleteLegacy() {
    let q: [String: Any] = [
        kSecClass as String: kSecClassGenericPassword,
        kSecAttrService as String: service,
        kSecAttrAccount as String: account,
        // NO access group — targets legacy entry
    ]
    SecItemDelete(q as CFDictionary)
}
```

### R2 Lifecycle Rule

Cloudflare R2 supports [object lifecycle rules](https://developers.cloudflare.com/r2/buckets/object-lifecycles/) natively. Configure via wrangler or dashboard:

```bash
# Via wrangler CLI (or dashboard)
# Rule: delete objects with prefix "screenshots/" after 7 days
wrangler r2 bucket lifecycle set robo-data \
  --rule '{"id":"screenshot-expiry","enabled":true,"conditions":{"prefix":"screenshots/"},"action":{"type":"Delete","afterDays":7}}'
```

7 days gives enough buffer for:
- Agent to fetch screenshot via MCP `get_screenshot` tool
- User to re-share if needed
- Debugging if something goes wrong

### D1 Cleanup

Add a check in `get_screenshot` MCP tool: if R2 object is gone (expired), return helpful message instead of error. Optionally add a Workers cron to clean up orphaned D1 rows.

## Files to Modify

| File | Change |
|------|--------|
| `ios/Robo/Services/KeychainHelper.swift` | Add fallback load without access group, migrate-in-place |
| `ios/RoboShare/SharedKeychainHelper.swift` | Commit existing fallback changes from worktree |
| `ios/RoboShare/ShareViewController.swift` | Commit existing debug improvements from worktree |
| `ios/RoboTests/DeviceServiceTests.swift` | Add keychain migration test scenarios |
| `workers/src/mcp.ts` | Handle expired R2 screenshots gracefully in `get_screenshot` |
| R2 bucket config | Add lifecycle rule for `screenshots/` prefix |

## Dependencies & Risks

- **R2 lifecycle rules**: Objects typically removed within 24 hours of expiration — not instant
- **Keychain migration**: One-time operation per device. If it fails, UserDefaults fallback still works
- **Device ID mismatch for existing users**: After migration fix, the user's current device (`a6fd7c15`) is the "real" one. Old MCP token (`9a9064d9`) needs to be updated — user should re-register in Settings to get new MCP token pointing to current device

## References

- PR #179: Share Extension implementation
- `ios/Robo/Services/DeviceService.swift:18-36` — init migration flow
- `ios/RoboTests/DeviceServiceTests.swift` — existing reRegister tests
- [Cloudflare R2 Object Lifecycles](https://developers.cloudflare.com/r2/buckets/object-lifecycles/)
- `docs/solutions/data-migration/PATTERN_SUMMARY.md` — related migration patterns
