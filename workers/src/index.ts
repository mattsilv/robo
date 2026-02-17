import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { logger } from 'hono/logger';
import { prettyJSON } from 'hono/pretty-json';
import type { Env } from './types';

// Import route handlers
import { registerDevice, getDevice, saveAPNsToken } from './routes/devices';
import { submitSensorData } from './routes/sensors';
import { getInbox, pushCard, respondToCard } from './routes/inbox';
import { analyzeWithOpus } from './routes/opus';
import { debugSync, debugList, debugGet, debugDownload } from './routes/debug';
import { uploadScreenshot } from './routes/screenshots';
import { lookupNutrition } from './routes/nutrition';
import { createHit, getHit, deleteHit, bulkDeleteHits, uploadHitPhoto, completeHit, listHits, listHitPhotos, respondToHit, listHitResponses } from './routes/hits';
import { serveHitPage } from './routes/hitPage';
import { serveOgImage } from './routes/ogImage';
import { listAPIKeys, createAPIKey, deleteAPIKey } from './routes/apikeys';
import { chatProxy } from './routes/chat';
import { appleAuth, appleAuthCallback, linkDevice, getMe, logout } from './routes/auth';
import { getSettings, updateSettings } from './routes/settings';
import { deviceAuth } from './middleware/deviceAuth';
import { mcpTokenAuth } from './middleware/mcpTokenAuth';
import { userAuth, csrfProtect } from './middleware/userAuth';
import { rateLimit } from './middleware/rateLimit';
import { handleMcpRequest } from './mcp';

const app = new Hono<{ Bindings: Env }>();

// Middleware
app.use('*', cors({
  origin: ['https://app.robo.app', 'https://robo.app', 'http://localhost:5173'],
  credentials: true,
  allowHeaders: ['Content-Type', 'Authorization', 'X-Device-ID'],
  allowMethods: ['GET', 'POST', 'PUT', 'PATCH', 'DELETE', 'OPTIONS'],
}));
app.use('*', logger());
app.use('*', prettyJSON());

// Health check
app.get('/health', (c) => {
  return c.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Auth routes
app.post('/api/auth/apple', csrfProtect, appleAuth);
app.post('/api/auth/apple/callback', appleAuthCallback);
app.post('/api/auth/link-device', csrfProtect, userAuth, linkDevice);
app.get('/api/auth/me', userAuth, getMe);
app.post('/api/auth/logout', csrfProtect, logout);

// Settings routes (user auth required)
app.get('/api/settings', userAuth, getSettings);
app.patch('/api/settings', csrfProtect, userAuth, updateSettings);

// Device routes
app.post('/api/devices/register', registerDevice);
app.get('/api/devices/:device_id', getDevice);
app.post('/api/devices/:device_id/apns-token', deviceAuth, saveAPNsToken);

// Sensor routes (auth required)
app.post('/api/sensors/data', deviceAuth, submitSensorData);

// Inbox routes (auth required)
app.get('/api/inbox/:device_id', deviceAuth, getInbox);
app.post('/api/inbox/push', deviceAuth, pushCard);
app.post('/api/inbox/:card_id/respond', deviceAuth, respondToCard);

// Nutrition lookup (proxied Nutritionix API)
app.get('/api/nutrition/lookup', deviceAuth, lookupNutrition);

// Opus integration
app.post('/api/opus/analyze', analyzeWithOpus);

// Chat proxy (OpenRouter) — auth required, rate limited
app.post('/api/chat', deviceAuth, rateLimit({ endpoint: 'chat', maxRequests: 20, windowSeconds: 300 }), chatProxy);

// HIT owner routes (auth required)
app.post('/api/hits', deviceAuth, createHit);
app.get('/api/hits', deviceAuth, listHits);
app.post('/api/hits/bulk-delete', deviceAuth, bulkDeleteHits);
app.delete('/api/hits/:id', deviceAuth, deleteHit);
app.get('/api/hits/:id/photos', deviceAuth, listHitPhotos);
app.get('/api/hits/:id/responses', deviceAuth, listHitResponses);

// HIT public routes (accessed via share link by non-app users)
app.get('/api/hits/:id', getHit);
app.post('/api/hits/:id/upload', uploadHitPhoto);
app.patch('/api/hits/:id/complete', completeHit);
app.post('/api/hits/:id/respond', respondToHit);

// HIT web page — served by Workers with dynamic OG tags (not Pages static files)
app.get('/hit/:id/og.png', serveOgImage);
app.get('/hit/:id', serveHitPage);

// API Key management (requires MCP token auth)
app.get('/api/keys', mcpTokenAuth, listAPIKeys);
app.post('/api/keys', mcpTokenAuth, createAPIKey);
app.delete('/api/keys/:key_id', mcpTokenAuth, deleteAPIKey);

// Screenshot upload (Share Extension → R2)
app.post('/api/screenshots', deviceAuth, uploadScreenshot);

// Debug sync (auth required — stores scan data in R2 for developer debugging)
app.post('/api/debug/sync', deviceAuth, debugSync);
app.get('/api/debug/sync/:device_id', deviceAuth, debugList);
app.get('/api/debug/sync/:device_id/:key{.+}', deviceAuth, debugGet);
app.get('/api/debug/download/:key{.+}', debugDownload);

// Error handling
app.onError((err, c) => {
  if (err instanceof SyntaxError && err.message.includes('JSON')) {
    return c.json({ error: 'Malformed JSON in request body' }, 400);
  }
  console.error('Error:', err);
  return c.json({ error: 'Internal Server Error' }, 500);
});

// 404 handler
app.notFound((c) => {
  return c.json({ error: 'Not Found' }, 404);
});

// Export with MCP routing before Hono
export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const url = new URL(request.url);

    // MCP endpoint — handled outside Hono (needs raw Request for WebStandardStreamableHTTPServerTransport)
    if (url.pathname === '/mcp') {
      // CORS preflight for MCP Inspector (browser-based testing)
      if (request.method === 'OPTIONS') {
        return new Response(null, {
          headers: {
            'Access-Control-Allow-Origin': '*',
            'Access-Control-Allow-Methods': 'GET, POST, DELETE, OPTIONS',
            'Access-Control-Allow-Headers': 'Content-Type, Accept, Mcp-Session-Id, Authorization',
          },
        });
      }
      return handleMcpRequest(request, env, ctx);
    }

    // Everything else → existing Hono app
    return app.fetch(request, env, ctx);
  },
};
