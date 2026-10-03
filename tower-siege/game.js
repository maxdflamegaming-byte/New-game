'use strict';

// Tower Siege: build roads between towers, march soldiers and tanks along them, take the map.
// The field is 900×1400 world units in portrait. On a wide screen it's turned on its side,
// so your base starts on the left instead of the bottom. render3d.js draws it in 3D;
// this canvas on top holds the numbers, the road you're dragging and other overlays.

// ---------- Canvas setup ----------
const canvas = document.getElementById('game');
const ctx = canvas.getContext('2d');
let W = 0, H = 0, DPR = 1;

const FW = 900, FH = 1400;
const HUD_TOP = 64, HUD_BOTTOM = 96;
let landscape = false;

function resize() {
  DPR = Math.min(window.devicePixelRatio || 1, 2);
  W = window.innerWidth;
  H = window.innerHeight;
  canvas.width = Math.round(W * DPR);
  canvas.height = Math.round(H * DPR);
  canvas.style.width = W + 'px';
  canvas.style.height = H + 'px';
  const wasLandscape = landscape;
  landscape = W > H * 1.05;
  R3D.layout(W, H, DPR, landscape, landscape ? FH : FW, landscape ? FW : FH, HUD_TOP, HUD_BOTTOM);
  if (wasLandscape !== landscape && towers.length) { placeWorld(); buildScene(); }
}
window.addEventListener('resize', resize);

// ---------- Helpers ----------
const $ = id => document.getElementById(id);
const TAU = Math.PI * 2;
const clamp = (v, a, b) => Math.max(a, Math.min(b, v));
const dist = (a, b) => Math.hypot(a.x - b.x, a.y - b.y);
const fmtTime = s => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;
function mulberry32(seed) {
  return () => {
    seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
    let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
    t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
    return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
  };
}
// Distance from point p to the segment a-b
function segDist(p, a, b) {
  const dx = b.x - a.x, dy = b.y - a.y;
  const len2 = dx * dx + dy * dy || 1;
  const t = clamp(((p.x - a.x) * dx + (p.y - a.y) * dy) / len2, 0, 1);
  return Math.hypot(p.x - (a.x + dx * t), p.y - (a.y + dy * t));
}
// Where segments p1-p2 and p3-p4 cross, or null
function segCross(p1, p2, p3, p4) {
  const d = (p2.x - p1.x) * (p4.y - p3.y) - (p2.y - p1.y) * (p4.x - p3.x);
  if (!d) return null;
  const u = ((p3.x - p1.x) * (p4.y - p3.y) - (p3.y - p1.y) * (p4.x - p3.x)) / d;
  const v = ((p3.x - p1.x) * (p2.y - p1.y) - (p3.y - p1.y) * (p2.x - p1.x)) / d;
  if (u < 0 || u > 1 || v < 0 || v > 1) return null;
  return { x: p1.x + (p2.x - p1.x) * u, y: p1.y + (p2.y - p1.y) * u };
}

// ---------- Armies and buildings ----------
const NEUTRAL = 0, PLAYER = 1;
const SIDES = [
  { name: 'Neutral', color: '#a9afba', dark: '#6b7280', light: '#dde1e8' },
  { name: 'Blue', color: '#3b8cff', dark: '#1d55c9', light: '#a9ccff' },
  { name: 'Red', color: '#ff4848', dark: '#b8202b', light: '#ffa6a6' },
  { name: 'Yellow', color: '#ffb526', dark: '#c47800', light: '#ffe08a' },
  { name: 'Green', color: '#3ec44b', dark: '#1f7f2b', light: '#a3eba8' },
];

const TYPES = {
  barracks: { name: 'Tower', prod: 1, defense: 1 },
  fort: { name: 'Bunker', prod: 0.8, defense: 2, intro: '🛡️ New: the Bunker. Attackers only do half damage to it.' },
  factory: { name: 'Tank Factory', prod: 1.1, defense: 1, intro: '🏭 New: the Tank Factory. It sends tanks: each one is worth 3 soldiers.' },
  watch: { name: 'Watchtower', prod: 0.6, defense: 1, intro: '🗼 New: the Watchtower. It shoots enemies inside its circle.' },
};

const CAP = 99;             // buildings stop training here
const HARD_CAP = 150;       // and can't be filled above this
const UNIT_SPEED = 115;     // world units per second
const TANK_POWER = 3;
const WATCH_RANGE = 230;
const WATCH_RELOAD = 0.55;
const MAX_LEVEL = 60;
const THEMES = ['grass', 'desert', 'snow', 'mine'];

const towerLevel = t => (t.units >= 60 ? 4 : t.units >= 30 ? 3 : t.units >= 10 ? 2 : 1);
const maxRoads = t => Math.min(3, towerLevel(t));
const towerRadius = t => (t.type === 'factory' ? 70 : t.type === 'fort' ? 72 : 60) + towerLevel(t) * 3;
const prodRate = t => (0.55 + 0.2 * towerLevel(t)) * TYPES[t.type].prod * (t.owner === PLAYER ? 1 + 0.08 * save.up.drill : 1);
const sendsTanks = t => t.type === 'factory';
const sendInterval = t => (sendsTanks(t) ? 2.4 : 1) / (1.6 + 0.4 * towerLevel(t)) / (t.owner === PLAYER && rally > 0 ? 2 : 1);
const unitSpeed = u => UNIT_SPEED * (u.power > 1 ? 0.8 : 1) * (u.owner === PLAYER ? (1 + 0.07 * save.up.boots) * (rally > 0 ? 1.4 : 1) : 1);
const themeFor = n => THEMES[Math.floor((n - 1) / 5) % THEMES.length];

// ---------- Saved progress ----------
const SAVE_KEY = 'tower-siege-save';
const UPGRADES = [
  { id: 'drill', icon: '🥁', name: 'Drill Sergeant', desc: 'Your buildings train soldiers 8% faster per level', max: 5, cost: [60, 120, 220, 360, 550] },
  { id: 'boots', icon: '👢', name: 'Swift Boots', desc: 'Your soldiers and tanks move 7% faster per level', max: 5, cost: [50, 100, 180, 300, 480] },
  { id: 'garrison', icon: '🏰', name: 'Garrison', desc: '+3 soldiers in each of your starting buildings per level', max: 5, cost: [40, 90, 160, 260, 400] },
  { id: 'armory', icon: '💣', name: 'Armory', desc: '+1 Airstrike and +1 Rally every battle', max: 2, cost: [250, 600] },
];
function defaultSave() {
  return { level: 1, stars: {}, coins: 0, up: { drill: 0, boots: 0, garrison: 0, armory: 0 }, seen: {}, help: false };
}
function loadSave() {
  try {
    const s = JSON.parse(localStorage.getItem(SAVE_KEY));
    if (s && typeof s === 'object') {
      const d = defaultSave();
      return { ...d, ...s, up: { ...d.up, ...(s.up || {}) }, stars: s.stars || {}, seen: s.seen || {} };
    }
  } catch { /* storage unavailable or corrupt */ }
  return defaultSave();
}
function writeSave() {
  try { localStorage.setItem(SAVE_KEY, JSON.stringify(save)); } catch { /* storage unavailable */ }
}
let save = loadSave();

// ---------- Levels ----------
// Buildings are [x, y, owner, soldiers, type]. Walls are [x, y, radius] circles that block roads.
// AI: think = seconds between moves, margin = spare soldiers it wants before attacking,
// bold = how much it prefers hitting you.
const TUTORIAL = [
  {
    towers: [[450, 1180, 1, 12], [260, 760, 0, 5], [640, 700, 0, 7], [450, 240, 2, 6]],
    ai: { think: 4.5, margin: 8, bold: 0 },
    hint: 'Drag from your blue tower to a gray one to send soldiers',
    hand: true,
  },
  {
    towers: [[230, 1190, 1, 14], [690, 1150, 0, 4], [450, 880, 0, 10], [200, 560, 0, 8], [700, 520, 0, 8], [450, 220, 2, 12]],
    ai: { think: 3.6, margin: 6, bold: 0.1 },
    hint: 'Swipe across one of your roads to cut it. Soldiers on it keep marching.',
  },
  {
    towers: [[450, 1210, 1, 16], [200, 940, 0, 6], [700, 940, 0, 6], [450, 700, 0, 16, 'fort'], [200, 460, 0, 6], [700, 460, 0, 6], [450, 190, 2, 16]],
    ai: { think: 3.2, margin: 5, bold: 0.2 },
    hint: 'Bigger towers hold more roads: 2 roads from 10 soldiers, 3 from 30',
  },
];

function genLevel(n) {
  const rng = mulberry32(n * 7919 + 13);
  const pick = (a, b) => a + rng() * (b - a);
  const mirror = p => ({ x: FW - p.x, y: FH - p.y });
  const per = Math.min(7, 3 + Math.floor(n / 7));
  const pts = [{ x: pick(280, 620), y: pick(1180, 1260) }];
  for (let k = 0; k < 600 && pts.length < per; k++) {
    const p = { x: pick(90, 810), y: pick(770, 1280) };
    const ok = pts.every(q => dist(p, q) > 200 && dist(p, mirror(q)) > 200) && dist(p, mirror(p)) > 200;
    if (ok) pts.push(p);
  }
  const towers = [];
  const neutralUnits = () => Math.round(4 + rng() * (6 + n * 0.22));
  const rollType = () => {
    const r = rng();
    if (n >= 3 && r < 0.15) return 'fort';
    if (n >= 4 && r < 0.32) return 'factory';
    if (n >= 7 && r < 0.45) return 'watch';
    return 'barracks';
  };
  const baseUnits = 12 + Math.floor(n / 6);
  pts.forEach((p, i) => {
    const m = mirror(p);
    if (i === 0) {
      towers.push([p.x, p.y, 1, 12], [m.x, m.y, 2, baseUnits]);
    } else {
      const u = neutralUnits(), type = rollType();
      towers.push([p.x, p.y, 0, u, type], [m.x, m.y, 0, u, type]);
    }
  });
  // A big neutral prize in the middle
  if (rng() < 0.6) towers.push([FW / 2, FH / 2, 0, 14 + Math.floor(n / 3), n >= 3 && rng() < 0.5 ? 'fort' : n >= 4 ? 'factory' : 'barracks']);

  // Enemy outposts on later levels: the gray buildings nearest the red base turn red
  const enemyBase = { x: towers[1][0], y: towers[1][1] };
  const byEnemy = towers.filter(t => t[2] === 0 && t[1] < FH / 2).sort((a, b) => Math.hypot(a[0] - enemyBase.x, a[1] - enemyBase.y) - Math.hypot(b[0] - enemyBase.x, b[1] - enemyBase.y));
  const outposts = Math.min(2, Math.floor((n - 10) / 15));
  for (let k = 0; k < outposts && k < byEnemy.length - 1; k++) { byEnemy[k][2] = 2; byEnemy[k][3] = 8 + Math.floor(n / 6); }
  // Every third level from 12: a yellow army far from the red base. From 25, every fifth: green too.
  const extra = [];
  if (n >= 12 && n % 3 === 0) extra.push(3);
  if (n >= 25 && n % 5 === 0) extra.push(4);
  for (const side of extra) {
    const far = towers.filter(t => t[2] === 0 && t[1] < FH * 0.62).sort((a, b) => Math.abs(b[0] - enemyBase.x) - Math.abs(a[0] - enemyBase.x))[0];
    if (far) { far[2] = side; far[3] = baseUnits; }
  }

  // Walls: short lines of blocks in the middle, mirrored, never cutting a building off
  const rocks = [];
  if (n >= 6) {
    const count = 1 + (n >= 18) + (n >= 35);
    for (let k = 0; k < 300 && rocks.length < count * 2 * 4; k++) {
      const len = 3 + Math.floor(rng() * 3), r = 30, gap = 44;
      const a = Math.floor(rng() * 4) * Math.PI / 4;
      const p = { x: pick(140, 760), y: pick(540, 860) };
      const wall = [];
      for (let i = 0; i < len; i++) wall.push([p.x + Math.cos(a) * gap * (i - (len - 1) / 2), p.y + Math.sin(a) * gap * (i - (len - 1) / 2), r]);
      const both = [...wall, ...wall.map(([x, y]) => [FW - x, FH - y, r])];
      const clear = both.every(([x, y]) => x > 40 && x < FW - 40 && towers.every(t => Math.hypot(t[0] - x, t[1] - y) > r + 80)
        && rocks.every(o => Math.hypot(o[0] - x, o[1] - y) > r + o[2] + 8));
      if (!clear || wall.some(([x, y]) => Math.hypot(x - FW / 2, y - FH / 2) < 60)) continue;
      rocks.push(...both);
      if (!connected(towers, rocks)) rocks.splice(-both.length, both.length);
    }
  }
  const ai = { think: Math.max(0.8, 3.1 - n * 0.04), margin: Math.max(1.5, 7 - n * 0.1), bold: Math.min(1, 0.25 + n * 0.02) };
  const hints = {
    4: 'Soldiers from different armies fight when they meet on the field',
    6: 'Walls block roads. Find a way around them.',
    12: 'A third army! The enemies fight each other too. Let them wear each other down.',
  };
  return { towers, rocks, ai, hint: hints[n] };
}

// Every building can be reached from every other by roads that don't hit walls
function connected(towers, rocks) {
  const pts = towers.map(t => ({ x: t[0], y: t[1] }));
  const rk = rocks.map(r => ({ x: r[0], y: r[1], r: r[2] }));
  const seen = new Set([0]), queue = [0];
  while (queue.length) {
    const i = queue.pop();
    pts.forEach((p, j) => {
      if (!seen.has(j) && rk.every(r => segDist(r, pts[i], p) > r.r + 6)) { seen.add(j); queue.push(j); }
    });
  }
  return seen.size === pts.length;
}

function levelData(n) {
  return n <= TUTORIAL.length ? { rocks: [], ...TUTORIAL[n - 1] } : genLevel(n);
}

// ---------- Game state ----------
let state = 'menu';          // menu | play | paused | over
let level = 1;
let towers = [], rocks = [], units = [];
let floats = [], shells = [], cutMarks = [], strikes = [];
let aiSides = [];            // { side, timer, cfg }
let gameTime = 0, speed = 1, shake = 0;
let rally = 0;               // seconds of Rally left
let charges = { strike: 0, rally: 0 };
let armed = null;            // ability waiting for a target
let hintData = null, hintTimer = 0, handShown = false, linksMade = 0, cutsMade = 0;
let nextUnitId = 0;
let quiet = false;           // the menu's demo battle makes no sound
let stats = { captured: 0, lost: 0, killed: 0 };
let sceneLevel = 1;

function placeWorld() {
  for (const t of towers) Object.assign(t, toWorld(t.bx, t.by));
  for (const r of rocks) Object.assign(r, toWorld(r.bx, r.by));
}
// Portrait level coordinates to the field as it's shown now
function toWorld(x, y) {
  return landscape ? { x: FH - y, y: x } : { x, y };
}
function buildScene() {
  R3D.build(sceneLevel * 101 + 7, themeFor(sceneLevel), towers, rocks);
}
function sfx(name) { if (!quiet) Sfx.play(name); }

function loadTowers(data, n) {
  towers = data.towers.map(([x, y, owner, u, type = 'barracks'], id) => ({
    id, bx: x, by: y, x, y, owner, type,
    units: u + (owner === PLAYER && state !== 'menu' ? 3 * save.up.garrison : 0),
    roads: [], flash: 0, pop: 0, reload: 0, aim: -Math.PI / 2,
  }));
  rocks = data.rocks.map(([x, y, r], id) => ({ bx: x, by: y, x, y, r, seed: id * 31 + n }));
  units = []; floats = []; shells = []; cutMarks = []; strikes = [];
  placeWorld();
  sceneLevel = n;
  buildScene();
}

function startLevel(n) {
  level = n;
  state = 'play';
  const data = levelData(n);
  loadTowers(data, n);
  const sides = [...new Set(towers.map(t => t.owner))].filter(s => s > PLAYER);
  aiSides = sides.map((side, i) => ({ side, timer: 2.5 + i * 0.7, cfg: data.ai }));
  gameTime = 0; rally = 0; armed = null; shake = 0;
  stats = { captured: 0, lost: 0, killed: 0 };
  linksMade = 0; cutsMade = 0; handShown = !!data.hand;
  charges = { strike: n >= 3 ? 1 + save.up.armory : 0, rally: n >= 6 ? 1 + save.up.armory : 0 };
  hintData = data.hint || null;
  hintTimer = n === 2 ? 25 : 10;
  drag = null; cut = null;
  showScreen(null);
  $('hud').classList.remove('hidden');
  $('abilities').classList.remove('hidden');
  $('level-label').textContent = `Level ${n}`;
  buildAbilities();
  setHint(hintData);
  // Introduce a new building the first time it shows up
  const intro = Object.keys(TYPES).find(k => TYPES[k].intro && !save.seen[k] && towers.some(t => t.type === k));
  if (intro) { save.seen[intro] = true; writeSave(); setTimeout(() => toast(TYPES[intro].intro, 4200), 600); }
  Music.track = 'sunny';
  Music.start();
}

// ---------- Roads ----------
function blocked(a, b) {
  return rocks.some(r => segDist(r, a, b) < r.r + 6);
}
function hasRoad(a, b) { return a.roads.some(r => r.to === b); }

// Try to build a road from a to b for `side`. Returns true or the reason it can't.
function tryLink(a, b, side) {
  if (!a || !b || a === b) return 'same';
  if (a.owner !== side) return 'not yours';
  if (hasRoad(a, b)) return 'exists';
  if (blocked(a, b)) return 'blocked';
  // A road the other way between your own buildings turns around
  const back = b.owner === side ? b.roads.findIndex(r => r.to === a) : -1;
  if (a.roads.length >= maxRoads(a)) return 'full';
  if (back >= 0) b.roads.splice(back, 1);
  a.roads.push({ to: b, timer: 0, born: gameTime });
  return true;
}
function cutRoad(a, i) {
  a.roads.splice(i, 1);
}

function spawnUnit(from, to, power = 1) {
  units.push({
    id: nextUnitId++, from, to, owner: from.owner, power, d: towerRadius(from) * 0.5,
    lane: (Math.random() - 0.5) * 10, x: from.x, y: from.y,
  });
}

// ---------- Simulation ----------
function update(dt) {
  gameTime += dt;
  if (rally > 0) rally = Math.max(0, rally - dt);

  for (const t of towers) {
    if (t.owner !== NEUTRAL && t.units < CAP) t.units = Math.min(CAP, t.units + prodRate(t) * dt);
    t.flash = Math.max(0, t.flash - dt * 3);
    t.pop = Math.max(0, t.pop - dt * 4);
    for (const r of t.roads) {
      r.timer -= dt;
      if (r.timer > 0) continue;
      // Tank factories send a tank when they have enough soldiers for one
      const power = sendsTanks(t) && t.units >= TANK_POWER ? TANK_POWER : 1;
      if (t.units >= power) {
        t.units -= power;
        spawnUnit(t, r.to, power);
        r.timer = sendInterval(t) * (power > 1 ? 1 : 0.6);
      } else r.timer = 0;
    }
    if (t.type === 'watch') updateWatch(t, dt);
  }

  // March
  for (const u of units) {
    if (u.dead) continue;
    u.d += unitSpeed(u) * dt;
    const L = dist(u.from, u.to);
    const k = Math.min(1, u.d / L);
    const nx = -(u.to.y - u.from.y) / L, ny = (u.to.x - u.from.x) / L;
    const sway = Math.sin(k * Math.PI) * u.lane;
    u.x = u.from.x + (u.to.x - u.from.x) * k + nx * sway;
    u.y = u.from.y + (u.to.y - u.from.y) * k + ny * sway;
    if (u.d >= L - towerRadius(u.to) * 0.5) { arrive(u); u.dead = true; }
  }

  fight();
  units = units.filter(u => !u.dead);

  for (const a of aiSides) {
    a.timer -= dt;
    if (a.timer <= 0) { a.timer = a.cfg.think * (0.8 + Math.random() * 0.4); aiThink(a.side, a.cfg); }
  }

  updateStrikes(dt);
  updateEffects(dt);
  // Hints fade after a while (the first level waits for you to try the move)
  if (hintData && !armed) {
    hintTimer -= dt;
    if (hintTimer <= 0 && !handShown) { hintData = null; setHint(null); }
  }
  checkEnd();
}

function arrive(u) {
  const t = u.to, power = u.power || 1;
  if (t.owner === u.owner) {
    t.units = Math.min(HARD_CAP, t.units + power);
    t.pop = 1;
    return;
  }
  t.units -= power / TYPES[t.type].defense;
  t.flash = 1;
  if (Math.random() < 0.5) R3D.hit(t.x, t.y, u.owner);
  if (t.owner === PLAYER) sfx('hit');
  if (t.units < 0) capture(t, u.owner);
}

function capture(t, side) {
  const old = t.owner;
  t.owner = side;
  t.units = Math.abs(t.units);
  t.roads = [];
  t.pop = 1.5;
  R3D.capture(t.x, t.y, side);
  if (side === PLAYER) {
    stats.captured++;
    sfx('capture');
    floatText(t, 'Captured!', SIDES[PLAYER].light);
  } else if (old === PLAYER) {
    stats.lost++;
    sfx('warn');
    if (!quiet) shake = Math.max(shake, 6);
    floatText(t, 'Lost!', SIDES[side].light);
    if (!quiet && navigator.vibrate) try { navigator.vibrate(60); } catch { /* not allowed */ }
  }
}

// Soldiers of different armies that meet fight: the stronger one (a tank) survives, weakened
function fight() {
  const R = 16, cell = 32, grid = new Map();
  for (const u of units) {
    if (u.dead) continue;
    const key = Math.floor(u.x / cell) + ',' + Math.floor(u.y / cell);
    let list = grid.get(key);
    if (!list) grid.set(key, (list = []));
    list.push(u);
  }
  for (const u of units) {
    if (u.dead) continue;
    const cx = Math.floor(u.x / cell), cy = Math.floor(u.y / cell);
    for (let dx = -1; dx <= 1 && !u.dead; dx++) {
      for (let dy = -1; dy <= 1 && !u.dead; dy++) {
        const list = grid.get((cx + dx) + ',' + (cy + dy));
        if (!list) continue;
        for (const v of list) {
          if (v.dead || v === u || v.owner === u.owner) continue;
          if (Math.abs(u.x - v.x) < R && Math.abs(u.y - v.y) < R) {
            const m = Math.min(u.power, v.power);
            u.power -= m; v.power -= m;
            if (u.power <= 0) u.dead = true;
            if (v.power <= 0) v.dead = true;
            if (u.owner === PLAYER || v.owner === PLAYER) stats.killed++;
            clash((u.x + v.x) / 2, (u.y + v.y) / 2, u.owner, v.owner);
            if (u.dead) break;
          }
        }
      }
    }
  }
}

// Watchtowers shoot the nearest enemy inside their circle
function updateWatch(t, dt) {
  t.reload -= dt;
  if (t.owner === NEUTRAL || t.reload > 0) return;
  let best = null, bd = WATCH_RANGE;
  for (const u of units) {
    if (u.dead || u.owner === t.owner) continue;
    const d = dist(u, t);
    if (d < bd) { bd = d; best = u; }
  }
  if (!best) return;
  best.power -= 1;
  if (best.power <= 0) best.dead = true;
  t.reload = WATCH_RELOAD;
  t.aim = Math.atan2(best.y - t.y, best.x - t.x);
  shells.push({ x1: t.x, y1: t.y, x2: best.x, y2: best.y, h: 50, time: 0.18, dur: 0.18 });
  R3D.muzzle(t, best.x, best.y);
  R3D.hit(best.x, best.y, best.owner);
  if (t.owner === PLAYER || best.owner === PLAYER) sfx('shoot');
}

function sideTotals() {
  const tot = SIDES.map(() => 0);
  for (const t of towers) tot[t.owner] += t.units;
  for (const u of units) tot[u.owner] += u.power;
  return tot;
}
function alive(side) {
  return towers.some(t => t.owner === side) || units.some(u => u.owner === side);
}

function checkEnd() {
  if (state !== 'play') return;
  if (!alive(PLAYER)) return endGame(false);
  if (aiSides.every(a => a.side === PLAYER || !alive(a.side))) endGame(true);
}

// ---------- Enemy brains ----------
// Enemy strength heading for tower t, and `side`'s own strength heading there
function threatOn(t) {
  let n = 0;
  for (const u of units) if (u.to === t && u.owner !== t.owner) n += u.power;
  return n;
}
function inbound(t, side) {
  let n = 0;
  for (const u of units) if (u.to === t && u.owner === side) n += u.power;
  return n;
}

function aiThink(side, cfg) {
  const mine = towers.filter(t => t.owner === side);
  if (!mine.length) return;

  // Tidy up: pull back hopeless attacks and supply roads from threatened buildings
  for (const t of mine) {
    for (let i = t.roads.length - 1; i >= 0; i--) {
      const tgt = t.roads[i].to;
      if (tgt.owner === side) {
        if (threatOn(t) > t.units * 0.6 || (threatOn(tgt) === 0 && Math.random() < 0.35)) cutRoad(t, i);
      } else {
        const need = tgt.units * TYPES[tgt.type].defense;
        const sending = inbound(tgt, side) + towers.filter(s => s.owner === side && hasRoad(s, tgt)).reduce((a, s) => a + s.units, 0);
        if (t.units < 3 && sending < need * 0.7 && Math.random() < 0.6) cutRoad(t, i);
      }
    }
  }

  // Attack: find the cheapest, closest building it can take with up to 3 of its own
  let best = null;
  for (const tgt of towers) {
    if (tgt.owner === side) continue;
    const already = inbound(tgt, side) + mine.filter(s => hasRoad(s, tgt)).reduce((a, s) => a + s.units, 0);
    const sources = mine
      .filter(s => s.roads.length < maxRoads(s) && s.units >= 5 && !hasRoad(s, tgt) && !blocked(s, tgt) && threatOn(s) < s.units * 0.5)
      .sort((a, b) => dist(a, tgt) - dist(b, tgt));
    if (!sources.length) continue;
    const travel = dist(sources[0], tgt) / UNIT_SPEED;
    const grow = tgt.owner === NEUTRAL ? 0 : prodRate(tgt) * travel;
    // Watchtowers shoot some of the attackers on the way in
    const guard = towers.filter(w => w.type === 'watch' && w.owner !== NEUTRAL && w.owner !== side && dist(w, tgt) < WATCH_RANGE).length * 4;
    const need = (tgt.units + grow) * TYPES[tgt.type].defense + cfg.margin + guard - already;
    const used = [];
    let sum = 0;
    for (const s of sources) {
      if (sum >= need || used.length >= 3) break;
      used.push(s);
      sum += s.units - 1;
    }
    if (sum < need) continue;
    const d = used.reduce((a, s) => a + dist(s, tgt), 0) / used.length;
    const value = 1 + (tgt.owner === PLAYER ? cfg.bold : 0) + (tgt.type === 'factory' ? 0.4 : 0) + (tgt.owner !== NEUTRAL ? 0.2 : 0);
    const score = value / (Math.max(1, need) + d / 22);
    if (!best || score > best.score) best = { score, tgt, used };
  }
  if (best) for (const s of best.used) tryLink(s, best.tgt, side);

  // Reinforce buildings under attack from safe buildings nearby
  for (const t of mine) {
    const threat = threatOn(t);
    if (threat <= t.units * 0.8) continue;
    const helper = mine
      .filter(s => s !== t && s.units > 8 && threatOn(s) === 0 && s.roads.length < maxRoads(s) && !hasRoad(s, t) && !blocked(s, t))
      .sort((a, b) => dist(a, t) - dist(b, t))[0];
    if (helper) tryLink(helper, t, side);
  }
}

// ---------- Abilities ----------
const ABILITIES = {
  strike: { icon: '✈️', name: 'Airstrike', tip: 'Tap an enemy or gray building to bomb it' },
  rally: { icon: '📯', name: 'Rally', tip: '' },
};
function buildAbilities() {
  const box = $('abilities');
  box.innerHTML = '';
  for (const id of Object.keys(ABILITIES)) {
    if (!charges[id] && !(id === 'strike' ? level >= 3 : level >= 6)) continue;
    const b = document.createElement('button');
    b.className = 'ability';
    b.id = 'ab-' + id;
    b.title = ABILITIES[id].name;
    b.setAttribute('aria-label', ABILITIES[id].name);
    b.innerHTML = `${ABILITIES[id].icon}<span class="count"></span><span class="cd"></span><span class="name">${ABILITIES[id].name}</span>`;
    b.addEventListener('click', e => { e.stopPropagation(); useAbility(id); });
    box.appendChild(b);
  }
  refreshAbilities();
}
function refreshAbilities() {
  for (const id of Object.keys(ABILITIES)) {
    const b = $('ab-' + id);
    if (!b) continue;
    b.querySelector('.count').textContent = charges[id];
    b.disabled = state !== 'play' || (!charges[id] && armed !== id) || (id === 'rally' && rally > 0);
    b.classList.toggle('armed', armed === id);
    b.querySelector('.cd').style.setProperty('--p', id === 'rally' && rally > 0 ? (100 - (rally / 8) * 100) + '%' : '0%');
  }
}
function useAbility(id) {
  if (state !== 'play') return;
  Sfx.unlock();
  if (id === 'strike') {
    if (armed === 'strike') { armed = null; setHint(hintData); }
    else if (charges.strike > 0) { armed = 'strike'; setHint(ABILITIES.strike.tip); sfx('beep'); }
  } else if (id === 'rally' && charges.rally > 0 && rally <= 0) {
    charges.rally--;
    rally = 8;
    sfx('speed');
    toast('📯 Rally! Your roads send twice as fast for 8 seconds');
    for (const t of towers) if (t.owner === PLAYER) R3D.capture(t.x, t.y, PLAYER);
  }
  refreshAbilities();
}
const STRIKE_TIME = 1.6;
function dropStrike(t) {
  charges.strike--;
  armed = null;
  setHint(hintData);
  strikes.push({ t, time: STRIKE_TIME, dur: STRIKE_TIME });
  sfx('warn');
  refreshAbilities();
}
function updateStrikes(dt) {
  for (const s of strikes) {
    s.time -= dt;
    if (s.time <= 0 && !s.done) {
      s.done = true;
      const t = s.t;
      if (t.owner !== PLAYER) t.units = Math.max(0, t.units - Math.max(8, t.units * 0.5));
      t.flash = 1;
      for (const u of units) if (u.owner !== PLAYER && dist(u, t) < 130) u.dead = true;
      units = units.filter(u => !u.dead);
      R3D.explode(t.x, t.y, true);
      R3D.explode(t.x + 30, t.y - 20, false);
      R3D.explode(t.x - 26, t.y + 24, false);
      shake = 12;
      sfx('boom');
    }
  }
  strikes = strikes.filter(s => !s.done);
}

// ---------- Effects ----------
function clash(x, y, a, b) {
  R3D.clash(x, y, a, b);
  if (Math.random() < 0.3) sfx('pop');
}
function floatText(t, text, color) {
  floats.push({ t, text, color, life: 1.3 });
}
function updateEffects(dt) {
  for (const f of floats) f.life -= dt;
  floats = floats.filter(f => f.life > 0);
  for (const s of shells) s.time -= dt;
  shells = shells.filter(s => s.time > 0);
  for (const c of cutMarks) c.life -= dt;
  cutMarks = cutMarks.filter(c => c.life > 0);
  shake = Math.max(0, shake - dt * 30);
}

// ---------- Input ----------
let drag = null;   // { from, sx, sy, p }  dragging a road out of a building
let cut = null;    // { last }            swiping to cut roads

function toField(e) {
  return R3D.ground(e.clientX, e.clientY) || { x: -9999, y: -9999 };
}
// The building under a screen point: anywhere from its foot to its roof counts
function towerAt(sx, sy, slack = 1) {
  let best = null, bd = Infinity;
  for (const t of towers) {
    const s = R3D.towerScreen(t);
    const base = R3D.project(t.x, t.y, 0);
    const d = segDist({ x: sx, y: sy }, base, { x: s.topX, y: s.topY });
    const reach = Math.max(s.r + 10, 28) * slack;
    if (d < reach && d < bd) { bd = d; best = t; }
  }
  return best;
}

canvas.addEventListener('pointerdown', e => {
  if (state !== 'play') return;
  Sfx.unlock();
  canvas.setPointerCapture?.(e.pointerId);
  const p = toField(e);
  const t = towerAt(e.clientX, e.clientY);
  if (armed === 'strike') {
    if (t && t.owner !== PLAYER) dropStrike(t);
    else toast('Pick an enemy or gray building');
    return;
  }
  if (t && t.owner === PLAYER) drag = { from: t, sx: e.clientX, sy: e.clientY, p, id: e.pointerId };
  else cut = { last: p, id: e.pointerId };
});
canvas.addEventListener('pointermove', e => {
  if (drag && e.pointerId === drag.id) { drag.sx = e.clientX; drag.sy = e.clientY; drag.p = toField(e); }
  if (cut && e.pointerId === cut.id) { const p = toField(e); swipe(cut.last, p); cut.last = p; }
});
function endPointer(e) {
  if (drag && e.pointerId === drag.id) {
    const t = towerAt(e.clientX, e.clientY, 1.2);
    if (t && t !== drag.from && state === 'play') {
      const res = tryLink(drag.from, t, PLAYER);
      if (res === true) {
        linksMade++;
        sfx('go');
        if (handShown) { handShown = false; hintData = null; setHint(null); }
      } else if (res === 'full') {
        toast(`This building can hold ${maxRoads(drag.from)} road${maxRoads(drag.from) > 1 ? 's' : ''}. More soldiers unlock more.`);
        sfx('beep');
      } else if (res === 'blocked') {
        toast('A wall is in the way');
        sfx('beep');
      }
    }
    drag = null;
  }
  if (cut && e.pointerId === cut.id) cut = null;
}
canvas.addEventListener('pointerup', endPointer);
canvas.addEventListener('pointercancel', endPointer);
canvas.addEventListener('contextmenu', e => e.preventDefault());

// Cut any of your roads the swipe crosses
function swipe(a, b) {
  cutMarks.push({ x1: a.x, y1: a.y, x2: b.x, y2: b.y, life: 0.35 });
  for (const t of towers) {
    if (t.owner !== PLAYER) continue;
    for (let i = t.roads.length - 1; i >= 0; i--) {
      const hit = segCross(a, b, t, t.roads[i].to);
      if (hit) {
        cutRoad(t, i);
        cutsMade++;
        R3D.hit(hit.x, hit.y, PLAYER);
        sfx('cut');
        if (hintData && level === 2) { hintData = null; setHint(null); }
      }
    }
  }
}

window.addEventListener('keydown', e => {
  const k = e.key.toLowerCase();
  if (k === 'p' || k === 'escape') { if (state === 'play') pause(); else if (state === 'paused') resume(); }
  else if (k === 'm') toggleSound();
  else if (k === 'n') toggleMusic();
  else if (k === 'f' && state === 'play') toggleSpeed();
  else if (k === '1' && state === 'play') useAbility('strike');
  else if (k === '2' && state === 'play') useAbility('rally');
});

// ---------- Drawing ----------
const FONT = '"Lilita One", "Arial Rounded MT Bold", system-ui, sans-serif';
const P = (x, y, h = 0) => R3D.project(x, y, h);

// What ring to draw under a building: the drag source, a drag target, or an airstrike target
function highlight(t) {
  if (armed === 'strike' && t.owner !== PLAYER) return 'target';
  if (!drag) return null;
  if (t === drag.from) return 'source';
  if (dragOver === t) return dragOk(t) ? 'over' : 'bad';
  return null;
}
let dragOver = null;
function dragOk(t) {
  const a = drag.from;
  return t !== a && !hasRoad(a, t) && !blocked(a, t) && a.roads.length < maxRoads(a);
}

function outlinedText(text, x, y, size, fill = '#fff', stroke = 'rgba(20,24,40,0.9)') {
  ctx.font = `${size}px ${FONT}`;
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.lineJoin = 'round';
  ctx.lineWidth = Math.max(3, size * 0.22);
  ctx.strokeStyle = stroke;
  ctx.strokeText(text, x, y);
  ctx.fillStyle = fill;
  ctx.fillText(text, x, y);
}

// The number on each building's roof, and dots for its roads
function drawLabels() {
  for (const t of towers) {
    const s = R3D.towerScreen(t);
    const ppu = R3D.pxPerUnit(t.x, t.y);
    const size = clamp(ppu * 46, 15, 36);
    const n = Math.floor(Math.max(0, t.units));
    const text = n >= CAP ? 'Max' : String(n);
    const y = s.topY - size * 0.55;
    outlinedText(sendsTanks(t) ? '⇡' + text : text, s.topX, y, size, '#ffffff');
    // Road dots: white = a free road, faded = a road in use
    const m = maxRoads(t);
    const dr = Math.max(2.5, size * 0.17);
    for (let i = 0; i < m; i++) {
      const dx = (i - (m - 1) / 2) * dr * 2.9;
      ctx.beginPath();
      ctx.arc(s.topX + dx, y + size * 0.72, dr, 0, TAU);
      ctx.fillStyle = i < m - t.roads.length ? '#ffffff' : 'rgba(255,255,255,0.35)';
      ctx.fill();
      ctx.lineWidth = 1.5;
      ctx.strokeStyle = 'rgba(20,24,40,0.6)';
      ctx.stroke();
    }
  }
}

function drawDrag() {
  if (!drag) return;
  const a = drag.from;
  const start = P(a.x, a.y, 4);
  let end = { x: drag.sx, y: drag.sy }, ok = a.roads.length < maxRoads(a) && !blocked(a, drag.p);
  if (dragOver && dragOver !== a) { end = P(dragOver.x, dragOver.y, 4); ok = dragOk(dragOver); }
  const col = ok ? SIDES[PLAYER].color : '#ff4a3a';
  ctx.lineCap = 'round';
  ctx.strokeStyle = 'rgba(255,255,255,0.9)';
  ctx.lineWidth = 16;
  ctx.beginPath(); ctx.moveTo(start.x, start.y); ctx.lineTo(end.x, end.y); ctx.stroke();
  ctx.strokeStyle = col;
  ctx.lineWidth = 10;
  ctx.setLineDash([14, 10]);
  ctx.lineDashOffset = -performance.now() / 20;
  ctx.beginPath(); ctx.moveTo(start.x, start.y); ctx.lineTo(end.x, end.y); ctx.stroke();
  ctx.setLineDash([]);
  ctx.fillStyle = col;
  ctx.beginPath(); ctx.arc(end.x, end.y, 9, 0, TAU); ctx.fill();
}

// A ghost hand that shows how to drag a road, on the first level
function drawHand() {
  if (!handShown || drag) return;
  const from = towers.find(t => t.owner === PLAYER);
  const to = towers.filter(t => t.owner === NEUTRAL).sort((a, b) => a.units - b.units)[0];
  if (!from || !to) return;
  const k = (performance.now() / 1600) % 1;
  const m = clamp((k - 0.15) / 0.6, 0, 1);
  const e = m * m * (3 - 2 * m);
  const a = P(from.x, from.y, 4), b = P(to.x, to.y, 4);
  const x = a.x + (b.x - a.x) * e, y = a.y + (b.y - a.y) * e;
  ctx.globalAlpha = k > 0.85 ? (1 - k) / 0.15 : 1;
  ctx.strokeStyle = 'rgba(255,255,255,0.85)';
  ctx.lineWidth = 6;
  ctx.setLineDash([12, 10]);
  ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(x, y); ctx.stroke();
  ctx.setLineDash([]);
  ctx.font = '52px system-ui';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'top';
  ctx.fillText('👆', x + 10, y - 6);
  ctx.globalAlpha = 1;
}

function drawOverlay() {
  ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
  ctx.clearRect(0, 0, W, H);
  if (!towers.length) return;
  if (state !== 'menu' && !screenOpen) drawLabels();
  // Swipe trail
  ctx.lineCap = 'round';
  for (const c of cutMarks) {
    const a = P(c.x1, c.y1, 2), b = P(c.x2, c.y2, 2);
    ctx.strokeStyle = `rgba(255,255,255,${(c.life / 0.35) * 0.9})`;
    ctx.lineWidth = 7 * (c.life / 0.35) + 1;
    ctx.beginPath(); ctx.moveTo(a.x, a.y); ctx.lineTo(b.x, b.y); ctx.stroke();
  }
  // Airstrike crosshair
  for (const st of strikes) {
    const c = P(st.t.x, st.t.y, 0);
    const r = 30 + (st.time / st.dur) * 30;
    ctx.strokeStyle = '#ff3b30';
    ctx.lineWidth = 4;
    ctx.beginPath(); ctx.arc(c.x, c.y, r, 0, TAU); ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(c.x - r - 12, c.y); ctx.lineTo(c.x - r + 12, c.y);
    ctx.moveTo(c.x + r - 12, c.y); ctx.lineTo(c.x + r + 12, c.y);
    ctx.moveTo(c.x, c.y - r - 12); ctx.lineTo(c.x, c.y - r + 12);
    ctx.moveTo(c.x, c.y + r - 12); ctx.lineTo(c.x, c.y + r + 12);
    ctx.stroke();
  }
  if (state !== 'menu' && !screenOpen) {
    for (const f of floats) {
      const c = P(f.t.x, f.t.y, R3D.towerTop(f.t) + 30 + (1.3 - f.life) * 40);
      ctx.globalAlpha = Math.min(1, f.life * 1.5);
      outlinedText(f.text, c.x, c.y, 24, f.color);
    }
  }
  ctx.globalAlpha = 1;
  drawDrag();
  drawHand();
}

function draw() {
  dragOver = drag ? towerAt(drag.sx, drag.sy, 1.2) : null;
  R3D.render({ towers, units, shells, strikes, threatOn, highlight, gameTime });
  drawOverlay();
  const gl = $('gl');
  if (gl) gl.style.transform = shake ? `translate(${(Math.random() - 0.5) * shake}px, ${(Math.random() - 0.5) * shake}px)` : '';
}

// ---------- HUD ----------
let lastHud = 0;
function updateHud() {
  const now = performance.now();
  if (now - lastHud < 150) return;
  lastHud = now;
  const tot = sideTotals();
  const sum = tot.reduce((a, b) => a + b, 0) || 1;
  const box = $('power');
  const present = [PLAYER, ...aiSides.map(a => a.side).filter(s => s !== PLAYER), NEUTRAL];
  if (box.dataset.sides !== present.join()) {
    box.dataset.sides = present.join();
    box.innerHTML = present.map(sd => `<div data-side="${sd}" style="background:${SIDES[sd].color}"></div>`).join('');
  }
  for (const el of box.children) {
    const sd = Number(el.dataset.side);
    el.style.flexGrow = tot[sd] / sum;
    el.textContent = sd !== NEUTRAL && tot[sd] / sum > 0.12 ? Math.floor(tot[sd]) : '';
  }
  $('time-label').textContent = fmtTime(gameTime);
  refreshAbilities();
}

let toastTimer = 0;
function toast(text, ms = 2200) {
  const el = $('toast');
  el.textContent = text;
  el.classList.add('show');
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => el.classList.remove('show'), ms);
}
function setHint(text) {
  const el = $('hint');
  el.textContent = text || '';
  el.classList.toggle('hidden', !text);
}

// ---------- Screens ----------
let screenOpen = null;
function showScreen(id) {
  screenOpen = id;
  if (id) { clearTimeout(toastTimer); $('toast').classList.remove('show'); }
  for (const el of document.querySelectorAll('.screen')) el.classList.toggle('show', el.id === id);
}
let returnTo = 'menu';
function openMenu() {
  state = 'menu';
  armed = null;
  rally = 0;
  demoTimer = 0;
  $('hud').classList.add('hidden');
  $('abilities').classList.add('hidden');
  setHint(null);
  showScreen('menu');
  refreshMenu();
  Music.track = 'night';
}
function refreshMenu() {
  $('menu-coins').textContent = save.coins;
  $('play-btn').innerHTML = `PLAY <small>Level ${Math.min(save.level, MAX_LEVEL)}</small>`;
  refreshToggles();
}
function refreshToggles() {
  for (const id of ['sound-btn', 'sound-btn2']) $(id).innerHTML = Icons.sound(!Sfx.muted);
  for (const id of ['music-btn', 'music-btn2']) $(id).innerHTML = Icons.music(Music.enabled && !Sfx.muted);
  $('menu-btn').innerHTML = Icons.pause;
}

function openLevels() {
  const grid = $('level-grid');
  grid.innerHTML = '';
  let total = 0;
  for (let n = 1; n <= MAX_LEVEL; n++) {
    const st = save.stars[n] || 0;
    total += st;
    const b = document.createElement('button');
    const locked = n > save.level;
    b.disabled = locked;
    b.className = 'theme-' + themeFor(n) + (n === save.level ? ' current' : '');
    b.innerHTML = locked ? `${n}${Icons.lock}` : `${n}<small>${'★'.repeat(st)}${'☆'.repeat(3 - st)}</small>`;
    b.addEventListener('click', () => startLevel(n));
    grid.appendChild(b);
  }
  $('levels-stars').textContent = total;
  showScreen('levels');
  grid.querySelector('.current')?.scrollIntoView({ block: 'center' });
}

function openShop(from = 'menu') {
  returnTo = from;
  $('shop-coins').textContent = save.coins;
  const list = $('shop-list');
  list.innerHTML = '';
  for (const u of UPGRADES) {
    const lv = save.up[u.id];
    const maxed = lv >= u.max;
    const cost = maxed ? 0 : u.cost[lv];
    const row = document.createElement('div');
    row.className = 'shop-item';
    row.innerHTML = `<div class="ico">${u.icon}</div><div class="info"><b>${u.name}</b><span>${u.desc}</span>
      <div class="pips">${Array.from({ length: u.max }, (_, i) => `<i class="${i < lv ? 'on' : ''}"></i>`).join('')}</div></div>`;
    const b = document.createElement('button');
    b.id = 'buy-' + u.id;
    b.innerHTML = maxed ? 'MAX' : `<span class="coin"></span>${cost}`;
    b.disabled = maxed || save.coins < cost;
    b.addEventListener('click', () => {
      if (save.coins < cost || maxed) return;
      save.coins -= cost;
      save.up[u.id]++;
      writeSave();
      sfx('coin');
      openShop(returnTo);
    });
    row.appendChild(b);
    list.appendChild(row);
  }
  showScreen('shop');
}

function pause() {
  if (state !== 'play') return;
  state = 'paused';
  drag = cut = null;
  showScreen('paused');
  refreshToggles();
  Music.stop();
}
function resume() {
  if (state !== 'paused') return;
  state = 'play';
  showScreen(null);
  Music.start();
}
function toggleSpeed() {
  speed = speed === 1 ? 2 : 1;
  $('speed-btn').textContent = speed + '×';
}
function toggleSound() {
  Sfx.toggle();
  if (Sfx.muted) Music.stop(); else if (state === 'play') Music.start();
  refreshToggles();
}
function toggleMusic() {
  Music.toggle();
  if (Music.enabled && state === 'play') Music.start(); else Music.stop();
  refreshToggles();
}

function starsFor(time) {
  const par = 30 + towers.length * 7;
  return time <= par ? 3 : time <= par * 1.8 ? 2 : 1;
}

function endGame(won) {
  state = 'over';
  drag = cut = null;
  armed = null;
  setHint(null);
  refreshAbilities();
  Music.stop();
  setTimeout(() => {
    if (won) showWin(); else showLose();
  }, 1100);
  if (won) { sfx('win'); for (const t of towers) R3D.capture(t.x, t.y, PLAYER); }
  else sfx('death');
}

function showWin() {
  const stars = starsFor(gameTime);
  const before = save.stars[level] || 0;
  const firstWin = level >= save.level;
  let coins = 15 + level * 2 + stars * 5;
  if (!firstWin) coins = Math.round(coins / 2);
  save.coins += coins;
  save.stars[level] = Math.max(before, stars);
  let unlock = '';
  if (firstWin && level < MAX_LEVEL) {
    save.level = level + 1;
    if (level + 1 === 3) unlock = '✈️ Airstrike unlocked! Bomb a building once per battle.';
    if (level + 1 === 6) unlock = '📯 Rally unlocked! Double your marching power for 8 seconds.';
  }
  writeSave();
  $('win-stars').innerHTML = '<span>★</span><span>★</span><span>★</span>';
  const spans = $('win-stars').querySelectorAll('span');
  spans.forEach((sp, i) => setTimeout(() => { if (i < stars) { sp.classList.add('on'); sfx('coin'); } }, 250 + i * 280));
  $('win-stats').innerHTML = `<div><b>${fmtTime(gameTime)}</b><span>Time</span></div><div><b>${stats.captured}</b><span>Captured</span></div><div><b>${stats.killed}</b><span>Beaten</span></div>`;
  $('win-coins').innerHTML = `<span class="coin"></span>+${coins}`;
  $('win-unlock').textContent = unlock;
  $('win-unlock').classList.toggle('hidden', !unlock);
  $('next-btn').classList.toggle('hidden', level >= MAX_LEVEL);
  $('hud').classList.add('hidden');
  $('abilities').classList.add('hidden');
  showScreen('win');
}

const TIPS = [
  'Take the gray buildings near you first. They\'re cheap, and every building trains soldiers.',
  'Attack from two or three buildings at once to break a big tower.',
  'Cut roads to buildings that are already safe, so your soldiers stay home to defend.',
  'Tank factories send tanks worth 3 soldiers each. Grab them early.',
  'Bunkers take half damage. Leave them for later unless you have a big army.',
  'Stay out of watchtower circles, or send a big wave all at once.',
  'Upgrades make every battle easier. Spend your coins!',
  'When two enemies fight, wait for them to wear each other down.',
];
function showLose() {
  $('lose-tip').textContent = '💡 ' + TIPS[(level + Math.floor(gameTime)) % TIPS.length];
  $('hud').classList.add('hidden');
  $('abilities').classList.add('hidden');
  showScreen('lose');
}

// ---------- Buttons ----------
$('play-btn').addEventListener('click', () => {
  Sfx.unlock();
  if (!save.help) { save.help = true; writeSave(); }
  startLevel(Math.min(save.level, MAX_LEVEL));
});
$('levels-btn').addEventListener('click', openLevels);
$('shop-btn').addEventListener('click', () => openShop('menu'));
$('help-btn').addEventListener('click', () => { returnTo = 'menu'; showScreen('help'); });
for (const b of document.querySelectorAll('.back-btn')) b.addEventListener('click', () => {
  if (returnTo === 'lose') { returnTo = 'menu'; showScreen('lose'); } else openMenu();
});
$('menu-btn').addEventListener('click', pause);
$('speed-btn').addEventListener('click', toggleSpeed);
$('resume-btn').addEventListener('click', resume);
$('restart-btn').addEventListener('click', () => startLevel(level));
$('quit-btn').addEventListener('click', openMenu);
$('next-btn').addEventListener('click', () => startLevel(Math.min(level + 1, MAX_LEVEL)));
$('replay-btn').addEventListener('click', () => startLevel(level));
$('retry-btn').addEventListener('click', () => startLevel(level));
$('lose-shop-btn').addEventListener('click', () => openShop('lose'));
for (const b of document.querySelectorAll('.menu-btn2')) b.addEventListener('click', openMenu);
for (const id of ['sound-btn', 'sound-btn2']) $(id).addEventListener('click', toggleSound);
for (const id of ['music-btn', 'music-btn2']) $(id).addEventListener('click', toggleMusic);
document.addEventListener('visibilitychange', () => { if (document.hidden) pause(); });

// ---------- Main loop ----------
let last = performance.now();
function frame(now) {
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  if (state === 'play') {
    for (let i = 0; i < speed; i++) update(dt);
    updateHud();
  } else if (state === 'over') {
    updateEffects(dt);
  } else if (state === 'menu') {
    menuDemo(dt);
  }
  draw();
  requestAnimationFrame(frame);
}

// A battle between AI armies plays behind the menu
let demoTimer = 0;
function menuDemo(dt) {
  if (towers.length && (!alive(2) || !alive(PLAYER))) demoTimer = Math.min(demoTimer, 3);
  if (demoTimer <= 0 || !towers.length) {
    const n = 7 + Math.floor(Math.random() * 30);
    loadTowers(genLevel(n), n);
    aiSides = [...new Set(towers.map(t => t.owner))].filter(s => s !== NEUTRAL)
      .map((side, i) => ({ side, timer: 1 + i * 0.4, cfg: { think: 1.4, margin: 3, bold: 0.5 } }));
    demoTimer = 90;
  }
  demoTimer -= dt;
  quiet = true;
  update(dt);
  quiet = false;
}

// ---------- Start ----------
if (!R3D.init(canvas, SIDES)) {
  document.body.innerHTML = '<p style="padding:24px;text-align:center">Tower Siege needs WebGL, which this browser doesn\'t support.</p>';
} else {
  resize();
  refreshMenu();
  requestAnimationFrame(frame);
}
