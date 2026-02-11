---
title: "Gemini Image Generation Rate Limits — Use OpenRouter"
category: integration-issues
component: image-generation
symptoms:
  - "429 RESOURCE_EXHAUSTED"
  - "Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests"
  - "limit: 0, model: gemini-3-pro-image"
root_cause: "Gemini free tier daily quota exhausted across all image-capable models"
resolution: "Route requests through OpenRouter API instead of Gemini directly"
date: 2026-02-10
tags: [gemini, openrouter, image-generation, rate-limits, api]
---

# Gemini Image Generation Rate Limits — Use OpenRouter

## Problem

When generating images via the Gemini Python SDK (`google-genai`), all image-capable models return `429 RESOURCE_EXHAUSTED` after the free tier daily quota is consumed.

### Error Message
```
google.genai.errors.ClientError: 429 RESOURCE_EXHAUSTED
Quota exceeded for metric: generativelanguage.googleapis.com/generate_content_free_tier_requests
limit: 0, model: gemini-3-pro-image
```

### Models Affected
All image-capable models share the same free tier pool:
- `gemini-3-pro-image-preview`
- `gemini-2.0-flash-exp-image-generation`
- `gemini-2.5-flash-image`

The `imagen-4.0-*` models require billing and won't work on free tier at all.

## Investigation

1. Tried `gemini-3-pro-image-preview` — 429 (daily quota exhausted)
2. Tried `gemini-2.0-flash-exp-image-generation` — 429 (same pool)
3. Tried `gemini-2.5-flash-image` — 429 (same pool)
4. Tried `imagen-4.0-fast-generate-001` — 400 "only accessible to billed users"
5. Added delays between requests (15s, 50s) — still 429 on per-day limit

## Solution

Route through **OpenRouter** which has its own quota/billing separate from Google's free tier.

### Setup
```bash
# .env
OPENROUTER_API_KEY=sk-or-v1-...
OPENROUTER_IMAGE_CREATION_MODEL=google/gemini-3-pro-image-preview
```

### API Call (curl)
```bash
source .env
curl -s --max-time 60 https://openrouter.ai/api/v1/chat/completions \
  -H "Content-Type: application/json" \
  -H "Authorization: Bearer $OPENROUTER_API_KEY" \
  -d '{
    "model": "google/gemini-3-pro-image-preview",
    "messages": [{"role": "user", "content": "YOUR PROMPT HERE"}]
  }' -o /tmp/response.json
```

### Extract Image (Python)
```python
import json, base64

with open('/tmp/response.json') as f:
    data = json.load(f)

img = data['choices'][0]['message']['images'][0]
b64 = img['image_url']['url'].split(',', 1)[1]

with open('output.png', 'wb') as f:
    f.write(base64.b64decode(b64))
```

### Response Structure
```
choices[0].message.images[0].image_url.url → "data:image/png;base64,..."
choices[0].message.content → text description
```

## Key Differences: Direct Gemini vs OpenRouter

| Aspect | Gemini Direct | OpenRouter |
|--------|--------------|------------|
| Auth | `GEMINI_API_KEY` | `OPENROUTER_API_KEY` |
| SDK | `google-genai` Python | REST API (curl/httpie) |
| Image location | `response.parts[].inline_data` | `message.images[].image_url.url` |
| Rate limits | Free tier per-model daily cap | Separate billing/quota |
| Image editing | Supports reference images | Text-to-image only |
| Response size | ~1MB | ~1.5MB (base64 in JSON) |

## Prevention

- **Always use OpenRouter for image generation** in this project (key is in `.env`)
- Keep the Gemini direct SDK as fallback for image *editing* (reference image input)
- Add `--max-time 60` to curl calls (generation can take 30-45s)
- Save responses to files (`-o /tmp/response.json`) to avoid terminal flooding

## Related

- Memory file: `memory/openrouter-image-generation.md`
- Icon options: `demo/icon-options/`
