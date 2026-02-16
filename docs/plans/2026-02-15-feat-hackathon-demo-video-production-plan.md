---
title: "Hackathon Demo Video Production"
type: feat
status: active
date: 2026-02-15
deadline: 2026-02-16 3:00 PM EST
---

# Hackathon Demo Video Production

## Overview

Create the required 3-minute demo video for the Claude Code hackathon submission. Demo Quality is **30% of judging** — the highest-weighted criterion. The video must show a working demo that "holds up when watched" and is "genuinely cool to experience."

**Submission requirements** (from `docs/feb-10-kickoff-instructions.md`):
1. 3-minute demo video (YouTube/Loom)
2. GitHub repo (ready — open source)
3. 100-200 word written summary

## Production Philosophy: Audio-First

**Start with the voiceover, align everything else to it.** ElevenLabs timing is hard to manipulate after generation, so the audio track is the timeline source of truth. All video segments get trimmed/sped to match.

## Tool Stack

| Tool | Purpose | Cost |
|------|---------|------|
| **ElevenLabs** | Voiceover narration | ~$0.30 (have API key) |
| **Kling 2.6 Pro via Fal.ai** | AI-generated intro/outro video | ~$1-2 (5-10s clips) |
| **Screen Studio** | iOS app demo recording (device mirroring) | One-time license |
| **FFmpeg** | Stitch segments, add audio, normalize | Free |
| **Claude** | Script writing, FFmpeg commands, editing guidance | Already using |

## Video Structure (3 minutes)

Based on `docs/solutions/pitch-storytelling-playbook.md`:

| Beat | Duration | Content | Source |
|------|----------|---------|--------|
| **Intro** | ~5s | Cinematic AI-generated title sequence | Kling via Fal.ai |
| **Beat 1: The Problem** | 30s | "Building an AI agent is easy. Getting it LiDAR data? Months of Swift..." | Screen recording of Xcode/complexity OR text cards |
| **Beat 2: The Solution** | 15s | "Robo is an open-source iOS app that unlocks native context for any AI agent" | App icon + integration options graphic |
| **Beat 3: Live Demo** | 90s | Full LiDAR scan walkthrough on real device | Screen Studio (iPhone mirror) |
| **Beat 4: The Wow** | 30s | "That LiDAR scan just went into Claude. Try doing that without Robo." | Show Claude analyzing the scan data |
| **Beat 5: Close** | 15s | "Open source. Free tier. $85 of Claude API usage. That's the whole app." | Text cards + GitHub link |
| **Outro** | ~5s | Logo/URL end card | Kling via Fal.ai OR static |

## Step-by-Step Production Checklist

### Phase 1: Script & Audio (Do First)

- [ ] **Write the full narration script** (~400 words for 3 min at natural pace)
  - Use key phrases from pitch playbook (see below)
  - Write conversationally — avoid jargon
  - Add `<break time="1.0s"/>` tags for pauses between beats
  - Save as `docs/video/script.md`

- [ ] **Generate voiceover with ElevenLabs**
  - Model: `eleven_multilingual_v2`
  - Format: `mp3_44100_128`
  - Use `seed` parameter for reproducibility
  - Use `speed: 1.0` (adjust if too fast/slow)
  - Generate full narration as single file OR per-beat segments
  - Save to `demo/audio/voiceover.mp3`

- [ ] **Measure audio timing**
  ```bash
  ffprobe -i demo/audio/voiceover.mp3 -show_entries format=duration -v quiet -of csv="p=0"
  ```
  - Note timestamp for each beat transition
  - This becomes the master timeline

### Phase 2: Visual Assets (Parallel — order doesn't matter)

- [ ] **Generate intro video with Kling AI (Fal.ai)**
  - Endpoint: `fal-ai/kling-video/v2.6/pro/text-to-video`
  - Duration: 5 seconds, 16:9, with audio
  - Prompt example: "A sleek iPhone floating in space with holographic sensor icons (LiDAR grid, barcode, camera lens) materializing around it. Cinematic lighting, dark background, subtle particle effects. Futuristic, clean, professional."
  - Export as MP4
  - Save to `demo/video/intro.mp4`

- [ ] **Generate outro video or static end card**
  - Options: Kling 5s clip OR simple text card via FFmpeg
  - Include: robo.app URL, GitHub link, "Built with Claude Code"
  - Save to `demo/video/outro.mp4`

- [ ] **Record app demo with Screen Studio**
  - Connect iPhone via wireless mirroring
  - Record the full flow: Create → LiDAR Scanner → Tips → Scan → Review → Share
  - Enable auto-zoom on taps
  - Record ~2-3 minutes raw, will trim to 90s
  - **Practice the walkthrough 2-3 times before recording**
  - Save raw to `demo/video/demo_raw.mp4`

- [ ] **Record/capture the "Wow" segment**
  - Show Claude Code or Claude chat receiving the LiDAR JSON
  - Show Claude analyzing room dimensions, suggesting furniture placement
  - Screen record this interaction
  - Save to `demo/video/wow_segment.mp4`

- [ ] **Create "Problem" visual** (optional: can be just voiceover + text)
  - Options: Screen recording of Xcode complexity, or simple text cards
  - Keep minimal — the voiceover carries this beat

### Phase 3: Assembly (After audio + all video ready)

- [ ] **Trim all video segments to match voiceover timing**
  - Use Screen Studio or FFmpeg to trim demo to ~90s
  - Speed up if needed (1.1-1.2x max to stay natural)
  ```bash
  # Speed up video by 1.15x
  ffmpeg -i demo_raw.mp4 -filter:v "setpts=0.87*PTS" -filter:a "atempo=1.15" demo_trimmed.mp4
  ```

- [ ] **Normalize all video specs** (resolution, codec)
  ```bash
  # Normalize to 1080p H.264
  ffmpeg -i input.mp4 -vf "scale=1920:1080:force_original_aspect_ratio=decrease,pad=1920:1080:-1:-1" \
    -c:v libx264 -crf 18 -c:a aac normalized.mp4
  ```

- [ ] **Create concat list and stitch**
  ```bash
  cat > demo/input.txt << EOF
  file 'video/intro.mp4'
  file 'video/problem_segment.mp4'
  file 'video/demo_trimmed.mp4'
  file 'video/wow_segment.mp4'
  file 'video/outro.mp4'
  EOF

  ffmpeg -f concat -safe 0 -i demo/input.txt -c:v libx264 -c:a aac demo/stitched.mp4
  ```

- [ ] **Add voiceover track**
  ```bash
  ffmpeg -i demo/stitched.mp4 -i demo/audio/voiceover.mp3 \
    -c:v copy -map 0:v -map 1:a -shortest demo/final.mp4
  ```

- [ ] **Optional: Add background music (low volume)**
  ```bash
  ffmpeg -i demo/stitched.mp4 -i demo/audio/music.mp3 -i demo/audio/voiceover.mp3 \
    -filter_complex "[1:a]volume=0.15[music];[2:a]volume=1.0[voice];[music][voice]amix=inputs=2:duration=first[mixed]" \
    -c:v copy -map 0:v -map "[mixed]" -c:a aac demo/final.mp4
  ```

### Phase 4: Polish & Submit

- [ ] **Review final video** — watch it fresh, check:
  - Audio/video sync
  - Total duration ≤ 3 minutes
  - All text readable
  - Demo flow makes sense without context
  - "Wow" moment lands

- [ ] **Upload to YouTube** (unlisted)
  - Title: "Robo — Native Mobile Context for AI Agents"
  - Description: Include GitHub link + summary

- [ ] **Write 100-200 word summary** for submission
  - Save as `docs/video/submission-summary.md`

- [ ] **Submit** before Mon Feb 16, 3:00 PM EST

## Key Phrases for Script (Pre-Approved)

From `docs/solutions/pitch-storytelling-playbook.md`:
- "Native mobile context for AI agents"
- "Trapped on the device, invisible to AI agents"
- "No iOS dev, no App Store"
- "Months of Swift, Xcode, and App Store review"
- "The missing bridge"
- "Guided capture — complete data on the first try"
- "$85 of Claude API usage. That's it."

**Avoid:** "walled garden", jargon-heavy descriptions

## ElevenLabs Quick Reference

```bash
# Generate voiceover
http POST https://api.elevenlabs.io/v1/text-to-speech/{voice_id} \
  xi-api-key:$ELEVENLABS_API_KEY \
  text="Your script here" \
  model_id=eleven_multilingual_v2 \
  output_format=mp3_44100_128 \
  voice_settings:='{"stability":0.5,"similarity_boost":0.75,"speed":1.0}' \
  seed:=12345 \
  --download --output voiceover.mp3 --timeout=30
```

## Kling AI (Fal.ai) Quick Reference

```bash
# Generate intro video
http POST https://queue.fal.run/fal-ai/kling-video/v2.6/pro/text-to-video \
  Authorization:"Key $FAL_KEY" \
  prompt="..." \
  duration:=5 \
  aspect_ratio=16:9 \
  generate_audio:=true \
  --timeout=30
```

## References

- Hackathon rules: `docs/feb-10-kickoff-instructions.md`
- Pitch playbook: `docs/solutions/pitch-storytelling-playbook.md`
- Use cases: `docs/use-cases.md`
- Judging: Impact 25%, Opus 4.6 Use 25%, Depth 20%, **Demo Quality 30%**
