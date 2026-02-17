/**
 * Shared Zod schemas for request/response validation.
 * Used by Workers (server-side) and web app (client-side).
 */
import { z } from 'zod';

// ─── Auth ───────────────────────────────────────────────────────────

export const UserSettingsSchema = z.object({
  first_name: z.string().min(1).max(50).optional(),
});

// ─── Chat ───────────────────────────────────────────────────────────

export const ChatMessageSchema = z.object({
  role: z.enum(['system', 'user', 'assistant']),
  content: z.string(),
});

export const ChatRequestSchema = z.object({
  messages: z.array(ChatMessageSchema).min(1),
  model: z.string().optional(),
  timezone: z.string().optional(),
  first_name: z.string().optional(),
});

// ─── Devices ────────────────────────────────────────────────────────

export const RegisterDeviceSchema = z.object({
  name: z.string().min(1).max(100),
  vendor_id: z.string().uuid().optional(),
  regenerate_token: z.boolean().optional(),
});

// ─── Sensor Data ────────────────────────────────────────────────────

export const SensorDataSchema = z.object({
  device_id: z.string().uuid(),
  sensor_type: z.enum(['barcode', 'camera', 'lidar', 'motion', 'beacon']),
  data: z.record(z.any()),
});

// ─── Nutrition ──────────────────────────────────────────────────────

export const NutritionLookupSchema = z.object({
  upc: z.string().regex(/^\d{6,14}$/, 'UPC must be 6-14 digits'),
});

// ─── Inbox Cards ────────────────────────────────────────────────────

export const PushCardSchema = z.object({
  device_id: z.string().uuid(),
  card_type: z.enum(['decision', 'task', 'info']),
  title: z.string().min(1).max(200),
  body: z.string().max(500).optional(),
});

export const RespondCardSchema = z.object({
  response: z.string().min(1).max(2000),
});

// ─── HITs ───────────────────────────────────────────────────────────

export const CreateHitSchema = z.object({
  recipient_name: z.string().min(1).max(50).optional(),
  task_description: z.string().min(1).max(500),
  agent_name: z.string().max(100).optional(),
  hit_type: z.enum(['photo', 'poll', 'availability', 'group_poll']).optional(),
  config: z.record(z.any()).optional(),
  group_id: z.string().max(100).optional(),
  sender_name: z.string().max(50).optional(),
  distribution_mode: z.enum(['individual', 'group', 'open']).optional(),
  participants: z.array(z.string().min(1).max(50)).max(50).optional(),
});

export const BulkDeleteHitsSchema = z.object({
  ids: z.array(z.string().min(1).max(20)).min(1).max(50).optional(),
  older_than_days: z.number().int().min(1).max(365).optional(),
  status: z.enum(['pending', 'in_progress', 'completed', 'expired']).optional(),
}).refine(
  (data) => data.ids || data.older_than_days,
  { message: 'Must provide either ids or older_than_days' }
);

export const HitResponseSchema = z.object({
  respondent_name: z.string().min(1).max(50),
  response_data: z.record(z.any()),
});

// ─── Image Analysis ─────────────────────────────────────────────────

export const AnalyzeRequestSchema = z.object({
  image_url: z.string().url().optional(),
  prompt: z.string().min(1),
});
