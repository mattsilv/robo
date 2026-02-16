---
title: "HIT Management UI: Polish & Remaining Features"
type: feat
status: active
date: 2026-02-15
issue: "#171"
---

# HIT Management UI: Polish & Remaining Features

## Overview

Complete the HIT management interface with progress indicators, response loading for all types, delete action, empty states, enhanced sharing, and tab badges. All UI work follows existing patterns in `HitListView.swift` and `HitDetailView.swift`.

## Acceptance Criteria

- [x] All HIT types load responses in detail view (not just group_poll/availability)
- [x] Progress indicator on list cards: "2/4 responded" for group_polls
- [x] Apple Intelligence summarize button for poll results (iOS 26+ only, graceful fallback)
- [x] Pull-to-refresh shows inline loading, not full-screen spinner
- [x] Empty state when 0 responses: "Waiting for responses..."
- [x] Share sheet includes poll results text (not just URL)
- [x] Swipe-to-delete on HIT list + delete button in detail view
- [x] Badge on HITs tab when new responses arrive

## Implementation Plan

### 1. Load responses for all HIT types

**File:** `ios/Robo/Views/HitDetailView.swift`

Currently the detail view only renders responses for `group_poll` and `availability` types. Add a generic response section that renders for `photo` and any other type.

```swift
// After the existing group_poll/availability sections, add:
if hit.hit_type != "group_poll" && hit.hit_type != "availability" && !responses.isEmpty {
    Section("Responses") {
        ForEach(responses, id: \.id) { response in
            ResponseRow(response: response)
        }
    }
}
```

The `fetchHitResponses(hitId:)` API call already exists in `APIService.swift:153`.

### 2. Progress indicator on list cards

**File:** `ios/Robo/Views/HitListView.swift` (HitCard component, ~line 84)

For group_polls, fetch response count and show progress. Two approaches:

**Option A (preferred — backend):** Add `response_count` and `participant_count` to the `GET /api/hits` list endpoint response so no extra API calls are needed per card.

**File:** `workers/src/routes/hits.ts` (~line 248, list endpoint)

```sql
SELECT h.*,
  (SELECT COUNT(*) FROM hit_responses WHERE hit_id = h.id) as response_count
FROM hits h WHERE h.device_id = ?
```

**iOS side:** Show in HitCard:
```swift
if let responseCount = hit.response_count, let total = hit.participant_count {
    Text("\(responseCount)/\(total) responded")
        .font(.caption)
        .foregroundStyle(.secondary)
}
```

### 3. Apple Intelligence summarization

**File:** `ios/Robo/Views/HitDetailView.swift`

Add an optional "Summarize" button that uses iOS 26 FoundationModels (already used in `CreateAvailabilityHITTool.swift`).

```swift
// Guard availability
if #available(iOS 26, *) {
    Button("Summarize Results") {
        await summarizeResults()
    }
}
```

Build the prompt from response data, pass to `LanguageModelSession`. Show result in an expandable section. Graceful no-op on devices without Apple Intelligence.

### 4. Inline pull-to-refresh loading

**File:** `ios/Robo/Views/HitDetailView.swift`

Replace the full-screen `ProgressView("Loading...")` pattern. Use a `@State private var isRefreshing = false` flag and show a small inline indicator instead of replacing content.

```swift
.refreshable {
    isRefreshing = true
    await loadData()
    isRefreshing = false
}
```

Only show full-screen spinner on initial load (`responses.isEmpty && isLoading`).

### 5. Empty state for 0 responses

**File:** `ios/Robo/Views/HitDetailView.swift`

```swift
if responses.isEmpty && !isLoading {
    ContentUnavailableView(
        "Waiting for responses...",
        systemImage: "clock",
        description: Text("Share the link and responses will appear here")
    )
}
```

### 6. Share sheet with results text

**File:** `ios/Robo/Views/HitDetailView.swift`

Build a formatted text summary of results and include it in the `ShareLink` or `UIActivityViewController` items alongside the URL.

```swift
let shareItems: [Any] = [hitURL, formattedResultsText].compactMap { $0 }
```

### 7. Delete HIT action

**Files:** `ios/Robo/Views/HitListView.swift`, `ios/Robo/Views/HitDetailView.swift`, `ios/Robo/Services/APIService.swift`

**Critical gotcha (from docs/solutions):** Explicit save after delete if using SwiftData. HITs are API-only so this is a network delete.

**Add to APIService:**
```swift
func deleteHit(id: String) async throws {
    // DELETE /api/hits/:id already exists in backend (hits.ts:426)
    let _: EmptyResponse = try await request(path: "/api/hits/\(id)", method: "DELETE")
}
```

**List swipe-to-delete:**
```swift
.swipeActions(edge: .trailing) {
    Button(role: .destructive) {
        Task { await deleteHit(hit) }
    } label: {
        Label("Delete", systemImage: "trash")
    }
}
```

**Detail view:** Add a toolbar button or destructive button at bottom.

### 8. Tab badge for new responses

**File:** `ios/Robo/Views/ContentView.swift`

Add `@State private var hitBadgeCount: Int = 0` and apply `.badge(hitBadgeCount)` to the HITs tab.

Update count when:
- Push notification arrives for HIT response (`AppDelegate.swift` notification handler)
- Clear when user visits HITs tab

```swift
Tab("HITs", systemImage: "link.badge.plus") {
    HitListView(deepLinkHitId: $deepLinkHitId)
}
.badge(hitBadgeCount)
```

## Design Notes

- Cards: `secondarySystemGroupedBackground` (light/dark)
- Accent: `#2563EB` / `Color(red: 0.15, green: 0.39, blue: 0.92)`
- Dates include year: "Thu Feb 20, 2027"
- Follow existing `StatusPill` component pattern (HitDetailView:514-549)

## Key Files

| File | Changes |
|------|---------|
| `ios/Robo/Views/HitListView.swift` | Progress indicator, swipe-to-delete |
| `ios/Robo/Views/HitDetailView.swift` | All-type responses, empty state, inline refresh, summarize, share, delete |
| `ios/Robo/Views/ContentView.swift` | Tab badge |
| `ios/Robo/Services/APIService.swift` | deleteHit method |
| `workers/src/routes/hits.ts` | response_count in list endpoint |

## References

- Issue: #171
- PR #170 (base HIT list + detail views)
- `docs/solutions/database-issues/swiftdata-task-detached-isolation-and-delete-save-reliability-20260210.md` — delete patterns
- `docs/solutions/integration-issues/cloudflare-multi-service-deployment-hit-system-20260212.md` — deployment checklist
