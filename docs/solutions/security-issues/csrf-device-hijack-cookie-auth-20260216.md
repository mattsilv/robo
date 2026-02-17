---
title: Device Hijacking + CSRF on Cookie-Authenticated Auth Routes
date: 2026-02-16
category: security-issues
tags: [csrf, cookie-auth, device-hijacking, hono, cloudflare-workers]
severity: P1
component: workers/auth
symptom: "Any authenticated user could reassign arbitrary devices to their account via POST /api/auth/link-device; malicious cross-site requests could trigger logout or device linking using browser session cookies"
root_cause: "linkDevice route lacked device ownership validation (only checked device_id existence); cookie-authenticated POST routes had no CSRF protection despite SameSite=None setting for cross-subdomain auth flow"
---

# Device Hijacking + CSRF on Cookie-Authenticated Auth Routes

## Problem

Two P1 security vulnerabilities found during code review of PR #228 (auth backend):

1. **Device Hijacking**: `POST /api/auth/link-device` allowed any authenticated user to reassign ANY device to themselves. The route only checked that `device_id` existed, then unconditionally set `user_id`. No ownership or proof-of-possession check.

2. **CSRF on Cookie Auth**: Auth routes used `SameSite=None` cookies (required for cross-subdomain auth between `app.robo.app` and `api.robo.app`), but POST routes like `/api/auth/link-device` and `/api/auth/logout` had no CSRF protection. A malicious site could forge cross-site requests using the browser's session cookie.

## Root Cause

### Device Hijacking
The `linkDevice` handler only checked device existence, not ownership:

```typescript
// VULNERABLE (workers/src/routes/auth.ts)
const device = await c.env.DB.prepare(
  'SELECT id FROM devices WHERE id = ?'
).bind(device_id).first();
if (!device) return c.json({ error: 'Device not found' }, 404);
await c.env.DB.prepare(
  'UPDATE devices SET user_id = ? WHERE id = ?'
).bind(userId, device_id).run();
```

### CSRF
No origin validation on state-changing POST routes:

```typescript
// VULNERABLE (workers/src/index.ts)
app.post('/api/auth/link-device', userAuth, linkDevice);  // No CSRF check
app.post('/api/auth/logout', logout);                      // No CSRF check
```

## Solution

### Fix 1: Ownership Check (`workers/src/routes/auth.ts`)

```typescript
const device = await c.env.DB.prepare(
  'SELECT id, user_id FROM devices WHERE id = ?'
).bind(device_id).first<{ id: string; user_id: string | null }>();

if (!device) {
  return c.json({ error: 'Device not found' }, 404);
}

// Prevent hijacking: reject if device belongs to another user
if (device.user_id && device.user_id !== userId) {
  return c.json({ error: 'Device is already linked to another account' }, 403);
}
```

Re-linking your own device is allowed (idempotent).

### Fix 2: CSRF Middleware (`workers/src/middleware/userAuth.ts`)

```typescript
const ALLOWED_ORIGINS = ['https://app.robo.app', 'https://robo.app', 'http://localhost:5173'];

export const csrfProtect = createMiddleware<{ Bindings: Env }>(async (c, next) => {
  if (c.req.method === 'GET' || c.req.method === 'HEAD' || c.req.method === 'OPTIONS') {
    return next();
  }
  // Bearer token requests (iOS) are not CSRF-vulnerable
  const authHeader = c.req.header('Authorization');
  if (authHeader?.startsWith('Bearer ')) return next();

  // Cookie-based requests must have a valid Origin
  const origin = c.req.header('Origin');
  if (!origin || !ALLOWED_ORIGINS.includes(origin)) {
    return c.json({ error: 'Invalid origin' }, 403);
  }
  await next();
});
```

Wired to all state-changing auth routes:

```typescript
app.post('/api/auth/apple', csrfProtect, appleAuth);
app.post('/api/auth/link-device', csrfProtect, userAuth, linkDevice);
app.post('/api/auth/logout', csrfProtect, logout);
```

**Why Origin validation (not CSRF tokens):** Browsers always include `Origin` on cross-origin POST requests. Token-based CSRF adds complexity without meaningful security gain here. Bearer token requests (iOS) bypass CSRF entirely since they aren't cookie-based.

## Verification

4 new tests added (25 total passing):

- CSRF rejects POST without Origin → 403
- CSRF rejects POST with wrong Origin (`https://evil.com`) → 403
- Bearer token requests bypass CSRF (iOS path) → passes through to handler
- Device ownership: user-b cannot claim user-a's device → 403

## Prevention Strategies

- **Always check resource ownership before mutations** — fetch `user_id` alongside the record and compare to authenticated user
- **Treat `SameSite=None` as no protection** — always pair with Origin validation or CSRF tokens
- **Exempt Bearer token requests from CSRF** — they aren't vulnerable (token must be explicitly set in JS)
- **Audit all state-changing endpoints** — every POST/PUT/DELETE touching user-scoped resources needs ownership + CSRF checks

## When This Applies

- Any endpoint that transfers ownership of a resource (devices, API keys, team memberships)
- Cross-subdomain cookie auth (e.g., `app.example.com` → `api.example.com`)
- Dual auth paths (cookies for web + Bearer tokens for mobile)

## Related

- [OWASP A01:2021 Broken Access Control](https://owasp.org/Top10/A01_2021-Broken_Access_Control/)
- [CSRF Prevention Cheat Sheet](https://cheatsheetseries.owasp.org/cheatsheets/Cross-Site_Request_Forgery_Prevention_Cheat_Sheet.html)
- `docs/solutions/security-issues/mcp-auth-token-exfiltration-r2-bypass-cors-20260214.md` — related auth bypass
- `docs/solutions/security-issues/xss-r2-growth-poll-winner-pr170-20260215.md` — related input validation
- `docs/plans/2026-02-15-fix-api-auth-lockdown-plan.md` — auth enforcement plan
- PR #228: `feat/auth` branch
