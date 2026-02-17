-- Add index on devices.mcp_token to eliminate full table scans on every auth lookup.
-- Without this index, each MCP auth check scanned the entire devices table (~33 rows/call).
CREATE UNIQUE INDEX idx_devices_mcp_token ON devices (mcp_token) WHERE mcp_token IS NOT NULL;

-- Clean up events older than 30 days to prevent unbounded table growth.
-- Run manually or via Cron Trigger as needed.
-- DELETE FROM events WHERE created_at < datetime('now', '-30 days');
