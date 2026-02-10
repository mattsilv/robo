import { z } from 'zod';

// Cloudflare bindings
export type Env = {
  DB: D1Database;
  BUCKET: R2Bucket;
  ENVIRONMENT: string;
};

// Request schemas
export const RegisterDeviceSchema = z.object({
  name: z.string().min(1).max(100),
});

export const SensorDataSchema = z.object({
  device_id: z.string().uuid(),
  sensor_type: z.enum(['barcode', 'camera', 'lidar']),
  data: z.record(z.any()),
});

export const PushCardSchema = z.object({
  device_id: z.string().uuid(),
  card_type: z.enum(['decision', 'task', 'info']),
  title: z.string().min(1).max(200),
  body: z.string().optional(),
});

export const RespondCardSchema = z.object({
  response: z.string().min(1),
});

export const AnalyzeRequestSchema = z.object({
  image_url: z.string().url().optional(),
  prompt: z.string().min(1),
});

// Response types
export type Device = {
  id: string;
  name: string;
  registered_at: string;
  last_seen_at: string | null;
};

export type SensorData = {
  id: number;
  device_id: string;
  sensor_type: 'barcode' | 'camera' | 'lidar';
  data: Record<string, any>;
  captured_at: string;
};

export type InboxCard = {
  id: string;
  device_id: string;
  card_type: 'decision' | 'task' | 'info';
  title: string;
  body: string | null;
  response: string | null;
  status: 'pending' | 'responded' | 'expired';
  created_at: string;
  responded_at: string | null;
};
