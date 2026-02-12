import type { Context } from 'hono';
import { CreateHitSchema, type Env, type Hit, type HitPhoto } from '../types';

// Default sender for CLI/API-created HITs
const DEFAULT_SENDER = 'M. Silverman';

/**
 * Generate an 8-char URL-safe short ID
 */
function generateShortId(): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  const bytes = new Uint8Array(8);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => chars[b % chars.length]).join('');
}

/**
 * POST /api/hits — Create a new HIT
 */
export async function createHit(c: Context<{ Bindings: Env }>) {
  const body = await c.req.json().catch(() => null);
  if (!body) {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const validated = CreateHitSchema.safeParse(body);
  if (!validated.success) {
    return c.json({ error: 'Invalid request body', issues: validated.error.issues }, 400);
  }

  const { recipient_name, task_description, agent_name } = validated.data;
  const id = generateShortId();
  const now = new Date().toISOString();

  // Get device_id from auth header if present
  const deviceId = c.req.header('X-Device-ID') || null;

  try {
    await c.env.DB.prepare(
      `INSERT INTO hits (id, sender_name, recipient_name, task_description, agent_name, status, photo_count, created_at, device_id)
       VALUES (?, ?, ?, ?, ?, 'pending', 0, ?, ?)`
    )
      .bind(id, DEFAULT_SENDER, recipient_name, task_description, agent_name || null, now, deviceId)
      .run();

    return c.json(
      {
        id,
        url: `https://robo.app/hit/${id}`,
        sender_name: DEFAULT_SENDER,
        recipient_name,
        task_description,
        agent_name: agent_name || null,
        status: 'pending',
        photo_count: 0,
        created_at: now,
      },
      201
    );
  } catch (error) {
    console.error('Failed to create HIT:', error);
    return c.json({ error: 'Failed to create HIT' }, 500);
  }
}

/**
 * GET /api/hits/:id — Get HIT details (public, no auth required)
 */
export async function getHit(c: Context<{ Bindings: Env }>) {
  const id = c.req.param('id');

  try {
    const hit = await c.env.DB.prepare('SELECT * FROM hits WHERE id = ?').bind(id).first<Hit>();

    if (!hit) {
      return c.json({ error: 'HIT not found' }, 404);
    }

    // If first access and still pending, mark as started
    if (hit.status === 'pending' && !hit.started_at) {
      const now = new Date().toISOString();
      await c.env.DB.prepare("UPDATE hits SET started_at = ?, status = 'in_progress' WHERE id = ? AND started_at IS NULL")
        .bind(now, id)
        .run();
      hit.started_at = now;
      hit.status = 'in_progress';
    }

    return c.json(hit, 200);
  } catch (error) {
    console.error('Failed to fetch HIT:', error);
    return c.json({ error: 'Failed to fetch HIT' }, 500);
  }
}

/**
 * POST /api/hits/:id/upload — Upload a photo directly to R2 via Workers binding
 * Accepts binary body (image/jpeg) or multipart form data
 */
export async function uploadHitPhoto(c: Context<{ Bindings: Env }>) {
  const hitId = c.req.param('id');

  try {
    // Verify HIT exists and is not completed/expired
    const hit = await c.env.DB.prepare('SELECT * FROM hits WHERE id = ?').bind(hitId).first<Hit>();

    if (!hit) {
      return c.json({ error: 'HIT not found' }, 404);
    }

    if (hit.status === 'completed' || hit.status === 'expired') {
      return c.json({ error: `HIT is ${hit.status}` }, 400);
    }

    // Get photo data from request body
    const contentType = c.req.header('Content-Type') || '';
    let photoBlob: ArrayBuffer;

    if (contentType.includes('multipart/form-data')) {
      const formData = await c.req.formData();
      const file = formData.get('photo') as File | null;
      if (!file) {
        return c.json({ error: 'No photo file in form data' }, 400);
      }
      photoBlob = await file.arrayBuffer();
    } else {
      // Accept raw binary body
      photoBlob = await c.req.arrayBuffer();
    }

    if (!photoBlob || photoBlob.byteLength === 0) {
      return c.json({ error: 'Empty photo data' }, 400);
    }

    // Limit to 10MB
    if (photoBlob.byteLength > 10 * 1024 * 1024) {
      return c.json({ error: 'Photo too large (max 10MB)' }, 400);
    }

    const photoId = crypto.randomUUID();
    const r2Key = `hits/${hitId}/${photoId}.jpg`;

    // Upload to R2 via binding
    await c.env.BUCKET.put(r2Key, photoBlob, {
      httpMetadata: { contentType: 'image/jpeg' },
      customMetadata: { hit_id: hitId, uploaded_by: 'web' },
    });

    // Record in D1
    const now = new Date().toISOString();
    await c.env.DB.prepare(
      'INSERT INTO hit_photos (id, hit_id, r2_key, file_size, uploaded_at) VALUES (?, ?, ?, ?, ?)'
    )
      .bind(photoId, hitId, r2Key, photoBlob.byteLength, now)
      .run();

    // Increment photo count
    await c.env.DB.prepare('UPDATE hits SET photo_count = photo_count + 1 WHERE id = ?')
      .bind(hitId)
      .run();

    return c.json(
      {
        photo_id: photoId,
        r2_key: r2Key,
        file_size: photoBlob.byteLength,
      },
      201
    );
  } catch (error) {
    console.error('Failed to upload photo:', error);
    return c.json({ error: 'Failed to upload photo' }, 500);
  }
}

/**
 * PATCH /api/hits/:id/complete — Mark HIT as completed
 */
export async function completeHit(c: Context<{ Bindings: Env }>) {
  const id = c.req.param('id');

  try {
    const hit = await c.env.DB.prepare('SELECT * FROM hits WHERE id = ?').bind(id).first<Hit>();

    if (!hit) {
      return c.json({ error: 'HIT not found' }, 404);
    }

    if (hit.status === 'completed') {
      return c.json({ error: 'HIT already completed' }, 400);
    }

    if (hit.status === 'expired') {
      return c.json({ error: 'HIT has expired' }, 400);
    }

    const now = new Date().toISOString();
    await c.env.DB.prepare("UPDATE hits SET status = 'completed', completed_at = ? WHERE id = ?")
      .bind(now, id)
      .run();

    return c.json(
      {
        id,
        status: 'completed',
        photo_count: hit.photo_count,
        completed_at: now,
      },
      200
    );
  } catch (error) {
    console.error('Failed to complete HIT:', error);
    return c.json({ error: 'Failed to complete HIT' }, 500);
  }
}

/**
 * GET /api/hits — List HITs for a sender device (auth required)
 */
export async function listHits(c: Context<{ Bindings: Env }>) {
  const deviceId = c.req.header('X-Device-ID');

  try {
    // If no device ID, return all HITs (for CLI/demo use)
    const query = deviceId
      ? 'SELECT * FROM hits WHERE device_id = ? ORDER BY created_at DESC LIMIT 50'
      : 'SELECT * FROM hits ORDER BY created_at DESC LIMIT 50';

    const result = deviceId
      ? await c.env.DB.prepare(query).bind(deviceId).all<Hit>()
      : await c.env.DB.prepare(query).all<Hit>();

    return c.json(
      {
        hits: result.results,
        count: result.results.length,
      },
      200
    );
  } catch (error) {
    console.error('Failed to list HITs:', error);
    return c.json({ error: 'Failed to list HITs' }, 500);
  }
}

/**
 * GET /api/hits/:id/photos — List photos for a HIT
 */
export async function listHitPhotos(c: Context<{ Bindings: Env }>) {
  const hitId = c.req.param('id');

  try {
    const hit = await c.env.DB.prepare('SELECT * FROM hits WHERE id = ?').bind(hitId).first<Hit>();

    if (!hit) {
      return c.json({ error: 'HIT not found' }, 404);
    }

    const result = await c.env.DB.prepare(
      'SELECT * FROM hit_photos WHERE hit_id = ? ORDER BY uploaded_at ASC'
    )
      .bind(hitId)
      .all<HitPhoto>();

    return c.json(
      {
        hit_id: hitId,
        photos: result.results,
        count: result.results.length,
      },
      200
    );
  } catch (error) {
    console.error('Failed to list HIT photos:', error);
    return c.json({ error: 'Failed to list HIT photos' }, 500);
  }
}
