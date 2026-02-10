## Robo — Concise Project Summary

**One-liner:** A generic iOS app that gives any AI agent access to native phone sensors and a human-in-the-loop interface, configured entirely via API — no custom app development needed.

**Problem:** Vibe-coded apps hit a wall when they need native phone capabilities (camera, LiDAR, BLE, barcode). Today, every project that needs this data requires building a custom iOS app from scratch.

**Solution:** Robo is a single native iOS app with two core functions:

1. **Sensor modules** — Developers configure capture modules (photo, barcode, LiDAR, BLE proximity, audio/video) that post data to any webhook or cloud endpoint. The app handles all native API complexity; the developer just receives structured data.

2. **Agentic inbox** — A two-way channel between AI agents and humans. Three modes:
   - **Decisions** — Agent pushes a card, user taps a response (yes/no, single-select, multi-select + optional text), callback fires to the agent's webhook.
   - **Tasks** — Assigned actions the user completes within the app (e.g., "take a photo of the equipment at site #4," "scan the barcode on this shipment"). Tasks combine sensor modules with the inbox — the completion of a capture *is* the task response.
   - **Crowdsourced / gamified tasks** — Open tasks that any user can claim. Need 50 photos of storefronts for a training dataset? Push it as a gamified task with a leaderboard. Any Robo user can pick it up, complete the capture, and earn points or credit. This turns Robo into a lightweight crowdsourcing platform for AI data collection.

**Tech stack:** Native Swift (SwiftUI) → Cloudflare Workers (Hono) → D1 + R2. ESP32-S3 for BLE hardware demos.

**Key insight:** The phone is the most powerful sensor array most people own. Robo makes it an open API endpoint that any developer can configure without touching Xcode.

My elevator pitch (dont make major changes ot this without approval)
Every AI agent would benefit from more context from your phone: a photo, a sensor reading, a human decision.

Today, giving native app data to a vibe-coded app is onerous, requiring custom native app development for each project if you want data that only native apps can provide.

Robo is an iOS app that liberates native phone data to your cloud and streamlines simple human-in-the-loop workflows.

Think: photo capture, barcode scanning, LiDAR, BLE proximity, agentic guidance, audio/video streaming.

Robo handles the native sensor access and posts to any endpoint you configure. 

It also acts as a lightweight agentic inbox: your AI pushes a decision card, the user taps a response with one thumb, and it calls back your webhook.

Your phone becomes a two-way bridge between you and your agentic apps. No native development required.

All the conveniences of a native app without the complexity of the Apple walled garden.