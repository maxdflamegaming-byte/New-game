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

// Skins change how a square looks. All but Classic are unlocked by playing.
const SKINS = [
  { id: 'classic', name: 'Classic' },
  { id: 'stripes', name: 'Stripes', need: { stat: 'games', n: 3, text: 'Play 3 games' } },
  { id: 'dots', name: 'Dots', need: { stat: 'bestPct', n: 10, text: 'Claim 10% in one game' } },
  { id: 'shades', name: 'Shades', need: { stat: 'kills', n: 3, text: 'Get 3 knockouts (total)' } },
  { id: 'cat', name: 'Cat', need: { stat: 'bestPct', n: 20, text: 'Claim 20% in one game' } },
  { id: 'confetti', name: 'Confetti', need: { stat: 'kills', n: 10, text: 'Get 10 knockouts (total)' } },
  { id: 'robot', name: 'Robot', need: { stat: 'games', n: 10, text: 'Play 10 games' } },
  { id: 'ninja', name: 'Ninja', need: { stat: 'wins', n: 1, text: 'Win a game' } },
  { id: 'rainbow', name: 'Rainbow', need: { stat: 'wins', n: 3, text: 'Win 3 games' } },
];

// Power-ups appear on the map; anyone (bots too) can grab them
const POWERUPS = {
  speed: { name: 'Speed', color: '#ffb84d', time: 4 },
  shield: { name: 'Shield', color: '#4f8cff', time: 6 },
  freeze: { name: 'Freeze', color: '#3fc7f5', time: 4 },
};
const MAX_POWERUPS = 4;
const SPAWN_SHIELD = 3; // seconds of protection after (re)spawning

let players = [];     // players[id], id starts at 1
let me = null;
let state = 'menu';
let best = Number(load('color-claim-best', 0)) || 0;
let myColor = clamp(Number(load('color-claim-color', 0)) || 0, 0, COLORS.length - 1);
let myName = load('color-claim-name', '');
let stats = { games: 0, kills: 0, wins: 0, bestPct: 0 };
try { Object.assign(stats, JSON.parse(load('color-claim-stats', '{}'))); } catch { /* bad saved data */ }
stats.bestPct = Math.max(stats.bestPct, best);
const isUnlocked = sk => !sk.need || stats[sk.need.stat] >= sk.need.n;
let mySkin = load('color-claim-skin', 'classic');
if (!SKINS.some(sk => sk.id === mySkin && isUnlocked(sk))) mySkin = 'classic';
let powerups = [], powerTimer = 5, freezer = null;
let particles = [], flashes = [], fades = [], floats = [], feed = [];
let peakPct = 0, minimapTimer = 0, time = 0, shake = 0, danger = 0, wasInDanger = false;
let countdown = 0, goFlash = 0, threats = [];
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
function makePlayer(id, name, color, isBot, skin) {
  return {
    id, name, color, isBot, skin, hueOff: rand(0, 360),
    fx: { speed: 0, shield: 0, freeze: 0 },
    dark: shade(color, -0.28),
    trailColor: alpha(color, 0.45),
    x: 0, y: 0, cx: 0, cy: 0, angle: 0, desired: 0,
    alive: false, trail: [], kills: 0, respawn: 0,
    wp: [], mode: 'idle', think: 0, blink: rand(1, 4), squash: 0,
    // Bot personality: how greedy, how aggressive, how big their loops are
    greed: rand(25, 60), aggro: rand(0.1, 0.5), loopScale: rand(0.8, 1.5),
  };
}

// Cells in the small starting disc around (x, y) that nobody owns and no trail crosses
function freeStartCells(x, y) {
  const cells = [];
  for (let dy = -3; dy <= 3; dy++) {
    for (let dx = -3; dx <= 3; dx++) {
      const i = (y + dy) * N + x + dx;
      if (dx * dx + dy * dy <= 7 && !owner[i] && !trail[i]) cells.push(i);
    }
  }
  return cells;
}

// Returns false if there was no free space; the bot then tries again a moment later.
// Spawning only ever claims empty cells, so it can never eat into someone else's land.
function spawn(p, fx, fy) {
  let bx = fx, by = fy;
  if (bx === undefined) {
    let bestScore = -Infinity;
    for (let t = 0; t < 60; t++) {
      const x = randInt(4, N - 5), y = randInt(4, N - 5);
      if (owner[y * N + x] || trail[y * N + x]) continue;
      let score = freeStartCells(x, y).length;
      for (const o of players) if (o && o !== p && o.alive && Math.hypot(o.x - x, o.y - y) < 10) score -= 30;
      if (score > bestScore) { bestScore = score; bx = x; by = y; }
    }
    if (bx === undefined || freeStartCells(bx, by).length < 5) {
      p.respawn = 1;
      return false;
    }
  }
  const cells = freeStartCells(bx, by);
  for (const i of cells) setOwner(i, p.id);
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
  p.route = null;
  p.squash = 1;
  p.fx = { speed: 0, shield: SPAWN_SHIELD, freeze: 0 };
  return true;
}

function kill(victim, killer, how = 'cut') {
  if (!victim.alive) return;
  // A shield stops other players cutting or bumping you. Your own mistakes still count,
  // and so does losing all your land.
  if (victim.fx.shield > 0 && killer !== victim && how !== 'swallow') return;
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
  else if (how === 'bump') addFeed(`💢 ${killer.name} bumped ${victim.name}`);
  else addFeed(`✂️ ${killer.name} cut ${victim.name}`);

  if (victim === me) {
    shake = 1;
    Sfx.play('death');
    const reason = killer === me ? 'You crossed your own trail!'
      : how === 'swallow' ? `${killer.name} swallowed all your land!`
      : how === 'bump' ? `You bumped into ${killer.name} outside your land!`
      : `${killer.name} cut your trail!`;
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
function speedOf(p) {
  let v = SPEED;
  if (p.fx.speed > 0) v *= 1.6;
  if (freezer && freezer !== p) v *= 0.5;
  return v;
}

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
  const v = speedOf(p);
  p.x = clamp(p.x + Math.cos(p.angle) * v * dt, 0.01, N - 0.01);
  p.y = clamp(p.y + Math.sin(p.angle) * v * dt, 0.01, N - 0.01);

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

function spawnPowerup() {
  const kinds = Object.keys(POWERUPS);
  for (let t = 0; t < 20; t++) {
    const x = randInt(3, N - 4), y = randInt(3, N - 4);
    if (powerups.some(pu => Math.hypot(pu.x - x, pu.y - y) < 10)) continue;
    powerups.push({ x: x + 0.5, y: y + 0.5, kind: kinds[randInt(0, kinds.length - 1)], age: 0 });
    return;
  }
}

function grabPowerup(p, pu) {
  const def = POWERUPS[pu.kind];
  p.fx[pu.kind] = def.time;
  burst(pu.x, pu.y, def.color, 16, 8);
  if (p === me) {
    toast(pu.kind === 'speed' ? 'Speed boost!' : pu.kind === 'shield' ? 'Shield! Nobody can cut your trail' : 'Freeze! Everyone else slows down');
    Sfx.play(pu.kind);
  } else if (pu.kind === 'freeze' && me.alive && dist(p, me) < 40) {
    toast(`${p.name} froze everyone!`);
    Sfx.play('freeze');
  }
}

function updatePowerups(dt) {
  powerTimer -= dt;
  if (powerTimer <= 0) {
    powerTimer = rand(6, 10);
    if (powerups.length < MAX_POWERUPS) spawnPowerup();
  }
  for (const pu of powerups) {
    pu.age += dt;
    for (const p of players) {
      if (p && p.alive && !pu.taken && Math.hypot(p.x - pu.x, p.y - pu.y) < 1.3) {
        pu.taken = true;
        grabPowerup(p, pu);
      }
    }
  }
  powerups = powerups.filter(pu => !pu.taken);
  freezer = null;
  for (const p of players) {
    if (!p || !p.alive) continue;
    for (const k in p.fx) p.fx[k] = Math.max(0, p.fx[k] - dt);
    if (p.fx.freeze > 0) freezer = p;
  }
}

// Two squares touching: whoever is safe on their own land wins. If both are outside,
// the one with the longer trail loses; equal trails knock both out.
function checkBumps() {
  for (let a = 1; a < players.length; a++) {
    for (let b = a + 1; b < players.length; b++) {
      const p = players[a], q = players[b];
      if (!p.alive || !q.alive || dist(p, q) > 0.9) continue;
      const pSafe = owner[p.cy * N + p.cx] === p.id, qSafe = owner[q.cy * N + q.cx] === q.id;
      if (pSafe && qSafe) continue;
      if (pSafe) kill(q, p, 'bump');
      else if (qSafe) kill(p, q, 'bump');
      else if (p.trail.length > q.trail.length) kill(p, q, 'bump');
      else if (q.trail.length > p.trail.length) kill(q, p, 'bump');
      else { kill(p, q, 'bump'); kill(q, p, 'bump'); }
    }
  }
}

// ---------- Bot pathfinding ----------
// Breadth-first search from a bot's head to its nearest own land that never steps on
// its own trail. The first pass also keeps a one-cell gap from the trail, because
// squares can't turn on the spot; if that finds nothing, a tighter path is used.
const bfsPrev = new Int32Array(N * N);
const bfsMark = new Uint32Array(N * N);
const bfsQueue = new Int32Array(N * N);
let bfsGen = 0;

function touchesOwnTrail(p, x, y) {
  const i = y * N + x;
  return (x > 0 && trail[i - 1] === p.id) || (x < N - 1 && trail[i + 1] === p.id) ||
    (y > 0 && trail[i - N] === p.id) || (y < N - 1 && trail[i + N] === p.id);
}

function bfsHome(p, padded) {
  bfsGen++;
  const start = p.cy * N + p.cx;
  let head = 0, tail = 0;
  bfsQueue[tail++] = start;
  bfsMark[start] = bfsGen;
  const step = (from, x, y) => {
    if (x < 0 || y < 0 || x >= N || y >= N) return;
    const j = y * N + x;
    if (bfsMark[j] === bfsGen || trail[j] === p.id) return;
    const nearHead = Math.abs(x - p.cx) <= 2 && Math.abs(y - p.cy) <= 2;
    if (padded && !nearHead && touchesOwnTrail(p, x, y)) return;
    bfsMark[j] = bfsGen;
    bfsPrev[j] = from;
    bfsQueue[tail++] = j;
  };
  while (head < tail) {
    const i = bfsQueue[head++];
    if (owner[i] === p.id) {
      const path = [];
      for (let c = i; c !== start; c = bfsPrev[c]) path.push(c);
      return path.reverse();
    }
    const x = i % N, y = (i - x) / N;
    step(i, x + 1, y);
    step(i, x - 1, y);
    step(i, x, y + 1);
    step(i, x, y - 1);
  }
  return null;
}

function routeHome(p) {
  return bfsHome(p, true) || bfsHome(p, false);
}

// Simulate the curve a square really drives (it can only turn so fast) while aiming at
// `desired`, and return how many steps it survives before touching its own trail.
function safeSteps(p, desired, steps = 10, dt = 0.05) {
  let x = p.x, y = p.y, a = p.angle, cx = p.cx, cy = p.cy;
  const v = speedOf(p);
  for (let k = 0; k < steps; k++) {
    let diff = Math.atan2(Math.sin(desired - a), Math.cos(desired - a));
    a += clamp(diff, -TURN * dt, TURN * dt);
    x = clamp(x + Math.cos(a) * v * dt, 0.01, N - 0.01);
    y = clamp(y + Math.sin(a) * v * dt, 0.01, N - 0.01);
    const nx = Math.floor(x), ny = Math.floor(y);
    if (nx === cx && ny === cy) continue;
    if (nx !== cx && ny !== cy && trail[cy * N + nx] === p.id) return k;
    if (trail[ny * N + nx] === p.id) return k;
    if (owner[ny * N + nx] === p.id) return steps; // made it home
    cx = nx;
    cy = ny;
  }
  return steps;
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
  p.wp = [{ x: c(ax), y: c(ay) }, { x: c(bx), y: c(by) }];
  p.mode = 'loop';
}

function think(p) {
  const outside = p.trail.length > 0;

  // Head home if an enemy gets close while our trail is exposed, or if we got greedy
  if (outside && p.mode !== 'home') {
    const threat = p.mode !== 'hunt' && players.some(o => o && o !== p && o.alive && dist(o, p) < 5);
    if (threat || p.trail.length > p.greed) {
      goHome(p);
      return;
    }
  }

  // Hunt: go for the closest part of a nearby enemy trail. The bigger you get,
  // the further bots look for your trail and the more often they come for it.
  if (p.mode !== 'home' && p.mode !== 'hunt' && p.trail.length < 25) {
    const growth = me && me.alive ? clamp(pct(me) / 30, 0, 1) : 0;
    for (const o of players) {
      if (!o || o === p || !o.alive || o.trail.length < 4 || o.fx.shield > 0) continue;
      const bold = o === me ? growth : 0;
      if (dist(o, p) < 14 + bold * 12 && Math.random() < p.aggro + bold * 0.4) {
        p.wp = [closestTrailPoint(p, o)];
        p.mode = 'hunt';
        return;
      }
    }
  }

  // At home: sometimes go and grab a nearby power-up
  if (!outside && p.mode !== 'grab') {
    const pu = powerups.find(q => Math.hypot(q.x - p.x, q.y - p.y) < 12);
    if (pu && Math.random() < 0.5) {
      p.wp = [{ x: pu.x, y: pu.y }];
      p.mode = 'grab';
      return;
    }
  }

  if (!outside && p.wp.length === 0) planLoop(p);
}

function closestTrailPoint(p, o) {
  let bestI = o.trail[0], bestD = Infinity;
  for (let k = 0; k < o.trail.length; k += 2) {
    const i = o.trail[k], x = (i % N) + 0.5, y = Math.floor(i / N) + 0.5;
    const d = (x - p.x) ** 2 + (y - p.y) ** 2;
    if (d < bestD) { bestD = d; bestI = i; }
  }
  return { x: (bestI % N) + 0.5, y: Math.floor(bestI / N) + 0.5 };
}

function goHome(p) {
  p.wp = [];
  p.mode = 'home';
  p.route = null;
}

function steerBot(p, dt) {
  p.think -= dt;
  if (p.think <= 0) {
    p.think = 0.25;
    think(p);
  }
  while (p.wp.length && dist(p, p.wp[0]) < 0.8) p.wp.shift();
  if (!p.wp.length && p.trail.length && p.mode !== 'home') goHome(p);

  let target = p.wp[0];
  if (p.mode === 'home') {
    // Re-plan often: the route is cheap and the board keeps changing
    p.routeTimer = (p.routeTimer || 0) - dt;
    if (!p.route || p.routeTimer <= 0) {
      p.route = routeHome(p);
      p.routeTimer = 0.1;
    }
    if (p.route && p.route.length) {
      const i = p.route[Math.min(2, p.route.length - 1)];
      target = { x: (i % N) + 0.5, y: Math.floor(i / N) + 0.5 };
    } else {
      target = nearestOwn(p);
    }
  }
  if (target) p.desired = Math.atan2(target.y - p.y, target.x - p.x);

  // Last-moment safety: never steer into our own trail. Try nearby directions and
  // keep whichever survives longest.
  if (p.trail.length && safeSteps(p, p.desired) < 10) {
    let bestDir = p.desired, bestSteps = -1;
    for (const off of [0.5, -0.5, 1, -1, 1.5, -1.5, 2, -2, 2.6, -2.6, Math.PI]) {
      const n = safeSteps(p, p.desired + off);
      if (n > bestSteps) { bestSteps = n; bestDir = p.desired + off; }
      if (n >= 10) break;
    }
    p.desired = bestDir;
  }
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
  if (k === 'n') toggleMusic();
  if ((k === 'enter' || k === ' ') && (state === 'menu' || state === 'over') && !document.querySelector('.screen.show:not(#menu):not(#over)')) {
    e.preventDefault();
    if (state === 'menu') playFromMenu();
    else startGame();
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
  buildSkins();
}

function buildSkins() {
  const box = $('skins');
  box.innerHTML = '';
  for (const sk of SKINS) {
    const open = isUnlocked(sk);
    const b = document.createElement('button');
    b.className = 'skin' + (sk.id === mySkin ? ' picked' : '') + (open ? '' : ' locked');
    b.title = open ? sk.name : `Locked: ${sk.need.text}`;
    b.setAttribute('aria-label', b.title);
    const c = document.createElement('canvas');
    c.width = c.height = 88;
    const g = c.getContext('2d');
    g.translate(44, 40);
    g.rotate(-Math.PI / 2);
    drawBody(g, { color: COLORS[myColor], dark: shade(COLORS[myColor], -0.28), skin: sk.id, blink: 1, hueOff: 200 }, 46, 0);
    b.appendChild(c);
    if (!open) b.insertAdjacentHTML('beforeend', Icons.lock);
    b.addEventListener('click', () => {
      if (open) {
        mySkin = sk.id;
        save('color-claim-skin', sk.id);
        buildSkins();
      }
      $('skin-info').textContent = open ? `${sk.name} skin` : `🔒 ${sk.name}: ${sk.need.text}`;
    });
    box.appendChild(b);
  }
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
  me = makePlayer(1, myName || 'You', COLORS[myColor], false, mySkin);
  players.push(me);
  const botColors = COLORS.filter((_, i) => i !== myColor);
  BOT_NAMES.forEach((name, i) => players.push(makePlayer(i + 2, name, botColors[i], true, SKINS[randInt(0, SKINS.length - 1)].id)));
  powerups = [];
  powerTimer = 3;
  freezer = null;
  spawn(me, N / 2, N / 2);
  for (const p of players) if (p && p.isBot) spawn(p);
  cam.x = me.x;
  cam.y = me.y;
  cam.zoom = 1;
  peakPct = 0;
  time = 0;
  shake = 0;
  countdown = 3;
  goFlash = 0;
  threats = [];
  stick.active = false;
  $('name-input').blur();
  state = 'play';
  showScreen(null);
  Sfx.play('beep');
  Music.start();
}

function togglePause() {
  state = state === 'play' ? 'paused' : 'play';
  showScreen(state === 'paused' ? 'paused' : null);
  if (state === 'paused') Music.stop();
  else Music.start();
}

function toggleMute() {
  Sfx.toggle();
  $('mute-btn').innerHTML = Icons.sound(!Sfx.muted);
  if (Sfx.muted) Music.stop();
  else if (state === 'play') Music.start();
}

function toggleMusic() {
  const on = Music.toggle();
  $('music-btn').innerHTML = Icons.music(on);
  if (on && state === 'play') Music.start();
  else Music.stop();
}

function endGame(won, reason) {
  if (state === 'over' || state === 'menu') return;
  state = 'over';
  Music.stop();
  const score = Math.round(peakPct * 10) / 10;
  const isBest = score > best;
  if (isBest) { best = score; save('color-claim-best', best); }

  // Update lifetime stats and announce any skins that just unlocked
  const before = SKINS.filter(isUnlocked);
  stats.games++;
  stats.kills += me.kills;
  if (won) stats.wins++;
  stats.bestPct = Math.max(stats.bestPct, score);
  save('color-claim-stats', JSON.stringify(stats));
  const fresh = SKINS.filter(sk => isUnlocked(sk) && !before.includes(sk));
  $('over-unlock').textContent = fresh.length ? `🎁 New skin unlocked: ${fresh.map(sk => sk.name).join(', ')}! Pick it on the menu.` : '';
  $('over-unlock').classList.toggle('hidden', !fresh.length);
  if (fresh.length) Sfx.play('win');
  buildSkins();
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
function updateCamera(dt) {
  // Camera glides after you and zooms out as your land grows
  const k = Math.min(1, dt * 6);
  cam.x += (me.x - cam.x) * k;
  cam.y += (me.y - cam.y) * k;
  const targetZoom = 1 - Math.min(0.35, pct(me) / 80);
  cam.zoom += (targetZoom - cam.zoom) * Math.min(1, dt * 2);
}

function update(dt) {
  time += dt;
  if (countdown > 0) {
    // 3-2-1: everyone waits, but you can already choose which way to go
    const before = Math.ceil(countdown);
    countdown -= dt;
    if (me.alive) { steerHuman(); me.angle = me.desired; }
    if (countdown <= 0) { goFlash = 0.8; Sfx.play('go'); }
    else if (Math.ceil(countdown) !== before) Sfx.play('beep');
    updateCamera(dt);
    return;
  }
  goFlash = Math.max(0, goFlash - dt);
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
  checkBumps();
  updatePowerups(dt);

  // Danger: is an enemy close to your exposed trail? Close ones also get marked.
  danger = 0;
  threats = [];
  if (me.alive && me.trail.length && me.fx.shield <= 0) {
    for (const o of players) {
      if (!o || o === me || !o.alive) continue;
      let closest = Infinity;
      for (let k = 0; k < me.trail.length; k += 2) {
        const i = me.trail[k], tx = (i % N) + 0.5, ty = Math.floor(i / N) + 0.5;
        closest = Math.min(closest, Math.hypot(o.x - tx, o.y - ty));
      }
      if (closest < 7) danger = Math.max(danger, 1 - closest / 7);
      if (closest < 10) threats.push(o);
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

  updateCamera(dt);
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
      const style = colorOf(players[id]);
      if (style) {
        ctx.fillStyle = style;
        ctx.fillRect(Math.floor(c * CELL - x0), Math.floor(r * CELL - y0 + yOffset), Math.ceil((e - c + 1) * CELL), Math.ceil(CELL));
      }
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

function drawCrown(x, y, w) {
  const h = w * 0.7;
  ctx.fillStyle = '#ffc93c';
  ctx.strokeStyle = '#c98a00';
  ctx.lineWidth = 1.5;
  ctx.beginPath();
  ctx.moveTo(x - w / 2, y + h / 2);
  ctx.lineTo(x - w / 2, y - h / 2);
  ctx.lineTo(x - w / 4, y);
  ctx.lineTo(x, y - h / 2);
  ctx.lineTo(x + w / 4, y);
  ctx.lineTo(x + w / 2, y - h / 2);
  ctx.lineTo(x + w / 2, y + h / 2);
  ctx.closePath();
  ctx.fill();
  ctx.stroke();
}

function skinColors(look, t) {
  if (look.skin !== 'rainbow') return [look.color, look.dark];
  const h = (t * 120 + look.hueOff) % 360;
  return [`hsl(${h}, 85%, 62%)`, `hsl(${h}, 70%, 42%)`];
}

// Draws a square body with its skin at the origin, facing +x. `g` is any 2D context,
// so the menu can draw previews with the same code.
function drawBody(g, look, s, t) {
  const [color, dark] = skinColors(look, t);
  const skin = look.skin;
  const circ = (x, y, r, c) => { g.fillStyle = c; g.beginPath(); g.arc(x, y, r, 0, TAU); g.fill(); };

  if (skin === 'robot') { // antenna sticking out the back
    g.strokeStyle = dark;
    g.lineWidth = s * 0.08;
    g.beginPath();
    g.moveTo(-s * 0.45, 0);
    g.lineTo(-s * 0.75, 0);
    g.stroke();
    circ(-s * 0.78, 0, s * 0.1, Math.sin(t * 8) > 0 ? '#ff5d73' : '#ffb84d');
  }
  if (skin === 'cat') { // ears
    for (const side of [-1, 1]) {
      g.fillStyle = color;
      g.beginPath();
      g.moveTo(s * 0.02, side * s * 0.45);
      g.lineTo(s * 0.38, side * s * 0.45);
      g.lineTo(s * 0.2, side * s * 0.78);
      g.fill();
      g.fillStyle = '#ffb3c7';
      g.beginPath();
      g.moveTo(s * 0.1, side * s * 0.48);
      g.lineTo(s * 0.3, side * s * 0.48);
      g.lineTo(s * 0.2, side * s * 0.66);
      g.fill();
    }
  }
  if (skin === 'ninja') { // headband tails fluttering behind
    g.strokeStyle = '#26304a';
    g.lineWidth = s * 0.08;
    g.lineCap = 'round';
    for (const side of [-1, 1]) {
      g.beginPath();
      g.moveTo(-s * 0.45, side * s * 0.1);
      g.quadraticCurveTo(-s * 0.7, side * (s * 0.2 + Math.sin(t * 10 + side) * s * 0.1), -s * 0.9, side * s * 0.25);
      g.stroke();
    }
  }

  g.fillStyle = dark;
  g.fillRect(-s / 2, -s / 2 + s * 0.18, s, s);
  g.fillStyle = color;
  g.fillRect(-s / 2, -s / 2, s, s);

  // Body pattern, clipped to the square
  g.save();
  g.beginPath();
  g.rect(-s / 2, -s / 2, s, s);
  g.clip();
  if (skin === 'stripes') {
    g.strokeStyle = 'rgba(255, 255, 255, 0.35)';
    g.lineWidth = s * 0.12;
    for (let k = -3; k <= 3; k++) {
      g.beginPath();
      g.moveTo(k * s * 0.3 - s / 2, -s / 2);
      g.lineTo(k * s * 0.3 + s / 2, s / 2);
      g.stroke();
    }
  } else if (skin === 'dots') {
    for (const dx of [-0.3, 0, 0.3]) for (const dy of [-0.3, 0, 0.3]) circ(dx * s - s * 0.05, dy * s, s * 0.07, 'rgba(255, 255, 255, 0.45)');
  } else if (skin === 'confetti') {
    [[-0.3, -0.3], [0.05, -0.12], [-0.2, 0.25], [0.3, 0.32], [-0.35, 0.02], [0.1, 0.38]].forEach(([dx, dy], i) => {
      g.fillStyle = COLORS[(i * 3 + 1) % COLORS.length];
      g.fillRect(dx * s - s * 0.06, dy * s - s * 0.06, s * 0.12, s * 0.12);
    });
  } else if (skin === 'robot') {
    g.fillStyle = 'rgba(0, 0, 0, 0.18)';
    g.fillRect(-s / 2, -s * 0.04, s * 0.45, s * 0.08);
    for (const [dx, dy] of [[-0.38, -0.38], [-0.38, 0.38]]) circ(dx * s, dy * s, s * 0.05, 'rgba(0, 0, 0, 0.3)');
  }
  g.fillStyle = 'rgba(255, 255, 255, 0.25)';
  g.fillRect(-s / 2, -s / 2, s * 0.22, s);
  g.restore();

  // Face
  const closed = look.blink < 0;
  if (skin === 'ninja') {
    g.fillStyle = '#26304a';
    g.fillRect(s * 0.02, -s / 2, s * 0.34, s);
  }
  if (skin === 'shades') {
    g.fillStyle = '#1b2033';
    g.fillRect(s * 0.1, -s * 0.36, s * 0.24, s * 0.72);
    g.fillStyle = 'rgba(255, 255, 255, 0.5)';
    g.fillRect(s * 0.14, -s * 0.3, s * 0.05, s * 0.12);
    g.fillRect(s * 0.14, s * 0.1, s * 0.05, s * 0.12);
  } else if (skin === 'robot') {
    for (const side of [-1, 1]) {
      g.fillStyle = closed ? '#26304a' : '#7df9ff';
      g.fillRect(s * 0.12, side * s * 0.2 - s * 0.08, s * 0.16, s * 0.16);
    }
  } else {
    for (const side of [-1, 1]) {
      g.fillStyle = '#fff';
      g.beginPath();
      if (closed) g.ellipse(s * 0.18, side * s * 0.2, s * 0.04, s * 0.14, 0, 0, TAU);
      else g.arc(s * 0.18, side * s * 0.2, s * 0.14, 0, TAU);
      g.fill();
      if (!closed) {
        g.fillStyle = '#26304a';
        g.beginPath();
        if (skin === 'cat') g.ellipse(s * 0.23, side * s * 0.2, s * 0.03, s * 0.09, 0, 0, TAU);
        else g.arc(s * 0.24, side * s * 0.2, s * 0.07, 0, TAU);
        g.fill();
      }
    }
  }
  if (skin === 'cat') { // whiskers
    g.strokeStyle = 'rgba(38, 48, 74, 0.6)';
    g.lineWidth = Math.max(1, s * 0.03);
    for (const side of [-1, 1]) {
      for (const k of [-1, 1]) {
        g.beginPath();
        g.moveTo(s * 0.42, side * s * 0.05);
        g.lineTo(s * 0.62, side * (s * 0.12 + k * s * 0.06));
        g.stroke();
      }
    }
  }
}

function drawPowerupIcon(kind, x, y, r) {
  const def = POWERUPS[kind];
  ctx.fillStyle = '#fff';
  ctx.beginPath();
  ctx.arc(x, y, r, 0, TAU);
  ctx.fill();
  ctx.lineWidth = r * 0.18;
  ctx.strokeStyle = def.color;
  ctx.stroke();
  ctx.fillStyle = def.color;
  ctx.strokeStyle = def.color;
  const u = r * 0.55;
  ctx.beginPath();
  if (kind === 'speed') {
    ctx.moveTo(x + u * 0.2, y - u);
    ctx.lineTo(x - u * 0.6, y + u * 0.15);
    ctx.lineTo(x - u * 0.05, y + u * 0.15);
    ctx.lineTo(x - u * 0.25, y + u);
    ctx.lineTo(x + u * 0.6, y - u * 0.2);
    ctx.lineTo(x + u * 0.05, y - u * 0.2);
    ctx.closePath();
    ctx.fill();
  } else if (kind === 'shield') {
    ctx.moveTo(x, y - u);
    ctx.lineTo(x + u * 0.8, y - u * 0.6);
    ctx.quadraticCurveTo(x + u * 0.7, y + u * 0.6, x, y + u);
    ctx.quadraticCurveTo(x - u * 0.7, y + u * 0.6, x - u * 0.8, y - u * 0.6);
    ctx.closePath();
    ctx.fill();
  } else {
    ctx.lineWidth = r * 0.14;
    ctx.lineCap = 'round';
    for (let k = 0; k < 3; k++) {
      const a = (k / 3) * Math.PI + Math.PI / 2;
      ctx.moveTo(x - Math.cos(a) * u, y - Math.sin(a) * u);
      ctx.lineTo(x + Math.cos(a) * u, y + Math.sin(a) * u);
    }
    ctx.stroke();
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

  // Speed boost: motion lines behind
  if (p.fx.speed > 0) {
    ctx.strokeStyle = alpha(POWERUPS.speed.color, 0.7);
    ctx.lineWidth = Math.max(2, CELL * 0.15);
    ctx.lineCap = 'round';
    for (const side of [-0.35, 0, 0.35]) {
      const bx = hx - Math.cos(p.angle) * s * 0.8 - Math.sin(p.angle) * side * s;
      const by = hy + bob - Math.sin(p.angle) * s * 0.8 + Math.cos(p.angle) * side * s;
      const len = s * (0.5 + 0.3 * Math.sin(time * 30 + side * 9));
      ctx.beginPath();
      ctx.moveTo(bx, by);
      ctx.lineTo(bx - Math.cos(p.angle) * len, by - Math.sin(p.angle) * len);
      ctx.stroke();
    }
  }

  ctx.save();
  ctx.translate(hx, hy + bob);
  ctx.rotate(p.angle);
  ctx.scale(1 + p.squash * 0.15, 1 - p.squash * 0.15);
  drawBody(ctx, p, s, time);
  // Frozen: icy tint
  if (freezer && freezer !== p) {
    ctx.fillStyle = 'rgba(160, 225, 255, 0.55)';
    ctx.fillRect(-s / 2, -s / 2, s, s);
  }
  ctx.restore();

  // Shield: a glowing bubble
  if (p.fx.shield > 0) {
    const fade = p.fx.shield < 1.5 ? 0.5 + 0.5 * Math.sin(time * 20) : 1;
    ctx.strokeStyle = alpha(POWERUPS.shield.color, 0.8 * fade);
    ctx.fillStyle = alpha(POWERUPS.shield.color, 0.12 * fade);
    ctx.lineWidth = 2.5;
    ctx.beginPath();
    ctx.arc(hx, hy + bob, s * 0.95 + Math.sin(time * 6) * 2, 0, TAU);
    ctx.fill();
    ctx.stroke();
  }

  ctx.textAlign = 'center';
  ctx.font = `bold ${Math.round(CELL * 0.8)}px system-ui, sans-serif`;
  ctx.lineWidth = 3;
  ctx.strokeStyle = 'rgba(255, 255, 255, 0.8)';
  ctx.strokeText(p.name, hx, hy - s * 0.85 + bob);
  ctx.fillStyle = 'rgba(38, 48, 74, 0.9)';
  ctx.fillText(p.name, hx, hy - s * 0.85 + bob);
  if (p.id === leaderId) drawCrown(hx, hy - s * 1.75 + bob + Math.sin(time * 4) * 2, CELL * 0.9);
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
  const pattern = landPattern(me.skin, x0, y0);
  if (pattern) drawRuns(owner, c0, c1, r0, r1, x0, y0, p => (p === me ? pattern : null), 0);

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
  drawRuns(trail, c0, c1, r0, r1, x0, y0, p => {
    if (p === me && danger > 0) return dangerColor;
    if (p.fx.shield > 0) return alpha(p.color, 0.8);
    if (p.skin === 'rainbow') return `hsla(${(time * 120 + p.hueOff) % 360}, 85%, 62%, 0.5)`;
    return p.trailColor;
  }, 0);

  // A shimmer runs along every trail toward the head
  const inner = CELL * 0.5;
  for (const p of players) {
    if (!p || !p.alive || !p.trail.length) continue;
    p.trail.forEach((i, k) => {
      const x = i % N, y = (i - x) / N;
      if (x < c0 || x > c1 || y < r0 || y > r1 || trail[i] !== p.id) return;
      ctx.fillStyle = `rgba(255, 255, 255, ${0.16 + 0.16 * Math.sin(k * 0.7 - time * 9)})`;
      ctx.fillRect(x * CELL - x0 + (CELL - inner) / 2, y * CELL - y0 + (CELL - inner) / 2, inner, inner);
    });
  }

  // Power-ups bob and pop in
  for (const pu of powerups) {
    const px = pu.x * CELL - x0, py = pu.y * CELL - y0 + Math.sin(time * 4 + pu.x) * CELL * 0.15;
    if (px < -40 || py < -40 || px > W + 40 || py > H + 40) continue;
    const r = CELL * 0.85 * Math.min(1, pu.age * 4);
    ctx.fillStyle = alpha(POWERUPS[pu.kind].color, 0.25);
    ctx.beginPath();
    ctx.arc(px, py, r * (1.5 + 0.15 * Math.sin(time * 6)), 0, TAU);
    ctx.fill();
    drawPowerupIcon(pu.kind, px, py, r);
  }

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

  // Frozen by someone else: frosty screen edge
  if (freezer && freezer !== me && me.alive) {
    const grad = ctx.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.3, W / 2, H / 2, Math.max(W, H) * 0.75);
    grad.addColorStop(0, 'rgba(160, 225, 255, 0)');
    grad.addColorStop(1, 'rgba(160, 225, 255, 0.55)');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, W, H);
  }

  // Danger warning: red glow around the screen edge
  if (danger > 0.3) {
    const a = danger * 0.35 * (0.6 + 0.4 * Math.sin(time * 18));
    const grad = ctx.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.35, W / 2, H / 2, Math.max(W, H) * 0.75);
    grad.addColorStop(0, 'rgba(255, 60, 80, 0)');
    grad.addColorStop(1, `rgba(255, 60, 80, ${a})`);
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, W, H);
  }

  // Enemies near your trail: a "!" above them, or an arrow at the screen edge if off-screen
  for (const o of threats) {
    const sx = o.x * CELL - x0, sy = o.y * CELL - y0;
    const pulse = 1 + 0.15 * Math.sin(time * 14);
    if (sx > 20 && sy > 20 && sx < W - 20 && sy < H - 20) {
      const bx = sx, by = sy - CELL * 2.9;
      ctx.fillStyle = '#ff3c50';
      ctx.beginPath();
      ctx.arc(bx, by, CELL * 0.6 * pulse, 0, TAU);
      ctx.fill();
      ctx.fillStyle = '#fff';
      ctx.font = `900 ${Math.round(CELL * 0.9)}px system-ui, sans-serif`;
      ctx.textAlign = 'center';
      ctx.textBaseline = 'middle';
      ctx.fillText('!', bx, by + 1);
      ctx.textBaseline = 'alphabetic';
    } else {
      const a = Math.atan2(sy - H / 2, sx - W / 2);
      const t = Math.min((W / 2 - 36) / Math.abs(Math.cos(a) || 1e-6), (H / 2 - 36) / Math.abs(Math.sin(a) || 1e-6));
      ctx.save();
      ctx.translate(W / 2 + Math.cos(a) * t, H / 2 + Math.sin(a) * t);
      ctx.rotate(a);
      ctx.scale(pulse, pulse);
      ctx.fillStyle = '#ff3c50';
      ctx.strokeStyle = '#fff';
      ctx.lineWidth = 2;
      ctx.beginPath();
      ctx.moveTo(16, 0);
      ctx.lineTo(-8, -12);
      ctx.lineTo(-8, 12);
      ctx.closePath();
      ctx.fill();
      ctx.stroke();
      ctx.restore();
    }
  }

  // 3-2-1-GO!
  if (countdown > 0 || goFlash > 0) {
    const text = countdown > 0 ? String(Math.ceil(countdown)) : 'GO!';
    const frac = countdown > 0 ? countdown % 1 : goFlash / 0.8;
    ctx.save();
    ctx.translate(W / 2, H * 0.38);
    ctx.scale(1 + frac * 0.5, 1 + frac * 0.5);
    ctx.globalAlpha = countdown > 0 ? 1 : Math.min(1, goFlash * 2);
    ctx.font = `900 ${Math.round(Math.min(W, H) * 0.16)}px system-ui, sans-serif`;
    ctx.textAlign = 'center';
    ctx.textBaseline = 'middle';
    ctx.lineWidth = 8;
    ctx.strokeStyle = me.dark;
    ctx.strokeText(text, 0, 0);
    ctx.fillStyle = '#fff';
    ctx.fillText(text, 0, 0);
    ctx.restore();
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

// Your skin's pattern also shows on your land. Patterns are anchored to the map so they
// scroll with it.
const patternCache = {};
function landPattern(skin, x0, y0) {
  if (!['stripes', 'dots', 'confetti'].includes(skin)) return null;
  if (!patternCache[skin]) {
    const c = document.createElement('canvas');
    c.width = c.height = 24;
    const g = c.getContext('2d');
    if (skin === 'stripes') {
      g.strokeStyle = 'rgba(255, 255, 255, 0.22)';
      g.lineWidth = 5;
      for (const o of [-24, 0, 24]) { g.beginPath(); g.moveTo(o, 0); g.lineTo(o + 24, 24); g.stroke(); }
    } else if (skin === 'dots') {
      g.fillStyle = 'rgba(255, 255, 255, 0.28)';
      g.beginPath(); g.arc(6, 6, 3, 0, TAU); g.arc(18, 18, 3, 0, TAU); g.fill();
    } else {
      [[4, 4, 0], [16, 8, 2], [8, 17, 4], [19, 19, 6]].forEach(([x, y, ci]) => { g.fillStyle = alpha(COLORS[ci], 0.55); g.fillRect(x, y, 4, 4); });
    }
    patternCache[skin] = ctx.createPattern(c, 'repeat');
  }
  const pat = patternCache[skin];
  pat.setTransform(new DOMMatrix().translateSelf(-x0, -y0));
  return pat;
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
  const fx = Object.keys(POWERUPS).filter(k => me.alive && me.fx[k] > 0)
    .map(k => `<span class="fx" style="--c:${POWERUPS[k].color}">${POWERUPS[k].name} ${Math.ceil(me.fx[k])}s</span>`);
  if (freezer && freezer !== me && me.alive) fx.push('<span class="fx" style="--c:#3fc7f5">Frozen!</span>');
  const fxHtml = fx.join('');
  if ($('effects').innerHTML !== fxHtml) $('effects').innerHTML = fxHtml;
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

// ---------- How to play ----------
// Four little diagrams drawn on canvases: leave land, loop back, cut trails, protect yours.
function drawHowtoStep(g, step) {
  const C = 10, blue = COLORS[myColor], red = COLORS[myColor === 1 ? 2 : 1];
  const cell = (x, y, col) => { g.fillStyle = col; g.fillRect(x * C, y * C, C, C); };
  const head = (x, y, col) => {
    g.fillStyle = shade(col, -0.3);
    g.fillRect(x * C - 3, y * C - 1, C + 6, C + 6);
    g.fillStyle = col;
    g.fillRect(x * C - 3, y * C - 3, C + 6, C + 6);
  };
  g.fillStyle = '#f5f7fc';
  g.fillRect(0, 0, 160, 110);
  for (let x = 1; x <= 5; x++) for (let y = 3; y <= 8; y++) cell(x, y, blue);
  if (step === 0) {
    for (let x = 6; x <= 11; x++) cell(x, 5, alpha(blue, 0.45));
    head(12, 5, blue);
  } else if (step === 1) {
    for (let x = 6; x <= 11; x++) for (let y = 2; y <= 8; y++) cell(x, y, alpha(blue, x === 11 || y === 2 || y === 8 ? 0.85 : 0.55));
    head(6, 8, blue);
  } else if (step === 2) {
    for (let y = 1; y <= 9; y++) cell(11, y, alpha(red, 0.5));
    head(11, 0.2, red);
    for (let x = 6; x <= 10; x++) cell(x, 5, alpha(blue, 0.45));
    head(11, 5, blue);
    g.strokeStyle = '#ffb84d';
    g.lineWidth = 3;
    for (let k = 0; k < 6; k++) {
      const a = (k * Math.PI) / 3;
      g.beginPath();
      g.moveTo(115 + Math.cos(a) * 12, 55 + Math.sin(a) * 12);
      g.lineTo(115 + Math.cos(a) * 20, 55 + Math.sin(a) * 20);
      g.stroke();
    }
  } else {
    for (let x = 6; x <= 13; x++) cell(x, 5, 'rgba(255, 60, 80, 0.6)');
    head(14, 5, blue);
    head(9, 3.6, red);
    g.fillStyle = '#ff3c50';
    g.beginPath();
    g.arc(95, 20, 9, 0, TAU);
    g.fill();
    g.fillStyle = '#fff';
    g.font = '900 13px system-ui';
    g.textAlign = 'center';
    g.fillText('!', 95, 25);
    g.textAlign = 'left';
  }
}

let howtoThenPlay = false;
function showHowto(thenPlay) {
  howtoThenPlay = thenPlay;
  document.querySelectorAll('#howto canvas').forEach(c => drawHowtoStep(c.getContext('2d'), Number(c.dataset.step)));
  $('howto-btn').textContent = thenPlay ? "Let's go!" : 'Got it';
  showScreen('howto');
}
$('howto-btn').addEventListener('click', () => {
  save('color-claim-howto-seen', '1');
  if (howtoThenPlay) startGame();
  else showScreen('menu');
});
$('howto-open').addEventListener('click', () => showHowto(false));

// The first time someone presses Play, show them how the game works
function playFromMenu() {
  if (load('color-claim-howto-seen', '') !== '1') showHowto(true);
  else startGame();
}

$('play-btn').addEventListener('click', () => { if (state === 'menu') playFromMenu(); });
$('again-btn').addEventListener('click', () => { if (state === 'over') startGame(); });
$('menu-btn').addEventListener('click', () => {
  if (state !== 'over') return;
  state = 'menu';
  me = null;
  showScreen('menu');
});
$('resume-btn').addEventListener('click', () => { if (state === 'paused') togglePause(); });
$('mute-btn').addEventListener('click', toggleMute);
$('mute-btn').innerHTML = Icons.sound(!Sfx.muted);
$('music-btn').innerHTML = Icons.music(Music.enabled);
$('music-btn').addEventListener('click', toggleMusic);
$('pause-btn').innerHTML = Icons.pause;
$('pause-btn').addEventListener('click', () => { if (state === 'play') togglePause(); });

buildSwatches();
showScreen('menu');
requestAnimationFrame(frame);
