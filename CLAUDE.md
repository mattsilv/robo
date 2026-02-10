# Robo — Development Conventions

## Project Overview
iOS app that exposes phone sensors (barcode, camera, LiDAR) as API endpoints for AI agents. Backend on Cloudflare Workers.

**Deadline:** Mon Feb 16, 3:00 PM EST

## Elevator Pitch (Vibe Coders)

You can build AI agents easily with Claude Projects or custom GPTs. But getting phone sensor data into those agents? That still requires building a native iOS app - months of Swift, Xcode, and App Store friction.

**Robo is the missing bridge:** Open-source iOS app (robo.app) that turns your phone's sensors into APIs any AI agent can use.

- **No iOS development required** - Skip the Swift learning curve
- **Provider-agnostic** - Works with Claude, ChatGPT, your custom backend, or just email
- **Open source** - Fork it, extend it, audit the code
- **Free tier** - Email/zip export works without any backend (privacy-first)

**Demo scenario (30 seconds):**
1. Download Robo from App Store
2. Point phone at room, tap "Scan with LiDAR"
3. 3D point cloud appears in your Claude Project
4. Agent: "Your room is 12ft × 14ft. Here's where that couch would fit..."

**Why it matters:** Getting LiDAR data into Claude today is impossible. Robo makes it trivial.

See [docs/use-cases.md](docs/use-cases.md) for detailed examples.

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

### iOS — prefer CLI over Xcode UI
Use command-line builds whenever possible. Only use XcodeBuildMCP simulator tools for UI testing that doesn't need sensors. Barcode, LiDAR, and camera features require a physical device.

```bash
cd ios
xcodegen generate         # Generate .xcodeproj from project.yml
xcodebuild -scheme Robo -configuration Debug | xcsift  # Build (errors only)

# Build for physical device
xcodebuild -scheme Robo -configuration Debug \
  -destination 'generic/platform=iOS' \
  -allowProvisioningUpdates \
  CODE_SIGN_IDENTITY="Apple Development" \
  DEVELOPMENT_TEAM=R3Z5CY34Q5

# Install and launch on physical device (no Xcode UI needed)
DEVICE_ID=7BDE5F34-030C-589D-9F0F-65C6B8DD2B48
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData/Robo-*/Build/Products/Debug-iphoneos -name "Robo.app" -maxdepth 1 | head -1)
xcrun devicectl device install app --device $DEVICE_ID "$APP_PATH"
xcrun devicectl device process launch --device $DEVICE_ID com.silv.Robo
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

## PR Review Guide

**For reviewers new to this codebase:**

### Quick Orientation (5 min)
1. Read [README.md](README.md) - Architecture and quick start
2. Check [docs/cloudflare-resources.md](docs/cloudflare-resources.md) - Infrastructure inventory
3. Review this file (CLAUDE.md) - Coding conventions

### Key Design Decisions to Understand

**Backend (Workers):**
- **Manual Zod validation** over `@hono/zod-validator` - See [docs/solutions/build-errors/hono-zod-cloudflare-workers-validation-20260210.md](docs/solutions/build-errors/hono-zod-cloudflare-workers-validation-20260210.md)
- **D1 only in M1** - R2 integration deferred to M2
- **nodejs_compat flag required** - For Node.js built-ins (crypto, buffer)

**iOS:**
- **@Observable pattern** over Combine/SwiftUI @Published - Modern iOS 17+ approach
- **DataScannerViewController** over AVFoundation - Higher-level VisionKit API
- **xcodegen** for project management - Avoids .xcodeproj merge conflicts

### What to Review

**Architecture & Design:**
- [ ] Does the solution fit the problem scope (hackathon MVP)?
- [ ] Are abstractions appropriate (not over-engineered)?
- [ ] Are there simpler alternatives to complex code?

**Code Quality:**
- [ ] Swift: No force-unwraps, proper optionals handling, guard statements
- [ ] TypeScript: Proper types, no `any`, Zod schemas match endpoints
- [ ] Error handling: User-facing errors are clear, technical details logged

**Security:**
- [ ] No hardcoded secrets or API keys
- [ ] Sensitive data only in .env (never committed)
- [ ] Input validation on all API endpoints

**Testing:**
- [ ] Can someone else clone and run this? (README accuracy)
- [ ] Are manual testing steps documented?
- [ ] Does the build succeed? (`xcodebuild` for iOS, `wrangler deploy` for Workers)

### How to Give Feedback

**Preferred format:**
```markdown
## [Section/File]

**Observation:** [What you noticed]
**Suggestion:** [Specific recommendation]
**Reasoning:** [Why this matters]
**Priority:** [Critical/High/Medium/Low]
```

**Example:**
```markdown
## iOS - BarcodeScannerView.swift:73

**Observation:** Haptic feedback occurs before API call completes
**Suggestion:** Consider moving haptic to after successful API response
**Reasoning:** User gets feedback even if network fails
**Priority:** Low (M1 scope is fine, consider for M2)
```

### Where to Find Things

- **API Endpoints:** `workers/src/routes/*.ts`
- **iOS Views:** `ios/Robo/Views/*.swift`
- **Data Models:** `ios/Robo/Models/*.swift` and `workers/src/types.ts`
- **Database Schema:** `workers/migrations/0001_initial_schema.sql`
- **Solved Problems:** `docs/solutions/build-errors/`
- **Infrastructure:** `docs/cloudflare-resources.md`

### Questions to Ask

- "Why this approach over [alternative]?" - Check commit messages and solution docs
- "What's the trade-off here?" - Likely speed vs complexity for hackathon deadline
- "Will this scale?" - M1 is MVP, scalability addressed in M2-M4

### Response Time Expectations

This is a **hackathon project** (deadline: Feb 16, 3 PM EST). Prioritize:
1. **Blocking issues** (security, broken builds) - Immediate
2. **High-value suggestions** (simple wins, quick fixes) - Within hours
3. **Nice-to-haves** (refactors, optimizations) - Note for post-M1

**Thank you for reviewing!** 🙏
