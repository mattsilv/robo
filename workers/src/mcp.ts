import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { WebStandardStreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js';
import { z } from 'zod';
import type { Env } from './types';

const MAX_SAMPLE_BYTES = 5_000; // 5 KB structural sample for room scan context

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
    'Retrieve a debug payload from R2. For room scans, returns a compact summary with engineering guidance instead of raw JSON — use the download URL to get the full data locally.\n\nWHAT YOU CAN BUILD with room scan data:\n- Generate an interactive 3D viewer (Three.js) with labeled walls, doors, windows, and furniture\n- Compute paint/flooring estimates from wall areas and floor dimensions\n- Check if furniture with given dimensions fits against a specific wall\n- Create a dimensioned floor plan SVG for contractors\n- Calculate material costs (paint, flooring, trim) based on room geometry',
    {
      key: z.string().describe('R2 object key from list_debug_payloads'),
    },
    async ({ key }) => {
      try {
        const expectedPrefix = `debug/${deviceId}/`;
        if (!key.startsWith(expectedPrefix)) {
          return {
            content: [{ type: 'text', text: `Access denied. Keys must start with ${expectedPrefix}` }],
            isError: true,
          };
        }
        const obj = await env.BUCKET.get(key);
        if (!obj) {
          return { content: [{ type: 'text', text: 'Payload not found' }] };
        }
        const text = await obj.text();
        let parsed: any;
        try { parsed = JSON.parse(text); } catch { parsed = null; }

        // Room scan: return summary + guidance instead of raw JSON
        if (parsed && (parsed.walls || parsed.floors)) {
          const walls = parsed.walls || [];
          const floors = parsed.floors || [];
          const doors = parsed.doors || [];
          const windows = parsed.windows || [];
          const objects = parsed.objects || [];

          const totalWallArea = walls.reduce((sum: number, w: any) => {
            const d = w.dimensions || {};
            return sum + (d.x || 0) * (d.y || 0);
          }, 0);

          const totalFloorArea = floors.reduce((sum: number, f: any) => {
            const d = f.dimensions || {};
            return sum + (d.x || 0) * (d.z || 0);
          }, 0);

          let minX = Infinity, maxX = -Infinity, minZ = Infinity, maxZ = -Infinity;
          for (const f of floors) {
            for (const c of (f.polygonCorners || [])) {
              if (c.x < minX) minX = c.x;
              if (c.x > maxX) maxX = c.x;
              if (c.z < minZ) minZ = c.z;
              if (c.z > maxZ) maxZ = c.z;
            }
          }

          const toFt = (m: number) => +(m * 3.28084).toFixed(1);
          const sample: any = {};
          if (walls.length) sample.walls_sample = [walls[0]];
          if (floors.length) sample.floors_sample = [floors[0]];
          if (objects.length) sample.objects_sample = [objects[0]];

          const summary = {
            type: 'room_scan_summary',
            stats: {
              walls: walls.length,
              floors: floors.length,
              doors: doors.length,
              windows: windows.length,
              objects: objects.length,
              object_categories: [...new Set(objects.map((o: any) => o.category))],
              total_wall_area_sqft: +(totalWallArea * 10.7639).toFixed(1),
              total_floor_area_sqft: +(totalFloorArea * 10.7639).toFixed(1),
              room_dimensions_ft: `${toFt(maxX - minX)} x ${toFt(maxZ - minZ)}`,
              payload_size_bytes: text.length,
              payload_size_human: text.length > 1_000_000
                ? `${(text.length / 1_000_000).toFixed(1)} MB`
                : `${(text.length / 1_000).toFixed(1)} KB`,
            },
            download_url: `/api/debug/download/${encodeURIComponent(key)}`,
            download_instructions: 'Use this URL with your Bearer token to download the full JSON to a local file. Do NOT load it into context — save to disk and process programmatically.',
            viewer_template_url: '/static/room-viewer.html',
            viewer_instructions: 'Fetch the HTML template, replace {{ROOM_DATA}} with the downloaded JSON, save as a local .html file, and open in browser.',
            schema: {
              walls: '{ dimensions: {x: width, y: height, z: depth}, transform: {columns: [[4x4 col-major]]} }',
              floors: '{ polygonCorners: [{x,y,z}], dimensions, transform }',
              doors: '{ dimensions, transform }',
              windows: '{ dimensions, transform }',
              objects: '{ category: string, dimensions, transform }',
              coordinate_system: 'Apple RoomPlan Y-up (same as Three.js). Transforms are column-major 4x4. Position = columns[3].',
            },
            engineering_guidance: [
              '1. DOWNLOAD: fetch download_url with Bearer token, save to local .json file',
              '2. 3D VIEWER: fetch viewer_template_url, replace {{ROOM_DATA}} with JSON, save as .html, open in browser',
              '3. PAINT ESTIMATE: total_wall_area_sqft / 350 = gallons (one coat). Subtract doors (~21 sqft) and windows (~15 sqft each)',
              '4. FURNITURE FIT: find target wall by index, compare wall dimensions.x (width) vs furniture width',
              '5. FLOOR PLAN SVG: use floor polygonCorners for outline, add wall segments and door arcs',
              '6. FLOORING: total_floor_area_sqft + 10% waste factor for ordering',
            ],
            structural_sample: sample,
          };

          return {
            content: [{ type: 'text', text: JSON.stringify(summary, null, 2) }],
          };
        }

        // Non-room-scan: return directly if small, summary if large
        if (text.length > 50_000) {
          return {
            content: [{
              type: 'text',
              text: `[LARGE PAYLOAD: ${text.length} bytes — download via /api/debug/download/${encodeURIComponent(key)}]\n\n${text.substring(0, MAX_SAMPLE_BYTES)}...`,
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
export async function handleMcpRequest(request: Request, env: Env, ctx?: ExecutionContext): Promise<Response> {
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

  // Record heartbeat timestamp (fire-and-forget)
  if (ctx) {
    ctx.waitUntil(
      env.DB.prepare('UPDATE devices SET last_mcp_call_at = ? WHERE id = ?')
        .bind(new Date().toISOString(), device.id).run()
    );
  }

  const server = createRoboMcpServer(env, device.id);
  const transport = new WebStandardStreamableHTTPServerTransport({
    sessionIdGenerator: undefined, // Stateless mode
  });
  await server.connect(transport);
  return transport.handleRequest(request);
}
