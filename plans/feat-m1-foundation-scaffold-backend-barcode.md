# M1: Foundation — Scaffold + Backend + Barcode E2E

**Issues:** #1, #2, #3, #4, #5
**Gate:** Barcode scan on physical iPhone → data in D1, TestFlight submitted
**Deadline context:** Day 1 of 6-day hackathon (Mon Feb 16, 3 PM EST final)

---

## Tool Setup (Before Any Code)

```bash
# 1. XcodeBuildMCP — lets Claude build/run/screenshot iOS apps
claude mcp add XcodeBuildMCP -- npx -y xcodebuildmcp@latest mcp

# 2. xcodegen — generate .xcodeproj from YAML
brew install xcodegen

# 3. xcsift — filter xcodebuild output to errors only
brew install xcsift

# 4. Cache a simulator UDID for CLAUDE.md
xcrun simctl list devices available | grep "iPhone"
```

---

## Issue #1: Repo Scaffold

```
CLAUDE.md, .gitignore, LICENSE (MIT), empty dirs: ios/, workers/, demo/
```

CLAUDE.md conventions: iOS 17+, SwiftUI, @Observable, async/await, URLSession. Workers: Hono, TypeScript. Build commands with xcsift. Simulator UDID.

```bash
git init && git remote add origin git@github.com:mattsilv/robo.git
# write files, initial commit + push
```

---

## Issue #2: Workers Backend

### One file, three endpoints

```
workers/
├── src/
│   └── index.ts          -- all routes (~60 lines)
├── schema.sql            -- 1 table
├── wrangler.toml
├── package.json
└── tsconfig.json
```

### Setup

```bash
cd workers
npm create hono@latest . -- --template cloudflare-workers
npm install zod @hono/zod-validator
```

### wrangler.toml

```toml
name = "robo-api"
main = "src/index.ts"
compatibility_date = "2026-02-01"

[[d1_databases]]
binding = "DB"
database_name = "robo-db"
database_id = "<from wrangler d1 create>"
```

No R2 in M1 (no blobs). No Anthropic SDK in M1 (no Opus calls yet).

### D1 Schema — 1 table

```sql
CREATE TABLE scans (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  barcode_value TEXT NOT NULL,
  symbology TEXT,
  created_at TEXT DEFAULT (datetime('now'))
);
```

No `devices` table. No FK. Device ID is client-generated UUID stored in UserDefaults. No registration endpoint needed.

No `inbox_cards` table — that's M2.

### API (3 endpoints)

```typescript
import { Hono } from 'hono';
import { zValidator } from '@hono/zod-validator';
import { z } from 'zod';

type Env = { Bindings: { DB: D1Database } };

const app = new Hono<Env>();

// Error handler — normalize all errors to { error: string }
app.onError((err, c) => {
  console.error(err);
  return c.json({ error: err.message }, 400);
});

// Health check
app.get('/api/health', (c) => c.json({ status: 'ok' }));

// Submit barcode scan
app.post('/api/scans', zValidator('json', z.object({
  device_id: z.string().uuid(),
  barcode_value: z.string().min(1),
  symbology: z.string().optional(),
})), async (c) => {
  const { device_id, barcode_value, symbology } = c.req.valid('json');
  const id = crypto.randomUUID();
  await c.env.DB.prepare(
    'INSERT INTO scans (id, device_id, barcode_value, symbology) VALUES (?, ?, ?, ?)'
  ).bind(id, device_id, barcode_value, symbology ?? null).run();
  return c.json({ data: { id, barcode_value, symbology } }, 201);
});

// List scans (for verification)
app.get('/api/scans', async (c) => {
  const { results } = await c.env.DB.prepare(
    'SELECT * FROM scans ORDER BY created_at DESC LIMIT 50'
  ).all();
  return c.json({ data: results });
});

// Request logging
app.use('*', async (c, next) => {
  const start = Date.now();
  await next();
  console.log(`${c.req.method} ${c.req.path} ${c.res.status} ${Date.now() - start}ms`);
});

export default app;
```

### Deploy

```bash
wrangler d1 create robo-db          # note the database_id → wrangler.toml
wrangler d1 execute robo-db --file=schema.sql
wrangler deploy
# Test:
http POST https://robo-api.<account>.workers.dev/api/scans \
  device_id="$(uuidgen)" barcode_value="0123456789012" symbology="ean13" --timeout=10
```

---

## Issue #3: iOS App

### 4 files, single screen

```
ios/
├── project.yml
└── Robo/
    ├── RoboApp.swift              -- @main, single ContentView
    ├── ContentView.swift          -- "Scan" button + result display
    ├── BarcodeScannerView.swift   -- DataScannerViewController wrapper
    ├── APIClient.swift            -- one POST function
    └── Assets.xcassets/           -- must include AppIcon (1024x1024)
```

### project.yml

```yaml
name: Robo
options:
  bundleIdPrefix: app.robo
  deploymentTarget:
    iOS: "17.0"
  xcodeVersion: "16.0"
  createIntermediateGroups: true

settings:
  base:
    SWIFT_VERSION: "5.9"
    DEVELOPMENT_TEAM: <TEAM_ID>
    CODE_SIGN_STYLE: Automatic
    TARGETED_DEVICE_FAMILY: "1"

targets:
  Robo:
    type: application
    platform: iOS
    sources: [Robo]
    dependencies:
      - sdk: VisionKit.framework
    info:
      path: Robo/Info.plist
      properties:
        CFBundleDisplayName: Robo
        NSCameraUsageDescription: "Robo needs camera access to scan barcodes"
        UILaunchScreen: {}
        UISupportedInterfaceOrientations:
          - UIInterfaceOrientationPortrait
    settings:
      base:
        PRODUCT_BUNDLE_IDENTIFIER: app.robo.ios
        INFOPLIST_FILE: Robo/Info.plist
```

### Key: DataScannerViewController (VisionKit)

~50 lines vs ~150+ for raw AVFoundation. Built-in highlighting, zoom, guidance. Tradeoff: no simulator support (needs Neural Engine / physical device).

**Must remember:**
1. Call `try scanner.startScanning()` — without it, camera shows but nothing detects
2. Guard `DataScannerViewController.isAvailable` — crashes without Neural Engine
3. Dismiss sheet after scan, show confirmation on ContentView
4. Haptic feedback on detection

### APIClient pattern

```swift
struct APIClient {
    static let baseURL = "https://robo-api.<account>.workers.dev"

    static func postScan(deviceId: String, barcodeValue: String, symbology: String?) async throws {
        var request = URLRequest(url: URL(string: "\(baseURL)/api/scans")!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")  // CRITICAL
        let body: [String: Any] = [
            "device_id": deviceId,
            "barcode_value": barcodeValue,
            "symbology": symbology ?? ""
        ]
        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        let (_, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 201 else {
            throw URLError(.badServerResponse)
        }
    }
}
```

Device ID: generate once with `UUID().uuidString`, store in `UserDefaults`. No backend registration.

### Generate + build

```bash
cd ios && xcodegen generate
xcodebuild -project Robo.xcodeproj -scheme Robo \
  -destination "platform=iphonesimulator,id=<UDID>" \
  -derivedDataPath DerivedData build 2>&1 | xcsift -w
```

---

## Issue #4: Barcode E2E

1. User taps "Scan Barcode" on ContentView
2. Sheet presents BarcodeScannerView
3. DataScannerViewController starts scanning (call `startScanning()`)
4. Barcode detected → haptic → set scannedCode → dismiss sheet
5. ContentView shows barcode value + auto-POSTs via APIClient
6. Show success checkmark or error message

### Verify

```bash
wrangler d1 execute robo-db --command "SELECT * FROM scans"
```

---

## Issue #5: Deploy + TestFlight

### Prerequisites (do FIRST, before any code)
- [ ] Confirm Apple Developer Program membership active
- [ ] Create Bundle ID `app.robo.ios` in Developer Portal
- [ ] Create App record in App Store Connect
- [ ] Note Development Team ID → put in project.yml
- [ ] Generate 1024x1024 app icon placeholder

### TestFlight submission
Try Xcode Cloud first (Product > Xcode Cloud > Create Workflow). If not provisioned within 30 min, fall back to manual:

```bash
xcodebuild archive -project ios/Robo.xcodeproj -scheme Robo \
  -archivePath build/Robo.xcarchive -destination "generic/platform=iOS"
xcodebuild -exportArchive -archivePath build/Robo.xcarchive \
  -exportOptionsPlist ExportOptions.plist -exportPath build/
```

ExportOptions.plist must specify `method: app-store` + `teamID`.

---

## Known Gaps (catch during implementation)

1. **`startScanning()` must be called** — scanner is silent without it
2. **`Content-Type: application/json` header** — Hono silently fails without it
3. **App icon required** — TestFlight rejects without 1024x1024
4. **ExportOptions.plist** — create before manual archive
5. **Guard `DataScannerViewController.isAvailable`** — one-line crash prevention

---

## Dependency Graph

```
#1 Scaffold ──┬──▶ #2 Backend ──┬──▶ #4 Barcode E2E ──▶ #5 TestFlight
              └──▶ #3 iOS Shell ─┘
```

#2 and #3 can be parallelized after #1.

---

## M2+ Context (informational only, do NOT pre-build)

- M2: Inbox cards, camera capture → R2 → Opus vision. Will need `inbox_cards` table, R2 bucket, Anthropic SDK, presigned URLs.
- M3: LiDAR via ARKit. Will need `sensor_data` table generalization.
- M4: Task system, API docs, polish.
- M5: Demo video (30% of judging score), final TestFlight.
