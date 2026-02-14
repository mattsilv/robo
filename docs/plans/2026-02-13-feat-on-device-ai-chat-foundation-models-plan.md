---
title: "feat: On-device AI chat using Apple Foundation Models"
type: feat
status: completed
date: 2026-02-13
related_issues: ["#113"]
---

# On-Device AI Chat Using Apple Foundation Models

## Overview

Add a Chat tab to Robo powered by Apple's Foundation Models framework — the on-device LLM that ships with iOS 26. Phase 1 is a proof-of-concept: users can ask what agents are available, what each agent does, and how to use Robo's sensor capabilities. All inference runs locally on-device (no API keys, no cloud, no cost). Phase 2 (future) adds actionable capabilities — triggering captures, provisioning agents, sending data.

## Problem Statement

Issue #113 identifies chat-first UX as Robo's direction, but no chat exists today. Users must navigate multiple screens to discover agent capabilities. An on-device AI chat provides:

- **Zero-friction discovery** — ask "what can I do?" instead of browsing screens
- **Privacy** — conversations never leave the device
- **Offline capable** — works without internet
- **No backend cost** — Apple provides the model for free with iOS 26

## Technical Context

### Apple Foundation Models Framework

- **Import:** `import FoundationModels`
- **Minimum OS:** iOS 26 (announced WWDC 2025, ships fall 2025)
- **Devices:** iPhone 15 Pro+ (A17 Pro or later)
- **No entitlements needed** for basic text generation
- **Context window:** 4096 tokens (input + output combined) — small, requires careful prompt design
- **Performance:** ~30 tokens/sec, ~0.6ms time-to-first-token after prewarming

### Key API Surface

```swift
import FoundationModels

// Check availability
let model = SystemLanguageModel.default
switch model.availability {
case .available: // ready
case .unavailable(let reason): // .deviceNotEligible, .appleIntelligenceNotEnabled, .modelNotReady
}

// Create session with system prompt
let session = LanguageModelSession {
    "You are Robo's assistant..."
}

// Streaming response
let stream = session.streamResponse(to: "What agents are available?")
for try await partial in stream {
    // partial text updates
}
```

### Robo Codebase Integration Points

| What | Where | Pattern |
|------|-------|---------|
| Tab bar | `ContentView.swift` | `TabView` with 3 tabs → add 4th |
| Services | `RoboApp.swift:9-10` | `@Observable class` + `.environment()` injection |
| Agent data | `MockAgentService.swift` | `static func loadAgents() -> [AgentConnection]` |
| Agent skills | `AgentConnection.swift` | `SkillType` enum: `.lidar`, `.barcode`, `.camera`, etc. |
| String constants | `AppStrings.swift` | `enum AppStrings` with nested namespaces |

## Proposed Solution

### Architecture

```
┌─────────────────────────────────────────────────┐
│ ContentView (TabView)                           │
│  Tab 1: Capture  Tab 2: History  Tab 3: Chat    │
│                                   Tab 4: Settings│
└──────────────────────────┬──────────────────────┘
                           │
              ┌────────────▼────────────┐
              │      ChatTabView        │
              │  #available(iOS 26, *)  │
              └───┬─────────────┬───────┘
                  │             │
         Available?      Unavailable?
                  │             │
         ┌────────▼──┐  ┌──────▼──────────┐
         │ ChatView   │  │ ChatUnavailable │
         │ (messages,  │  │ View (per-reason│
         │  input bar, │  │  fallback UI)   │
         │  streaming) │  │                 │
         └──────┬─────┘  └─────────────────┘
                │
       ┌────────▼────────┐
       │  ChatService     │
       │  @Observable     │
       │  - session       │
       │  - messages[]    │
       │  - systemPrompt  │
       │  (built from     │
       │   MockAgentService│
       │   dynamically)   │
       └─────────────────┘
```

### New Files

| File | Purpose | ~Lines |
|------|---------|--------|
| `ios/Robo/Views/ChatTabView.swift` | Availability gate + routing | 50 |
| `ios/Robo/Views/ChatView.swift` | Chat UI — messages, input bar, streaming | 120 |
| `ios/Robo/Views/ChatUnavailableView.swift` | Fallback UIs per unavailability reason | 60 |
| `ios/Robo/Services/ChatService.swift` | `@Observable` — session, messages, send/stream logic | 80 |
| `ios/Robo/Models/ChatMessage.swift` | Simple message model (id, role, content, timestamp) | 20 |

### Modified Files

| File | Change |
|------|--------|
| `ios/Robo/Views/ContentView.swift` | Add Chat tab (tab 3, shift Settings to tab 4) |
| `ios/Robo/Models/AppStrings.swift` | Add `Tabs.chat` string constant |
| `ios/Robo/RoboApp.swift` | Create & inject `ChatService` via `.environment()` |

**No SwiftData schema migration needed** — Phase 1 keeps messages in memory only.

## Acceptance Criteria

### Functional

- [x] Chat tab appears in tab bar for all users (4th position = Settings shifts right)
- [x] On iOS 26+ with Apple Intelligence enabled: full chat UI with streaming responses
- [x] On iOS 26+ without Apple Intelligence: fallback with "Enable Apple Intelligence" guidance
- [x] On iOS 17-25 or unsupported hardware: fallback explaining device/OS requirements
- [x] User can ask about available agents and get accurate responses
- [x] User can ask about specific agent capabilities (skills, use cases)
- [x] Streaming text appears token-by-token with typing cursor
- [x] Send button disabled while streaming; stop button shown instead
- [x] Empty state shows 3-4 tappable suggestion chips
- [x] "Clear Chat" toolbar button resets conversation and session
- [x] Subtle "On-device AI — conversations stay private" indicator

### Non-Functional

- [x] No external dependencies (no SPM packages for chat UI)
- [x] `session.prewarm()` called in `.onAppear` to minimize first-response latency
- [x] System prompt stays under 1000 tokens with all current agents
- [x] Builds with `xcodebuild` — no Xcode UI required

## Technical Considerations

### Availability Gating Pattern

The deployment target is iOS 17, but Foundation Models requires iOS 26. Use compile-time `#available` checks:

```swift
// ChatTabView.swift
struct ChatTabView: View {
    var body: some View {
        if #available(iOS 26, *) {
            FoundationModelsChatView()
        } else {
            ChatUnavailableView(reason: .osNotSupported)
        }
    }
}

// FoundationModelsChatView.swift (inside #available block)
@available(iOS 26, *)
struct FoundationModelsChatView: View {
    var body: some View {
        let model = SystemLanguageModel.default
        switch model.availability {
        case .available:
            ChatView()
        case .unavailable(.deviceNotEligible):
            ChatUnavailableView(reason: .hardwareNotSupported)
        case .unavailable(.appleIntelligenceNotEnabled):
            ChatUnavailableView(reason: .appleIntelligenceDisabled)
        case .unavailable(.modelNotReady):
            ChatUnavailableView(reason: .modelDownloading)
        default:
            ChatUnavailableView(reason: .unknown)
        }
    }
}
```

### Dynamic System Prompt

Build the system prompt from live agent data to stay in sync:

```swift
static func buildSystemPrompt() -> String {
    let agents = MockAgentService.loadAgents()
    let agentDescriptions = agents.map { agent in
        "- \(agent.name): \(agent.description) [Skills: \(agent.skills.map(\.rawValue).joined(separator: ", "))]"
    }.joined(separator: "\n")

    return """
    You are Robo's on-device assistant. Robo is an iOS app that turns phone sensors \
    (LiDAR, camera, barcode scanner, Bluetooth beacons, motion, health) into APIs for AI agents.

    Available agents:
    \(agentDescriptions)

    You help users understand what Robo can do and how to use each agent. \
    You CANNOT perform actions like scanning or capturing — when asked, explain how the user \
    can do it themselves using the Capture tab. Action capabilities are coming in a future update.

    Keep responses concise (2-3 sentences unless the user asks for detail).
    """
}
```

### Chat UI — Key SwiftUI Patterns

- **ScrollView + LazyVStack** (not List) with `defaultScrollAnchor(.bottom)` + `ScrollViewReader`
- **`safeAreaInset(edge: .bottom)`** for input bar — keyboard avoidance is automatic
- **`scrollDismissesKeyboard(.interactively)`** — drag to dismiss like Apple Messages
- **`TextField(axis: .vertical)` with `lineLimit(1...5)`** — expanding multiline input
- **Streaming:** append each partial token to the last message's content via `@Observable` service

### Token Budget (4096 total)

| Component | Estimated Tokens |
|-----------|-----------------|
| System prompt (9 agents) | ~400-600 |
| User message | ~50-200 |
| Model response | ~200-800 |
| Conversation history | Remaining |

With ~9 agents, the system prompt leaves ~3400 tokens for conversation. After ~4-6 exchanges, context fills up. **Mitigation:** show a "conversation getting long, tap Clear to start fresh" banner when nearing the limit.

### Edge Cases

| Scenario | Handling |
|----------|----------|
| Empty/whitespace input | Disable send button |
| Rapid-fire messages | Disable send while streaming |
| Mid-stream tab switch | Keep partial response, cancel stream Task |
| Guardrail refusal | Show "I can't help with that" message in chat |
| Context overflow | Show banner suggesting Clear Chat |
| Action request ("scan my room") | Model redirects to Capture tab instructions |
| Model downloading (transient) | Show progress indicator, check periodically |

## Implementation Phases

### Phase 1: POC (This PR) — Hackathon Scope

**Goal:** Working chat that explains Robo's capabilities using on-device AI.

1. **ChatMessage model** — `struct ChatMessage: Identifiable` with `id`, `role` (.user/.assistant/.system), `content`, `timestamp`
2. **ChatService** — `@Observable class` managing `LanguageModelSession`, message array, streaming state. Marked `@available(iOS 26, *)`. Dynamic system prompt from `MockAgentService`.
3. **ChatView** — ScrollView + message bubbles + input bar + suggestion chips empty state
4. **ChatTabView** — Availability gate routing to ChatView or ChatUnavailableView
5. **ChatUnavailableView** — Per-reason `ContentUnavailableView` with appropriate messaging
6. **ContentView integration** — Add Chat as tab 3, shift Settings to tab 4
7. **RoboApp integration** — Create ChatService conditionally, inject via environment

### Phase 2: Actionable Chat (Future — #113)

- Foundation Models Tool calling: define `Tool` structs for each agent action (trigger scan, configure agent, etc.)
- `@Generable` structured output for typed responses
- SwiftData persistence for chat history (new schema version)
- MCP server on Cloudflare Workers for cloud-backed chat when on-device is unavailable
- HIT link generation from chat ("text this link to your friends")

## Fallback UI Copy

| Reason | Title | Message | Action |
|--------|-------|---------|--------|
| OS not supported | "Chat Requires iOS 26" | "On-device AI chat needs iOS 26 or later. Update your iPhone to get started." | "Check for Update" → deep link to Settings |
| Hardware not supported | "Device Not Supported" | "On-device AI chat requires iPhone 15 Pro or later with Apple Intelligence." | None |
| Apple Intelligence disabled | "Enable Apple Intelligence" | "Turn on Apple Intelligence to use on-device chat." | "Open Settings" → deep link |
| Model downloading | "Preparing AI Model..." | "The on-device model is downloading. This usually takes a few minutes." | ProgressView |

## Suggested Prompt Chips (Empty State)

- "What agents are available?"
- "What can the Interior Designer do?"
- "What sensors does Robo support?"
- "How do I scan a room?"

## Success Metrics

- Chat tab loads and shows appropriate UI based on device capabilities
- Users can have a multi-turn conversation about Robo's agents
- Streaming responses feel responsive (first token < 1s after prewarm)
- No crashes on any iOS 17+ device (graceful fallbacks)

## Dependencies & Risks

| Risk | Likelihood | Mitigation |
|------|-----------|------------|
| iOS 26 not available on test device | Medium | Test on simulator (requires macOS 26), or use `#if targetEnvironment(simulator)` mock |
| 4096 token limit too restrictive | Low | Keep system prompt lean, add Clear Chat |
| Model quality for agent descriptions | Low | Model only needs to parrot system prompt context, not reason deeply |
| Phase 2 architecture incompatibility | Low | Free-text Phase 1 → Tool calling Phase 2 is a supported migration path |

## References

- [Foundation Models — Apple Developer Documentation](https://developer.apple.com/documentation/FoundationModels)
- [Meet the Foundation Models framework — WWDC25](https://developer.apple.com/videos/play/wwdc2025/286/)
- [Code-along: Bring on-device AI to your app — WWDC25](https://developer.apple.com/videos/play/wwdc2025/259/)
- Issue #113 — In-app chat agent (MCP-backed) + Group Think
- `ios/Robo/Services/MockAgentService.swift` — Agent definitions
- `ios/Robo/Models/AgentConnection.swift` — SkillType enum
- `ios/Robo/Views/ContentView.swift` — Tab bar structure
- `ios/Robo/RoboApp.swift` — Service injection pattern
