---
title: "MCP Device Auth Security Gaps — Token Exfiltration, Cross-Device R2 Access, CORS Missing Bearer"
date: 2026-02-14
type: security_issue
severity: high
module: workers
tags: [authentication, authorization, MCP, R2, CORS, device-scoped-auth]
symptoms:
  - "GET /api/devices/:device_id exposed mcp_token to anyone knowing device UUID"
  - "get_debug_payload tool accepted any R2 key without device prefix validation"
  - "MCP CORS preflight missing Authorization header, blocking Bearer token clients"
root_cause: "PR review of feat/mcp-device-auth (#125) uncovered 3 auth gaps introduced by new device-scoped MCP feature"
---

# MCP Device Auth Security Gaps

Three security gaps found during PR review of `feat/mcp-device-auth` (PR #125). All fixed in commit `8200b20`.

## Root Cause Analysis

**P0 — Token Exfiltration**
`GET /api/devices/:device_id` used `SELECT * FROM devices` with no authentication. After migration `0003_mcp_token.sql` added the `mcp_token` column, this endpoint exposed bearer tokens to anyone knowing a device UUID.

**P1 — Cross-Device R2 Access**
The `get_debug_payload` MCP tool accepted user-provided R2 object keys without path prefix validation. An authenticated Device A could construct keys targeting Device B's debug payloads (stored under `debug/{deviceId}/` prefixes), bypassing device-scoped isolation.

**P2 — CORS Missing Authorization Header**
The OPTIONS handler for `/mcp` explicitly listed allowed CORS headers but omitted `Authorization`. Browser-based MCP clients (MCP Inspector) couldn't send Bearer tokens.

## Solution

**P0 — Selective Field Projection (`workers/src/routes/devices.ts:42`)**

```typescript
// Before (vulnerable): exposes mcp_token
'SELECT * FROM devices WHERE id = ?'

// After (fixed): explicit safe columns only
'SELECT id, name, registered_at, last_seen_at FROM devices WHERE id = ?'
```

**P1 — R2 Key Prefix Enforcement (`workers/src/mcp.ts:147`)**

```typescript
// Added before env.BUCKET.get(key)
const expectedPrefix = `debug/${deviceId}/`;
if (!key.startsWith(expectedPrefix)) {
  return {
    content: [{ type: 'text', text: `Access denied. Keys must start with ${expectedPrefix}` }],
    isError: true,
  };
}
```

**P2 — CORS Header Addition (`workers/src/index.ts:88`)**

```typescript
// Before
'Access-Control-Allow-Headers': 'Content-Type, Accept, Mcp-Session-Id',
// After
'Access-Control-Allow-Headers': 'Content-Type, Accept, Mcp-Session-Id, Authorization',
```

## Verification

```bash
# P0: Token not exposed
http GET https://api.robo.app/api/devices/60202e7d-4f75-4105-90cf-ef5c520c639a --timeout=10
# Returns: {id, name, registered_at, last_seen_at} — no mcp_token

# P2: CORS includes Authorization
http OPTIONS https://mcp.robo.app/mcp --timeout=10 --print=h
# Access-Control-Allow-Headers: Content-Type, Accept, Mcp-Session-Id, Authorization
```

## Prevention Strategies

1. **Never use `SELECT *`** — Always use explicit column lists. New sensitive columns silently leak through wildcards.
2. **Validate storage key prefixes** — Any user-provided object key must be validated against `{prefix}/{authenticatedId}/` before access.
3. **Sync CORS with auth changes** — When adding auth headers to an endpoint, update the OPTIONS handler in the same commit.

## PR Review Checklist Additions

- [ ] New DB columns added? Check all `SELECT` queries touching that table for `*`
- [ ] Object storage accessed with user input? Verify prefix enforcement
- [ ] New auth headers required? Verify CORS preflight allows them

## Related Documentation

- [MCP Device-Scoped Auth Solution](../security/mcp-device-scoped-auth-bearer-token-20260214.md)
- [MCP Server on Cloudflare Workers](../integration-issues/mcp-server-cloudflare-workers-claude-code-bridge-20260214.md)
- [Export Filename Sanitization](../security/export-filename-sanitization-path-traversal-20260213.md)
- [Fix Plan](../../plans/2026-02-14-fix-mcp-auth-security-gaps-plan.md)
