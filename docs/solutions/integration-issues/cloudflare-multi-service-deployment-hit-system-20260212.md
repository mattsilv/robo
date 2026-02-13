---
title: "HIT System End-to-End Deployment — Workers, D1, R2, and Pages Functions"
date: 2026-02-12
category: integration-issues
tags:
  - cloudflare-workers
  - cloudflare-pages
  - cloudflare-d1
  - cloudflare-r2
  - pages-functions
  - hono
  - cors
  - deployment
severity: high
component:
  - workers
  - pages-functions
  - d1
  - r2
status: resolved
related_prs:
  - "97"
  - "100"
---

# HIT System End-to-End Deployment — Workers, D1, R2, and Pages Functions

## Problem

The HIT (Human Intelligence Task) system was built across PRs #97 (static POC) and #100 (functional backend + web capture) but couldn't be tested end-to-end after merging. Multiple Cloudflare deployment steps were missing or misconfigured.

**Symptoms:**
- HIT API endpoints returning 404 (Workers not redeployed)
- Dynamic HIT pages at `/hit/:id` not rendering (Pages Functions not deployed)
- Assumed R2 CORS was blocking browser uploads (false — architecture doesn't require it)
- Unclear whether D1 migration had been applied

## Investigation

### 1. D1 Migration Status — Ambiguous CLI Output
```bash
wrangler d1 migrations list robo-db --remote
# Output: "No migrations to apply" — unclear if already applied or not found
```

**Fix:** Verify tables directly:
```bash
wrangler d1 execute robo-db --remote \
  --command "SELECT name FROM sqlite_master WHERE type='table';"
```
Result: `hits` and `hit_photos` tables present — migration was already applied.

### 2. R2 CORS — False Assumption
```bash
wrangler r2 bucket cors list robo-data
# Output: "CORS configuration does not exist"
```

Tried multiple JSON formats to set CORS — all failed with "not well formed." This led to re-analyzing the upload architecture.

### 3. Architecture Re-Analysis — Key Insight

The upload flow is **Browser → Workers → R2 binding**, not Browser → R2 directly:

```
Browser (robo.app)
    ↓ POST /api/hits/:id/upload
Workers API (robo-api.silv.workers.dev)   ← Hono cors() handles cross-origin here
    ↓ env.BUCKET.put()                    ← R2 binding, server-to-server
R2 (robo-data bucket)
```

**R2 CORS is NOT needed.** The cross-origin request is Browser → Workers, handled by Hono's `cors()` middleware. R2 CORS would only be needed for direct browser → R2 uploads via presigned URLs.

### 4. Workers Not Deployed
The HIT route handlers were merged but Workers hadn't been redeployed. API returned 404 for `/api/hits/*`.

### 5. Pages Functions Path
`functions/hit/[id].ts` existed at project root but Pages hadn't been redeployed. The `functions/` directory must be a sibling of the deploy directory (`site/`), and `wrangler pages deploy` must run from the project root.

## Root Cause

Four independent blockers, all deployment-related:

1. **Workers API not redeployed** after merging PR #100 with new HIT routes
2. **Pages Functions not deployed** — `functions/hit/[id].ts` wasn't live
3. **R2 CORS misunderstanding** — assumed browser → R2 architecture, but actual architecture uses Workers binding (no CORS needed)
4. **D1 migration status unclear** — `migrations list` output was ambiguous; needed direct table verification

## Solution

### Deploy Workers
```bash
cd /path/to/robo/workers
wrangler deploy
```

### Deploy Pages + Functions
```bash
cd /path/to/robo  # Project root, NOT site/
wrangler pages deploy site --project-name=robo-app --commit-dirty=true --branch=main
```

Output must show `"Uploading Functions bundle"` — confirms `functions/` directory was detected.

### Verify D1 Tables
```bash
wrangler d1 execute robo-db --remote \
  --command "SELECT name FROM sqlite_master WHERE type='table';"
```

### Skip R2 CORS
No configuration needed. Uploads go through Workers binding.

## Verification

```bash
# 1. Create a HIT
http --ignore-stdin POST https://robo-api.silv.workers.dev/api/hits \
  recipient_name="James" \
  task_description="Photo the inside of your fridge" \
  agent_name="Simple Chef Agent" --timeout=10

# 2. Open the returned URL — verify personalized OG tags + camera button
# https://robo.app/hit/{ID}

# 3. Check status transition (pending → in_progress on first view)
http --ignore-stdin GET https://robo-api.silv.workers.dev/api/hits/{ID} --timeout=10
```

## Prevention

### When R2 CORS IS vs IS NOT Needed

| Architecture | R2 CORS? | Why |
|---|---|---|
| Browser → Workers API → R2 binding | **No** | Workers binding is server-to-server; Hono `cors()` handles browser→Workers |
| Browser → R2 presigned URL (direct PUT) | **Yes** | Browser sends cross-origin request directly to R2 |
| iOS app → Workers API → R2 binding | **No** | Native apps don't send CORS preflight |

### Multi-Service Deployment Checklist

After merging changes that touch multiple Cloudflare services:

- [ ] `wrangler deploy` — Workers API (if `workers/**` changed)
- [ ] `wrangler pages deploy site` — Pages + Functions (if `site/**` or `functions/**` changed)
- [ ] `wrangler d1 migrations apply robo-db --remote` — D1 (if new migration files)
- [ ] Verify Workers health: `http GET https://robo-api.silv.workers.dev/health --timeout=10`
- [ ] Verify Pages Function: open dynamic URL in browser
- [ ] Verify D1 tables: `wrangler d1 execute robo-db --remote --command "SELECT name FROM sqlite_master WHERE type='table';"`

### Pages Functions Directory Convention

```
robo/                          ← Run wrangler pages deploy from HERE
├── site/                      ← Static assets (deploy target)
│   ├── index.html
│   └── demo/
└── functions/                 ← Pages Functions (auto-detected at project root)
    └── hit/
        └── [id].ts            ← Dynamic route: /hit/:id
```

**Key:** `functions/` must be at the same level as the deploy directory. Running `wrangler pages deploy site` from project root auto-detects it.

## Related Documentation

- [Cloudflare Resources Inventory](../../cloudflare-resources.md)
- [Hono + Zod Validation Pattern](../build-errors/hono-zod-cloudflare-workers-validation-20260210.md)
- [M1 Hardening Guide](../integration-issues/m1-hardening-mvp-to-demo-ready-20260210.md)
- [HIT Static POC Plan](../../plans/2026-02-12-feat-hit-link-personalized-og-preview-plan.md)
- [HIT Functional System Plan](../../plans/2026-02-12-feat-functional-hit-system-web-capture-chat-plan.md)
