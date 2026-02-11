import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { logger } from 'hono/logger';
import { prettyJSON } from 'hono/pretty-json';
import type { Env } from './types';

// Import route handlers
import { registerDevice, getDevice } from './routes/devices';
import { submitSensorData } from './routes/sensors';
import { getInbox, pushCard, respondToCard } from './routes/inbox';
import { analyzeWithOpus } from './routes/opus';
import { debugSync, debugList, debugGet } from './routes/debug';
import { deviceAuth } from './middleware/deviceAuth';

const app = new Hono<{ Bindings: Env }>();

// Middleware
app.use('*', cors());
app.use('*', logger());
app.use('*', prettyJSON());

// Health check
app.get('/health', (c) => {
  return c.json({ status: 'ok', timestamp: new Date().toISOString() });
});

// Device routes
app.post('/api/devices/register', registerDevice);
app.get('/api/devices/:device_id', getDevice);

// Sensor routes (auth required)
app.post('/api/sensors/data', deviceAuth, submitSensorData);

// Inbox routes
app.get('/api/inbox/:device_id', getInbox);
app.post('/api/inbox/push', deviceAuth, pushCard);
app.post('/api/inbox/:card_id/respond', deviceAuth, respondToCard);

// Opus integration
app.post('/api/opus/analyze', analyzeWithOpus);

// Debug sync (stores scan data in R2 for developer debugging)
app.post('/api/debug/sync', debugSync);
app.get('/api/debug/sync/:device_id', debugList);
app.get('/api/debug/sync/:device_id/:key{.+}', debugGet);

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

export default app;
