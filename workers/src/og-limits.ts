// OG Image Text Safety — single source of truth
// DB limits: generous, for storage
// Visual tiers: the image renderer picks tier based on actual text length

export const OG_DB = {
  recipientName: 100,
  senderName: 100,
  taskDescription: 500,
  agentName: 100,
} as const;

// Visual tier breakpoints (chars where we switch font sizes)
export const OG_TIERS = {
  recipientName: { ideal: 16, max: 30 }, // <=16: 62px font, 17-30: 44px font, >30: truncate at 30
  senderName: { ideal: 16, max: 30 }, // <=16: 40px font, 17-30: 30px font, >30: truncate at 30
  taskDescription: { ideal: 45, max: 80 }, // <=45: 1 line 24px, 46-80: 2 lines 20px, >80: truncate at 80
  agentName: { ideal: 25, max: 40 }, // <=25: 16px, 26-40: 13px, >40: truncate at 40
} as const;

export const OG_SIZE = { width: 1200, height: 630 } as const;

// Safety truncation — always applied before rendering
export function ogSafe(
  text: string,
  field: keyof typeof OG_TIERS
): string {
  const { max } = OG_TIERS[field];
  if (text.length <= max) return text;
  return text.slice(0, max - 1) + '\u2026';
}

// Tier selection — returns 'ideal' or 'compact'
export function ogTier(
  text: string,
  field: keyof typeof OG_TIERS
): 'ideal' | 'compact' {
  return text.length <= OG_TIERS[field].ideal ? 'ideal' : 'compact';
}
