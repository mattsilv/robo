---
title: Share Extension Stale Device ID — Bearer Token Auth Fix
date: 2026-02-15
category: integration-issues
tags:
  - share-extension
  - authentication
  - device-registration
  - keychain
  - mcp
  - bearer-token
severity: high
affected_components:
  - ios/RoboShare/SharedKeychainHelper.swift
  - ios/RoboShare/ShareViewController.swift
  - workers/src/middleware/deviceAuth.ts
  - workers/src/routes/screenshots.ts
related_issues:
  - "#191"
  - "#185"
  - "#180"
related_prs:
  - "#192"
status: resolved
---

# Share Extension Stale Device ID — Bearer Token Auth Fix

## Problem

Screenshots shared via the iOS Share Extension were sometimes invisible to MCP queries. After device re-registration, the Share Extension could send a stale device ID (`X-Device-ID` header) because the shared keychain hadn't been updated by the main app. The MCP queried by the current device ID and found nothing.

**Reproduction:**
1. Re-register device (or fresh install)
2. Without opening the main app, share a screenshot via Share Extension
3. Ask Claude to get the screenshot via MCP — not found
4. Open the main app (tap Settings tab) — share again — works

## Root Cause

The Share Extension reads `SharedDeviceConfig` from the App Group keychain. This struct only contained `id` and `apiBaseURL`. The main app writes the full `DeviceConfig` (including `mcpToken`) to keychain on foreground, but the Share Extension is a **separate process** — it reads whatever was last written.

After re-registration, the new device ID is saved to keychain by the main app. But if the user shares a screenshot *before* foregrounding the app, the extension reads the old ID. The screenshot gets stored under device ID A, while MCP queries device ID B (resolved from the current token).

**Key insight:** iOS App Extensions and their host app share keychain data, but the data is only as fresh as the last write from the main app process.

## Solution

Use the MCP Bearer token (which never goes stale) to resolve the canonical device ID on the backend.

### 1. Add `mcpToken` to SharedDeviceConfig

```swift
// SharedKeychainHelper.swift
struct SharedDeviceConfig: Codable {
    var id: String
    var apiBaseURL: String
    var mcpToken: String?  // NEW — decoded from full DeviceConfig in keychain
}
```

The full `DeviceConfig` already stores `mcpToken` in keychain. Adding the field to `SharedDeviceConfig` lets the extension decode it automatically.

### 2. Share Extension sends Bearer token

```swift
// ShareViewController.swift — uploadImage()
request.setValue(config.id, forHTTPHeaderField: "X-Device-ID")
if let token = config.mcpToken {
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
}
```

### 3. Backend resolves device ID from token

```typescript
// deviceAuth.ts middleware
const authHeader = c.req.header('Authorization');
if (authHeader?.startsWith('Bearer ')) {
  const token = authHeader.slice(7);
  const tokenDevice = await c.env.DB.prepare(
    'SELECT id FROM devices WHERE mcp_token = ?'
  ).bind(token).first<{ id: string }>();

  if (tokenDevice) {
    c.set('resolvedDeviceId', tokenDevice.id);
    await next();
    return;
  }
}
// Fall back to X-Device-ID
```

### 4. Screenshot route uses resolved ID

```typescript
// screenshots.ts
const deviceId = c.get('resolvedDeviceId') ?? c.req.header('X-Device-ID')!;
```

## Why It Works

The MCP token is set at registration time and maps 1:1 to a device ID in the database. Even if the keychain has a stale device ID, the token resolves to the correct device. The backend trusts the token over the header.

## Backward Compatibility

Older app versions that don't send a Bearer token continue to work — the middleware falls back to `X-Device-ID` validation. New versions send both headers; the backend prefers the token when available.

## Prevention Strategies

1. **Never rely solely on static identifiers across process boundaries** — iOS extensions run in separate processes with eventually-consistent shared state
2. **Use tokens for identity resolution** — let the backend compute the device ID from the auth token, not the client
3. **Treat shared keychain as eventually consistent** — don't assume writes from the main app are immediately visible to extensions
4. **Log auth path taken** — when debugging, knowing whether Bearer or X-Device-ID was used reveals stale-data issues immediately

## Related Documentation

- [MCP device-scoped auth](../security/mcp-device-scoped-auth-bearer-token-20260214.md)
- [Keychain migration + screenshot privacy](../../plans/2026-02-15-fix-keychain-migration-screenshot-privacy-plan.md)
- [Share Extension implementation](../../plans/2026-02-15-feat-ios-share-extension-screenshot-to-agent-plan.md)
- [Stale DerivedData builds](../build-errors/stale-deriveddata-wrong-binary-installed-20260214.md)
- [Device ID proliferation fix (#185)](../integration-issues/device-id-proliferation-idempotent-registration-20260215.md)
