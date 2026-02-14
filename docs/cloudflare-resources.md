# Cloudflare Resources

## D1 Database
- **Name:** robo-db
- **ID:** `fb24f9a0-d52b-4a74-87ca-54069ec9471a`
- **Binding:** `DB`
- **Tables:** devices, sensor_data, inbox_cards, hits, hit_photos

## R2 Bucket
- **Name:** robo-data
- **Binding:** `BUCKET`
- **Purpose:** Store uploaded images, LiDAR meshes, and other sensor data blobs
- **Key prefixes:**
  - `debug/` — Developer debug payloads
  - `hits/` — HIT photo uploads (format: `hits/{hit_id}/{photo_id}.jpg`)

## Workers
- **Name:** robo-api
- **URL:** https://api.robo.app (custom domain), https://mcp.robo.app (MCP custom domain), https://robo-api.silv.workers.dev (workers.dev fallback)
- **Version ID:** `98e106f7-db42-4791-ac6d-d9add74313e1`
- **Main File:** `src/index.ts`
- **Framework:** Hono + TypeScript

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
| POST | `/api/opus/analyze` | Trigger Opus analysis |
| POST | `/api/hits` | Create a new HIT |
| GET | `/api/hits` | List all HITs |
| GET | `/api/hits/:id` | Get HIT details (public) |
| POST | `/api/hits/:id/upload` | Upload photo to HIT (binary body) |
| PATCH | `/api/hits/:id/complete` | Mark HIT as completed |
| GET | `/api/hits/:id/photos` | List photos for a HIT |

## App Store Connect
- **App Name:** ROBO.APP
- **App ID:** `6759011077`
- **Bundle ID:** `com.silv.Robo`
- **SKU:** `robo`
- **Apple ID:** `matt@argentlabs.xyz`
- **Dashboard:** https://appstoreconnect.apple.com/apps/6759011077/distribution/ios/version/inflight

## Pages (Landing Page + HIT Pages)
- **Project:** robo-app
- **URL:** https://robo.app
- **Source:** `site/` (static assets)
- **Functions:** `functions/` (Pages Functions at project root)
- **Deploy:** `wrangler pages deploy site --project-name=robo-app --commit-dirty=true --branch=main`

### Pages Functions
| Route | File | Purpose |
|-------|------|---------|
| `/hit/:id` | `functions/hit/[id].ts` | Dynamic HIT page with personalized OG tags + photo capture UI |

### D1 Migrations
| File | Tables | Purpose |
|------|--------|---------|
| `0001_initial_schema.sql` | devices, sensor_data, inbox_cards | Core tables |
| `0002_hits.sql` | hits, hit_photos | HIT system tables |

## Wrangler Commands

```bash
# Deploy Workers
wrangler deploy

# Run D1 migrations
wrangler d1 migrations apply robo-db --remote

# Query D1 database
wrangler d1 execute robo-db --command "SELECT * FROM devices"

# List R2 buckets
wrangler r2 bucket list
```
