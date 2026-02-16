# Robo

> Phone sensors (barcode, camera, LiDAR) as API endpoints for AI agents

## Hackathon Submission — Built with Opus 4.6

**The problem:** The future of building is agentic — but phone sensor data is trapped on the device. Want LiDAR data in Claude? Build a native iOS app. Months of Swift, Xcode, and App Store review.

**Robo is the missing bridge.** An open-source iOS app that turns your phone's 9 sensors into APIs any AI agent can use — no iOS development required. Provider-agnostic (Claude, ChatGPT, any backend), with MCP integration, HIT links for crowdsourcing data from anyone via browser, and a chat-first UX powered by OpenRouter tool calling.

**Built in 6 days** by one developer pair-programming with Claude Code:

| Metric | Count |
|--------|-------|
| Commits | 336 |
| Pull requests | 100 (95 merged) |
| Lines of code | ~22,000 (Swift + TypeScript) |
| Total code churn | 104,734 lines |
| TestFlight builds | ~40 |
| Sensors integrated | 9 (LiDAR, camera, barcode, BLE, HealthKit, motion, compass, iBeacon, WiFi) |
| Integration points | 7 (MCP, HIT links, Share Extension, on-device AI, OpenRouter, webhooks, API keys) |

**Key demo flow:** Download Robo → LiDAR scan a room with AR guidance → share results → agent analyzes: "Your room is 12ft × 14ft. Here's where that couch would fit." Getting LiDAR data into Claude today is impossible. Robo makes it trivial.

**Stack:** SwiftUI (iOS 17+), Cloudflare Workers (Hono + D1 + R2), MCP server, GitHub Actions CI → TestFlight auto-deploy.

## Overview

Robo is an open-source iOS app that turns your phone's sensors into APIs any AI agent can use. LiDAR, camera, barcodes — no iOS development required.

**Live API:** https://api.robo.app
**MCP Server:** https://mcp.robo.app/mcp
**Landing Page:** https://robo.app

## Features

- **LiDAR Room Scanning** — Walk a room with AR guidance, export 3D data for AI analysis
- **Barcode Scanner** — VisionKit-powered scanning with real-time cloud submission
- **HIT Links** — Text anyone a link to capture photos/data — no app install required
- **MCP Bridge** — Connect Claude Code (or any MCP client) directly to phone sensors
- **Device Auth** — UUID-based device registration + Bearer token auth for MCP
- **Guided Capture** — Tips before scanning, real-time AR feedback during

### Connect Claude Code to Your Phone

```bash
claude mcp add robo --transport http https://mcp.robo.app/mcp \
  -H "Authorization: Bearer YOUR_MCP_TOKEN"
```

Then ask: *"What rooms has my phone scanned?"*

## Quick Start

### Prerequisites

- Xcode 26.0+ (for iOS development)
- Node.js 18+ (for Workers development)
- [Cloudflare account](https://dash.cloudflare.com/sign-up) (free tier works)
- [wrangler CLI](https://developers.cloudflare.com/workers/wrangler/install-and-update/)
- [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`)

### Setup

1. **Clone the repository**
   ```bash
   git clone https://github.com/mattsilv/robo.git
   cd robo
   ```

2. **Configure your environment**

   **Workers:** Update `workers/wrangler.toml` with your D1 database ID (see step 3).

   **iOS:** Edit `ios/project.yml` line 11 — set `DEVELOPMENT_TEAM` to your Apple Team ID.

3. **Deploy Workers backend**
   ```bash
   cd workers
   npm install

   # Create D1 database
   wrangler d1 create robo-db
   # Update wrangler.toml with the database ID

   # Run migrations
   wrangler d1 migrations apply robo-db --remote

   # Deploy
   wrangler deploy
   ```

4. **Build iOS app**
   ```bash
   cd ../ios
   xcodegen generate
   open Robo.xcodeproj
   # Build and run in Xcode
   ```

## Architecture

```
┌─────────┐     ┌──────────────────┐     ┌─────────┐
│  iOS    │────▶│  Workers (Hono)  │────▶│  Claude  │
│  App    │◀────│  D1 + R2         │◀────│  Code    │
└─────────┘     └──────────────────┘     └─────────┘
                   │  api.robo.app          │
                   │  mcp.robo.app          │
                   │                    MCP Client
                   │
              HIT Links
            (browser-based)
```

### Tech Stack

**iOS:**
- SwiftUI (iOS 17+)
- VisionKit (barcode scanning)
- ARKit + RoomPlan (LiDAR room scanning)
- URLSession (async/await networking)

**Backend:**
- Cloudflare Workers (Hono + TypeScript)
- D1 (SQLite database)
- R2 (object storage)
- MCP server (Streamable HTTP transport)

## API Endpoints

Base URL: `https://api.robo.app`

| Method | Path | Auth | Purpose |
|--------|------|:----:|---------|
| GET | `/health` | - | Health check |
| POST | `/api/devices/register` | - | Register device |
| GET | `/api/devices/:device_id` | - | Get device info |
| POST | `/api/sensors/data` | `X-Device-ID` | Submit sensor data |
| POST | `/api/sensors/upload` | `X-Device-ID` | Get presigned R2 URL |
| GET | `/api/inbox/:device_id` | - | Poll pending cards |
| POST | `/api/inbox/push` | `X-Device-ID` | Agent pushes card |
| POST | `/api/inbox/:card_id/respond` | `X-Device-ID` | User responds |
| POST | `/api/hits` | `X-Device-ID` | Create a HIT |
| GET | `/api/hits/:id` | - | Get HIT details (public) |
| POST | `/api/hits/:id/upload` | - | Upload photo to HIT |
| PATCH | `/api/hits/:id/complete` | - | Mark HIT completed |
| GET | `/api/hits/:id/photos` | - | List HIT photos |
| POST | `/api/debug/payload` | `X-Device-ID` | Store debug payload |
| POST | `/mcp` | `Bearer` | MCP endpoint |

### Example: Device Registration

```bash
http POST https://api.robo.app/api/devices/register \
  Content-Type:application/json \
  name="My iPhone" --timeout=10
```

Response:
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "My iPhone",
  "mcp_token": "4E00A6CBBC1B9AE14EFA4447CB191EEE",
  "registered_at": "2026-02-10T18:19:39.262Z",
  "last_seen_at": null
}
```

### Example: Submit Sensor Data (requires auth)

```bash
http POST https://api.robo.app/api/sensors/data \
  Content-Type:application/json \
  X-Device-ID:550e8400-e29b-41d4-a716-446655440000 \
  device_id=550e8400-e29b-41d4-a716-446655440000 \
  sensor_type=barcode \
  data:='{"value":"012345678901"}' --timeout=10
```

## Development

### iOS Development

```bash
cd ios

# Generate Xcode project
xcodegen generate

# Build for simulator
xcodebuild -scheme Robo -configuration Debug -sdk iphonesimulator build
```

**Note:** Barcode scanner and LiDAR require a physical device (not supported on simulator).

### Workers Development

```bash
cd workers

# Local development
npm run dev

# Deploy to production
npm run deploy

# Query database
wrangler d1 execute robo-db --command "SELECT * FROM devices"
```

## Testing

### Manual Testing

1. Install app on physical iPhone via Xcode
2. Open app and navigate to Sensors tab
3. Tap "Barcode Scanner"
4. Scan a barcode (e.g., product UPC)
5. Verify data in D1:
   ```bash
   wrangler d1 execute robo-db --command "SELECT * FROM sensor_data ORDER BY captured_at DESC LIMIT 5"
   ```

### API Testing

```bash
# Health check
http GET https://api.robo.app/health --timeout=10

# Register device
http POST https://api.robo.app/api/devices/register \
  Content-Type:application/json \
  name=test-device --timeout=10
```

## Deployment

### TestFlight

Auto-deploys to TestFlight on push to `main` when `ios/**` files change (via `.github/workflows/testflight.yml`). Can also trigger manually:
```bash
gh workflow run testflight.yml
```

See [docs/testflight-deployment.md](docs/testflight-deployment.md) for complete TestFlight deployment guide.

### Workers Production

```bash
cd workers
wrangler deploy
```

## Documentation

- [CLAUDE.md](CLAUDE.md) - Development conventions
- [docs/cloudflare-resources.md](docs/cloudflare-resources.md) - Cloudflare resource inventory
- [docs/testflight-deployment.md](docs/testflight-deployment.md) - TestFlight deployment guide
- [docs/use-cases.md](docs/use-cases.md) - Use cases and demo scenarios
- [docs/solutions/](docs/solutions/) - Problem solutions and troubleshooting

## Contributing

This is a hackathon project, but contributions are welcome after the initial submission!

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

## License

[MIT](LICENSE)

## Acknowledgments

Built by [Matt Silverman](https://silv.app) and [Claude Code](https://claude.ai/code)

- [Hono](https://hono.dev/) web framework
- [VisionKit](https://developer.apple.com/documentation/visionkit) for barcode scanning
- [ARKit + RoomPlan](https://developer.apple.com/augmented-reality/roomplan/) for LiDAR scanning
- [Cloudflare Workers](https://workers.cloudflare.com/) for serverless backend
