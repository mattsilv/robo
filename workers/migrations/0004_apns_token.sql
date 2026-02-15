-- Add APNs push notification token to devices
ALTER TABLE devices ADD COLUMN apns_token TEXT;
ALTER TABLE devices ADD COLUMN apns_token_updated_at TEXT;
