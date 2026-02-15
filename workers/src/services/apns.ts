import type { Env } from '../types';

const APNS_PRODUCTION_HOST = 'https://api.push.apple.com';
const APNS_SANDBOX_HOST = 'https://api.sandbox.push.apple.com';
const TEAM_ID = 'R3Z5CY34Q5';
const BUNDLE_ID = 'com.silv.Robo';

// Cache JWT for reuse (valid for ~1 hour, we refresh every 50 min)
let cachedJWT: { token: string; expiresAt: number } | null = null;

/**
 * Import a PEM-encoded ES256 private key (APNs p8 format) for signing.
 */
async function importPrivateKey(pem: string): Promise<CryptoKey> {
  // Strip PEM headers and whitespace
  const stripped = pem
    .replace(/-----BEGIN PRIVATE KEY-----/, '')
    .replace(/-----END PRIVATE KEY-----/, '')
    .replace(/\s/g, '');

  const binaryDer = Uint8Array.from(atob(stripped), (c) => c.charCodeAt(0));

  return crypto.subtle.importKey(
    'pkcs8',
    binaryDer,
    { name: 'ECDSA', namedCurve: 'P-256' },
    false,
    ['sign']
  );
}

/**
 * Base64url encode (no padding).
 */
function base64url(data: Uint8Array | string): string {
  const str = typeof data === 'string' ? data : String.fromCharCode(...data);
  return btoa(str).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

/**
 * Create a signed JWT for APNs authentication.
 */
async function createAPNsJWT(env: Env): Promise<string> {
  const now = Math.floor(Date.now() / 1000);

  // Return cached JWT if still valid (50 min window)
  if (cachedJWT && cachedJWT.expiresAt > now) {
    return cachedJWT.token;
  }

  const header = base64url(JSON.stringify({ alg: 'ES256', kid: env.APNS_KEY_ID }));
  const payload = base64url(JSON.stringify({ iss: TEAM_ID, iat: now }));
  const signingInput = `${header}.${payload}`;

  const key = await importPrivateKey(env.APNS_AUTH_KEY);
  const signature = await crypto.subtle.sign(
    { name: 'ECDSA', hash: 'SHA-256' },
    key,
    new TextEncoder().encode(signingInput)
  );

  // Convert DER signature to raw r||s format expected by JWT
  const sig = derToRaw(new Uint8Array(signature));
  const token = `${signingInput}.${base64url(sig)}`;

  cachedJWT = { token, expiresAt: now + 3000 }; // 50 min
  return token;
}

/**
 * Convert DER-encoded ECDSA signature to raw r||s (64 bytes).
 * crypto.subtle may return DER format on some runtimes.
 */
function derToRaw(der: Uint8Array): Uint8Array {
  // If already 64 bytes, it's raw format
  if (der.length === 64) return der;

  // DER: 0x30 <len> 0x02 <rLen> <r> 0x02 <sLen> <s>
  if (der[0] !== 0x30) return der; // Not DER, return as-is

  let offset = 2;
  // Skip sequence length byte(s)

  // Read r
  if (der[offset] !== 0x02) return der;
  offset++;
  const rLen = der[offset++];
  const r = der.slice(offset, offset + rLen);
  offset += rLen;

  // Read s
  if (der[offset] !== 0x02) return der;
  offset++;
  const sLen = der[offset++];
  const s = der.slice(offset, offset + sLen);

  // Pad/trim to 32 bytes each
  const raw = new Uint8Array(64);
  raw.set(r.length > 32 ? r.slice(r.length - 32) : r, 32 - Math.min(r.length, 32));
  raw.set(s.length > 32 ? s.slice(s.length - 32) : s, 64 - Math.min(s.length, 32));
  return raw;
}

/**
 * Send a push notification via APNs HTTP/2.
 */
export async function sendPushNotification(
  env: Env,
  deviceToken: string,
  alert: { title: string; body: string },
  data?: Record<string, string>
): Promise<{ success: boolean; status?: number; reason?: string }> {
  try {
    const jwt = await createAPNsJWT(env);

    const payload = {
      aps: {
        alert,
        sound: 'default',
      },
      ...data,
    };

    // Use sandbox for development builds, production for App Store
    const host = env.APNS_SANDBOX === 'true' ? APNS_SANDBOX_HOST : APNS_PRODUCTION_HOST;

    const response = await fetch(`${host}/3/device/${deviceToken}`, {
      method: 'POST',
      headers: {
        'authorization': `bearer ${jwt}`,
        'apns-topic': BUNDLE_ID,
        'apns-push-type': 'alert',
        'apns-priority': '10',
        'content-type': 'application/json',
      },
      body: JSON.stringify(payload),
    });

    if (response.ok) {
      return { success: true, status: response.status };
    }

    const errorBody = await response.text().catch(() => '');
    console.error(`APNs push failed: ${response.status} ${errorBody}`);
    return { success: false, status: response.status, reason: errorBody };
  } catch (error) {
    console.error('APNs push error:', error);
    return { success: false, reason: String(error) };
  }
}
