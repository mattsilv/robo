# Robo Demo Video Script

## Background Context (for coaching — not in the video)

### What is Robo?
Robo is an open-source iOS app that turns your phone's sensors (LiDAR, camera, barcode scanner) into APIs that any AI agent can use. It's the missing bridge between the physical world and AI — today, getting LiDAR data into Claude or ChatGPT is literally impossible without building a native iOS app from scratch.

### Who built it?
Matt Silv, solo developer. The entire app — iOS frontend and Cloudflare Workers backend — was built with Claude Code (Anthropic's AI coding tool) for about $550 in API usage.

### Who is the audience?
"Vibe coders" — developers who can build AI agents quickly (system prompt, a few tools, done) but hit a wall when they need real-world sensor data. Native iOS development is months of Swift, Xcode, provisioning profiles, and App Store review. Robo eliminates all of that.

### What makes it different?
- **Open source** — fork it, extend it, audit the code
- **No subscription required** — free tier works entirely on-device (email/zip export)
- **Provider-agnostic** — works with Claude, ChatGPT, any custom backend
- **4 integration paths** — Webhooks, REST API, MCP (Model Context Protocol), or email/zip export
- **Guided capture** — tips before scanning + real-time AR feedback during, so users get complete data on the first try
- **Chat-first UX** — instead of building form UIs for every feature, users talk to an on-device chat agent

### Core demo scenario
1. Open Robo → tap Create → LiDAR Room Scanner
2. Read 4 scanning tips (guided capture)
3. Walk the room with Apple RoomPlan AR guidance (~30 seconds)
4. Review scan summary (dimensions, sq ft, wall positions, detected objects)
5. Share as structured JSON → Claude analyzes it instantly

### Key stats
- ~$550 of Claude API usage to build the entire app
- Live on TestFlight, live API at api.robo.app, MCP server at mcp.robo.app
- HIT Links: text anyone a URL to capture data — no app install needed on their end

### The pitch in one line
"Robo turns your phone's real-world sensors and human input into APIs any AI agent can use instantly."

### The stinger
A physical BLE beacon chip with a blinking LED delivers the closing line in a different voice: "But what do I know? I'm just AI myself." — a playful callback that the tool was built by AI too.

---

## Script

**Target:** ~2 minutes (120s) — tight and punchy, under 2:30 max
**Format:** 1920x1080, 16:9, YouTube unlisted
**Voice:** Direct, conversational, short sentences. No jargon. Brief team intro for personality.
**Approach:** Audio-first — generate voiceover, then align video to it.
**Key principle:** Show the actual app running on a real device — no slide decks. The first 10 seconds decide if they keep watching.

---

## 1. Hook / Elevator Pitch (0:00–0:10) ~10s

**[VISUAL: Quick cut — real device screen recording of AR overlay scanning a room, data flowing to Claude. Fast, energetic. Show touch interactions.]**

> I'm Matt — I built Robo. Watch this.
>
> **[LiDAR scan fires up — 3-second visual burst]**
>
> AI can finally sense the world — and collaborate inside it. That's Robo.

**~25 words, ~10 seconds**

---

## 2. Problem Statement (0:10–0:25) ~15s

**[VISUAL: Quick cuts of Xcode complexity, Swift code, provisioning profiles, error screens]**

> Want a barcode scan? A 3D room scan? Suddenly you need Swift, Xcode, provisioning profiles, App Store review — months of work just to give your agent eyes in the real world.

**~35 words, ~15 seconds**

---

## 3. Solution & Differentiator (0:25–0:45) ~20s

**[VISUAL: Robo app icon → 4 integration paths diagram (Webhooks, REST API, MCP, Email/ZIP) → "Open Source" badge]**

> Robo is an open-source iOS app that turns your phone's sensors into APIs any AI agent can use. Webhooks, REST, MCP, or email export — your choice. No iOS development. No subscription. Privacy-first with a free on-device tier.

**~45 words, ~20 seconds**

---

## 4. Live Demo (0:45–1:50) ~65s

### Demo A: Share Sheet → MCP — Lead Demo (~15s)

**[VISUAL: Screen recording — browsing, screenshot, iOS Share Sheet, "Send to Claude Code" action via Robo MCP.]**

> Say I'm browsing and find something I want Claude's help with. I take a screenshot, tap Share, and send it straight to Claude Code via Robo's MCP. No copy-paste, no file uploads — one tap.

**~40 words, ~15 seconds**

### Demo B: LiDAR — Visual Credibility (~15s)

**[VISUAL: Screen Studio recording of real iPhone Pro — LiDAR scan in action, then scan summary.]**

> But Robo goes beyond screenshots. Need a full room scan? Tap Interior Designer, walk the room with LiDAR, and Robo generates dimensions, square footage, detected objects — even compass directions. Tap once to share with Claude.

**~40 words, ~15 seconds**

### Transition

> But sensing the world is only half the story. The real breakthrough is letting AI collaborate with humans instantly.

### Demo B: Group Think — Emotional Peak (~45s)

**[VISUAL: Screen Studio — Robo chat interface, then texts going out, then responses coming back in real time.]**

> Here's where it gets interesting. I'm planning a ski trip with friends. I open Robo's chat and say "help me pick dates with my group."
>
> Robo creates a link. I text it to three friends. No app install — they just tap and pick their available dates.
>
> Watch — responses flow back in real time. Robo's agent aggregates them and tells me: "Everyone's free the weekend of March 7th."
>
> AI doesn't replace people here. It coordinates them.

**~80 words, ~35 seconds**

---

## 5. Technical Highlights (1:50–2:00) ~10s

**[VISUAL: "~$550" stat, "Built with Claude Code" badge, open source badge]**

> Built entirely with Claude Code — about five hundred fifty dollars. Open source. No subscription. The Context Cultivator.

**~20 words, ~10 seconds**

---

## 6. Impact & Vision (2:00–2:10) ~10s

**[VISUAL: GitHub repo, robo.app URL, future sensors montage]**

> Once AI can sense spaces, scan objects, and ask humans for help in real time… every agent stops being a chatbot and starts becoming an actor in the real world.
>
> This is the moment AI steps out of the chat window… and into the real world. AI can finally sense the world — and collaborate inside it.

**~50 words, ~15 seconds**

---

## 7. Stinger — Post-Credits (2:10–2:15) ~5s

**[VISUAL: Handheld phone video of the BLE beacon chip on a board. LED blinks in sync with each word. Dark/moody lighting. Dramatic pause before the line.]**

**[VOICE: Different voice — southern/country accent, warm and wry]**

> But what do I know? I'm just AI myself.

**[LED blinks out. Cut to black.]**

**~10 words, ~5 seconds**

### Stinger Production Notes
- Record on iPhone, handheld, close-up of the chip + LED
- Sync LED blinks to the syllables of the voiceover (or approximate)
- Generate this line as a **separate ElevenLabs clip** with a different voice (southern accent)
- Keep it deadpan/dry delivery — the humor is in the understatement

---

## Production Notes

### Total Word Count: ~325 words (~2 min at natural pace)

### Video Technical Specs
- **Resolution:** 1920x1080, 16:9 aspect ratio
- **Upload:** YouTube unlisted (preferred) or Google Drive
- **Audio:** Record in a quiet room; add subtitles
- **Screen recording:** Screen Studio on real iPhone Pro (not Simulator) — show native gestures
- **Consider:** Separate technical deep-dive video if allowed (architecture, Swift/SwiftUI, backend)

### ElevenLabs Generation Settings
- Model: `eleven_multilingual_v2`
- Format: `mp3_44100_128`
- Speed: `1.0`
- Stability: `0.5`
- Similarity boost: `0.75`
- Use `seed: 12345` for reproducibility

### Timing Markers (for video alignment)
| Timestamp | Section | Visual Cue |
|-----------|---------|------------|
| 0:00 | 1. Hook | AR scan burst + intro |
| 0:10 | 2. Problem | Xcode / Swift complexity |
| 0:25 | 3. Solution | App icon + open source badge |
| 0:45 | 4a. Demo — Share Sheet | Screenshot → Share → MCP → Claude |
| 1:00 | 4b. Demo — LiDAR | Visual credibility, room scan |
| 1:15 | Transition | "Sensing the world is only half..." |
| 1:20 | 4c. Demo — Group Think | Chat → HIT link → real-time responses |
| 1:50 | 5. Technical | $550 + Claude Code badge |
| 2:00 | 6. Vision | Inevitability beat + closing |
| 2:15 | 7. Stinger | BLE chip close-up |
| 2:20 | End | Cut to black |

### Key Phrases Used
- "Turns your phone's sensors into APIs" (Section 3)
- "Guided capture — complete data the first time" (Section 4)
- "~$550 of API usage" (Section 5)
- "No iOS development. No subscription." (Section 3)
- "Open source. Privacy-first." (Sections 3, 6)
- "Built with Claude Code" (Section 5)
