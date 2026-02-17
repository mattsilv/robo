-- Users table for Sign in with Apple / Google
CREATE TABLE users (
  id TEXT PRIMARY KEY,
  apple_sub TEXT UNIQUE,
  google_sub TEXT,
  email TEXT,
  first_name TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Link devices to users (optional — backward compat with anonymous devices)
ALTER TABLE devices ADD COLUMN user_id TEXT REFERENCES users(id);
