-- Migration: Add vendor_id for idempotent device registration
-- vendor_id = UIDevice.identifierForVendor (persists across app updates)
-- Used to dedup device registrations from the same physical phone

ALTER TABLE devices ADD COLUMN vendor_id TEXT;

CREATE UNIQUE INDEX idx_devices_vendor_id ON devices(vendor_id) WHERE vendor_id IS NOT NULL;
