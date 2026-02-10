# Robo

> Phone sensors (barcode, camera, LiDAR) as API endpoints for AI agents

**Hackathon Project** | **Deadline:** Mon Feb 16, 3:00 PM EST

## Overview

Robo is an iOS app that exposes phone sensors as HTTP API endpoints, allowing AI agents to request real-world data. Built with SwiftUI and Cloudflare Workers.

**Live API:** https://robo-api.silv.workers.dev

## Features

### M1 (Current)
- ✅ Barcode scanner with VisionKit
- ✅ Real-time data submission to cloud
- ✅ Device management and settings
- ✅ Cloudflare Workers backend (Hono + D1 + R2)

### Coming Soon
- M2: Inbox card system + Camera + AI analysis
- M3: LiDAR room scanning
- M4: Task system + API documentation
- M5: Production deployment

## Quick Start

### Prerequisites

- Xcode 15.0+ (for iOS development)
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

2. **Configure environment**
   ```bash
   cp .env.example .env
   # Edit .env with your Apple Team ID and Cloudflare Account ID
   ```

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
│  App    │◀────│  D1 + R2         │◀────│  Opus    │
└─────────┘     └──────────────────┘     └─────────┘
                        ▲
                        │
                   AI Agents
                  (external)
```

### Tech Stack

**iOS:**
- SwiftUI (iOS 17+)
- VisionKit (barcode scanning)
- ARKit (LiDAR - coming in M3)
- URLSession (async/await networking)

**Backend:**
- Cloudflare Workers (Hono + TypeScript)
- D1 (SQLite database)
- R2 (object storage)
- Anthropic Claude API (M2+)

## API Endpoints

| Method | Path | Purpose |
|--------|------|---------|
| GET | `/health` | Health check |
| POST | `/api/devices/register` | Register device |
| POST | `/api/sensors/data` | Submit sensor data |
| POST | `/api/sensors/upload` | Get presigned R2 URL |
| GET | `/api/inbox/:device_id` | Poll pending cards |
| POST | `/api/inbox/push` | Agent pushes card |
| POST | `/api/inbox/:card_id/respond` | User responds |
| POST | `/api/opus/analyze` | Trigger AI analysis |

### Example: Device Registration

```bash
curl -X POST https://robo-api.silv.workers.dev/api/devices/register \
  -H "Content-Type: application/json" \
  -d '{"name":"My iPhone"}'
```

Response:
```json
{
  "id": "550e8400-e29b-41d4-a716-446655440000",
  "name": "My iPhone",
  "registered_at": "2026-02-10T18:19:39.262Z",
  "last_seen_at": null
}
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

**Note:** Barcode scanner requires a physical device (not supported on simulator).

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
curl https://robo-api.silv.workers.dev/health

# Register device
curl -X POST https://robo-api.silv.workers.dev/api/devices/register \
  -H "Content-Type: application/json" \
  -d '{"name":"test-device"}'
```

## Deployment

### TestFlight

See [docs/testflight-deployment.md](docs/testflight-deployment.md) for complete TestFlight deployment guide.

**Quick steps:**
1. Create 1024x1024 app icon
2. Archive in Xcode: Product → Archive
3. Upload to App Store Connect
4. Submit for TestFlight review

### Workers Production

```bash
cd workers
wrangler deploy
```

## Documentation

- [CLAUDE.md](CLAUDE.md) - Development conventions
- [docs/cloudflare-resources.md](docs/cloudflare-resources.md) - Cloudflare resource inventory
- [docs/testflight-deployment.md](docs/testflight-deployment.md) - TestFlight deployment guide
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

- Built with [Claude Code](https://claude.com/claude-code)
- [Hono](https://hono.dev/) web framework
- [VisionKit](https://developer.apple.com/documentation/visionkit) for barcode scanning
- [Cloudflare Workers](https://workers.cloudflare.com/) for serverless backend

---

**Project Status:** M1 Complete (5/5 milestones) | **Next Milestone:** M2 (Inbox + Camera + AI)
