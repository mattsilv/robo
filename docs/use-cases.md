# Robo Use Cases

## Target Audience: Vibe Coders

You can build AI agents with Claude Projects, ChatGPT, or custom GPTs. But getting phone sensor data into those agents? That requires building a native iOS app - months of Xcode, Swift, and App Store bureaucracy.

Robo is the missing bridge: **open-source iOS app that turns your phone's sensors into APIs any AI agent can use.**

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
1. Download Robo from App Store (free, open source)
2. Point phone at room, tap "Scan"
3. LiDAR data automatically sent to your agent endpoint
4. Agent analyzes dimensions, suggests furniture placement
5. ~10 minutes to working prototype

**Why it matters:** LiDAR data is impossible to get into Claude/ChatGPT today. Robo makes it trivial.

---

## Use Case 2: Inventory Management (Barcode)

**What you want to build:**
"I want an AI agent that tracks my pantry by scanning barcodes and suggesting recipes."

**Today (without Robo):**
- Manual: Type UPC codes into ChatGPT (tedious)
- Or build native iOS barcode scanner (months of work)

**With Robo:**
1. Scan barcode with Robo
2. UPC sent to your agent (Claude Project, custom GPT, etc.)
3. Agent looks up product, updates inventory, suggests recipes
4. Works with any AI backend you choose

**Privacy win:** No backend required - Robo can email you the barcode data directly. Your data never touches our servers.

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

## Key Differentiators

### For Vibe Coders
- **No iOS development required** - Skip the Swift learning curve
- **Provider-agnostic** - Works with Claude, ChatGPT, your custom backend, or just email
- **Open source** - Fork it, extend it, audit the code
- **Free tier** - Email/zip export works without any backend

### Technical Flow
```
Phone Sensors → Robo App → [Your Choice:]
                            ├─ Claude Project
                            ├─ ChatGPT
                            ├─ Custom agent endpoint
                            ├─ Email (free, no backend)
                            └─ Robo hosted backend (paid, optional)
```

---

## Demo Scenario (LiDAR + Guided Capture)

**Setup:** 2 minutes
- Download Robo from App Store
- Configure endpoint URL (or use email)

**Demo:** 3 minutes (guided capture ensures complete data on the first try)
1. Tap Create → LiDAR Room Scanner
2. Read 4 quick scanning tips (lighting, coverage, pacing, timing)
3. Tap "Start Scanning" — Apple's RoomPlan shows real-time AR guidance
4. Walk slowly around room perimeter — walls, doors, windows detected live
5. Tap Done → review scan summary (wall count, floor area, detected objects)
6. Share as ZIP → room_summary.json + room_full.json sent to your agent
7. Agent: "Your room is 12ft × 14ft with 2 windows. Here's where that couch would fit..."

**Wow factor:** "Wait, you can get LiDAR data into Claude now? And it guided you through the whole scan?"

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
