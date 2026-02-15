import type { Context } from 'hono';
import { ImageResponse } from 'workers-og';
import type { Env } from '../types';

type HitData = {
  sender_name: string;
  recipient_name: string;
  task_description: string;
  hit_type: string;
  config: string | null;
};

function escapeHtml(str: string): string {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;');
}

function buildOgLayout(hit: HitData) {
  const senderName = hit.sender_name || 'Someone';
  let headline = `${senderName} needs your help`;
  let subtitle = hit.task_description || '';

  if (hit.hit_type === 'group_poll') {
    const config = hit.config ? JSON.parse(hit.config) : {};
    subtitle = config.context || config.title || hit.task_description || '';
  } else if (hit.hit_type === 'availability') {
    headline = `${senderName} is planning something`;
  }

  if (headline.length > 50) headline = headline.slice(0, 47) + '...';
  if (subtitle.length > 80) subtitle = subtitle.slice(0, 77) + '...';

  return { headline, subtitle };
}

function buildOgHtml(headline: string, subtitle: string): string {
  const safeHeadline = escapeHtml(headline);
  const safeSubtitle = escapeHtml(subtitle);

  const subtitleHtml = safeSubtitle
    ? `<div style="display: flex; font-size: 24px; color: #3b82f6; background-color: rgba(37,99,235,0.12); border: 1px solid rgba(37,99,235,0.25); border-radius: 12px; padding: 12px 20px; line-height: 1.4;">${safeSubtitle}</div>`
    : '';

  return `<div style="display: flex; width: 1200px; height: 630px; background-color: #06060a; font-family: sans-serif;"><div style="display: flex; flex-direction: column; justify-content: center; padding: 60px 70px; flex: 1;"><div style="display: flex; align-items: center; margin-bottom: 40px;"><div style="display: flex; width: 44px; height: 44px; background-color: #2563EB; border-radius: 12px; margin-right: 12px;"></div><div style="display: flex; font-size: 22px; font-weight: 700; color: #ffffff; letter-spacing: 0.05em;">ROBO.APP</div></div><div style="display: flex; font-size: 52px; font-weight: 700; color: #ffffff; line-height: 1.15; margin-bottom: 20px;">${safeHeadline}</div>${subtitleHtml}<div style="display: flex; font-size: 16px; color: #6b6b7b; margin-top: 40px; letter-spacing: 0.03em;">robo.app</div></div><div style="display: flex; align-items: center; justify-content: center; width: 350px;"><div style="display: flex; width: 200px; height: 200px; background-color: #2563EB; border-radius: 44px;"></div></div></div>`;
}

export async function serveOgImage(c: Context<{ Bindings: Env }>) {
  const id = c.req.param('id');

  // Check R2 cache first
  const r2Key = `og/${id}.png`;
  try {
    const cached = await c.env.BUCKET.get(r2Key);
    if (cached) {
      return new Response(cached.body, {
        headers: {
          'Content-Type': 'image/png',
          'Cache-Control': 'public, max-age=86400',
        },
      });
    }
  } catch {
    // R2 miss — generate
  }

  // Fetch HIT data
  let hit: HitData | null = null;
  try {
    hit = await c.env.DB.prepare(
      'SELECT sender_name, recipient_name, task_description, hit_type, config FROM hits WHERE id = ?'
    )
      .bind(id)
      .first<HitData>();
  } catch {
    // Fall through to fallback
  }

  if (!hit) {
    hit = {
      sender_name: 'Someone',
      recipient_name: '',
      task_description: "You've been invited",
      hit_type: 'photo',
      config: null,
    };
  }

  try {
    const { headline, subtitle } = buildOgLayout(hit);
    const html = buildOgHtml(headline, subtitle);

    const imgResponse = new ImageResponse(html, {
      width: 1200,
      height: 630,
    });

    // Get the PNG bytes for R2 caching
    const pngBuffer = await imgResponse.arrayBuffer();

    // Cache in R2 (fire-and-forget)
    c.executionCtx.waitUntil(c.env.BUCKET.put(r2Key, pngBuffer));

    return new Response(pngBuffer, {
      headers: {
        'Content-Type': 'image/png',
        'Cache-Control': 'public, max-age=86400',
      },
    });
  } catch (err) {
    console.error('OG image generation failed:', err);
    return c.redirect('https://robo.app/og-image.png', 302);
  }
}
