---
title: "XSS, Unbounded R2 Growth, and Unstable Poll Winner (PR #170)"
date: 2026-02-15
category: security-issues
tags: [security, xss, r2, storage, ios, poll, stability]
severity: [P1, P2, P2]
components: [workers/src/routes/hitPage.ts, workers/src/routes/ogImage.ts, ios/Robo/Views/HitDetailView.swift]
status: fixed
pr: 170
---

# XSS, Unbounded R2 Growth, and Unstable Poll Winner

Three issues found by Codex automated review on PR #170 (OG images + HIT management UI).

## P1: Reflected XSS in HIT Page Route

**Symptom:** `hitPage.ts` injected `hitId` into a single-quoted JS string using only HTML escaping. A crafted path like `/hit/%27;alert(1)//` could break out and execute arbitrary script.

**Root cause:** `escapeHtml()` only escaped `& < > "` — not `'`, `\`, or other JS-significant characters. The hitId was used in a JS string context (`var hitId = '${escapeHtml(hitId)}'`) where HTML escaping is insufficient.

**Fix:** Added a dedicated `escapeJs()` function that escapes `\`, `'`, `<`, `>`, `\n`, `\r`. Used `escapeJs()` for the JS string context. Also added `'` → `&#39;` to `escapeHtml()` for defense-in-depth.

**Key lesson:** Always match the escaping function to the output context (HTML attribute, JS string, URL, CSS). HTML escaping in a JS string is a classic XSS vector.

## P2: OG Image Endpoint Caches Misses (Unbounded R2 Growth)

**Symptom:** Requesting `/hit/<random-id>/og.png` for a non-existent HIT would generate a fallback image and cache it to R2 at `og/<random-id>.png`. Any attacker could inflate R2 storage by requesting arbitrary IDs.

**Root cause:** The cache-write at line 100 ran unconditionally — even when the HIT wasn't found in D1 and the code fell through to the default fallback image.

**Fix:** Track whether the HIT was found (`const hitExists = !!hit`) and only write to R2 when `hitExists` is true. Fallback images are still generated on-the-fly but never persisted.

**Key lesson:** Never cache negative/fallback results without bounds. If the cache key comes from user input, an attacker can enumerate infinite keys.

## P2: Poll Winner Highlighting Unstable on Ties

**Symptom:** In `HitDetailView.swift`, the poll "winner" (highlighted in blue) could change between renders when multiple date options had the same vote count, because dictionary iteration order is non-deterministic.

**Root cause:** `computePollTallies()` sorted only by `.count` descending. Tied entries had arbitrary order from `Dictionary` iteration. The winner check (`index == 0`) would pick whichever happened to land first.

**Fix:**
1. Added stable tiebreaker: `.sorted { $0.count != $1.count ? $0.count > $1.count : $0.slot < $1.slot }`
2. Only highlight as winner when there's a sole leader: `let winnerCount = tallies.filter { $0.count == maxVotes }.count` → `isWinner = index == 0 && winnerCount == 1`

**Key lesson:** When sorting data for UI display, always include a deterministic tiebreaker (alphabetical, chronological, by ID). Never rely on dictionary/set iteration order.

## Prevention

- **XSS:** Use context-appropriate escaping functions. Consider Content Security Policy headers.
- **R2 growth:** Validate that the underlying resource exists before caching. Add R2 object count monitoring.
- **Sort stability:** Always add a secondary sort key when the primary key can have duplicates.
