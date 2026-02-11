---
title: "Nutritionix API Integration: Proxied Barcode Nutrition Lookup"
date: 2026-02-11
category: integration-issues
tags:
  - barcode-scanning
  - third-party-api
  - cloudflare-workers
  - swiftdata-migration
  - nutrition-data
  - api-proxy
component: BarcodeScanner, Workers
severity: medium
status: implemented
pr: https://github.com/mattsilv/robo/pull/62
issue: https://github.com/mattsilv/robo/issues/60
---

# Nutritionix API Proxy: Barcode Nutrition Lookup

## Problem

Scanned barcodes showed only raw UPC codes and symbology type — no product information. Food/grocery barcodes had no enrichment, making the scanner's output minimal and hard for AI agents to use meaningfully.

## Solution Overview

Proxy the Nutritionix API through our Cloudflare Workers backend so:
- API keys stay server-side (never in the iOS binary)
- iOS app only talks to our backend (single trust boundary)
- Background lookup happens after scan save (non-blocking UX)
- Nutrition data persists in SwiftData for offline access and export

## Architecture

```
iPhone (scan) → Workers /api/nutrition/lookup?upc=X → Nutritionix API
                    ↓
              Normalized JSON response
                    ↓
        iOS updates ScanRecord in SwiftData
```

## Implementation Details

### 1. Workers Proxy Endpoint

**File:** `workers/src/routes/nutrition.ts`

```typescript
// Key pattern: validate UPC with Zod, proxy to Nutritionix, normalize response
const parsed = NutritionLookupSchema.safeParse({ upc: c.req.query('upc') });
// ...
const resp = await fetch(
  `https://trackapi.nutritionix.com/v2/search/item?upc=${upc}`,
  { headers: { 'x-app-id': c.env.NUTRITIONIX_APP_ID, 'x-app-key': c.env.NUTRITIONIX_APP_KEY } }
);
```

Key decisions:
- **Secrets via `wrangler secret put`** — not in wrangler.toml (would leak in repo)
- **Returns `{ found: false }` for unknown UPCs** — not 404 (iOS can handle gracefully)
- **Returns 502 for Nutritionix API errors** — distinguishes upstream vs our failures
- **Normalizes field names** — `nf_calories` → `calories`, `nf_total_fat` → `fat`
- **Uses existing `deviceAuth` middleware** — only registered devices can proxy

### 2. SwiftData V3 Schema Migration

**File:** `ios/Robo/Models/RoboSchema.swift`

Added `RoboSchemaV3` with 16 new fields on `ScanRecord`. Critical rules:
- **All new fields MUST be optional or have defaults** (lightweight migration requirement)
- **`nutritionLookedUp: Bool = false`** prevents re-fetching on every view
- **`nutritionJSON: Data?`** stores raw response for export/debugging

```swift
// Lightweight migration — no data transformation needed
static let migrateV2toV3 = MigrationStage.lightweight(
    fromVersion: RoboSchemaV2.self,
    toVersion: RoboSchemaV3.self
)
```

Update `RoboApp.swift`: `Schema(versionedSchema: RoboSchemaV3.self)` (was V2).

### 3. Fire-and-Forget Background Lookup

**File:** `ios/Robo/Services/NutritionService.swift`

```swift
// In BarcodeScannerView, AFTER modelContext.save():
Task {
    await NutritionService.lookup(
        upc: code, record: record,
        apiService: apiService, modelContext: modelContext
    )
}
```

Pattern:
- Scan save + haptic + toast remain **instant**
- Nutrition lookup runs in background Task
- On success: updates ScanRecord fields, saves, prefetches thumbnail
- On failure: marks `nutritionLookedUp = true` to prevent re-fetching
- SwiftUI list rows update automatically via SwiftData observation

### 4. Image Caching

**File:** `ios/Robo/Services/ImageCacheService.swift`

- File-based cache in `Caches/nutrition-images/`
- SHA256 hash of URL as filename (using CryptoKit, no external deps)
- Two-phase load: check cache synchronously, then async prefetch if missing

## Gotchas Encountered

1. **Cloudflare Workers `wrangler secret`**: Must set secrets BEFORE deploy, or the env vars will be undefined at runtime. Use `echo "value" | wrangler secret put NAME`.

2. **SwiftData migration order**: `RoboMigrationPlan.schemas` array must list versions in order (V1, V2, V3). Missing an intermediate version causes crash.

3. **Nutritionix 404 handling**: Their API returns HTTP 404 for unknown UPCs (not an empty array). Must check `resp.status === 404` before `resp.json()`.

4. **SwiftUI `@Environment` capture**: In `BarcodeScannerView.handleScan()`, capture `apiService` and `modelContext` before the `Task {}` closure to avoid sendability issues.

## Prevention & Best Practices

- **Always proxy third-party APIs through Workers** — keeps secrets server-side, enables rate limiting, normalizes responses
- **Schema migrations: test with existing data** — install old build first, then upgrade
- **Background lookups: always set a "looked up" flag** — prevents infinite retry loops
- **Image caching: use content-addressable storage** — SHA256 of URL avoids filename conflicts

## Related Documentation

- [SwiftData Persistence Failure](../database-issues/swiftdata-persistence-failure-no-save-no-schema-versioning-20260210.md) — explicit save pattern, VersionedSchema requirement
- [SwiftData Derived Field Migration](../data-migration/swiftdata-derived-field-migration-userdefaults-versioning-20260210.md) — advanced migration patterns
- [Hono + Zod Cloudflare Workers Validation](../build-errors/hono-zod-cloudflare-workers-validation-20260210.md) — manual Zod validation pattern
- [M1 Hardening](../integration-issues/m1-hardening-mvp-to-demo-ready-20260210.md) — device auth middleware, error handling

## Files Changed

| File | Action | Purpose |
|------|--------|---------|
| `workers/src/routes/nutrition.ts` | Create | Nutritionix proxy endpoint |
| `workers/src/types.ts` | Modify | Env type + Zod schema + response type |
| `workers/src/index.ts` | Modify | Register route |
| `ios/Robo/Models/RoboSchema.swift` | Modify | V3 schema + migration |
| `ios/Robo/Models/NutritionResponse.swift` | Create | Codable model |
| `ios/Robo/Services/NutritionService.swift` | Create | Background lookup orchestrator |
| `ios/Robo/Services/ImageCacheService.swift` | Create | File-based image cache |
| `ios/Robo/Services/APIService.swift` | Modify | Add `lookupNutrition()` |
| `ios/Robo/Views/BarcodeScannerView.swift` | Modify | Wire up background lookup |
| `ios/Robo/Views/ScanHistoryView.swift` | Modify | Product thumbnail + calorie badge |
| `ios/Robo/Views/BarcodeDetailView.swift` | Modify | Nutrition facts card + attribution |
