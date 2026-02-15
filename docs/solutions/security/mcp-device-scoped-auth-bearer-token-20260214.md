---
title: "MCP Device-Scoped Authentication via Bearer Token"
date: 2026-02-14
category: security
tags:
  - mcp
  - authentication
  - bearer-token
  - device-scoping
  - cloudflare-workers
  - d1
severity: high
status: resolved
component:
  - workers
  - ios
---

# MCP Device-Scoped Authentication via Bearer Token

## Problem

The MCP endpoint (`POST /mcp`) on Cloudflare Workers was completely unauthenticated. Any client could query the endpoint and retrieve sensor data (LiDAR room scans, photos, barcodes) from **all** devices in the system. No access control existed on the MCP route.

**Symptoms:**
- `POST /mcp` accepted requests without any credentials
- `list_captures` returned data from every registered device
- `list_debug_payloads` listed all R2 objects across all devices
- No way for a device owner to restrict access to their data

## Root Cause

Two gaps in the MCP architecture:

1. **No authentication layer** on the `/mcp` route. The handler called `createRoboMcpServer(env)` directly without validating any credentials.
2. **No device scoping** in MCP tool queries. Tools like `list_captures` accepted an optional `device_id` parameter but defaulted to returning all devices' data when omitted.

## Solution

### Step 1: D1 Migration

`workers/migrations/0003_mcp_token.sql`:

```sql
ALTER TABLE devices ADD COLUMN mcp_token TEXT;
UPDATE devices SET mcp_token = hex(randomblob(16)) WHERE mcp_token IS NULL;
```

### Step 2: Token Generation on Registration

`workers/src/routes/devices.ts` — generate a 48-char hex token (24 random bytes):

```typescript
const mcpToken = [...crypto.getRandomValues(new Uint8Array(24))]
  .map(b => b.toString(16).padStart(2, '0')).join('');

await c.env.DB.prepare(
  'INSERT INTO devices (id, name, mcp_token, registered_at) VALUES (?, ?, ?, ?)'
).bind(deviceId, name, mcpToken, now).run();

return c.json({ id: deviceId, name, mcp_token: mcpToken, registered_at: now }, 201);
```

### Step 3: Bearer Token Validation

`workers/src/mcp.ts` — extract and validate the token before creating the MCP server:

```typescript
const authHeader = request.headers.get('Authorization');
const token = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : null;

if (!token) {
  return new Response(JSON.stringify({
    jsonrpc: '2.0',
    error: { code: -32000, message: 'Missing Authorization header...' },
    id: null,
  }), { status: 401 });
}

const device = await env.DB.prepare(
  'SELECT id, name FROM devices WHERE mcp_token = ?'
).bind(token).first<{ id: string; name: string }>();

if (!device) {
  return new Response(JSON.stringify({
    jsonrpc: '2.0',
    error: { code: -32000, message: 'Invalid token' },
    id: null,
  }), { status: 401 });
}

const server = createRoboMcpServer(env, device.id);
```

### Step 4: Device-Scoped Queries

Changed `createRoboMcpServer(env)` to `createRoboMcpServer(env, deviceId)`. All tools now filter by the authenticated device:

- `list_captures` — removed `device_id` param, always `WHERE device_id = ?`
- `get_capture` — added `AND device_id = ?` check
- `get_latest_capture` — removed `device_id` param, always scoped
- `list_debug_payloads` — always uses `debug/${deviceId}/` R2 prefix
- `list_devices` replaced with `get_device_info` — returns only the authenticated device

### Step 5: iOS Integration

- `DeviceConfig.swift` — added `var mcpToken: String?`
- `APIService.swift` — decode `mcp_token` from registration response via `CodingKeys`
- `ClaudeCodeConnectionView.swift` — new view with pre-built `claude mcp add` command + copy button
- `AgentsView.swift` — shows connection UI in Claude Code agent detail view

## Verification

Tested 2026-02-14 against production (`https://mcp.robo.app/mcp`):

```bash
# No token -> 401
echo '{"jsonrpc":"2.0","method":"initialize","id":1}' | \
  http --timeout=10 POST https://mcp.robo.app/mcp Content-Type:application/json
# → {"jsonrpc":"2.0","error":{"code":-32000,"message":"Missing Authorization header..."},"id":null}

# Invalid token -> 401
echo '{"jsonrpc":"2.0","method":"tools/list","id":1,"params":{}}' | \
  http --timeout=10 POST https://mcp.robo.app/mcp \
  Content-Type:application/json 'Accept:application/json, text/event-stream' \
  'Authorization:Bearer INVALIDTOKEN'
# → {"jsonrpc":"2.0","error":{"code":-32000,"message":"Invalid token"},"id":null}

# Valid token -> MCP initializes with device-scoped access
echo '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | \
  http --timeout=10 POST https://mcp.robo.app/mcp \
  Content-Type:application/json 'Accept:application/json, text/event-stream' \
  'Authorization:Bearer YOUR_TOKEN'
# → event: message
# → data: {"result":{"protocolVersion":"2025-03-26","capabilities":{"tools":{"listChanged":true}},"serverInfo":{"name":"Robo Sensor Bridge","version":"1.0.0"}},...}

# Device info returns only the authenticated device
echo '{"jsonrpc":"2.0","method":"tools/call","id":2,"params":{"name":"get_device_info","arguments":{}}}' | \
  http --timeout=10 POST https://mcp.robo.app/mcp \
  Content-Type:application/json 'Accept:application/json, text/event-stream' \
  'Authorization:Bearer YOUR_TOKEN'
# → returns only the device matching the token, not all devices
```

## Files Changed

| File | Change |
|------|--------|
| `workers/migrations/0003_mcp_token.sql` | **New** — ALTER TABLE + backfill |
| `workers/src/routes/devices.ts` | Generate + return `mcp_token` |
| `workers/src/mcp.ts` | Bearer validation + device-scoped queries |
| `ios/Robo/Models/DeviceConfig.swift` | Added `mcpToken: String?` |
| `ios/Robo/Services/APIService.swift` | Decode `mcp_token` from response |
| `ios/Robo/Views/ClaudeCodeConnectionView.swift` | **New** — copy-to-clipboard UI |
| `ios/Robo/Views/AgentsView.swift` | Connection UI in agent detail |

## Prevention

- **Authenticate by default** — require auth at the routing layer before handler logic
- **Scope all queries** — never trust client-supplied `device_id`; always derive from token lookup
- **Use parameterized queries** — bind `deviceId` via `?` placeholders, never interpolate

## Future Considerations

- **Token rotation** — allow users to regenerate tokens (not implemented in M1)
- **Keychain storage** — move from UserDefaults to iOS Keychain for token persistence
- **Rate limiting** — per-token request limits to contain leaked tokens
- **Token expiry** — add `expires_at` column for time-limited tokens

## Related

- [MCP Server Implementation](../integration-issues/mcp-server-cloudflare-workers-claude-code-bridge-20260214.md)
- [MCP Bridge Plan](../../plans/2026-02-14-feat-claude-code-mcp-bridge-plan.md)
- [Device Auth Plan](../../plans/2026-02-14-feat-mcp-device-auth-primer.md)
