-- Track last MCP call timestamp for connection status indicator
ALTER TABLE devices ADD COLUMN last_mcp_call_at TEXT;
