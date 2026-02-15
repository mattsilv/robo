---
title: "fix: Lock down HIT/debug/inbox APIs (unauthenticated + cross-device IDOR)"
type: fix
status: completed
date: 2026-02-15
issue: "#176"
priority: P0
---

# Lock Down HIT/Debug/Inbox APIs

## Overview

Issue #176: Multiple API routes are exposed without auth, and some auth'd routes trust client-supplied IDs over the authenticated identity. This plan adds `deviceAuth` middleware to all private routes, adds ownership checks, and closes the global-data-leak in `listHits`.

## Route-by-Route Changes

### 1. Add `deviceAuth` to unprotected routes in `index.ts`

**Current (no auth):**
```typescript
// index.ts:54-62 — HIT routes
app.post('/api/hits', createHit);
app.get('/api/hits', listHits);
app.get('/api/hits/:id', getHit);
app.delete('/api/hits/:id', deleteHit);
app.post('/api/hits/:id/upload', uploadHitPhoto);
app.patch('/api/hits/:id/complete', completeHit);
app.get('/api/hits/:id/photos', listHitPhotos);
app.get('/api/hits/:id/responses', listHitResponses);

// index.ts:43 — Inbox
app.get('/api/inbox/:device_id', getInbox);

// index.ts:74-76 — Debug
app.post('/api/debug/sync', debugSync);
app.get('/api/debug/sync/:device_id', debugList);
app.get('/api/debug/sync/:device_id/:key{.+}', debugGet);
```

**Fixed:**
```typescript
// HIT owner routes — require deviceAuth
app.post('/api/hits', deviceAuth, createHit);
app.get('/api/hits', deviceAuth, listHits);
app.delete('/api/hits/:id', deviceAuth, deleteHit);
app.get('/api/hits/:id/photos', deviceAuth, listHitPhotos);
app.get('/api/hits/:id/responses', deviceAuth, listHitResponses);

// HIT public routes — respondents don't have accounts
// getHit, respondToHit, uploadHitPhoto, completeHit stay public
// (accessed via share link by non-app users)

// Inbox — require deviceAuth
app.get('/api/inbox/:device_id', deviceAuth, getInbox);

// Debug — require deviceAuth
app.post('/api/debug/sync', deviceAuth, debugSync);
app.get('/api/debug/sync/:device_id', deviceAuth, debugList);
app.get('/api/debug/sync/:device_id/:key{.+}', deviceAuth, debugGet);
```

### 2. Fix `listHits` global data leak — `hits.ts:263-266`

Remove the else branch that returns all HITs. Require `X-Device-ID` (guaranteed by middleware):

```typescript
// hits.ts — listHits
const deviceId = c.req.header('X-Device-ID')!; // guaranteed by deviceAuth
// Remove else branch that returns all HITs
// Keep group_id filter but scope it: only return HITs where device_id matches
```

### 3. Add ownership check to `deleteHit` — `hits.ts:426-455`

After fetching the HIT, verify the authenticated device owns it:

```typescript
const deviceId = c.req.header('X-Device-ID')!;
const hit = await c.env.DB.prepare('SELECT * FROM hits WHERE id = ?').bind(hitId).first<Hit>();
if (!hit) return c.json({ error: 'HIT not found' }, 404);
if (hit.device_id !== deviceId) return c.json({ error: 'Forbidden' }, 403);
```

### 4. Fix `submitSensorData` identity binding — `sensors.ts:12`

Use header identity instead of body `device_id`:

```typescript
// sensors.ts — submitSensorData
const authenticatedDeviceId = c.req.header('X-Device-ID')!;
// Use authenticatedDeviceId for DB writes, ignore body device_id
```

### 5. Fix `getInbox` ownership — `inbox.ts:4`

Enforce that path `:device_id` matches authenticated identity:

```typescript
const authenticatedDeviceId = c.req.header('X-Device-ID')!;
const pathDeviceId = c.req.param('device_id');
if (pathDeviceId !== authenticatedDeviceId) {
  return c.json({ error: 'Forbidden' }, 403);
}
```

### 6. Fix `debugSync` identity binding — `debug.ts:8`

Use header identity, ignore body `device_id`:

```typescript
const authenticatedDeviceId = c.req.header('X-Device-ID')!;
const key = `debug/${authenticatedDeviceId}/${timestamp}-${body.type}.json`;
```

### 7. Fix `debugList`/`debugGet` ownership — `debug.ts:31,49`

Enforce path `:device_id` matches authenticated identity (same pattern as inbox).

### 8. Fail closed — 401 before 404

The `deviceAuth` middleware already returns 401/403 before handlers run. No additional work needed here since we're adding middleware at the route level.

## iOS Client Updates

The iOS app already sends `X-Device-ID` on most requests. Verify these routes include it:
- `GET /api/hits` — check `APIService.swift` sends header
- `DELETE /api/hits/:id` — check header is sent
- `GET /api/inbox/:device_id` — check header is sent
- `POST /api/debug/sync` — check header is sent

Search for calls missing the header: `Grep for "api/hits" and "api/debug" and "api/inbox" in ios/Robo/Services/`

## What Stays Public (No Auth)

These routes are intentionally public — accessed by share-link recipients who don't have the app:
- `GET /api/hits/:id` — View HIT details (share link)
- `POST /api/hits/:id/respond` — Submit response to HIT
- `POST /api/hits/:id/upload` — Upload photo for HIT
- `PATCH /api/hits/:id/complete` — Mark HIT complete
- `GET /hit/:id` — HIT web page
- `GET /hit/:id/og.png` — OG image
- `POST /api/devices/register` — New device registration
- `GET /health` — Health check

## Testing

### Negative auth tests (Vitest)

```typescript
// tests/auth.test.ts
describe('Auth enforcement', () => {
  it('GET /api/hits without X-Device-ID returns 401', ...);
  it('DELETE /api/hits/:id with wrong device returns 403', ...);
  it('GET /api/inbox/:device_id with mismatched auth returns 403', ...);
  it('POST /api/debug/sync without X-Device-ID returns 401', ...);
  it('GET /api/debug/sync/:device_id with mismatched auth returns 403', ...);
});
```

### Live smoke test after deploy

```bash
# Should return 401 (currently returns 200)
http --timeout=10 GET https://api.robo.app/api/hits
http --timeout=10 GET https://api.robo.app/api/debug/sync/random-device
http --timeout=10 GET https://api.robo.app/api/inbox/00000000-0000-0000-0000-000000000000
```

## Acceptance Criteria (from #176)

- [ ] Unauthenticated requests to private HIT/debug/inbox endpoints return 401
- [ ] Authenticated device A cannot read/write/delete device B resources (returns 403)
- [ ] Public HIT share link flow still works (get/respond/upload/complete)
- [ ] `listHits` never returns global data without auth
- [ ] `submitSensorData` uses header identity, not body
- [ ] `getInbox` enforces ownership
- [ ] Debug routes enforce ownership
- [ ] iOS client continues to work (sends X-Device-ID on all affected routes)

## Files to Modify

| File | Change |
|------|--------|
| `workers/src/index.ts` | Add `deviceAuth` to 8 routes |
| `workers/src/routes/hits.ts` | Remove global list fallback, add ownership to delete |
| `workers/src/routes/sensors.ts` | Use header device_id, ignore body |
| `workers/src/routes/inbox.ts` | Add ownership check in getInbox |
| `workers/src/routes/debug.ts` | Use header device_id in sync, ownership check in list/get |
| `workers/tests/auth.test.ts` | New: negative auth + IDOR tests |
