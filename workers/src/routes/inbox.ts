import type { Context } from 'hono';
import { PushCardSchema, RespondCardSchema, type Env, type InboxCard } from '../types';

export const getInbox = async (c: Context<{ Bindings: Env }>) => {
  const deviceId = c.req.param('device_id');

  try {
    const result = await c.env.DB.prepare(
      'SELECT * FROM inbox_cards WHERE device_id = ? AND status = ? ORDER BY created_at DESC'
    )
      .bind(deviceId, 'pending')
      .all<InboxCard>();

    return c.json({
      cards: result.results,
      count: result.results.length,
    }, 200);
  } catch (error) {
    console.error('Failed to fetch inbox:', error);
    return c.json({ error: 'Failed to fetch inbox' }, 500);
  }
};

export const pushCard = async (c: Context<{ Bindings: Env }>) => {
  const body = await c.req.json();
  const validated = PushCardSchema.safeParse(body);

  if (!validated.success) {
    return c.json({ error: 'Invalid request body', issues: validated.error.issues }, 400);
  }

  const { device_id, card_type, title, body: cardBody } = validated.data;
  const cardId = crypto.randomUUID();
  const now = new Date().toISOString();

  try {
    await c.env.DB.prepare(
      'INSERT INTO inbox_cards (id, device_id, card_type, title, body, status, created_at) VALUES (?, ?, ?, ?, ?, ?, ?)'
    )
      .bind(cardId, device_id, card_type, title, cardBody || null, 'pending', now)
      .run();

    return c.json({
      id: cardId,
      device_id,
      card_type,
      title,
      body: cardBody || null,
      response: null,
      status: 'pending',
      created_at: now,
      responded_at: null,
    }, 201);
  } catch (error) {
    console.error('Failed to push card:', error);
    return c.json({ error: 'Failed to push card' }, 500);
  }
};

export const respondToCard = async (c: Context<{ Bindings: Env }>) => {
  const cardId = c.req.param('card_id');
  const body = await c.req.json();
  const validated = RespondCardSchema.safeParse(body);

  if (!validated.success) {
    return c.json({ error: 'Invalid request body', issues: validated.error.issues }, 400);
  }

  const { response } = validated.data;
  const now = new Date().toISOString();

  try {
    await c.env.DB.prepare(
      'UPDATE inbox_cards SET response = ?, status = ?, responded_at = ? WHERE id = ?'
    )
      .bind(response, 'responded', now, cardId)
      .run();

    const card = await c.env.DB.prepare('SELECT * FROM inbox_cards WHERE id = ?')
      .bind(cardId)
      .first<InboxCard>();

    if (!card) {
      return c.json({ error: 'Card not found' }, 404);
    }

    return c.json(card, 200);
  } catch (error) {
    console.error('Failed to respond to card:', error);
    return c.json({ error: 'Failed to respond to card' }, 500);
  }
};
