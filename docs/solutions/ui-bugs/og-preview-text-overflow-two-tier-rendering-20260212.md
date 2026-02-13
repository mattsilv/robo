---
title: OG Image Text Overflow Prevention — Two-Tier Responsive Rendering
date: 2026-02-12
category: ui-bugs
tags: [og-images, text-truncation, zod-validation, responsive-design, dynamic-content, svg]
component: workers/src/og-limits.ts, workers/src/types.ts, site/demo/hit/
severity: high
---

# OG Image Text Overflow Prevention — Two-Tier Responsive Rendering

## Problem

Dynamic text fields (`recipient_name`, `sender_name`, `task_description`, `agent_name`) injected into OG preview images could overflow and break the 1200x630 layout. The HIT system was transitioning to dynamic content with no validation or responsive rendering for variable-length text.

Additionally, existing Zod schemas had unbounded string fields (`PushCardSchema.body`, `RespondCardSchema.response`) that could accept arbitrarily long input.

**Symptoms:** Long names or descriptions would overflow the robot icon safe zone, wrap unpredictably, or extend beyond image boundaries in social previews (iMessage, Slack, Twitter).

## Root Cause

Three compounding issues:

1. **No text length validation** — Zod schemas allowed unlimited text through to the renderer
2. **No responsive font sizing** — Fixed font sizes (62px, 40px) regardless of text length
3. **No truncation safety net** — No graceful fallback for text exceeding visual limits

## Solution

Created a two-tier responsive OG image rendering system with a single source of truth for all text constraints.

### 1. Constants file — `workers/src/og-limits.ts`

Separates DB storage limits (generous) from visual rendering limits (strict):

```typescript
// DB limits: generous, for storage
export const OG_DB = {
  recipientName: 100,
  senderName: 100,
  taskDescription: 500,
  agentName: 100,
} as const;

// Visual tier breakpoints (chars where we switch font sizes)
export const OG_TIERS = {
  recipientName:   { ideal: 16, max: 30 },   // <=16: 62px, 17-30: 44px, >30: truncate
  senderName:      { ideal: 16, max: 30 },   // <=16: 40px, 17-30: 30px, >30: truncate
  taskDescription: { ideal: 45, max: 80 },   // <=45: 1-line 24px, 46-80: 2-line 20px, >80: truncate
  agentName:       { ideal: 25, max: 40 },   // <=25: 16px, 26-40: 13px, >40: truncate
} as const;

// Safety truncation — always applied before rendering
export function ogSafe(text: string, field: keyof typeof OG_TIERS): string {
  const { max } = OG_TIERS[field];
  if (text.length <= max) return text;
  return text.slice(0, max - 1) + '\u2026';
}

// Tier selection — returns 'ideal' or 'compact'
export function ogTier(text: string, field: keyof typeof OG_TIERS): 'ideal' | 'compact' {
  return text.length <= OG_TIERS[field].ideal ? 'ideal' : 'compact';
}
```

### 2. Schema hardening — `workers/src/types.ts`

Added `.max()` constraints to previously unbounded fields:

```typescript
body: z.string().max(500).optional(),     // was: z.string().optional()
response: z.string().min(1).max(2000),    // was: z.string().min(1)
```

### 3. Two-tier SVG template — `site/demo/hit/og-hit-preview.svg`

- **Tier 1 "Ideal"**: Big bold text for short names (<=16 chars) — 62px greeting, 40px subtitle
- **Tier 2 "Compact"**: Smaller text for longer names (17-30 chars) — 44px greeting, 30px subtitle

**Safe zones** (1200x630):
- Text block: x=90, max-width=680px
- Robot icon: fixed at x=880, 220x220 — never moves
- Task pill: x=90, max-width=700px
- Bottom bar: ROBO.APP left, ALPHA TEST INVITE right

### Usage pattern

```typescript
import { ogSafe, ogTier } from '../og-limits';

const name = ogSafe(hit.recipient_name, 'recipientName');
const tier = ogTier(hit.recipient_name, 'recipientName');
// tier === 'ideal'   → 62px font
// tier === 'compact' → 44px font
```

## Verification

```
ogSafe("A very long recipient name that exceeds the max", 'recipientName')
→ "A very long recipient name th…"

ogTier("James", 'recipientName') → 'ideal'
ogTier("Christopher Longname", 'recipientName') → 'compact'
```

Typecheck passes: `npm run typecheck` clean. PNG renders correctly at 1200x630 (95KB).

## Key Design Pattern: Separation of Concerns

| Layer | Responsibility | Limits |
|-------|---------------|--------|
| **Storage** (DB) | Store full-length data | 100-500 chars (generous) |
| **Validation** (Zod) | Enforce API contract | `.max()` on all string fields |
| **Rendering** (SVG) | Visual safety | `ogSafe()` + `ogTier()` per field |

Each layer can evolve independently. DB limits can grow without affecting rendering. Visual breakpoints can tighten without changing the API contract.

## Prevention Strategies

1. **Always add `.max()` to Zod string schemas** — unbounded text is a risk for both rendering and DoS
2. **Define visual breakpoints for any dynamic text in images** — font sizes must adapt to content length
3. **Use a single constants file** — import limits in schemas, renderers, and tests from one place
4. **Test at boundary lengths** — exercise ideal/compact/truncation thresholds

## Files Changed

| File | Action |
|------|--------|
| `workers/src/og-limits.ts` | Created — DB limits, visual tiers, `ogSafe()`, `ogTier()` |
| `workers/src/types.ts` | Modified — `.max(500)` on body, `.max(2000)` on response |
| `site/demo/hit/og-hit-preview.svg` | Created — two-tier SVG template |
| `site/demo/hit/og-hit-preview.png` | Regenerated — from SVG via `rsvg-convert` |

## Related

- [HIT link personalized OG preview plan](../../plans/2026-02-12-feat-hit-link-personalized-og-preview-plan.md)
- [Functional HIT system CRAWL/WALK/RUN plan](../../plans/2026-02-12-feat-functional-hit-system-web-capture-chat-plan.md)
- [Hono Zod validation pattern for Workers](../build-errors/hono-zod-cloudflare-workers-validation-20260210.md)
- [Multi-service deployment checklist](../integration-issues/cloudflare-multi-service-deployment-hit-system-20260212.md)
- PR #100: Functional HIT system
- PR #97: HIT link POC
- Issue #103: HIT system pre-demo hardening
