-- Migration: HIT (Human Intelligence Task) tables
-- Created: 2026-02-12

-- HITs table: shareable task links for human data collection
CREATE TABLE hits (
  id TEXT PRIMARY KEY,                    -- 8-char URL-safe short ID
  sender_name TEXT NOT NULL,              -- e.g. "M. Silverman"
  recipient_name TEXT NOT NULL,           -- e.g. "James"
  task_description TEXT NOT NULL,         -- e.g. "Photo the inside of your fridge"
  agent_name TEXT,                        -- e.g. "Simple Chef Agent"
  status TEXT NOT NULL DEFAULT 'pending', -- 'pending', 'in_progress', 'completed', 'expired'
  photo_count INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  started_at TEXT,                        -- when recipient first opened
  completed_at TEXT,                      -- when recipient submitted
  device_id TEXT,                         -- sender's device (nullable for CLI-created)
  FOREIGN KEY (device_id) REFERENCES devices(id)
);

CREATE INDEX idx_hits_status ON hits(status);
CREATE INDEX idx_hits_device ON hits(device_id);

-- HIT photos: R2 references for uploaded photos
CREATE TABLE hit_photos (
  id TEXT PRIMARY KEY,                    -- UUID
  hit_id TEXT NOT NULL,
  r2_key TEXT NOT NULL,                   -- e.g. hits/{hit_id}/{photo_id}.jpg
  file_size INTEGER,
  uploaded_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (hit_id) REFERENCES hits(id)
);

CREATE INDEX idx_hit_photos_hit ON hit_photos(hit_id);
