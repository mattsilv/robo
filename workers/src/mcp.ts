import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { WebStandardStreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js';
import { z } from 'zod';
import type { Env } from './types';

const MAX_R2_PAYLOAD_BYTES = 500_000; // 500 KB safety limit

function createRoboMcpServer(env: Env, deviceId: string) {
  const server = new McpServer({
    name: 'Robo Sensor Bridge',
    version: '1.0.0',
  });

  server.tool(
    'get_device_info',
    'Get info about the authenticated Robo device',
    {},
    async () => {
      try {
        const result = await env.DB.prepare(
          'SELECT id, name, registered_at, last_seen_at FROM devices WHERE id = ?'
        ).bind(deviceId).first();
        return {
          content: [{ type: 'text', text: JSON.stringify(result, null, 2) }],
        };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }], isError: true };
      }
    }
  );

  server.tool(
    'list_captures',
    'List sensor captures for this device. Filter by sensor_type (barcode, camera, lidar, motion, beacon). Returns IDs and timestamps — use get_capture for full data.',
    {
      sensor_type: z.enum(['barcode', 'camera', 'lidar', 'motion', 'beacon']).optional()
        .describe('Filter by sensor type'),
      limit: z.number().default(20).describe('Max results (default 20)'),
    },
    async ({ sensor_type, limit }) => {
      try {
        let query = 'SELECT id, device_id, sensor_type, captured_at FROM sensor_data WHERE device_id = ?';
        const binds: any[] = [deviceId];
        if (sensor_type) { query += ' AND sensor_type = ?'; binds.push(sensor_type); }
        query += ' ORDER BY captured_at DESC LIMIT ?';
        binds.push(limit);

        const result = await env.DB.prepare(query).bind(...binds).all();
        return {
          content: [{ type: 'text', text: JSON.stringify(result.results, null, 2) }],
        };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }], isError: true };
      }
    }
  );

  server.tool(
    'get_capture',
    'Get full sensor capture data by ID (includes the raw JSON payload)',
    { id: z.number().describe('Capture ID from list_captures') },
    async ({ id }) => {
      try {
        const result = await env.DB.prepare(
          'SELECT * FROM sensor_data WHERE id = ? AND device_id = ?'
        ).bind(id, deviceId).first();
        if (!result) {
          return { content: [{ type: 'text', text: 'Capture not found' }] };
        }
        const parsed = { ...result, data: JSON.parse(result.data as string) };
        return {
          content: [{ type: 'text', text: JSON.stringify(parsed, null, 2) }],
        };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }], isError: true };
      }
    }
  );

  server.tool(
    'get_latest_capture',
    'Get the most recent sensor capture from this device. For LiDAR room scans, this returns the D1 summary — for the FULL 3D room data, also call list_debug_payloads and get_debug_payload to retrieve the complete room geometry from R2.',
    {
      sensor_type: z.enum(['barcode', 'camera', 'lidar', 'motion', 'beacon']).optional()
        .describe('Filter by sensor type'),
    },
    async ({ sensor_type }) => {
      try {
        let query = 'SELECT * FROM sensor_data WHERE device_id = ?';
        const binds: any[] = [deviceId];
        if (sensor_type) { query += ' AND sensor_type = ?'; binds.push(sensor_type); }
        query += ' ORDER BY captured_at DESC LIMIT 1';

        const result = await env.DB.prepare(query).bind(...binds).first();
        if (!result) {
          return { content: [{ type: 'text', text: 'No captures found. The user may not have scanned anything yet.' }] };
        }
        const parsed = { ...result, data: JSON.parse(result.data as string) };

        let hint = '';
        if (parsed.sensor_type === 'lidar') {
          hint = '\n\n[TIP: This is the D1 summary. For full 3D room geometry, call list_debug_payloads with this device_id, then get_debug_payload for the complete room scan JSON.]';
        }

        return {
          content: [{ type: 'text', text: JSON.stringify(parsed, null, 2) + hint }],
        };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }], isError: true };
      }
    }
  );

  server.tool(
    'list_debug_payloads',
    'List debug sync payloads stored in R2 for this device — these contain FULL sensor data (complete LiDAR room scans with 3D geometry, wall positions, surfaces). Use get_debug_payload to retrieve one.',
    {},
    async () => {
      try {
        const prefix = `debug/${deviceId}/`;
        const listed = await env.BUCKET.list({ prefix, limit: 50 });
        const items = listed.objects.map((obj) => ({
          key: obj.key,
          size: obj.size,
          size_human: obj.size > 1_000_000
            ? `${(obj.size / 1_000_000).toFixed(1)} MB`
            : `${(obj.size / 1_000).toFixed(1)} KB`,
          uploaded: obj.uploaded.toISOString(),
        }));
        return {
          content: [{ type: 'text', text: JSON.stringify(items, null, 2) }],
        };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }], isError: true };
      }
    }
  );

  server.tool(
    'get_debug_payload',
    'Retrieve a debug payload from R2 (full room scan JSON, etc.). Large payloads (>500KB) are truncated to fit in context.',
    {
      key: z.string().describe('R2 object key from list_debug_payloads'),
    },
    async ({ key }) => {
      try {
        const obj = await env.BUCKET.get(key);
        if (!obj) {
          return { content: [{ type: 'text', text: 'Payload not found' }] };
        }
        const text = await obj.text();
        if (text.length > MAX_R2_PAYLOAD_BYTES) {
          const truncated = text.substring(0, MAX_R2_PAYLOAD_BYTES);
          return {
            content: [{
              type: 'text',
              text: `[TRUNCATED: ${text.length} bytes total, showing first ${MAX_R2_PAYLOAD_BYTES} bytes]\n\n${truncated}`,
            }],
          };
        }
        return { content: [{ type: 'text', text }] };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }], isError: true };
      }
    }
  );

  return server;
}

/**
 * Handle an MCP request using stateless WebStandard transport.
 * Creates a new McpServer per request (SDK 1.26.0+ security requirement).
 */
export async function handleMcpRequest(request: Request, env: Env): Promise<Response> {
  // Extract and validate Bearer token
  const authHeader = request.headers.get('Authorization');
  const token = authHeader?.startsWith('Bearer ') ? authHeader.slice(7) : null;

  if (!token) {
    return new Response(JSON.stringify({
      jsonrpc: '2.0',
      error: { code: -32000, message: 'Missing Authorization header. Use: claude mcp add robo --transport http URL --header "Authorization: Bearer YOUR_TOKEN"' },
      id: null,
    }), { status: 401, headers: { 'Content-Type': 'application/json' } });
  }

  const device = await env.DB.prepare(
    'SELECT id, name FROM devices WHERE mcp_token = ?'
  ).bind(token).first<{ id: string; name: string }>();

  if (!device) {
    return new Response(JSON.stringify({
      jsonrpc: '2.0',
      error: { code: -32000, message: 'Invalid token' },
      id: null,
    }), { status: 401, headers: { 'Content-Type': 'application/json' } });
  }

  const server = createRoboMcpServer(env, device.id);
  const transport = new WebStandardStreamableHTTPServerTransport({
    sessionIdGenerator: undefined, // Stateless mode
  });
  await server.connect(transport);
  return transport.handleRequest(request);
}
