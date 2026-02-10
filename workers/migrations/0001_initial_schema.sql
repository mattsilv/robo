-- Migration: Initial schema for Robo API
-- Created: 2026-02-10

-- Devices table: Store registered device UUIDs
CREATE TABLE devices (
  id TEXT PRIMARY KEY,
  name TEXT NOT NULL,
  registered_at TEXT NOT NULL DEFAULT (datetime('now')),
  last_seen_at TEXT
);

-- Sensor data table: Store barcode scans, camera uploads, LiDAR data
CREATE TABLE sensor_data (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  device_id TEXT NOT NULL,
  sensor_type TEXT NOT NULL,  -- 'barcode', 'camera', 'lidar'
  data TEXT NOT NULL,          -- JSON payload
  captured_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (device_id) REFERENCES devices(id)
);

CREATE INDEX idx_sensor_data_device ON sensor_data(device_id);
CREATE INDEX idx_sensor_data_type ON sensor_data(sensor_type);

-- Inbox cards table: Agent-pushed tasks/questions for devices
CREATE TABLE inbox_cards (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL,
  card_type TEXT NOT NULL,     -- 'decision', 'task', 'info'
  title TEXT NOT NULL,
  body TEXT,
  response TEXT,
  status TEXT NOT NULL DEFAULT 'pending',  -- 'pending', 'responded', 'expired'
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  responded_at TEXT,
  FOREIGN KEY (device_id) REFERENCES devices(id)
);

CREATE INDEX idx_inbox_cards_device ON inbox_cards(device_id);
CREATE INDEX idx_inbox_cards_status ON inbox_cards(status);
