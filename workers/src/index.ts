import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { logger } from 'hono/logger';
import { prettyJSON } from 'hono/pretty-json';
import type { Env } from './types';

// Import route handlers
import { registerDevice } from './routes/devices';
import { submitSensorData, getUploadUrl } from './routes/sensors';
import { getInbox, pushCard, respondToCard } from './routes/inbox';
import { analyzeWithOpus } from './routes/opus';

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

// Sensor routes
app.post('/api/sensors/data', submitSensorData);
app.post('/api/sensors/upload', getUploadUrl);

// Inbox routes
app.get('/api/inbox/:device_id', getInbox);
app.post('/api/inbox/push', pushCard);
app.post('/api/inbox/:card_id/respond', respondToCard);

// Opus integration
app.post('/api/opus/analyze', analyzeWithOpus);

// Error handling
app.onError((err, c) => {
  console.error('Error:', err);
  return c.json({ error: err.message || 'Internal Server Error' }, 500);
});

// 404 handler
app.notFound((c) => {
  return c.json({ error: 'Not Found' }, 404);
});

export default app;
