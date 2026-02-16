CREATE TABLE rate_limits (
  device_id TEXT NOT NULL,
  endpoint TEXT NOT NULL,
  window_start TEXT NOT NULL,
  request_count INTEGER NOT NULL DEFAULT 1,
  PRIMARY KEY (device_id, endpoint, window_start)
);
