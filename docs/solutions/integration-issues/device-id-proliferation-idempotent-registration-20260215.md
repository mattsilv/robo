---
title: "Device ID Proliferation — Idempotent Registration via vendor_id"
date: 2026-02-15
category: integration-issues
severity: critical
tags: [device-identity, d1, idempotent, vendor_id, testflight]
pr: "#185"
issue: "#183"
---

# Device ID Proliferation — Idempotent Registration via vendor_id

## Problem

One iPhone created **19 device registrations** in 6 days. Every TestFlight update or app reinstall generated a new device row in D1, because registration relied on a random UUID generated at first launch (stored in UserDefaults, which gets wiped on reinstall).

### Symptoms
- D1 `devices` table growing with duplicate rows for the same physical phone
- MCP tokens invalidated after each TestFlight update (new device ID = new token)
- Screenshot and capture history "lost" (tied to old device IDs)
- Device count metrics wildly inflated

### Impact
- Broken MCP connections after every TestFlight build
- User data fragmented across multiple device rows
- Impossible to track a device reliably across app updates

## Root Cause

The original registration flow:
1. App launch → generate `UUID()` → store in `UserDefaults`
2. `POST /api/devices/register` with that UUID → create new device row
3. TestFlight update → UserDefaults wiped → new UUID → new device row

There was no stable identifier linking registrations from the same physical device.

## Solution

**Use `UIDevice.identifierForVendor` (`vendor_id`)** — a stable per-device, per-vendor identifier that persists across app updates (only resets if ALL apps from the same vendor are uninstalled).

### Changes

**D1 Migration (`0008_vendor_id.sql`):**
- Added `vendor_id TEXT` column to `devices` table
- Created `UNIQUE INDEX` on `vendor_id` for upsert support

**Backend (`POST /api/devices/register`):**
- Accepts optional `vendor_id` in request body
- If `vendor_id` matches existing device: returns existing device row, regenerates MCP token
- If no match: creates new device row as before

**iOS (`DeviceService`):**
- Sends `UIDevice.current.identifierForVendor?.uuidString` on every registration call
- Falls back to UUID-based registration if `identifierForVendor` is nil (rare edge case)

### Key Design Decisions
- `vendor_id` is optional in the API to maintain backwards compatibility with older app versions
- Re-registration regenerates the MCP token on the **same device row** rather than creating a new one
- Unique index enforces idempotency at the database level (not just application logic)

## Prevention Strategies

1. **Never use random UUIDs for device identity** — they don't survive reinstalls
2. **Use `identifierForVendor`** for stable device identity on iOS
3. **Enforce uniqueness at the DB level** (unique index) — don't rely solely on app logic
4. **Make registration idempotent** — calling register twice with the same device should return the same result

## Verification

```sql
-- Check for duplicate vendor_ids (should return 0 rows)
SELECT vendor_id, COUNT(*) as cnt
FROM devices
WHERE vendor_id IS NOT NULL
GROUP BY vendor_id
HAVING cnt > 1;

-- Verify device reuse after TestFlight update
SELECT id, vendor_id, registered_at, updated_at
FROM devices
ORDER BY registered_at DESC LIMIT 10;
```

## Related

- Issue: #183 (device proliferation report)
- PR: #185 (fix implementation)
- Migration: `workers/migrations/0008_vendor_id.sql`
