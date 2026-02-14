---
title: "Chat formatting displayed raw Snapshot debug output instead of clean text"
date: 2026-02-13
category: ui-bugs
tags: [chat, string-formatting, foundation-models, ios-26, swift]
component: ChatService.swift
severity: high
symptoms: "Chat bubbles displayed raw Snapshot debug output like 'Snapshot(content: \"...\", rawContent: \"...\")' instead of user-friendly text"
root_cause: "String(describing: partial) called debug description of FoundationModels stream Snapshot type instead of accessing .content property"
---

# Chat Formatting: Raw Snapshot Debug Output in Chat Bubbles

## Symptom

The on-device AI chat (powered by Apple FoundationModels, iOS 26) displayed raw debug output in chat bubbles instead of clean text. Users saw something like:

```
Snapshot(content: "Hello! I can help you with that.", rawContent: "...")
```

Instead of just:

```
Hello! I can help you with that.
```

## Root Cause

In `ios/Robo/Services/ChatService.swift`, line 66:

```swift
// BROKEN — dumps debug representation of the entire Snapshot struct
let text = String(describing: partial)
```

The `streamResponse(to:)` method from Apple's FoundationModels framework returns a stream of `Snapshot` objects. `String(describing:)` accepts `Any` — so there's no compiler error — but it produces the debug representation including all internal fields, not just the content.

## Solution

```swift
// FIXED — extract the actual generated text
let text = partial.content
```

The `.content` property on `Snapshot` contains only the generated text string, which is what should be displayed in the chat bubble.

### Also: Tightened System Prompt

The system prompt was also updated to enforce more concise responses:

```swift
// BEFORE
Keep responses concise (2-3 sentences unless the user asks for detail). \
Be friendly and helpful.

// AFTER
IMPORTANT: Keep responses very short — 1-2 sentences max. \
Only give longer answers if the user explicitly asks for detail. \
Never use bullet points or lists unless asked. Be direct and conversational.
```

## Why This Happened

- `String(describing:)` accepts `Any`, providing zero compile-time safety
- It's a common Swift "escape hatch" for converting objects to strings
- The bug is only visible at runtime when the chat UI renders the output
- No unit tests existed for the stream content extraction path

## Prevention

### Code Review Checklist

- Never use `String(describing:)`, `String(reflecting:)`, or `.description` to extract data from known types
- Always access explicit typed properties (e.g., `.content`, `.text`, `.value`)
- `String(describing:)` is acceptable only for logging/debugging unknown types

### SwiftLint Rule (Optional)

```yaml
custom_rules:
  no_string_describing_streams:
    name: "No String(describing:) on stream objects"
    regex: 'String\s*\(\s*describing\s*:\s*(?:partial|snapshot|stream)'
    message: "Use the explicit property (e.g., partial.content) instead of String(describing:)"
    severity: error
```

### Testing

Unit testing FoundationModels streaming is limited (requires iOS 26 device with Apple Intelligence), but a smoke test can assert that message content never contains `"Snapshot("`:

```swift
// After any chat interaction:
XCTAssertFalse(message.content.contains("Snapshot("),
    "Chat content should not contain debug representation")
```

## Related

- Commit: `0bf1b59` — fix(chat): extract content from stream snapshot and tighten prompt
- Commit: `5ca2c11` — fix(chat): prevent stream races and stale availability state
- Plan: `docs/plans/2026-02-13-feat-on-device-ai-chat-foundation-models-plan.md`
- PR: [#121](https://github.com/mattsilv/robo/pull/121)
