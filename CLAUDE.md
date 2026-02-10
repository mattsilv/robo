# Robo — Development Conventions

## Project Overview
iOS app that exposes phone sensors (barcode, camera, LiDAR) as API endpoints for AI agents. Backend on Cloudflare Workers.

**Deadline:** Mon Feb 16, 3:00 PM EST

## Technology Stack

### iOS (Swift)
- **Language:** Swift 5.9+
- **Framework:** SwiftUI (iOS 17+)
- **Architecture:** @Observable pattern, async/await for networking
- **Project Management:** xcodegen (generates .xcodeproj from project.yml)
- **Key Frameworks:** VisionKit (barcode), ARKit (LiDAR), AVFoundation (camera)

### Backend (TypeScript)
- **Runtime:** Cloudflare Workers
- **Framework:** Hono
- **Database:** D1 (SQLite)
- **Storage:** R2 (object storage)
- **Language:** TypeScript 5+

## Coding Conventions

### Swift Style
- Use `async/await` for all network calls, never completion handlers
- Use `@Observable` macro for state management (not `@Published`)
- Use `UIViewRepresentable` to wrap UIKit components (AVCaptureSession)
- Error handling: explicit `throws` in signatures, `do-catch` at call sites
- Never force-unwrap optionals in production code
- Use `guard let` for early returns
- Naming: `camelCase` for variables/functions, `PascalCase` for types

### TypeScript Style
- Use Hono's typed routing patterns
- All DB access via Cloudflare D1 bindings
- Zod for request/response validation
- Error handling: return typed error responses, never throw
- Use `c.env` for environment bindings (D1, R2, secrets)

### API Design
- RESTful endpoints with semantic HTTP methods
- JSON request/response bodies
- ISO 8601 timestamps (UTC)
- Device authentication via UUID in headers

## Project Structure

```
robo/
├── ios/
│   ├── project.yml          # xcodegen config
│   └── Robo/
│       ├── RoboApp.swift    # App entry point
│       ├── Views/           # SwiftUI views
│       ├── Services/        # API clients, device services
│       ├── Models/          # Codable data models
│       └── Resources/       # Assets, Info.plist
├── workers/
│   ├── src/
│   │   ├── index.ts         # Hono app entry
│   │   ├── routes/          # API route handlers
│   │   ├── db/              # D1 schema and queries
│   │   └── types.ts         # Shared TypeScript types
│   ├── wrangler.toml        # Cloudflare config
│   └── package.json
├── demo/                    # Demo videos, screenshots
└── CLAUDE.md
```

## Build Commands

### iOS
```bash
cd ios
xcodegen generate         # Generate .xcodeproj from project.yml
xcodebuild -scheme Robo -configuration Debug | xcsift  # Build (errors only)
```

### Workers
```bash
cd workers
npm install
npm run dev              # Local dev server
npm run deploy           # Deploy to production
wrangler d1 migrations apply robo-db  # Run DB migrations
```

## Testing

### iOS
- Barcode scanner requires physical device (simulator not supported)
- Use TestFlight for testing on real hardware
- LiDAR requires iPhone Pro models (12 Pro+)

### Workers
- Use Postman/httpie for API testing
- Test D1 queries: `wrangler d1 execute robo-db --command "SELECT * FROM devices"`

## Deployment

### Workers
```bash
wrangler deploy
```

### iOS
1. Archive in Xcode: Product → Archive
2. Upload to App Store Connect
3. Submit for TestFlight review

## Environment Variables

Create `.env` in project root:
```bash
APPLE_TEAM_ID=R3Z5CY34Q5
CLOUDFLARE_ACCOUNT_ID=<your-account-id>
```

## Cloudflare Resources

**D1 Database:** robo-db (`fb24f9a0-d52b-4a74-87ca-54069ec9471a`)
**R2 Bucket:** robo-data
**Workers API:** https://robo-api.silv.workers.dev

See `docs/cloudflare-resources.md` for complete resource inventory.

## Critical Gotchas

### iOS
- **DataScannerViewController:** Must call `startScanning()` explicitly, must guard `DataScannerViewController.isAvailable`, no simulator support
- **Camera Permissions:** Add `NSCameraUsageDescription` to Info.plist
- Always set `Content-Type: application/json` header in URLSession requests

### Workers
- **Hono + Zod:** Add `onError` handler for Zod validation failures
- **D1 Bindings:** Access via `c.env.DB`, not global
- **R2 CORS:** Must configure CORS for browser uploads

## Code Review Checklist

Before committing:
- [ ] No force-unwraps (`!`) in Swift code
- [ ] All async functions use `async/await` (not callbacks)
- [ ] TypeScript types defined for all API routes
- [ ] Error handling for all network calls
- [ ] Camera/sensor permissions documented in Info.plist
