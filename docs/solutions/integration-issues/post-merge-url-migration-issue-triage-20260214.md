---
title: "Post-merge cleanup: URL migration and GitHub issue triage after custom domains deployment"
date: "2026-02-14"
status: "solved"
category: "integration-issues"
component: "documentation, github-issues, landing-page"
tags:
  - url-migration
  - cloudflare-domains
  - issue-triage
  - post-deployment
  - documentation-sync
related_issues:
  - "126"
  - "130"
  - "131"
severity: "medium"
time_to_resolve: "~30 minutes"
---

## Problem

After merging PRs #126 (custom domains `api.robo.app`, `mcp.robo.app`) and #130 (device-scoped MCP auth), the codebase had significant documentation drift:

- **20+ stale URL references** to `robo-api.silv.workers.dev` scattered across README.md, site/index.html, site/hit/index.html, docs/testflight-deployment.md, and solution docs
- **17 of 21 open GitHub issues** were stale — completed features, post-hackathon ideas, or superseded items
- **README.md** still showed M1-era features and "Coming Soon" milestones despite LiDAR, MCP, HIT links, and device auth all being shipped
- **Issue #128** (demo sprint) was outdated and superseded

## Root Cause

Normal technical debt accumulation during rapid hackathon development. The custom domain migration was implemented in infrastructure (`wrangler.toml` routes) but documentation and code references weren't updated atomically. Issues accumulated over multiple sprints without pruning.

## Solution

### 1. Batch GitHub issue closure

Closed 17 stale issues (#14, #15, #16, #19, #20, #36, #39, #40, #41, #86, #87, #88, #89, #90, #91, #92, #128) using parallel `gh issue close` with consistent comment: "Closing — not applicable to hackathon deadline. Tracked for post-hackathon."

Kept 4 relevant issues open: #68 (UI bug affecting demo), #79 (CI token needed), #103 (HIT hardening), #113 (chat agent roadmap).

### 2. README.md rewrite

Complete rewrite reflecting shipped state:
- Listed shipped features: LiDAR scanning, MCP bridge, HIT links, device auth, guided capture
- Added MCP connection example with `mcp.robo.app`
- Expanded API endpoints table from 8 to 15 endpoints (added HIT, debug, MCP routes)
- Updated architecture diagram to show MCP client and HIT links
- Removed "Coming Soon" milestones and outdated status line

### 3. URL migration across codebase

| File | Change |
|------|--------|
| `site/hit/index.html` | `API_BASE` → `https://api.robo.app` |
| `site/index.html` | MCP command → `mcp.robo.app` |
| `docs/testflight-deployment.md` | API URL → `api.robo.app` |
| `README.md` | All 6 occurrences updated |

### 4. Fresh action items issue

Created #131 "Final sprint: remaining action items for Feb 16 deadline" with categorized checklist replacing the outdated #128.

## Files Changed

- `README.md` — Complete rewrite
- `site/index.html` — MCP endpoint URL
- `site/hit/index.html` — API_BASE variable
- `docs/testflight-deployment.md` — API URL

## Verification

```bash
# Confirm no stale URLs in key files
grep -r "robo-api\.silv\.workers\.dev" README.md CLAUDE.md
# Should return nothing

# Confirm correct open issue count
gh issue list --state open
# Should show: #68, #79, #103, #113, #131
```

## Prevention

### 1. CI URL scanning

Add a grep check to CI that fails on stale domain references in user-facing files:

```bash
STALE=$(grep -r "robo-api\.silv\.workers\.dev" \
  --include="*.md" --include="*.html" --include="*.swift" \
  README.md CLAUDE.md site/ docs/ || true)
if [ -n "$STALE" ]; then echo "Stale URLs found:" && echo "$STALE" && exit 1; fi
```

### 2. Centralize API base URLs

Use config constants (`DeviceConfig.swift`, `config.ts`) instead of hardcoding URLs in docs and HTML. Reference the config as the source of truth.

### 3. Atomic documentation updates

When changing infrastructure (domains, routes, auth), update docs in the same PR. Use `grep -r "old-pattern"` before merging to catch stragglers.

### 4. Issue hygiene during hackathons

Label issues at creation (`hackathon-scope` vs `post-hackathon`). Run `gh issue list --state open` weekly and close anything that's been shipped or deferred.

## Related Documentation

- [docs/cloudflare-resources.md](../cloudflare-resources.md) — Infrastructure inventory (already updated with custom domains)
- [docs/solutions/integration-issues/mcp-server-cloudflare-workers-claude-code-bridge-20260214.md](mcp-server-cloudflare-workers-claude-code-bridge-20260214.md) — MCP bridge implementation
- [docs/solutions/security/mcp-device-scoped-auth-bearer-token-20260214.md](../security/mcp-device-scoped-auth-bearer-token-20260214.md) — Device-scoped auth
