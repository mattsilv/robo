import { McpServer } from '@modelcontextprotocol/sdk/server/mcp.js';
import { WebStandardStreamableHTTPServerTransport } from '@modelcontextprotocol/sdk/server/webStandardStreamableHttp.js';
import { z } from 'zod';
import { HIT_DISTRIBUTION_MODES, type DistributionMode } from './types';
import type { Env } from './types';
import { detectDistributionMode } from './routes/hits';

const MAX_SAMPLE_BYTES = 5_000; // 5 KB structural sample for room scan context

/** Generate a Python script that renders a 2D floor plan PNG and opens it in the browser. */
function generateFloorPlanScript(
  polygon: { x: number; y: number }[],
  widthFt: number,
  depthFt: number,
  objects: { category: string; x_ft: number; y_ft: number; width_ft: number; depth_ft: number }[],
): string {
  const pts = polygon.map((p) => `(${p.x}, ${p.y})`).join(', ');
  const objLines = objects.map((o) =>
    `    ax.add_patch(plt.Rectangle((${o.x_ft - o.width_ft / 2}, ${o.y_ft - o.depth_ft / 2}), ${o.width_ft}, ${o.depth_ft}, fc='#dbeafe', ec='#3b82f6', lw=1))\n` +
    `    ax.text(${o.x_ft}, ${o.y_ft}, '${o.category}', ha='center', va='center', fontsize=7, color='#1e40af')`
  ).join('\n');

  return `#!/usr/bin/env python3
"""Robo floor plan renderer — auto-generated from LiDAR scan. Run: python3 /tmp/floor_plan.py"""
import subprocess, sys
try:
    import matplotlib
except ImportError:
    subprocess.check_call([sys.executable, '-m', 'pip', 'install', 'matplotlib'])
    import matplotlib
matplotlib.use('Agg')
import matplotlib.pyplot as plt
from matplotlib.patches import Polygon
import webbrowser, os

polygon = [${pts}]
fig, ax = plt.subplots(1, 1, figsize=(10, 8))
ax.add_patch(Polygon(polygon, closed=True, fc='#f8fafc', ec='#1e293b', lw=2))
ax.set_aspect('equal')
xs = [p[0] for p in polygon]
ys = [p[1] for p in polygon]
margin = 2
ax.set_xlim(min(xs) - margin, max(xs) + margin)
ax.set_ylim(min(ys) - margin, max(ys) + margin)
ax.set_xlabel('feet')
ax.set_ylabel('feet')
ax.set_title('Floor Plan (${widthFt} x ${depthFt} ft)')
ax.grid(True, alpha=0.3)
# Label dimensions
ax.annotate(f'${widthFt} ft', xy=((min(xs)+max(xs))/2, min(ys)-1), ha='center', fontsize=10, color='#64748b')
ax.annotate(f'${depthFt} ft', xy=(min(xs)-1, (min(ys)+max(ys))/2), ha='center', fontsize=10, color='#64748b', rotation=90)
# Objects
if True:
${objLines || '    pass'}
out = '/tmp/robo_floor_plan.png'
fig.savefig(out, dpi=150, bbox_inches='tight')
print(f'Floor plan saved to {out}')
webbrowser.open('file://' + os.path.abspath(out))
`;
}

function createRoboMcpServer(env: Env, deviceId: string) {
  const server = new McpServer({
    name: 'Robo Sensor Bridge',
    version: '1.0.0',
  });

  server.tool(
    'get_device_info',
    'Get info about the authenticated Robo device and verify the MCP connection is healthy. If the connection is broken (e.g., screenshots not showing up), this will detect it.',
    {},
    async () => {
      try {
        const device = await env.DB.prepare(
          'SELECT id, name, vendor_id, registered_at, last_seen_at FROM devices WHERE id = ?'
        ).bind(deviceId).first<any>();

        if (!device) {
          return { content: [{ type: 'text', text: 'ERROR: Device not found. MCP token may be orphaned. Ask the user to re-register in Robo Settings.' }], isError: true };
        }

        // Check for duplicate devices with same vendor_id (split device problem)
        let healthWarnings: string[] = [];
        if (device.vendor_id) {
          const dupes = await env.DB.prepare(
            'SELECT id FROM devices WHERE vendor_id = ? AND id != ?'
          ).bind(device.vendor_id, deviceId).all();
          if (dupes.results.length > 0) {
            healthWarnings.push(`WARNING: ${dupes.results.length} duplicate device(s) found with same vendor_id. This can cause screenshots to upload to the wrong device. Device IDs: ${dupes.results.map((d: any) => d.id).join(', ')}`);
          }
        } else {
          healthWarnings.push('WARNING: No vendor_id set. This device was registered before the identity migration. Screenshots may upload to a different device record.');
        }

        // Check for recent screenshots
        const recentScreenshot = await env.DB.prepare(
          "SELECT captured_at FROM sensor_data WHERE device_id = ? AND sensor_type = 'camera' ORDER BY captured_at DESC LIMIT 1"
        ).bind(deviceId).first<{ captured_at: string }>();

        const recentCapture = await env.DB.prepare(
          'SELECT captured_at FROM sensor_data WHERE device_id = ? ORDER BY captured_at DESC LIMIT 1'
        ).bind(deviceId).first<{ captured_at: string }>();

        const info = {
          device_id: device.id,
          name: device.name,
          vendor_id: device.vendor_id || 'NOT SET',
          registered_at: device.registered_at,
          last_seen_at: device.last_seen_at,
          last_screenshot: recentScreenshot?.captured_at || 'never',
          last_any_capture: recentCapture?.captured_at || 'never',
          health: healthWarnings.length === 0 ? 'OK' : 'ISSUES DETECTED',
          warnings: healthWarnings,
        };

        let text = JSON.stringify(info, null, 2);
        if (healthWarnings.length > 0) {
          text = 'HEALTH CHECK: ISSUES DETECTED\n\n' + healthWarnings.join('\n') + '\n\n' + text;
        }

        return { content: [{ type: 'text', text }] };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }], isError: true };
      }
    }
  );

  // @ts-expect-error - MCP SDK deep type instantiation
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
        const parsed: Record<string, unknown> = { ...result, data: JSON.parse(result.data as string) };

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

  // @ts-expect-error - MCP SDK deep type instantiation
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

          // Extract floor polygon in 2D feet (same as iOS RoomDataProcessor)
          const floorPolygon2dFt: { x: number; y: number }[] = [];
          if (floors.length > 0) {
            const f = floors[0];
            const corners = f.polygonCorners || [];
            // Transform corners from local to world space using the floor's 4x4 transform
            const cols = f.transform?.columns;
            for (const c of corners) {
              let wx: number, wz: number;
              if (cols && cols.length === 4) {
                // column-major 4x4: world = M * local
                wx = cols[0][0] * c.x + cols[1][0] * c.y + cols[2][0] * c.z + cols[3][0];
                wz = cols[0][2] * c.x + cols[1][2] * c.y + cols[2][2] * c.z + cols[3][2];
              } else {
                wx = c.x;
                wz = c.z;
              }
              floorPolygon2dFt.push({
                x: +(wx * 3.28084).toFixed(2),
                y: +(wz * 3.28084).toFixed(2),
              });
            }
          }

          // Simplified objects list: category + position + size in feet (no matrices)
          const objectsSummary = objects.map((o: any) => {
            const d = o.dimensions || {};
            const cols = o.transform?.columns;
            const pos = cols?.[3] || [0, 0, 0];
            return {
              category: o.category || 'unknown',
              x_ft: toFt(pos[0] || 0),
              y_ft: toFt(pos[2] || 0),
              width_ft: toFt(d.x || 0),
              depth_ft: toFt(d.z || 0),
            };
          });

          const widthFt = toFt(maxX - minX);
          const depthFt = toFt(maxZ - minZ);
          const downloadPath = `/api/debug/download/${encodeURIComponent(key)}`;

          // Python floor plan script — renders PNG and opens in browser
          const floorPlanScript = generateFloorPlanScript(floorPolygon2dFt, widthFt, depthFt, objectsSummary);

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
              room_dimensions_ft: `${widthFt} x ${depthFt}`,
              payload_size_bytes: text.length,
              payload_size_human: text.length > 1_000_000
                ? `${(text.length / 1_000_000).toFixed(1)} MB`
                : `${(text.length / 1_000).toFixed(1)} KB`,
            },
            floor_polygon_2d_ft: floorPolygon2dFt,
            objects_summary: objectsSummary,
            download_url: downloadPath,
            viewer_template_url: '/static/room-viewer.html',
            actionable_commands: [
              `# Download full room JSON (save to disk, do NOT load into context)`,
              `http GET https://api.robo.app${downloadPath} 'Authorization:Bearer YOUR_TOKEN' --download -o /tmp/room.json`,
              `# Render 2D floor plan PNG (auto-opens in browser)`,
              `python3 /tmp/floor_plan.py`,
              `# Open interactive 3D viewer`,
              `http GET https://api.robo.app/static/room-viewer.html --download -o /tmp/viewer.html && sed -i '' 's/{{ROOM_DATA}}/'$(cat /tmp/room.json)'/g' /tmp/viewer.html && open /tmp/viewer.html`,
              `# Paint estimate: ${+(totalWallArea * 10.7639).toFixed(1)} sqft / 350 = ${+((totalWallArea * 10.7639) / 350).toFixed(1)} gallons (one coat). Subtract ~21 sqft per door, ~15 sqft per window.`,
              `# Flooring: ${+(totalFloorArea * 10.7639).toFixed(1)} sqft + 10% waste = ${+((totalFloorArea * 10.7639) * 1.1).toFixed(0)} sqft to order`,
            ],
            floor_plan_script: floorPlanScript,
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

  // @ts-expect-error - MCP SDK deep type instantiation
  server.tool(
    'create_hit',
    `Create a HIT (Human Intelligence Task) link to collect data from people. Three distribution modes:
- individual: Separate link per person (name baked in). Best for close friends, zero friction.
- group: Single link, pick name from dropdown (~10 people).
- open: Single link, type your name (large groups, public).`,
    {
      task_description: z.string().describe('What you need from them'),
      distribution_mode: z.enum(['individual', 'group', 'open']).describe('How to distribute the link'),
      participants: z.array(z.string()).optional().describe('Names of participants (required for individual and group modes)'),
      sender_name: z.string().optional().describe('Your display name on the HIT page'),
      hit_type: z.enum(['photo', 'poll', 'availability', 'group_poll']).optional().describe('Type of HIT'),
      config: z.record(z.any()).optional().describe('Additional config (e.g. date_options, time_slots)'),
    },
    async ({ task_description, distribution_mode, participants, sender_name, hit_type, config }) => {
      try {
        // Validate mode requirements
        if ((distribution_mode === 'individual' || distribution_mode === 'group') && (!participants || participants.length === 0)) {
          return { content: [{ type: 'text', text: `Error: '${distribution_mode}' mode requires participants array.` }], isError: true };
        }

        const now = new Date().toISOString();
        const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
        const genId = () => { const b = new Uint8Array(8); crypto.getRandomValues(b); return Array.from(b, (v) => chars[v % chars.length]).join(''); };
        const resolvedSender = sender_name || 'Someone';

        if (distribution_mode === 'individual') {
          const groupId = `grp_${genId()}`;
          const results: { name: string; url: string }[] = [];
          for (const name of participants!) {
            const id = genId();
            await env.DB.prepare(
              `INSERT INTO hits (id, sender_name, recipient_name, task_description, agent_name, status, photo_count, created_at, device_id, hit_type, config, group_id) VALUES (?, ?, ?, ?, ?, 'pending', 0, ?, ?, ?, ?, ?)`
            ).bind(id, resolvedSender, name, task_description, null, now, deviceId, hit_type || 'photo', config ? JSON.stringify(config) : null, groupId).run();
            results.push({ name, url: `https://robo.app/hit/${id}` });
          }
          let text = `Created ${results.length} individual HIT links (group: ${groupId}):\n`;
          for (const r of results) text += `  ${r.name}: ${r.url}\n`;
          return { content: [{ type: 'text', text }] };
        }

        if (distribution_mode === 'group') {
          const id = genId();
          const mergedConfig = { ...(config || {}), participants };
          await env.DB.prepare(
            `INSERT INTO hits (id, sender_name, recipient_name, task_description, agent_name, status, photo_count, created_at, device_id, hit_type, config, group_id) VALUES (?, ?, ?, ?, ?, 'pending', 0, ?, ?, ?, ?, ?)`
          ).bind(id, resolvedSender, 'Group', task_description, null, now, deviceId, hit_type || 'photo', JSON.stringify(mergedConfig), null).run();
          return { content: [{ type: 'text', text: `Created group HIT: https://robo.app/hit/${id}\nParticipants: ${participants!.join(', ')}\nRecipients pick their name from a dropdown.` }] };
        }

        // open mode
        const id = genId();
        await env.DB.prepare(
          `INSERT INTO hits (id, sender_name, recipient_name, task_description, agent_name, status, photo_count, created_at, device_id, hit_type, config, group_id) VALUES (?, ?, ?, ?, ?, 'pending', 0, ?, ?, ?, ?, ?)`
        ).bind(id, resolvedSender, 'Anyone', task_description, null, now, deviceId, hit_type || 'photo', config ? JSON.stringify(config) : null, null).run();
        return { content: [{ type: 'text', text: `Created open HIT: https://robo.app/hit/${id}\nAnyone can respond — they type their name on the page.` }] };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }], isError: true };
      }
    }
  );

  // @ts-expect-error - MCP SDK deep type instantiation
  server.tool(
    'check_hit_status',
    'Check the status of recent HITs (Human Intelligence Tasks) — availability polls, group polls, etc. Returns the most recent HITs with response details so you can see who has responded and what they said. If no hit_id is provided, returns the 3 most recent HITs.',
    {
      hit_id: z.string().optional().describe('Specific HIT ID to check. If omitted, returns the 3 most recent.'),
    },
    async ({ hit_id }) => {
      try {
        let hits: any[];
        if (hit_id) {
          const hit = await env.DB.prepare('SELECT * FROM hits WHERE id = ? AND device_id = ?')
            .bind(hit_id, deviceId).first();
          hits = hit ? [hit] : [];
        } else {
          const result = await env.DB.prepare(
            'SELECT * FROM hits WHERE device_id = ? ORDER BY created_at DESC LIMIT 3'
          ).bind(deviceId).all();
          hits = result.results;
        }

        if (hits.length === 0) {
          return { content: [{ type: 'text', text: 'No HITs found.' }] };
        }

        const enriched = [];
        for (const hit of hits) {
          const responses = await env.DB.prepare(
            'SELECT respondent_name, response_data, created_at FROM hit_responses WHERE hit_id = ? ORDER BY created_at ASC'
          ).bind(hit.id).all();

          const config = hit.config ? JSON.parse(hit.config) : {};
          const participants: string[] = config.participants || [];
          const respondedNames = responses.results.map((r: any) => r.respondent_name);
          const notResponded = participants.filter((p: string) => !respondedNames.includes(p));

          enriched.push({
            id: hit.id,
            type: hit.hit_type,
            distribution_mode: detectDistributionMode(hit as any),
            title: config.title || hit.task_description,
            status: hit.status,
            created_at: hit.created_at,
            url: `https://robo.app/hit/${hit.id}`,
            participants,
            responded: respondedNames,
            not_responded: notResponded,
            responses: responses.results.map((r: any) => ({
              name: r.respondent_name,
              data: JSON.parse(r.response_data),
              at: r.created_at,
            })),
          });
        }

        // For the most recent HIT, provide a natural language summary
        const latest = enriched[0];
        let summary = `Most recent HIT: "${latest.title}" (${latest.type})\n`;
        summary += `Status: ${latest.status} | Created: ${latest.created_at}\n`;
        summary += `Link: ${latest.url}\n\n`;

        if (latest.participants.length > 0) {
          summary += `Responded (${latest.responded.length}/${latest.participants.length}): ${latest.responded.join(', ') || 'nobody yet'}\n`;
          if (latest.not_responded.length > 0) {
            summary += `Still waiting on: ${latest.not_responded.join(', ')}\n`;
          }
        }

        if (latest.responses.length > 0) {
          summary += '\nResponses:\n';
          for (const r of latest.responses) {
            summary += `  ${r.name}: ${JSON.stringify(r.data)}\n`;
          }
        }

        return {
          content: [{ type: 'text', text: summary + '\n\n' + JSON.stringify(enriched, null, 2) }],
        };
      } catch (err: any) {
        return { content: [{ type: 'text', text: `Error: ${err.message}` }], isError: true };
      }
    }
  );

  server.tool(
    'get_screenshot',
    'Get the most recent screenshot shared from the iOS Share Extension. Returns the image as base64 so Claude can see it directly.\n\nIMPORTANT: The image is deleted from cloud storage immediately after retrieval for privacy. You MUST save it to /tmp/RoboScreenshots/ using the suggested filename BEFORE doing anything else with it. Create the directory if it doesn\'t exist. This may be the only copy — the user may not have saved it to their phone.',
    {},
    async () => {
      try {
        const row = await env.DB.prepare(
          "SELECT * FROM sensor_data WHERE device_id = ? AND sensor_type = 'camera' AND data LIKE '%share_extension%' ORDER BY captured_at DESC LIMIT 1"
        ).bind(deviceId).first();

        if (!row) {
          return { content: [{ type: 'text', text: 'No screenshots found. Share a screenshot from iOS using Share → Robo.' }] };
        }

        const data = JSON.parse(row.data as string);
        const r2Key = data.r2_key;
        if (!r2Key) {
          return { content: [{ type: 'text', text: 'Screenshot metadata found but no R2 key.' }] };
        }

        const obj = await env.BUCKET.get(r2Key);
        if (!obj) {
          // Screenshot may have expired (R2 lifecycle: 7-day TTL on screenshots/ prefix)
          return { content: [{ type: 'text', text: `Screenshot expired or not found. Screenshots are automatically deleted after 24 hours for privacy (or immediately after first retrieval). Ask the user to share it again.` }] };
        }

        const arrayBuffer = await obj.arrayBuffer();
        const bytes = new Uint8Array(arrayBuffer);

        // Base64 encode
        let binary = '';
        for (let i = 0; i < bytes.length; i++) {
          binary += String.fromCharCode(bytes[i]);
        }
        const base64 = btoa(binary);

        // Delete from R2 after successful fetch — screenshots are transient
        let deleted = false;
        try { await env.BUCKET.delete(r2Key); deleted = true; } catch { /* lifecycle will clean up */ }

        const suggestedName = `robo-screenshot-${(row.captured_at as string).replace(/[:.]/g, '-')}.jpg`;
        const privacyNote = deleted
          ? 'It has been deleted from cloud storage and this may be the only copy.'
          : 'Cloud deletion failed — it will be auto-removed within 24 hours by lifecycle policy. This may be the only easily accessible copy.';

        return {
          content: [
            {
              type: 'image' as const,
              data: base64,
              mimeType: 'image/jpeg',
            },
            {
              type: 'text',
              text: `Screenshot captured at ${row.captured_at}. File size: ${data.file_size || 'unknown'} bytes.\n\nACTION REQUIRED: Save this image to /tmp/RoboScreenshots/${suggestedName} IMMEDIATELY (create the directory if needed). ${privacyNote}`,
            },
          ],
        };
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

  // Debounced heartbeat: only write to D1 if last_mcp_call_at is >1 minute stale.
  // Skips the write if already recent, reducing from ~197K writes/day to ~1/device/min.
  if (ctx) {
    ctx.waitUntil(
      env.DB.prepare(
        `UPDATE devices SET last_mcp_call_at = ?
         WHERE id = ? AND (last_mcp_call_at IS NULL OR last_mcp_call_at < datetime('now', '-1 minute'))`
      ).bind(new Date().toISOString(), device.id).run()
    );
  }

  const server = createRoboMcpServer(env, device.id);
  const transport = new WebStandardStreamableHTTPServerTransport({
    sessionIdGenerator: undefined, // Stateless mode
  });
  await server.connect(transport);
  return transport.handleRequest(request);
}
