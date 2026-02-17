/**
 * Shared types used across Workers, web app, and (future) Android.
 * Platform-specific types (e.g., Cloudflare Env bindings) stay in their respective packages.
 */

// ─── Users ──────────────────────────────────────────────────────────

export interface User {
  id: string;
  apple_sub: string | null;
  google_sub: string | null;
  email: string | null;
  first_name: string | null;
  created_at: string;
  updated_at: string;
}

export interface UserSettings {
  first_name: string | null;
  mcp_tokens: { device_id: string; token: string; label: string }[];
}

// ─── Devices ────────────────────────────────────────────────────────

export interface Device {
  id: string;
  user_id: string | null;
  name: string;
  vendor_id: string | null;
  mcp_token: string;
  registered_at: string;
  last_seen_at: string | null;
}

// ─── Sensor Data ────────────────────────────────────────────────────

export type SensorType = 'barcode' | 'camera' | 'lidar' | 'motion' | 'beacon';

export interface SensorData {
  id: number;
  device_id: string;
  sensor_type: SensorType;
  data: Record<string, unknown>;
  captured_at: string;
}

// ─── Nutrition ──────────────────────────────────────────────────────

export interface NutritionLookupResponse {
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
}

// ─── Inbox Cards ────────────────────────────────────────────────────

export type CardType = 'decision' | 'task' | 'info';
export type CardStatus = 'pending' | 'responded' | 'expired';

export interface InboxCard {
  id: string;
  device_id: string;
  card_type: CardType;
  title: string;
  body: string | null;
  response: string | null;
  status: CardStatus;
  created_at: string;
  responded_at: string | null;
}

// ─── HITs (Human Intelligence Tasks) ────────────────────────────────

export type HitStatus = 'pending' | 'in_progress' | 'completed' | 'expired';
export type HitType = 'photo' | 'poll' | 'availability' | 'group_poll';

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

export interface Hit {
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
}

export interface HitResponse {
  id: string;
  hit_id: string;
  respondent_name: string;
  response_data: string;
  created_at: string;
}

export interface HitPhoto {
  id: string;
  hit_id: string;
  r2_key: string;
  file_size: number | null;
  uploaded_at: string;
}

// ─── Chat ───────────────────────────────────────────────────────────

export interface ChatMessage {
  role: 'system' | 'user' | 'assistant';
  content: string;
}
