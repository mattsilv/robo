---
title: "feat: Capture-First UX Redesign"
type: feat
date: 2026-02-13
---

# Capture-First UX Redesign

## Overview

Redesign the app's primary experience from "browse agents, then capture" to "capture first, route after." The first screen should show large, single-tap buttons for each sensor type. After capture, a lightweight heuristic infers intent and suggests which agent(s) should receive the data. User always confirms before routing.

**Core insight:** Users don't want to think about agents. They want to capture data as fast as possible and trust the system to figure out where it goes.

## Problem Statement

Current UX friction points:
1. **Agent list on launch is confusing** — users don't know what agents are or why they're seeing a list of them
2. **Capture requires agent context** — you must tap an agent card's "Scan Now" to start any capture, coupling "what" (data) to "who" (agent)
3. **No zero-context capture** — impossible to just "take a photo" without choosing an agent first
4. **Motion data only pulls today** — `MotionService.captureToday()` queries from midnight to now (limited by design, not by API)
5. **No HealthKit integration** — sleep, workouts, and activity data are untapped sensor sources

## Proposed Solution

### New Tab Structure

Replace the current 3-tab layout:

```
BEFORE: Agents | My Data | Settings
AFTER:  Capture | My Data | Settings
```

- **Capture tab** (new, first tab): Large capture buttons + pending agent requests section
- **My Data tab** (unchanged): History browsed by agent or by type
- **Settings tab** (unchanged): Device info, toggles

### Capture Home Screen (`CaptureHomeView`)

A grid of large, tappable cards — one per sensor type:

```
┌─────────────────────────────┐
│  Pending: Interior Designer │  ← Agent requests banner (if any)
│  wants a room scan          │
└─────────────────────────────┘

┌──────────┐  ┌──────────┐
│  📸      │  │  🏠      │
│  Photos  │  │  Room    │
│          │  │  Scan    │
└──────────┘  └──────────┘
┌──────────┐  ┌──────────┐
│  📦      │  │  🏃      │
│  Product │  │  Motion  │
│  Scan    │  │  & Health│
└──────────┘  └──────────┘
┌──────────┐  ┌──────────┐
│  ⬜      │  │  📡      │
│  Barcode │  │  Beacon  │
└──────────┘  └──────────┘
```

Single tap → launches capture immediately (instructions screen, then sensor).

### Post-Capture Routing (Heuristic for Demo)

After capture completes with no agent context:

1. **Heuristic intent detection** runs instantly (no API call, no latency):
   - LiDAR scan → suggest Interior Designer / Contractor Bot
   - Barcode scan → suggest Practical Chef (if food UPC) or Store Ops
   - Multi-photo with checklist items → suggest Smart Stylist / Playtime Muse
   - Product scan (barcode + photos) → suggest Practical Chef
   - Motion/Health data → save locally (no obvious agent match yet)

2. **Routing confirmation sheet** slides up:
   ```
   ┌─────────────────────────────┐
   │  Room scan captured!        │
   │                             │
   │  Suggested:                 │
   │  🏠 Interior Designer       │
   │  🔨 Contractor Bot          │
   │                             │
   │  [Send to Interior Designer]│
   │  [Save to My Data only]     │
   └─────────────────────────────┘
   ```

3. User taps confirm → data tagged with agent, sync animation plays
4. User taps "Save to My Data only" → data saved untagged

**Why heuristic, not AI:** Given the Feb 16 deadline, a rule-based heuristic looks identical in a demo and ships in an hour. Real AI model integration (Cloud or on-device) is a follow-up. The routing UI is the same either way — swap the heuristic for an API call later.

### Agent Requests (Preserved, Relocated)

Pending agent requests move from a dedicated tab to a **banner section** at the top of the Capture tab. If an agent has a pending request, it shows as a prominent card above the capture grid. Tapping it launches the capture with full `CaptureContext` (existing flow, unchanged).

When no requests are pending, the banner is hidden and the capture grid fills the screen.

## Technical Approach

### Phase 1: Capture Home Screen (Core UX change)

**Files to create:**
- `ios/Robo/Views/CaptureHomeView.swift` — New first tab with capture grid + agent request banner

**Files to modify:**
- `ios/Robo/Views/ContentView.swift` — Replace `AgentsView()` with `CaptureHomeView()`, rename tab from "Agents" to "Capture"
- `ios/Robo/Models/AppStrings.swift` — Update tab label string

**Key design decisions:**
- Capture buttons launch `fullScreenCover` directly (no agent context required)
- All existing capture views already accept `CaptureContext?` as optional — pass `nil` for zero-context captures
- Pending agent requests rendered inline using existing `AgentRequestCard` component (extracted from `AgentsView`)
- `AgentsView` can be kept as a secondary view (navigable from settings or agent request cards) or removed entirely

### Phase 2: Post-Capture Routing Sheet

**Files to create:**
- `ios/Robo/Views/RoutingSuggestionSheet.swift` — Bottom sheet shown after agent-less capture completes

**Files to modify:**
- `ios/Robo/Views/LiDARScanView.swift` — On dismiss without agent context, show routing sheet
- `ios/Robo/Views/PhotoCaptureView.swift` — Same
- `ios/Robo/Views/BarcodeScannerView.swift` — Same
- `ios/Robo/Views/ProductScanFlowView.swift` — Same

**Heuristic service:**
- `ios/Robo/Services/IntentHeuristicService.swift` — Maps capture type + metadata to suggested agents
- Returns `[SuggestedRoute]` with agent name, icon, color, confidence
- Rule-based: `switch sensorType { case .lidar: return [interiorDesigner, contractorBot] ... }`

### Phase 3: Motion 30-Day Expansion

**File to modify:**
- `ios/Robo/Services/MotionService.swift` — Change date range from "midnight today" to "30 days ago"

**Technical constraint:** `CMPedometer.queryPedometerData` has a ~7-day hardware limit on most devices. For 30 days:
- **Option A (quick):** Query the max available range (7 days). Show "Last 7 days" with a note that HealthKit integration coming for full 30-day history.
- **Option B (proper):** Use HealthKit `HKQuantityType(.stepCount)` for 30-day step data, keep CMMotionActivityManager for activity types (which does support longer ranges).

**Recommendation for demo:** Option A (7 days via CoreMotion) with a UI label change. Option B is the HealthKit work in Phase 4.

**Files to modify:**
- `ios/Robo/Services/MotionService.swift` — Parameterize the date range, default to 7 days back
- `ios/Robo/Views/MotionCaptureView.swift` — Update UI to say "Last 7 days" instead of "Today"
- `ios/Robo/Views/MotionResultView.swift` — Handle multi-day data display (daily summaries)

### Phase 4: HealthKit Integration (Stretch Goal / Post-Demo)

**New files:**
- `ios/Robo/Services/HealthKitService.swift` — Request authorization, query sleep/workout/activity
- `ios/Robo/Views/HealthCaptureView.swift` — Capture flow for health data
- `ios/Robo/Models/HealthRecord.swift` — SwiftData model (requires V8 schema migration)

**HealthKit data types to request:**
- `HKCategoryType(.sleepAnalysis)` — sleep intervals with stages
- `HKWorkoutType.workoutType()` — workout summaries (type, duration, calories, distance)
- `HKQuantityType(.stepCount)` — 30-day step history (replaces CoreMotion for historical data)
- `HKQuantityType(.activeEnergyBurned)` — daily active calories
- `HKQuantityType(.appleExerciseTime)` — daily exercise minutes

**NOT requesting** (per spec — no medical data):
- Heart rate, blood pressure, blood glucose, respiratory rate, body temperature, oxygen saturation

**Required entitlements & Info.plist:**
- Add HealthKit capability in project.yml
- `NSHealthShareUsageDescription` — "Robo reads your sleep, workout, and activity data to share with your AI agents."

**Schema migration V7 → V8:**
- Add `HealthRecord` model to `RoboSchemaV8`
- Fields: `id`, `capturedAt`, `dataType` (sleep/workout/activity), `dateRangeStart`, `dateRangeEnd`, `summaryJSON` (Data), `agentId?`, `agentName?`

### Phase 5: Enable Motion in Capture Grid

Currently `.motion` is excluded from `enabledSkillTypes` and has `case .motion: break` in `handleScanNow`. Enable it:

**Files to modify:**
- `ios/Robo/Views/CaptureHomeView.swift` — Include motion button in capture grid (it's already a separate view `MotionCaptureView`)

## Acceptance Criteria

### Must Have (Demo on Feb 16)
- [x] App launches to Capture tab with single-tap sensor buttons
- [x] Zero-context capture works for all sensor types (photo, LiDAR, barcode, product scan)
- [x] Post-capture routing sheet suggests agents based on heuristic
- [x] User can confirm routing or save locally
- [x] Pending agent requests shown as banner in Capture tab
- [x] Agent-initiated captures still work (tapping request banner)
- [x] Motion data pulls max available range (up to 7 days)
- [ ] All existing My Data / export flows unbroken

### Should Have (Before Feb 16 if time allows)
- [x] HealthKit sleep + workout data capture
- [x] 30-day motion via HealthKit step count query
- [x] Motion/health data shown as daily summaries (not flat activity list)

### Future (Post-Demo)
- [ ] Real AI model for intent detection (replace heuristic with API call)
- [ ] Multi-photo intent splitting (group photos by content, route separately)
- [ ] Real agent configuration (replace `MockAgentService`)
- [ ] Agent capability registry (agents declare what data types they accept)
- [ ] Offline intent detection queue (analyze when back online)
- [ ] Cloud AI privacy consent flow

## Dependencies & Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| Tab restructure breaks existing navigation flows | Medium | Test all capture → history → export paths after change |
| `CaptureContext = nil` causes crashes in capture views | Low | All capture views already handle optional context; grep for force-unwraps |
| CoreMotion 7-day limit surprises users expecting 30 days | High | Label UI as "Last 7 days" explicitly; HealthKit path for true 30-day |
| HealthKit App Store review requires specific usage strings | Medium | Write clear `NSHealthShareUsageDescription`; only request non-medical types |
| SwiftData V8 migration fails on existing installs | Low | Follow established migration pattern (V1→V7 works); backup-and-recreate fallback already exists |

## Separate Issues to File

### Issue 1: HealthKit Integration for Sleep, Workout, and Activity Data
Add HealthKit as a data source. Capture sleep analysis intervals, workout summaries, and daily activity metrics. Requires new SwiftData schema, HealthKit entitlement, and permission flow. See Phase 4 above for full spec.

### Issue 2: Makeup Color Palette Agent
**Use case:** User takes a selfie. AI detects it's a face/portrait photo. Routes to a "Color Analyst" or "Makeup Artist" agent that analyzes skin tone, eye color, and hair color to suggest a personalized makeup color palette (foundation, lip, eye shadow, blush).

**Why this matters:** This is a trending use case (people are sending selfies to ChatGPT for color analysis). Having this as a built-in agent demonstrates the power of the capture-first UX — take a selfie, AI figures out it should go to the color analyst, user confirms, gets a palette back.

**Growth hack angle:** Highly shareable output (palette cards). Users share their results on social media, driving organic downloads.

**Implementation notes:**
- Add "Color Analyst" to agent registry with capability: `.camera` (face/portrait photos)
- Intent heuristic: detect portrait/selfie photo → suggest Color Analyst
- Agent backend: use vision API to analyze skin undertone, suggest palette
- Output: visual palette card (shareable image)

### Issue 3: Trader Joe's Florist Agent
**Use case:** User takes multi-photos of flowers at Trader Joe's (or any store). AI detects floral content. Routes to a "Florist" agent that identifies the flowers, considers current season and availability, suggests which to buy and how to arrange them, then emails simple arrangement instructions.

**Why this matters:** Practical, delightful use case. Demonstrates multi-photo → actionable advice pipeline. The email delivery shows data leaving the app ecosystem (not just tagging).

**Implementation notes:**
- Add "Florist" agent with capability: `.camera` (multi-photo of flowers/plants)
- Intent heuristic: detect flower/plant photos → suggest Florist
- Agent backend: vision API identifies flower types, cross-references seasonal data
- Output: arrangement guide with step-by-step instructions, emailed to user
- Bonus: cost estimate based on typical TJ's pricing

## References

### Internal
- Current tab structure: `ios/Robo/Views/ContentView.swift`
- Agent list (to be replaced): `ios/Robo/Views/AgentsView.swift`
- Motion service (date range fix): `ios/Robo/Services/MotionService.swift:24-43`
- CaptureContext model: `ios/Robo/Models/AgentConnection.swift:62`
- Mock agents: `ios/Robo/Services/MockAgentService.swift`
- Compound flow pattern: `docs/solutions/architecture-patterns/compound-multi-sensor-capture-flow-pattern-20260212.md`
- Agent context threading: `docs/solutions/architecture-issues/swiftdata-schema-drift-agent-context-threading-20260212.md`

### Related Plans
- `docs/plans/2026-02-12-feat-agent-driven-capture-auto-complete-plan.md` — Phase 1-5 agent flow roadmap
- `docs/plans/2026-02-12-fix-agent-ux-photo-crash-and-polish-plan.md` — Camera permission + UX polish fixes
