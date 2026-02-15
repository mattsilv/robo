---
title: Adding Remote MCP Server to Cloudflare Workers for Claude Code Integration
date: 2026-02-14
category: integration-issues
tags:
  - mcp
  - cloudflare-workers
  - claude-code
  - sensor-bridge
  - model-context-protocol
component: workers/src/mcp.ts
severity: medium
sdk_version: "@modelcontextprotocol/sdk@1.26.0"
runtime: cloudflare-workers
transport: WebStandardStreamableHTTPServerTransport
---

# Adding Remote MCP Server to Cloudflare Workers for Claude Code Integration

## Problem

Need to expose iOS sensor data (barcodes, LiDAR room scans, photos, beacon events) to Claude Code so developers can query physical-world data from their terminal. The data already lives in Cloudflare D1 (structured sensor data) and R2 (full LiDAR payloads), but there's no way for Claude Code to access it.

## Solution

Add a stateless MCP (Model Context Protocol) endpoint at `/mcp` to the existing Cloudflare Workers + Hono backend. Uses `@modelcontextprotocol/sdk` v1.26.0 with `WebStandardStreamableHTTPServerTransport` in stateless mode.

**One-command connection:**
```bash
claude mcp add robo --transport http https://mcp.robo.app/mcp \
  --header "Authorization: Bearer YOUR_MCP_TOKEN"
```

Get your token from the Robo iOS app (Settings → Claude Code Connection) or from D1:
```bash
wrangler d1 execute robo-db --command "SELECT name, mcp_token FROM devices" --remote
```

## Architecture

```
iPhone (Robo) → POST /api/sensors/data → D1 sensor_data table
              → POST /api/debug/sync   → R2 debug/ prefix

Claude Code   → POST /mcp (Bearer token) → validates token → device-scoped D1 + R2
```

The MCP endpoint coexists with the Hono REST API on the same Worker. Routing happens in the `fetch` handler **before** Hono:

```typescript
// workers/src/index.ts
export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    // MCP endpoint — handled outside Hono
    if (url.pathname === '/mcp') {
      if (request.method === 'OPTIONS') {
        return new Response(null, {
          headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Accept, Mcp-Session-Id, Authorization',
          },
        });
      }
      return handleMcpRequest(request, env);
    }

    // Everything else → existing Hono app
    return app.fetch(request, env, ctx);
  },
};
```

## Key Technical Decisions

### 1. WebStandardStreamableHTTPServerTransport (not StreamableHTTPServerTransport)

The MCP SDK ships two transport classes:
- `StreamableHTTPServerTransport` — wraps Node.js `IncomingMessage/ServerResponse`
- `WebStandardStreamableHTTPServerTransport` — uses Web Standard `Request/Response`

**Cloudflare Workers must use `WebStandardStreamableHTTPServerTransport`** because Workers use Web Standard APIs, not Node.js HTTP.

```typescript
import { WebStandardStreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js';
```

### 2. Stateless Mode (New McpServer Per Request)

SDK 1.26.0 introduced a security fix (CVE) that prevents sharing `McpServer` instances across requests — doing so leaks data between clients. The solution: create a new server per request with stateless transport.

```typescript
export async function handleMcpRequest(request: Request, env: Env): Promise<Response> {
  // Validate Bearer token → device lookup
  const authHeader = request.headers.get('Authorization');
  const token = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : null;
  if (!token) return new Response(JSON.stringify({
    jsonrpc: '2.0', error: { code: -32000, message: 'Missing Authorization header' }, id: null,
  }), { status: 401, headers: { 'Content-Type': 'application/json' } });

  const device = await env.DB.prepare(
    'SELECT id, name FROM devices WHERE mcp_token = ?'
  ).bind(token).first<{ id: string; name: string }>();
  if (!device) return new Response(JSON.stringify({
    jsonrpc: '2.0', error: { code: -32000, message: 'Invalid token' }, id: null,
  }), { status: 401, headers: { 'Content-Type': 'application/json' } });

  const server = createRoboMcpServer(env, device.id); // device-scoped
  const transport = new WebStandardStreamableHTTPServerTransport({
    sessionIdGenerator: undefined, // Stateless — no session persistence
  });
  await server.connect(transport);
  return transport.handleRequest(request);
}
```

### 3. R2 Payload Truncation (500KB Limit)

LiDAR room scan JSON stored in R2 can be 5-50 MB. Returning the full payload would crash the Worker or overwhelm Claude's context window. All R2 reads are capped at 500KB with a clear truncation notice.

```typescript
const MAX_R2_PAYLOAD_BYTES = 500_000;

if (text.length > MAX_R2_PAYLOAD_BYTES) {
  const truncated = text.substring(0, MAX_R2_PAYLOAD_BYTES);
  return {
    content: [{
      type: 'text',
      text: `[TRUNCATED: ${text.length} bytes total, showing first ${MAX_R2_PAYLOAD_BYTES} bytes]\n\n${truncated}`,
    }],
  };
}
```

### 4. Error Handling with `isError: true`

Every MCP tool wraps its body in try/catch and returns structured errors using the MCP SDK's `isError` flag, which signals to Claude that the tool call failed.

```typescript
} catch (err: any) {
  return { content: [{ type: 'text', text: `Error: ${err.message}` }], isError: true };
}
```

### 5. LiDAR Data Split Hint

LiDAR data lives in two places: D1 has a summary, R2 has the full 3D geometry. The `get_latest_capture` tool description and response include hints guiding Claude to also fetch R2 data:

```typescript
if (parsed.sensor_type === 'lidar') {
  hint = '\n\n[TIP: This is the D1 summary. For full 3D room geometry, call list_debug_payloads with this device_id, then get_debug_payload for the complete room scan JSON.]';
}
```

## MCP Tools Exposed

All tools are **device-scoped** — the Bearer token determines which device's data is accessible.

| Tool | Parameters | Data Source | Description |
|------|-----------|-------------|-------------|
| `get_device_info` | *(none)* | D1 `devices` | Info about the authenticated device |
| `list_captures` | `sensor_type?`, `limit` (default 20) | D1 `sensor_data` | Sensor captures filtered by type |
| `get_capture` | `id` (required) | D1 `sensor_data` | Full capture by ID |
| `get_latest_capture` | `sensor_type?` | D1 `sensor_data` | Most recent capture (with LiDAR hint) |
| `list_debug_payloads` | *(none)* | R2 `debug/{deviceId}/` | R2 objects (full LiDAR scans, etc.) |
| `get_debug_payload` | `key` (required) | R2 | Full R2 payload (500KB truncation) |

**Sensor types:** `barcode`, `camera`, `lidar`, `motion`, `beacon`

## Gotchas & Things to Watch

### CORS Not Applied to /mcp

The `/mcp` route is handled before Hono, so Hono's `cors()` middleware doesn't apply. This is fine for Claude Code (server-side HTTP), but browser-based tools like MCP Inspector need the manual CORS preflight handler. The OPTIONS handler must include `Authorization` in `Access-Control-Allow-Headers` for Bearer token auth to work from browsers.

### Compatibility Date Must Be Recent

The original `wrangler.toml` had `compatibility_date = "2024-01-01"`. The MCP SDK requires newer Worker runtime features. Bumped to `2025-04-01`.

### Import Paths Use .js Extension

Even though the source is TypeScript, the ESM imports require `.js` extensions:
```typescript
// Correct
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';

// Wrong — will fail in Workers
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp';
```

### No Durable Objects Needed

The Cloudflare `agents` package (`createMcpHandler`) uses Durable Objects for session state. For stateless MCP servers, skip `agents` entirely and use `@modelcontextprotocol/sdk` directly — simpler config, no DO bindings needed.

## Testing

All requests require a valid Bearer token. Replace `YOUR_TOKEN` with a real `mcp_token` from D1.

```bash
# Auth failure (no token) → 401
echo '{"jsonrpc":"2.0","method":"initialize","id":1}' | \
  http --timeout=10 POST https://mcp.robo.app/mcp Content-Type:application/json
# → {"jsonrpc":"2.0","error":{"code":-32000,"message":"Missing Authorization header..."},"id":null}

# Auth failure (bad token) → 401
echo '{"jsonrpc":"2.0","method":"tools/list","id":1,"params":{}}' | \
  http --timeout=10 POST https://mcp.robo.app/mcp \
  Content-Type:application/json 'Accept:application/json, text/event-stream' \
  'Authorization:Bearer INVALIDTOKEN'
# → {"jsonrpc":"2.0","error":{"code":-32000,"message":"Invalid token"},"id":null}

# Initialize MCP session
echo '{"jsonrpc":"2.0","method":"initialize","id":1,"params":{"protocolVersion":"2025-03-26","capabilities":{},"clientInfo":{"name":"test","version":"1.0"}}}' | \
  http --timeout=10 POST https://mcp.robo.app/mcp \
  Content-Type:application/json 'Accept:application/json, text/event-stream' \
  'Authorization:Bearer YOUR_TOKEN'
# → event: message
# → data: {"result":{"protocolVersion":"2025-03-26","capabilities":{"tools":{"listChanged":true}},"serverInfo":{"name":"Robo Sensor Bridge","version":"1.0.0"}},...}

# List tools
echo '{"jsonrpc":"2.0","method":"tools/list","id":2,"params":{}}' | \
  http --timeout=10 POST https://mcp.robo.app/mcp \
  Content-Type:application/json 'Accept:application/json, text/event-stream' \
  'Authorization:Bearer YOUR_TOKEN'

# Call a tool (get device info)
echo '{"jsonrpc":"2.0","method":"tools/call","id":3,"params":{"name":"get_device_info","arguments":{}}}' | \
  http --timeout=10 POST https://mcp.robo.app/mcp \
  Content-Type:application/json 'Accept:application/json, text/event-stream' \
  'Authorization:Bearer YOUR_TOKEN'

# List barcode captures
echo '{"jsonrpc":"2.0","method":"tools/call","id":4,"params":{"name":"list_captures","arguments":{"sensor_type":"barcode","limit":5}}}' | \
  http --timeout=10 POST https://mcp.robo.app/mcp \
  Content-Type:application/json 'Accept:application/json, text/event-stream' \
  'Authorization:Bearer YOUR_TOKEN'
```

### Verified 2026-02-14

| Test | Result |
|------|--------|
| `initialize` | `Robo Sensor Bridge v1.0.0`, protocol `2025-03-26` |
| `tools/list` | 6 tools returned (all device-scoped) |
| `get_device_info` | Returns authenticated device's name, ID, timestamps |
| `list_captures` | Filters by sensor type, ordered by recency |
| `get_capture` | Returns full payload (e.g. EAN13 barcode data) |
| `get_latest_capture` | Returns most recent capture |
| `list_debug_payloads` | Lists R2 objects scoped to device |
| Auth: missing token | 401 with helpful error message |
| Auth: invalid token | 401 `"Invalid token"` |

## Files Changed

| File | Change |
|------|--------|
| `workers/src/mcp.ts` | **New** — MCP server with 6 tools |
| `workers/src/index.ts` | Route `/mcp` before Hono, wrap in fetch handler |
| `workers/wrangler.toml` | Bump `compatibility_date` to `2025-04-01` |
| `workers/package.json` | Add `@modelcontextprotocol/sdk` dependency |

## Prevention & Best Practices

1. **Always use `WebStandardStreamableHTTPServerTransport`** for Cloudflare Workers, Deno, or Bun — never the Node.js variant
2. **Always create new `McpServer` per request** (SDK 1.26.0+ requirement)
3. **Always truncate large payloads** from R2/storage before returning in MCP tool responses
4. **Always add `isError: true`** to error responses so Claude knows the tool failed
5. **Always require authentication** — validate Bearer tokens before creating MCP server instances
6. **Always scope queries to the authenticated device** — never trust client-supplied device IDs
7. **Test with httpie/curl first** before connecting Claude Code — the SSE event format is easy to inspect

## Related Documentation

- [Plan: Claude Code MCP Bridge](../plans/2026-02-14-feat-claude-code-mcp-bridge-plan.md)
- [Cloudflare: Build a Remote MCP Server](https://developers.cloudflare.com/agents/guides/remote-mcp-server/)
- [Cloudflare: createMcpHandler API](https://developers.cloudflare.com/agents/model-context-protocol/mcp-handler-api/)
- [Claude Code: Connect via MCP](https://code.claude.com/docs/en/mcp)
- [MCP Transport Spec](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports)
