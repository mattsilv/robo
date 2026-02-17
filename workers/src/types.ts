// Re-export shared types and schemas so existing imports still work
export type {
  Device,
  SensorData,
  NutritionLookupResponse,
  InboxCard,
  Hit,
  HitResponse,
  HitPhoto,
  HitStatus,
  DistributionMode,
  User,
  UserSettings,
  ChatMessage,
} from '@robo/shared';

export {
  HIT_DISTRIBUTION_MODES,
  RegisterDeviceSchema,
  SensorDataSchema,
  NutritionLookupSchema,
  PushCardSchema,
  RespondCardSchema,
  CreateHitSchema,
  BulkDeleteHitsSchema,
  HitResponseSchema,
  AnalyzeRequestSchema,
  ChatRequestSchema,
} from '@robo/shared';

// Cloudflare-specific bindings — NOT shared (platform-specific)
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
