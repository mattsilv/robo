---
title: "feat: Claude Code MCP Bridge — Send Sensor Data to Claude Code"
type: feat
status: active
date: 2026-02-14
deadline: 2026-02-16 3:00 PM EST
---

# Claude Code MCP Bridge — Send Sensor Data to Claude Code

## Overview

Add a **remote MCP server** to Robo's existing Cloudflare Workers backend so that Claude Code (and Claude AI) can directly access sensor data captured on the phone. One command connects Claude Code to your device's captures — photos, LiDAR scans, barcodes, beacon data — no manual file transfer needed.

**Demo flow (30 seconds):**
1. User scans a room with LiDAR on their iPhone
2. Developer runs: `claude mcp add robo https://robo-api.silv.workers.dev/mcp`
3. In Claude Code: *"Describe the room I just scanned and suggest furniture placement"*
4. Claude Code calls `get_latest_capture` → gets the LiDAR JSON → responds with analysis

**Why this wows Anthropic:** This is the first open-source iOS app that bridges physical-world sensor data into Claude Code via MCP. It demonstrates the exact future Anthropic is building toward — AI agents that can perceive the physical world.

## Architecture

```
┌─────────────────┐     POST /api/sensors/data      ┌──────────────────────┐
│   iPhone (Robo)  │ ──────────────────────────────► │  Cloudflare Workers  │
│                  │     POST /api/debug/sync         │  (robo-api)          │
│  - LiDAR scan    │ ──────────────────────────────► │                      │
│  - Photos        │                                  │  Existing: Hono app  │
│  - Barcodes      │                                  │  + NEW: /mcp endpoint│
│  - Beacon data   │                                  │                      │
└─────────────────┘                                  │  D1 ─── sensor_data  │
                                                     │  R2 ─── debug/*.json │
┌─────────────────┐     MCP (Streamable HTTP)        │         hits/*.jpg   │
│  Claude Code     │ ◄──────────────────────────────►│                      │
│  (or Claude AI)  │     GET/POST /mcp               │  MCP Tools:          │
│                  │                                  │  - list_captures     │
│  "Describe the   │                                  │  - get_capture       │
│   room I just    │                                  │  - get_latest_capture│
│   scanned"       │                                  │  - list_devices      │
└─────────────────┘                                  └──────────────────────┘
```

**Key insight:** All the data infrastructure already exists. D1 has `sensor_data`, R2 has `debug/` payloads and HIT photos. The MCP server just needs to expose read access to this existing data.

## Proposed Solution

### Approach: Stateless MCP endpoint alongside existing Hono app

Add an `/mcp` route to the existing Cloudflare Worker that handles MCP Streamable HTTP transport. **Primary approach:** use `@modelcontextprotocol/sdk` with `StreamableHTTPServerTransport` in stateless mode. **Fallback:** Cloudflare's `agents` package with `createMcpHandler` (requires Durable Objects — more complex).

**Why stateless `@modelcontextprotocol/sdk` directly:**
- Zero new infrastructure — same Worker, same D1, same R2
- No Durable Objects needed — simpler `wrangler.toml`
- Deploys with existing `wrangler deploy`
- No auth needed for hackathon (device_id acts as a soft scope)
- New `McpServer` per request (required by SDK 1.26.0+ — CVE fix)
- Stateless session mode: no session persistence needed between requests

**Critical note:** Validate `compatibility_date` — bump `wrangler.toml` from `2024-01-01` to `2025-04-01` for MCP SDK compatibility.

### MCP Tools

| Tool | Description | Data Source |
|------|-------------|-------------|
| `list_devices` | List registered devices | D1 `devices` table |
| `list_captures` | List sensor captures for a device, filterable by type | D1 `sensor_data` table |
| `get_capture` | Get a specific capture by ID | D1 `sensor_data` table |
| `get_latest_capture` | Get most recent capture (optionally by sensor type) | D1 `sensor_data` table |
| `get_debug_payload` | Get a debug sync payload (full LiDAR/room JSON from R2) | R2 `debug/` prefix |
| `list_debug_payloads` | List debug payloads for a device | R2 `debug/` prefix |

### MCP Resources (optional, time permitting)

| Resource | URI | Description |
|----------|-----|-------------|
| `robo://device/{id}/latest` | Dynamic | Latest capture for a device |

## Technical Approach

### Phase 1: MCP Server (Backend — ~2 hours)

#### 1a. Install dependencies

```bash
cd workers
npm install @modelcontextprotocol/sdk agents
```

#### 1b. Create MCP route handler

**New file:** `workers/src/mcp.ts`

```typescript
import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { StreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/streamableHttp.js';
import { z } from 'zod';
import type { Env } from './types';

const MAX_R2_PAYLOAD_BYTES = 500_000; // 500 KB safety limit

function createRoboMcpServer(env: Env) {
  const server = new McpServer({
    name: 'Robo Sensor Bridge',
    version: '1.0.0',
  });

  // Tool: list_devices
  server.tool(
    'list_devices',
    'List all registered Robo devices with their names and last activity',
    {},
    async () => {
      try {
        const result = await env.DB.prepare(
          'SELECT id, name, registered_at, last_seen_at FROM devices ORDER BY last_seen_at DESC'
        ).all();
        return {
          content: [{ type: 'text', text: JSON.stringify(result.results, null, 2) }],
        };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }], isError: true };
      }
    }
  );

  // Tool: list_captures
  server.tool(
    'list_captures',
    'List sensor captures for a device. Filter by sensor_type: barcode, camera, lidar, motion, beacon. Returns IDs and timestamps — use get_capture for full data.',
    {
      device_id: z.string().optional().describe('Device UUID (omit for all devices)'),
      sensor_type: z.enum(['barcode', 'camera', 'lidar', 'motion', 'beacon']).optional()
        .describe('Filter by sensor type'),
      limit: z.number().default(20).describe('Max results (default 20)'),
    },
    async ({ device_id, sensor_type, limit }) => {
      try {
        let query = 'SELECT id, device_id, sensor_type, captured_at FROM sensor_data WHERE 1=1';
        const binds: any[] = [];
        if (device_id) { query += ' AND device_id = ?'; binds.push(device_id); }
        if (sensor_type) { query += ' AND sensor_type = ?'; binds.push(sensor_type); }
        query += ' ORDER BY captured_at DESC LIMIT ?';
        binds.push(limit);

        const stmt = env.DB.prepare(query);
        const result = await stmt.bind(...binds).all();
        return {
          content: [{ type: 'text', text: JSON.stringify(result.results, null, 2) }],
        };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }], isError: true };
      }
    }
  );

  // Tool: get_capture
  server.tool(
    'get_capture',
    'Get full sensor capture data by ID (includes the raw JSON payload)',
    { id: z.number().describe('Capture ID from list_captures') },
    async ({ id }) => {
      try {
        const result = await env.DB.prepare(
          'SELECT * FROM sensor_data WHERE id = ?'
        ).bind(id).first();
        if (!result) {
          return { content: [{ type: 'text', text: 'Capture not found' }] };
        }
        const parsed = { ...result, data: JSON.parse(result.data as string) };
        return {
          content: [{ type: 'text', text: JSON.stringify(parsed, null, 2) }],
        };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }], isError: true };
      }
    }
  );

  // Tool: get_latest_capture
  server.tool(
    'get_latest_capture',
    'Get the most recent sensor capture. For LiDAR room scans, this returns the D1 summary — for the FULL 3D room data, also call list_debug_payloads and get_debug_payload to get the complete room geometry from R2.',
    {
      device_id: z.string().optional().describe('Device UUID (omit to get latest across ALL devices)'),
      sensor_type: z.enum(['barcode', 'camera', 'lidar', 'motion', 'beacon']).optional()
        .describe('Filter by sensor type'),
    },
    async ({ device_id, sensor_type }) => {
      try {
        let query = 'SELECT * FROM sensor_data WHERE 1=1';
        const binds: any[] = [];
        if (device_id) { query += ' AND device_id = ?'; binds.push(device_id); }
        if (sensor_type) { query += ' AND sensor_type = ?'; binds.push(sensor_type); }
        query += ' ORDER BY captured_at DESC LIMIT 1';

        const stmt = env.DB.prepare(query);
        const result = binds.length ? await stmt.bind(...binds).first() : await stmt.first();
        if (!result) {
          return { content: [{ type: 'text', text: 'No captures found. The user may not have scanned anything yet.' }] };
        }
        const parsed = { ...result, data: JSON.parse(result.data as string) };

        // Hint for LiDAR: guide Claude to also check R2
        let hint = '';
        if (parsed.sensor_type === 'lidar') {
          hint = '\n\n[TIP: This is the D1 summary. For full 3D room geometry, call list_debug_payloads with this device_id, then get_debug_payload for the complete room scan JSON.]';
        }

        return {
          content: [{ type: 'text', text: JSON.stringify(parsed, null, 2) + hint }],
        };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }], isError: true };
      }
    }
  );

  // Tool: list_debug_payloads
  server.tool(
    'list_debug_payloads',
    'List debug sync payloads stored in R2 — these contain FULL sensor data (complete LiDAR room scans with 3D geometry, wall positions, surfaces). Use get_debug_payload to retrieve one.',
    {
      device_id: z.string().optional().describe('Device UUID (omit to search all devices)'),
    },
    async ({ device_id }) => {
      try {
        const prefix = device_id ? `debug/${device_id}/` : 'debug/';
        const listed = await env.BUCKET.list({ prefix, limit: 50 });
        const items = listed.objects.map((obj) => ({
          key: obj.key,
          size: obj.size,
          size_human: obj.size > 1_000_000 ? `${(obj.size / 1_000_000).toFixed(1)} MB` : `${(obj.size / 1_000).toFixed(1)} KB`,
          uploaded: obj.uploaded.toISOString(),
        }));
        return {
          content: [{ type: 'text', text: JSON.stringify(items, null, 2) }],
        };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }], isError: true };
      }
    }
  );

  // Tool: get_debug_payload
  server.tool(
    'get_debug_payload',
    'Retrieve a debug payload from R2 (full room scan JSON, etc.). Large payloads (>500KB) are truncated.',
    {
      key: z.string().describe('R2 object key from list_debug_payloads'),
    },
    async ({ key }) => {
      try {
        const obj = await env.BUCKET.get(key);
        if (!obj) {
          return { content: [{ type: 'text', text: 'Payload not found' }] };
        }
        if (obj.size > MAX_R2_PAYLOAD_BYTES) {
          const text = await obj.text();
          const truncated = text.substring(0, MAX_R2_PAYLOAD_BYTES);
          return {
            content: [{
              type: 'text',
              text: `[TRUNCATED: ${obj.size} bytes total, showing first ${MAX_R2_PAYLOAD_BYTES} bytes]\n\n${truncated}`,
            }],
          };
        }
        const data = await obj.text();
        return { content: [{ type: 'text', text: data }] };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }], isError: true };
      }
    }
  );

  return server;
}

// Stateless MCP handler — new server per request (SDK 1.26.0+ requirement)
export async function handleMcpRequest(request: Request, env: Env): Promise<Response> {
  const server = createRoboMcpServer(env);
  const transport = new StreamableHTTPServerTransport({
    sessionIdGenerator: undefined, // Stateless mode — no session persistence
  });
  await server.connect(transport);
  return transport.handleRequest(request);
}
```

> **Note on `StreamableHTTPServerTransport`:** If this import path doesn't exist in the SDK version available on npm, the fallback is to use Cloudflare's `agents` package with `createMcpHandler`. That approach requires adding a Durable Object binding to `wrangler.toml`. Check the SDK exports first before coding.

#### 1c. Wire into existing Worker

**Modified file:** `workers/src/index.ts`

Add the MCP endpoint alongside existing Hono routes. The MCP handler needs direct access to the raw `Request` object (not Hono's context), so we route `/mcp` before Hono:

```typescript
import { handleMcpRequest } from './mcp';

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    // MCP endpoint — handled outside Hono (needs raw Request for StreamableHTTPServerTransport)
    if (url.pathname === '/mcp') {
      // Add CORS for MCP Inspector (browser-based testing)
      if (request.method === 'OPTIONS') {
        return new Response(null, {
          headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Accept, Mcp-Session-Id',
          },
        });
      }
      return handleMcpRequest(request, env);
    }

    // Everything else → existing Hono app
    return app.fetch(request, env, ctx);
  }
};
```

> **Note:** CORS is handled manually for `/mcp` since it bypasses Hono's middleware. This is only needed for browser-based MCP testing tools (MCP Inspector). Claude Code connects server-side and doesn't need CORS.

#### 1d. Update wrangler.toml (if needed)

No changes needed — the same Worker serves both REST and MCP. D1 and R2 bindings are already configured.

### Phase 2: iOS "Claude" Agent (iOS — ~1 hour)

Add "Claude Code" as a built-in agent in the app. This agent's purpose: **help users understand their data is available to Claude Code** and guide them to connect.

**Modified file:** `ios/Robo/Services/MockAgentService.swift`

Add a new agent:
```swift
AgentConnection(
    id: UUID(uuidString: "CLAUDE-CODE-0000-0000-000000000001")!,
    name: "Claude Code",
    description: "Bridge your sensor data to Claude Code. Scan a room, take a photo, or capture barcodes — then access it all from your terminal.",
    iconSystemName: "terminal",
    accentColor: .orange,
    status: .connected,
    pendingRequest: AgentRequest(
        id: UUID(),
        title: "Capture data for Claude Code",
        description: "Any sensor capture will be available to Claude Code via MCP. Scan a room, photograph something, or scan a barcode.",
        skillType: .lidar,
        photoChecklist: nil,
        roomNameHint: nil
    )
)
```

### Phase 3: Connection Guide UI (iOS — ~1 hour)

After a capture completes (or in the agent detail view), show a "Connect to Claude Code" card with the one-liner:

```
claude mcp add robo https://robo-api.silv.workers.dev/mcp
```

With a "Copy" button and brief explanation. This is the "Apple Magic" moment — one command, done.

**New file:** `ios/Robo/Views/ClaudeCodeConnectionView.swift` (~60 lines)

Simple card view with:
- Terminal icon + "Connect to Claude Code" header
- The `claude mcp add` command in a monospace copyable field
- "Copy Command" button (copies to clipboard)
- Brief description: "After connecting, ask Claude about your captures"
- Optional: example prompts ("Describe the room I just scanned", "What barcodes did I capture?")

### Phase 4: Polish & Demo Prep (~30 min)

- Test end-to-end: capture on device → query from Claude Code
- Ensure debug sync uploads work (room scan JSON → R2 → MCP tool)
- Prepare demo script

## Implementation Sequence

**Priority order (do steps 1-4 first — everything else is polish):**

```
1. [Validate] Install deps, verify SDK imports work           (15 min)
   - npm install @modelcontextprotocol/sdk
   - Check if StreamableHTTPServerTransport exists
   - If not: npm install agents, use createMcpHandler + Durable Objects
   - Bump wrangler.toml compatibility_date to 2025-04-01

2. [Backend] Create workers/src/mcp.ts with all 6 tools       (45 min)
   - All tools with try/catch + isError:true
   - R2 size limit (500KB truncation)
   - LiDAR hint in get_latest_capture

3. [Backend] Wire /mcp into index.ts + deploy                 (15 min)
   - Route /mcp before Hono
   - Add CORS preflight for /mcp
   - wrangler deploy

4. [Backend] Test with Claude Code                             (15 min)
   - claude mcp add robo https://robo-api.silv.workers.dev/mcp
   - Test: list_devices, get_latest_capture, get_debug_payload
   - Verify end-to-end data flow

--- MVP DONE (1.5 hours) — Everything below is polish ---

5. [Data] Pre-seed demo data if needed                         (15 min)
   - Ensure at least 1 LiDAR scan in R2 + sensor_data row in D1
   - Ensure at least 1 barcode scan in D1

6. [iOS] Add Claude Code agent to MockAgentService             (15 min)

7. [iOS] Create ClaudeCodeConnectionView with copy button      (30 min)

8. [Polish] Demo script + rehearsal                            (30 min)
```

**MVP: ~1.5 hours | Full: ~3 hours**

## Acceptance Criteria

### Functional

- [x] `claude mcp add robo https://robo-api.silv.workers.dev/mcp` connects successfully
- [x] `list_devices` returns registered devices
- [x] `list_captures` returns sensor data filterable by type
- [x] `get_latest_capture` returns the most recent capture with full data
- [x] `get_debug_payload` returns full LiDAR room scan JSON from R2
- [ ] Claude Code can answer questions about captured sensor data
- [ ] iOS app shows "Claude Code" agent in agent list
- [ ] iOS app shows connection command after captures
- [ ] Copy button works for the `claude mcp add` command

### Non-Functional

- [x] MCP endpoint doesn't break existing REST API
- [x] New McpServer instance per request (SDK 1.26.0+ security requirement)
- [x] No auth required for hackathon (can add OAuth later)
- [x] Deploys with existing `npm run deploy`

## Demo Script (3 minutes)

1. **Setup** (30s): Show Claude Code terminal. Run `claude mcp add robo https://robo-api.silv.workers.dev/mcp`
2. **Capture** (60s): Open Robo on iPhone → Claude Code agent → LiDAR scan a room
3. **Query** (60s): In Claude Code, ask: *"What room did I just scan? Describe the dimensions and suggest furniture layout."*
4. **Magic moment** (30s): Claude Code calls `get_latest_capture` → returns room JSON → provides analysis with dimensions, wall positions, furniture suggestions

**Alternative demos:**
- Barcode scan → "What did I just scan? Any nutrition concerns?"
- Multi-photo capture → "Describe what you see in my recent photos"
- Beacon data → "What rooms have I been in today?"

## SpecFlow Analysis — Key Risks & Mitigations

| Priority | Gap | Fix | Time |
|----------|-----|-----|------|
| **CRITICAL** | `StreamableHTTPServerTransport` may not exist in npm SDK — Cloudflare's `agents` package may require Durable Objects | Validate imports in step 1. Fallback: `agents` + DO binding | 15 min |
| **CRITICAL** | MCP session state lost between requests in stateless mode | Use `sessionIdGenerator: undefined` for stateless mode | Built-in |
| **IMPORTANT** | LiDAR data split: D1 has summary, R2 has full 3D JSON. Claude may only query D1 | Added hint in `get_latest_capture` tool description guiding Claude to also fetch R2 | Done |
| **IMPORTANT** | Large R2 payloads (5-50 MB LiDAR scans) can crash Worker or overwhelm context | Added 500 KB truncation with size indicator | Done |
| **IMPORTANT** | `compatibility_date` too old for MCP SDK | Bump to `2025-04-01` | 1 min |
| **MODERATE** | No error handling in tools — one bad D1 row crashes the call | Added try/catch + `isError: true` in all tools | Done |
| **MODERATE** | No auth on MCP — all data exposed to anyone with URL | Acceptable for hackathon. Can add bearer token in 10 min post-MVP | Accept |
| **LOW** | CORS not applied to `/mcp` (bypasses Hono middleware) | Added manual CORS preflight handler | Done |
| **LOW** | Multi-device ambiguity (which device is "mine"?) | `get_latest_capture` defaults to latest across ALL devices | Done |

## Dependencies & Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| `createMcpHandler` + Hono conflict | Low | MCP routes handled before Hono in fetch handler |
| `agents` package not compatible with existing wrangler config | Low | Fall back to raw `@modelcontextprotocol/sdk` with manual HTTP handler |
| Large R2 payloads exceed MCP token limit | Medium | Truncate or summarize large payloads; set `MAX_MCP_OUTPUT_TOKENS` |
| Device has no data yet during demo | Low | Pre-seed with test captures before demo |

## Future Considerations (Post-Hackathon)

- **OAuth:** Add device-scoped auth so users only see their own data
- **Claude AI (claude.ai):** Same MCP server works — users add it in Claude settings
- **Real-time:** SSE streaming for live sensor feeds (beacon proximity in real-time)
- **Write tools:** Let Claude Code trigger captures via MCP → inbox push → device responds
- **Photo/image tools:** Serve R2 images as MCP resources for vision analysis

## References

- [Cloudflare: Build a Remote MCP Server](https://developers.cloudflare.com/agents/guides/remote-mcp-server/)
- [Cloudflare: createMcpHandler API](https://developers.cloudflare.com/agents/model-context-protocol/mcp-handler-api/)
- [Claude Code: Connect via MCP](https://code.claude.com/docs/en/mcp)
- [MCP Transport Spec](https://modelcontextprotocol.io/specification/2025-03-26/basic/transports)
- Existing routes: `workers/src/routes/sensors.ts`, `workers/src/routes/debug.ts`
- Agent definitions: `ios/Robo/Services/MockAgentService.swift`
- Existing types: `workers/src/types.ts`
