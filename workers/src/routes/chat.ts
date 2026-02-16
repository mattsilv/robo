import type { Context } from 'hono';
import type { Env } from '../types';
import { z } from 'zod';

const ChatRequestSchema = z.object({
  messages: z.array(z.object({
    role: z.enum(['system', 'user', 'assistant']),
    content: z.string(),
  })).min(1),
  model: z.string().optional(),
});

const DEFAULT_MODEL = 'google/gemini-2.5-flash-lite-preview-09-2025';

export async function chatProxy(c: Context<{ Bindings: Env }>): Promise<Response> {
  const body = await c.req.json();
  const parsed = ChatRequestSchema.safeParse(body);

  if (!parsed.success) {
    return c.json({ error: 'Invalid request', details: parsed.error.flatten() }, 400);
  }

  const model = parsed.data.model || c.env.OPENROUTER_MODEL || DEFAULT_MODEL;

  const response = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${c.env.OPENROUTER_API_KEY}`,
    },
    body: JSON.stringify({
      model,
      messages: parsed.data.messages,
      stream: true,
    }),
  });

  if (!response.ok || !response.body) {
    const text = await response.text();
    return c.json({ error: 'OpenRouter request failed', status: response.status, details: text }, 502);
  }

  // Pass through SSE stream directly — zero buffering
  return new Response(response.body, {
    headers: {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive',
    },
  });
}
