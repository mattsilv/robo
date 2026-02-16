import type { Context } from 'hono';
import type { Env } from '../types';

function escapeHtml(str: string): string {
  return str.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;').replace(/"/g, '&quot;').replace(/'/g, '&#39;');
}

function escapeJs(str: string): string {
  return str.replace(/\\/g, '\\\\').replace(/'/g, "\\'").replace(/</g, '\\x3c').replace(/>/g, '\\x3e').replace(/\n/g, '\\n').replace(/\r/g, '\\r');
}

/**
 * GET /hit/:id — Serve the HIT web page.
 *
 * This Worker route replaces the old Cloudflare Pages static file.
 * It fetches the HIT from D1 to inject dynamic OG meta tags for link previews,
 * then the client-side JS handles all UI rendering.
 */
export async function serveHitPage(c: Context<{ Bindings: Env }>) {
  const id = c.req.param('id');

  // Fetch HIT metadata for OG tags (best-effort — page works without it)
  let ogTitle = 'Robo — You\'ve been invited';
  let ogDescription = 'Someone sent you a request via Robo';
  let senderName = '';

  try {
    const hit = await c.env.DB.prepare('SELECT sender_name, recipient_name, task_description, hit_type, config FROM hits WHERE id = ?')
      .bind(id)
      .first<{ sender_name: string; recipient_name: string; task_description: string; hit_type: string; config: string | null }>();

    if (hit) {
      senderName = hit.sender_name || '';
      const recipientName = hit.recipient_name || '';
      const desc = hit.task_description || '';

      if (hit.hit_type === 'group_poll') {
        const config = hit.config ? JSON.parse(hit.config) : {};
        ogTitle = `${senderName} needs your help`;
        ogDescription = config.context || desc;
      } else if (hit.hit_type === 'availability') {
        const config = hit.config ? JSON.parse(hit.config) : {};
        const title = config.title || desc;
        ogTitle = `${senderName} is planning ${title}`;
        ogDescription = '';
      } else {
        ogTitle = `Hi ${recipientName} — ${senderName} wants you to test something`;
        ogDescription = `${senderName} assigned you a HIT (Human Intelligence Task). ${desc}`;
      }
    }
  } catch {
    // Use defaults — page still works via client-side fetch
  }

  const html = buildHitPageHtml(id, ogTitle, ogDescription);
  return c.html(html);
}

/**
 * Inline the full HIT page HTML.
 *
 * OG meta tags are injected server-side for link previews (iMessage, Slack, etc.).
 * All UI rendering happens client-side via the <script> block which fetches from /api/hits/:id.
 *
 * To update the page UI, edit this template. There is no separate static file —
 * this Worker IS the source of truth for /hit/:id pages.
 */
function buildHitPageHtml(hitId: string, ogTitle: string, ogDescription: string): string {
  const safeTitle = escapeHtml(ogTitle);
  const safeDesc = escapeHtml(ogDescription);

  return `<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>${safeTitle}</title>
  <meta name="description" content="${safeDesc}">

  <!-- OG / Social (must be in first 32KB for Slack) -->
  <meta property="og:type" content="website">
  <meta property="og:url" content="https://robo.app/hit/${escapeHtml(hitId)}">
  <meta property="og:title" content="${safeTitle}">
  <meta property="og:description" content="${safeDesc}">
  <meta property="og:image" content="https://robo.app/hit/${escapeHtml(hitId)}/og.png">
  <meta property="og:image:width" content="1200">
  <meta property="og:image:height" content="630">
  <meta property="og:site_name" content="ROBO.APP">
  <meta name="twitter:card" content="summary_large_image">
  <meta name="twitter:title" content="${safeTitle}">
  <meta name="twitter:description" content="${safeDesc}">
  <meta name="twitter:image" content="https://robo.app/hit/${escapeHtml(hitId)}/og.png">

  <meta name="theme-color" content="#06060a">
  <link rel="icon" type="image/svg+xml" href="https://robo.app/favicon.svg">
  <link rel="preconnect" href="https://fonts.googleapis.com">
  <link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
  <link href="https://fonts.googleapis.com/css2?family=JetBrains+Mono:wght@400;700;800&family=DM+Sans:wght@400;500;600&display=swap" rel="stylesheet">
  <style>
    *,*::before,*::after{margin:0;padding:0;box-sizing:border-box}
    :root {
      --blue: #2563EB; --blue-light: #3b82f6; --blue-glow: rgba(37,99,235,0.35);
      --blue-dim: rgba(37,99,235,0.12); --green: #22c55e; --green-dim: rgba(34,197,94,0.12);
      --green-border: rgba(34,197,94,0.3); --bg: #06060a; --surface: #0d0d14;
      --surface-raised: #12121c; --border: rgba(255,255,255,0.06);
      --border-accent: rgba(37,99,235,0.2); --text: #e2e2e8; --text-dim: #6b6b7b;
      --text-muted: #3d3d4d;
    }
    html { scroll-behavior:smooth }
    body { background:var(--bg); color:var(--text); font-family:'DM Sans',system-ui,sans-serif;
      min-height:100vh; display:flex; flex-direction:column; align-items:center;
      overflow-x:hidden; position:relative; }
    body::before { content:''; position:fixed; inset:0;
      background-image:radial-gradient(circle,rgba(255,255,255,0.03) 1px,transparent 1px);
      background-size:24px 24px; pointer-events:none; z-index:0; }
    body::after { content:''; position:fixed; top:-30%; left:50%; transform:translateX(-50%);
      width:500px; height:500px; background:radial-gradient(circle,var(--blue-glow) 0%,transparent 70%);
      filter:blur(80px); pointer-events:none; z-index:0; animation:pulse 6s ease-in-out infinite; }
    @keyframes pulse { 0%,100%{opacity:0.4;transform:translateX(-50%) scale(1)} 50%{opacity:0.6;transform:translateX(-50%) scale(1.1)} }
    .container { position:relative; z-index:1; display:flex; flex-direction:column;
      align-items:center; padding:2.5rem 1.5rem 3rem; max-width:520px; width:100%; }
    .fi { opacity:0; transform:translateY(14px); animation:fadeUp 0.6s ease-out forwards; }
    .fi:nth-child(1){animation-delay:0.05s} .fi:nth-child(2){animation-delay:0.12s}
    .fi:nth-child(3){animation-delay:0.19s} .fi:nth-child(4){animation-delay:0.26s}
    .fi:nth-child(5){animation-delay:0.33s} .fi:nth-child(6){animation-delay:0.4s}
    .fi:nth-child(7){animation-delay:0.47s} .fi:nth-child(8){animation-delay:0.54s}
    .top-bar { display:flex; align-items:center; gap:10px; align-self:flex-start; margin-bottom:1rem; }
    .top-bar svg { width:40px; height:40px; filter:drop-shadow(0 0 16px var(--blue-glow)); }
    .top-bar .brand { font-family:'JetBrains Mono',monospace; font-weight:800; font-size:1.1rem; color:#fff; letter-spacing:0.04em; }
    .top-bar .brand .dot { color:var(--blue-light); }
    .hero { align-self:flex-start; margin-bottom:1.75rem; width:100%; }
    .greeting { font-family:'DM Sans',system-ui,sans-serif; font-size:3rem; font-weight:600; color:#fff; line-height:1.1; letter-spacing:-0.02em; margin-bottom:0.35rem; }
    .greeting .name { color:var(--blue-light); }
    .subtitle { font-family:'DM Sans',system-ui,sans-serif; font-size:1.5rem; font-weight:500; color:var(--text-dim); line-height:1.3; }
    .subtitle .sender { color:var(--text); }
    .task-card { width:100%; background:var(--surface); border:1px solid var(--border-accent); border-radius:16px;
      padding:1.25rem 1.35rem; margin-bottom:0.75rem; position:relative; overflow:hidden; }
    .task-card::before { content:''; position:absolute; top:0; left:0; right:0; height:1px;
      background:linear-gradient(90deg,transparent,var(--blue),transparent); opacity:0.4; }
    .task-header { display:flex; align-items:center; gap:14px; margin-bottom:0.85rem; }
    .task-icon { width:44px; height:44px; background:var(--blue-dim); border-radius:12px;
      display:flex; align-items:center; justify-content:center; flex-shrink:0; }
    .task-icon svg { width:22px; height:22px; stroke:var(--blue-light); }
    .task-title { font-family:'JetBrains Mono',monospace; font-size:1rem; font-weight:700; color:var(--text); letter-spacing:0.01em; line-height:1.3; }
    .task-meta { display:flex; align-items:center; gap:10px; margin-top:4px; }
    .task-pill { font-family:'JetBrains Mono',monospace; font-size:0.62rem; font-weight:700; letter-spacing:0.08em;
      text-transform:uppercase; color:var(--blue-light); background:var(--blue-dim);
      border:1px solid rgba(37,99,235,0.3); border-radius:100px; padding:3px 10px; }
    .task-desc { font-size:0.9rem; color:var(--text-dim); line-height:1.55; }
    .loading { text-align:center; padding:4rem 1rem; }
    .loading .spinner { width:32px; height:32px; border:3px solid var(--border);
      border-top-color:var(--blue); border-radius:50%; animation:spin 0.8s linear infinite; margin:0 auto 1rem; }
    @keyframes spin { to { transform:rotate(360deg); } }
    .loading-text { font-family:'JetBrains Mono',monospace; font-size:0.8rem; color:var(--text-dim); }
    .error { text-align:center; padding:4rem 1rem; }
    .error-title { font-family:'JetBrains Mono',monospace; font-size:1.2rem; font-weight:700; color:var(--text); margin-bottom:0.5rem; }
    .error-msg { font-size:0.9rem; color:var(--text-dim); }
    .hit-header { align-self:flex-start; margin-bottom:1.75rem; width:100%; }
    .hit-greeting { font-size:1.3rem; font-weight:500; color:var(--text); margin-bottom:0.5rem; line-height:1.3; }
    .hit-description { font-size:1rem; color:var(--text-dim); line-height:1.5; }
    .name-section { width:100%; margin-bottom:1.5rem; }
    .name-label { font-family:'JetBrains Mono',monospace; font-size:0.7rem; font-weight:700;
      letter-spacing:0.08em; text-transform:uppercase; color:var(--text-dim); margin-bottom:0.5rem; display:block; }
    .name-input { width:100%; padding:0.75rem 1rem; background:var(--surface); border:1px solid var(--border);
      border-radius:10px; color:var(--text); font-family:'DM Sans',system-ui,sans-serif; font-size:1rem; outline:none; transition:border-color 0.2s; }
    .name-input:focus { border-color:var(--blue); }
    .name-input::placeholder { color:var(--text-muted); }
    .availability-section { width:100%; margin-bottom:2rem; }
    .section-label { font-family:'JetBrains Mono',monospace; font-size:0.7rem; font-weight:700;
      letter-spacing:0.08em; text-transform:uppercase; color:var(--text-dim); margin-bottom:0.75rem; display:block; }
    .day-grid { display:flex; flex-direction:column; gap:0.5rem; }
    .day-row { display:flex; align-items:center; gap:0.5rem; }
    .day-label { font-family:'JetBrains Mono',monospace; font-size:0.72rem; font-weight:700;
      color:var(--text-dim); min-width:5.5rem; text-align:right; }
    .time-slots { display:flex; gap:0.35rem; flex:1; }
    .time-slot { flex:1; padding:0.5rem 0.25rem; background:var(--surface); border:1px solid var(--border);
      border-radius:8px; font-family:'JetBrains Mono',monospace; font-size:0.6rem; font-weight:700;
      color:var(--text-muted); text-align:center; cursor:pointer; transition:all 0.15s ease;
      user-select:none; -webkit-tap-highlight-color:transparent; }
    .time-slot:hover { border-color:var(--border-accent); color:var(--text-dim); }
    .time-slot.selected { background:var(--green-dim); border-color:var(--green-border); color:var(--green); }
    .submit-btn { width:100%; padding:0.85rem; background:var(--blue); border:none; border-radius:10px;
      font-family:'JetBrains Mono',monospace; font-size:0.85rem; font-weight:700; letter-spacing:0.02em;
      color:#fff; cursor:pointer; transition:all 0.15s ease; margin-bottom:1rem; }
    .submit-btn:hover:not(:disabled) { background:var(--blue-light); }
    .submit-btn:disabled { opacity:0.4; cursor:not-allowed; }
    .submit-btn.submitting { opacity:0.7; }
    .success { text-align:center; padding:2rem 0; animation:fadeUp 0.5s ease-out; }
    .success-icon { font-size:3rem; margin-bottom:1rem; }
    .success-title { font-family:'JetBrains Mono',monospace; font-size:1.1rem; font-weight:700; color:var(--green); margin-bottom:0.5rem; }
    .success-msg { font-size:0.95rem; color:var(--text-dim); line-height:1.5; }
    @keyframes fadeUp { from { opacity:0; transform:translateY(12px); } to { opacity:1; transform:translateY(0); } }
    .hit-footer { margin-top:2rem; text-align:center; }
    .hit-footer a { font-family:'JetBrains Mono',monospace; font-size:0.65rem; color:var(--text-muted);
      text-decoration:none; letter-spacing:0.04em; transition:color 0.2s; }
    .hit-footer a:hover { color:var(--blue-light); }
    .name-picker { display:flex; flex-direction:column; gap:0.4rem; }
    .name-option { display:flex; align-items:center; gap:0.75rem; padding:0.7rem 1rem; background:var(--surface);
      border:1px solid var(--border); border-radius:10px; cursor:pointer; transition:all 0.15s ease;
      user-select:none; -webkit-tap-highlight-color:transparent; }
    .name-option:hover:not(.voted) { border-color:var(--border-accent); }
    .name-option:has(input:checked) { background:var(--blue-dim); border-color:var(--blue); }
    .name-option input[type="radio"] { accent-color:var(--blue); width:18px; height:18px; }
    .name-option-label { font-size:1rem; color:var(--text); }
    .name-option.voted { opacity:0.5; cursor:not-allowed; }
    .voted-badge { margin-left:auto; font-family:'JetBrains Mono',monospace; font-size:0.6rem;
      font-weight:700; color:var(--green); text-transform:uppercase; letter-spacing:0.05em; }
    @media (min-width:640px) {
      .container { padding:3.5rem 2rem 4rem; }
      .greeting { font-size:3.5rem; }
      .subtitle { font-size:1.65rem; }
      .top-bar svg { width:48px; height:48px; }
      .top-bar .brand { font-size:1.25rem; }
    }
    @media (max-width:420px) {
      .time-slot { font-size:0.55rem; padding:0.4rem 0.15rem; }
      .day-label { min-width:2.8rem; font-size:0.65rem; }
    }
  </style>
</head>
<body>
  <main class="container" id="app">
    <div class="loading" id="loading-state">
      <div class="spinner"></div>
      <p class="loading-text">Loading...</p>
    </div>
  </main>
<script>
(function() {
  var API_BASE = 'https://api.robo.app';
  var app = document.getElementById('app');
  var hitId = '${escapeJs(hitId)}';

  var topBar = '<div class="top-bar fi"><svg viewBox="0 0 120 120" fill="none" xmlns="http://www.w3.org/2000/svg"><rect width="120" height="120" rx="28" fill="#2563EB"/><circle cx="42" cy="48" r="14" fill="white"/><circle cx="78" cy="48" r="14" fill="white"/><circle cx="42" cy="48" r="7" fill="#1a4fc0"/><circle cx="78" cy="48" r="7" fill="#1a4fc0"/><path d="M 34 80 Q 60 102 86 80" fill="none" stroke="white" stroke-width="8" stroke-linecap="round"/></svg><div><span class="brand">ROBO<span class="dot">.</span>APP</span></div></div>';

  if (!hitId) { showError('Invalid link', 'This HIT link appears to be broken.'); return; }

  fetch(API_BASE + '/api/hits/' + hitId)
    .then(function(res) { if (!res.ok) throw new Error('HIT not found'); return res.json(); })
    .then(function(hit) { renderHit(hit); })
    .catch(function() { showError('Not found', 'This link may have expired or been completed.'); });

  function showError(title, msg) {
    app.innerHTML = '<div class="error"><p class="error-title">' + title + '</p><p class="error-msg">' + msg + '</p></div>';
  }

  function renderHit(hit) {
    if (hit.status === 'completed') {
      app.innerHTML = topBar +
        '<div class="success fi"><div class="success-icon">&#10003;</div>' +
        '<p class="success-title">This request has been completed</p>' +
        '<p class="success-msg">Thanks for checking — ' + esc(hit.sender_name) + ' already has what they need.</p></div>' +
        '<div class="hit-footer fi"><a href="https://robo.app">Powered by Robo</a></div>';
      return;
    }
    if (hit.hit_type === 'group_poll') { renderGroupPoll(hit); }
    else if (hit.hit_type === 'availability') { renderAvailability(hit); }
    else { renderGenericHit(hit); }
  }

  function renderGroupPoll(hit) {
    var config = hit.config ? (typeof hit.config === 'string' ? JSON.parse(hit.config) : hit.config) : {};
    var title = config.title || hit.task_description;
    var participants = config.participants || [];
    var dateOptions = config.date_options || [];
    var context = config.context || title;

    fetch(API_BASE + '/api/hits/' + hitId + '/responses')
      .then(function(res) { return res.json(); })
      .then(function(data) { renderGroupPollUI(hit, participants, dateOptions, context, data.responses || []); })
      .catch(function() { renderGroupPollUI(hit, participants, dateOptions, context, []); });
  }

  function renderGroupPollUI(hit, participants, dateOptions, context, existingResponses) {
    var respondedNames = {};
    existingResponses.forEach(function(r) { respondedNames[r.respondent_name] = true; });

    var html = topBar +
      '<div class="hero fi"><h1 class="greeting">Hi there,</h1>' +
      '<p class="subtitle"><span class="sender">' + esc(hit.sender_name) + '</span> needs your help</p></div>';

    html += '<div class="task-card fi"><div class="task-header"><div class="task-icon">' +
      '<svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M17 21v-2a4 4 0 0 0-4-4H5a4 4 0 0 0-4 4v2"/><circle cx="9" cy="7" r="4"/><path d="M23 21v-2a4 4 0 0 0-3-3.87"/><path d="M16 3.13a4 4 0 0 1 0 7.75"/></svg>' +
      '</div><div><div class="task-title">' + esc(context) + '</div>' +
      '<div class="task-meta"><span class="task-pill">Group Poll</span></div></div></div></div>';

    html += '<div class="name-section fi"><span class="name-label">Who are you?</span><div class="name-picker" id="name-picker">';
    if (participants.length > 0) {
      participants.forEach(function(name) {
        var voted = respondedNames[name];
        html += '<label class="name-option' + (voted ? ' voted' : '') + '">' +
          '<input type="radio" name="participant" value="' + esc(name) + '"' + (voted ? ' disabled' : '') + '>' +
          '<span class="name-option-label">' + esc(name) + '</span>' +
          (voted ? '<span class="voted-badge">Voted</span>' : '') + '</label>';
      });
    } else {
      html += '<input class="name-input" id="poll-name-input" type="text" placeholder="Enter your name" style="width:100%;padding:0.75rem;border:1px solid var(--border);border-radius:0.5rem;font-size:0.95rem;background:var(--bg);color:var(--text);">';
    }
    html += '</div></div>';

    if (dateOptions.length > 0) {
      html += '<div class="availability-section fi"><span class="section-label">Which dates work for you?</span>' +
        '<div class="day-grid" id="date-grid">';
      dateOptions.forEach(function(isoDate) {
        var d = new Date(isoDate + 'T12:00:00');
        var label = d.toLocaleDateString('en-US', { weekday:'short', month:'short', day:'numeric' });
        html += '<div class="day-row"><div class="time-slots">' +
          '<div class="time-slot date-option" data-date="' + isoDate + '" style="flex:1;padding:0.75rem;font-size:0.75rem;">' + label + '</div>' +
          '</div></div>';
      });
      html += '</div></div>';
    }

    html += '<div class="name-section fi"><label class="name-label" for="poll-notes-input">Anything to add?</label>' +
      '<textarea class="name-input" id="poll-notes-input" placeholder="Additional context..." rows="2" style="resize:vertical;font-family:inherit;"></textarea></div>';
    html += '<button class="submit-btn fi" id="submit-btn" disabled>Pick your name, then vote</button>';
    html += '<div id="result-area"></div>';
    html += '<div class="hit-footer fi"><a href="https://robo.app">Powered by Robo</a></div>';
    app.innerHTML = html;

    var selectedName = null;
    var selectedDates = {};
    document.querySelectorAll('#name-picker input[type="radio"]').forEach(function(input) {
      input.addEventListener('change', function() {
        selectedName = this.value;
        updateBtn();
        var dg = document.getElementById('date-grid');
        if (dg) dg.scrollIntoView({ behavior:'smooth', block:'start' });
      });
    });
    var pollNameInput = document.getElementById('poll-name-input');
    if (pollNameInput) {
      pollNameInput.addEventListener('input', function() {
        selectedName = this.value.trim() || null;
        updateBtn();
      });
    }

    var dateGrid = document.getElementById('date-grid');
    if (dateGrid) {
      dateGrid.addEventListener('click', function(e) {
        var slot = e.target.closest('.date-option');
        if (!slot) return;
        var date = slot.dataset.date;
        if (selectedDates[date]) { delete selectedDates[date]; slot.classList.remove('selected'); }
        else { selectedDates[date] = true; slot.classList.add('selected'); }
        updateBtn();
      });
    }

    var submitBtn = document.getElementById('submit-btn');
    function updateBtn() {
      var n = Object.keys(selectedDates).length;
      if (selectedName && n > 0) { submitBtn.disabled = false; submitBtn.textContent = 'Submit vote (' + n + ' date' + (n > 1 ? 's' : '') + ')'; }
      else if (selectedName) { submitBtn.disabled = true; submitBtn.textContent = 'Select at least one date'; }
      else { submitBtn.disabled = true; submitBtn.textContent = 'Pick your name, then vote'; }
    }

    function gpShowSuccess(title, msg) {
      submitBtn.style.display = 'none';
      var sections = document.querySelectorAll('.availability-section, .name-section, .task-card');
      for (var i = 0; i < sections.length; i++) sections[i].style.display = 'none';
      document.getElementById('result-area').innerHTML =
        '<div class="success"><div class="success-icon">&#10003;</div>' +
        '<p class="success-title">' + title + '</p>' +
        '<p class="success-msg">' + msg + '</p></div>';
      window.scrollTo({ top: 0, behavior: 'smooth' });
    }

    submitBtn.addEventListener('click', function() {
      if (submitBtn.disabled) return;
      submitBtn.disabled = true; submitBtn.classList.add('submitting'); submitBtn.textContent = 'Submitting...';
      fetch(API_BASE + '/api/hits/' + hitId + '/respond', {
        method:'POST', headers:{'Content-Type':'application/json'},
        body: JSON.stringify({ respondent_name: selectedName, response_data: (function() { var d = { selected_dates: Object.keys(selectedDates) }; var n = (document.getElementById('poll-notes-input').value || '').trim(); if (n) d.notes = n; return d; })() })
      })
      .then(function(res) { if (res.status === 409) throw new Error('already_responded'); if (!res.ok) throw new Error('fail'); return res.json(); })
      .then(function() {
        gpShowSuccess('Thank you!', 'This has been sent to ' + esc(hit.sender_name) + '.');
      })
      .catch(function(err) {
        if (err.message === 'already_responded') {
          gpShowSuccess('Already voted!', 'Your response was already submitted.');
        } else { submitBtn.disabled = false; submitBtn.classList.remove('submitting'); submitBtn.textContent = 'Error — tap to retry'; }
      });
    });
  }

  function renderAvailability(hit) {
    var config = hit.config ? (typeof hit.config === 'string' ? JSON.parse(hit.config) : hit.config) : {};
    var participants = config.participants || [];

    if (participants.length > 0) {
      fetch(API_BASE + '/api/hits/' + hitId + '/responses')
        .then(function(res) { return res.json(); })
        .then(function(data) { renderAvailabilityUI(hit, config, data.responses || []); })
        .catch(function() { renderAvailabilityUI(hit, config, []); });
    } else {
      renderAvailabilityUI(hit, config, []);
    }
  }

  function renderAvailabilityUI(hit, config, existingResponses) {
    var title = config.title || hit.task_description;
    var participants = config.participants || [];
    var timeSlots = config.time_slots || [];
    // Normalize military time (e.g. "19:00" → "7 PM")
    timeSlots = timeSlots.map(function(t) {
      var m = t.match(/^(\d{1,2}):(\d{2})$/);
      if (m) { var h = parseInt(m[1],10); var suffix = h >= 12 ? 'PM' : 'AM'; if (h > 12) h -= 12; if (h === 0) h = 12; return h + ' ' + suffix; }
      return t;
    });
    var days = [];
    if (config.date_options && config.date_options.length > 0) {
      config.date_options.forEach(function(opt) {
        if (opt.indexOf(':') > -1) {
          var parts = opt.split(':');
          var d1 = new Date(parts[0] + 'T12:00:00');
          var d2 = new Date(parts[1] + 'T12:00:00');
          var label = d1.toLocaleDateString('en-US',{month:'short',day:'numeric'}) + '-' + d2.getDate();
          days.push({ label: label, short: label, date: opt });
        } else {
          var d = new Date(opt + 'T12:00:00');
          days.push({ label: d.toLocaleDateString('en-US',{weekday:'short',month:'short',day:'numeric'}),
            short: d.toLocaleDateString('en-US',{weekday:'short',month:'short',day:'numeric'}), date: opt });
        }
      });
    } else {
      for (var i = 0; i < (config.days||5); i++) {
        var d = new Date(); d.setDate(d.getDate()+i+1);
        days.push({ label: d.toLocaleDateString('en-US',{weekday:'short',month:'short',day:'numeric'}),
          short: d.toLocaleDateString('en-US',{weekday:'short'}), date: d.toISOString().split('T')[0] });
      }
    }

    var respondedNames = {};
    existingResponses.forEach(function(r) { respondedNames[r.respondent_name] = true; });

    var html = topBar +
      '<div class="hero fi"><h1 class="greeting">Hi!</h1>' +
      '<p class="subtitle"><span class="sender">' + esc(hit.sender_name) + '</span> is planning ' + esc(title) + '</p></div>';
    html += '<div class="task-card fi"><div class="task-header"><div class="task-icon">' +
      '<svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><rect x="3" y="4" width="18" height="18" rx="2" ry="2"/><line x1="16" y1="2" x2="16" y2="6"/><line x1="8" y1="2" x2="8" y2="6"/><line x1="3" y1="10" x2="21" y2="10"/></svg>' +
      '</div><div><div class="task-title">' + esc(title) + '</div>' +
      '<div class="task-meta"><span class="task-pill">Availability</span></div></div></div></div>';

    if (participants.length > 0) {
      html += '<div class="name-section fi"><span class="name-label">Who are you?</span><div class="name-picker" id="avail-name-picker">';
      participants.forEach(function(name) {
        var voted = respondedNames[name];
        html += '<label class="name-option' + (voted ? ' voted' : '') + '">' +
          '<input type="radio" name="avail-participant" value="' + esc(name) + '"' + (voted ? ' disabled' : '') + '>' +
          '<span class="name-option-label">' + esc(name) + '</span>' +
          (voted ? '<span class="voted-badge">Voted &#10003;</span>' : '') + '</label>';
      });
      html += '</div></div>';
    } else {
      html += '<div class="name-section fi"><label class="name-label" for="name-input">Your name</label>' +
        '<input class="name-input" id="name-input" type="text" placeholder="' + esc(hit.recipient_name) + '" value="' + esc(hit.recipient_name) + '"></div>';
    }

    var dateOnly = timeSlots.length === 0;
    html += '<div class="availability-section fi"><span class="section-label">When are you free?</span><div class="day-grid" id="day-grid">';
    if (dateOnly) {
      days.forEach(function(day) {
        html += '<div class="day-row"><div class="time-slots">' +
          '<div class="time-slot date-option" data-day="' + day.date + '" data-time="all-day" style="flex:1;padding:0.75rem;font-size:0.75rem;">' + day.label + '</div>' +
          '</div></div>';
      });
    } else {
      days.forEach(function(day) {
        html += '<div class="day-row"><span class="day-label">' + day.short + '</span><div class="time-slots">';
        timeSlots.forEach(function(time) { html += '<div class="time-slot" data-day="' + day.date + '" data-time="' + time + '">' + time + '</div>'; });
        html += '</div></div>';
      });
    }
    html += '</div></div>';
    html += '<div class="name-section fi"><label class="name-label" for="notes-input">Anything to add?</label>' +
      '<textarea class="name-input" id="notes-input" placeholder="Additional context..." rows="2" style="resize:vertical;font-family:inherit;"></textarea></div>';

    var hasParticipants = participants.length > 0;
    var defaultBtnText = hasParticipants ? 'Pick your name, then select dates' : (dateOnly ? 'Select dates, then submit' : 'Select times, then submit');
    html += '<button class="submit-btn fi" id="submit-btn" disabled>' + defaultBtnText + '</button>';
    html += '<div id="result-area"></div>';
    html += '<div class="hit-footer fi"><a href="https://robo.app">Powered by Robo</a></div>';
    app.innerHTML = html;

    var selectedName = null;
    var selectedSlots = {};

    if (hasParticipants) {
      document.querySelectorAll('#avail-name-picker input[type="radio"]').forEach(function(input) {
        input.addEventListener('change', function() {
          selectedName = this.value;
          updSlots();
          var dg = document.getElementById('day-grid');
          if (dg) dg.scrollIntoView({ behavior:'smooth', block:'start' });
        });
      });
    }

    document.getElementById('day-grid').addEventListener('click', function(e) {
      var slot = e.target.closest('.time-slot'); if (!slot) return;
      var key = slot.dataset.day + '|' + slot.dataset.time;
      if (selectedSlots[key]) { delete selectedSlots[key]; slot.classList.remove('selected'); }
      else { selectedSlots[key] = true; slot.classList.add('selected'); }
      updSlots();
    });
    var submitBtn = document.getElementById('submit-btn');
    function updSlots() {
      var n = Object.keys(selectedSlots).length;
      var unit = dateOnly ? 'date' : 'time';
      if (hasParticipants) {
        if (selectedName && n > 0) { submitBtn.disabled = false; submitBtn.textContent = 'Submit ' + n + ' ' + unit + (n>1?'s':''); }
        else if (selectedName) { submitBtn.disabled = true; submitBtn.textContent = 'Select at least one ' + unit; }
        else { submitBtn.disabled = true; submitBtn.textContent = 'Pick your name, then select ' + unit + 's'; }
      } else {
        submitBtn.disabled = n === 0;
        submitBtn.textContent = n > 0 ? 'Submit ' + n + ' ' + unit + (n>1?'s':'') : (dateOnly ? 'Select dates, then submit' : 'Select times, then submit');
      }
    }
    function showSuccess(title, msg) {
      // Hide all form elements, show only success
      submitBtn.style.display = 'none';
      var sections = document.querySelectorAll('.availability-section, .name-section, .task-card');
      for (var i = 0; i < sections.length; i++) sections[i].style.display = 'none';
      // Also hide any extra name-section (notes field)
      var allNameSections = document.querySelectorAll('.name-section');
      for (var j = 0; j < allNameSections.length; j++) allNameSections[j].style.display = 'none';
      document.getElementById('result-area').innerHTML =
        '<div class="success"><div class="success-icon">&#10003;</div>' +
        '<p class="success-title">' + title + '</p>' +
        '<p class="success-msg">' + msg + '</p></div>';
      window.scrollTo({ top: 0, behavior: 'smooth' });
    }

    submitBtn.addEventListener('click', function() {
      if (submitBtn.disabled) return;
      var name;
      if (hasParticipants) {
        name = selectedName;
        if (respondedNames[name]) {
          document.getElementById('result-area').innerHTML =
            '<div class="success"><div class="success-icon">&#10003;</div>' +
            '<p class="success-title">Already responded!</p>' +
            '<p class="success-msg">You\\'ve already submitted your availability.</p></div>';
          return;
        }
      } else {
        name = document.getElementById('name-input').value.trim() || hit.recipient_name;
      }
      submitBtn.disabled = true; submitBtn.classList.add('submitting'); submitBtn.textContent = 'Submitting...';
      var slots = Object.keys(selectedSlots).map(function(k) { var p=k.split('|'); return {date:p[0],time:p[1]}; });
      var notes = (document.getElementById('notes-input').value || '').trim();
      var responseData = { available_slots: slots };
      if (notes) responseData.notes = notes;
      fetch(API_BASE + '/api/hits/' + hitId + '/respond', {
        method:'POST', headers:{'Content-Type':'application/json'},
        body: JSON.stringify({ respondent_name: name, response_data: responseData })
      })
      .then(function(res) { if (res.status === 409) throw new Error('already_responded'); if (!res.ok) throw new Error('fail'); return res.json(); })
      .then(function() {
        showSuccess('Thank you!', 'This has been sent to ' + esc(hit.sender_name) + '.');
      })
      .catch(function(err) {
        if (err.message === 'already_responded') {
          showSuccess('Already responded!', 'Your availability was already submitted.');
        } else { submitBtn.disabled=false; submitBtn.classList.remove('submitting'); submitBtn.textContent='Error — tap to retry'; }
      });
    });
  }

  function renderGenericHit(hit) {
    var html = topBar +
      '<div class="hero fi"><h1 class="greeting">Hi <span class="name">' + esc(hit.recipient_name) + '</span>,</h1>' +
      '<p class="subtitle"><span class="sender">' + esc(hit.sender_name) + '</span> sent you a request</p></div>';
    html += '<div class="task-card fi"><div class="task-header"><div class="task-icon">' +
      '<svg viewBox="0 0 24 24" fill="none" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"><path d="M14.5 4h-5L7 7H4a2 2 0 0 0-2 2v9a2 2 0 0 0 2 2h16a2 2 0 0 0 2-2V9a2 2 0 0 0-2-2h-3l-2.5-3z"/><circle cx="12" cy="13" r="3"/></svg>' +
      '</div><div><div class="task-title">' + esc(hit.task_description) + '</div>' +
      '<div class="task-meta"><span class="task-pill">Photo</span>';
    if (hit.agent_name) html += '<span style="font-family:\\'JetBrains Mono\\',monospace;font-size:0.72rem;color:var(--text-muted);">via ' + esc(hit.agent_name) + '</span>';
    html += '</div></div></div></div>';
    html += '<p class="fi" style="font-size:0.85rem;color:var(--text-dim);text-align:center;">Photo upload is available in the Robo app.</p>';
    html += '<div class="hit-footer fi"><a href="https://robo.app">Get Robo</a></div>';
    app.innerHTML = html;
  }

  function esc(str) { if (!str) return ''; var d=document.createElement('div'); d.textContent=str; return d.innerHTML; }
})();
</script>
</body>
</html>`;
}
