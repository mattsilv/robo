-- Add group_id to link related HITs (e.g. all participants in one availability poll)
ALTER TABLE hits ADD COLUMN group_id TEXT;
CREATE INDEX idx_hits_group_id ON hits(group_id);
