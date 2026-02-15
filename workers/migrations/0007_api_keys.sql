CREATE TABLE api_keys (
  id TEXT PRIMARY KEY,
  device_id TEXT NOT NULL REFERENCES devices(id),
  key_value TEXT NOT NULL UNIQUE,
  label TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_api_keys_device ON api_keys(device_id);
CREATE INDEX idx_api_keys_value ON api_keys(key_value);
