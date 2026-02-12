---
title: "feat: HIT Link with Personalized OG Preview (Static POC)"
type: feat
date: 2026-02-12
---

# HIT Link with Personalized OG Preview — Static POC

## Overview

Build a static proof-of-concept for **HIT (Human Intelligence Task) links** — shareable URLs that show personalized Open Graph previews in iMessage, Slack, and other platforms. When someone receives a link like `robo.app/demo/hit/`, the link preview shows a custom card: **"Hi James, Matt needs your help scanning a room"**.

This is a **growth hacking mechanism**: the personalized preview builds trust with recipients who've never heard of Robo, making them more likely to tap the link.

## Problem Statement

AI agents need real-world sensor data (LiDAR, photos, barcodes) from humans who may not have the Robo app. Today there's no way to:
1. Send someone a task request with a personalized, trust-building preview
2. Show the recipient WHO is asking and WHAT they need before they even tap the link
3. Guide them to install and complete the task

The link preview is the first impression — it needs to feel personal, not spammy.

## Proposed Solution — Static POC

Deploy a **single static demo page** on the existing `robo.app` Cloudflare Pages site at `site/demo/hit/index.html`. This demonstrates:

1. **Personalized OG image** (1200x630 PNG) showing sender name, recipient name, and task type
2. **Landing page** that a recipient would see after tapping the link
3. **Design language** consistent with the existing robo.app site

### What This POC Proves

- Link previews work correctly in iMessage, Slack, Discord, Twitter/X
- The personalized card format builds trust and communicates intent
- The design language is compelling enough to drive taps

### What This POC Does NOT Do (Deferred to Dynamic Version)

- Dynamic per-task pages (this is one hardcoded demo)
- Server-side OG image generation (`workers-og` + satori + resvg-wasm — researched, ready for Phase 2)
- Database-backed HIT tracking
- `hit.robo.app` subdomain routing

## Technical Approach

### Files to Create

```
site/
├── demo/
│   └── hit/
│       ├── index.html          # Landing page for the HIT link
│       └── og-hit-preview.png  # Personalized OG image (1200x630)
```

### 1. Personalized OG Image (`og-hit-preview.png`)

**Dimensions:** 1200 x 630 px (standard OG image size)

**Design** — based on existing `site/og-image.svg` design tokens:
- Background: `#06060a` with dot grid pattern and blue radial glow
- Robot icon (reuse the blue rounded rect with eyes + smile)
- Personalized text: **"Hi James"** (large, white) + **"Matt needs your help"** (medium, dim)
- Task description: **"Scan your master bedroom with LiDAR"** (blue accent)
- Skill type pill: `LIDAR` (blue pill, matching existing feature pills)
- `robo.app` branding at bottom

**Production approach:** Create as SVG first (template from `og-image.svg`), then convert to PNG. For the static POC, use `agent-browser screenshot` at 1200x630 of a purpose-built HTML render, or create in an image tool.

**Platform requirements** (from research):
- Must be PNG (not SVG — no platform supports SVG for og:image)
- Must be under 1MB
- Must be served over HTTPS at an absolute URL
- `og:image:width` and `og:image:height` meta tags required

### 2. Landing Page (`index.html`)

**URL:** `https://robo.app/demo/hit/` (or `https://robo.app/demo/hit/index.html`)

**OG Meta Tags:**
```html
<meta property="og:type" content="website">
<meta property="og:url" content="https://robo.app/demo/hit/">
<meta property="og:title" content="Hi James — Matt needs your help">
<meta property="og:description" content="Scan your master bedroom with LiDAR. Takes about 2 minutes with the Robo app.">
<meta property="og:image" content="https://robo.app/demo/hit/og-hit-preview.png">
<meta property="og:image:width" content="1200">
<meta property="og:image:height" content="630">
<meta property="og:site_name" content="ROBO.APP">

<meta name="twitter:card" content="summary_large_image">
<meta name="twitter:title" content="Hi James — Matt needs your help">
<meta name="twitter:description" content="Scan your master bedroom with LiDAR. Takes about 2 minutes.">
<meta name="twitter:image" content="https://robo.app/demo/hit/og-hit-preview.png">
```

**Page Design — what the recipient sees after tapping:**

Use the `/frontend-design` skill to create a polished, distinctive page matching robo.app's design language (dark bg, dot grid, blue glow, JetBrains Mono + DM Sans).

**Key sections:**
1. **Header** — Robot icon + "ROBO.APP" wordmark (smaller than main site)
2. **Personalized greeting** — "Hi James" (large) + "Matt needs your help" (subtitle)
3. **Task card** — bordered card showing:
   - Task: "Scan your master bedroom"
   - Type pill: `LIDAR`
   - Estimated time: "~2 minutes"
   - Brief description of what they'll do
4. **CTA button** — "Get Robo" (links to App Store / TestFlight)
5. **How it works** — 3 simple steps: Install → Open task → Scan & sync
6. **Trust signals** — "Open source" + "Your data stays on your device" + "No account required"
7. **Footer** — robo.app branding

**Design principles:**
- Mobile-first (recipients will view on phones from iMessage/Slack)
- Fast loading (no external dependencies beyond Google Fonts)
- All CSS inline (matching existing site pattern)
- No JavaScript required for core content
- Accessibility: proper heading hierarchy, semantic HTML

### 3. Deploy

```bash
wrangler pages deploy site --project-name=robo-app --commit-dirty=true --branch=main
```

Then test by sharing `https://robo.app/demo/hit/` in:
- iMessage (primary channel)
- Slack
- Discord
- Twitter/X DMs

## Acceptance Criteria

- [ ] OG image is 1200x630 PNG showing "Hi James, Matt needs your help" with Robo branding
- [ ] Link preview renders correctly in iMessage (shows personalized card)
- [ ] Link preview renders correctly in Slack
- [ ] Landing page loads on mobile with task details and CTA
- [ ] Design matches robo.app aesthetic (dark theme, blue accents, monospace fonts)
- [ ] Page weight under 100KB (HTML + inline CSS, excluding OG image)
- [ ] OG image under 500KB

## Phase 2: Dynamic Version (Post-POC)

Once the static POC validates the concept, the dynamic version uses:

- **`workers-og`** library (satori + resvg-wasm) for on-the-fly PNG generation
- **Three-tier caching:** Cache API (edge) → R2 (durable) → Generate (CPU-intensive)
- **D1 `hits` table** for tracking: sender, recipient, task type, status, created_at
- **`hit.robo.app` subdomain** via Cloudflare Workers custom domain
- **Short IDs** (8 chars, URL-safe) for clean URLs: `hit.robo.app/abc12345`
- **Paid Workers plan** ($5/mo) needed for reliable CPU time on uncached image generation

All of this has been researched and documented — ready to implement when the static POC is validated.

## References

- Existing OG image template: `site/og-image.svg`
- Existing site design: `site/index.html` (CSS variables, fonts, component patterns)
- `workers-og` library: wraps satori + resvg-wasm for Cloudflare Workers OG image generation
- Platform requirements: PNG required (no SVG support), 1200x630, under 5MB, absolute HTTPS URLs
- iMessage crawler spoofs Facebook/Twitter user agents, fetches from sender's device
- Slack only reads first 32KB of HTML — OG tags must be near top of `<head>`
