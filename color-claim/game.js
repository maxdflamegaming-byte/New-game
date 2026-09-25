'use strict';

// ---------- Canvas setup ----------
const canvas = document.getElementById('game');
const ctx = canvas.getContext('2d');
let W = 0, H = 0, BASE_CELL = 16, CELL = 16;

function resize() {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  W = window.innerWidth;
  H = window.innerHeight;
  canvas.width = W * dpr;
  canvas.height = H * dpr;
  canvas.style.width = W + 'px';
  canvas.style.height = H + 'px';
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
  BASE_CELL = Math.max(10, Math.min(18, Math.min(W, H) / 38));
}
window.addEventListener('resize', resize);
resize();

// ---------- Helpers ----------
const $ = id => document.getElementById(id);
const TAU = Math.PI * 2;
const rand = (a, b) => a + Math.random() * (b - a);
const randInt = (a, b) => Math.floor(rand(a, b + 1));
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
const escapeHtml = s => s.replace(/[&<>"']/g, c => `&#${c.charCodeAt(0)};`);

function shade(hex, amt) {
  const n = parseInt(hex.slice(1), 16);
  const f = c => clamp(Math.round(c * (1 + amt)), 0, 255);
  return `rgb(${f(n >> 16)}, ${f((n >> 8) & 255)}, ${f(n & 255)})`;
}
function alpha(hex, a) {
  const n = parseInt(hex.slice(1), 16);
  return `rgba(${n >> 16}, ${(n >> 8) & 255}, ${n & 255}, ${a})`;
}

function load(key, fallback) {
  try { const v = localStorage.getItem(key); return v === null ? fallback : v; } catch { return fallback; }
}
function save(key, value) {
  try { localStorage.setItem(key, String(value)); } catch { /* storage unavailable */ }
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
let best = Number(load('color-claim-best', 0)) || 0;
let myColor = clamp(Number(load('color-claim-color', 0)) || 0, 0, COLORS.length - 1);
let myName = load('color-claim-name', '');
let particles = [], flashes = [], fades = [], floats = [], feed = [];
let peakPct = 0, minimapTimer = 0, time = 0, shake = 0, danger = 0, wasInDanger = false;
const cam = { x: N / 2, y: N / 2, zoom: 1 };

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
    wp: [], mode: 'idle', think: 0, blink: rand(1, 4), squash: 0,
    // Bot personality: how greedy, how aggressive, how big their loops are
    greed: rand(25, 60), aggro: rand(0.1, 0.5), loopScale: rand(0.8, 1.5),
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
  const cells = [];
  for (let dy = -3; dy <= 3; dy++) {
    for (let dx = -3; dx <= 3; dx++) {
      if (dx * dx + dy * dy <= 7) {
        const i = (by + dy) * N + bx + dx;
        setOwner(i, p.id);
        cells.push(i);
      }
    }
  }
  flashes.push({ cells, life: 0.45 });
  p.x = bx + 0.5;
  p.y = by + 0.5;
  p.cx = bx;
  p.cy = by;
  p.angle = p.desired = Math.random() * TAU;
  p.alive = true;
  p.trail = [];
  p.wp = [];
  p.mode = 'idle';
  p.think = rand(0.2, 1);
  p.squash = 1;
}

function kill(victim, killer, how = 'cut') {
  if (!victim.alive) return;
  victim.alive = false;
  const lost = [];
  for (const i of victim.trail) if (trail[i] === victim.id) { trail[i] = 0; lost.push(i); }
  victim.trail = [];
  for (let i = 0; i < N * N; i++) if (owner[i] === victim.id) { setOwner(i, 0); lost.push(i); }
  fades.push({ cells: lost, color: victim.color, life: 0.7 });
  burst(victim.x, victim.y, victim.color, 40, 12);
  victim.respawn = 3;

  if (killer && killer !== victim) killer.kills++;
  if (killer === victim) addFeed(`💥 ${victim.name} crossed their own trail`);
  else if (how === 'swallow') addFeed(`🍽️ ${killer.name} swallowed ${victim.name}`);
  else addFeed(`✂️ ${killer.name} cut ${victim.name}`);

  if (victim === me) {
    shake = 1;
    Sfx.play('death');
    const reason = killer === me ? 'You crossed your own trail!'
      : how === 'swallow' ? `${killer.name} swallowed all your land!` : `${killer.name} cut your trail!`;
    setTimeout(() => endGame(false, reason), 900);
  } else if (killer === me) {
    toast(`You knocked out ${victim.name}!`);
    Sfx.play('cut');
    shake = 0.4;
  }
}

// ---------- Capturing land ----------
function capture(p) {
  const gained = [];
  for (const i of p.trail) {
    if (trail[i] === p.id) trail[i] = 0;
    if (owner[i] !== p.id) gained.push(i);
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
  for (let i = 0; i < N * N; i++) {
    if (!seen[i] && owner[i] !== p.id) {
      setOwner(i, p.id);
      gained.push(i);
    }
  }
  flashes.push({ cells: gained, life: 0.45 });

  // Anyone who lost all their land is out
  for (const o of players) if (o && o !== p && o.alive && counts[o.id] === 0) kill(o, p, 'swallow');

  if (p === me && gained.length) {
    const gainPct = (gained.length / (N * N)) * 100;
    if (gainPct >= 0.1) floats.push({ x: p.x, y: p.y - 3, text: `+${gainPct.toFixed(1)}%`, life: 1.2, big: gainPct > 3 });
    burst(p.x, p.y, p.color, Math.min(40, 8 + gained.length / 10), 8);
    Sfx.play('capture');
  }
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
  const turn = clamp(diff, -TURN * dt, TURN * dt);
  p.angle += turn;
  // Squash a little while turning hard, spring back when going straight
  const turning = dt > 0 ? Math.abs(turn) / (TURN * dt) : 0;
  p.squash += (turning * 0.5 - p.squash) * Math.min(1, dt * 10);
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
  const a = Math.random() * TAU;
  const len = rand(5, 11 + Math.min(10, counts[p.id] / 60)) * p.loopScale;
  const wid = rand(4, 10) * p.loopScale * (Math.random() < 0.5 ? -1 : 1);
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
    if (threat || p.trail.length > p.greed) {
      p.wp = [nearestOwn(p)];
      p.mode = 'flee';
      return;
    }
  }

  // Hunt: go for a nearby enemy trail
  if (p.mode !== 'flee' && p.mode !== 'hunt' && p.trail.length < 25) {
    for (const o of players) {
      if (!o || o === p || !o.alive || o.trail.length < 4) continue;
      if (dist(o, p) < 14 && Math.random() < p.aggro) {
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
  if (e.target.tagName === 'INPUT' && k !== 'enter') return;
  keys.add(k);
  Sfx.unlock();
  if (k.startsWith('arrow') || 'wasd'.includes(k)) mouse.active = false;
  if ((k === 'p' || k === 'escape') && (state === 'play' || state === 'paused')) togglePause();
  if (k === 'm') toggleMute();
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
  Sfx.unlock();
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
    // Steer toward the mouse, measured from where your square is drawn
    const hx = (me.x - cam.x) * CELL + W / 2, hy = (me.y - cam.y) * CELL + H / 2;
    const dx = mouse.x - hx, dy = mouse.y - hy;
    if (Math.hypot(dx, dy) > CELL) { x = dx; y = dy; }
  }
  if (x || y) me.desired = Math.atan2(y, x);
}

// ---------- Menu customisation ----------
function buildSwatches() {
  const box = $('swatches');
  box.innerHTML = '';
  COLORS.forEach((c, i) => {
    const b = document.createElement('button');
    b.className = 'swatch' + (i === myColor ? ' picked' : '');
    b.style.background = c;
    b.setAttribute('aria-label', `Color ${i + 1}`);
    b.addEventListener('click', () => {
      myColor = i;
      save('color-claim-color', i);
      buildSwatches();
    });
    box.appendChild(b);
  });
  $('play-btn').style.background = COLORS[myColor];
  $('play-btn').style.boxShadow = `0 5px 0 ${shade(COLORS[myColor], -0.3)}`;
}

$('name-input').value = myName;
$('name-input').addEventListener('input', e => {
  myName = e.target.value.trim().slice(0, 12);
  save('color-claim-name', myName);
});

// ---------- Game flow ----------
function startGame() {
  owner.fill(0);
  trail.fill(0);
  counts.fill(0);
  particles = [];
  flashes = [];
  fades = [];
  floats = [];
  feed = [];
  renderFeed();
  rgbCache.length = 0;
  players = [null];
  me = makePlayer(1, myName || 'You', COLORS[myColor], false);
  players.push(me);
  const botColors = COLORS.filter((_, i) => i !== myColor);
  BOT_NAMES.forEach((name, i) => players.push(makePlayer(i + 2, name, botColors[i], true)));
  spawn(me, N / 2, N / 2);
  for (const p of players) if (p && p.isBot) spawn(p);
  cam.x = me.x;
  cam.y = me.y;
  cam.zoom = 1;
  peakPct = 0;
  time = 0;
  shake = 0;
  stick.active = false;
  $('name-input').blur();
  state = 'play';
  showScreen(null);
}

function togglePause() {
  state = state === 'play' ? 'paused' : 'play';
  showScreen(state === 'paused' ? 'paused' : null);
}

function toggleMute() {
  $('mute-btn').textContent = Sfx.toggle() ? '🔇' : '🔊';
}

function endGame(won, reason) {
  if (state === 'over' || state === 'menu') return;
  state = 'over';
  const score = Math.round(peakPct * 10) / 10;
  const isBest = score > best;
  if (isBest) { best = score; save('color-claim-best', best); }
  $('over-title').textContent = won ? '🏆 You win!' : 'Game Over';
  $('over-reason').textContent = reason;
  $('over-stats').textContent = `Best size: ${score.toFixed(1)}% · ${me.kills} knockouts`;
  $('over-best').textContent = isBest ? 'New personal best!' : `Personal best: ${best.toFixed(1)}%`;
  showScreen('over');
}

function win() {
  state = 'won';
  Sfx.play('win');
  for (let i = 0; i < 6; i++) burst(me.x + rand(-8, 8), me.y + rand(-6, 6), COLORS[i], 30, 14);
  setTimeout(() => endGame(true, `You claimed ${WIN_PCT}% of the map!`), 1600);
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
  el.classList.remove('show');
  void el.offsetWidth; // restart the pop animation
  el.classList.add('show');
  clearTimeout(toastTimeout);
  toastTimeout = setTimeout(() => el.classList.remove('show'), 1400);
}

function addFeed(text) {
  feed.unshift({ text, life: 4 });
  if (feed.length > 4) feed.pop();
  renderFeed();
}

function renderFeed() {
  $('feed').innerHTML = feed.map(f => `<li style="opacity:${Math.min(1, f.life).toFixed(2)}">${escapeHtml(f.text)}</li>`).join('');
}

function burst(x, y, color, n, speed = 9) {
  for (let i = 0; i < n; i++) {
    const a = Math.random() * TAU, s = rand(speed * 0.2, speed);
    particles.push({
      x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s - 3,
      life: rand(0.5, 1), rot: rand(0, TAU), spin: rand(-10, 10), size: rand(0.3, 0.6), color,
    });
  }
}

// ---------- Update ----------
let feedTimer = 0;
function update(dt) {
  time += dt;
  if (state === 'play' && me.alive) steerHuman();
  for (const p of players) {
    if (!p) continue;
    if (!p.alive) {
      if (p.isBot) {
        p.respawn -= dt;
        if (p.respawn <= 0) spawn(p);
      }
      continue;
    }
    p.blink -= dt;
    if (p.blink < -0.12) p.blink = rand(2, 5);
    if (p.isBot) steerBot(p, dt);
    if (p !== me || state === 'play') move(p, dt);
  }

  // Danger: is an enemy close to your exposed trail?
  danger = 0;
  if (me.alive && me.trail.length) {
    for (const o of players) {
      if (!o || o === me || !o.alive) continue;
      for (let k = 0; k < me.trail.length; k += 2) {
        const i = me.trail[k], tx = (i % N) + 0.5, ty = Math.floor(i / N) + 0.5;
        const d = Math.hypot(o.x - tx, o.y - ty);
        if (d < 7) danger = Math.max(danger, 1 - d / 7);
      }
    }
  }
  if (danger > 0.3 && !wasInDanger) Sfx.play('warn');
  wasInDanger = danger > 0.3;

  for (const pt of particles) {
    pt.x += pt.vx * dt;
    pt.y += pt.vy * dt;
    pt.vy += 12 * dt;
    pt.vx *= 0.96;
    pt.rot += pt.spin * dt;
    pt.life -= dt;
  }
  particles = particles.filter(pt => pt.life > 0);
  for (const f of flashes) f.life -= dt;
  flashes = flashes.filter(f => f.life > 0);
  for (const f of fades) f.life -= dt;
  fades = fades.filter(f => f.life > 0);
  for (const f of floats) { f.life -= dt; f.y -= dt * 1.5; }
  floats = floats.filter(f => f.life > 0);
  for (const f of feed) f.life -= dt;
  feedTimer -= dt;
  if (feedTimer <= 0 && feed.length) {
    feed = feed.filter(f => f.life > 0);
    renderFeed();
    feedTimer = 0.1;
  }
  shake = Math.max(0, shake - dt * 2);

  if (me.alive && state === 'play') {
    peakPct = Math.max(peakPct, pct(me));
    if (pct(me) >= WIN_PCT) win();
  }

  // Camera glides after you and zooms out as your land grows
  const k = Math.min(1, dt * 6);
  cam.x += (me.x - cam.x) * k;
  cam.y += (me.y - cam.y) * k;
  const targetZoom = 1 - Math.min(0.35, pct(me) / 80);
  cam.zoom += (targetZoom - cam.zoom) * Math.min(1, dt * 2);
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
function drawRuns(grid, c0, c1, r0, r1, x0, y0, colorOf, yOffset) {
  for (let r = r0; r <= r1; r++) {
    let c = c0;
    while (c <= c1) {
      const id = grid[r * N + c];
      if (!id) { c++; continue; }
      let e = c;
      while (e + 1 <= c1 && grid[r * N + e + 1] === id) e++;
      ctx.fillStyle = colorOf(players[id]);
      ctx.fillRect(Math.floor(c * CELL - x0), Math.floor(r * CELL - y0 + yOffset), Math.ceil((e - c + 1) * CELL), Math.ceil(CELL));
      c = e + 1;
    }
  }
}

function forCellsInView(cells, c0, c1, r0, r1, fn) {
  for (const i of cells) {
    const x = i % N, y = (i - x) / N;
    if (x >= c0 && x <= c1 && y >= r0 && y <= r1) fn(x, y);
  }
}

function drawHead(p, x0, y0, leaderId) {
  const hx = p.x * CELL - x0, hy = p.y * CELL - y0;
  if (hx < -60 || hy < -60 || hx > W + 60 || hy > H + 60) return;
  const s = CELL * 1.4;
  const bob = Math.sin(time * 12 + p.id) * CELL * 0.06;

  // Soft shadow on the ground
  ctx.fillStyle = 'rgba(38, 48, 74, 0.18)';
  ctx.beginPath();
  ctx.ellipse(hx, hy + s * 0.55, s * 0.6, s * 0.2, 0, 0, TAU);
  ctx.fill();

  ctx.save();
  ctx.translate(hx, hy + bob);
  ctx.rotate(p.angle);
  ctx.scale(1 + p.squash * 0.15, 1 - p.squash * 0.15);
  ctx.fillStyle = p.dark;
  ctx.fillRect(-s / 2, -s / 2 + CELL * 0.25, s, s);
  ctx.fillStyle = p.color;
  ctx.fillRect(-s / 2, -s / 2, s, s);
  ctx.fillStyle = 'rgba(255, 255, 255, 0.25)';
  ctx.fillRect(-s / 2, -s / 2, s, s * 0.22);

  const closed = p.blink < 0;
  for (const side of [-1, 1]) {
    ctx.fillStyle = '#fff';
    ctx.beginPath();
    if (closed) ctx.ellipse(s * 0.18, side * s * 0.2, s * 0.04, s * 0.14, 0, 0, TAU);
    else ctx.arc(s * 0.18, side * s * 0.2, s * 0.14, 0, TAU);
    ctx.fill();
    if (!closed) {
      ctx.fillStyle = '#26304a';
      ctx.beginPath();
      ctx.arc(s * 0.24, side * s * 0.2, s * 0.07, 0, TAU);
      ctx.fill();
    }
  }
  ctx.restore();

  ctx.textAlign = 'center';
  ctx.font = `bold ${Math.round(CELL * 0.8)}px system-ui, sans-serif`;
  ctx.lineWidth = 3;
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.8)';
  ctx.strokeText(p.name, hx, hy - s * 0.85 + bob);
  ctx.fillStyle = 'rgba(38, 48, 74, 0.9)';
  ctx.fillText(p.name, hx, hy - s * 0.85 + bob);
  if (p.id === leaderId) {
    ctx.font = `${Math.round(CELL * 1.1)}px system-ui, sans-serif`;
    ctx.fillStyle = '#ffb84d';
    ctx.fillText('👑', hx, hy - s * 1.6 + bob + Math.sin(time * 4) * 2);
  }
}

function draw(dt) {
  ctx.fillStyle = '#cfd6e4';
  ctx.fillRect(0, 0, W, H);

  if (!me) {
    drawMenuBackdrop(dt);
    return;
  }

  CELL = BASE_CELL * cam.zoom;
  const sh = shake * CELL * 0.6;
  const x0 = cam.x * CELL - W / 2 + rand(-sh, sh), y0 = cam.y * CELL - H / 2 + rand(-sh, sh);

  // Map floor: a raised board with a soft checker pattern
  ctx.fillStyle = '#aab4c8';
  ctx.fillRect(-x0 - 4, -y0 - 4 + CELL * 0.5, N * CELL + 8, N * CELL + 8);
  ctx.fillStyle = '#f5f7fc';
  ctx.fillRect(-x0, -y0, N * CELL, N * CELL);
  const c0 = clamp(Math.floor(x0 / CELL), 0, N - 1), c1 = clamp(Math.floor((x0 + W) / CELL), 0, N - 1);
  const r0 = clamp(Math.floor(y0 / CELL), 0, N - 1), r1 = clamp(Math.floor((y0 + H) / CELL), 0, N - 1);
  ctx.fillStyle = '#edf0f8';
  for (let r = r0; r <= r1; r++) {
    for (let c = c0 + ((r + c0) % 2); c <= c1; c += 2) {
      ctx.fillRect(Math.floor(c * CELL - x0), Math.floor(r * CELL - y0), Math.ceil(CELL), Math.ceil(CELL));
    }
  }

  // Land: a darker copy nudged down gives a chunky 3D edge, then the top colour
  drawRuns(owner, c0, c1, r0, r1, x0, y0, p => p.dark, CELL * 0.3);
  drawRuns(owner, c0, c1, r0, r1, x0, y0, p => p.color, 0);

  // Land of knocked-out players shrinks away
  for (const f of fades) {
    const t = f.life / 0.7, s = CELL * t;
    ctx.globalAlpha = t;
    ctx.fillStyle = f.color;
    forCellsInView(f.cells, c0, c1, r0, r1, (x, y) => {
      ctx.fillRect(x * CELL - x0 + (CELL - s) / 2, y * CELL - y0 + (CELL - s) / 2, s, s);
    });
  }
  ctx.globalAlpha = 1;

  // Trails (yours pulses red when an enemy is close to it)
  const dangerColor = `rgba(255, 60, 80, ${0.35 + danger * 0.4 * (0.5 + 0.5 * Math.sin(time * 18))})`;
  drawRuns(trail, c0, c1, r0, r1, x0, y0, p => (p === me && danger > 0 ? dangerColor : p.trailColor), 0);

  // Freshly claimed land flashes white
  for (const f of flashes) {
    ctx.fillStyle = `rgba(255, 255, 255, ${(f.life / 0.45) * 0.6})`;
    forCellsInView(f.cells, c0, c1, r0, r1, (x, y) => {
      ctx.fillRect(Math.floor(x * CELL - x0), Math.floor(y * CELL - y0), Math.ceil(CELL), Math.ceil(CELL));
    });
  }

  // Players (you are drawn last so you're always on top)
  let leader = null;
  for (const p of players) if (p && p.alive && (!leader || counts[p.id] > counts[leader.id])) leader = p;
  const leaderId = leader && leader.id;
  for (const p of players) if (p && p.alive && p !== me) drawHead(p, x0, y0, leaderId);
  if (me.alive) drawHead(me, x0, y0, leaderId);

  // Confetti particles
  for (const pt of particles) {
    ctx.globalAlpha = Math.min(1, pt.life * 2);
    ctx.fillStyle = pt.color;
    const s = CELL * pt.size;
    ctx.save();
    ctx.translate(pt.x * CELL - x0, pt.y * CELL - y0);
    ctx.rotate(pt.rot);
    ctx.fillRect(-s / 2, -s / 2, s, s);
    ctx.restore();
  }
  ctx.globalAlpha = 1;

  // Floating "+x%" text
  ctx.textAlign = 'center';
  for (const f of floats) {
    const pop = 1 + Math.max(0, f.life - 1) * 3;
    ctx.globalAlpha = Math.min(1, f.life * 2);
    ctx.font = `900 ${Math.round(CELL * (f.big ? 1.8 : 1.3) * pop)}px system-ui, sans-serif`;
    ctx.lineWidth = 4;
    ctx.strokeStyle = me.dark;
    ctx.strokeText(f.text, f.x * CELL - x0, f.y * CELL - y0);
    ctx.fillStyle = '#fff';
    ctx.fillText(f.text, f.x * CELL - x0, f.y * CELL - y0);
  }
  ctx.globalAlpha = 1;

  // Danger warning: red glow around the screen edge
  if (danger > 0.3) {
    const a = danger * 0.35 * (0.6 + 0.4 * Math.sin(time * 18));
    const grad = ctx.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.35, W / 2, H / 2, Math.max(W, H) * 0.75);
    grad.addColorStop(0, 'rgba(255, 60, 80, 0)');
    grad.addColorStop(1, `rgba(255, 60, 80, ${a})`);
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, W, H);
  }

  // Touch joystick
  if (stick.active && state === 'play') {
    ctx.strokeStyle = 'rgba(38, 48, 74, 0.3)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(stick.ox, stick.oy, 50, 0, TAU);
    ctx.stroke();
    const dx = stick.x - stick.ox, dy = stick.y - stick.oy, d = Math.hypot(dx, dy);
    const m = d > 50 ? 50 / d : 1;
    ctx.fillStyle = 'rgba(38, 48, 74, 0.3)';
    ctx.beginPath();
    ctx.arc(stick.ox + dx * m, stick.oy + dy * m, 20, 0, TAU);
    ctx.fill();
  }

  // Minimap
  minimapTimer -= dt;
  if (minimapTimer <= 0) { updateMinimap(); minimapTimer = 0.25; }
  const ms = Math.min(130, W * 0.28), mx = 16, my = H - ms - 16;
  ctx.fillStyle = 'rgba(255, 255, 255, 0.7)';
  ctx.fillRect(mx - 4, my - 4, ms + 8, ms + 8);
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(mini, mx, my, ms, ms);
  ctx.strokeStyle = '#26304a';
  ctx.lineWidth = 1;
  ctx.strokeRect(mx + (x0 / CELL / N) * ms, my + (y0 / CELL / N) * ms, (W / CELL / N) * ms, (H / CELL / N) * ms);
  if (me.alive) {
    ctx.fillStyle = '#fff';
    ctx.strokeStyle = me.dark;
    ctx.beginPath();
    ctx.arc(mx + (me.x / N) * ms, my + (me.y / N) * ms, 3 + Math.sin(time * 6), 0, TAU);
    ctx.fill();
    ctx.stroke();
  }
}

// Menu backdrop: floating coloured blocks
const menuBlocks = Array.from({ length: 26 }, (_, i) => ({
  x: Math.random(), y: Math.random(), s: rand(20, 60), c: COLORS[i % COLORS.length], v: rand(0.02, 0.06), r: rand(0, TAU),
}));
function drawMenuBackdrop(dt) {
  for (const b of menuBlocks) {
    b.y -= b.v * dt;
    b.r += 0.3 * dt;
    if (b.y < -0.1) { b.y = 1.1; b.x = Math.random(); }
    ctx.save();
    ctx.translate(b.x * W, b.y * H);
    ctx.rotate(b.r);
    ctx.fillStyle = shade(b.c, -0.28);
    ctx.fillRect(-b.s / 2, -b.s / 2 + b.s * 0.15, b.s, b.s);
    ctx.fillStyle = b.c;
    ctx.fillRect(-b.s / 2, -b.s / 2, b.s, b.s);
    ctx.restore();
  }
}

function updateHud() {
  $('pct').textContent = `${pct(me).toFixed(1)}%`;
  $('kills').textContent = `${me.kills} knockouts`;
  $('goal-fill').style.width = `${Math.min(100, (pct(me) / WIN_PCT) * 100)}%`;
  $('goal-fill').style.background = me.color;
  const ranked = players.filter(p => p && p.alive).sort((a, b) => counts[b.id] - counts[a.id]);
  const top = ranked.slice(0, 5);
  if (me.alive && !top.includes(me)) top.push(me);
  $('board').innerHTML = top.map(p =>
    `<li class="${p === me ? 'me' : ''}"><span><span class="dot" style="background:${p.color}"></span>${ranked.indexOf(p) + 1}. ${escapeHtml(p.name)}</span><span>${pct(p).toFixed(1)}%</span></li>`
  ).join('');
}

// ---------- Main loop ----------
let last = performance.now();
let hudTimer = 0;
function frame(now) {
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  if (state === 'play' || state === 'won') update(dt);
  // Behind the pause / game over screens the last frame stays frozen
  if (state !== 'over' && state !== 'paused') draw(dt);
  hudTimer -= dt;
  if (me && state !== 'menu' && hudTimer <= 0) { updateHud(); hudTimer = 0.2; }
  requestAnimationFrame(frame);
}

$('play-btn').addEventListener('click', () => { if (state === 'menu') startGame(); });
$('again-btn').addEventListener('click', () => { if (state === 'over') startGame(); });
$('menu-btn').addEventListener('click', () => {
  if (state !== 'over') return;
  state = 'menu';
  me = null;
  showScreen('menu');
});
$('resume-btn').addEventListener('click', () => { if (state === 'paused') togglePause(); });
$('mute-btn').addEventListener('click', toggleMute);
$('mute-btn').textContent = Sfx.muted ? '🔇' : '🔊';

buildSwatches();
showScreen('menu');
requestAnimationFrame(frame);
