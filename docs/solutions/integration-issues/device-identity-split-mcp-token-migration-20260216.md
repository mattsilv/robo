---
title: MCP Screenshots Lost After Vendor ID Device Registration Migration
date: 2026-02-16
category: integration-issues
severity: high
component: [iOS device registration, Workers API, MCP protocol, D1 database]
symptoms:
  - MCP screenshot uploads fail silently
  - Screenshots appear in app but not accessible via MCP tools
  - Device records duplicated after vendor_id migration
  - get_device_info shows stale or missing screenshot timestamps
root_cause: Vendor ID migration created new device record instead of adopting existing device. MCP token bound to legacy device (NULL vendor_id), but screenshots uploaded to new device (with vendor_id).
resolution: Legacy device adoption in registration endpoint + MCP health check for future detection
tags: [device-registration, vendor-id, mcp, data-consistency, migration, ios-workers-sync]
---

# MCP Screenshots Lost After Vendor ID Device Registration Migration

## Problem Symptom

After deploying vendor_id-based idempotent registration (PR #185), MCP screenshots stopped working. The app appeared functional — screenshots uploaded successfully — but MCP tools (`get_screenshot`, `get_latest_capture`) returned no data.

**Observable behavior:**
1. iOS app registers with `vendor_id` → backend creates NEW device record
2. Screenshots upload to new device ID
3. MCP authenticates with old `mcp_token` → resolves to OLD device ID (no vendor_id)
4. MCP queries old device's data → finds nothing

## Investigation Steps

1. **Queried D1 devices table** — Found two device records for same physical phone:
   - `device_old`: registered weeks ago, has `mcp_token`, `vendor_id = NULL`
   - `device_new`: registered recently, has different `mcp_token`, `vendor_id = <UUID>`

2. **Traced screenshot upload path** — New screenshots written with `device_id = device_new`

3. **Debugged MCP token lookup** — MCP endpoint resolves device via `WHERE mcp_token = ?`, which matched `device_old` (the one with no screenshots)

4. **Reviewed registration logic** — Only checked `WHERE vendor_id = ?`. No fallback for legacy devices with `vendor_id IS NULL`.

## Root Cause Analysis

The **legacy device adoption gap**: When `vendor_id` was added (migration 0008), existing device records had `vendor_id = NULL`. The registration endpoint's lookup only checked `WHERE vendor_id = ?`, which never matched legacy records. Result: a new device was created every time, splitting the MCP token from the data.

**Timeline:**
1. Before migration — iOS registers without vendor_id → device created with `mcp_token`
2. Migration 0008 deployed — adds `vendor_id` column (nullable)
3. iOS app updated — sends `vendor_id` on registration
4. Backend query `WHERE vendor_id = ?` finds nothing (old device has NULL)
5. Backend creates NEW device → two records, split token/data

## Working Solution

### Fix 1: Legacy Device Adoption (`workers/src/routes/devices.ts`)

Added a second lookup before creating a new device. If the `X-Device-ID` header matches an existing device with `vendor_id IS NULL`, adopt it instead of creating a duplicate:

```typescript
// Before creating a new device, check for legacy device to adopt
if (vendor_id) {
  const existingDeviceId = c.req.header('X-Device-ID');
  if (existingDeviceId) {
    const legacy = await c.env.DB.prepare(
      'SELECT id, mcp_token FROM devices WHERE id = ? AND vendor_id IS NULL'
    ).bind(existingDeviceId).first();

    if (legacy) {
      let mcpToken = legacy.mcp_token;
      if (regenerate_token) {
        mcpToken = [...crypto.getRandomValues(new Uint8Array(24))]
          .map(b => b.toString(16).padStart(2, '0')).join('');
      }
      await c.env.DB.prepare(
        'UPDATE devices SET vendor_id = ?, name = ?, mcp_token = ?, last_seen_at = ? WHERE id = ?'
      ).bind(vendor_id, name, mcpToken, now, legacy.id).run();

      return c.json({
        id: legacy.id, name, mcp_token: mcpToken,
        registered_at: now, last_seen_at: now,
      }, 200);
    }
  }
}
```

**Key design decisions:**
- Uses `X-Device-ID` header (not guessing) to identify the legacy device
- Preserves original `mcp_token` unless `regenerate_token` is requested
- One-time operation: once adopted, future registrations match the `vendor_id` lookup

### Fix 2: MCP Health Check (`workers/src/mcp.ts`)

Added diagnostics to `get_device_info` that detect device splits:

- Checks for duplicate devices sharing the same vendor_id
- Warns if device has no vendor_id (pre-migration)
- Reports last screenshot timestamps
- Returns `HEALTH: ISSUES DETECTED` with actionable warnings

## Prevention Strategies

### Identity Migration Checklist

When adding a new identity field to an existing entity:

1. **New field must be nullable** — existing records have NULL; treat NULL as valid state
2. **Two-phase lookup** — Check new key first, then fall back to legacy identifier
3. **Adopt, don't duplicate** — Update the existing record with the new field instead of creating a new one
4. **Preserve auth state** — Keep tokens/keys intact during adoption so existing clients don't break
5. **Partial unique index** — `CREATE UNIQUE INDEX ... WHERE field IS NOT NULL` to allow multiple NULLs

### Testing Recommendations

```typescript
it('legacy adoption: old device with NULL vendor_id gets adopted', async () => {
  // Create pre-migration device
  const oldDevice = await createDevice({ vendor_id: null });

  // Re-register with vendor_id + X-Device-ID header
  const res = await register(
    { vendor_id: 'VID-123', name: 'iPhone' },
    { 'X-Device-ID': oldDevice.id }
  );

  expect(res.id).toBe(oldDevice.id);        // Same device
  expect(res.mcp_token).toBe(oldDevice.mcp_token); // Token preserved
});
```

### Monitoring Queries

```sql
-- Detect duplicate vendor_ids (should never happen)
SELECT vendor_id, COUNT(*) FROM devices
WHERE vendor_id IS NOT NULL
GROUP BY vendor_id HAVING COUNT(*) > 1;

-- Track legacy device ratio (should decrease over time)
SELECT CAST(SUM(CASE WHEN vendor_id IS NULL THEN 1 ELSE 0 END) AS FLOAT) / COUNT(*)
FROM devices WHERE last_seen_at > datetime('now', '-30 days');
```

## Related Documentation

- [Device ID Proliferation Fix](device-id-proliferation-idempotent-registration-20260215.md) — The vendor_id migration that caused this issue
- [MCP Server on Cloudflare Workers](mcp-server-cloudflare-workers-claude-code-bridge-20260214.md) — MCP architecture overview
- [MCP Device-Scoped Auth](../security/mcp-device-scoped-auth-bearer-token-20260214.md) — Bearer token authentication
- [Share Extension Stale Device ID](ios-share-extension-stale-device-id-bearer-token-auth-20260215.md) — Related device identity issue

## Related PRs

- [PR #185](https://github.com/mattsilv/robo/pull/185) — Idempotent device registration via vendor_id (introduced the gap)
- [PR #207](https://github.com/mattsilv/robo/pull/207) — Legacy device adoption fix + MCP health check
- [PR #192](https://github.com/mattsilv/robo/pull/192) — Share Extension Bearer token auth (related identity fix)
- [Issue #187](https://github.com/mattsilv/robo/issues/187) — Rotate MCP token without re-registration
