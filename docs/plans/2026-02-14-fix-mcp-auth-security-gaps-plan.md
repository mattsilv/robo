---
title: "Fix MCP Auth Security Gaps"
type: fix
status: completed
date: 2026-02-14
priority: P0
source: PR review of feat/mcp-device-auth
---

# Fix MCP Auth Security Gaps

Three security gaps found during PR review of `feat/mcp-device-auth` (PR #125). All are straightforward fixes in the Workers backend.

## [P0] MCP Token Exfiltration via Unauthenticated Device Endpoint

**Problem:** `GET /api/devices/:device_id` requires no auth and uses `SELECT *`, which now includes `mcp_token` after migration `0003_mcp_token.sql`. Anyone who knows a device UUID can retrieve its bearer token.

**File:** `workers/src/routes/devices.ts:39-50`

**Fix:** Use explicit column list instead of `SELECT *`:

```typescript
// workers/src/routes/devices.ts
const device = await c.env.DB.prepare(
  'SELECT id, name, registered_at, last_seen_at FROM devices WHERE id = ?'
).bind(deviceId).first();
```

- [x] Replace `SELECT *` with explicit columns excluding `mcp_token` in `getDevice`
- [x] Verify `registerDevice` response also excludes token from the general GET path (registration response can include it since the registering device needs it)

## [P1] Device-Scoping Bypass in MCP Debug Payload Fetch

**Problem:** `get_debug_payload` in `mcp.ts:139-166` accepts any R2 key without validating the `debug/${deviceId}/` prefix. A valid token holder for Device A can read Device B's payloads by guessing/knowing the key.

**File:** `workers/src/mcp.ts:139-166`

**Fix:** Validate key starts with authenticated device's prefix:

```typescript
// workers/src/mcp.ts — inside get_debug_payload handler
const expectedPrefix = `debug/${deviceId}/`;
if (!key.startsWith(expectedPrefix)) {
  return {
    content: [{ type: 'text', text: `Access denied. Keys must start with ${expectedPrefix}` }],
    isError: true,
  };
}
```

- [x] Add prefix validation before `env.BUCKET.get(key)` in `get_debug_payload`
- [x] Use the `deviceId` already available in scope from auth

## [P2] CORS Preflight Missing Authorization Header

**Problem:** The OPTIONS handler for `/mcp` in `index.ts:84-90` lists `Content-Type, Accept, Mcp-Session-Id` but omits `Authorization`. Browser-based MCP clients (MCP Inspector) can't send Bearer tokens.

**File:** `workers/src/index.ts:84-90`

**Fix:** Add `Authorization` to allowed headers:

```typescript
'Access-Control-Allow-Headers': 'Content-Type, Accept, Mcp-Session-Id, Authorization',
```

- [x] Add `Authorization` to `Access-Control-Allow-Headers` in the `/mcp` OPTIONS handler

## Bonus: Token Length Consistency

**Problem:** Migration `0003_mcp_token.sql` backfills with `hex(randomblob(16))` (32 chars) but registration generates 24-byte tokens (48 chars). Not a security issue but inconsistent.

- [ ] Update migration to use `hex(randomblob(24))` for consistency (or note as acceptable since backfilled tokens still work)

## Testing

All manual (no integration test suite exists):

```bash
# P0: Verify token not exposed
http GET https://api.robo.app/api/devices/60202e7d-4f75-4105-90cf-ef5c520c639a --timeout=10
# Should NOT contain mcp_token in response

# P1: Verify cross-device R2 access blocked
# Use MCP tool call with a key not matching authenticated device's prefix
# Should return "Access denied" error

# P2: Verify CORS preflight includes Authorization
http OPTIONS https://mcp.robo.app/mcp --timeout=10
# Access-Control-Allow-Headers should include Authorization
```

## Scope

- **3 files changed** in `workers/src/`
- **No iOS changes** needed
- **No migration changes** needed (P0 fix is query-side, not schema-side)
- Deploy with `wrangler deploy` from workers directory
