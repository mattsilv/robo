# Cloudflare Resources

## D1 Database
- **Name:** robo-db
- **ID:** `fb24f9a0-d52b-4a74-87ca-54069ec9471a`
- **Binding:** `DB`
- **Tables:** devices, sensor_data, inbox_cards

## R2 Bucket
- **Name:** robo-data
- **Binding:** `BUCKET`
- **Purpose:** Store uploaded images, LiDAR meshes, and other sensor data blobs

## Workers
- **Name:** robo-api
- **URL:** https://robo-api.silv.workers.dev
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
