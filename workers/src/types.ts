import { z } from 'zod';

// Cloudflare bindings
export type Env = {
  DB: D1Database;
  BUCKET: R2Bucket;
  ENVIRONMENT: string;
  NUTRITIONIX_APP_ID: string;
  NUTRITIONIX_APP_KEY: string;
  APNS_AUTH_KEY: string;
  APNS_KEY_ID: string;
  APNS_SANDBOX?: string;
  OPENROUTER_API_KEY: string;
  OPENROUTER_MODEL?: string;
};

// Nutrition lookup
export const NutritionLookupSchema = z.object({
  upc: z.string().regex(/^\d{6,14}$/, 'UPC must be 6-14 digits'),
});

export type NutritionLookupResponse = {
  found: boolean;
  food_name: string | null;
  brand_name: string | null;
  calories: number | null;
  protein: number | null;
  fat: number | null;
  carbs: number | null;
  fiber: number | null;
  sugars: number | null;
  sodium: number | null;
  serving_qty: number | null;
  serving_unit: string | null;
  serving_weight_grams: number | null;
  photo_thumb: string | null;
  photo_highres: string | null;
};

// Request schemas
export const RegisterDeviceSchema = z.object({
  name: z.string().min(1).max(100),
  vendor_id: z.string().uuid().optional(),
  regenerate_token: z.boolean().optional(),
});

export const SensorDataSchema = z.object({
  device_id: z.string().uuid(),
  sensor_type: z.enum(['barcode', 'camera', 'lidar', 'motion', 'beacon']),
  data: z.record(z.any()),
});

export const PushCardSchema = z.object({
  device_id: z.string().uuid(),
  card_type: z.enum(['decision', 'task', 'info']),
  title: z.string().min(1).max(200),
  body: z.string().max(500).optional(),
});

export const RespondCardSchema = z.object({
  response: z.string().min(1).max(2000),
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
  sensor_type: 'barcode' | 'camera' | 'lidar' | 'motion' | 'beacon';
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

// HIT Distribution Modes
export const HIT_DISTRIBUTION_MODES = {
  individual: {
    key: 'individual' as const,
    label: 'Individual Links',
    description: 'Separate link per person, name baked in',
    requires_participants: true,
    creates_multiple_hits: true,
  },
  group: {
    key: 'group' as const,
    label: 'Group Link',
    description: 'Single link, pick your name from dropdown',
    requires_participants: true,
    creates_multiple_hits: false,
  },
  open: {
    key: 'open' as const,
    label: 'Open Link',
    description: 'Single link, type your name',
    requires_participants: false,
    creates_multiple_hits: false,
  },
} as const;

export type DistributionMode = keyof typeof HIT_DISTRIBUTION_MODES;

// HIT (Human Intelligence Task) schemas
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

export const HitResponseSchema = z.object({
  respondent_name: z.string().min(1).max(50),
  response_data: z.record(z.any()),
});

export type HitStatus = 'pending' | 'in_progress' | 'completed' | 'expired';

export type Hit = {
  id: string;
  sender_name: string;
  recipient_name: string;
  task_description: string;
  agent_name: string | null;
  status: HitStatus;
  photo_count: number;
  created_at: string;
  started_at: string | null;
  completed_at: string | null;
  device_id: string | null;
  hit_type: string | null;
  config: string | null;
  group_id: string | null;
};

export type HitResponse = {
  id: string;
  hit_id: string;
  respondent_name: string;
  response_data: string;
  created_at: string;
};

export type HitPhoto = {
  id: string;
  hit_id: string;
  r2_key: string;
  file_size: number | null;
  uploaded_at: string;
};
