---
title: Pitch Storytelling Playbook
category: messaging
component: site, docs, video
severity: critical
date_solved: 2026-02-11
tags: [pitch, storytelling, hackathon, video, messaging]
---

# Pitch Storytelling Playbook

## The Line That Lands

**"Native mobile context for AI agents."**

Not "sensor APIs." Not "phone data endpoints." Context. That's the word that clicks — Daniel's aha moment on the Zoom was: "So it's like converting native APIs of the device into some kind of MCP tool for the agent." He got it when we framed it as *context* the agent can't reach today.

## Voice & Tone

**Direct.** Short sentences. Lead with the friction, then the fix. No jargon-padding.

**The formula:**

> [Pain in one sentence] → [Robo in one sentence] → [Proof it works]

Examples that land:

- "Building an AI agent is easy. Getting it phone sensor data? That means months of Swift, Xcode, and App Store review."
- "LiDAR data into Claude is impossible today. Robo makes it trivial."
- "Your phone's richest context — LiDAR, camera, barcodes — is trapped on the device, invisible to AI agents."

Examples that don't land:

- "Robo exposes native iOS sensor capabilities as RESTful API endpoints" (too technical, no emotion)
- "A bridge between mobile hardware and AI infrastructure" (vague, forgettable)
- "The native app sidekick for AI agents" (original tagline — cute but unclear)

## Audience: Builders (Not "Vibe Coders")

"Vibe coders" was the original label. It's fun but limiting — sounds like a niche. "Builders" is broader and more aspirational. These are people who:

- Build AI agents with Claude Projects, custom GPTs, or their own backends
- Hit a wall when they need real-world sensor data
- Don't want to learn Swift/Xcode/App Store process
- Want integration options, not lock-in

## The Friction Story (Lead With This)

The pitch only works if the audience *feels* the friction first. Three beats:

1. **The future is agentic** — everyone's building AI agents, it's easy now
2. **But there's a wall** — phone sensors (the richest real-world context) are trapped behind native iOS development
3. **Robo breaks through** — open-source app, download it, connect your agent, done

The wall is the story. Without it, Robo sounds like a nice-to-have. With it, Robo sounds inevitable.

## Key Phrases (Approved for Video/Site)

Use freely:

- "Native mobile context for AI agents"
- "Trapped on the device, invisible to AI agents"
- "No iOS dev, no App Store"
- "Months of Swift, Xcode, and App Store review"
- "The missing bridge"
- "Webhooks, REST API, MCP, or simple email export"
- "Open source, privacy-first"
- "$85 of Claude API usage. That's it. That's the whole app."
- "Guided capture — complete data on the first try"

**Do NOT use** (App Store approval risk):

- "Apple's walled garden"
- "Break through Apple's [anything]"
- Any language that frames Apple as the adversary

The friction is *building native apps*, not *Apple being restrictive*. Frame it as complexity, not antagonism.

## Demo Script Skeleton (3 min)

### Beat 1: The Problem (30s)
"You can build an AI agent in an afternoon. But getting it LiDAR data from your phone? That's months of Swift, Xcode, provisioning profiles, App Store review. Your phone has incredible sensors — and they're completely invisible to your agent."

### Beat 2: The Solution (15s)
"Robo is an open-source iOS app that unlocks your phone's native context for any AI agent. Webhooks, REST, MCP, email — your choice."

### Beat 3: Live Demo (90s)
1. Open Robo → tap Create → LiDAR Room Scanner
2. Show the 4 scanning tips (guided capture)
3. Walk the room — RoomPlan AR guidance visible
4. Done → review scan summary (walls, floor area, objects)
5. Share as ZIP → structured JSON goes to agent
6. Agent responds with room analysis

### Beat 4: The Wow (30s)
"That LiDAR scan just went into Claude. Try doing that without Robo. You can't. That's the point — native mobile context, unlocked for agents."

### Beat 5: Close (15s)
"Open source. Free tier. Built with Claude Code — $85 of API usage, that's the whole app. Download it, connect your agent, ship."

## Pitch Evolution (For Reference)

| Version | Tagline | Problem |
|---------|---------|---------|
| V1 (launch) | "The native app sidekick for AI agents" | Sensor APIs are hard |
| V2 (dev) | Same | Missing bridge metaphor |
| V3 (current) | "Native mobile context for AI agents" | Friction: months of Swift/Xcode/App Store |

**What changed:** Shifted from *technical capability* ("sensor APIs") to *strategic unlock* ("native mobile context"). The audience cares about what their agent can *do*, not what APIs it calls.

## Integration Options (Always Mention All Four)

Every time you describe how Robo connects to agents, list all four:

1. **Webhooks** — real-time push to your endpoint
2. **REST API** — pull on demand
3. **MCP** — Claude tool integration (this is the aha moment for Claude users)
4. **Email / ZIP** — free, no backend, privacy-first

The email option is critical for the "free tier" story. It means zero infrastructure to get started.

## Judging Criteria Alignment

From the hackathon rules, judges care about:

- **Creativity & Innovation** → LiDAR-to-Claude is genuinely new. Lead with this.
- **Technical Implementation** → Built entirely with Claude Code. Mention $85.
- **Practical Usefulness** → Room scanning, barcode inventory, guided capture UX.
- **Presentation Quality** → This playbook. Nail the friction → solution → demo arc.
