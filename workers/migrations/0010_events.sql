CREATE TABLE events (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  type TEXT NOT NULL,
  device_id TEXT,
  endpoint TEXT NOT NULL,
  status TEXT NOT NULL,
  duration_ms INTEGER,
  metadata TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_events_type_created ON events (type, created_at);
CREATE INDEX idx_events_device_created ON events (device_id, created_at);
