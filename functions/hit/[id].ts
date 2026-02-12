/**
 * Pages Function: Dynamic HIT page
 * Serves personalized HTML with OG meta tags for link previews
 * URL: /hit/:id
 */

interface HitData {
  id: string;
  sender_name: string;
  recipient_name: string;
  task_description: string;
  agent_name: string | null;
  status: string;
  photo_count: number;
}

const API_BASE = 'https://robo-api.silv.workers.dev';

export const onRequest: PagesFunction = async (context) => {
  const hitId = context.params.id as string;

  // Fetch HIT data from Workers API
  let hit: HitData | null = null;
  try {
    const resp = await fetch(`${API_BASE}/api/hits/${hitId}`);
    if (resp.ok) {
      hit = (await resp.json()) as HitData;
    }
  } catch (e) {
    // API fetch failed — render error page
  }

  if (!hit) {
    return new Response(renderNotFound(), {
      status: 404,
      headers: { 'Content-Type': 'text/html; charset=utf-8' },
    });
  }

  // Determine first name for greeting
  const firstName = hit.recipient_name.split(' ')[0];
  // "M. Silverman" → "Matt", or use first word/name
  const senderFirst = hit.sender_name === 'M. Silverman' ? 'Matt' : hit.sender_name.split(' ')[0];

  return new Response(renderHitPage(hit, firstName, senderFirst), {
    headers: { 'Content-Type': 'text/html; charset=utf-8' },
  });
};

function renderNotFound(): string {
  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Task Not Found — ROBO.APP</title>
  <style>
    body { background: #06060a; color: #e2e2e8; font-family: 'DM Sans', system-ui, sans-serif; display: flex; align-items: center; justify-content: center; min-height: 100vh; margin: 0; }
    .msg { text-align: center; }
    h1 { font-size: 2rem; margin-bottom: 0.5rem; }
    p { color: #6b6b7b; }
    a { color: #3b82f6; text-decoration: none; }
  </style>
</head>
<body>
  <div class="msg">
    <h1>Task not found</h1>
    <p>This link may have expired or doesn't exist.</p>
    <p><a href="https://robo.app">robo.app</a></p>
  </div>
</body>
</html>`;
}

function escapeHtml(str: string): string {
  return str
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#039;');
}

function renderHitPage(hit: HitData, firstName: string, senderFirst: string): string {
  const safeFirst = escapeHtml(firstName);
  const safeSender = escapeHtml(senderFirst);
  const safeTask = escapeHtml(hit.task_description);
  const safeAgent = hit.agent_name ? escapeHtml(hit.agent_name) : null;
  const isCompleted = hit.status === 'completed';
  const isExpired = hit.status === 'expired';

  const ogTitle = `Hi ${safeFirst}, — ${safeSender} wants you to test something`;
  const ogDesc = `${safeSender} assigned you a HIT (Human Intelligence Task). ${safeTask}${safeAgent ? ` for the ${safeAgent}.` : '.'}`;

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${ogTitle}</title>

  <!-- OG / Social (must be in first 32KB for Slack) -->
  <meta property="og:type" content="website">
  <meta property="og:url" content="https://robo.app/hit/${hit.id}">
  <meta property="og:title" content="${ogTitle}">
  <meta property="og:description" content="${ogDesc}">
  <meta property="og:image" content="https://robo.app/demo/hit/og-hit-preview.png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:site_name" content="ROBO.APP">

  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${ogTitle}">
  <meta name="twitter:description" content="${ogDesc}">
  <meta name="twitter:image" content="https://robo.app/demo/hit/og-hit-preview.png">

  <meta name="theme-color" content="#06060a">

  <link rel="icon" type="image/svg+xml" href="/favicon.svg">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700;800&family=DM+Sans:wght@400;500;600&display=swap" rel="stylesheet">

  <style>
    *,*::before,*::after{margin:0;padding:0;box-sizing:border-box}

    :root {
      --blue: #2563EB;
      --blue-light: #3b82f6;
      --blue-glow: rgba(37, 99, 235, 0.35);
      --blue-dim: rgba(37, 99, 235, 0.12);
      --bg: #06060a;
      --surface: #0d0d14;
      --surface-raised: #12121c;
      --border: rgba(255,255,255,0.06);
      --border-accent: rgba(37, 99, 235, 0.2);
      --text: #e2e2e8;
      --text-dim: #6b6b7b;
      --text-muted: #3d3d4d;
      --green: #22c55e;
      --green-dim: rgba(34, 197, 94, 0.12);
      --red: #ef4444;
    }

    html { scroll-behavior: smooth }

    body {
      background: var(--bg);
      color: var(--text);
      font-family: 'DM Sans', system-ui, sans-serif;
      min-height: 100vh;
      display: flex;
      flex-direction: column;
      align-items: center;
      overflow-x: hidden;
      position: relative;
    }

    body::before {
      content: '';
      position: fixed;
      inset: 0;
      background-image: radial-gradient(circle, rgba(255,255,255,0.03) 1px, transparent 1px);
      background-size: 24px 24px;
      pointer-events: none;
      z-index: 0;
    }

    body::after {
      content: '';
      position: fixed;
      top: -30%;
      left: 50%;
      transform: translateX(-50%);
      width: 500px;
      height: 500px;
      background: radial-gradient(circle, var(--blue-glow) 0%, transparent 70%);
      filter: blur(80px);
      pointer-events: none;
      z-index: 0;
    }

    .container {
      position: relative;
      z-index: 1;
      display: flex;
      flex-direction: column;
      align-items: center;
      padding: 2.5rem 1.5rem 3rem;
      max-width: 520px;
      width: 100%;
    }

    .fi {
      opacity: 0;
      transform: translateY(14px);
      animation: fadeUp 0.6s ease-out forwards;
    }
    .fi:nth-child(1) { animation-delay: 0.05s }
    .fi:nth-child(2) { animation-delay: 0.12s }
    .fi:nth-child(3) { animation-delay: 0.19s }
    .fi:nth-child(4) { animation-delay: 0.26s }
    .fi:nth-child(5) { animation-delay: 0.33s }
    .fi:nth-child(6) { animation-delay: 0.4s }
    .fi:nth-child(7) { animation-delay: 0.47s }
    .fi:nth-child(8) { animation-delay: 0.54s }

    @keyframes fadeUp {
      to { opacity: 1; transform: translateY(0); }
    }

    .alpha-badge {
      align-self: flex-start;
      display: inline-flex;
      align-items: center;
      gap: 6px;
      padding: 0.35rem 0.75rem;
      border: 1px solid rgba(34, 197, 94, 0.3);
      border-radius: 100px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.6rem;
      font-weight: 700;
      letter-spacing: 0.08em;
      text-transform: uppercase;
      color: var(--green);
      background: var(--green-dim);
      margin-bottom: 1.75rem;
    }

    .alpha-badge::before {
      content: '';
      width: 5px;
      height: 5px;
      border-radius: 50%;
      background: var(--green);
      animation: blink 2s ease-in-out infinite;
    }

    @keyframes blink {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.3; }
    }

    .top-bar {
      display: flex;
      align-items: center;
      gap: 10px;
      align-self: flex-start;
      margin-bottom: 1rem;
    }

    .top-bar svg { width: 40px; height: 40px; filter: drop-shadow(0 0 16px var(--blue-glow)); }
    .top-bar .brand { font-family: 'JetBrains Mono', monospace; font-weight: 800; font-size: 1.1rem; color: #fff; letter-spacing: 0.04em; }
    .top-bar .brand .dot { color: var(--blue-light); }

    .hero { align-self: flex-start; margin-bottom: 1.75rem; width: 100%; }
    .greeting { font-size: 3rem; font-weight: 600; color: #fff; line-height: 1.1; letter-spacing: -0.02em; margin-bottom: 0.35rem; }
    .greeting .name { color: var(--blue-light); }
    .subtitle { font-size: 1.5rem; font-weight: 500; color: var(--text-dim); line-height: 1.3; }
    .subtitle .sender { color: var(--text); }

    .task-card {
      width: 100%;
      background: var(--surface);
      border: 1px solid var(--border-accent);
      border-radius: 16px;
      padding: 1.25rem 1.35rem;
      margin-bottom: 0.75rem;
      position: relative;
      overflow: hidden;
    }

    .task-card::before {
      content: '';
      position: absolute;
      top: 0; left: 0; right: 0;
      height: 1px;
      background: linear-gradient(90deg, transparent, var(--blue), transparent);
      opacity: 0.4;
    }

    .task-header { display: flex; align-items: center; gap: 14px; margin-bottom: 0.85rem; }

    .task-icon {
      width: 44px; height: 44px;
      background: var(--blue-dim);
      border-radius: 12px;
      display: flex; align-items: center; justify-content: center;
      flex-shrink: 0;
    }

    .task-icon svg { width: 22px; height: 22px; stroke: var(--blue-light); }
    .task-title { font-family: 'JetBrains Mono', monospace; font-size: 1rem; font-weight: 700; color: var(--text); letter-spacing: 0.01em; line-height: 1.3; }

    .task-meta { display: flex; align-items: center; gap: 10px; margin-top: 4px; }

    .task-pill {
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.62rem; font-weight: 700; letter-spacing: 0.08em; text-transform: uppercase;
      color: var(--blue-light);
      background: var(--blue-dim);
      border: 1px solid rgba(37, 99, 235, 0.3);
      border-radius: 100px;
      padding: 3px 10px;
    }

    .task-time { font-family: 'JetBrains Mono', monospace; font-size: 0.72rem; color: var(--text-muted); }
    .task-desc { font-size: 0.9rem; color: var(--text-dim); line-height: 1.55; }

    /* Camera CTA */
    .camera-cta {
      width: 72px; height: 72px;
      border-radius: 50%;
      background: var(--blue);
      border: 3px solid rgba(255,255,255,0.15);
      display: flex; align-items: center; justify-content: center;
      cursor: pointer;
      transition: all 0.2s ease;
      box-shadow: 0 0 32px rgba(37, 99, 235, 0.35);
      margin-top: 0.5rem;
    }
    .camera-cta svg { width: 28px; height: 28px; }
    .camera-cta:hover { background: var(--blue-light); box-shadow: 0 0 48px rgba(37, 99, 235, 0.5); transform: scale(1.06); }
    .camera-cta:active { transform: scale(0.96); }

    .camera-label {
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.68rem; color: var(--text-muted);
      margin-top: 0.6rem; letter-spacing: 0.02em;
      margin-bottom: 2rem;
    }

    /* Camera modal */
    .camera-modal {
      display: none;
      position: fixed;
      inset: 0;
      background: #000;
      z-index: 200;
      flex-direction: column;
    }
    .camera-modal.active { display: flex; }

    .camera-top-bar {
      display: flex;
      align-items: center;
      justify-content: space-between;
      padding: 12px 16px;
      background: rgba(0,0,0,0.8);
      z-index: 2;
    }

    .camera-top-bar .count {
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.85rem;
      color: #fff;
    }

    .camera-top-bar button {
      background: none;
      border: none;
      color: #fff;
      font-family: 'DM Sans', sans-serif;
      font-size: 0.9rem;
      cursor: pointer;
      padding: 6px 12px;
    }

    .camera-viewfinder {
      flex: 1;
      position: relative;
      overflow: hidden;
      background: #111;
    }

    .camera-viewfinder video {
      width: 100%;
      height: 100%;
      object-fit: cover;
    }

    .camera-bottom {
      background: rgba(0,0,0,0.9);
      padding: 12px 16px 24px;
      display: flex;
      flex-direction: column;
      gap: 12px;
      z-index: 2;
    }

    .thumb-strip {
      display: flex;
      gap: 8px;
      overflow-x: auto;
      padding: 4px 0;
      min-height: 60px;
      -webkit-overflow-scrolling: touch;
    }

    .thumb-strip:empty { display: none; }

    .thumb-item {
      position: relative;
      width: 56px;
      height: 56px;
      border-radius: 8px;
      overflow: hidden;
      flex-shrink: 0;
      border: 2px solid rgba(255,255,255,0.2);
    }

    .thumb-item img {
      width: 100%;
      height: 100%;
      object-fit: cover;
    }

    .thumb-item .remove {
      position: absolute;
      top: -2px; right: -2px;
      width: 20px; height: 20px;
      background: var(--red);
      border: none;
      border-radius: 50%;
      color: #fff;
      font-size: 12px;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
      line-height: 1;
    }

    .shutter-row {
      display: flex;
      align-items: center;
      justify-content: center;
      gap: 32px;
    }

    .shutter-btn {
      width: 72px; height: 72px;
      border-radius: 50%;
      background: #fff;
      border: 4px solid rgba(255,255,255,0.3);
      cursor: pointer;
      transition: transform 0.1s;
    }
    .shutter-btn:active { transform: scale(0.9); }

    .flip-btn {
      width: 44px; height: 44px;
      border-radius: 50%;
      background: rgba(255,255,255,0.15);
      border: none;
      cursor: pointer;
      display: flex;
      align-items: center;
      justify-content: center;
    }
    .flip-btn svg { width: 24px; height: 24px; }

    .submit-btn {
      width: 100%;
      padding: 14px;
      background: var(--blue);
      color: #fff;
      border: none;
      border-radius: 12px;
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.9rem;
      font-weight: 700;
      cursor: pointer;
      transition: background 0.2s;
    }
    .submit-btn:hover { background: var(--blue-light); }
    .submit-btn:disabled { opacity: 0.5; cursor: not-allowed; }

    /* Completion state */
    .completed-state {
      display: none;
      text-align: center;
      padding: 2rem 0;
    }
    .completed-state.active { display: block; }
    .completed-state .check { font-size: 3rem; margin-bottom: 1rem; }
    .completed-state h2 { font-size: 1.5rem; color: #fff; margin-bottom: 0.5rem; }
    .completed-state p { color: var(--text-dim); font-size: 0.95rem; }

    /* Upload progress */
    .upload-progress {
      display: none;
      text-align: center;
      padding: 1rem 0;
    }
    .upload-progress.active { display: block; }
    .upload-progress .bar {
      width: 100%;
      height: 4px;
      background: var(--surface);
      border-radius: 2px;
      overflow: hidden;
      margin-top: 0.75rem;
    }
    .upload-progress .fill {
      height: 100%;
      background: var(--blue);
      border-radius: 2px;
      transition: width 0.3s ease;
      width: 0%;
    }

    /* File fallback */
    .file-fallback {
      display: none;
      text-align: center;
      margin-top: 0.5rem;
    }
    .file-fallback a {
      color: var(--text-muted);
      font-size: 0.75rem;
      text-decoration: underline;
    }

    /* Toast */
    .toast {
      display: none;
      position: fixed;
      bottom: 2rem;
      left: 50%;
      transform: translateX(-50%) translateY(20px);
      background: var(--surface-raised);
      border: 1px solid var(--border-accent);
      border-radius: 12px;
      padding: 0.75rem 1.25rem;
      font-family: 'JetBrains Mono', monospace;
      font-size: 0.72rem;
      color: var(--text);
      z-index: 300;
      opacity: 0;
      transition: opacity 0.3s ease, transform 0.3s ease;
      box-shadow: 0 8px 32px rgba(0,0,0,0.4);
      text-align: center;
      max-width: 320px;
    }
    .toast.is-visible { display: block; opacity: 1; transform: translateX(-50%) translateY(0); }

    @media (min-width: 640px) {
      .container { padding: 3.5rem 2rem 4rem; }
      .greeting { font-size: 3.5rem; }
      .subtitle { font-size: 1.65rem; }
    }
  </style>
</head>
<body>
  <main class="container" id="main-content">
    <div class="top-bar fi">
      <svg viewBox="0 0 120 120" fill="none" xmlns="http://www.w3.org/2000/svg">
        <rect width="120" height="120" rx="28" fill="#2563EB"/>
        <circle cx="42" cy="48" r="14" fill="white"/>
        <circle cx="78" cy="48" r="14" fill="white"/>
        <circle cx="42" cy="48" r="7" fill="#1a4fc0"/>
        <circle cx="78" cy="48" r="7" fill="#1a4fc0"/>
        <path d="M 34 80 Q 60 102 86 80" fill="none" stroke="white" stroke-width="8" stroke-linecap="round"/>
      </svg>
      <span class="brand">ROBO<span class="dot">.</span>APP</span>
    </div>

    <div class="alpha-badge fi">Alpha Test Invite</div>

    <div class="hero fi">
      <h1 class="greeting">Hi <span class="name">${safeFirst}</span>,</h1>
      <p class="subtitle"><span class="sender">${safeSender}</span> wants you to test something</p>
    </div>

    <div class="task-card fi">
      <div class="task-header">
        <div class="task-icon">
          <svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z"/><circle cx="12" cy="13" r="3"/></svg>
        </div>
        <div>
          <div class="task-title">${safeTask}</div>
          <div class="task-meta">
            <span class="task-pill">Camera</span>
            <span class="task-time">~30 seconds</span>
          </div>
        </div>
      </div>
      <p class="task-desc">${safeAgent ? `Help test the <strong>${safeAgent}</strong> by completing this quick photo task.` : 'Complete this quick photo task to help test our AI agent.'}</p>
    </div>

    ${isCompleted ? `
    <div class="completed-state active fi">
      <div class="check">&#10003;</div>
      <h2>Task completed!</h2>
      <p>${safeFirst} submitted ${hit.photo_count} photo${hit.photo_count !== 1 ? 's' : ''}. Thank you!</p>
    </div>
    ` : isExpired ? `
    <div class="completed-state active fi">
      <h2>Task expired</h2>
      <p>This task is no longer available.</p>
    </div>
    ` : `
    <button class="camera-cta fi" id="camera-btn" aria-label="Take photos">
      <svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z"/><circle cx="12" cy="13" r="3"/></svg>
    </button>
    <p class="camera-label fi">Tap to capture</p>
    <div class="file-fallback fi" id="file-fallback">
      <a href="#" id="file-fallback-link">Or select photos from your library</a>
      <input type="file" id="file-input" accept="image/*" multiple style="display:none">
    </div>

    <div class="upload-progress fi" id="upload-progress">
      <p style="color: var(--text-dim); font-size: 0.85rem;">Uploading photos...</p>
      <div class="bar"><div class="fill" id="upload-fill"></div></div>
    </div>

    <div class="completed-state fi" id="completed-msg">
      <div class="check" style="color: var(--green);">&#10003;</div>
      <h2>Photos submitted!</h2>
      <p>Thanks ${safeFirst}! ${safeSender} will be notified.</p>
    </div>
    `}
  </main>

  <!-- Camera modal -->
  <div class="camera-modal" id="camera-modal">
    <div class="camera-top-bar">
      <button id="camera-cancel">Cancel</button>
      <span class="count" id="photo-count">0 photos</span>
      <button id="camera-done" style="color: var(--blue-light); font-weight: 600;">Done</button>
    </div>
    <div class="camera-viewfinder">
      <video id="camera-video" autoplay playsinline muted></video>
    </div>
    <div class="camera-bottom">
      <div class="thumb-strip" id="thumb-strip"></div>
      <div class="shutter-row">
        <div style="width:44px"></div>
        <button class="shutter-btn" id="shutter-btn" aria-label="Capture photo"></button>
        <button class="flip-btn" id="flip-btn" aria-label="Flip camera">
          <svg viewBox="0 0 24 24" fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round">
            <path d="M1 4v6h6"/><path d="M23 20v-6h-6"/>
            <path d="M20.49 9A9 9 0 0 0 5.64 5.64L1 10m22 4l-4.64 4.36A9 9 0 0 1 3.51 15"/>
          </svg>
        </button>
      </div>
    </div>
  </div>

  <div class="toast" id="toast"></div>

  <script>
  (function() {
    var HIT_ID = '${hit.id}';
    var API = '${API_BASE}';
    var photos = []; // { blob, url }
    var stream = null;
    var facingMode = 'environment';

    var cameraBtn = document.getElementById('camera-btn');
    var cameraModal = document.getElementById('camera-modal');
    var video = document.getElementById('camera-video');
    var shutterBtn = document.getElementById('shutter-btn');
    var flipBtn = document.getElementById('flip-btn');
    var cancelBtn = document.getElementById('camera-cancel');
    var doneBtn = document.getElementById('camera-done');
    var thumbStrip = document.getElementById('thumb-strip');
    var photoCount = document.getElementById('photo-count');
    var uploadProgress = document.getElementById('upload-progress');
    var uploadFill = document.getElementById('upload-fill');
    var completedMsg = document.getElementById('completed-msg');
    var mainContent = document.getElementById('main-content');
    var fileFallback = document.getElementById('file-fallback');
    var fileInput = document.getElementById('file-input');
    var toast = document.getElementById('toast');

    function showToast(msg, duration) {
      if (!toast) return;
      toast.textContent = msg;
      toast.classList.add('is-visible');
      setTimeout(function() { toast.classList.remove('is-visible'); }, duration || 3000);
    }

    function updateCount() {
      if (photoCount) photoCount.textContent = photos.length + ' photo' + (photos.length !== 1 ? 's' : '');
    }

    async function startCamera() {
      try {
        stream = await navigator.mediaDevices.getUserMedia({
          video: { facingMode: facingMode, width: { ideal: 1920 }, height: { ideal: 1080 } },
          audio: false
        });
        video.srcObject = stream;
        cameraModal.classList.add('active');
      } catch (e) {
        // Camera not available — show file fallback
        if (fileFallback) fileFallback.style.display = 'block';
        showToast('Camera not available. Use file picker instead.');
      }
    }

    function stopCamera() {
      if (stream) {
        stream.getTracks().forEach(function(t) { t.stop(); });
        stream = null;
      }
      video.srcObject = null;
      cameraModal.classList.remove('active');
    }

    function capturePhoto() {
      var canvas = document.createElement('canvas');
      canvas.width = video.videoWidth;
      canvas.height = video.videoHeight;
      var ctx = canvas.getContext('2d');
      ctx.drawImage(video, 0, 0);

      canvas.toBlob(function(blob) {
        if (!blob) return;
        var url = URL.createObjectURL(blob);
        photos.push({ blob: blob, url: url });
        addThumb(photos.length - 1, url);
        updateCount();
      }, 'image/jpeg', 0.85);
    }

    function addThumb(index, url) {
      var item = document.createElement('div');
      item.className = 'thumb-item';
      item.innerHTML = '<img src="' + url + '"><button class="remove" data-idx="' + index + '">&times;</button>';
      thumbStrip.appendChild(item);
      thumbStrip.scrollLeft = thumbStrip.scrollWidth;

      item.querySelector('.remove').addEventListener('click', function() {
        var idx = parseInt(this.getAttribute('data-idx'));
        URL.revokeObjectURL(photos[idx].url);
        photos.splice(idx, 1);
        rebuildThumbs();
        updateCount();
      });
    }

    function rebuildThumbs() {
      thumbStrip.innerHTML = '';
      photos.forEach(function(p, i) { addThumb(i, p.url); });
    }

    async function uploadPhotos() {
      if (photos.length === 0) {
        showToast('Take at least one photo first');
        return;
      }

      stopCamera();

      // Hide capture UI, show progress
      if (cameraBtn) cameraBtn.style.display = 'none';
      var label = document.querySelector('.camera-label');
      if (label) label.style.display = 'none';
      if (fileFallback) fileFallback.style.display = 'none';
      if (uploadProgress) uploadProgress.classList.add('active');

      var uploaded = 0;
      for (var i = 0; i < photos.length; i++) {
        try {
          // Upload photo directly to Workers (which stores in R2 via binding)
          await fetch(API + '/api/hits/' + HIT_ID + '/upload', {
            method: 'POST',
            body: photos[i].blob,
            headers: { 'Content-Type': 'image/jpeg' }
          });

          uploaded++;
          if (uploadFill) uploadFill.style.width = Math.round((uploaded / photos.length) * 100) + '%';
        } catch (e) {
          console.error('Upload failed for photo ' + i, e);
        }
      }

      // 3. Complete the HIT
      try {
        await fetch(API + '/api/hits/' + HIT_ID + '/complete', { method: 'PATCH' });
      } catch (e) {
        console.error('Complete failed', e);
      }

      // Show completion
      if (uploadProgress) uploadProgress.classList.remove('active');
      if (completedMsg) completedMsg.classList.add('active');

      // Cleanup
      photos.forEach(function(p) { URL.revokeObjectURL(p.url); });
      photos = [];
    }

    // Event listeners
    if (cameraBtn) {
      cameraBtn.addEventListener('click', startCamera);
    }

    if (shutterBtn) {
      shutterBtn.addEventListener('click', capturePhoto);
    }

    if (flipBtn) {
      flipBtn.addEventListener('click', function() {
        facingMode = facingMode === 'environment' ? 'user' : 'environment';
        stopCamera();
        startCamera();
      });
    }

    if (cancelBtn) {
      cancelBtn.addEventListener('click', function() {
        stopCamera();
        photos.forEach(function(p) { URL.revokeObjectURL(p.url); });
        photos = [];
        thumbStrip.innerHTML = '';
        updateCount();
      });
    }

    if (doneBtn) {
      doneBtn.addEventListener('click', uploadPhotos);
    }

    // File fallback
    if (fileInput) {
      var fallbackLink = document.getElementById('file-fallback-link');
      if (fallbackLink) {
        fallbackLink.addEventListener('click', function(e) {
          e.preventDefault();
          fileInput.click();
        });
      }

      fileInput.addEventListener('change', function() {
        var files = Array.from(this.files || []);
        files.forEach(function(f) {
          var url = URL.createObjectURL(f);
          photos.push({ blob: f, url: url });
        });
        if (photos.length > 0) {
          uploadPhotos();
        }
      });
    }

    // Show file fallback link always on page load (as alternative)
    if (fileFallback && !${isCompleted || isExpired}) {
      fileFallback.style.display = 'block';
    }
  })();
  </script>
</body>
</html>`;
}
