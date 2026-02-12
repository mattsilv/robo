# Robo Use Cases

## The Agentic Inbox

Your AI agents need real-world data — floor plans, barcode scans, photos. Today that means building a native iOS app. Months of Swift, Xcode, and App Store review.

Robo is the missing bridge: **the agentic inbox for your phone's sensors.** Agents request data, you capture it in one tap, it syncs automatically.

---

## Use Case 1: Room Measurement Agent (LiDAR)

**What you want to build:**
"I want an AI agent that helps me plan furniture layouts by measuring my room."

**Today (without Robo):**
1. Learn Swift, UIKit, ARKit
2. Build iOS app for LiDAR capture
3. Handle camera permissions, 3D mesh processing, file exports
4. Submit to App Store, wait for review
5. ~3-6 months later: finally get room data to your agent

**With Robo:**
1. Interior Decorator agent sends a request: "I need the floor plan of your master bedroom"
2. You see the request in Robo's Agents tab
3. Tap "Scan Room" → LiDAR guided capture with AR guidance
4. Save → "Syncing with Interior Decorator..." → done
5. Agent analyzes dimensions, suggests furniture placement

**Why it matters:** LiDAR data is impossible to get into Claude/ChatGPT today. Robo makes it trivial — and the agent-driven flow means zero friction.

---

## Use Case 2: Practical Chef (Barcode + Photo)

**What you want to build:**
"I want an AI agent that sees what's in my kitchen and suggests recipes."

**Today (without Robo):**
- Manual: Type UPC codes into ChatGPT (tedious)
- Or take photos, switch apps, upload, repeat
- Or build native iOS barcode scanner (months of work)

**With Robo:**
1. Practical Chef agent is connected in your Agents tab
2. Open your fridge → batch-photo everything visible (multi-photo capture, no dismissing between shots)
3. Scan specific barcodes for items you want tracked
4. Agent gets photos + barcode data together, suggests recipes based on what you have
5. Works with any AI backend — Claude, ChatGPT, your custom agent

**Two sensor types, one agent.** The Practical Chef shows how agents can use multiple Robo skills (camera + barcode) in a single workflow.

**Privacy win:** No backend required - Robo can email you the data directly. Your data never touches our servers.

---

## Use Case 3: Visual Context (Camera)

**What you want to build:**
"I want my home repair agent to see what I'm looking at in real-time."

**Today (without Robo):**
1. Take photo
2. Open Claude app
3. Upload photo
4. Wait for response
5. Repeat for each new angle

**With Robo:**
1. Connect camera feed to your agent
2. Agent sees live context as you troubleshoot
3. No app-switching, no manual uploads

**Why it matters:** Most AI apps support photo upload, but the workflow is onerous. Robo makes context capture seamless.

---

## Use Case 4: Home Task Reminder (BLE Proximity) — Future

**What you want to build:**
"I want an AI agent that reminds me of tasks when I'm near relevant locations in my home."

**The vision:**
1. USB-C Bluetooth beacons placed around your home (laundry room, garage, kitchen)
2. When your phone detects a beacon, Robo triggers a location-aware task
3. "You're near the laundry room — time to switch loads"
4. Agent can push context-aware suggestions based on where you are

**Why it matters:** BLE proximity turns passive reminders into context-aware, location-triggered tasks. Your agent knows not just *what* you need to do, but *where* you are when you need to do it.

**Status:** Future skill — needs more baking on the use case and hardware requirements.

---

## Key Differentiators

### For Builders
- **No iOS development required** - Skip Swift, Xcode, and App Store review
- **Provider-agnostic** - Works with Claude, ChatGPT, your custom backend, or just email
- **Integration options** - Webhooks, REST API, MCP, or simple email/zip export
- **Open source** - Fork it, extend it, audit the code
- **Free tier** - Email/zip export works without any backend

### Technical Flow
```
Phone Sensors → Robo App → [Your Choice:]
                            ├─ Webhooks (real-time push)
                            ├─ REST API (pull on demand)
                            ├─ MCP (Claude tool integration)
                            ├─ Email / ZIP (free, no backend)
                            └─ Custom endpoint (any HTTP)
```

---

## Demo Scenario (LiDAR + Guided Capture)

**Setup:** 2 minutes
- Download Robo from App Store
- Configure endpoint URL (or use email)

**Demo:** 3 minutes (agent-driven flow with guided capture)
1. Open Robo → Agents tab → Interior Decorator's request: "I need the floor plan of your master bedroom"
2. Tap "Scan Room" → read 4 quick scanning tips
3. Tap "Start Scanning" — Apple's RoomPlan shows real-time AR guidance
4. Walk slowly around room perimeter — walls, doors, windows detected live
5. Tap Done → review scan summary → Save
6. "Syncing with Interior Decorator..." animation → "Synced just now"
7. Agent: "Your room is 12ft × 14ft with 2 windows. Here's where that couch would fit..."

**Wow factor:** "Wait, the agent *asked* for the scan? And it just synced automatically?"

**Core UX principle: Guided capture.** Robo ensures users capture complete data on the first try. Before scanning, you see essential tips. During scanning, Apple's RoomPlan provides real-time AR guidance. No guessing, no re-scans, no frustration.

---

## Roadmap

**M1 (Hackathon MVP):** Barcode scanning, LiDAR room scanning (guided capture), D1 backend, email/zip export (free tier, no backend required)
**M2:** Camera support, live sensor feeds
**M3:** Background capture, multiple agent connections

---

## FAQs

**Q: Why not just use the Claude/ChatGPT mobile app?**
A: Those apps only support photos. No barcode scanning, no LiDAR, no live sensor feeds. And your data is locked into their ecosystem.

**Q: Do I need to host a backend?**
A: No. Free tier exports data via email. Or connect to any HTTP endpoint (your agent, Zapier, etc.). Paid hosted backend is optional.

**Q: What sensors are supported?**
A: M1 (now): Barcode + LiDAR room scanning + email/zip export. M2: Camera. M3+: GPS, accelerometer, microphone.

**Q: Can I use this for enterprise?**
A: Yes, but that's not the initial target. See `docs/enterprise-use-cases.md` (future).

**Q: Is my data private?**
A: Yes. Open source app, optional backend. Email export keeps data on your device until you choose to send it.
