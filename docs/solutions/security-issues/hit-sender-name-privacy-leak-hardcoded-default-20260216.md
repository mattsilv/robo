---
title: "HIT Sender Name Privacy Leak & Hardcoded Default"
date: "2026-02-16"
category: "security-issues"
tags: [hits, privacy, sender-name, api-design, device-identity]
severity: high
component: [workers/src/routes/hits.ts, functions/hit/[id].ts, ios/Robo/Views/HitListView.swift]
symptoms:
  - "HIT links showed 'M. Silverman' regardless of who created them"
  - "Device name lookup could leak personal names into public HIT links"
related:
  - docs/solutions/integration-issues/device-identity-split-mcp-token-migration-20260216.md
  - docs/solutions/integration-issues/device-id-proliferation-idempotent-registration-20260215.md
---

## Problem

Two bugs in HIT creation:

1. **Hardcoded sender name**: `DEFAULT_SENDER = 'M. Silverman'` in `workers/src/routes/hits.ts` meant every HIT link showed "M. Silverman needs your help" regardless of who created it.

2. **HIT form created broken HITs**: The CreateHitView form on the HITs tab produced generic HITs without proper config (no availability options, no structured data). The Chat-based creation flow is the correct path.

## Initial Fix (Wrong)

First attempt: look up the device's `name` from D1 to resolve sender identity.

```typescript
// BAD — leaks device owner names into public links
const device = await c.env.DB.prepare('SELECT name FROM devices WHERE id = ?').bind(deviceId).first();
if (deviceName && !deviceName.toLowerCase().startsWith('iphone')) {
  resolvedSender = deviceName;
}
```

**Why this was wrong:**
- **P1 Privacy**: iOS sends `UIDevice.current.name` at registration, which is often "Alice's iPhone" or personal names. The `startsWith('iphone')` guard doesn't catch these. This data ends up in public HIT pages and OG meta tags.
- **P2 Reliability**: The DB lookup was outside the `try` block, so a transient D1 failure would crash the entire HIT creation endpoint instead of falling back gracefully.

## Correct Fix

Sender name must be **explicitly provided** in the API request. The chat route already sends the user's `firstName` (from UserDefaults). The direct API fallback is "Someone".

```typescript
const resolvedSender = sender_name || DEFAULT_SENDER; // DEFAULT_SENDER = 'Someone'
```

For the iOS UI: replaced the CreateHitView form with a redirect to the Chat tab via `NotificationCenter`.

## Key Lesson

**Never derive public-facing identity from device metadata.** Device names are user-controlled, often contain real names, and were never intended for public display. Public identity should always be explicitly set by the user (e.g., a "display name" field or chat-provided first name).

## Prevention

- Sender name resolution should only use explicitly user-provided values
- Any new field that appears in public HIT pages/OG tags should be reviewed for PII exposure
- Prefer "Someone" as a safe default over any auto-resolved identity
