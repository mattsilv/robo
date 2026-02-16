import type { Context } from 'hono';
import { CreateHitSchema, HitResponseSchema, type Env, type Hit, type HitPhoto, type HitResponse } from '../types';
import { sendPushNotification } from '../services/apns';

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

  const { recipient_name, task_description, agent_name, hit_type, config, group_id, sender_name } = validated.data;
  const id = generateShortId();
  const now = new Date().toISOString();

  // Get device_id from auth header if present
  const deviceId = c.req.header('X-Device-ID') || null;
  const resolvedSender = sender_name || DEFAULT_SENDER;

  try {
    await c.env.DB.prepare(
      `INSERT INTO hits (id, sender_name, recipient_name, task_description, agent_name, status, photo_count, created_at, device_id, hit_type, config, group_id)
       VALUES (?, ?, ?, ?, ?, 'pending', 0, ?, ?, ?, ?, ?)`
    )
      .bind(id, resolvedSender, recipient_name, task_description, agent_name || null, now, deviceId, hit_type || 'photo', config ? JSON.stringify(config) : null, group_id || null)
      .run();

    return c.json(
      {
        id,
        url: `https://robo.app/hit/${id}`,
        sender_name: resolvedSender,
        recipient_name,
        task_description,
        agent_name: agent_name || null,
        status: 'pending',
        photo_count: 0,
        created_at: now,
        group_id: group_id || null,
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

    // Send push notification to the HIT creator (fire-and-forget)
    if (hit.device_id) {
      c.executionCtx.waitUntil(
        (async () => {
          try {
            const device = await c.env.DB.prepare(
              'SELECT apns_token FROM devices WHERE id = ?'
            ).bind(hit.device_id).first<{ apns_token: string | null }>();

            if (device?.apns_token) {
              const body = hit.photo_count > 0
                ? `${hit.recipient_name} sent ${hit.photo_count} photo${hit.photo_count === 1 ? '' : 's'}`
                : `${hit.recipient_name} completed your request`;

              await sendPushNotification(c.env, device.apns_token, {
                title: 'HIT Completed',
                body,
              }, { hit_id: id });
            }
          } catch (err) {
            console.error('Push notification failed:', err);
          }
        })()
      );
    }

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
  const deviceId = c.req.header('X-Device-ID')!; // guaranteed by deviceAuth middleware
  const groupId = c.req.query('group_id');

  try {
    let result;
    if (groupId) {
      // Filter by group_id, scoped to authenticated device
      result = await c.env.DB.prepare(
        'SELECT h.*, (SELECT COUNT(*) FROM hit_responses WHERE hit_id = h.id) as response_count FROM hits h WHERE h.group_id = ? AND h.device_id = ? ORDER BY h.created_at DESC LIMIT 50'
      ).bind(groupId, deviceId).all<Hit & { response_count: number }>();
    } else {
      result = await c.env.DB.prepare(
        'SELECT h.*, (SELECT COUNT(*) FROM hit_responses WHERE hit_id = h.id) as response_count FROM hits h WHERE h.device_id = ? ORDER BY h.created_at DESC LIMIT 50'
      ).bind(deviceId).all<Hit & { response_count: number }>();
    }

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

/**
 * POST /api/hits/:id/respond — Submit a structured response to a HIT
 */
export async function respondToHit(c: Context<{ Bindings: Env }>) {
  const hitId = c.req.param('id');

  const body = await c.req.json().catch(() => null);
  if (!body) {
    return c.json({ error: 'Invalid JSON body' }, 400);
  }

  const validated = HitResponseSchema.safeParse(body);
  if (!validated.success) {
    return c.json({ error: 'Invalid request body', issues: validated.error.issues }, 400);
  }

  const { respondent_name, response_data } = validated.data;

  try {
    const hit = await c.env.DB.prepare('SELECT * FROM hits WHERE id = ?').bind(hitId).first<Hit>();

    if (!hit) {
      return c.json({ error: 'HIT not found' }, 404);
    }

    if (hit.status === 'completed' || hit.status === 'expired') {
      return c.json({ error: `HIT is ${hit.status}` }, 400);
    }

    // For group_poll and availability: validate respondent is in participant list and hasn't already responded
    if (hit.hit_type === 'group_poll' || hit.hit_type === 'availability') {
      const config = hit.config ? JSON.parse(hit.config) : {};
      const participants: string[] = config.participants || [];
      if (participants.length > 0 && !participants.includes(respondent_name)) {
        return c.json({ error: 'Name not in participant list' }, 400);
      }

      // Check for duplicate response
      const existing = await c.env.DB.prepare(
        'SELECT id FROM hit_responses WHERE hit_id = ? AND respondent_name = ?'
      ).bind(hitId, respondent_name).first();
      if (existing) {
        return c.json({ error: 'You have already responded' }, 409);
      }
    }

    const responseId = crypto.randomUUID();
    const now = new Date().toISOString();

    await c.env.DB.prepare(
      'INSERT INTO hit_responses (id, hit_id, respondent_name, response_data, created_at) VALUES (?, ?, ?, ?, ?)'
    )
      .bind(responseId, hitId, respondent_name, JSON.stringify(response_data), now)
      .run();

    // Mark HIT as in_progress if still pending
    if (hit.status === 'pending') {
      await c.env.DB.prepare("UPDATE hits SET status = 'in_progress', started_at = ? WHERE id = ? AND status = 'pending'")
        .bind(now, hitId)
        .run();
    }

    // Send push notification per response (fire-and-forget)
    if (hit.device_id) {
      c.executionCtx.waitUntil(
        (async () => {
          try {
            const device = await c.env.DB.prepare(
              'SELECT apns_token FROM devices WHERE id = ?'
            ).bind(hit.device_id).first<{ apns_token: string | null }>();

            if (device?.apns_token) {
              const isGroupPoll = hit.hit_type === 'group_poll';
              const isAvailability = hit.hit_type === 'availability';
              const body = isGroupPoll
                ? `${respondent_name} voted in your group poll`
                : isAvailability
                ? `${respondent_name} responded to your availability poll`
                : `${respondent_name} responded to your request`;

              await sendPushNotification(c.env, device.apns_token, {
                title: isGroupPoll ? 'New Group Poll Vote' : isAvailability ? 'New Availability Response' : 'HIT Response',
                body,
              }, { hit_id: hitId });
            }
          } catch (err) {
            console.error('Push notification failed:', err);
          }
        })()
      );
    }

    return c.json(
      {
        id: responseId,
        hit_id: hitId,
        respondent_name,
        response_data,
        created_at: now,
      },
      201
    );
  } catch (error) {
    console.error('Failed to submit HIT response:', error);
    return c.json({ error: 'Failed to submit response' }, 500);
  }
}

/**
 * DELETE /api/hits/:id — Delete a HIT and its responses/photos
 */
export async function deleteHit(c: Context<{ Bindings: Env }>) {
  const hitId = c.req.param('id');
  const deviceId = c.req.header('X-Device-ID')!; // guaranteed by deviceAuth middleware

  try {
    const hit = await c.env.DB.prepare('SELECT * FROM hits WHERE id = ?').bind(hitId).first<Hit>();

    if (!hit) {
      return c.json({ error: 'HIT not found' }, 404);
    }

    if (hit.device_id !== deviceId) {
      return c.json({ error: 'Forbidden' }, 403);
    }

    // Delete associated photos from R2
    const photos = await c.env.DB.prepare('SELECT r2_key FROM hit_photos WHERE hit_id = ?')
      .bind(hitId)
      .all<{ r2_key: string }>();

    for (const photo of photos.results) {
      await c.env.BUCKET.delete(photo.r2_key).catch(() => {});
    }

    // Delete in order: responses, photos, then hit
    await c.env.DB.prepare('DELETE FROM hit_responses WHERE hit_id = ?').bind(hitId).run();
    await c.env.DB.prepare('DELETE FROM hit_photos WHERE hit_id = ?').bind(hitId).run();
    await c.env.DB.prepare('DELETE FROM hits WHERE id = ?').bind(hitId).run();

    return c.json({ deleted: true, id: hitId }, 200);
  } catch (error) {
    console.error('Failed to delete HIT:', error);
    return c.json({ error: 'Failed to delete HIT' }, 500);
  }
}

/**
 * GET /api/hits/:id/responses — List structured responses for a HIT
 */
export async function listHitResponses(c: Context<{ Bindings: Env }>) {
  const hitId = c.req.param('id');

  try {
    const hit = await c.env.DB.prepare('SELECT * FROM hits WHERE id = ?').bind(hitId).first<Hit>();

    if (!hit) {
      return c.json({ error: 'HIT not found' }, 404);
    }

    const result = await c.env.DB.prepare(
      'SELECT * FROM hit_responses WHERE hit_id = ? ORDER BY created_at ASC'
    )
      .bind(hitId)
      .all<HitResponse>();

    // Parse response_data JSON for each response
    const responses = result.results.map((r) => ({
      ...r,
      response_data: JSON.parse(r.response_data),
    }));

    return c.json(
      {
        hit_id: hitId,
        responses,
        count: responses.length,
      },
      200
    );
  } catch (error) {
    console.error('Failed to list HIT responses:', error);
    return c.json({ error: 'Failed to list HIT responses' }, 500);
  }
}
