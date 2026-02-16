---
title: "Optimize MCP get_debug_payload for AI agent consumption"
date: 2026-02-16
category: "integration-issues"
tags:
  - MCP
  - LiDAR
  - data-efficiency
  - agent-usability
  - floor-plan
severity: high
component: "workers/src/mcp.ts"
related_issues:
  - "#198"
  - "#199"
related_docs:
  - "docs/solutions/integration-issues/mcp-server-cloudflare-workers-claude-code-bridge-20260214.md"
  - "docs/solutions/security/mcp-device-scoped-auth-bearer-token-20260214.md"
  - "docs/solutions/logic-errors/roomplan-floor-area-zero-sqft-fix-20260210.md"
---

# Optimize MCP get_debug_payload for AI Agent Consumption

## Problem

The MCP `get_debug_payload` tool returned room scan data designed for human developers, not AI agents:

1. **`structural_sample`** contained raw Apple RoomPlan 4x4 transform matrices (~1.5KB) — no AI agent can interpret these directly
2. **`floor_polygon_2d_ft`** (50-200 bytes, immediately actionable) was computed on iOS but not included in the MCP response
3. **`engineering_guidance`** was vague prose ("use floor polygonCorners for outline") instead of actionable commands
4. No mechanism for agents to render floor plans locally

## Root Cause

The MCP response was built incrementally — first returning raw JSON, then adding a summary layer (PR #151). The summary included a `structural_sample` of raw data for "context," but 4x4 column-major transform matrices require domain expertise to use. Meanwhile, the iOS `RoomDataProcessor` already computed `floor_polygon_2d_ft` with proper world-space transforms — this just wasn't replicated server-side.

## Solution

Redesigned the room scan summary in `workers/src/mcp.ts` to prioritize agent usability:

### Removed
- `structural_sample` — raw 4x4 matrices, ~1.5KB of wasted tokens
- `engineering_guidance` — vague text guidance
- `schema` — raw data structure descriptions
- `download_instructions`, `viewer_instructions` — verbose prose

### Added

**`floor_polygon_2d_ft`** — 2D polygon points in feet, extracted from floor polygonCorners with world-space transform:

```typescript
// column-major 4x4: world = M * local
const cols = floor.transform?.columns;
wx = cols[0][0] * c.x + cols[1][0] * c.y + cols[2][0] * c.z + cols[3][0];
wz = cols[0][2] * c.x + cols[1][2] * c.y + cols[2][2] * c.z + cols[3][2];
floorPolygon2dFt.push({
  x: +(wx * 3.28084).toFixed(2),
  y: +(wz * 3.28084).toFixed(2),
});
```

**`objects_summary`** — simplified object list with position/size in feet (no matrices):
```json
[{"category": "sofa", "x_ft": 4.2, "y_ft": 8.1, "width_ft": 6.5, "depth_ft": 3.0}]
```

**`floor_plan_script`** — self-contained Python/matplotlib script with room data baked in. Auto-installs matplotlib, renders labeled PNG, opens in browser.

**`actionable_commands`** — copy-paste shell commands with pre-computed values for download, render, 3D viewer, paint/flooring estimates.

### Token Budget
~3.2KB (before) → ~3.8KB (after). Removed 1.5KB of useless matrices, added 2.1KB of actionable data.

## Verification

1. `wrangler deploy` from main
2. Call `get_debug_payload` → confirm `floor_polygon_2d_ft` present, `structural_sample` gone
3. Extract `floor_plan_script` → `python3 /tmp/floor_plan.py` → confirm PNG renders with labeled dimensions
4. Verify total response < 5KB

## Prevention

- **Design MCP responses for AI agents first.** Ask: "Can an agent use this field without domain expertise?" If not, transform it.
- **Mirror iOS post-processing server-side.** If `RoomDataProcessor.swift` computes a useful derived field, the MCP response should include it.
- **Prefer pre-computed values over raw data.** Agents shouldn't need to multiply 4x4 matrices — give them feet and positions directly.
- **Include executable code, not prose instructions.** A Python script the agent can run beats "use polygonCorners for outline."
