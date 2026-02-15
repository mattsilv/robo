---
title: Stale Cloudflare Workers deployment after PR merge — 404 on new API endpoints
date: 2026-02-15
category: integration-issues
severity: high
component: cloudflare-workers
tags: [ci-cd, workers-deployment, api-endpoints, stale-build, smoke-tests]
symptoms:
  - iOS app shows "server error 404 error not found" on Developer Portal
  - /api/keys endpoint returns 404 despite code merged to main
  - Endpoint code exists in repository but not deployed
root_cause: Workers not redeployed after merge — CI failed silently due to missing wasm dependency
resolution_time: ~30min
related_docs:
  - docs/solutions/integration-issues/cloudflare-multi-service-deployment-hit-system-20260212.md
related_prs: ["#162", "#165", "#168"]
---

# Stale Cloudflare Workers After PR Merge

## Problem

After merging PRs #162 and #165 (API key management for Developer Portal), the iOS app showed "server error 404 error not found" when accessing `/api/keys`. The code was on `main` but the live Workers API was stale.

## Investigation

1. **Git log:** PRs confirmed merged to main
2. **API test:** `httpie https://api.robo.app/api/keys` returned 404 (not auth error)
3. **GitHub PR status:** Both PRs showed MERGED with passing checks
4. **Deploy attempt:** `wrangler deploy` failed — missing `@aspect-build/resvg-wasm` (stale `node_modules`)
5. **Clean install:** `rm -rf node_modules && npm install` resolved wasm issue
6. **Redeploy:** After clean install, `/api/keys` returned proper 401 (not 404)

## Root Cause

Two compounding issues:

1. **Silent CI failure:** `deploy-workers.yml` either didn't trigger (path filter) or failed during build with unresolvable wasm dependency — no notification of failure
2. **No post-deploy verification:** No smoke tests to confirm endpoints were actually live after deployment

## Solution

### 1. Manual fix
```bash
cd workers
rm -rf node_modules && npm install
wrangler deploy
```

### 2. Pre-deploy tests added to CI
```yaml
- name: Run tests
  working-directory: workers
  run: npm test
```

### 3. Post-deploy smoke tests added to CI
```yaml
- name: Smoke test deployed API
  run: |
    sleep 5
    echo "Testing /health..."
    STATUS=$(curl -s -o /dev/null -w '%{http_code}' https://api.robo.app/health)
    if [ "$STATUS" != "200" ]; then echo "FAIL: /health returned $STATUS"; exit 1; fi

    echo "Testing /api/keys (auth required)..."
    STATUS=$(curl -s -o /dev/null -w '%{http_code}' -H 'X-Device-ID: smoke-test' -H 'Authorization: Bearer fake' https://api.robo.app/api/keys)
    if [ "$STATUS" = "404" ]; then echo "FAIL: /api/keys returned 404 — routes not registered"; exit 1; fi

    echo "Testing /api/devices/register exists..."
    STATUS=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'Content-Type: application/json' -d '{}' https://api.robo.app/api/devices/register)
    if [ "$STATUS" = "404" ]; then echo "FAIL: /api/devices/register returned 404"; exit 1; fi

    echo "All smoke tests passed"
```

## Prevention

### Checklist for new API routes
- [ ] Add route handler in `workers/src/routes/*.ts`
- [ ] Register route in `workers/src/index.ts`
- [ ] Write vitest test
- [ ] Add endpoint to post-deploy smoke tests in `deploy-workers.yml`
- [ ] Test locally with `npm run dev` before pushing

### Key learning
A successful CI status doesn't mean code is deployed. Always verify with smoke tests hitting actual production endpoints. This is the **second time** this exact issue occurred — see [cloudflare-multi-service-deployment-hit-system-20260212.md](cloudflare-multi-service-deployment-hit-system-20260212.md) for the first occurrence with HIT routes.
