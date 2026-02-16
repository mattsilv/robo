import type { Context } from 'hono';
import type { Env } from '../types';
import { z } from 'zod';

const ChatRequestSchema = z.object({
  messages: z.array(z.object({
    role: z.enum(['system', 'user', 'assistant']),
    content: z.string(),
  })).min(1),
  model: z.string().optional(),
  timezone: z.string().optional(),
});

const DEFAULT_MODEL = 'google/gemini-2.5-flash';

const tools = [
  {
    type: 'function' as const,
    function: {
      name: 'create_availability_poll',
      description: 'Creates a group availability poll with shareable HIT links for each participant. Use IMMEDIATELY when the user wants to plan something with friends, schedule a group event, or find a time that works for everyone. You know the current date — calculate specific dates yourself (e.g., if user says "weekends next month", compute the actual YYYY-MM-DD dates). Do NOT ask the user for dates in any specific format — figure it out from context.',
      parameters: {
        type: 'object',
        properties: {
          eventTitle: { type: 'string', description: 'Title of the event (e.g., "Ski Trip")' },
          participants: { type: 'string', description: 'Comma-separated participant names (e.g., "Sam, Vince, Greg")' },
          dateOptions: { type: 'string', description: 'Comma-separated dates in YYYY-MM-DD format. YOU must compute these from context (e.g., "weekends in March 2026" → "2026-03-07,2026-03-08,2026-03-14,2026-03-15,...")' },
          timeSlots: { type: 'string', description: 'Comma-separated time slots (e.g., "Morning, Afternoon, Evening"). Default to "Morning, Afternoon, Evening" if not specified.' },
        },
        required: ['eventTitle', 'participants'],
      },
    },
  },
  {
    type: 'function' as const,
    function: {
      name: 'scan_room',
      description: 'Launches the LiDAR room scanner to scan and measure a room. Use when the user asks to scan a room or measure a space.',
      parameters: {
        type: 'object',
        properties: {
          roomName: { type: 'string', description: 'Name for the room scan' },
        },
      },
    },
  },
  {
    type: 'function' as const,
    function: {
      name: 'scan_barcode',
      description: 'Launches the barcode scanner. Use when the user asks to scan a barcode or QR code.',
      parameters: {
        type: 'object',
        properties: {
          productDescription: { type: 'string', description: 'Optional description of what to scan' },
        },
      },
    },
  },
  {
    type: 'function' as const,
    function: {
      name: 'take_photo',
      description: 'Launches the camera to capture photos. Use when the user asks to take or capture photos.',
      parameters: {
        type: 'object',
        properties: {
          subject: { type: 'string', description: 'What to photograph' },
        },
      },
    },
  },
];

/**
 * Generate an 8-char URL-safe short ID for HITs
 */
function generateShortId(): string {
  const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
  const bytes = new Uint8Array(8);
  crypto.getRandomValues(bytes);
  return Array.from(bytes, (b) => chars[b % chars.length]).join('');
}

interface HitResult {
  name: string;
  url: string;
  hitId: string;
}

/**
 * Execute the create_availability_poll tool call by creating HITs in D1
 */
async function executeCreateAvailabilityPoll(
  c: Context<{ Bindings: Env }>,
  args: { eventTitle: string; participants: string; dateOptions?: string; timeSlots?: string },
  deviceId: string
): Promise<{ text: string; hits: HitResult[] }> {
  const db = c.env.DB;
  const participants = args.participants.split(',').map((p: string) => p.trim()).filter(Boolean);
  const hitId = generateShortId();
  const now = new Date().toISOString();

  const device = await db.prepare('SELECT name FROM devices WHERE id = ?').bind(deviceId).first<{ name: string | null }>();
  const senderName = device?.name || 'Someone';

  const config = JSON.stringify({
    title: args.eventTitle,
    participants,
    date_options: args.dateOptions?.split(',').map((d: string) => d.trim()) || [],
    time_slots: args.timeSlots?.split(',').map((t: string) => t.trim()) || ['Morning', 'Afternoon', 'Evening'],
  });

  await db.prepare(`
    INSERT INTO hits (id, sender_name, recipient_name, task_description, status, photo_count, created_at, device_id, hit_type, config, group_id)
    VALUES (?, ?, ?, ?, 'pending', 0, ?, ?, 'availability', ?, ?)
  `).bind(
    hitId,
    senderName,
    participants.join(', '),
    `When are you free for: ${args.eventTitle}?`,
    now,
    deviceId,
    config,
    crypto.randomUUID()
  ).run();

  const url = `https://robo.app/hit/${hitId}`;
  return {
    text: `Created availability poll "${args.eventTitle}" for ${participants.length} people: ${url}`,
    hits: [{ name: args.eventTitle, url, hitId }],
  };
}

/**
 * Convert content string to SSE response format
 */
function contentToSSE(content: string, hitResults?: HitResult[]): Response {
  const encoder = new TextEncoder();
  const stream = new ReadableStream({
    start(controller) {
      controller.enqueue(encoder.encode(`data: ${JSON.stringify({ choices: [{ delta: { content } }] })}\n\n`));
      if (hitResults && hitResults.length > 0) {
        controller.enqueue(encoder.encode(`data: ${JSON.stringify({ hit_results: hitResults })}\n\n`));
      }
      controller.enqueue(encoder.encode('data: [DONE]\n\n'));
      controller.close();
    },
  });

  return new Response(stream, {
    headers: { 'Content-Type': 'text/event-stream', 'Cache-Control': 'no-cache' },
  });
}

export async function chatProxy(c: Context<{ Bindings: Env }>): Promise<Response> {
  const body = await c.req.json();
  const parsed = ChatRequestSchema.safeParse(body);

  if (!parsed.success) {
    return c.json({ error: 'Invalid request', details: parsed.error.flatten() }, 400);
  }

  const model = parsed.data.model || c.env.OPENROUTER_MODEL || DEFAULT_MODEL;
  const deviceId = c.req.header('X-Device-ID') || '';

  // Inject timezone into system message if provided
  const messages = parsed.data.messages.map((msg) => {
    if (msg.role === 'system' && parsed.data.timezone) {
      return { ...msg, content: `${msg.content}\n\nUser's timezone: ${parsed.data.timezone}` };
    }
    return msg;
  });

  // Non-streaming request to detect tool calls
  const initialResponse = await fetch('https://openrouter.ai/api/v1/chat/completions', {
    method: 'POST',
    headers: {
      'Content-Type': 'application/json',
      'Authorization': `Bearer ${c.env.OPENROUTER_API_KEY}`,
    },
    body: JSON.stringify({
      model,
      messages,
      tools,
      tool_choice: 'auto',
      reasoning: { effort: 'low' },
    }),
  });

  if (!initialResponse.ok) {
    const text = await initialResponse.text();
    return c.json({ error: 'OpenRouter request failed', status: initialResponse.status, details: text }, 502);
  }

  const result = await initialResponse.json() as any;
  const choice = result.choices?.[0];

  if (choice?.message?.tool_calls?.length > 0) {
    // Handle tool calls
    const toolResults = [];
    let allHitResults: HitResult[] = [];
    for (const toolCall of choice.message.tool_calls) {
      const args = JSON.parse(toolCall.function.arguments);
      let toolResultText: string;

      if (toolCall.function.name === 'create_availability_poll') {
        try {
          const result = await executeCreateAvailabilityPoll(c, args, deviceId);
          toolResultText = result.text;
          allHitResults = allHitResults.concat(result.hits);
        } catch (err) {
          console.error('Failed to create availability poll:', err);
          toolResultText = 'Failed to create the availability poll. Please try again.';
        }
      } else {
        // Sensor tools can't run server-side
        toolResultText = `The ${toolCall.function.name} tool requires the Robo iOS app. Please use the Capture tab to ${toolCall.function.name.replace(/_/g, ' ')}.`;
      }

      toolResults.push({
        role: 'tool' as const,
        tool_call_id: toolCall.id,
        content: toolResultText,
      });
    }

    // Build follow-up messages, instructing model not to include URLs if HITs were created
    const followUpMessages = [
      ...messages,
      choice.message,
      ...toolResults,
    ];
    if (allHitResults.length > 0) {
      followUpMessages.push({
        role: 'system' as const,
        content: 'A single shared poll link was created. Do NOT include any URLs in your response — the app displays them as a tappable card with a copy button. In your response, tell the user to copy the link and send it to their group chat or text thread with their friends. Keep it casual and brief, like "Copy the link below and send it to your group chat — everyone picks their name and marks their availability."',
      });
    }

    // Second request with tool results
    const followUp = await fetch('https://openrouter.ai/api/v1/chat/completions', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'Authorization': `Bearer ${c.env.OPENROUTER_API_KEY}`,
      },
      body: JSON.stringify({
        model,
        messages: followUpMessages,
        reasoning: { effort: 'low' },
      }),
    });

    if (!followUp.ok) {
      const text = await followUp.text();
      console.error('Follow-up request failed:', text);
      // Fall back to returning tool result directly
      const fallbackContent = toolResults.map((r) => r.content).join('\n');
      return contentToSSE(fallbackContent, allHitResults.length > 0 ? allHitResults : undefined);
    }

    const followUpResult = await followUp.json() as any;
    const modelSummary = followUpResult.choices?.[0]?.message?.content || 'Done!';
    return contentToSSE(modelSummary, allHitResults.length > 0 ? allHitResults : undefined);
  } else {
    // No tool calls — return content as SSE
    const content = choice?.message?.content || '';
    return contentToSSE(content);
  }
}
