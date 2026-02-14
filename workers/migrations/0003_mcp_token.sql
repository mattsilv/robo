-- Add MCP authentication token for device-scoped access
ALTER TABLE devices ADD COLUMN mcp_token TEXT;

-- Backfill existing devices with tokens
UPDATE devices SET mcp_token = hex(randomblob(16)) WHERE mcp_token IS NULL;
