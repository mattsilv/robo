-- HIT structured responses (availability polls, etc.)
CREATE TABLE IF NOT EXISTS hit_responses (
  id TEXT PRIMARY KEY,
  hit_id TEXT NOT NULL REFERENCES hits(id),
  respondent_name TEXT NOT NULL,
  response_data TEXT NOT NULL,  -- JSON
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  FOREIGN KEY (hit_id) REFERENCES hits(id)
);

CREATE INDEX IF NOT EXISTS idx_hit_responses_hit_id ON hit_responses(hit_id);

-- Add hit_type and config columns to hits table
ALTER TABLE hits ADD COLUMN hit_type TEXT DEFAULT 'photo';
ALTER TABLE hits ADD COLUMN config TEXT;
