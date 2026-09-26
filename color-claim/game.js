'use strict';

// ---------- Canvas setup ----------
const canvas = document.getElementById('game');
let ctx = canvas.getContext('2d'); // swapped for an offscreen canvas while saving a GIF
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
// `random` is swapped for a seeded generator while a Daily map is set up
let random = Math.random;
const rand = (a, b) => a + random() * (b - a);
const randInt = (a, b) => Math.floor(rand(a, b + 1));
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
const fmtTime = t => `${Math.floor(t / 60)}:${String(Math.floor(t % 60)).padStart(2, '0')}`;

function mulberry32(seed) {
  return () => {
    seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
function hashStr(str) {
  let h = 2166136261;
  for (const c of str) { h ^= c.charCodeAt(0); h = Math.imul(h, 16777619); }
  return h >>> 0;
}
function todayKey() {
  const d = new Date();
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}

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
let N = 80;           // map is N x N cells (Marathon uses a bigger map)
let owner;            // which player owns each cell (0 = nobody)
let trail;            // whose trail is on each cell (0 = none)
let wall;             // 0 = floor, 1 = pillar, 2 = outside the arena
let seen;             // scratch buffer for flood fill
let belt;             // conveyor belt direction on each cell (0 = none, see BELT_DIRS)
let playCells = 1;    // number of floor cells, for percentages
const counts = new Int32Array(16); // cells owned per player id

function allocWorld(size) {
  N = size;
  owner = new Uint8Array(N * N);
  trail = new Uint8Array(N * N);
  wall = new Uint8Array(N * N);
  seen = new Uint8Array(N * N);
  belt = new Int8Array(N * N);
  bfsPrev = new Int32Array(N * N);
  bfsMark = new Uint32Array(N * N);
  bfsQueue = new Int32Array(N * N);
  mini = document.createElement('canvas');
  mini.width = mini.height = N;
  miniCtx = mini.getContext('2d');
  miniImg = miniCtx.createImageData(N, N);
}

const MODES = {
  classic: { name: 'Classic', desc: 'Claim 50% of the map to win', size: 80, win: 50, powerups: 4 },
  timed: { name: 'Timed', desc: 'Biggest player after 3:00 wins', size: 80, win: 0, time: 180, powerups: 5 },
  daily: { name: 'Daily', desc: 'Same starting map for everyone today · claim 50%', size: 80, win: 50, powerups: 4, daily: true },
  weekly: { name: 'Weekly', desc: "This week's tournament: the same map and start all week · 3:00 · race the ghost of your best run", size: 80, win: 0, time: 180, powerups: 5, weekly: true },
  marathon: { name: 'Marathon', desc: 'A huge map · claim 60% to win', size: 120, win: 60, powerups: 7 },
  tutorial: { name: 'Tutorial', desc: 'Learn the game step by step', size: 48, win: 0, powerups: 0, tutorial: true, hidden: true },
  cup: { name: 'Cup', desc: '3 two-minute rounds on different maps · most points wins the cup', size: 80, win: 0, time: 120, powerups: 5, cup: true },
  duo: { name: '2 Players', desc: 'Same keyboard: Player 1 uses WASD, Player 2 the arrow keys · first to 40% (or last one standing) wins', size: 80, win: 40, powerups: 5, duo: true },
  team: { name: 'Teams', desc: 'You + 3 bots vs 4 bots · first team to 50% wins', size: 80, win: 50, powerups: 5, teams: true },
  boss: { name: 'Boss Battle', desc: "Just you and the King · cut his trail to hit him · knock off all his hearts to win", size: 64, win: 0, powerups: 4, boss: true },
};

const MAPS = {
  square: { name: 'Square' },
  round: { name: 'Round' },
  pillars: { name: 'Pillars' },
  maze: { name: 'Maze' },
  islands: { name: 'Islands' },
  saws: { name: 'Saw Mill' },
  storm: { name: 'Storm' },
  belts: { name: 'Conveyor' },
  portals: { name: 'Portals' },
};

// Custom maps are saved as a bit string of wall cells (80 x 80), base64 encoded
const CUSTOM_SIZE = 80;
function packCells(cells) {
  let bin = '';
  for (let i = 0; i < cells.length; i += 8) {
    let b = 0;
    for (let k = 0; k < 8; k++) if (cells[i + k]) b |= 1 << k;
    bin += String.fromCharCode(b);
  }
  return btoa(bin);
}
function unpackCells(str) {
  const cells = new Uint8Array(CUSTOM_SIZE * CUSTOM_SIZE);
  try {
    const bin = atob(str);
    for (let i = 0; i < cells.length; i++) cells[i] = (bin.charCodeAt(i >> 3) >> (i & 7)) & 1;
  } catch { /* bad saved data: empty map */ }
  return cells;
}
function loadCustomMaps() {
  try { const m = JSON.parse(load('color-claim-maps', '[]')); return Array.isArray(m) ? m : []; } catch { return []; }
}

function buildMap(id) {
  if (id.startsWith('custom')) {
    const map = loadCustomMaps()[Number(id.slice(6))];
    if (map) {
      const cells = unpackCells(map.cells);
      for (let i = 0; i < cells.length; i++) if (cells[i]) wall[i] = 1;
    }
  } else if (id === 'round') {
    const c = (N - 1) / 2, r = N / 2 - 1;
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) if (Math.hypot(x - c, y - c) > r) wall[y * N + x] = 2;
  } else if (id === 'maze') {
    // Blocks with a wall on their top or left edge (a "binary tree" maze), each with a gap
    const g = Math.round(N / 8), c = N / 2;
    for (let by = 0; by < N; by += g) {
      for (let bx = 0; bx < N; bx += g) {
        const top = random() < 0.5;
        if ((top && by === 0) || (!top && bx === 0)) continue; // leave the outer edge open
        const gap = 2 + Math.floor(random() * (g - 6));
        for (let k = 0; k < g; k++) {
          if (k >= gap && k < gap + 4) continue;
          const x = top ? bx + k : bx, y = top ? by : by + k;
          if (x < N && y < N && Math.hypot(x - c, y - c) > 8) wall[y * N + x] = 1;
        }
      }
    }
  } else if (id === 'islands') {
    // A central island and a ring of six, joined by bridges, with water (outside) between
    wall.fill(2);
    const c = N / 2, isles = [[c, c, N * 0.16]];
    for (let k = 0; k < 6; k++) {
      const a = (k / 6) * TAU + 0.3;
      isles.push([c + Math.cos(a) * N * 0.33, c + Math.sin(a) * N * 0.33, N * 0.13]);
    }
    const bridges = [];
    for (let k = 1; k <= 6; k++) bridges.push([isles[0], isles[k]], [isles[k], isles[(k % 6) + 1]]);
    const nearSeg = (x, y, [ax, ay], [bx, by]) => {
      const dx = bx - ax, dy = by - ay, t = clamp(((x - ax) * dx + (y - ay) * dy) / (dx * dx + dy * dy), 0, 1);
      return Math.hypot(x - (ax + dx * t), y - (ay + dy * t));
    };
    for (let y = 0; y < N; y++) {
      for (let x = 0; x < N; x++) {
        const land = isles.some(([ix, iy, r]) => Math.hypot(x - ix, y - iy) <= r) || bridges.some(([a, b]) => nearSeg(x, y, a, b) <= 2.2);
        if (land) wall[y * N + x] = 0;
      }
    }
  } else if (id === 'pillars') {
    const s = Math.round(N * 0.07);
    for (const fx of [0.22, 0.5, 0.78]) {
      for (const fy of [0.22, 0.5, 0.78]) {
        if (fx === 0.5 && fy === 0.5) continue; // keep the middle free for your start
        const x0 = Math.round(N * fx - s / 2), y0 = Math.round(N * fy - s / 2);
        for (let y = y0; y < y0 + s; y++) for (let x = x0; x < x0 + s; x++) wall[y * N + x] = 1;
      }
    }
  }
  playCells = 0;
  for (let i = 0; i < N * N; i++) if (!wall[i]) playCells++;
}

// ---------- Hazards ----------
// Saw Mill: spinning saws slide along tracks and cut any trail they touch (a shield keeps you safe).
// Storm: the arena keeps shrinking. Land, trails and players caught outside the ring are lost.
let saws = [];
let storm = null;
const SAW_R = 1.2;
const STORM_FIRST = 40, STORM_EVERY = 25, STORM_WARN = 6, STORM_SHRINK = 4;

function buildHazards(id) {
  saws = [];
  storm = null;
  portals = [];
  if (id === 'belts') {
    // Four conveyor strips that carry you around the map in a big square
    const w = N > 100 ? 4 : 3, a = Math.round(N * 0.25), b = Math.round(N * 0.75), lo = Math.round(N * 0.1), hi = Math.round(N * 0.9);
    const lay = (x0, y0, x1, y1, dir) => {
      for (let y = y0; y <= y1; y++) for (let x = x0; x <= x1; x++) belt[y * N + x] = dir;
    };
    lay(lo, a, hi, a + w - 1, 1);
    lay(lo, b - w + 1, hi, b, 3);
    lay(b - w + 1, lo, b, hi, 2);
    lay(a, lo, a + w - 1, hi, 4);
  } else if (id === 'portals') {
    // Pairs of portals: step into one and you come out of its twin
    const pairs = [[[0.18, 0.18], [0.82, 0.82], '#3fa9f5'], [[0.82, 0.18], [0.18, 0.82], '#ff8c42']];
    if (N > 100) pairs.push([[0.5, 0.12], [0.5, 0.88], '#b06bff']);
    for (const [a, b, color] of pairs) {
      const k = portals.length;
      portals.push({ x: N * a[0], y: N * a[1], color, link: k + 1 }, { x: N * b[0], y: N * b[1], color, link: k });
    }
  } else if (id === 'saws') {
    // Saws run back and forth along horizontal and vertical lanes, and one circles the middle
    const lanes = N > 100 ? [0.2, 0.4, 0.6, 0.8] : [0.28, 0.72];
    for (const f of lanes) {
      saws.push({ kind: 'line', ax: N * 0.08, ay: N * f, bx: N * 0.92, by: N * f, speed: rand(3.2, 4.2), t: random(), x: 0, y: 0, spin: 0 });
      saws.push({ kind: 'line', ax: N * f, ay: N * 0.08, bx: N * f, by: N * 0.92, speed: rand(3.2, 4.2), t: random(), x: 0, y: 0, spin: 0 });
    }
    saws.push({ kind: 'circle', cx: N / 2, cy: N / 2, r: N * 0.2, speed: 3.6, t: random(), x: 0, y: 0, spin: 0 });
    for (const sw of saws) moveSaw(sw, 0);
  } else if (id === 'storm') {
    storm = { r: N * 0.72, from: N * 0.72, to: N * 0.72, min: N * 0.3, clock: STORM_FIRST, phase: 'wait' };
  }
}

function moveSaw(sw, dt) {
  sw.spin += dt * 10;
  if (sw.kind === 'line') {
    const len = Math.hypot(sw.bx - sw.ax, sw.by - sw.ay);
    sw.t = (sw.t + (sw.speed * dt) / (2 * len)) % 1;
    const u = sw.t < 0.5 ? sw.t * 2 : 2 - sw.t * 2;
    sw.x = sw.ax + (sw.bx - sw.ax) * u;
    sw.y = sw.ay + (sw.by - sw.ay) * u;
  } else {
    sw.t = (sw.t + (sw.speed * dt) / (TAU * sw.r)) % 1;
    sw.x = sw.cx + Math.cos(sw.t * TAU) * sw.r;
    sw.y = sw.cy + Math.sin(sw.t * TAU) * sw.r;
  }
}

// Where a saw will be `ahead` seconds from now
function sawAhead(sw, ahead) {
  const copy = { ...sw };
  moveSaw(copy, ahead);
  return copy;
}

const nearSaw = (x, y, d) => saws.some(sw => Math.hypot(sw.x - x, sw.y - y) < d);
const nearPortal = (x, y, d) => portals.some(pt => Math.hypot(pt.x - x, pt.y - y) < d);

// Conveyor belts push anything standing on them
const BELT_DIRS = [null, [1, 0], [0, 1], [-1, 0], [0, -1]];
const BELT_SPEED = 2.6;
const beltAt = (x, y) => BELT_DIRS[belt[Math.floor(y) * N + Math.floor(x)]];

let portals = [];
const PORTAL_R = 1.1;
function checkPortals(p) {
  if (!portals.length || !p.alive || (p.portalWait || 0) > time) return;
  const from = portals.find(pt => Math.hypot(p.x - pt.x, p.y - pt.y) < PORTAL_R);
  if (from) teleport(p, from, portals[from.link]);
}

function teleport(p, from, to) {
  burst(p.x, p.y, from.color, 14, 6);
  p.x = clamp(to.x + Math.cos(p.angle) * 1.6, 0.5, N - 0.5);
  p.y = clamp(to.y + Math.sin(p.angle) * 1.6, 0.5, N - 0.5);
  p.portalWait = time + 1;
  p.cx = Math.floor(p.x);
  p.cy = Math.floor(p.y);
  visit(p, p.cx, p.cy); // your trail carries on from the other side
  burst(p.x, p.y, to.color, 14, 6);
  if (p === me) { cam.x = p.x; cam.y = p.y; Sfx.play('portal'); run.teleports++; }
  if (p === p2) { cam2.x = p.x; cam2.y = p.y; }
  if (p.isBot) {
    p.route = null;
    if (p.trail.length) goHome(p);
    else { p.wp = []; p.mode = 'idle'; }
  }
}

// Is this spot safe from the storm? While the ring is about to shrink, "safe" means inside the new ring.
function stormSafe(x, y, margin = 0) {
  if (!storm) return true;
  const r = storm.phase === 'wait' ? storm.r : storm.to;
  return Math.hypot(x - N / 2, y - N / 2) < r - margin;
}

function updateHazards(dt) {
  for (const sw of saws) {
    moveSaw(sw, dt);
    // Cut every trail the blade touches
    for (let y = Math.floor(sw.y - SAW_R); y <= Math.floor(sw.y + SAW_R); y++) {
      for (let x = Math.floor(sw.x - SAW_R); x <= Math.floor(sw.x + SAW_R); x++) {
        if (x < 0 || y < 0 || x >= N || y >= N || Math.hypot(x + 0.5 - sw.x, y + 0.5 - sw.y) > SAW_R + 0.3) continue;
        const id = trail[y * N + x];
        if (id && players[id] && players[id].alive) {
          kill(players[id], null, 'saw');
          if (!players[id].alive && me && dist(sw, me) < 20) Sfx.play('saw');
        }
      }
    }
  }
  if (storm) updateStorm(dt);
}

function updateStorm(dt) {
  const st = storm;
  st.clock -= dt;
  if (st.phase === 'wait' && st.clock <= STORM_WARN && st.r > st.min + 0.5) {
    st.phase = 'warn';
    st.to = Math.max(st.min, Math.min(N * 0.56, st.r - N * 0.065)); // the first one cuts off the corners
    if (me.alive) {
      toast('The storm is closing in! Stay inside the ring.');
      Sfx.play('warn');
    }
  } else if (st.phase === 'warn' && st.clock <= 0) {
    st.phase = 'shrink';
    st.from = st.r;
    st.clock = STORM_SHRINK;
    if (me.alive) Sfx.play('rumble');
  } else if (st.phase === 'shrink') {
    st.r = st.to + (st.from - st.to) * Math.max(0, st.clock / STORM_SHRINK);
    if (st.clock <= 0) {
      st.r = st.to;
      st.phase = 'wait';
      st.clock = STORM_EVERY;
    }
    applyStorm();
  }
}

// Turn everything outside the ring into storm (wall 3)
function applyStorm() {
  const c = N / 2;
  let changed = false;
  for (let y = 0; y < N; y++) {
    for (let x = 0; x < N; x++) {
      const i = y * N + x;
      if (wall[i] || Math.hypot(x + 0.5 - c, y + 0.5 - c) <= storm.r) continue;
      wall[i] = 3;
      playCells--;
      changed = true;
      if (owner[i]) setOwner(i, 0);
      const t = trail[i];
      if (t) {
        trail[i] = 0;
        if (players[t] && players[t].alive) kill(players[t], null, 'storm');
      }
    }
  }
  if (!changed) return;
  for (const p of players) {
    if (p && p.alive && (wall[p.cy * N + p.cx] || counts[p.id] === 0)) kill(p, null, 'storm');
  }
  powerups = powerups.filter(pu => !isWallAt(pu.x, pu.y));
  mapCoins = mapCoins.filter(co => !isWallAt(co.x, co.y));
}

// Bot personalities, shown under each bot's name
const PERSONALITIES = {
  hunter: { name: 'Hunter', aggro: 0.8, greed: 26, loop: 0.9, flee: 4, grab: 0.3 },
  turtle: { name: 'Turtle', aggro: 0.06, greed: 18, loop: 0.7, flee: 8, grab: 0.3 },
  explorer: { name: 'Explorer', aggro: 0.15, greed: 60, loop: 1.6, flee: 5, grab: 0.3 },
  collector: { name: 'Collector', aggro: 0.25, greed: 35, loop: 1.0, flee: 5, grab: 0.9 },
  wildcard: { name: 'Wildcard' }, // keeps its random settings
};
const PERSONA_MIX = ['hunter', 'turtle', 'explorer', 'collector', 'wildcard', 'hunter', 'explorer'];

function givePersonality(p, id) {
  const def = PERSONALITIES[id];
  p.persona = id;
  if (def.aggro !== undefined) {
    p.aggro = def.aggro;
    p.greed = def.greed;
    p.loopScale = def.loop;
  }
  p.fleeDist = def.flee || 5;
  p.grabChance = def.grab || 0.5;
}

// Bot difficulty (picked on the menu). Harder bots also pay more coins.
const DIFFICULTY = {
  easy: { name: 'Easy', speed: 0.9, aggro: 0.4, range: -4, think: 0.45, coins: 0.75 },
  normal: { name: 'Normal', speed: 1, aggro: 1, range: 0, think: 0.25, coins: 1 },
  hard: { name: 'Hard', speed: 1.06, aggro: 1.7, range: 6, think: 0.15, coins: 1.5 },
};
let gameDiff = DIFFICULTY.normal, gameDiffId = 'normal';

// Weekly events: one runs each week (Monday to Sunday), picked from the week number
const EVENTS = [
  { id: 'double', name: 'Double Coins Week', desc: 'Coins from games and the map are doubled' },
  { id: 'frenzy', name: 'Power-up Frenzy', desc: 'Twice as many power-ups, and they appear faster' },
  { id: 'goldrush', name: 'Gold Rush', desc: 'The map is full of gold coins' },
  { id: 'speed', name: 'Speed Week', desc: 'Everyone moves 20% faster' },
  { id: 'xp', name: 'XP Boost', desc: '+50% XP from every game' },
];
function weekInfo() {
  const d = new Date();
  const monday = new Date(d.getFullYear(), d.getMonth(), d.getDate() - ((d.getDay() + 6) % 7));
  const week = Math.floor((monday - new Date(2024, 0, 1)) / (7 * 86400000)); // 1 Jan 2024 was a Monday
  const daysLeft = 7 - ((d.getDay() + 6) % 7);
  return { event: EVENTS[((week % EVENTS.length) + EVENTS.length) % EVENTS.length], daysLeft, week };
}
const eventOn = id => weekInfo().event.id === id;

// In Teams mode, teammates can't cut, bump or steal from each other
const allies = (a, b) => a === b || (!!gameMode.teams && a.team === b.team);
const teamPct = team => players.reduce((sum, p) => sum + (p && p.team === team ? pct(p) : 0), 0);

const isWallAt = (x, y) => wall[Math.floor(y) * N + Math.floor(x)] !== 0;

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
  // Season pass rewards (can't be bought)
  { id: 'crystal', name: 'Crystal', need: { stat: 'season', n: Infinity, text: 'Season pass reward' } },
  { id: 'tiger', name: 'Tiger', need: { stat: 'season', n: Infinity, text: 'Season pass reward' } },
];

// Power-ups appear on the map; anyone (bots too) can grab them
const POWERUPS = {
  speed: { name: 'Speed', color: '#ffb84d', time: 4 },
  shield: { name: 'Shield', color: '#4f8cff', time: 6 },
  freeze: { name: 'Freeze', color: '#3fc7f5', time: 4 },
  ghost: { name: 'Ghost', color: '#8d7bd6', time: 5 },      // cross your own trail safely
  paint: { name: 'Paint Bomb', color: '#ff5d9e', time: 0 }, // instant: claims a circle of land
};
const SPAWN_SHIELD = 3; // seconds of protection after (re)spawning

let players = [];     // players[id], id starts at 1
let me = null;
let p2 = null; // Player 2 in 2-player mode
const cam2 = { x: 40, y: 40, zoom: 0.8 };
let state = 'menu';
let best = Number(load('color-claim-best', 0)) || 0; // Classic best (older saves use this key)
let myMode = load('color-claim-mode', 'classic');
if (!MODES[myMode]) myMode = 'classic';
let myDiff = load('color-claim-diff', 'normal');
if (!DIFFICULTY[myDiff]) myDiff = 'normal';
let challenge = null; // a friend's challenge being played: { seed, mode, map, diff, score }
let cup = null;       // the Cup in progress: { round, seed, maps, points }
let gameSeed = 0;
let myMap = load('color-claim-map', 'square');
if (!MAPS[myMap] && !(myMap.startsWith('custom') && load('color-claim-maps', '').length)) myMap = 'square';
let gameMode = MODES.classic, gameModeId = 'classic', gameMapId = 'square', playTime = 0;

const bestKey = modeId => (modeId === 'classic' ? 'color-claim-best'
  : modeId === 'daily' ? `color-claim-daily-${todayKey()}`
  : modeId === 'weekly' ? `color-claim-weekly-${weekInfo().week}`
  : `color-claim-best-${modeId}`);
const bestFor = modeId => Number(load(bestKey(modeId), 0)) || 0;
const dailyMap = () => Object.keys(MAPS)[hashStr(todayKey()) % Object.keys(MAPS).length];
const weeklyMap = () => Object.keys(MAPS)[hashStr('color-claim-week-' + weekInfo().week) % Object.keys(MAPS).length];
const fixedMap = modeId => (MODES[modeId].daily ? dailyMap() : MODES[modeId].weekly ? weeklyMap() : null);
let myColor = clamp(Number(load('color-claim-color', 0)) || 0, 0, COLORS.length - 1);
let myName = load('color-claim-name', '');
let stats = { games: 0, kills: 0, wins: 0, bestPct: 0 };
try { Object.assign(stats, JSON.parse(load('color-claim-stats', '{}'))); } catch { /* bad saved data */ }
stats.bestPct = Math.max(stats.bestPct, best);
let ownedSkins = [];
try { ownedSkins = JSON.parse(load('color-claim-owned-skins', '[]')); } catch { /* bad saved data */ }
// A skin is yours if you reached its milestone or bought it in the Locker
const isUnlocked = sk => !sk.need || stats[sk.need.stat] >= sk.need.n || ownedSkins.includes(sk.id);
let myFx = load('color-claim-fx', 'none');

// Settings (changed on the Settings screen)
const settings = { vibrate: true, shake: true, controls: 'joystick', stickSize: 'normal', patterns: false, emotes: true, track: 'sunny' };
try { Object.assign(settings, JSON.parse(load('color-claim-settings', '{}'))); } catch { /* bad saved data */ }
const saveSettings = () => save('color-claim-settings', JSON.stringify(settings));

// Short vibrations on phones that support it
function buzz(pattern) {
  if (settings.vibrate && navigator.vibrate) {
    try { navigator.vibrate(pattern); } catch { /* not allowed */ }
  }
}
let run = { powerups: 0, bigLoop: 0, freezeKO: false, trophies: [], coinsPicked: 0, giantKO: false, teleports: 0, bossHits: 0, beatGhost: false }; // this game's numbers
let fxParts = [], fxTimer = 0, achTimer = 1;
let mySkin = load('color-claim-skin', 'classic');
let myPet = load('color-claim-pet', 'chick');
if (!SKINS.some(sk => sk.id === mySkin && isUnlocked(sk))) mySkin = 'classic';
let powerups = [], powerTimer = 5, freezer = null;
let mapCoins = [], coinTimer = 3; // gold coins lying on the map
let particles = [], flashes = [], fades = [], floats = [], feed = [];
let peakPct = 0, minimapTimer = 0, time = 0, shake = 0, danger = 0, wasInDanger = false;
let countdown = 0, goFlash = 0, threats = [];
let replayFrames = [], replayTimer = 0, replayT = 0; // the last 10 seconds, 10 snapshots a second
let gameCounter = 0; // bumps every game, so delayed callbacks from an old game do nothing
function later(ms, fn) {
  const id = gameCounter;
  setTimeout(() => { if (id === gameCounter) fn(); }, ms);
}
const cam = { x: 40, y: 40, zoom: 1 };

function pct(p) { return (counts[p.id] / playCells) * 100; }

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
    fx: { speed: 0, shield: 0, freeze: 0, ghost: 0 },
    dark: shade(color, -0.28),
    trailColor: alpha(color, 0.45),
    x: 0, y: 0, cx: 0, cy: 0, angle: 0, desired: 0,
    alive: false, trail: [], kills: 0, respawn: 0,
    wp: [], mode: 'idle', think: 0, blink: rand(1, 4), squash: 0,
    pet: 'none', petX: 0, petY: 0, petFace: 1,
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
      if (dx * dx + dy * dy <= 7 && !owner[i] && !trail[i] && !wall[i]) cells.push(i);
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
      if (owner[y * N + x] || trail[y * N + x] || wall[y * N + x] || !stormSafe(x, y, 5)) continue;
      let score = freeStartCells(x, y).length;
      if (nearSaw(x, y, 4)) score -= 20;
      if (nearPortal(x, y, 5)) continue;
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
  p.petX = p.x;
  p.petY = p.y + 1;
  p.angle = p.desired = Math.random() * TAU;
  p.alive = true;
  p.trail = [];
  p.wp = [];
  p.mode = 'idle';
  p.think = rand(0.2, 1);
  p.route = null;
  p.squash = 1;
  p.fx = { speed: 0, shield: SPAWN_SHIELD, freeze: 0, ghost: 0 };
  return true;
}

function kill(victim, killer, how = 'cut') {
  if (!victim.alive) return;
  // A shield stops other players cutting or bumping you. Your own mistakes still count,
  // and so does losing all your land. Nothing protects you from the storm.
  if (victim.fx.shield > 0 && killer !== victim && how !== 'swallow' && how !== 'storm') return;
  if (victim.isKing && victim.hp > 1) { hurtKing(victim, killer, how); return; }
  victim.alive = false;
  const lost = [];
  for (const i of victim.trail) if (trail[i] === victim.id) { trail[i] = 0; lost.push(i); }
  victim.trail = [];
  for (let i = 0; i < N * N; i++) if (owner[i] === victim.id) { setOwner(i, 0); lost.push(i); }
  fades.push({ cells: lost, color: victim.color, life: 0.7 });
  burst(victim.x, victim.y, victim.color, 40, 12);
  victim.respawn = victim.isBoss ? Infinity : 3; // the Giant doesn't come back

  if (killer && killer !== victim) killer.kills++;
  if (killer && killer.isBot && killer !== victim && Math.random() < (victim === me ? 0.7 : 0.35)) botEmote(killer, Math.random() < 0.5 ? 'cool' : 'lol');
  if (killer === me && victim !== me && me.fx.freeze > 0) run.freezeKO = true;
  if (how === 'saw') addFeed(`🪚 A saw cut ${victim.name}`);
  else if (how === 'storm') addFeed(`🌀 The storm caught ${victim.name}`);
  else if (killer === victim) addFeed(`💥 ${victim.name} crossed their own trail`);
  else if (how === 'swallow') addFeed(`🍽️ ${killer.name} swallowed ${victim.name}`);
  else if (how === 'bump') addFeed(`💢 ${killer.name} bumped ${victim.name}`);
  else addFeed(`✂️ ${killer.name} cut ${victim.name}`);

  if (gameMode.duo && (victim === me || victim === p2)) {
    // 2 players: the first human knocked out loses
    shake = 1;
    Sfx.play('death');
    buzz(300);
    const winner = victim === me ? p2 : me;
    const by = killer && killer !== victim ? ` by ${killer.name}` : '';
    later(900, () => endDuo(winner, `${victim.name} was knocked out${by}.`));
  } else if (victim === me && gameMode.boss && lives > 1 && king && king.alive) {
    // Boss Battle: lose a life and come back somewhere else
    lives--;
    shake = 1;
    Sfx.play('hurt');
    buzz(200);
    toast(`Ouch! ${lives} ${lives === 1 ? 'life' : 'lives'} left`);
    later(1200, () => {
      if (!spawn(me)) spawn(me, N / 2, N / 2);
      cam.x = me.x;
      cam.y = me.y;
    });
  } else if (victim === me && gameMode.tutorial) {
    // Tutorial: no game over, just a tip and a fresh start
    toast(killer === me ? "Oops! Don't cross your own trail." : 'Watch out: your trail was cut!');
    Sfx.play('hurt');
    later(900, () => { spawn(me, N / 2, N / 2); cam.x = me.x; cam.y = me.y; });
  } else if (victim === me) {
    shake = 1;
    Sfx.play('death');
    buzz(300);
    const reason = how === 'saw' ? 'A saw cut your trail!'
      : how === 'storm' ? 'The storm caught you!'
      : killer === me ? 'You crossed your own trail!'
      : how === 'swallow' ? `${killer.name} swallowed all your land!`
      : how === 'bump' ? `You bumped into ${killer.name} outside your land!`
      : `${killer.name} cut your trail!`;
    later(900, () => endGame(false, reason));
  } else if (victim.isKing) {
    run.bossHits++;
    Sfx.play('bossdown');
    buzz([60, 40, 60, 40, 200]);
    shake = 1;
    for (let k = 0; k < 6; k++) burst(victim.x + rand(-3, 3), victim.y + rand(-3, 3), COLORS[k], 30, 14);
    toast('The King is defeated!');
    later(900, () => { if (state === 'play') win('You defeated the King!'); });
  } else if (killer === me && victim.isBoss) {
    run.giantKO = true;
    addCoins(100);
    toast('You beat the Giant! +100 coins');
    Sfx.play('win');
    buzz([60, 40, 60, 40, 120]);
    shake = 1;
    for (let k = 0; k < 4; k++) burst(victim.x, victim.y, COLORS[k * 2], 25, 14);
  } else if (killer === me) {
    toast(`You knocked out ${victim.name}!`);
    Sfx.play('cut');
    buzz([30, 40, 30]);
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
    if (!seen[i] && owner[i] !== p.id && !wall[i] && !(owner[i] && allies(players[owner[i]], p))) {
      setOwner(i, p.id);
      gained.push(i);
    }
  }
  flashes.push({ cells: gained, life: 0.45 });

  // Anyone who lost all their land is out
  for (const o of players) if (o && o !== p && o.alive && counts[o.id] === 0) kill(o, p, 'swallow');

  if (p.isBot && gained.length / playCells > 0.02 && Math.random() < 0.3) botEmote(p, Math.random() < 0.5 ? 'hi' : 'cool');
  if (p === me && gained.length) {
    const gainPct = (gained.length / playCells) * 100;
    run.bigLoop = Math.max(run.bigLoop, gainPct);
    if (gainPct >= 1) buzz(20);
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
  if (p.isBoss) v *= p.rage ? 1.28 : 1.12;
  else if (p.isBot) v *= gameDiff.speed;
  if (eventOn('speed')) v *= 1.2;
  if (p.fx.speed > 0) v *= 1.6;
  if (freezer && freezer !== p) v *= 0.5;
  return v;
}

function visit(p, x, y) {
  const i = y * N + x;
  if (wall[i]) return;
  const t = trail[i];
  if (t) {
    const other = players[t];
    if (other === p) {
      if (p.fx.ghost > 0) return; // Ghost: pass over your own trail
      kill(p, p);
      return;
    }
    if (allies(p, other)) return; // a teammate's trail is safe (and stays theirs)
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
  // A little click when you step onto a conveyor
  if (p === me && belt) {
    const on = !!beltAt(p.x, p.y);
    if (on && !p.onBelt) Sfx.play('belt');
    p.onBelt = on;
  }
  let diff = p.desired - p.angle;
  diff = Math.atan2(Math.sin(diff), Math.cos(diff));
  const turn = clamp(diff, -TURN * dt, TURN * dt);
  p.angle += turn;
  // Squash a little while turning hard, spring back when going straight
  const turning = dt > 0 ? Math.abs(turn) / (TURN * dt) : 0;
  p.squash += (turning * 0.5 - p.squash) * Math.min(1, dt * 10);
  const v = speedOf(p), push = beltAt(p.x, p.y);
  let nx = clamp(p.x + (Math.cos(p.angle) * v + (push ? push[0] * BELT_SPEED : 0)) * dt, 0.01, N - 0.01);
  let ny = clamp(p.y + (Math.sin(p.angle) * v + (push ? push[1] * BELT_SPEED : 0)) * dt, 0.01, N - 0.01);
  if (isWallAt(nx, ny)) {
    // Slide along walls instead of stopping dead
    if (!isWallAt(p.x, ny)) nx = p.x;
    else if (!isWallAt(nx, p.y)) ny = p.y;
    else { nx = p.x; ny = p.y; }
  }
  p.blocked = nx === p.x && ny === p.y;
  p.x = nx;
  p.y = ny;

  const cx = Math.floor(p.x), cy = Math.floor(p.y);
  if (cx === p.cx && cy === p.cy) return;
  // Diagonal step: also visit a corner cell so trails never have gaps to slip through
  if (cx !== p.cx && cy !== p.cy) {
    if (wall[p.cy * N + cx]) visit(p, p.cx, cy);
    else visit(p, cx, p.cy);
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
    if (wall[y * N + x] || !stormSafe(x, y, 3) || nearPortal(x, y, 2.5) || powerups.some(pu => Math.hypot(pu.x - x, pu.y - y) < 10)) continue;
    powerups.push({ x: x + 0.5, y: y + 0.5, kind: kinds[randInt(0, kinds.length - 1)], age: 0 });
    return;
  }
}

const POWERUP_TOASTS = {
  speed: 'Speed boost!',
  shield: 'Shield! Nobody can cut your trail',
  freeze: 'Freeze! Everyone else slows down',
  ghost: 'Ghost! You can cross your own trail',
  paint: 'Paint bomb!',
};

function grabPowerup(p, pu) {
  const def = POWERUPS[pu.kind];
  if (def.time) p.fx[pu.kind] = def.time;
  if (p === me) { run.powerups++; buzz(15); }
  burst(pu.x, pu.y, def.color, 16, 8);
  if (pu.kind === 'paint') paintBomb(p);
  if (p === me) {
    toast(POWERUP_TOASTS[pu.kind]);
    Sfx.play(pu.kind);
  } else if (pu.kind === 'freeze' && me.alive && dist(p, me) < 40) {
    toast(`${p.name} froze everyone!`);
    Sfx.play('freeze');
  }
}

// Paint Bomb: instantly claims a circle of land around you, even other players' land
function paintBomb(p) {
  const cells = [];
  for (let dy = -5; dy <= 5; dy++) {
    for (let dx = -5; dx <= 5; dx++) {
      const x = p.cx + dx, y = p.cy + dy;
      if (dx * dx + dy * dy > 20 || x < 0 || y < 0 || x >= N || y >= N) continue;
      const i = y * N + x;
      if (wall[i] || owner[i] === p.id || trail[i] === p.id) continue; // your own trail is claimed when you get home
      if (owner[i] && allies(players[owner[i]], p)) continue; // never paint over a teammate
      setOwner(i, p.id);
      cells.push(i);
    }
  }
  flashes.push({ cells, life: 0.45 });
  burst(p.x, p.y, POWERUPS.paint.color, 30, 12);
  for (const o of players) if (o && o !== p && o.alive && counts[o.id] === 0) kill(o, p, 'swallow');
  if (p === me && cells.length) {
    const gain = (cells.length / playCells) * 100;
    floats.push({ x: p.x, y: p.y - 3, text: `+${gain.toFixed(1)}%`, life: 1.2, big: false });
    buzz(25);
  }
}

// Gold coins appear around the map. Walk over one to pick it up (bots can grab them too).
const COIN_VALUE = 2;
function updateMapCoins(dt) {
  coinTimer -= dt;
  if (gameMode.tutorial) return;
  const rush = eventOn('goldrush');
  const max = (N > 100 ? 10 : 6) * (rush ? 3 : 1);
  if (coinTimer <= 0) {
    coinTimer = rush ? rand(0.8, 1.6) : rand(3, 6);
    if (mapCoins.length < max) {
      for (let t = 0; t < 20; t++) {
        const x = randInt(2, N - 3), y = randInt(2, N - 3);
        if (wall[y * N + x] || !stormSafe(x, y, 3) || nearPortal(x, y, 2.5)) continue;
        mapCoins.push({ x: x + 0.5, y: y + 0.5, age: 0, life: 25 });
        break;
      }
    }
  }
  for (const c of mapCoins) {
    c.age += dt;
    c.life -= dt;
    for (const p of players) {
      if (!p || !p.alive || c.taken || Math.hypot(p.x - c.x, p.y - c.y) > 1.1) continue;
      c.taken = true;
      if (p === me) {
        const value = COIN_VALUE * (eventOn('double') ? 2 : 1);
        run.coinsPicked += value;
        addCoins(value);
        floats.push({ x: c.x, y: c.y - 1, text: `+${value}`, life: 0.8, gold: true });
        Sfx.play('coin');
      }
    }
  }
  mapCoins = mapCoins.filter(c => !c.taken && c.life > 0);
}

function updatePowerups(dt) {
  powerTimer -= dt;
  if (powerTimer <= 0) {
    const frenzy = eventOn('frenzy');
    powerTimer = frenzy ? rand(3, 5) : rand(6, 10);
    if (powerups.length < gameMode.powerups * (frenzy ? 2 : 1)) spawnPowerup();
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

// The Giant: a big, fast boss bot that arrives once you're doing well, and hunts your trail
let giant = null;
function giantDue() {
  if (giant || !me.alive || gameMode.duo || gameMode.cup || gameMode.tutorial || gameMode.boss) return false;
  if (gameMode.time) return playTime >= 90;
  return pct(me) >= (N > 100 ? 15 : 20);
}
function spawnGiant() {
  giant = makePlayer(players.length, 'Giant', '#3b3f58', true, 'giant');
  giant.isBoss = true;
  giant.greed = 50;
  giant.aggro = 0.6;
  giant.loopScale = 1.6;
  giant.team = gameMode.teams ? 1 : giant.id;
  players.push(giant);
  if (!spawn(giant)) { players.pop(); giant = null; return; }
  giant.fx.shield = 4;
  addFeed('⚠️ The Giant has arrived!');
  toast('The Giant is coming for your trail!');
  Sfx.play('warn');
  shake = 0.6;
}

// ---------- Boss Battle: the King ----------
// A huge bot with hearts. Cutting his trail (or him crossing it) takes a heart instead of
// knocking him out. At half health he calls two guards; on his last heart he gets faster.
let king = null;
let lives = 1; // Boss Battle gives you 3
const KING_HEARTS = { easy: 3, normal: 5, hard: 7 };

function spawnKing() {
  const k = makePlayer(players.length, 'King', '#3b3f58', true, 'giant');
  k.isBoss = true;
  k.isKing = true;
  k.maxHp = k.hp = KING_HEARTS[gameDiffId] || 5;
  k.greed = 55;
  k.aggro = 0.7;
  k.loopScale = 1.7;
  k.fleeDist = 0;
  k.team = k.id;
  k.hitFlash = 0;
  players.push(k);
  if (spawn(k)) growKingdom(k);
  king = k;
}

// The King starts with a bigger home than everyone else
function growKingdom(k) {
  for (let dy = -5; dy <= 5; dy++) {
    for (let dx = -5; dx <= 5; dx++) {
      const x = k.cx + dx, y = k.cy + dy, i = y * N + x;
      if (x < 0 || y < 0 || x >= N || y >= N || dx * dx + dy * dy > 26 || owner[i] || trail[i] || wall[i]) continue;
      setOwner(i, k.id);
    }
  }
}

function hurtKing(k, killer, how) {
  k.hp--;
  run.bossHits++;
  // His trail breaks, and he gets a moment to recover
  const lost = [];
  for (const i of k.trail) if (trail[i] === k.id) { trail[i] = 0; lost.push(i); }
  k.trail = [];
  fades.push({ cells: lost, color: k.color, life: 0.7 });
  k.fx.shield = 2.5;
  k.wp = [];
  k.mode = 'idle';
  k.route = null;
  k.hitFlash = 1;
  // Swallowed (no land left) or caught by the storm: he escapes to a new home
  if (how === 'swallow' || how === 'storm' || counts[k.id] === 0) {
    k.alive = false;
    if (spawn(k)) growKingdom(k);
    else k.respawn = 0.5;
  }
  burst(k.x, k.y, '#ffd23f', 40, 14);
  floats.push({ x: k.x, y: k.y - 3, text: '-1 ♥', life: 1.2, big: true, gold: true });
  shake = 0.8;
  Sfx.play('bosshit');
  buzz([40, 30, 80]);
  addFeed(`👑 ${killer === k ? 'The King tripped on his own trail' : `${killer ? killer.name : 'A hazard'} hit the King`} · ${k.hp} ♥ left`);
  if (k.hp === Math.ceil(k.maxHp / 2)) later(600, () => callGuards(k));
  if (k.hp === 1) {
    k.rage = true;
    toast('Last heart! The King is furious!');
  }
}

function callGuards(k) {
  if (!k.alive || state !== 'play') return;
  const colors = COLORS.filter((_, i) => i !== myColor);
  ['Guard', 'Knight'].forEach((name, n) => {
    const g = makePlayer(players.length, name, colors[n * 3], true, 'classic');
    givePersonality(g, 'hunter');
    g.team = g.id;
    players.push(g);
    if (!spawn(g)) g.respawn = 1;
  });
  toast('The King calls his guards!');
  Sfx.play('roar');
}

// Two squares touching: whoever is safe on their own land wins. If both are outside,
// the one with the longer trail loses; equal trails knock both out.
function checkBumps() {
  if (gameMode.tutorial) return; // no bumping in the tutorial
  for (let a = 1; a < players.length; a++) {
    for (let b = a + 1; b < players.length; b++) {
      const p = players[a], q = players[b];
      if (!p.alive || !q.alive || allies(p, q) || dist(p, q) > (p.isBoss || q.isBoss ? 1.5 : 0.9)) continue;
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
let bfsPrev, bfsMark, bfsQueue; // allocated with the world
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
    if (bfsMark[j] === bfsGen || trail[j] === p.id || wall[j]) return;
    const nearHead = Math.abs(x - p.cx) <= 2 && Math.abs(y - p.cy) <= 2;
    if (padded && !nearHead && touchesOwnTrail(p, x, y)) return;
    if (padded && !nearHead && saws.length && nearSaw(x + 0.5, y + 0.5, 2.2)) return;
    if (!nearHead && portals.length && nearPortal(x + 0.5, y + 0.5, 1.8)) return;
    bfsMark[j] = bfsGen;
    bfsPrev[j] = from;
    bfsQueue[tail++] = j;
  };
  while (head < tail) {
    const i = bfsQueue[head++];
    if (owner[i] === p.id && (!storm || stormSafe((i % N) + 0.5, Math.floor(i / N) + 0.5, 1.5))) {
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
    const push = beltAt(x, y);
    let nx = clamp(x + (Math.cos(a) * v + (push ? push[0] * BELT_SPEED : 0)) * dt, 0.01, N - 0.01);
    let ny = clamp(y + (Math.sin(a) * v + (push ? push[1] * BELT_SPEED : 0)) * dt, 0.01, N - 0.01);
    // Walls aren't deadly: slide along them exactly like move() does
    if (isWallAt(nx, ny)) {
      if (!isWallAt(x, ny)) nx = x;
      else if (!isWallAt(nx, y)) ny = y;
      else { nx = x; ny = y; }
    }
    x = nx;
    y = ny;
    const fx = Math.floor(x), fy = Math.floor(y);
    if (fx === cx && fy === cy) continue;
    if (fx !== cx && fy !== cy && trail[cy * N + fx] === p.id && !wall[cy * N + fx]) return k;
    if (trail[fy * N + fx] === p.id) return k;
    if (owner[fy * N + fx] === p.id) return steps; // made it home
    cx = fx;
    cy = fy;
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

// Is the straight line between two points free of walls (and water)?
function clearLine(ax, ay, bx, by) {
  const steps = Math.ceil(Math.hypot(bx - ax, by - ay) * 2);
  for (let k = 0; k <= steps; k++) {
    const t = k / (steps || 1);
    if (isWallAt(ax + (bx - ax) * t, ay + (by - ay) * t)) return false;
  }
  return true;
}

// Will a saw run into this loop (you -> A -> B -> back) in the next few seconds?
function sawCrosses(p, A, B) {
  if (!saws.length && !portals.length) return false;
  const segDist = (x, y, a, b) => {
    const dx = b.x - a.x, dy = b.y - a.y, t = clamp(((x - a.x) * dx + (y - a.y) * dy) / (dx * dx + dy * dy || 1), 0, 1);
    return Math.hypot(x - (a.x + dx * t), y - (a.y + dy * t));
  };
  const legs = [[p, A], [A, B], [B, p]];
  if (portals.some(pt => legs.some(([a, b]) => segDist(pt.x, pt.y, a, b) < 2.2))) return true;
  for (const sw of saws) {
    for (const ahead of [0, 1, 2, 3, 4]) {
      const at = ahead ? sawAhead(sw, ahead) : sw;
      if (legs.some(([a, b]) => segDist(at.x, at.y, a, b) < 2.5)) return true;
    }
  }
  return false;
}

// A saw about to reach our head or trail?
function sawThreat(p) {
  for (const sw of saws) {
    for (const at of [sw, sawAhead(sw, 0.7)]) {
      if (Math.hypot(at.x - p.x, at.y - p.y) < 4) return true;
      for (let k = 0; k < p.trail.length; k += 2) {
        const i = p.trail[k];
        if (Math.hypot((i % N) + 0.5 - at.x, Math.floor(i / N) + 0.5 - at.y) < 2.8) return true;
      }
    }
  }
  return false;
}

// Is any of our trail (or our head) where the storm is about to be?
function stormThreat(p) {
  if (!storm || storm.phase === 'wait') return false;
  if (!stormSafe(p.x, p.y, 2)) return true;
  for (let k = 0; k < p.trail.length; k += 3) {
    const i = p.trail[k];
    if (!stormSafe((i % N) + 0.5, Math.floor(i / N) + 0.5, 1)) return true;
  }
  return false;
}

function planLoop(p) {
  const tight = gameMapId === 'islands' ? 0.55 : 1; // small islands: small loops
  const c = v => clamp(v, 1.5, N - 1.5);
  // Try a few random loops and keep the first whose three sides don't hit a wall
  for (let tries = 0; tries < 10; tries++) {
    const shrink = tries < 6 ? 1 : 0.5;
    const a = Math.random() * TAU;
    const len = rand(5, 11 + Math.min(10, counts[p.id] / 60)) * p.loopScale * tight * shrink;
    const wid = rand(4, 10) * p.loopScale * tight * shrink * (Math.random() < 0.5 ? -1 : 1);
    const A = { x: c(p.x + Math.cos(a) * len), y: c(p.y + Math.sin(a) * len) };
    const B = { x: c(A.x + Math.cos(a + Math.PI / 2) * wid), y: c(A.y + Math.sin(a + Math.PI / 2) * wid) };
    if (!stormSafe(A.x, A.y, 3) || !stormSafe(B.x, B.y, 3) || sawCrosses(p, A, B)) continue;
    if (clearLine(p.x, p.y, A.x, A.y) && clearLine(A.x, A.y, B.x, B.y) && clearLine(B.x, B.y, p.x, p.y)) {
      p.wp = [A, B];
      p.mode = 'loop';
      return;
    }
  }
  // Nowhere good to go right now: wander a little inside our own land and try again soon
  p.wp = [nearestOwn(p)];
  p.mode = 'idle';
}

function think(p) {
  const outside = p.trail.length > 0;

  // Hazards come first: get home (inside the ring) before the storm or a saw gets us
  if (p.mode !== 'home' && (stormThreat(p) || (outside && saws.length && sawThreat(p)))) {
    goHome(p);
    return;
  }

  // Head home if an enemy gets close while our trail is exposed, or if we got greedy
  if (outside && p.mode !== 'home') {
    const threat = p.mode !== 'hunt' && !p.isBoss && players.some(o => o && !allies(o, p) && o.alive && dist(o, p) < (p.fleeDist || 5));
    if (threat || p.trail.length > (gameMapId === 'islands' ? Math.min(p.greed, 22) : p.greed)) {
      goHome(p);
      return;
    }
  }

  // Hunt: go for the closest part of a nearby enemy trail. The bigger you get,
  // the further bots look for your trail and the more often they come for it.
  // The Giant only has eyes for you
  if (p.isBoss && p.mode !== 'home' && me.alive && me.trail.length >= 3 && me.fx.shield <= 0 && dist(me, p) < 30) {
    p.wp = [closestTrailPoint(p, me)];
    p.mode = 'hunt';
    return;
  }
  if (p.mode !== 'home' && p.mode !== 'hunt' && p.trail.length < 25) {
    const growth = me && me.alive ? clamp(pct(me) / 30, 0, 1) : 0;
    for (const o of players) {
      if (!o || allies(o, p) || !o.alive || o.trail.length < 4 || o.fx.shield > 0) continue;
      const bold = o === me ? growth : 0;
      if (dist(o, p) < 14 + bold * 12 + gameDiff.range && Math.random() < (p.aggro + bold * 0.4) * gameDiff.aggro) {
        p.wp = [closestTrailPoint(p, o)];
        p.mode = 'hunt';
        return;
      }
    }
  }

  // At home: sometimes go and grab a nearby power-up (Collectors also go for coins)
  if (!outside && p.mode !== 'grab') {
    const pu = powerups.find(q => Math.hypot(q.x - p.x, q.y - p.y) < 12 && stormSafe(q.x, q.y, 3))
      || (p.persona === 'collector' && mapCoins.find(c => Math.hypot(c.x - p.x, c.y - p.y) < 15 && stormSafe(c.x, c.y, 3)));
    if (pu && Math.random() < (p.grabChance || 0.5)) {
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
    p.think = gameDiff.think;
    think(p);
  }
  while (p.wp.length && dist(p, p.wp[0]) < 0.8) p.wp.shift();
  // Stuck against a wall, or the next waypoint is behind one: head home the safe way
  if (p.trail.length && p.mode !== 'home' && (p.blocked || (p.wp.length && !clearLine(p.x, p.y, p.wp[0].x, p.wp[0].y)))) goHome(p);
  else if (p.blocked && p.wp.length) p.wp.shift();
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
const isTouchDevice = window.matchMedia && window.matchMedia('(pointer: coarse)').matches;
const turnTouches = new Map(); // pointerId -> -1 (left half) or +1 (right half), for tap-to-turn
const stickRadius = () => (settings.stickSize === 'large' ? 80 : 50);

window.addEventListener('keydown', e => {
  const k = e.key.toLowerCase();
  if (e.target.tagName === 'INPUT' && k !== 'enter') return;
  keys.add(k);
  Sfx.unlock();
  if (k.startsWith('arrow') || 'wasd'.includes(k)) mouse.active = false;
  if ((k === 'p' || k === 'escape') && (state === 'play' || state === 'paused')) togglePause();
  if (k === 'm') toggleMute();
  if (k === 'n') toggleMusic();
  if (k >= '1' && k <= '6' && state === 'play') playerEmote(EMOTES[Number(k) - 1].id);
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
  if (settings.controls === 'turn') {
    turnTouches.set(e.pointerId, e.clientX < W / 2 ? -1 : 1);
    capturePointer(e.pointerId);
    return;
  }
  stick.active = true;
  stick.id = e.pointerId;
  stick.ox = stick.x = e.clientX;
  stick.oy = stick.y = e.clientY;
  capturePointer(e.pointerId);
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
function capturePointer(id) {
  try { canvas.setPointerCapture(id); } catch { /* pointer already gone */ }
}
const endStick = e => {
  // Letting go of tap-to-turn means "go straight now"
  if (turnTouches.delete(e.pointerId) && !turnTouches.size && me) me.desired = me.angle;
  if (e.pointerId === stick.id) stick.active = false;
};
canvas.addEventListener('pointerup', endStick);
canvas.addEventListener('pointercancel', endStick);

function steerKeys(p, up, down, left, right) {
  let x = 0, y = 0;
  if (keys.has(left)) x -= 1;
  if (keys.has(right)) x += 1;
  if (keys.has(up)) y -= 1;
  if (keys.has(down)) y += 1;
  if (x || y) p.desired = Math.atan2(y, x);
}

function steerHuman() {
  if (gameMode.duo) {
    // Player 1: WASD (or touch), Player 2: arrow keys
    steerKeys(me, 'w', 's', 'a', 'd');
    if (p2 && p2.alive) steerKeys(p2, 'arrowup', 'arrowdown', 'arrowleft', 'arrowright');
    return;
  }
  let x = 0, y = 0;
  if (keys.has('a') || keys.has('arrowleft')) x -= 1;
  if (keys.has('d') || keys.has('arrowright')) x += 1;
  if (keys.has('w') || keys.has('arrowup')) y -= 1;
  if (keys.has('s') || keys.has('arrowdown')) y += 1;
  if (turnTouches.size) {
    // Tap-to-turn: hold the left or right half of the screen to turn that way
    let side = 0;
    for (const v of turnTouches.values()) side += v;
    me.desired = me.angle + Math.sign(side) * 1.2;
    return;
  }
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
  refreshLocker();
}

function buildPickers() {
  const seg = (boxId, items, current, onPick, disabled) => {
    const box = $(boxId);
    box.innerHTML = '';
    for (const [id, item] of Object.entries(items)) {
      if (item.hidden) continue;
      const b = document.createElement('button');
      b.className = 'seg-btn' + (id === current ? ' picked' : '');
      b.textContent = item.name;
      b.disabled = !!disabled;
      b.addEventListener('click', () => onPick(id));
      box.appendChild(b);
    }
  };
  const daily = !!fixedMap(myMode);
  seg('modes', MODES, myMode, id => { myMode = id; save('color-claim-mode', id); buildPickers(); });
  seg('diffs', DIFFICULTY, myDiff, id => { myDiff = id; save('color-claim-diff', id); buildPickers(); });
  const allMaps = { ...MAPS };
  loadCustomMaps().forEach((m, i) => { if (m) allMaps['custom' + i] = { name: m.name }; });
  if (!allMaps[myMap]) myMap = 'square';
  seg('maps', allMaps, daily ? fixedMap(myMode) : myMap, id => { myMap = id; save('color-claim-map', id); buildPickers(); }, daily || MODES[myMode].cup);
  const ranked = RANKED_MODES.includes(myMode) && (daily || !myMap.startsWith('custom'));
  $('mode-desc').textContent = MODES[myMode].desc + (ranked ? ' · Ranked' : '') + (daily ? ` · ${MODES[myMode].weekly ? "This week's" : "Today's"} map: ${MAPS[fixedMap(myMode)].name}` : '')
    + (myDiff !== 'normal' ? ` · ${DIFFICULTY[myDiff].name} bots pay ×${DIFFICULTY[myDiff].coins} coins` : '')
    + (!daily && myMap.startsWith('custom') && MODES[myMode].size !== CUSTOM_SIZE ? ' · Custom maps are always normal size' : '');
  updateMenuBest();
}

$('name-input').value = myName;
$('name-input').addEventListener('input', e => {
  myName = e.target.value.trim().slice(0, 12);
  save('color-claim-name', myName);
});

// ---------- Game flow ----------
function startGame() {
  gameCounter++;
  // Every game's starting layout comes from a seed, so it can be shared as a challenge.
  // Daily uses the date as its seed; a challenge uses its friend's seed.
  const cfg = tutorialOn ? { mode: 'tutorial', map: 'square', diff: 'normal' } : challenge || { mode: myMode, map: myMap, diff: myDiff };
  gameModeId = cfg.mode;
  gameMode = MODES[cfg.mode];
  gameDiffId = cfg.diff;
  gameDiff = DIFFICULTY[cfg.diff];
  if (gameMode.cup && (!cup || cup.round > 3)) cup = newCup();
  gameMapId = fixedMap(cfg.mode) || (gameMode.cup ? cup.maps[cup.round - 1] : cfg.map);
  gameSeed = challenge ? challenge.seed
    : gameMode.daily ? hashStr('color-claim-' + todayKey())
    : gameMode.weekly ? hashStr('color-claim-week-' + weekInfo().week)
    : gameMode.cup ? cup.seed
    : (Math.random() * 4294967296) >>> 0;
  random = mulberry32(gameSeed);
  // Custom maps are always 80 x 80
  allocWorld(gameMapId.startsWith('custom') ? CUSTOM_SIZE : gameMode.size);
  buildMap(gameMapId);
  buildHazards(gameMapId);
  counts.fill(0);
  particles = [];
  flashes = [];
  fades = [];
  floats = [];
  feed = [];
  renderFeed();
  rgbCache.length = 0;
  players = [null];
  const duo = !!gameMode.duo;
  me = makePlayer(1, duo ? myName || 'Player 1' : myName || 'You', COLORS[myColor], false, mySkin);
  players.push(me);
  p2 = null;
  const taken = [myColor];
  if (duo) {
    const c2 = (myColor + 4) % COLORS.length;
    taken.push(c2);
    p2 = makePlayer(2, 'Player 2', COLORS[c2], false, 'classic');
    players.push(p2);
  }
  const botColors = COLORS.filter((_, i) => !taken.includes(i));
  const names = BOT_NAMES.slice().sort(() => random() - 0.5).slice(0, gameMode.tutorial || gameMode.boss ? 0 : botColors.length);
  names.forEach((name, i) => players.push(makePlayer(players.length, name, botColors[i], true, SKINS[randInt(0, SKINS.length - 1)].id)));
  // Personalities: a mix of hunters, turtles, explorers, collectors and wildcards
  const mix = PERSONA_MIX.slice().sort(() => random() - 0.5);
  players.filter(p => p && p.isBot).forEach((p, i) => givePersonality(p, mix[i % mix.length]));
  // Pets (Math.random, so the seeded layout stays the same)
  me.pet = myPet;
  for (const p of players) if (p && p.isBot && Math.random() < 0.3) p.pet = BOT_PETS[Math.floor(Math.random() * BOT_PETS.length)];
  // Teams: you and the first 3 bots against the other 4. Otherwise everyone is on their own.
  for (const p of players) if (p) p.team = gameMode.teams ? (p.id <= 4 ? 0 : 1) : p.id;
  giant = null;
  powerups = [];
  powerTimer = 3;
  mapCoins = [];
  coinTimer = 3;
  freezer = null;
  if (duo) {
    spawn(me, Math.round(N * 0.3), N / 2);
    spawn(p2, Math.round(N * 0.7), N / 2);
  } else {
    spawn(me, N / 2, N / 2);
  }
  for (const p of players) if (p && p.isBot) spawn(p);
  king = null;
  lives = gameMode.boss ? 3 : 1;
  if (gameMode.boss) spawnKing();
  if (p2) { cam2.x = p2.x; cam2.y = p2.y; cam2.zoom = 0.8; }
  random = Math.random;
  playTime = 0;
  run = { powerups: 0, bigLoop: 0, freezeKO: false, trophies: [], coinsPicked: 0, giantKO: false, teleports: 0, bossHits: 0, beatGhost: false };
  replayFrames = [];
  replayTimer = 0;
  startGhost();
  emoteCooldown = 0;
  $('emote-tray').classList.add('hidden');
  resetGif();
  fxParts = [];
  achTimer = 1;
  cam.x = me.x;
  cam.y = me.y;
  cam.zoom = duo ? 0.8 : 1;
  peakPct = 0;
  time = 0;
  shake = 0;
  countdown = 3;
  goFlash = 0;
  threats = [];
  stick.active = false;
  turnTouches.clear();
  $('name-input').blur();
  state = 'play';
  showScreen(null);
  Sfx.play('beep');
  Music.track = gameMode.boss ? 'boss' : settings.track;
  Music.start();
  const ev = weekInfo().event;
  if (gameMode.boss) {
    later(3400, () => { toast(`Cut the King's trail ${king.maxHp} times to win!`); Sfx.play('roar'); });
  } else later(3400, () => toast(`${ev.name}: ${ev.desc}`));
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
  const prevBest = bestFor(gameModeId);
  const isBest = score > prevBest;
  if (gameMode.weekly && ghostRun && score > ghostRun.score) run.beatGhost = true;
  if (isBest) save(bestKey(gameModeId), score);
  if (gameModeId === 'classic') best = Math.max(best, score);

  // Update lifetime stats and announce any skins that just unlocked
  const before = SKINS.filter(isUnlocked);
  const { earned, fresh: trophies, xpGain, levelsUp, levelCoins, missionsDone, missionCoins, seasonRewards, ranked, streakDay } = finishRun(won, score);
  showRankResult(ranked);
  $('over-streak').classList.toggle('hidden', !streakDay);
  if (streakDay) {
    $('over-streak').innerHTML = `${FLAME}<b>Day ${streakDay.day} streak!</b> +${streakDay.coins} coins${streakDay.pet ? ' · <b>Star Sprite pet unlocked!</b>' : ''}`;
    if (streakDay.pet) toast('7-day streak! Star Sprite pet unlocked in the Locker');
  }
  const fresh = SKINS.filter(sk => isUnlocked(sk) && !before.includes(sk));
  $('over-unlock').textContent = fresh.length ? `🎁 New skin unlocked: ${fresh.map(sk => sk.name).join(', ')}! Find it in the Locker.` : '';
  $('over-unlock').classList.toggle('hidden', !fresh.length);
  if (fresh.length || trophies.length) Sfx.play('trophy');
  const bonus = trophies.length * ACH_REWARD;
  const extras = [bonus && `+${bonus} from trophies`, run.coinsPicked && `+${run.coinsPicked} picked up`, missionCoins && `+${missionCoins} from missions`, levelCoins && `+${levelCoins} level bonus`].filter(Boolean);
  $('over-coins').innerHTML = `+${earned} <span class="coin"></span> coins${extras.length ? ` <small>(${extras.join(' · ')})</small>` : ''}`;
  const lv = levelInfo(xp);
  $('over-xp').innerHTML = `+${xpGain} XP · Level ${lv.lvl}${levelsUp ? ' <b>Level up!</b>' : ''}<span class="xpbar"><span style="width:${(lv.into / lv.need) * 100}%"></span></span>`;
  $('over-missions').innerHTML = missionsDone.map(m => `<li>✓ Mission done: ${m.text} <small>+${m.reward}</small></li>`).join('');
  $('over-missions').classList.toggle('hidden', !missionsDone.length);
  $('over-season').innerHTML = seasonRewards.map(r => `<li>Season tier ${r.tier}: ${r.text}</li>`).join('');
  $('over-season').classList.toggle('hidden', !seasonRewards.length);
  renderLevel();
  $('over-ach').innerHTML = trophies.map(a => `<li>${Icons.trophy}${a.name} <small>+${ACH_REWARD}</small></li>`).join('');
  $('over-ach').classList.toggle('hidden', !trophies.length);
  refreshLocker();
  $('over-title').textContent = won ? '🏆 You win!' : 'Game Over';
  $('over-reason').textContent = reason;
  $('over-stats').textContent = `Best size: ${score.toFixed(1)}% · ${me.kills} knockouts`;
  const label = gameModeId === 'daily' ? "Today's best" : gameModeId === 'weekly' ? "This week's best" : `${gameMode.name} best`;
  if (gameMode.weekly && isBest && ghostRec) saveGhost(score);
  $('over-best').textContent = isBest ? `New ${label.toLowerCase()}!${gameMode.weekly ? ' Your ghost will race you next time.' : ''}` : `${label}: ${prevBest.toFixed(1)}%`;

  // Playing a friend's challenge: did you beat their score?
  $('challenge-result').classList.toggle('hidden', !challenge);
  if (challenge) {
    const beat = score > challenge.score;
    $('challenge-result').className = 'challenge-result ' + (beat ? 'good' : 'bad');
    $('challenge-result').textContent = beat
      ? `✓ Challenge beaten: ${score.toFixed(1)}% vs ${challenge.score.toFixed(1)}%!`
      : `✗ Challenge not beaten: ${score.toFixed(1)}% vs ${challenge.score.toFixed(1)}%. Try again!`;
    if (beat) challengeBeaten();
  }
  // Offer a challenge code for this game (not for 2 players, the Cup or custom maps)
  const shareable = !gameMode.duo && !gameMode.cup && !gameMode.boss && !gameMapId.startsWith('custom');
  $('challenge-share').classList.toggle('hidden', !shareable);
  $('challenge-code').classList.add('hidden');
  lastChallenge = shareable ? { seed: gameSeed, mode: gameMode.daily ? 'classic' : gameMode.weekly ? 'timed' : gameModeId, map: gameMapId, diff: gameDiffId, score } : null;

  if (gameMode.cup) {
    scoreCupRound();
    showCup(earned);
    return;
  }
  $('replay-btn').classList.toggle('hidden', replayFrames.length < 5);
  $('gif-box').classList.toggle('hidden', replayFrames.length < 5);
  showScreen('over');
}

function win(reason = `You claimed ${gameMode.win}% of the map!`) {
  state = 'won';
  players.filter(p => p && p.isBot && p.alive && !p.isBoss).sort((a, b) => dist(a, me) - dist(b, me)).slice(0, 2)
    .forEach((p, i) => later(300 + i * 400, () => botEmote(p, 'gg')));
  Sfx.play('win');
  for (let i = 0; i < 6; i++) burst(me.x + rand(-8, 8), me.y + rand(-6, 6), COLORS[i], 30, 14);
  later(1600, () => endGame(true, reason));
}

// 2 players: celebrate, then show who won. These games don't give coins or trophies.
function duoWin(p) {
  state = 'won';
  Sfx.play('win');
  for (let i = 0; i < 6; i++) burst(p.x + rand(-8, 8), p.y + rand(-6, 6), COLORS[i], 30, 14);
  later(1600, () => endDuo(p, `${p.name} claimed ${gameMode.win}% of the map!`));
}

function endDuo(winner, reason) {
  if (state === 'over' || state === 'menu') return;
  state = 'over';
  Music.stop();
  $('over-title').textContent = `🏆 ${winner.name} wins!`;
  $('over-reason').textContent = reason;
  $('over-stats').textContent = `${me.name} ${pct(me).toFixed(1)}% · ${p2.name} ${pct(p2).toFixed(1)}%`;
  $('over-best').textContent = "2-player games are just for fun: they don't give coins, XP or trophies.";
  for (const id of ['over-coins', 'over-xp']) $(id).innerHTML = '';
  for (const id of ['over-missions', 'over-season', 'over-unlock', 'over-ach', 'over-rank', 'over-streak']) $(id).classList.add('hidden');
  $('replay-btn').classList.toggle('hidden', replayFrames.length < 5);
  $('gif-box').classList.toggle('hidden', replayFrames.length < 5);
  showScreen('over');
}

// ---------- Tutorial ----------
let tutorialOn = false;
let tut = { step: 0, dummy: null };
const TUT_STEPS = [
  { text: 'Move out of your land. A trail follows you!', done: () => me.trail.length >= 6 },
  { text: 'Now head back into your land to claim everything inside the loop.', done: () => run.bigLoop > 0 },
  { text: 'Grab the power-up. Follow the green arrow!', enter: () => tutPowerup(), done: () => run.powerups >= 1 },
  { text: "A practice bot is drawing a trail. Touch its trail to knock it out!", enter: () => tutDummy(), done: () => me.kills >= 1 },
  { text: 'Last step: claim 15% of the map.', done: () => pct(me) >= 15 },
];

function tutPowerup() {
  for (let d = 7; d < 20; d++) {
    const x = clamp(Math.round(me.x + Math.cos(me.angle) * d), 3, N - 4), y = clamp(Math.round(me.y + Math.sin(me.angle) * d), 3, N - 4);
    if (owner[y * N + x] !== me.id) { powerups = [{ x: x + 0.5, y: y + 0.5, kind: 'speed', age: 0 }]; return; }
  }
  powerups = [{ x: 8.5, y: 8.5, kind: 'speed', age: 0 }];
}

function tutDummy() {
  const d = makePlayer(players.length, 'Practice bot', COLORS[(myColor + 3) % COLORS.length], true, 'classic');
  givePersonality(d, 'explorer');
  d.aggro = 0;         // never hunts you
  d.fleeDist = 0;      // doesn't run away either
  d.team = d.id;
  players.push(d);
  spawn(d, me.cx > N / 2 ? 10 : N - 11, me.cy > N / 2 ? 10 : N - 11);
  d.fx.shield = 0;
  tut.dummy = d;
}

function tutTarget() {
  if (tut.step === 2 && powerups[0]) return powerups[0];
  if (tut.step === 3 && tut.dummy && tut.dummy.alive) return tut.dummy.trail.length ? closestTrailPoint(me, tut.dummy) : tut.dummy;
  return null;
}

function updateTutorial() {
  // The practice bot comes back if it crashes before you catch it
  if (tut.step === 3 && tut.dummy && !tut.dummy.alive && me.kills < 1) { tut.dummy.alive = false; spawn(tut.dummy); tut.dummy.fx.shield = 0; }
  const step = TUT_STEPS[tut.step];
  if (step && step.done()) {
    tut.step++;
    Sfx.play('capture');
    buzz(20);
    const next = TUT_STEPS[tut.step];
    if (next && next.enter) next.enter();
    if (!next) finishTutorial();
  }
  renderTutorial();
}

function renderTutorial() {
  const step = TUT_STEPS[tut.step];
  $('tutorial-panel').classList.toggle('hidden', !gameMode.tutorial);
  $('tutorial-step').textContent = step ? `Step ${tut.step + 1} of ${TUT_STEPS.length}` : 'Done!';
  $('tutorial-text').textContent = step ? step.text : 'Tutorial complete! You know everything you need. Have fun!';
}

function finishTutorial() {
  const first = load('color-claim-tutorial-done', '') !== '1';
  save('color-claim-tutorial-done', '1');
  if (first) addCoins(50);
  toast(first ? 'Tutorial complete! +50 coins' : 'Tutorial complete!');
  Sfx.play('win');
  for (let i = 0; i < 6; i++) burst(me.x + rand(-6, 6), me.y + rand(-5, 5), COLORS[i], 25, 12);
  state = 'won';
  later(2200, leaveTutorial);
}

function leaveTutorial() {
  tutorialOn = false;
  gameCounter++;
  $('tutorial-panel').classList.add('hidden');
  Music.stop();
  state = 'menu';
  me = null;
  showScreen('menu');
}

function startTutorial() {
  tutorialOn = true;
  tut = { step: 0, dummy: null };
  startGame();
  countdown = 0;
  renderTutorial();
}

// ---------- Pets ----------
// A little friend that follows your square around (some bots bring one too).
// How each one unlocks lives in progress.js.
const PETS = [
  { id: 'none', name: 'No pet' },
  { id: 'chick', name: 'Chick', price: 0 },
  { id: 'slime', name: 'Slime', price: 120 },
  { id: 'bat', name: 'Bat', price: 200 },
  { id: 'kitty', name: 'Kitty', rank: 1 },
  { id: 'dragon', name: 'Dragon', rank: 2 },
  { id: 'ufo', name: 'UFO', rank: 3 },
  { id: 'star', name: 'Star Sprite', streak: 7 },
];
const BOT_PETS = ['chick', 'slime', 'bat', 'kitty'];

function updatePet(p, dt) {
  // Trot along behind, a little late
  const tx = p.x - Math.cos(p.angle) * 1.4, ty = p.y - Math.sin(p.angle) * 1.4;
  const k = Math.min(1, dt * 9);
  if (Math.abs(tx - p.petX) > 0.01) p.petFace = tx > p.petX ? 1 : -1;
  p.petX += (tx - p.petX) * k;
  p.petY += (ty - p.petY) * k;
}

// Draws pet `id` centred on (x, y), about `s` pixels tall; t is time, face is 1 (right) or -1
function drawPet(g, id, x, y, s, t, face = 1) {
  const r = s / 2;
  g.save();
  g.translate(x, y);
  g.scale(face, 1);
  const eye = (ex, ey, er = 0.12) => {
    g.fillStyle = '#26304a';
    g.beginPath();
    g.arc(ex * r, ey * r, er * r, 0, TAU);
    g.fill();
    g.fillStyle = '#fff';
    g.beginPath();
    g.arc(ex * r + er * r * 0.35, ey * r - er * r * 0.35, er * r * 0.4, 0, TAU);
    g.fill();
  };
  const blob = (cx, cy, rx, ry, color) => {
    g.fillStyle = color;
    g.beginPath();
    g.ellipse(cx * r, cy * r, rx * r, ry * r, 0, 0, TAU);
    g.fill();
  };
  // Soft shadow
  g.fillStyle = 'rgba(38, 48, 74, 0.15)';
  g.beginPath();
  g.ellipse(0, r * 0.95, r * 0.7, r * 0.2, 0, 0, TAU);
  g.fill();
  if (id === 'chick') {
    const hop = Math.abs(Math.sin(t * 8)) * r * 0.25;
    g.translate(0, -hop);
    blob(0, 0.1, 0.8, 0.75, '#ffd23f');
    blob(-0.25, 0.25, 0.35, 0.25, '#f5b400');
    g.fillStyle = '#ff8c42';
    g.beginPath();
    g.moveTo(r * 0.7, -r * 0.05);
    g.lineTo(r * 1.1, r * 0.08);
    g.lineTo(r * 0.7, r * 0.22);
    g.fill();
    eye(0.35, -0.2);
  } else if (id === 'slime') {
    const sq = Math.sin(t * 6) * 0.12;
    g.fillStyle = '#6fd66f';
    g.beginPath();
    g.moveTo(-r * (0.9 + sq), r * 0.8);
    g.quadraticCurveTo(-r * (0.9 + sq), -r * (0.8 - sq), 0, -r * (0.8 - sq));
    g.quadraticCurveTo(r * (0.9 + sq), -r * (0.8 - sq), r * (0.9 + sq), r * 0.8);
    g.closePath();
    g.fill();
    blob(-0.35, -0.35, 0.18, 0.1, 'rgba(255, 255, 255, 0.6)');
    eye(-0.2, 0.05);
    eye(0.3, 0.05);
  } else if (id === 'bat') {
    const flap = Math.sin(t * 16);
    g.translate(0, -r * 0.4 + Math.sin(t * 4) * r * 0.15);
    g.fillStyle = '#7d4fd6';
    for (const side of [-1, 1]) {
      g.beginPath();
      g.moveTo(side * r * 0.4, -r * 0.1);
      g.lineTo(side * r * 1.4, -r * (0.5 + flap * 0.4));
      g.lineTo(side * r * 1.1, r * 0.15);
      g.lineTo(side * r * 0.8, -r * 0.05);
      g.lineTo(side * r * 0.6, r * 0.3);
      g.closePath();
      g.fill();
    }
    blob(0, 0, 0.55, 0.55, '#9b6bff');
    g.fillStyle = '#9b6bff';
    g.beginPath();
    g.moveTo(-r * 0.4, -r * 0.3);
    g.lineTo(-r * 0.3, -r * 0.8);
    g.lineTo(-r * 0.1, -r * 0.4);
    g.moveTo(r * 0.4, -r * 0.3);
    g.lineTo(r * 0.3, -r * 0.8);
    g.lineTo(r * 0.1, -r * 0.4);
    g.fill();
    eye(-0.18, -0.05, 0.1);
    eye(0.2, -0.05, 0.1);
  } else if (id === 'kitty') {
    const hop = Math.abs(Math.sin(t * 7)) * r * 0.15;
    g.translate(0, -hop);
    g.fillStyle = '#ffa94d';
    g.beginPath();
    g.moveTo(-r * 0.7, -r * 0.3);
    g.lineTo(-r * 0.55, -r * 0.95);
    g.lineTo(-r * 0.15, -r * 0.55);
    g.moveTo(r * 0.7, -r * 0.3);
    g.lineTo(r * 0.55, -r * 0.95);
    g.lineTo(r * 0.15, -r * 0.55);
    g.fill();
    blob(0, 0.1, 0.8, 0.7, '#ffa94d');
    blob(0, 0.35, 0.35, 0.22, '#fff1e0');
    eye(-0.3, 0);
    eye(0.3, 0);
    g.strokeStyle = 'rgba(38, 48, 74, 0.5)';
    g.lineWidth = Math.max(1, r * 0.06);
    g.beginPath();
    for (const side of [-1, 1]) {
      g.moveTo(side * r * 0.35, r * 0.3);
      g.lineTo(side * r * 0.95, r * 0.2);
      g.moveTo(side * r * 0.35, r * 0.38);
      g.lineTo(side * r * 0.95, r * 0.45);
    }
    g.stroke();
  } else if (id === 'dragon') {
    const flap = Math.sin(t * 10);
    g.translate(0, -r * 0.3 + Math.sin(t * 3) * r * 0.12);
    g.fillStyle = '#2eaa6a';
    g.beginPath();
    g.moveTo(-r * 0.2, -r * 0.2);
    g.lineTo(-r * 0.9, -r * (0.9 + flap * 0.3));
    g.lineTo(-r * 0.6, 0);
    g.closePath();
    g.fill();
    blob(0, 0.1, 0.75, 0.62, '#3ccf82');
    blob(0.1, 0.35, 0.4, 0.22, '#c7f5d9');
    g.fillStyle = '#ffd23f';
    g.beginPath();
    g.moveTo(r * 0.1, -r * 0.4);
    g.lineTo(r * 0.2, -r * 0.9);
    g.lineTo(r * 0.4, -r * 0.45);
    g.fill();
    eye(0.4, -0.1);
    if (Math.sin(t * 2) > 0.85) { // a puff of smoke now and then
      blob(1.05, 0.05, 0.14, 0.14, 'rgba(160, 170, 190, 0.7)');
      blob(1.3, -0.1, 0.1, 0.1, 'rgba(160, 170, 190, 0.5)');
    }
  } else if (id === 'ufo') {
    g.translate(0, -r * 0.5 + Math.sin(t * 3) * r * 0.15);
    g.rotate(Math.sin(t * 2) * 0.12);
    blob(0, -0.15, 0.45, 0.4, 'rgba(111, 195, 255, 0.85)');
    blob(0, 0.1, 1, 0.32, '#8d97ab');
    blob(0, 0.02, 0.9, 0.18, '#aab4c8');
    for (let k = -1; k <= 1; k++) blob(k * 0.55, 0.18, 0.09, 0.09, Math.floor(t * 4 + k) % 2 ? '#ffd23f' : '#ff5d73');
    eye(-0.12, -0.18, 0.08);
    eye(0.14, -0.18, 0.08);
  } else if (id === 'star') {
    g.translate(0, -r * 0.4 + Math.sin(t * 4) * r * 0.15);
    const glow = g.createRadialGradient(0, 0, 0, 0, 0, r * 1.4);
    glow.addColorStop(0, 'rgba(255, 210, 63, 0.5)');
    glow.addColorStop(1, 'rgba(255, 210, 63, 0)');
    g.fillStyle = glow;
    g.beginPath();
    g.arc(0, 0, r * 1.4, 0, TAU);
    g.fill();
    g.rotate(Math.sin(t * 2) * 0.25);
    g.fillStyle = '#ffd23f';
    g.beginPath();
    for (let k = 0; k < 10; k++) {
      const a = -Math.PI / 2 + (k * Math.PI) / 5, rr = k % 2 ? r * 0.45 : r;
      g.lineTo(Math.cos(a) * rr, Math.sin(a) * rr);
    }
    g.closePath();
    g.fill();
    eye(-0.18, 0, 0.1);
    eye(0.18, 0, 0.1);
  }
  g.restore();
}

// ---------- Weekly ghost ----------
// In the Weekly tournament your best run this week is recorded (where you went, and how
// big you were) and replayed as a see-through ghost next time you play.
let ghostRun = null, ghostRec = null;
const ghostKey = () => `color-claim-ghost-${weekInfo().week}`;

function startGhost() {
  ghostRun = null;
  ghostRec = null;
  if (!gameMode.weekly) return;
  try { ghostRun = JSON.parse(load(ghostKey(), 'null')); } catch { ghostRun = null; }
  ghostRec = { path: [], pcts: [] };
}

function recordGhost() {
  // One point every 0.1 s of play: position (in tenths of a cell) and your land
  while (ghostRec.pcts.length <= playTime * 10) {
    ghostRec.path.push(Math.round(me.x * 10), Math.round(me.y * 10));
    ghostRec.pcts.push(Math.round(pct(me) * 10));
  }
}

function saveGhost(score) {
  save(ghostKey(), JSON.stringify({ score, path: ghostRec.path, pcts: ghostRec.pcts }));
  // Older weeks' ghosts aren't needed any more
  try {
    for (let i = localStorage.length - 1; i >= 0; i--) {
      const k = localStorage.key(i);
      if (k && k.startsWith('color-claim-ghost-') && k !== ghostKey()) localStorage.removeItem(k);
    }
  } catch { /* storage unavailable */ }
}

// Where the ghost is right now (null once its run had ended)
function ghostNow() {
  if (!ghostRun || !ghostRun.pcts || !ghostRun.pcts.length) return null;
  const k = playTime * 10, i = Math.floor(k);
  if (i >= ghostRun.pcts.length - 1) return null;
  const t = k - i, P = ghostRun.path;
  const x = (P[i * 2] + (P[i * 2 + 2] - P[i * 2]) * t) / 10, y = (P[i * 2 + 1] + (P[i * 2 + 3] - P[i * 2 + 1]) * t) / 10;
  const angle = Math.atan2(P[i * 2 + 3] - P[i * 2 + 1], P[i * 2 + 2] - P[i * 2]);
  return { x, y, angle, pct: ghostRun.pcts[i] / 10 };
}

function drawGhost(x0, y0) {
  const g = ghostNow();
  if (!g || !me) return;
  const gx = g.x * CELL - x0, gy = g.y * CELL - y0, sz = CELL * 1.4;
  if (gx < -60 || gy < -60 || gx > W + 60 || gy > H + 60) return;
  ctx.save();
  ctx.globalAlpha = 0.38;
  ctx.translate(gx, gy);
  ctx.rotate(g.angle);
  drawBody(ctx, { color: me.color, dark: me.dark, skin: me.skin, blink: 1, hueOff: me.hueOff }, sz, time);
  ctx.restore();
  ctx.globalAlpha = 0.7;
  ctx.font = `bold ${Math.round(CELL * 0.7)}px system-ui, sans-serif`;
  ctx.textAlign = 'center';
  ctx.fillStyle = 'rgba(38, 48, 74, 0.9)';
  ctx.fillText(`Best run · ${g.pct.toFixed(1)}%`, gx, gy - sz * 0.85);
  ctx.globalAlpha = 1;
}

// ---------- Emotes ----------
// Press 1-6 (or the smiley button) to pop a bubble over your square. Nearby bots answer back.
const EMOTES = [
  { id: 'hi', name: 'Hi!' },
  { id: 'lol', name: 'LOL' },
  { id: 'grr', name: 'Grr' },
  { id: 'cool', name: 'Cool' },
  { id: 'love', name: 'Love' },
  { id: 'gg', name: 'GG' },
];
const PERSONA_EMOTES = {
  hunter: ['grr', 'cool'], turtle: ['hi', 'love'], explorer: ['lol', 'hi'], collector: ['cool', 'love'], wildcard: ['lol', 'grr', 'gg', 'love'],
};
const EMOTE_TIME = 2.2;
let emoteCooldown = 0;

function playerEmote(id) {
  if (state !== 'play' || !me || !me.alive || emoteCooldown > 0) return false;
  emoteCooldown = 1.2;
  me.emote = { id, t: 0 };
  run.emotes = (run.emotes || 0) + 1;
  Sfx.play('emote');
  $('emote-tray').classList.add('hidden');
  // The nearest bot usually answers
  const bot = players.filter(p => p && p.isBot && p.alive && !p.isBoss && dist(p, me) < 25).sort((a, b) => dist(a, me) - dist(b, me))[0];
  if (bot && Math.random() < 0.85) {
    const mine = PERSONA_EMOTES[bot.persona] || PERSONA_EMOTES.wildcard;
    const reply = (id === 'hi' || id === 'gg') && Math.random() < 0.6 ? id : mine[Math.floor(Math.random() * mine.length)];
    later(rand(500, 1200), () => botEmote(bot, reply));
  }
  return true;
}

function botEmote(p, id) {
  if (!settings.emotes || !p || !p.alive || (p.emoteWait || 0) > time) return;
  p.emoteWait = time + 3;
  p.emote = { id, t: 0 };
  if (me && dist(p, me) < 25) Sfx.play('emote');
}

// Draws an emote centred on (x, y) with radius r (faces, a heart, or "GG")
function drawEmote(g, id, x, y, r) {
  g.save();
  g.translate(x, y);
  const pen = (w, color = '#5a3f00') => {
    g.lineWidth = Math.max(1.2, r * w);
    g.lineCap = 'round';
    g.strokeStyle = color;
  };
  const dot = (dx, dy, rr, color = '#5a3f00') => {
    g.fillStyle = color;
    g.beginPath();
    g.arc(dx * r, dy * r, rr * r, 0, TAU);
    g.fill();
  };
  if (id === 'love') {
    g.fillStyle = '#ff5d73';
    g.beginPath();
    g.moveTo(0, r * 0.85);
    g.bezierCurveTo(-r * 1.35, -r * 0.05, -r * 0.6, -r * 1.05, 0, -r * 0.4);
    g.bezierCurveTo(r * 0.6, -r * 1.05, r * 1.35, -r * 0.05, 0, r * 0.85);
    g.fill();
    dot(-0.42, -0.42, 0.14, 'rgba(255, 255, 255, 0.7)');
  } else if (id === 'gg') {
    g.fillStyle = '#4f8cff';
    g.font = `900 ${Math.round(r * 1.2)}px system-ui, sans-serif`;
    g.textAlign = 'center';
    g.textBaseline = 'middle';
    g.fillText('GG', 0, r * 0.08);
    g.textBaseline = 'alphabetic';
  } else {
    g.fillStyle = id === 'grr' ? '#ff7a5c' : '#ffc93c';
    g.beginPath();
    g.arc(0, 0, r, 0, TAU);
    g.fill();
    pen(0.08, 'rgba(90, 63, 0, 0.35)');
    g.stroke();
    if (id === 'hi') {
      dot(-0.33, -0.2, 0.12);
      dot(0.33, -0.2, 0.12);
      pen(0.11);
      g.beginPath();
      g.arc(0, 0.02, r * 0.5, 0.15 * Math.PI, 0.85 * Math.PI);
      g.stroke();
      dot(-0.62, 0.25, 0.13, 'rgba(255, 93, 115, 0.45)');
      dot(0.62, 0.25, 0.13, 'rgba(255, 93, 115, 0.45)');
    } else if (id === 'lol') {
      pen(0.1);
      for (const sx of [-1, 1]) {
        g.beginPath();
        g.arc(sx * 0.35 * r, -0.12 * r, r * 0.17, Math.PI * 1.1, Math.PI * 1.9);
        g.stroke();
      }
      g.fillStyle = '#5a3f00';
      g.beginPath();
      g.arc(0, 0.12 * r, r * 0.45, 0, Math.PI);
      g.closePath();
      g.fill();
      dot(-0.8, 0.02, 0.16, '#6fc3ff');
      dot(0.8, 0.02, 0.16, '#6fc3ff');
    } else if (id === 'grr') {
      pen(0.1);
      g.beginPath();
      g.moveTo(-0.62 * r, -0.5 * r);
      g.lineTo(-0.15 * r, -0.28 * r);
      g.moveTo(0.62 * r, -0.5 * r);
      g.lineTo(0.15 * r, -0.28 * r);
      g.stroke();
      dot(-0.33, -0.08, 0.11);
      dot(0.33, -0.08, 0.11);
      g.beginPath();
      g.arc(0, 0.68 * r, r * 0.34, 1.15 * Math.PI, 1.85 * Math.PI);
      g.stroke();
    } else if (id === 'cool') {
      g.fillStyle = '#26304a';
      for (const sx of [-1, 1]) {
        g.beginPath();
        g.roundRect(sx * 0.36 * r - 0.3 * r, -0.36 * r, 0.6 * r, 0.36 * r, 0.12 * r);
        g.fill();
      }
      pen(0.08, '#26304a');
      g.beginPath();
      g.moveTo(-0.1 * r, -0.26 * r);
      g.lineTo(0.1 * r, -0.26 * r);
      g.stroke();
      pen(0.1);
      g.beginPath();
      g.arc(0.08 * r, 0.12 * r, r * 0.4, 0.2 * Math.PI, 0.7 * Math.PI);
      g.stroke();
    }
  }
  g.restore();
}

// The speech bubble over a square, popping in and fading out
function drawEmoteBubble(e, x, y) {
  const t = e.t, k = Math.min(1, t / 0.25);
  const pop = t < 0.25 ? 1 + 2.7 * (k - 1) ** 3 + 1.7 * (k - 1) ** 2 : 1; // ease out, with a little overshoot
  const r = Math.max(13, CELL * 1.05) * pop;
  ctx.save();
  ctx.globalAlpha = t > EMOTE_TIME - 0.3 ? Math.max(0, (EMOTE_TIME - t) / 0.3) : 1;
  ctx.translate(x, y - r * 1.5 - t * 3);
  ctx.fillStyle = '#fff';
  ctx.strokeStyle = 'rgba(38, 48, 74, 0.2)';
  ctx.lineWidth = 2;
  ctx.beginPath();
  ctx.arc(0, 0, r * 1.2, 0, TAU);
  ctx.fill();
  ctx.stroke();
  ctx.beginPath();
  ctx.moveTo(-r * 0.3, r * 1.05);
  ctx.lineTo(0, r * 1.6);
  ctx.lineTo(r * 0.3, r * 1.05);
  ctx.fill();
  drawEmote(ctx, e.id, 0, 0, r * 0.85);
  ctx.restore();
}

const SMILE_ICON = '<svg viewBox="0 0 24 24"><circle cx="12" cy="12" r="9" fill="none" stroke="currentColor" stroke-width="2"/><circle cx="9" cy="10" r="1.4" fill="currentColor"/><circle cx="15" cy="10" r="1.4" fill="currentColor"/><path d="M8 14.2a4.5 4.5 0 0 0 8 0" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round"/></svg>';
function buildEmoteTray() {
  const tray = $('emote-tray');
  tray.innerHTML = '';
  EMOTES.forEach((em, n) => {
    const b = document.createElement('button');
    b.className = 'emote-btn';
    b.title = `${em.name} (${n + 1})`;
    b.setAttribute('aria-label', em.name);
    b.dataset.emote = em.id;
    const cv = document.createElement('canvas');
    cv.width = cv.height = 64;
    drawEmote(cv.getContext('2d'), em.id, 32, 32, 24);
    b.appendChild(cv);
    b.addEventListener('click', () => playerEmote(em.id));
    tray.appendChild(b);
  });
}
$('emote-btn').innerHTML = SMILE_ICON;
$('emote-btn').addEventListener('click', () => { if (state === 'play') $('emote-tray').classList.toggle('hidden'); });
buildEmoteTray();

// ---------- Cup ----------
const CUP_POINTS = [10, 7, 5, 3, 2, 1, 1, 1];
function newCup() {
  const maps = ['square', 'round', 'pillars', 'maze', 'islands', 'saws', 'storm', 'belts', 'portals'].sort(() => Math.random() - 0.5).slice(0, 3);
  return { round: 1, seed: (Math.random() * 4294967296) >>> 0, maps, points: {}, last: {} };
}

// Score a finished Cup round: everyone still standing by land, anyone knocked out after them
function scoreCupRound() {
  const field = players.filter(p => p && !p.isBoss);
  const ranked = field.filter(p => p.alive).sort((a, b) => counts[b.id] - counts[a.id]).concat(field.filter(p => !p.alive));
  cup.last = {};
  ranked.forEach((p, i) => {
    const pts = CUP_POINTS[i] || 1;
    cup.last[p.name] = pts;
    cup.points[p.name] = (cup.points[p.name] || 0) + pts;
  });
  cup.meName = me.name;
  cup.round++;
  return ranked.indexOf(me) + 1;
}

// Timed mode: when the clock runs out, the biggest player wins
function timeUp() {
  const ranked = players.filter(p => p && p.alive).sort((a, b) => counts[b.id] - counts[a.id]);
  const rank = ranked.indexOf(me) + 1;
  if (rank === 1) {
    Sfx.play('win');
    for (let i = 0; i < 6; i++) burst(me.x + rand(-8, 8), me.y + rand(-6, 6), COLORS[i], 30, 14);
  }
  state = 'won';
  later(rank === 1 ? 1600 : 600, () => endGame(rank === 1, `Time's up! You finished #${rank} of ${ranked.length}.`));
}

function showScreen(id) {
  for (const el of document.querySelectorAll('.screen')) el.classList.toggle('show', el.id === id);
  $('hud').classList.toggle('hidden', state === 'menu' || state === 'over' || state === 'replay');
  if (state === 'menu' || state === 'over' || state === 'replay') $('boss-bar').classList.add('hidden');
  updateMenuBest();
}

function updateMenuBest() {
  const b = bestFor(myMode);
  $('menu-best').textContent = `${myMode === 'daily' ? "Today's best" : myMode === 'weekly' ? "This week's best" : MODES[myMode].name + ' best'}: ${b.toFixed(1)}%`;
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
  const base = gameMode.duo ? 0.8 : 1;
  cam.zoom += (base - Math.min(0.35, pct(me) / 80) - cam.zoom) * Math.min(1, dt * 2);
  if (p2) {
    cam2.x += (p2.x - cam2.x) * k;
    cam2.y += (p2.y - cam2.y) * k;
    cam2.zoom += (base - Math.min(0.35, pct(p2) / 80) - cam2.zoom) * Math.min(1, dt * 2);
  }
}

function update(dt) {
  time += dt;
  if (countdown > 0) {
    // 3-2-1: everyone waits, but you can already choose which way to go
    const before = Math.ceil(countdown);
    countdown -= dt;
    if (me.alive) { steerHuman(); me.angle = me.desired; }
    if (p2) p2.angle = p2.desired;
    if (countdown <= 0) { goFlash = 0.8; Sfx.play('go'); buzz(40); }
    else if (Math.ceil(countdown) !== before) Sfx.play('beep');
    updateCamera(dt);
    return;
  }
  goFlash = Math.max(0, goFlash - dt);
  if (state === 'play') {
    playTime += dt;
    if (ghostRec && me.alive) recordGhost();
    if (gameMode.time && playTime >= gameMode.time && me.alive) timeUp();
    achTimer -= dt;
    if (achTimer <= 0 && me.alive && !gameMode.duo && !gameMode.tutorial) { achTimer = 1; liveAchievementCheck(); }
    if (gameMode.tutorial) updateTutorial(dt);
  }

  // Your trail effect (from the Locker) puffs out behind you while you're outside your land
  if (myFx !== 'none' && me.alive && me.trail.length) {
    fxTimer -= dt;
    if (fxTimer <= 0) {
      fxTimer = 0.05;
      const back = me.angle + Math.PI;
      fxParts.push({
        kind: myFx, x: me.x + Math.cos(back) * 0.8 + rand(-0.3, 0.3), y: me.y + Math.sin(back) * 0.8 + rand(-0.3, 0.3),
        vx: rand(-0.6, 0.6), vy: rand(-1.5, -0.3), life: 1, rot: rand(0, TAU), hue: (time * 200) % 360, size: rand(0.7, 1.1),
      });
    }
  }
  for (const f of fxParts) { f.x += f.vx * dt; f.y += f.vy * dt; f.life -= dt * 1.2; f.rot += dt * 3; }
  fxParts = fxParts.filter(f => f.life > 0);
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
    if (p.hitFlash) p.hitFlash = Math.max(0, p.hitFlash - dt * 2);
    if (p.pet !== 'none') updatePet(p, dt);
    if (p.isBot) steerBot(p, dt);
    if (p !== me || state === 'play') {
      move(p, dt);
      checkPortals(p);
    }
  }
  checkBumps();
  updateHazards(dt);
  emoteCooldown -= dt;
  for (const p of players) if (p && p.emote && (p.emote.t += dt) > EMOTE_TIME) p.emote = null;
  updatePowerups(dt);
  updateMapCoins(dt);
  if (state === 'play' && giantDue()) spawnGiant();

  // Danger: is an enemy close to your exposed trail? Close ones also get marked.
  danger = 0;
  threats = [];
  if (me.alive && me.trail.length && me.fx.shield <= 0) {
    for (const o of players) {
      if (!o || allies(o, me) || !o.alive) continue;
      let closest = Infinity;
      for (let k = 0; k < me.trail.length; k += 2) {
        const i = me.trail[k], tx = (i % N) + 0.5, ty = Math.floor(i / N) + 0.5;
        closest = Math.min(closest, Math.hypot(o.x - tx, o.y - ty));
      }
      if (closest < 7) danger = Math.max(danger, 1 - closest / 7);
      if (closest < 10) threats.push(o);
    }
    // Saws heading for your trail get a warning too
    for (const sw of saws) {
      let closest = Math.hypot(sw.x - me.x, sw.y - me.y);
      for (let k = 0; k < me.trail.length; k += 2) {
        const i = me.trail[k];
        closest = Math.min(closest, Math.hypot(sw.x - (i % N) - 0.5, sw.y - Math.floor(i / N) - 0.5));
      }
      if (closest < 6) danger = Math.max(danger, 1 - closest / 6);
      if (closest < 8) threats.push(sw);
    }
  }
  // Standing where the storm is about to hit
  if (me.alive && storm && storm.phase !== 'wait' && !stormSafe(me.x, me.y, 0.5)) danger = Math.max(danger, 0.7);
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
    if (gameMode.duo) {
      if (pct(me) >= gameMode.win) duoWin(me);
      else if (p2.alive && pct(p2) >= gameMode.win) duoWin(p2);
    } else if (gameMode.teams) {
      if (teamPct(0) >= gameMode.win) win(`Your team claimed ${gameMode.win}% of the map!`);
      else if (teamPct(1) >= gameMode.win) { state = 'won'; later(600, () => endGame(false, `The other team claimed ${gameMode.win}% first.`)); }
    } else if (gameMode.win && pct(me) >= gameMode.win) win();
  }

  updateCamera(dt);
}

// ---------- Drawing ----------
let mini, miniCtx, miniImg; // allocated with the world
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
    const [r, g, b] = id ? rgbOf(id) : wall[i] === 1 ? [107, 118, 144] : wall[i] === 3 ? [122, 91, 176] : belt[i] ? [200, 207, 222] : [245, 247, 252];
    d[i * 4] = r;
    d[i * 4 + 1] = g;
    d[i * 4 + 2] = b;
    d[i * 4 + 3] = wall[i] === 2 ? 0 : id || wall[i] ? 255 : 220;
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
  if (skin === 'giant') { // horns
    g.fillStyle = '#e8e2d0';
    for (const side of [-1, 1]) {
      g.beginPath();
      g.moveTo(s * 0.05, side * s * 0.42);
      g.lineTo(s * 0.35, side * s * 0.42);
      g.lineTo(s * 0.1, side * s * 0.8);
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
  } else if (skin === 'crystal') {
    // Gem facets
    g.fillStyle = 'rgba(255, 255, 255, 0.45)';
    g.beginPath(); g.moveTo(-s / 2, -s / 2); g.lineTo(0, 0); g.lineTo(-s / 2, s / 2); g.fill();
    g.fillStyle = 'rgba(255, 255, 255, 0.2)';
    g.beginPath(); g.moveTo(-s / 2, -s / 2); g.lineTo(s / 2, -s / 2); g.lineTo(0, 0); g.fill();
    g.fillStyle = 'rgba(0, 0, 0, 0.12)';
    g.beginPath(); g.moveTo(s / 2, s / 2); g.lineTo(0, 0); g.lineTo(-s / 2, s / 2); g.fill();
    g.fillStyle = 'rgba(255, 255, 255, 0.8)';
    g.fillRect(-s * 0.3, -s * 0.34, s * 0.1, s * 0.1);
  } else if (skin === 'tiger') {
    g.fillStyle = 'rgba(20, 20, 30, 0.55)';
    for (const k of [-0.35, -0.1, 0.15]) {
      g.beginPath();
      g.moveTo(k * s, -s / 2);
      g.lineTo((k + 0.12) * s, -s / 2);
      g.lineTo((k + 0.02) * s, 0);
      g.lineTo((k + 0.12) * s, s / 2);
      g.lineTo(k * s, s / 2);
      g.lineTo((k - 0.06) * s, 0);
      g.fill();
    }
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
  if (skin === 'giant') { // angry brows and red eyes
    g.strokeStyle = '#1a1c2a';
    g.lineWidth = s * 0.07;
    for (const side of [-1, 1]) {
      g.beginPath();
      g.moveTo(s * 0.05, side * s * 0.36);
      g.lineTo(s * 0.32, side * s * 0.1);
      g.stroke();
    }
    for (const side of [-1, 1]) circ(s * 0.24, side * s * 0.2, s * 0.06, '#ff3c50');
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

// One trail-effect particle, drawn at (x, y). `size` is in pixels.
function drawFxShape(g, f, x, y, size) {
  const s = size * f.size * (f.kind === 'bubbles' ? 1.2 - f.life * 0.4 : 0.5 + f.life * 0.5);
  g.save();
  g.translate(x, y);
  g.globalAlpha = Math.min(1, f.life * 1.5);
  const star = (points, outer, inner) => {
    g.beginPath();
    for (let k = 0; k < points * 2; k++) {
      const r = k % 2 ? inner : outer, a = (k * Math.PI) / points - Math.PI / 2;
      g.lineTo(Math.cos(a) * r, Math.sin(a) * r);
    }
    g.closePath();
    g.fill();
  };
  if (f.kind === 'sparkle') {
    g.fillStyle = '#fff3a0';
    star(4, s * 0.5, s * 0.12);
  } else if (f.kind === 'bubbles') {
    g.strokeStyle = 'rgba(120, 200, 255, 0.9)';
    g.lineWidth = Math.max(1, s * 0.1);
    g.beginPath();
    g.arc(0, 0, s * 0.35, 0, TAU);
    g.stroke();
    g.fillStyle = 'rgba(255, 255, 255, 0.8)';
    g.fillRect(-s * 0.15, -s * 0.18, s * 0.08, s * 0.08);
  } else if (f.kind === 'hearts') {
    g.fillStyle = '#ff6fa5';
    g.beginPath();
    g.moveTo(0, s * 0.35);
    g.bezierCurveTo(-s * 0.6, -s * 0.05, -s * 0.3, -s * 0.5, 0, -s * 0.18);
    g.bezierCurveTo(s * 0.3, -s * 0.5, s * 0.6, -s * 0.05, 0, s * 0.35);
    g.fill();
  } else if (f.kind === 'fire') {
    g.fillStyle = f.life > 0.6 ? '#ffd23f' : f.life > 0.3 ? '#ff8c42' : '#ff5d73';
    g.beginPath();
    g.arc(0, 0, s * 0.3, 0, TAU);
    g.fill();
  } else if (f.kind === 'stars') {
    g.rotate(f.rot);
    g.fillStyle = '#ffc93c';
    star(5, s * 0.45, s * 0.2);
  } else if (f.kind === 'lightning') {
    g.strokeStyle = '#ffe14d';
    g.lineWidth = Math.max(1.5, s * 0.1);
    g.lineJoin = 'round';
    g.beginPath();
    g.moveTo(-s * 0.1, -s * 0.45);
    g.lineTo(s * 0.12, -s * 0.05);
    g.lineTo(-s * 0.08, 0.05 * s);
    g.lineTo(s * 0.1, s * 0.45);
    g.stroke();
  } else if (f.kind === 'snow') {
    g.rotate(f.rot);
    g.strokeStyle = '#ffffff';
    g.lineWidth = Math.max(1, s * 0.07);
    for (let k = 0; k < 3; k++) {
      g.rotate(Math.PI / 3);
      g.beginPath();
      g.moveTo(-s * 0.35, 0);
      g.lineTo(s * 0.35, 0);
      g.stroke();
    }
  } else if (f.kind === 'rainbow') {
    g.rotate(f.rot);
    g.fillStyle = `hsl(${f.hue}, 85%, 60%)`;
    g.fillRect(-s * 0.22, -s * 0.22, s * 0.44, s * 0.44);
  }
  g.restore();
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
  } else if (kind === 'ghost') {
    ctx.moveTo(x - u * 0.7, y + u * 0.8);
    ctx.lineTo(x - u * 0.7, y - u * 0.1);
    ctx.arc(x, y - u * 0.1, u * 0.7, Math.PI, 0);
    ctx.lineTo(x + u * 0.7, y + u * 0.8);
    for (let k = 0; k < 3; k++) ctx.lineTo(x + u * (0.47 - k * 0.47), y + u * (k % 2 ? 0.8 : 0.5));
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = '#fff';
    ctx.beginPath();
    ctx.arc(x - u * 0.25, y - u * 0.1, u * 0.15, 0, TAU);
    ctx.arc(x + u * 0.25, y - u * 0.1, u * 0.15, 0, TAU);
    ctx.fill();
  } else if (kind === 'paint') {
    for (let k = 0; k < 7; k++) {
      const a = (k / 7) * TAU, rr = k % 2 ? u * 0.45 : u * 0.8;
      ctx.moveTo(x + Math.cos(a) * rr + u * 0.2, y + Math.sin(a) * rr);
      ctx.arc(x + Math.cos(a) * rr, y + Math.sin(a) * rr, u * 0.2, 0, TAU);
    }
    ctx.moveTo(x + u * 0.55, y);
    ctx.arc(x, y, u * 0.55, 0, TAU);
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
  const s = CELL * (p.isBoss ? 2.4 : 1.4);
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
  if (p.fx.ghost > 0) ctx.globalAlpha = 0.45 + 0.15 * Math.sin(time * 10);
  drawBody(ctx, p, s, time);
  ctx.globalAlpha = 1;
  if (p.hitFlash > 0) {
    ctx.fillStyle = `rgba(255, 255, 255, ${p.hitFlash * 0.8})`;
    ctx.fillRect(-s / 2, -s / 2, s, s);
  }
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
  ctx.fillStyle = p.isBoss ? '#d6304a' : gameMode.teams && p !== me && allies(p, me) ? '#1f5fd6' : 'rgba(38, 48, 74, 0.9)';
  ctx.fillText(gameMode.teams && p !== me && allies(p, me) ? `★ ${p.name}` : p.name, hx, hy - s * 0.85 + bob);
  if (p.id === leaderId || p.isKing) drawCrown(hx, hy - s * 1.75 + bob + Math.sin(time * 4) * 2, CELL * 0.9);

  // Under the square: a bot's personality, or the badge you're wearing
  const tag = p.isBot && !p.isBoss && p.persona ? PERSONALITIES[p.persona].name : p === me ? badgeName() : '';
  if (tag) {
    ctx.font = `bold ${Math.round(CELL * 0.6)}px system-ui, sans-serif`;
    const tw = ctx.measureText(tag).width + CELL * 0.8, ty = hy + s * 0.95 + bob;
    ctx.fillStyle = p === me ? '#ffc93c' : 'rgba(255, 255, 255, 0.8)';
    ctx.beginPath();
    ctx.roundRect(hx - tw / 2, ty - CELL * 0.5, tw, CELL, CELL * 0.5);
    ctx.fill();
    ctx.fillStyle = p === me ? '#5a3f00' : 'rgba(38, 48, 74, 0.8)';
    ctx.textBaseline = 'middle';
    ctx.fillText(tag, hx, ty + 1);
    ctx.textBaseline = 'alphabetic';
  }
  if (p.emote) drawEmoteBubble(p.emote, hx, hy - s * 0.85 + bob - (p.id === leaderId ? CELL * 1.6 : CELL * 0.6));
}

function draw(dt) {
  ctx.fillStyle = '#cfd6e4';
  ctx.fillRect(0, 0, W, H);

  if (!me) {
    drawMenuBackdrop(dt);
    return;
  }

  minimapTimer -= dt;
  if (minimapTimer <= 0) { updateMinimap(); minimapTimer = 0.25; }

  if (!gameMode.duo || !p2) {
    drawWorld(me, cam);
    return;
  }
  // 2 players: split screen (side by side when wide, top and bottom when tall)
  const wide = W >= H, fullW = W, fullH = H;
  const views = wide ? [[0, 0, W / 2, H], [W / 2, 0, W / 2, H]] : [[0, 0, W, H / 2], [0, H / 2, W, H / 2]];
  [[me, cam], [p2, cam2]].forEach(([focus, c], i) => {
    const [vx, vy, vw, vh] = views[i];
    ctx.save();
    ctx.beginPath();
    ctx.rect(vx, vy, vw, vh);
    ctx.clip();
    ctx.translate(vx, vy);
    W = vw;
    H = vh;
    drawWorld(focus, c);
    // Player label and score at the bottom of each view
    ctx.font = 'bold 15px system-ui, sans-serif';
    ctx.textAlign = 'center';
    const label = `${focus.name} · ${pct(focus).toFixed(1)}%${focus.alive ? '' : ' · out'}`;
    const lw = ctx.measureText(label).width + 20;
    ctx.fillStyle = focus.color;
    ctx.fillRect(W / 2 - lw / 2, H - 34, lw, 24);
    ctx.fillStyle = '#fff';
    ctx.fillText(label, W / 2, H - 17);
    W = fullW;
    H = fullH;
    ctx.restore();
  });
  ctx.fillStyle = '#26304a';
  if (wide) ctx.fillRect(W / 2 - 2, 0, 4, H);
  else ctx.fillRect(0, H / 2 - 2, W, 4);
}

// Draws the world as seen by `focus`, through camera `c`, filling the current W x H view
function drawWorld(focus, c) {
  CELL = BASE_CELL * c.zoom;
  const sh = settings.shake ? shake * CELL * 0.6 : 0;
  const x0 = c.x * CELL - W / 2 + rand(-sh, sh), y0 = c.y * CELL - H / 2 + rand(-sh, sh);

  // Map floor: a raised board with a soft checker pattern
  if (gameMapId !== 'round' && gameMapId !== 'islands') {
    ctx.fillStyle = '#aab4c8';
    ctx.fillRect(-x0 - 4, -y0 - 4 + CELL * 0.5, N * CELL + 8, N * CELL + 8);
  }
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

  // Outside the round arena, and pillars (drawn as raised blocks)
  const wallColor = [null, null, '#cfd6e4'];
  const drawWalls = (kind, color, yOff) => {
    ctx.fillStyle = color;
    for (let r = r0; r <= r1; r++) {
      let c = c0;
      while (c <= c1) {
        if (wall[r * N + c] !== kind) { c++; continue; }
        let e = c;
        while (e + 1 <= c1 && wall[r * N + e + 1] === kind) e++;
        ctx.fillRect(Math.floor(c * CELL - x0), Math.floor(r * CELL - y0 + yOff), Math.ceil((e - c + 1) * CELL), Math.ceil(CELL));
        c = e + 1;
      }
    }
  };
  drawWalls(2, wallColor[2], 0);
  if (gameMapId === 'belts') drawBelts(c0, c1, r0, r1, x0, y0, false);
  drawWalls(1, '#4a5369', CELL * 0.35);
  drawWalls(1, '#6b7690', 0);
  if (storm) drawWalls(3, '#6b4fa0', 0);

  // Land: a darker copy nudged down gives a chunky 3D edge, then the top colour
  drawRuns(owner, c0, c1, r0, r1, x0, y0, p => p.dark, CELL * 0.3);
  drawRuns(owner, c0, c1, r0, r1, x0, y0, p => p.color, 0);
  if (settings.patterns) {
    // Colorblind mode: every player's land and trail also gets its own pattern
    drawRuns(owner, c0, c1, r0, r1, x0, y0, p => playerPattern(p, x0, y0), 0);
  }
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

  if (settings.patterns) drawRuns(trail, c0, c1, r0, r1, x0, y0, p => playerPattern(p, x0, y0), 0);

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

  if (gameMapId === 'belts') drawBelts(c0, c1, r0, r1, x0, y0, true);
  drawHazards(x0, y0);

  // Gold coins spin (and blink before they vanish)
  for (const c of mapCoins) {
    const px = c.x * CELL - x0, py = c.y * CELL - y0 + Math.sin(time * 3 + c.x) * CELL * 0.1;
    if (px < -30 || py < -30 || px > W + 30 || py > H + 30) continue;
    if (c.life < 3 && Math.floor(c.life * 8) % 2) continue;
    const r = CELL * 0.45 * Math.min(1, c.age * 4), w = Math.max(0.15, Math.abs(Math.cos(time * 4 + c.x)));
    ctx.fillStyle = '#c98a00';
    ctx.beginPath();
    ctx.ellipse(px, py + r * 0.15, r * w, r, 0, 0, TAU);
    ctx.fill();
    ctx.fillStyle = '#ffc93c';
    ctx.beginPath();
    ctx.ellipse(px, py, r * w, r, 0, 0, TAU);
    ctx.fill();
    ctx.fillStyle = 'rgba(255, 255, 255, 0.6)';
    ctx.fillRect(px - r * w * 0.35, py - r * 0.5, Math.max(1, r * w * 0.25), r * 0.5);
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
  for (const p of players) {
    if (!p || !p.alive || p.pet === 'none') continue;
    const px = p.petX * CELL - x0, py = p.petY * CELL - y0;
    if (px > -40 && py > -40 && px < W + 40 && py < H + 40) drawPet(ctx, p.pet, px, py, CELL * 1.4, time + p.id, p.petFace);
  }
  for (const p of players) if (p && p.alive && p !== focus) drawHead(p, x0, y0, leaderId);
  if (ghostRun && (state === 'play' || state === 'won') && focus === me) drawGhost(x0, y0);
  if (focus.alive) drawHead(focus, x0, y0, leaderId);

  for (const f of fxParts) drawFxShape(ctx, f, f.x * CELL - x0, f.y * CELL - y0, CELL * 1.1);

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
    ctx.strokeStyle = f.gold ? '#9a6a00' : me.dark;
    ctx.strokeText(f.text, f.x * CELL - x0, f.y * CELL - y0);
    ctx.fillStyle = f.gold ? '#ffd23f' : '#fff';
    ctx.fillText(f.text, f.x * CELL - x0, f.y * CELL - y0);
  }
  ctx.globalAlpha = 1;

  // Frozen by someone else: frosty screen edge
  if (freezer && freezer !== focus && focus.alive) {
    const grad = ctx.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.3, W / 2, H / 2, Math.max(W, H) * 0.75);
    grad.addColorStop(0, 'rgba(160, 225, 255, 0)');
    grad.addColorStop(1, 'rgba(160, 225, 255, 0.55)');
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, W, H);
  }

  // Danger warning: red glow around the screen edge (your view only)
  if (danger > 0.3 && focus === me) {
    const a = danger * 0.35 * (0.6 + 0.4 * Math.sin(time * 18));
    const grad = ctx.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.35, W / 2, H / 2, Math.max(W, H) * 0.75);
    grad.addColorStop(0, 'rgba(255, 60, 80, 0)');
    grad.addColorStop(1, `rgba(255, 60, 80, ${a})`);
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, W, H);
  }

  // Enemies near your trail: a "!" above them, or an arrow at the screen edge if off-screen
  for (const o of focus === me ? threats : []) {
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

  // Tutorial: a bouncing green arrow points at what to do next
  const goal = gameMode.tutorial && tutTarget();
  if (goal) {
    const sx = goal.x * CELL - x0, sy = goal.y * CELL - y0, bounce = Math.sin(time * 8) * 6;
    ctx.fillStyle = '#1f9d6b';
    ctx.strokeStyle = '#fff';
    ctx.lineWidth = 2;
    ctx.save();
    if (sx > 30 && sy > 30 && sx < W - 30 && sy < H - 30) {
      ctx.translate(sx, sy - CELL * 1.6 + bounce);
      ctx.rotate(Math.PI / 2);
    } else {
      const a = Math.atan2(sy - H / 2, sx - W / 2);
      const t = Math.min((W / 2 - 40) / Math.abs(Math.cos(a) || 1e-6), (H / 2 - 40) / Math.abs(Math.sin(a) || 1e-6));
      ctx.translate(W / 2 + Math.cos(a) * t, H / 2 + Math.sin(a) * t);
      ctx.rotate(a);
    }
    ctx.beginPath();
    ctx.moveTo(14, 0);
    ctx.lineTo(-10, -13);
    ctx.lineTo(-10, 13);
    ctx.closePath();
    ctx.fill();
    ctx.stroke();
    ctx.restore();
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
    ctx.strokeStyle = focus.dark;
    ctx.strokeText(text, 0, 0);
    ctx.fillStyle = '#fff';
    ctx.fillText(text, 0, 0);
    ctx.restore();
  }

  // Touch joystick
  if (stick.active && state === 'play' && !gameMode.duo) {
    const R = stickRadius();
    ctx.strokeStyle = 'rgba(38, 48, 74, 0.3)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(stick.ox, stick.oy, R, 0, TAU);
    ctx.stroke();
    const dx = stick.x - stick.ox, dy = stick.y - stick.oy, d = Math.hypot(dx, dy);
    const m = d > R ? R / d : 1;
    ctx.fillStyle = 'rgba(38, 48, 74, 0.3)';
    ctx.beginPath();
    ctx.arc(stick.ox + dx * m, stick.oy + dy * m, R * 0.4, 0, TAU);
    ctx.fill();
  }

  // Tap-to-turn hints in the bottom corners
  if (settings.controls === 'turn' && state === 'play' && isTouchDevice) {
    const held = [...turnTouches.values()];
    const hintY = H - Math.min(130, W * 0.28) - 70; // just above the minimap
    for (const side of [-1, 1]) {
      const cx = side < 0 ? W * 0.25 : W * 0.75, cy = hintY;
      ctx.fillStyle = held.includes(side) ? 'rgba(38, 48, 74, 0.35)' : 'rgba(38, 48, 74, 0.15)';
      ctx.beginPath();
      ctx.arc(cx, cy, 34, 0, TAU);
      ctx.fill();
      ctx.strokeStyle = '#fff';
      ctx.lineWidth = 5;
      ctx.lineCap = 'round';
      ctx.beginPath();
      ctx.moveTo(cx - side * 6, cy - 12);
      ctx.lineTo(cx + side * 8, cy);
      ctx.lineTo(cx - side * 6, cy + 12);
      ctx.stroke();
    }
  }

  // Minimap
  if (drawingGif) return;
  const ms = Math.min(130, W * 0.28), mx = 16, my = H - ms - 16;
  ctx.fillStyle = 'rgba(255, 255, 255, 0.7)';
  ctx.fillRect(mx - 4, my - 4, ms + 8, ms + 8);
  ctx.imageSmoothingEnabled = false;
  ctx.drawImage(mini, mx, my, ms, ms);
  ctx.save();
  ctx.beginPath();
  ctx.rect(mx, my, ms, ms);
  ctx.clip();
  ctx.strokeStyle = '#26304a';
  ctx.lineWidth = 1;
  ctx.strokeRect(mx + (x0 / CELL / N) * ms, my + (y0 / CELL / N) * ms, (W / CELL / N) * ms, (H / CELL / N) * ms);
  ctx.fillStyle = '#26304a';
  for (const sw of saws) {
    ctx.beginPath();
    ctx.arc(mx + (sw.x / N) * ms, my + (sw.y / N) * ms, 2, 0, TAU);
    ctx.fill();
  }
  for (const pt of portals) {
    ctx.fillStyle = pt.color;
    ctx.beginPath();
    ctx.arc(mx + (pt.x / N) * ms, my + (pt.y / N) * ms, 3, 0, TAU);
    ctx.fill();
  }
  ctx.restore();
  if (focus.alive) {
    ctx.fillStyle = '#fff';
    ctx.strokeStyle = focus.dark;
    ctx.beginPath();
    ctx.arc(mx + (focus.x / N) * ms, my + (focus.y / N) * ms, 3 + Math.sin(time * 6), 0, TAU);
    ctx.fill();
    ctx.stroke();
  }
}

// Saw tracks, saws and the storm's edge
// Conveyor strips: the grey base goes under the land, the moving arrows on top
function drawBelts(c0, c1, r0, r1, x0, y0, arrows) {
  if (!arrows) {
    ctx.fillStyle = '#c8cfde';
    for (let r = r0; r <= r1; r++) for (let c = c0; c <= c1; c++) {
      if (belt[r * N + c]) ctx.fillRect(Math.floor(c * CELL - x0), Math.floor(r * CELL - y0), Math.ceil(CELL), Math.ceil(CELL));
    }
    return;
  }
  const shift = (time * BELT_SPEED) % 1, k = CELL * 0.28;
  ctx.strokeStyle = 'rgba(38, 48, 74, 0.28)';
  ctx.lineWidth = Math.max(1.5, CELL * 0.14);
  ctx.lineCap = 'round';
  ctx.beginPath();
  for (let r = r0; r <= r1; r++) for (let c = c0; c <= c1; c++) {
    const d = BELT_DIRS[belt[r * N + c]];
    if (!d) continue;
    const cx = (c + 0.5 + d[0] * (shift - 0.5)) * CELL - x0, cy = (r + 0.5 + d[1] * (shift - 0.5)) * CELL - y0;
    ctx.moveTo(cx - d[0] * k - d[1] * k, cy - d[1] * k - d[0] * k);
    ctx.lineTo(cx, cy);
    ctx.lineTo(cx - d[0] * k + d[1] * k, cy - d[1] * k + d[0] * k);
  }
  ctx.stroke();
}

function drawHazards(x0, y0) {
  for (const pt of portals) {
    const sx = pt.x * CELL - x0, sy = pt.y * CELL - y0, R = PORTAL_R * CELL * 1.3;
    if (sx < -R * 2 || sy < -R * 2 || sx > W + R * 2 || sy > H + R * 2) continue;
    const grad = ctx.createRadialGradient(sx, sy, 0, sx, sy, R * 1.6);
    grad.addColorStop(0, alpha(pt.color, 0.05));
    grad.addColorStop(0.6, alpha(pt.color, 0.35));
    grad.addColorStop(1, alpha(pt.color, 0));
    ctx.fillStyle = grad;
    ctx.beginPath();
    ctx.arc(sx, sy, R * 1.6, 0, TAU);
    ctx.fill();
    ctx.fillStyle = '#26304a';
    ctx.beginPath();
    ctx.arc(sx, sy, R * 0.75, 0, TAU);
    ctx.fill();
    ctx.lineWidth = Math.max(2, CELL * 0.22);
    for (let k = 0; k < 3; k++) {
      ctx.strokeStyle = alpha(pt.color, 0.9 - k * 0.25);
      ctx.beginPath();
      const a = time * (3 + k) + k * 2;
      ctx.arc(sx, sy, R * (0.95 - k * 0.22), a, a + Math.PI * 1.3);
      ctx.stroke();
    }
  }
  if (saws.length) {
    ctx.strokeStyle = 'rgba(38, 48, 74, 0.16)';
    ctx.lineWidth = Math.max(2, CELL * 0.3);
    ctx.setLineDash([CELL * 0.6, CELL * 0.5]);
    for (const sw of saws) {
      ctx.beginPath();
      if (sw.kind === 'line') {
        ctx.moveTo(sw.ax * CELL - x0, sw.ay * CELL - y0);
        ctx.lineTo(sw.bx * CELL - x0, sw.by * CELL - y0);
      } else {
        ctx.arc(sw.cx * CELL - x0, sw.cy * CELL - y0, sw.r * CELL, 0, TAU);
      }
      ctx.stroke();
    }
    ctx.setLineDash([]);
    for (const sw of saws) {
      const sx = sw.x * CELL - x0, sy = sw.y * CELL - y0, R = SAW_R * CELL;
      if (sx < -R * 2 || sy < -R * 2 || sx > W + R * 2 || sy > H + R * 2) continue;
      ctx.fillStyle = 'rgba(38, 48, 74, 0.2)';
      ctx.beginPath();
      ctx.ellipse(sx, sy + R * 0.5, R, R * 0.4, 0, 0, TAU);
      ctx.fill();
      ctx.save();
      ctx.translate(sx, sy);
      ctx.rotate(sw.spin);
      ctx.fillStyle = '#8d97ab';
      ctx.beginPath();
      for (let k = 0; k < 12; k++) {
        const a = (k / 12) * TAU;
        ctx.lineTo(Math.cos(a) * R * 1.15, Math.sin(a) * R * 1.15);
        ctx.lineTo(Math.cos(a + TAU / 24) * R * 0.8, Math.sin(a + TAU / 24) * R * 0.8);
      }
      ctx.closePath();
      ctx.fill();
      ctx.fillStyle = '#d8dde8';
      ctx.beginPath();
      ctx.arc(0, 0, R * 0.68, 0, TAU);
      ctx.fill();
      ctx.strokeStyle = '#aab4c8';
      ctx.lineWidth = Math.max(1, R * 0.1);
      ctx.beginPath();
      ctx.moveTo(-R * 0.5, 0);
      ctx.lineTo(R * 0.5, 0);
      ctx.stroke();
      ctx.fillStyle = '#4a5369';
      ctx.beginPath();
      ctx.arc(0, 0, R * 0.2, 0, TAU);
      ctx.fill();
      ctx.restore();
    }
  }
  if (storm) {
    const cx = (N / 2) * CELL - x0, cy = (N / 2) * CELL - y0;
    // A glowing edge where the storm is
    ctx.strokeStyle = `rgba(176, 107, 255, ${0.45 + 0.2 * Math.sin(time * 5)})`;
    ctx.lineWidth = Math.max(3, CELL * 0.5);
    ctx.beginPath();
    ctx.arc(cx, cy, storm.r * CELL, 0, TAU);
    ctx.stroke();
    // Where it's about to close in to
    if (storm.phase !== 'wait') {
      ctx.strokeStyle = `rgba(255, 60, 80, ${0.55 + 0.35 * Math.sin(time * 12)})`;
      ctx.lineWidth = Math.max(2, CELL * 0.25);
      ctx.setLineDash([CELL * 0.8, CELL * 0.6]);
      ctx.beginPath();
      ctx.arc(cx, cy, storm.to * CELL, 0, TAU);
      ctx.stroke();
      ctx.setLineDash([]);
    }
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

// Colorblind patterns: 8 distinct dark overlays, one per player slot
const playerPatterns = [];
function playerPattern(p, x0, y0) {
  const k = (p.id - 1) % 8;
  if (!playerPatterns[k]) {
    const c = document.createElement('canvas');
    c.width = c.height = 16;
    const g = c.getContext('2d');
    g.strokeStyle = g.fillStyle = 'rgba(20, 24, 40, 0.32)';
    g.lineWidth = 2;
    const line = (a, b, cc, d) => { g.beginPath(); g.moveTo(a, b); g.lineTo(cc, d); g.stroke(); };
    if (k === 0) { line(0, 16, 16, 0); line(-8, 8, 8, -8); line(8, 24, 24, 8); }        // diagonal /
    else if (k === 1) { line(0, 0, 16, 16); line(-8, 8, 8, 24); line(8, -8, 24, 8); }   // diagonal \
    else if (k === 2) { g.beginPath(); g.arc(8, 8, 2.5, 0, TAU); g.fill(); }             // dots
    else if (k === 3) { line(0, 8, 16, 8); line(8, 0, 8, 16); }                          // grid
    else if (k === 4) { line(0, 4, 16, 4); line(0, 12, 16, 12); }                        // horizontal
    else if (k === 5) { line(4, 0, 4, 16); line(12, 0, 12, 16); }                        // vertical
    else if (k === 6) { g.fillRect(0, 0, 8, 8); g.fillRect(8, 8, 8, 8); }                // checks
    else { line(3, 3, 13, 13); line(13, 3, 3, 13); }                                     // crosses
    playerPatterns[k] = ctx.createPattern(c, 'repeat');
  }
  const pat = playerPatterns[k];
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
  const timed = !!gameMode.time;
  $('goal').classList.toggle('hidden', timed);
  $('timer').classList.toggle('hidden', !timed);
  if (timed) {
    const left = Math.max(0, gameMode.time - playTime);
    $('timer').textContent = `⏱ ${fmtTime(Math.ceil(left))}`;
    $('timer').classList.toggle('urgent', left <= 15);
  } else {
    $('goal-fill').style.width = `${Math.min(100, (pct(me) / gameMode.win) * 100)}%`;
  }
  $('goal-fill').style.background = me.color;
  $('storm-info').classList.toggle('hidden', !storm);
  const bossShown = !!king && state !== 'over' && state !== 'replay';
  $('boss-bar').classList.toggle('hidden', !bossShown);
  document.body.classList.toggle('boss-on', bossShown);
  if (king) {
    const heart = on => `<svg viewBox="0 0 24 24" class="${on ? 'on' : ''}"><path d="M12 21s-8-5.5-8-11a4.5 4.5 0 0 1 8-2.8A4.5 4.5 0 0 1 20 10c0 5.5-8 11-8 11z"/></svg>`;
    const html = `<b>King${king.rage ? ' · furious!' : ''}</b><span class="hearts">${Array.from({ length: king.maxHp }, (_, i) => heart(i < (king.alive ? king.hp : 0))).join('')}</span>`
      + `<small>You: ${Array.from({ length: 3 }, (_, i) => (i < lives ? '●' : '○')).join(' ')}</small>`;
    if ($('boss-bar').innerHTML !== html) $('boss-bar').innerHTML = html;
  }
  if (storm) {
    const left = storm.phase === 'wait' ? storm.clock + STORM_WARN : storm.clock;
    $('storm-info').textContent = storm.phase === 'shrink' ? 'Storm closing!'
      : storm.phase === 'warn' ? `Storm closes in ${Math.ceil(left)}s!`
      : storm.r <= storm.min + 0.5 ? 'Storm: final ring' : `Storm shrinks in ${fmtTime(Math.ceil(left))}`;
    $('storm-info').classList.toggle('urgent', storm.phase !== 'wait');
  }
  const fx = Object.keys(POWERUPS).filter(k => POWERUPS[k].time && me.alive && me.fx[k] > 0)
    .map(k => `<span class="fx" style="--c:${POWERUPS[k].color}">${POWERUPS[k].name} ${Math.ceil(me.fx[k])}s</span>`);
  if (freezer && freezer !== me && me.alive) fx.push('<span class="fx" style="--c:#3fc7f5">Frozen!</span>');
  const fxHtml = fx.join('');
  if ($('effects').innerHTML !== fxHtml) $('effects').innerHTML = fxHtml;
  $('team-score').classList.toggle('hidden', !gameMode.teams && !gameMode.duo && !challenge && !gameMode.cup && !gameMode.weekly);
  if (gameMode.weekly && !challenge) {
    const g = ghostNow();
    $('team-score').innerHTML = !ghostRun ? '<b class="us">No ghost yet</b> <span>· set this week\'s best!</span>'
      : g ? `<b class="us">Ghost ${g.pct.toFixed(1)}%</b> <span>· ${pct(me) >= g.pct ? 'you\'re ahead!' : 'catch up!'}</span>`
      : `<b class="us">Best ${ghostRun.score.toFixed(1)}%</b> <span>· beat it!</span>`;
  } else if (challenge) $('team-score').innerHTML = `<b class="us">Beat ${challenge.score.toFixed(1)}%</b> <span>· ${pct(me) > challenge.score ? 'ahead!' : 'keep going'}</span>`;
  else if (gameMode.cup) $('team-score').innerHTML = `<b class="us">Cup round ${cup.round} of 3</b>`;
  else if (gameMode.duo) $('team-score').innerHTML = `<b class="us">P1 ${pct(me).toFixed(1)}%</b> <span>vs</span> <b class="them">P2 ${pct(p2).toFixed(1)}%</b>`;
  else if (gameMode.teams) $('team-score').innerHTML = `<b class="us">Your team ${teamPct(0).toFixed(1)}%</b> <span>vs</span> <b class="them">${teamPct(1).toFixed(1)}%</b>`;
  const ranked = players.filter(p => p && p.alive).sort((a, b) => counts[b.id] - counts[a.id]);
  const top = ranked.slice(0, 5);
  if (me.alive && !top.includes(me)) top.push(me);
  $('board').innerHTML = top.map(p => {
    const cls = [p === me && 'me', gameMode.teams && allies(p, me) && 'ally', p.isBoss && 'boss'].filter(Boolean).join(' ');
    const tag = p === me && badgeName() ? ` <small class="badge-tag">${badgeName()}</small>` : '';
    return `<li class="${cls}"><span><span class="dot" style="background:${p.color}"></span>${ranked.indexOf(p) + 1}. ${escapeHtml(p.name)}${tag}</span><span>${pct(p).toFixed(1)}%</span></li>`;
  }).join('');
}

// ---------- Replay ----------
// A snapshot of the board and every player 10 times a second, keeping the last 10 seconds
function recordFrame() {
  replayFrames.push({
    owner: owner.slice(), trail: trail.slice(),
    wall: storm ? wall.slice() : null,
    storm: storm && { r: storm.r, to: storm.to, phase: storm.phase },
    saws: saws.map(sw => [sw.x, sw.y, sw.spin]),
    ps: players.map(p => p && {
      x: p.x, y: p.y, angle: p.angle, alive: p.alive, shield: p.fx.shield > 0, ghost: p.fx.ghost > 0, emote: p.emote && { ...p.emote },
      px: p.petX, py: p.petY, pf: p.petFace,
    }),
    cam: { x: cam.x, y: cam.y, zoom: cam.zoom },
  });
  if (replayFrames.length > 100) replayFrames.shift();
}

function startReplay() {
  if (replayFrames.length < 5) return;
  replayT = 0;
  state = 'replay';
  showScreen(null);
  $('replay-bar').classList.remove('hidden');
}

function stopReplay() {
  $('replay-bar').classList.add('hidden');
  state = 'over';
  showScreen('over');
}

function playReplay(dt) {
  const len = (replayFrames.length - 1) / 10;
  replayT += dt;
  if (replayT >= len) { stopReplay(); return; }
  withReplayFrame(replayT * 10, c => {
    ctx.fillStyle = '#cfd6e4';
    ctx.fillRect(0, 0, W, H);
    drawWorld(me, c);
  });
  $('replay-fill').style.width = `${(replayT / len) * 100}%`;
}

// Swap recorded frame `k` (it can be between two frames) into the world, call fn with its
// camera, then put the real state back
function withReplayFrame(k, fn) {
  const i = Math.min(Math.floor(k), replayFrames.length - 1), t = k - i;
  const f = replayFrames[i], g = replayFrames[i + 1] || f;
  const lerp = (a, b) => a + (b - a) * t;
  const saved = { owner, trail, wall, freezer, threats, danger, countdown, goFlash, particles, flashes, fades, floats, fxParts, shake };
  const savedPlayers = players.map(p => p && { x: p.x, y: p.y, angle: p.angle, alive: p.alive, trail: p.trail, fx: p.fx, emote: p.emote, petX: p.petX, petY: p.petY, petFace: p.petFace });
  const savedSaws = saws.map(sw => [sw.x, sw.y, sw.spin]);
  const savedStorm = storm && { ...storm };
  owner = f.owner;
  trail = f.trail;
  if (f.wall) wall = f.wall;
  if (f.storm) Object.assign(storm, f.storm);
  saws.forEach((sw, n) => { if (f.saws[n]) [sw.x, sw.y, sw.spin] = f.saws[n]; });
  freezer = null; threats = []; danger = 0; countdown = 0; goFlash = 0; shake = 0;
  particles = []; flashes = []; fades = []; floats = []; fxParts = [];
  players.forEach((p, n) => {
    const a = f.ps[n], b = g.ps[n] || a;
    if (!p) return;
    if (!a) { p.alive = false; return; }
    let da = b.angle - a.angle;
    da = Math.atan2(Math.sin(da), Math.cos(da));
    p.x = lerp(a.x, b.x); p.y = lerp(a.y, b.y); p.angle = a.angle + da * t; p.alive = a.alive;
    p.trail = [];
    p.fx = { speed: 0, shield: a.shield ? 1 : 0, freeze: 0, ghost: a.ghost ? 1 : 0 };
    p.emote = a.emote && { id: a.emote.id, t: a.emote.t + t * 0.1 };
    p.petX = lerp(a.px, b.px); p.petY = lerp(a.py, b.py); p.petFace = a.pf;
  });
  try {
    fn({ x: lerp(f.cam.x, g.cam.x), y: lerp(f.cam.y, g.cam.y), zoom: lerp(f.cam.zoom, g.cam.zoom) });
  } finally {
    ({ owner, trail, wall, freezer, threats, danger, countdown, goFlash, particles, flashes, fades, floats, fxParts, shake } = saved);
    players.forEach((p, n) => { if (p) Object.assign(p, savedPlayers[n]); });
    saws.forEach((sw, n) => { [sw.x, sw.y, sw.spin] = savedSaws[n]; });
    if (savedStorm) Object.assign(storm, savedStorm);
  }
}

// ---------- Replay GIF ----------
// Draws every replay frame onto a small offscreen canvas and encodes them as a looping GIF.
const GIF_SIZE = 320;
let drawingGif = false, gifUrl = null, gifBlob = null, gifJob = 0;

function renderGifFrame(g, k) {
  const screenW = W, screenH = H, screenCtx = ctx;
  ctx = g;
  W = H = GIF_SIZE;
  drawingGif = true;
  try {
    withReplayFrame(k, c => {
      g.fillStyle = '#cfd6e4';
      g.fillRect(0, 0, GIF_SIZE, GIF_SIZE);
      drawWorld(me, { x: c.x, y: c.y, zoom: (c.zoom * GIF_SIZE) / Math.min(screenW, screenH) / 0.8 });
    });
  } finally {
    ctx = screenCtx;
    W = screenW;
    H = screenH;
    drawingGif = false;
  }
  // Caption strip
  g.fillStyle = 'rgba(38, 48, 74, 0.85)';
  g.fillRect(0, GIF_SIZE - 22, GIF_SIZE, 22);
  g.fillStyle = '#fff';
  g.font = '900 12px system-ui, sans-serif';
  g.textBaseline = 'middle';
  g.textAlign = 'left';
  g.fillText('COLOR CLAIM', 8, GIF_SIZE - 11);
  g.textAlign = 'right';
  g.font = 'bold 12px system-ui, sans-serif';
  g.fillText(`${me.name} · best ${peakPct.toFixed(1)}%`, GIF_SIZE - 8, GIF_SIZE - 11);
  g.textBaseline = 'alphabetic';
  return g.getImageData(0, 0, GIF_SIZE, GIF_SIZE).data;
}

async function makeReplayGif(onProgress = () => {}) {
  const job = ++gifJob;
  const n = replayFrames.length;
  const off = document.createElement('canvas');
  off.width = off.height = GIF_SIZE;
  const g = off.getContext('2d', { willReadFrequently: true });
  const pause = () => new Promise(r => setTimeout(r, 0));
  // Pick the palette from a sample of frames, then encode them all
  const pal = new GifPalette();
  const step = Math.max(1, Math.floor(n / 10));
  for (let k = 0; k < n; k += step) pal.sample(renderGifFrame(g, k));
  const gif = new GifWriter(GIF_SIZE, GIF_SIZE, pal.build());
  for (let k = 0; k < n; k++) {
    if (job !== gifJob) return null; // a new game started
    gif.addFrame(pal.index(renderGifFrame(g, k)), k === n - 1 ? 150 : 10);
    onProgress((k + 1) / n);
    if (k % 4 === 3) await pause();
  }
  return new Blob([gif.finish()], { type: 'image/gif' });
}

function resetGif() {
  gifJob++;
  if (gifUrl) URL.revokeObjectURL(gifUrl);
  gifUrl = null;
  gifBlob = null;
  $('gif-btn').disabled = false;
  $('gif-btn').textContent = 'Make a GIF';
  for (const id of ['gif-img', 'gif-save', 'gif-share']) $(id).classList.add('hidden');
  $('gif-status').textContent = '';
}

async function gifFromReplay() {
  if (state !== 'over' || replayFrames.length < 5 || $('gif-btn').disabled) return;
  $('gif-btn').disabled = true;
  $('gif-status').textContent = 'Making your GIF… 0%';
  const blob = await makeReplayGif(f => { $('gif-status').textContent = `Making your GIF… ${Math.round(f * 100)}%`; });
  if (!blob) return;
  gifBlob = blob;
  gifUrl = URL.createObjectURL(blob);
  $('gif-img').src = gifUrl;
  $('gif-save').href = gifUrl;
  $('gif-img').classList.remove('hidden');
  $('gif-save').classList.remove('hidden');
  const file = new File([blob], 'color-claim-replay.gif', { type: 'image/gif' });
  $('gif-share').classList.toggle('hidden', !(navigator.canShare && navigator.canShare({ files: [file] })));
  $('gif-btn').textContent = 'GIF ready';
  $('gif-status').textContent = `${Math.round(blob.size / 1024)} KB · ${replayFrames.length / 10} seconds. Tap and hold (or right-click) the picture to save it too.`;
  Sfx.play('coin');
}
$('gif-btn').addEventListener('click', gifFromReplay);
// Inside the claude.ai viewer a plain download link can't save files, so ask the viewer instead
let viewerDownloads = null;
if (window.claude && typeof window.claude.use === 'function') {
  window.claude.use('downloads').then(d => { viewerDownloads = d; }).catch(() => { /* not available */ });
}
$('gif-save').addEventListener('click', e => {
  if (!viewerDownloads || !gifBlob) return; // normal browsers use the link itself
  e.preventDefault();
  viewerDownloads.save({ filename: 'color-claim-replay.gif', data: gifBlob })
    .then(() => { $('gif-status').textContent = 'GIF saved!'; })
    .catch(err => {
      if (err && err.code === 'declined') return;
      if (err && err.code === 'rate_limited') { $('gif-status').textContent = 'One moment, then try again.'; return; }
      $('gif-save').classList.add('hidden');
      $('gif-status').textContent = 'Saving isn\'t available here. Tap and hold (or right-click) the picture to save it.';
    });
});
$('gif-share').addEventListener('click', () => {
  if (!gifBlob) return;
  const file = new File([gifBlob], 'color-claim-replay.gif', { type: 'image/gif' });
  navigator.share({ files: [file], title: 'Color Claim replay' }).catch(() => { /* cancelled */ });
});

// ---------- Main loop ----------
let last = performance.now();
let hudTimer = 0;
function frame(now) {
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  if (state === 'play' || state === 'won') {
    update(dt);
    replayTimer -= dt;
    if (replayTimer <= 0) { replayTimer = 0.1; recordFrame(); }
  }
  if (state === 'replay') { playReplay(dt); requestAnimationFrame(frame); return; }
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
$('tutorial-btn').addEventListener('click', () => { save('color-claim-howto-seen', '1'); startTutorial(); });
$('tutorial-skip').addEventListener('click', () => { if (gameMode.tutorial) leaveTutorial(); });

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
$('replay-btn').addEventListener('click', () => { if (state === 'over') startReplay(); });
$('replay-skip').addEventListener('click', () => { if (state === 'replay') stopReplay(); });
$('menu-btn').addEventListener('click', () => {
  if (state !== 'over') return;
  challenge = null;
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

// Start-up happens at the end of progress.js, once everything is loaded
