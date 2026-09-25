'use strict';

// ---------- Canvas setup ----------
const canvas = document.getElementById('game');
const ctx = canvas.getContext('2d');
let W = 0, H = 0, CELL = 16;

function resize() {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  W = window.innerWidth;
  H = window.innerHeight;
  canvas.width = W * dpr;
  canvas.height = H * dpr;
  canvas.style.width = W + 'px';
  canvas.style.height = H + 'px';
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  CELL = Math.max(10, Math.min(18, Math.min(W, H) / 38));
}
window.addEventListener('resize', resize);
resize();

// ---------- Helpers ----------
const $ = id => document.getElementById(id);
const rand = (a, b) => a + Math.random() * (b - a);
const randInt = (a, b) => Math.floor(rand(a, b + 1));
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);

function shade(hex, amt) {
  const n = parseInt(hex.slice(1), 16);
  const f = c => clamp(Math.round(c * (1 + amt)), 0, 255);
  return `rgb(${f(n >> 16)}, ${f((n >> 8) & 255)}, ${f(n & 255)})`;
}
function alpha(hex, a) {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${n >> 16}, ${(n >> 8) & 255}, ${n & 255}, ${a})`;
}

function loadBest() {
  try { return Number(localStorage.getItem('color-claim-best')) || 0; } catch { return 0; }
}
function saveBest(v) {
  try { localStorage.setItem('color-claim-best', String(v)); } catch { /* storage unavailable */ }
}

// ---------- World ----------
const N = 80;                         // map is N x N cells
const WIN_PCT = 50;
const owner = new Uint8Array(N * N);  // which player owns each cell (0 = nobody)
const trail = new Uint8Array(N * N);  // whose trail is on each cell (0 = none)
const seen = new Uint8Array(N * N);   // scratch buffer for flood fill
const counts = new Int32Array(16);    // cells owned per player id

const COLORS = ['#4f8cff', '#ff5d73', '#ffb84d', '#2ec4b6', '#b06bff', '#ff7ac6', '#8bd346', '#ff8c42'];
const BOT_NAMES = ['Mango', 'Zigzag', 'Pixel', 'Turbo', 'Luna', 'Nacho', 'Bloop'];
const SPEED = 7.5;    // cells per second
const TURN = 5.5;     // radians per second

let players = [];     // players[id], id starts at 1
let me = null;
let state = 'menu';
let best = loadBest();
let particles = [];
let peakPct = 0;
let minimapTimer = 0;

function pct(p) { return (counts[p.id] / (N * N)) * 100; }

function setOwner(i, id) {
  const prev = owner[i];
  if (prev === id) return;
  if (prev) counts[prev]--;
  owner[i] = id;
  if (id) counts[id]++;
}

// ---------- Players ----------
function makePlayer(id, name, color, isBot) {
  return {
    id, name, color, isBot,
    dark: shade(color, -0.28),
    trailColor: alpha(color, 0.45),
    x: 0, y: 0, cx: 0, cy: 0, angle: 0, desired: 0,
    alive: false, trail: [], kills: 0, respawn: 0,
    wp: [], mode: 'idle', think: 0,
  };
}

function spawn(p, fx, fy) {
  let bx = fx, by = fy;
  if (bx === undefined) {
    let bestScore = Infinity;
    for (let t = 0; t < 40; t++) {
      const x = randInt(6, N - 7), y = randInt(6, N - 7);
      let score = 0;
      for (let dy = -5; dy <= 5; dy++) for (let dx = -5; dx <= 5; dx++) if (owner[(y + dy) * N + x + dx]) score++;
      for (const o of players) if (o && o.alive && Math.hypot(o.x - x, o.y - y) < 12) score += 100;
      if (score < bestScore) { bestScore = score; bx = x; by = y; }
    }
  }
  for (let dy = -3; dy <= 3; dy++) {
    for (let dx = -3; dx <= 3; dx++) {
      if (dx * dx + dy * dy <= 7) setOwner((by + dy) * N + bx + dx, p.id);
    }
  }
  p.x = bx + 0.5;
  p.y = by + 0.5;
  p.cx = bx;
  p.cy = by;
  p.angle = p.desired = Math.random() * Math.PI * 2;
  p.alive = true;
  p.trail = [];
  p.wp = [];
  p.mode = 'idle';
  p.think = rand(0.2, 1);
}

function kill(victim, killer) {
  if (!victim.alive) return;
  victim.alive = false;
  for (const i of victim.trail) if (trail[i] === victim.id) trail[i] = 0;
  victim.trail = [];
  for (let i = 0; i < N * N; i++) if (owner[i] === victim.id) setOwner(i, 0);
  burst(victim.x, victim.y, victim.color, 30);
  victim.respawn = 3;

  if (killer && killer !== victim) killer.kills++;
  if (victim === me) {
    const reason = !killer || killer === me ? 'You crossed your own trail!' : `${killer.name} cut your trail!`;
    setTimeout(() => endGame(false, reason), 700);
  } else if (killer === me) {
    toast(`You knocked out ${victim.name}!`);
  }
}

// ---------- Capturing land ----------
function capture(p) {
  for (const i of p.trail) {
    if (trail[i] === p.id) trail[i] = 0;
    setOwner(i, p.id);
  }
  p.trail = [];

  // Flood fill from the map edges through every cell that isn't ours.
  // Whatever the fill can't reach is enclosed by our land, so we claim it.
  seen.fill(0);
  const stack = [];
  const push = i => { if (!seen[i] && owner[i] !== p.id) { seen[i] = 1; stack.push(i); } };
  for (let k = 0; k < N; k++) {
    push(k);
    push((N - 1) * N + k);
    push(k * N);
    push(k * N + N - 1);
  }
  while (stack.length) {
    const i = stack.pop();
    const x = i % N, y = (i - x) / N;
    if (x > 0) push(i - 1);
    if (x < N - 1) push(i + 1);
    if (y > 0) push(i - N);
    if (y < N - 1) push(i + N);
  }
  const before = counts[p.id];
  for (let i = 0; i < N * N; i++) if (!seen[i] && owner[i] !== p.id) setOwner(i, p.id);

  // Anyone who lost all their land is out
  for (const o of players) if (o && o !== p && o.alive && counts[o.id] === 0) kill(o, p);

  if (p === me && counts[p.id] - before > 40) burst(p.x, p.y, p.color, 14);
  p.wp = [];
  p.mode = 'idle';
}

// ---------- Movement ----------
function visit(p, x, y) {
  const i = y * N + x;
  const t = trail[i];
  if (t) {
    const other = players[t];
    if (other === p) { kill(p, p); return; }
    kill(other, p);
  }
  if (owner[i] === p.id) {
    if (p.trail.length) capture(p);
  } else {
    trail[i] = p.id;
    p.trail.push(i);
  }
}

function move(p, dt) {
  let diff = p.desired - p.angle;
  diff = Math.atan2(Math.sin(diff), Math.cos(diff));
  p.angle += clamp(diff, -TURN * dt, TURN * dt);
  p.x = clamp(p.x + Math.cos(p.angle) * SPEED * dt, 0.01, N - 0.01);
  p.y = clamp(p.y + Math.sin(p.angle) * SPEED * dt, 0.01, N - 0.01);

  const cx = Math.floor(p.x), cy = Math.floor(p.y);
  if (cx === p.cx && cy === p.cy) return;
  // Diagonal step: also visit a corner cell so trails never have gaps to slip through
  if (cx !== p.cx && cy !== p.cy) {
    visit(p, cx, p.cy);
    if (!p.alive) return;
  }
  visit(p, cx, cy);
  p.cx = cx;
  p.cy = cy;
}

// ---------- Bot brains ----------
function nearestOwn(p) {
  for (let r = 0; r < N; r++) {
    for (let d = -r; d <= r; d++) {
      const cands = [[p.cx + d, p.cy - r], [p.cx + d, p.cy + r], [p.cx - r, p.cy + d], [p.cx + r, p.cy + d]];
      for (const [x, y] of cands) {
        if (x >= 0 && y >= 0 && x < N && y < N && owner[y * N + x] === p.id) return { x: x + 0.5, y: y + 0.5 };
      }
    }
  }
  return { x: p.x, y: p.y };
}

function planLoop(p) {
  const a = Math.random() * Math.PI * 2;
  const len = rand(5, 11 + Math.min(10, counts[p.id] / 60));
  const wid = rand(4, 10) * (Math.random() < 0.5 ? -1 : 1);
  const ax = p.x + Math.cos(a) * len, ay = p.y + Math.sin(a) * len;
  const bx = ax + Math.cos(a + Math.PI / 2) * wid, by = ay + Math.sin(a + Math.PI / 2) * wid;
  const c = v => clamp(v, 1.5, N - 1.5);
  p.wp = [{ x: c(ax), y: c(ay) }, { x: c(bx), y: c(by) }, { x: p.x, y: p.y }];
  p.mode = 'loop';
}

function think(p) {
  const outside = p.trail.length > 0;

  // Flee home if an enemy gets close while our trail is exposed, or if we got greedy
  if (outside && p.mode !== 'flee') {
    const threat = p.mode !== 'hunt' && players.some(o => o && o !== p && o.alive && dist(o, p) < 5);
    if (threat || p.trail.length > 45) {
      p.wp = [nearestOwn(p)];
      p.mode = 'flee';
      return;
    }
  }

  // Hunt: go for a nearby enemy trail
  if (p.mode !== 'flee' && p.mode !== 'hunt' && p.trail.length < 25) {
    for (const o of players) {
      if (!o || o === p || !o.alive || o.trail.length < 4) continue;
      if (dist(o, p) < 14 && Math.random() < 0.35) {
        const i = o.trail[Math.max(0, o.trail.length - 4)];
        const tx = i % N, ty = (i - tx) / N;
        p.wp = [{ x: tx + 0.5, y: ty + 0.5 }];
        p.mode = 'hunt';
        return;
      }
    }
  }

  if (!outside && p.wp.length === 0) planLoop(p);
}

function steerBot(p, dt) {
  p.think -= dt;
  if (p.think <= 0) {
    p.think = 0.25;
    think(p);
  }
  while (p.wp.length && dist(p, p.wp[0]) < 0.8) p.wp.shift();
  if (!p.wp.length && p.trail.length) {
    p.wp = [nearestOwn(p)];
    p.mode = 'flee';
  }
  if (p.wp.length) p.desired = Math.atan2(p.wp[0].y - p.y, p.wp[0].x - p.x);
}

// ---------- Human input ----------
const keys = new Set();
const stick = { active: false, id: null, ox: 0, oy: 0, x: 0, y: 0 };
const mouse = { active: false, x: 0, y: 0 };

window.addEventListener('keydown', e => {
  const k = e.key.toLowerCase();
  keys.add(k);
  if (k.startsWith('arrow') || 'wasd'.includes(k)) mouse.active = false;
  if ((k === 'p' || k === 'escape') && (state === 'play' || state === 'paused')) togglePause();
  if ((k === 'enter' || k === ' ') && (state === 'menu' || state === 'over')) {
    e.preventDefault();
    startGame();
  }
});
window.addEventListener('keyup', e => keys.delete(e.key.toLowerCase()));
window.addEventListener('blur', () => {
  keys.clear();
  stick.active = false;
  if (state === 'play') togglePause();
});

canvas.addEventListener('pointerdown', e => {
  if (state !== 'play' || e.pointerType === 'mouse') return;
  stick.active = true;
  stick.id = e.pointerId;
  stick.ox = stick.x = e.clientX;
  stick.oy = stick.y = e.clientY;
  canvas.setPointerCapture(e.pointerId);
});
canvas.addEventListener('pointermove', e => {
  if (e.pointerType === 'mouse') {
    mouse.active = true;
    mouse.x = e.clientX;
    mouse.y = e.clientY;
  } else if (stick.active && e.pointerId === stick.id) {
    stick.x = e.clientX;
    stick.y = e.clientY;
  }
});
const endStick = e => { if (e.pointerId === stick.id) stick.active = false; };
canvas.addEventListener('pointerup', endStick);
canvas.addEventListener('pointercancel', endStick);

function steerHuman() {
  let x = 0, y = 0;
  if (keys.has('a') || keys.has('arrowleft')) x -= 1;
  if (keys.has('d') || keys.has('arrowright')) x += 1;
  if (keys.has('w') || keys.has('arrowup')) y -= 1;
  if (keys.has('s') || keys.has('arrowdown')) y += 1;
  if (stick.active) {
    const dx = stick.x - stick.ox, dy = stick.y - stick.oy;
    if (Math.hypot(dx, dy) > 10) { x = dx; y = dy; }
  } else if (!x && !y && mouse.active) {
    const dx = mouse.x - W / 2, dy = mouse.y - H / 2;
    if (Math.hypot(dx, dy) > CELL) { x = dx; y = dy; }
  }
  if (x || y) me.desired = Math.atan2(y, x);
}

// ---------- Game flow ----------
function startGame() {
  owner.fill(0);
  trail.fill(0);
  counts.fill(0);
  particles = [];
  players = [null];
  me = makePlayer(1, 'You', COLORS[0], false);
  players.push(me);
  BOT_NAMES.forEach((name, i) => players.push(makePlayer(i + 2, name, COLORS[i + 1], true)));
  spawn(me, N / 2, N / 2);
  for (const p of players) if (p && p.isBot) spawn(p);
  peakPct = 0;
  stick.active = false;
  state = 'play';
  showScreen(null);
}

function togglePause() {
  state = state === 'play' ? 'paused' : 'play';
  showScreen(state === 'paused' ? 'paused' : null);
}

function endGame(won, reason) {
  if (state === 'over' || state === 'menu') return;
  state = 'over';
  const score = Math.round(peakPct * 10) / 10;
  const isBest = score > best;
  if (isBest) { best = score; saveBest(best); }
  $('over-title').textContent = won ? '🏆 You win!' : 'Game Over';
  $('over-reason').textContent = reason;
  $('over-stats').textContent = `Best size: ${score.toFixed(1)}% · ${me.kills} knockouts`;
  $('over-best').textContent = isBest ? 'New personal best!' : `Personal best: ${best.toFixed(1)}%`;
  showScreen('over');
}

function showScreen(id) {
  for (const el of document.querySelectorAll('.screen')) el.classList.toggle('show', el.id === id);
  $('hud').classList.toggle('hidden', state === 'menu' || state === 'over');
  $('menu-best').textContent = `${best.toFixed(1)}%`;
}

let toastTimeout;
function toast(text) {
  const el = $('toast');
  el.textContent = text;
  el.classList.add('show');
  clearTimeout(toastTimeout);
  toastTimeout = setTimeout(() => el.classList.remove('show'), 1400);
}

function burst(x, y, color, n) {
  for (let i = 0; i < n; i++) {
    const a = Math.random() * Math.PI * 2, s = rand(2, 9);
    particles.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: rand(0.4, 0.8), color });
  }
}

// ---------- Update ----------
function update(dt) {
  if (me.alive) steerHuman();
  for (const p of players) {
    if (!p) continue;
    if (!p.alive) {
      if (p.isBot) {
        p.respawn -= dt;
        if (p.respawn <= 0) spawn(p);
      }
      continue;
    }
    if (p.isBot) steerBot(p, dt);
    move(p, dt);
  }

  for (const pt of particles) {
    pt.x += pt.vx * dt;
    pt.y += pt.vy * dt;
    pt.vx *= 0.93;
    pt.vy *= 0.93;
    pt.life -= dt;
  }
  particles = particles.filter(pt => pt.life > 0);

  if (me.alive) {
    peakPct = Math.max(peakPct, pct(me));
    if (pct(me) >= WIN_PCT) endGame(true, `You claimed ${WIN_PCT}% of the map!`);
  }
}

// ---------- Drawing ----------
const mini = document.createElement('canvas');
mini.width = mini.height = N;
const miniCtx = mini.getContext('2d');
const miniImg = miniCtx.createImageData(N, N);
const rgbCache = [];

function rgbOf(id) {
  if (!rgbCache[id]) {
    const n = parseInt(players[id].color.slice(1), 16);
    rgbCache[id] = [n >> 16, (n >> 8) & 255, n & 255];
  }
  return rgbCache[id];
}

function updateMinimap() {
  const d = miniImg.data;
  for (let i = 0; i < N * N; i++) {
    const id = owner[i] || trail[i];
    const [r, g, b] = id ? rgbOf(id) : [245, 247, 252];
    d[i * 4] = r;
    d[i * 4 + 1] = g;
    d[i * 4 + 2] = b;
    d[i * 4 + 3] = id ? 255 : 220;
  }
  miniCtx.putImageData(miniImg, 0, 0);
}

// Draw horizontal runs of cells that share an owner (much faster than one rect per cell)
function drawRuns(grid, c0, c1, r0, r1, x0, y0, colorOf, yOffset, h) {
  for (let r = r0; r <= r1; r++) {
    let c = c0;
    while (c <= c1) {
      const id = grid[r * N + c];
      if (!id) { c++; continue; }
      let e = c;
      while (e + 1 <= c1 && grid[r * N + e + 1] === id) e++;
      ctx.fillStyle = colorOf(players[id]);
      ctx.fillRect(Math.floor(c * CELL - x0), Math.floor(r * CELL - y0 + yOffset), Math.ceil((e - c + 1) * CELL), Math.ceil(h));
      c = e + 1;
    }
  }
}

function draw(dt) {
  ctx.fillStyle = '#cfd6e4';
  ctx.fillRect(0, 0, W, H);
  if (!me) return;

  const x0 = me.x * CELL - W / 2, y0 = me.y * CELL - H / 2;

  // Map floor with a soft grid
  ctx.fillStyle = '#f5f7fc';
  ctx.fillRect(-x0, -y0, N * CELL, N * CELL);
  const c0 = clamp(Math.floor(x0 / CELL), 0, N - 1), c1 = clamp(Math.floor((x0 + W) / CELL), 0, N - 1);
  const r0 = clamp(Math.floor(y0 / CELL), 0, N - 1), r1 = clamp(Math.floor((y0 + H) / CELL), 0, N - 1);
  ctx.strokeStyle = 'rgba(40, 60, 120, 0.05)';
  ctx.lineWidth = 1;
  ctx.beginPath();
  for (let c = c0; c <= c1 + 1; c++) { const x = Math.floor(c * CELL - x0) + 0.5; ctx.moveTo(x, r0 * CELL - y0); ctx.lineTo(x, (r1 + 1) * CELL - y0); }
  for (let r = r0; r <= r1 + 1; r++) { const y = Math.floor(r * CELL - y0) + 0.5; ctx.moveTo(c0 * CELL - x0, y); ctx.lineTo((c1 + 1) * CELL - x0, y); }
  ctx.stroke();

  // Land: a darker copy nudged down gives a chunky 3D edge, then the top colour
  drawRuns(owner, c0, c1, r0, r1, x0, y0, p => p.dark, CELL * 0.3, CELL);
  drawRuns(owner, c0, c1, r0, r1, x0, y0, p => p.color, 0, CELL);
  drawRuns(trail, c0, c1, r0, r1, x0, y0, p => p.trailColor, 0, CELL);

  // Players
  ctx.textAlign = 'center';
  ctx.font = `bold ${Math.round(CELL * 0.8)}px system-ui, sans-serif`;
  for (const p of players) {
    if (!p || !p.alive) continue;
    const hx = p.x * CELL - x0, hy = p.y * CELL - y0;
    if (hx < -50 || hy < -50 || hx > W + 50 || hy > H + 50) continue;
    const s = CELL * 1.4;
    ctx.save();
    ctx.translate(hx, hy);
    ctx.rotate(p.angle);
    ctx.fillStyle = p.dark;
    ctx.fillRect(-s / 2, -s / 2 + CELL * 0.25, s, s);
    ctx.fillStyle = p.color;
    ctx.fillRect(-s / 2, -s / 2, s, s);
    ctx.fillStyle = '#fff';
    for (const side of [-1, 1]) {
      ctx.beginPath();
      ctx.arc(s * 0.18, side * s * 0.2, s * 0.14, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.fillStyle = '#26304a';
    for (const side of [-1, 1]) {
      ctx.beginPath();
      ctx.arc(s * 0.23, side * s * 0.2, s * 0.07, 0, Math.PI * 2);
      ctx.fill();
    }
    ctx.restore();
    ctx.fillStyle = 'rgba(38, 48, 74, 0.85)';
    ctx.fillText(p.name, hx, hy - s * 0.8);
  }

  // Particles
  for (const pt of particles) {
    ctx.globalAlpha = Math.min(1, pt.life * 2);
    ctx.fillStyle = pt.color;
    const s = CELL * 0.45;
    ctx.fillRect(pt.x * CELL - x0 - s / 2, pt.y * CELL - y0 - s / 2, s, s);
  }
  ctx.globalAlpha = 1;

  // Touch joystick
  if (stick.active && state === 'play') {
    ctx.strokeStyle = 'rgba(38, 48, 74, 0.3)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(stick.ox, stick.oy, 50, 0, Math.PI * 2);
    ctx.stroke();
    const dx = stick.x - stick.ox, dy = stick.y - stick.oy, d = Math.hypot(dx, dy);
    const m = d > 50 ? 50 / d : 1;
    ctx.fillStyle = 'rgba(38, 48, 74, 0.3)';
    ctx.beginPath();
    ctx.arc(stick.ox + dx * m, stick.oy + dy * m, 20, 0, Math.PI * 2);
    ctx.fill();
  }

  // Minimap
  minimapTimer -= dt;
  if (minimapTimer <= 0) { updateMinimap(); minimapTimer = 0.25; }
  const ms = Math.min(130, W * 0.28), mx = 16, my = H - ms - 16;
  ctx.fillStyle = 'rgba(255, 255, 255, 0.6)';
  ctx.fillRect(mx - 3, my - 3, ms + 6, ms + 6);
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(mini, mx, my, ms, ms);
  ctx.strokeStyle = '#26304a';
  ctx.strokeRect(mx + (x0 / CELL / N) * ms, my + (y0 / CELL / N) * ms, (W / CELL / N) * ms, (H / CELL / N) * ms);
}

function updateHud() {
  $('pct').textContent = `${pct(me).toFixed(1)}%`;
  $('kills').textContent = `${me.kills} knockouts`;
  const ranked = players.filter(p => p && p.alive).sort((a, b) => counts[b.id] - counts[a.id]);
  const top = ranked.slice(0, 5);
  if (me.alive && !top.includes(me)) top.push(me);
  $('board').innerHTML = top.map(p =>
    `<li class="${p === me ? 'me' : ''}"><span><span class="dot" style="background:${p.color}"></span>${ranked.indexOf(p) + 1}. ${p.name}</span><span>${pct(p).toFixed(1)}%</span></li>`
  ).join('');
}

// ---------- Main loop ----------
let last = performance.now();
let hudTimer = 0;
function frame(now) {
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  if (state === 'play') update(dt);
  draw(dt);
  hudTimer -= dt;
  if (me && state !== 'menu' && hudTimer <= 0) { updateHud(); hudTimer = 0.2; }
  requestAnimationFrame(frame);
}

$('play-btn').addEventListener('click', () => { if (state === 'menu') startGame(); });
$('again-btn').addEventListener('click', () => { if (state === 'over') startGame(); });
$('resume-btn').addEventListener('click', () => { if (state === 'paused') togglePause(); });

showScreen('menu');
requestAnimationFrame(frame);
