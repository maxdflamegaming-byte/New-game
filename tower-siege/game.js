'use strict';

// Tower Siege: build roads between towers, march soldiers along them and take the map.
// The field is 900×1400 world units in portrait. On a wide screen it's turned on its side,
// so your base starts on the left instead of the bottom.

// ---------- Canvas setup ----------
const canvas = document.getElementById('game');
const ctx = canvas.getContext('2d');
let W = 0, H = 0, DPR = 1;

const FW = 900, FH = 1400;
let landscape = false;
let view = { s: 1, ox: 0, oy: 0, fw: FW, fh: FH };

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
  const fw = landscape ? FH : FW, fh = landscape ? FW : FH;
  const top = 60, bottom = 88, side = 12;
  const s = Math.min((W - side * 2) / fw, (H - top - bottom) / fh);
  view = { s, fw, fh, ox: (W - fw * s) / 2, oy: top + (H - top - bottom - fh * s) / 2 };
  if (wasLandscape !== landscape || !bg) placeWorld();
  bg = null;
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

// ---------- Factions and tower types ----------
const NEUTRAL = 0, PLAYER = 1;
const SIDES = [
  { name: 'Neutral', color: '#9aa1a9', dark: '#5d646c', light: '#c9ced3' },
  { name: 'You', color: '#3d8bfd', dark: '#1d4fa8', light: '#9cc6ff' },
  { name: 'Red', color: '#e5483b', dark: '#93231a', light: '#ff9b90' },
  { name: 'Gold', color: '#f0b323', dark: '#9a6c00', light: '#ffe08a' },
];

const TYPES = {
  barracks: { name: 'Barracks', prod: 1, defense: 1 },
  fort: { name: 'Fort', prod: 0.8, defense: 2, intro: '🛡️ New: the Fort. Attackers only do half damage to it.' },
  workshop: { name: 'Workshop', prod: 2, defense: 1, intro: '⚙️ New: the Workshop. It trains soldiers twice as fast.' },
  cannon: { name: 'Cannon', prod: 0.6, defense: 1, intro: '🎯 New: the Cannon. It shoots enemy soldiers that march past it.' },
};

const CAP = 99;             // towers stop training here
const HARD_CAP = 150;       // and can't be filled above this
const UNIT_SPEED = 95;      // world units per second
const CANNON_RANGE = 190;
const CANNON_RELOAD = 0.7;
const MAX_LEVEL = 60;

const towerLevel = t => (t.units >= 60 ? 4 : t.units >= 30 ? 3 : t.units >= 10 ? 2 : 1);
const maxRoads = t => Math.min(3, towerLevel(t));
const towerRadius = t => 33 + towerLevel(t) * 6;
const prodRate = t => (0.55 + 0.2 * towerLevel(t)) * TYPES[t.type].prod * (t.owner === PLAYER ? 1 + 0.08 * save.up.drill : 1);
const sendInterval = t => 1 / (1.6 + 0.4 * towerLevel(t)) / (t.owner === PLAYER && rally > 0 ? 2 : 1);
const unitSpeed = owner => UNIT_SPEED * (owner === PLAYER ? (1 + 0.07 * save.up.boots) * (rally > 0 ? 1.4 : 1) : 1);

// ---------- Saved progress ----------
const SAVE_KEY = 'tower-siege-save';
const UPGRADES = [
  { id: 'drill', icon: '🥁', name: 'Drill Sergeant', desc: 'Your towers train soldiers 8% faster per level', max: 5, cost: [60, 120, 220, 360, 550] },
  { id: 'boots', icon: '👢', name: 'Swift Boots', desc: 'Your soldiers march 7% faster per level', max: 5, cost: [50, 100, 180, 300, 480] },
  { id: 'garrison', icon: '🏰', name: 'Garrison', desc: '+3 soldiers in each of your starting towers per level', max: 5, cost: [40, 90, 160, 260, 400] },
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
// Towers are [x, y, owner, soldiers, type]. AI: think = seconds between moves,
// margin = spare soldiers it wants before attacking, bold = how much it prefers hitting you.
const TUTORIAL = [
  {
    towers: [[450, 1180, 1, 12], [260, 760, 0, 5], [640, 700, 0, 7], [450, 240, 2, 6]],
    ai: { think: 4.5, margin: 8, bold: 0 },
    hint: 'Drag from your blue tower to a gray tower to send soldiers',
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
    if (n >= 3 && r < 0.17) return 'fort';
    if (n >= 5 && r < 0.32) return 'workshop';
    if (n >= 8 && r < 0.45) return 'cannon';
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
  if (rng() < 0.6) towers.push([FW / 2, FH / 2, 0, 14 + Math.floor(n / 3), n >= 3 && rng() < 0.6 ? 'fort' : 'workshop']);

  // Enemy outposts on later levels: the gray towers nearest the red base turn red
  const enemyBase = { x: towers[1][0], y: towers[1][1] };
  const byEnemy = towers.filter(t => t[2] === 0 && t[1] < FH / 2).sort((a, b) => Math.hypot(a[0] - enemyBase.x, a[1] - enemyBase.y) - Math.hypot(b[0] - enemyBase.x, b[1] - enemyBase.y));
  const outposts = Math.min(2, Math.floor((n - 5) / 15));
  for (let k = 0; k < outposts && k < byEnemy.length - 1; k++) { byEnemy[k][2] = 2; byEnemy[k][3] = 8 + Math.floor(n / 6); }
  // Every third level from 12: a second enemy (Gold) far from the red base
  const threeWay = n >= 12 && n % 3 === 0;
  if (threeWay) {
    const far = towers.filter(t => t[2] === 0 && t[1] < FH * 0.62).sort((a, b) => Math.abs(b[0] - enemyBase.x) - Math.abs(a[0] - enemyBase.x))[0];
    if (far) { far[2] = 3; far[3] = baseUnits; }
  }

  // Rocks in the middle band, mirrored, never cutting a tower off
  const rocks = [];
  if (n >= 6) {
    const count = 1 + (n >= 20) + (n >= 35);
    for (let k = 0; k < 200 && rocks.length < count * 2; k++) {
      const r = pick(38, 68);
      const p = { x: pick(120, 780), y: pick(520, 880) };
      const m = mirror(p);
      const clear = q => towers.every(t => Math.hypot(t[0] - q.x, t[1] - q.y) > r + 75) && rocks.every(o => Math.hypot(o[0] - q.x, o[1] - q.y) > r + o[2] + 20);
      if (!clear(p) || !clear(m) || dist(p, m) < r * 2 + 20) continue;
      rocks.push([p.x, p.y, r], [m.x, m.y, r]);
      if (!connected(towers, rocks)) rocks.splice(-2, 2);
    }
  }
  const ai = { think: Math.max(0.7, 2.7 - n * 0.035), margin: Math.max(1, 6 - n * 0.09), bold: Math.min(1, 0.25 + n * 0.02) };
  const hints = {
    4: 'Soldiers from different armies fight when they meet on the field',
    6: 'Rocks block roads. Find a way around them.',
    12: 'Two enemies! They fight each other too. Let them wear each other down.',
  };
  return { towers, rocks, ai, hint: hints[n] };
}

// Every tower can be reached from every other by roads that don't hit rocks
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
let particles = [], floats = [], shots = [], cutMarks = [], strikes = [];
let aiSides = [];            // { side, timer, cfg }
let gameTime = 0, speed = 1, shake = 0;
let rally = 0;               // seconds of Rally left
let charges = { strike: 0, rally: 0 };
let armed = null;            // ability waiting for a target
let hintData = null, hintTimer = 0, handShown = false, linksMade = 0, cutsMade = 0;
let bg = null;
let nextUnitId = 0;
let stats = { captured: 0, lost: 0, killed: 0 };

function placeWorld() {
  for (const t of towers) Object.assign(t, toWorld(t.bx, t.by));
  for (const r of rocks) Object.assign(r, toWorld(r.bx, r.by));
}
// Portrait level coordinates to the field as it's shown now
function toWorld(x, y) {
  return landscape ? { x: FH - y, y: x } : { x, y };
}

function startLevel(n) {
  level = n;
  const data = levelData(n);
  towers = data.towers.map(([x, y, owner, u, type = 'barracks'], id) => ({
    id, bx: x, by: y, x, y, owner, type,
    units: u + (owner === PLAYER ? 3 * save.up.garrison : 0),
    roads: [], flash: 0, pop: 0, reload: 0, aim: -Math.PI / 2,
  }));
  rocks = data.rocks.map(([x, y, r], id) => ({ bx: x, by: y, x, y, r, seed: id * 31 + n }));
  placeWorld();
  units = []; particles = []; floats = []; shots = []; cutMarks = []; strikes = [];
  const sides = [...new Set(towers.map(t => t.owner))].filter(s => s > PLAYER);
  aiSides = sides.map((side, i) => ({ side, timer: 2.5 + i * 0.7, cfg: data.ai }));
  gameTime = 0; rally = 0; armed = null; shake = 0;
  stats = { captured: 0, lost: 0, killed: 0 };
  linksMade = 0; cutsMade = 0; handShown = !!data.hand;
  charges = { strike: n >= 3 ? 1 + save.up.armory : 0, rally: n >= 6 ? 1 + save.up.armory : 0 };
  hintData = data.hint || null;
  hintTimer = n === 2 ? 25 : 10;
  drag = null; cut = null;
  bg = null;
  state = 'play';
  showScreen(null);
  $('hud').classList.remove('hidden');
  $('abilities').classList.remove('hidden');
  $('level-label').textContent = `Level ${n}`;
  buildAbilities();
  setHint(hintData);
  // Introduce a new tower type the first time it shows up
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
  // A road the other way between your own towers turns around
  const back = b.owner === side ? b.roads.findIndex(r => r.to === a) : -1;
  if (a.roads.length >= maxRoads(a)) return 'full';
  if (back >= 0) b.roads.splice(back, 1);
  a.roads.push({ to: b, timer: 0, born: gameTime });
  return true;
}
function cutRoad(a, i) {
  a.roads.splice(i, 1);
}

function spawnUnit(from, to) {
  units.push({
    id: nextUnitId++, from, to, owner: from.owner, d: towerRadius(from) * 0.6,
    lane: (Math.random() - 0.5) * 12, x: from.x, y: from.y,
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
      if (r.timer <= 0 && t.units >= 1) {
        t.units -= 1;
        spawnUnit(t, r.to);
        r.timer += sendInterval(t);
        if (r.timer < 0) r.timer = 0;
      } else if (r.timer < 0) r.timer = 0;
    }
    if (t.type === 'cannon') updateCannon(t, dt);
  }

  // March
  for (const u of units) {
    if (u.dead) continue;
    u.d += unitSpeed(u.owner) * dt;
    const L = dist(u.from, u.to);
    const k = Math.min(1, u.d / L);
    const nx = -(u.to.y - u.from.y) / L, ny = (u.to.x - u.from.x) / L;
    const sway = Math.sin(k * Math.PI) * u.lane;
    u.x = u.from.x + (u.to.x - u.from.x) * k + nx * sway;
    u.y = u.from.y + (u.to.y - u.from.y) * k + ny * sway;
    if (u.d >= L - towerRadius(u.to) * 0.6) { arrive(u); u.dead = true; }
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
  const t = u.to;
  if (t.owner === u.owner) {
    t.units = Math.min(HARD_CAP, t.units + 1);
    t.pop = 1;
    return;
  }
  t.units -= 1 / TYPES[t.type].defense;
  t.flash = 1;
  if (t.owner === PLAYER) Sfx.play('hit');
  if (t.units < 0) capture(t, u.owner);
}

function capture(t, side) {
  const old = t.owner;
  t.owner = side;
  t.units = Math.abs(t.units);
  t.roads = [];
  t.pop = 1.5;
  burst(t.x, t.y, SIDES[side].color, 26, 160);
  ring(t.x, t.y, SIDES[side].color);
  if (side === PLAYER) {
    stats.captured++;
    Sfx.play('capture');
    floatText(t.x, t.y - 50, 'Captured!', SIDES[PLAYER].light);
  } else if (old === PLAYER) {
    stats.lost++;
    Sfx.play('warn');
    shake = Math.max(shake, 6);
    floatText(t.x, t.y - 50, 'Lost!', SIDES[side].light);
    if (navigator.vibrate) try { navigator.vibrate(60); } catch { /* not allowed */ }
  }
}

// Soldiers of different armies that meet both fall
function fight() {
  const R = 10, cell = 24, grid = new Map();
  for (const u of units) {
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
          if (v.dead || v.owner === u.owner) continue;
          if (Math.abs(u.x - v.x) < R && Math.abs(u.y - v.y) < R) {
            u.dead = v.dead = true;
            if (u.owner === PLAYER || v.owner === PLAYER) stats.killed++;
            clash((u.x + v.x) / 2, (u.y + v.y) / 2);
            break;
          }
        }
      }
    }
  }
}

function updateCannon(t, dt) {
  t.reload -= dt;
  if (t.owner === NEUTRAL || t.reload > 0) return;
  let best = null, bd = CANNON_RANGE;
  for (const u of units) {
    if (u.dead || u.owner === t.owner) continue;
    const d = dist(u, t);
    if (d < bd) { bd = d; best = u; }
  }
  if (!best) return;
  best.dead = true;
  t.reload = CANNON_RELOAD;
  t.aim = Math.atan2(best.y - t.y, best.x - t.x);
  shots.push({ x1: t.x + Math.cos(t.aim) * 26, y1: t.y + Math.sin(t.aim) * 26, x2: best.x, y2: best.y, life: 0.15, color: SIDES[t.owner].light });
  burst(best.x, best.y, '#ffd28a', 6, 80);
  if (t.owner === PLAYER || best.owner === PLAYER) Sfx.play('shoot');
}

function sideTotals() {
  const tot = [0, 0, 0, 0];
  for (const t of towers) tot[t.owner] += t.units;
  for (const u of units) tot[u.owner] += 1;
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
// Soldiers needed to take tower t (counting what's already on the way)
function threatOn(t) {
  let n = 0;
  for (const u of units) if (u.to === t && u.owner !== t.owner) n++;
  return n;
}
function inbound(t, side) {
  let n = 0;
  for (const u of units) if (u.to === t && u.owner === side) n++;
  return n;
}

function aiThink(side, cfg) {
  const mine = towers.filter(t => t.owner === side);
  if (!mine.length) return;

  // Tidy up: pull back hopeless attacks and supply roads from threatened towers
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

  // Attack: find the cheapest, closest tower it can take with up to 3 towers
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
    const need = (tgt.units + grow) * TYPES[tgt.type].defense + cfg.margin - already;
    const used = [];
    let sum = 0;
    for (const s of sources) {
      if (sum >= need || used.length >= 3) break;
      used.push(s);
      sum += s.units - 1;
    }
    if (sum < need) continue;
    const d = used.reduce((a, s) => a + dist(s, tgt), 0) / used.length;
    let value = 1 + (tgt.owner === PLAYER ? cfg.bold : 0) + (tgt.type === 'workshop' ? 0.4 : 0) + (tgt.owner !== NEUTRAL ? 0.2 : 0);
    const score = value / (Math.max(1, need) + d / 22);
    if (!best || score > best.score) best = { score, tgt, used };
  }
  if (best) for (const s of best.used) tryLink(s, best.tgt, side);

  // Reinforce towers under attack from safe towers nearby
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
  strike: { icon: '💣', name: 'Airstrike', tip: 'Tap an enemy or gray tower to bomb it' },
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
    b.innerHTML = `${ABILITIES[id].icon}<span class="count"></span><span class="cd"></span>`;
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
    else if (charges.strike > 0) { armed = 'strike'; setHint(ABILITIES.strike.tip); Sfx.play('beep'); }
  } else if (id === 'rally' && charges.rally > 0 && rally <= 0) {
    charges.rally--;
    rally = 8;
    Sfx.play('speed');
    toast('📯 Rally! Your roads send twice as fast for 8 seconds');
    for (const t of towers) if (t.owner === PLAYER) ring(t.x, t.y, '#ffd54a');
  }
  refreshAbilities();
}
function dropStrike(t) {
  charges.strike--;
  armed = null;
  setHint(hintData);
  strikes.push({ t, time: 0.9 });
  Sfx.play('warn');
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
      burst(t.x, t.y, '#ffb347', 40, 260);
      burst(t.x, t.y, '#555', 20, 120);
      ring(t.x, t.y, '#ffdd88');
      shake = 12;
      Sfx.play('boom');
    }
  }
  strikes = strikes.filter(s => !s.done);
}

// ---------- Effects ----------
function burst(x, y, color, n, spd) {
  for (let i = 0; i < n; i++) {
    const a = Math.random() * TAU, v = spd * (0.3 + Math.random() * 0.7);
    particles.push({ x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v, life: 0.5 + Math.random() * 0.4, max: 0.9, color, size: 2 + Math.random() * 3 });
  }
}
function clash(x, y) {
  for (let i = 0; i < 4; i++) {
    const a = Math.random() * TAU, v = 40 + Math.random() * 60;
    particles.push({ x, y, vx: Math.cos(a) * v, vy: Math.sin(a) * v, life: 0.3, max: 0.3, color: '#fff3c4', size: 2 });
  }
  if (Math.random() < 0.3) Sfx.play('pop');
}
function ring(x, y, color) {
  particles.push({ x, y, ring: true, life: 0.6, max: 0.6, color, size: 20 });
}
function floatText(x, y, text, color) {
  floats.push({ x, y, text, color, life: 1.3 });
}
function updateEffects(dt) {
  for (const p of particles) {
    p.life -= dt;
    if (!p.ring) { p.x += p.vx * dt; p.y += p.vy * dt; p.vx *= 0.92; p.vy *= 0.92; }
  }
  particles = particles.filter(p => p.life > 0);
  for (const f of floats) { f.life -= dt; f.y -= 30 * dt; }
  floats = floats.filter(f => f.life > 0);
  for (const s of shots) s.life -= dt;
  shots = shots.filter(s => s.life > 0);
  for (const c of cutMarks) c.life -= dt;
  cutMarks = cutMarks.filter(c => c.life > 0);
  shake = Math.max(0, shake - dt * 30);
}

// ---------- Input ----------
let drag = null;   // { from, x, y }  dragging a road out of a tower
let cut = null;    // { last }        swiping to cut roads

function toField(e) {
  return { x: (e.clientX - view.ox) / view.s, y: (e.clientY - view.oy) / view.s };
}
function towerAt(p, slack = 1) {
  let best = null, bd = Infinity;
  for (const t of towers) {
    const d = dist(p, t);
    const reach = Math.max(towerRadius(t) + 16, 34 / view.s) * slack;
    if (d < reach && d < bd) { bd = d; best = t; }
  }
  return best;
}

canvas.addEventListener('pointerdown', e => {
  if (state !== 'play') return;
  Sfx.unlock();
  canvas.setPointerCapture?.(e.pointerId);
  const p = toField(e);
  const t = towerAt(p);
  if (armed === 'strike') {
    if (t && t.owner !== PLAYER) dropStrike(t);
    else toast('Pick an enemy or gray tower');
    return;
  }
  if (t && t.owner === PLAYER) drag = { from: t, x: p.x, y: p.y, id: e.pointerId };
  else cut = { last: p, id: e.pointerId };
});
canvas.addEventListener('pointermove', e => {
  const p = toField(e);
  if (drag && e.pointerId === drag.id) { drag.x = p.x; drag.y = p.y; }
  if (cut && e.pointerId === cut.id) { swipe(cut.last, p); cut.last = p; }
});
function endPointer(e) {
  if (drag && e.pointerId === drag.id) {
    const p = toField(e);
    const t = towerAt(p, 1.15);
    if (t && t !== drag.from) {
      const res = tryLink(drag.from, t, PLAYER);
      if (res === true) {
        linksMade++;
        Sfx.play('go');
        if (handShown) { handShown = false; hintData = null; setHint(null); }
      } else if (res === 'full') {
        toast(`This tower can hold ${maxRoads(drag.from)} road${maxRoads(drag.from) > 1 ? 's' : ''}. More soldiers unlock more.`);
        Sfx.play('beep');
      } else if (res === 'blocked') {
        toast('Rocks are in the way');
        Sfx.play('beep');
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
        burst(hit.x, hit.y, '#ffffff', 10, 120);
        Sfx.play('cut');
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
function wx(x) { return view.ox + x * view.s; }
function wy(y) { return view.oy + y * view.s; }

function buildBackground() {
  const c = document.createElement('canvas');
  c.width = canvas.width;
  c.height = canvas.height;
  const g = c.getContext('2d');
  g.setTransform(DPR, 0, 0, DPR, 0, 0);
  const s = view.s;
  g.fillStyle = '#1d2b18';
  g.fillRect(0, 0, W, H);
  const fx = view.ox, fy = view.oy, fw = view.fw * s, fh = view.fh * s;
  // Field with a soft edge
  g.save();
  g.shadowColor = 'rgba(0,0,0,0.5)';
  g.shadowBlur = 24;
  roundRect(g, fx - 8, fy - 8, fw + 16, fh + 16, 26 * s + 8);
  g.fillStyle = '#3f6a2f';
  g.fill();
  g.restore();
  g.save();
  roundRect(g, fx - 8, fy - 8, fw + 16, fh + 16, 26 * s + 8);
  g.clip();
  const grad = g.createLinearGradient(fx, fy, fx + fw, fy + fh);
  grad.addColorStop(0, '#5b8f42');
  grad.addColorStop(1, '#4b7d36');
  g.fillStyle = grad;
  g.fillRect(fx - 8, fy - 8, fw + 16, fh + 16);
  const rng = mulberry32(level * 101 + 7);
  // Meadow patches
  for (let i = 0; i < 26; i++) {
    const x = fx + rng() * fw, y = fy + rng() * fh, r = (40 + rng() * 90) * s;
    const pg = g.createRadialGradient(x, y, 0, x, y, r);
    const light = rng() < 0.5;
    pg.addColorStop(0, light ? 'rgba(140,190,90,0.22)' : 'rgba(40,70,30,0.2)');
    pg.addColorStop(1, 'rgba(0,0,0,0)');
    g.fillStyle = pg;
    g.fillRect(x - r, y - r, r * 2, r * 2);
  }
  // Grass tufts and little flowers
  for (let i = 0; i < 420; i++) {
    const x = fx + rng() * fw, y = fy + rng() * fh;
    g.strokeStyle = rng() < 0.5 ? 'rgba(30,60,20,0.35)' : 'rgba(150,200,100,0.3)';
    g.lineWidth = 1.2;
    g.beginPath();
    g.moveTo(x, y); g.lineTo(x - 2 * s, y - 6 * s);
    g.moveTo(x, y); g.lineTo(x + 2 * s, y - 7 * s);
    g.stroke();
  }
  for (let i = 0; i < 40; i++) {
    g.fillStyle = ['#fff6d5', '#ffd1e0', '#ffe066'][i % 3];
    g.beginPath();
    g.arc(fx + rng() * fw, fy + rng() * fh, 1.8 * Math.max(1, s), 0, TAU);
    g.fill();
  }
  // Rocks
  for (const r of rocks) drawRock(g, r);
  // Vignette
  const vg = g.createRadialGradient(fx + fw / 2, fy + fh / 2, Math.min(fw, fh) * 0.35, fx + fw / 2, fy + fh / 2, Math.max(fw, fh) * 0.75);
  vg.addColorStop(0, 'rgba(0,0,0,0)');
  vg.addColorStop(1, 'rgba(0,0,0,0.3)');
  g.fillStyle = vg;
  g.fillRect(fx - 8, fy - 8, fw + 16, fh + 16);
  g.restore();
  bg = c;
}

function roundRect(g, x, y, w, h, r) {
  g.beginPath();
  g.moveTo(x + r, y);
  g.arcTo(x + w, y, x + w, y + h, r);
  g.arcTo(x + w, y + h, x, y + h, r);
  g.arcTo(x, y + h, x, y, r);
  g.arcTo(x, y, x + w, y, r);
  g.closePath();
}

function drawRock(g, r) {
  const rng = mulberry32(r.seed + 5);
  const x = wx(r.x), y = wy(r.y), R = r.r * view.s;
  const pts = [];
  const n = 9;
  for (let i = 0; i < n; i++) {
    const a = (i / n) * TAU, k = 0.8 + rng() * 0.25;
    pts.push([x + Math.cos(a) * R * k, y + Math.sin(a) * R * k]);
  }
  const path = () => { g.beginPath(); pts.forEach(([px, py], i) => (i ? g.lineTo(px, py) : g.moveTo(px, py))); g.closePath(); };
  g.save();
  g.translate(4 * view.s, 7 * view.s);
  path();
  g.fillStyle = 'rgba(0,0,0,0.3)';
  g.fill();
  g.restore();
  path();
  const rg = g.createLinearGradient(x - R, y - R, x + R, y + R);
  rg.addColorStop(0, '#a7a39a');
  rg.addColorStop(1, '#5f5b54');
  g.fillStyle = rg;
  g.fill();
  g.strokeStyle = '#4a4741';
  g.lineWidth = 2;
  g.stroke();
  // Cracks and moss
  g.strokeStyle = 'rgba(60,56,50,0.6)';
  g.lineWidth = 1.5;
  for (let i = 0; i < 3; i++) {
    const a = rng() * TAU;
    g.beginPath();
    g.moveTo(x + Math.cos(a) * R * 0.2, y + Math.sin(a) * R * 0.2);
    g.lineTo(x + Math.cos(a + 0.3) * R * 0.6, y + Math.sin(a + 0.3) * R * 0.6);
    g.stroke();
  }
  g.fillStyle = 'rgba(110,150,70,0.55)';
  g.beginPath();
  g.ellipse(x - R * 0.25, y - R * 0.45, R * 0.35, R * 0.16, -0.3, 0, TAU);
  g.fill();
}

function drawRoads() {
  const s = view.s;
  const now = performance.now() / 1000;
  for (const t of towers) {
    for (const r of t.roads) {
      const b = r.to;
      const col = SIDES[t.owner];
      const x1 = wx(t.x), y1 = wy(t.y), x2 = wx(b.x), y2 = wy(b.y);
      const grow = clamp((gameTime - r.born) / 0.25, 0, 1);
      const ex = x1 + (x2 - x1) * grow, ey = y1 + (y2 - y1) * grow;
      ctx.lineCap = 'round';
      // Dirt road
      ctx.strokeStyle = 'rgba(70,52,30,0.45)';
      ctx.lineWidth = 16 * s;
      ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(ex, ey); ctx.stroke();
      ctx.strokeStyle = col.color + '55';
      ctx.lineWidth = 11 * s;
      ctx.beginPath(); ctx.moveTo(x1, y1); ctx.lineTo(ex, ey); ctx.stroke();
      // Marching arrows
      const L = Math.hypot(ex - x1, ey - y1);
      const a = Math.atan2(y2 - y1, x2 - x1);
      const gap = 34 * s, off = (now * 60 * s) % gap;
      ctx.fillStyle = col.light + 'aa';
      for (let d = off + towerRadius(t) * s; d < L - towerRadius(b) * s; d += gap) {
        const px = x1 + Math.cos(a) * d, py = y1 + Math.sin(a) * d;
        ctx.save();
        ctx.translate(px, py);
        ctx.rotate(a);
        ctx.beginPath();
        ctx.moveTo(4 * s, 0); ctx.lineTo(-3 * s, -4 * s); ctx.lineTo(-1 * s, 0); ctx.lineTo(-3 * s, 4 * s);
        ctx.closePath();
        ctx.fill();
        ctx.restore();
      }
    }
  }
}

function drawUnits() {
  const s = view.s;
  const r = Math.max(3, 5 * s);
  const now = performance.now() / 1000;
  for (const u of units) {
    const col = SIDES[u.owner];
    const x = wx(u.x), y = wy(u.y) - Math.abs(Math.sin(now * 10 + u.id)) * 2 * s;
    ctx.fillStyle = 'rgba(0,0,0,0.25)';
    ctx.beginPath(); ctx.ellipse(wx(u.x), wy(u.y) + r * 0.8, r, r * 0.45, 0, 0, TAU); ctx.fill();
    ctx.fillStyle = col.dark;
    ctx.beginPath(); ctx.arc(x, y, r + 1.2, 0, TAU); ctx.fill();
    ctx.fillStyle = col.color;
    ctx.beginPath(); ctx.arc(x, y, r, 0, TAU); ctx.fill();
    ctx.fillStyle = col.light;
    ctx.beginPath(); ctx.arc(x - r * 0.3, y - r * 0.35, r * 0.38, 0, TAU); ctx.fill();
  }
}

function drawTower(t) {
  const s = view.s;
  const x = wx(t.x), y = wy(t.y);
  const lv = towerLevel(t);
  const r = towerRadius(t) * s * (1 + t.pop * 0.08);
  const col = SIDES[t.owner];
  const now = performance.now() / 1000;

  // Shadow
  ctx.fillStyle = 'rgba(0,0,0,0.3)';
  ctx.beginPath(); ctx.ellipse(x + 3 * s, y + r * 0.55, r * 1.05, r * 0.55, 0, 0, TAU); ctx.fill();

  // Range of a cannon
  if (t.type === 'cannon' && t.owner !== NEUTRAL) {
    ctx.strokeStyle = col.color + '33';
    ctx.setLineDash([6 * s, 8 * s]);
    ctx.lineWidth = 2;
    ctx.beginPath(); ctx.arc(x, y, CANNON_RANGE * s, 0, TAU); ctx.stroke();
    ctx.setLineDash([]);
  }

  // Stone wall with battlements
  const stone = t.type === 'fort' ? '#8d8679' : '#9b978e';
  const merlons = 8 + lv * 2;
  ctx.fillStyle = t.type === 'fort' ? '#6e685d' : '#7d7970';
  for (let i = 0; i < merlons; i++) {
    const a = (i / merlons) * TAU;
    ctx.save();
    ctx.translate(x + Math.cos(a) * r, y + Math.sin(a) * r);
    ctx.rotate(a);
    ctx.fillRect(-4 * s, -5 * s, 8 * s, 10 * s);
    ctx.restore();
  }
  const wg = ctx.createRadialGradient(x - r * 0.3, y - r * 0.3, r * 0.2, x, y, r);
  wg.addColorStop(0, '#c9c4b8');
  wg.addColorStop(1, stone);
  ctx.fillStyle = wg;
  ctx.beginPath(); ctx.arc(x, y, r, 0, TAU); ctx.fill();
  ctx.strokeStyle = 'rgba(60,55,48,0.7)';
  ctx.lineWidth = (t.type === 'fort' ? 4 : 2) * s;
  ctx.stroke();

  // Banner-colored keep
  const ir = r * 0.68;
  const kg = ctx.createRadialGradient(x - ir * 0.35, y - ir * 0.4, ir * 0.1, x, y, ir);
  kg.addColorStop(0, col.light);
  kg.addColorStop(0.55, col.color);
  kg.addColorStop(1, col.dark);
  ctx.fillStyle = kg;
  ctx.beginPath(); ctx.arc(x, y, ir, 0, TAU); ctx.fill();
  if (t.flash > 0) {
    ctx.fillStyle = `rgba(255,255,255,${t.flash * 0.5})`;
    ctx.beginPath(); ctx.arc(x, y, ir, 0, TAU); ctx.fill();
  }

  drawGlyph(t, x, y, ir);

  // Level pips
  for (let i = 0; i < lv; i++) {
    const a = -Math.PI / 2 + (i - (lv - 1) / 2) * 0.32;
    ctx.fillStyle = '#ffe28a';
    ctx.beginPath(); ctx.arc(x + Math.cos(a) * (r + 9 * s), y + Math.sin(a) * (r + 9 * s), 3 * Math.max(1, s), 0, TAU); ctx.fill();
  }

  // Soldier count
  const n = Math.floor(Math.max(0, t.units));
  const fs = Math.max(12, 17 * s);
  ctx.font = `900 ${fs}px system-ui, sans-serif`;
  const tw = ctx.measureText(n).width + fs * 0.8;
  const py = y + r + fs * 0.35;
  ctx.fillStyle = 'rgba(10,14,8,0.82)';
  roundRect(ctx, x - tw / 2, py - fs * 0.62, tw, fs * 1.24, fs * 0.62);
  ctx.fill();
  ctx.strokeStyle = col.color;
  ctx.lineWidth = 2;
  ctx.stroke();
  ctx.fillStyle = '#fff';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'middle';
  ctx.fillText(n, x, py + 1);

  // Free road slots on your towers
  if (t.owner === PLAYER) {
    const m = maxRoads(t);
    for (let i = 0; i < m; i++) {
      const dx = (i - (m - 1) / 2) * 9 * Math.max(1, s);
      ctx.beginPath();
      ctx.arc(x + dx, py + fs * 0.95, 3 * Math.max(1, s), 0, TAU);
      if (i < t.roads.length) { ctx.fillStyle = '#ffffff'; ctx.fill(); }
      else { ctx.strokeStyle = 'rgba(255,255,255,0.8)'; ctx.lineWidth = 1.5; ctx.stroke(); }
    }
  }

  // Under attack
  if (t.owner === PLAYER && threatOn(t) > 0) {
    ctx.strokeStyle = `rgba(255,80,60,${0.4 + 0.3 * Math.sin(now * 8)})`;
    ctx.lineWidth = 3;
    ctx.beginPath(); ctx.arc(x, y, r + 14 * s, 0, TAU); ctx.stroke();
  }
}

function drawGlyph(t, x, y, ir) {
  const s = ir / 20;
  ctx.save();
  ctx.translate(x, y);
  ctx.fillStyle = 'rgba(255,255,255,0.92)';
  ctx.strokeStyle = 'rgba(255,255,255,0.92)';
  ctx.lineWidth = 2.2 * s;
  ctx.lineCap = 'round';
  ctx.lineJoin = 'round';
  if (t.type === 'barracks') {
    // A flag on a pole
    ctx.beginPath(); ctx.moveTo(-5 * s, 10 * s); ctx.lineTo(-5 * s, -11 * s); ctx.stroke();
    const wave = Math.sin(performance.now() / 250 + t.id) * 1.5 * s;
    ctx.beginPath();
    ctx.moveTo(-4 * s, -11 * s);
    ctx.quadraticCurveTo(2 * s, -13 * s + wave, 9 * s, -8 * s);
    ctx.quadraticCurveTo(2 * s, -5 * s + wave, -4 * s, -3 * s);
    ctx.closePath();
    ctx.fill();
  } else if (t.type === 'fort') {
    ctx.beginPath();
    ctx.moveTo(0, -11 * s); ctx.lineTo(9 * s, -7 * s); ctx.lineTo(8 * s, 3 * s);
    ctx.quadraticCurveTo(5 * s, 9 * s, 0, 12 * s);
    ctx.quadraticCurveTo(-5 * s, 9 * s, -8 * s, 3 * s);
    ctx.lineTo(-9 * s, -7 * s);
    ctx.closePath();
    ctx.fill();
    ctx.fillStyle = SIDES[t.owner].dark;
    ctx.fillRect(-1.5 * s, -7 * s, 3 * s, 15 * s);
    ctx.fillRect(-6 * s, -2 * s, 12 * s, 3 * s);
  } else if (t.type === 'workshop') {
    ctx.rotate(performance.now() / 900);
    for (let i = 0; i < 8; i++) {
      ctx.rotate(TAU / 8);
      ctx.fillRect(-2.5 * s, -12 * s, 5 * s, 6 * s);
    }
    ctx.beginPath(); ctx.arc(0, 0, 8 * s, 0, TAU); ctx.fill();
    ctx.fillStyle = SIDES[t.owner].dark;
    ctx.beginPath(); ctx.arc(0, 0, 3.5 * s, 0, TAU); ctx.fill();
  } else if (t.type === 'cannon') {
    ctx.rotate(t.aim);
    ctx.fillStyle = '#2b2b2b';
    ctx.fillRect(0, -3.5 * s, 16 * s, 7 * s);
    ctx.fillStyle = '#444';
    ctx.beginPath(); ctx.arc(0, 0, 7.5 * s, 0, TAU); ctx.fill();
    ctx.fillStyle = 'rgba(255,255,255,0.3)';
    ctx.beginPath(); ctx.arc(-2 * s, -2 * s, 3 * s, 0, TAU); ctx.fill();
  }
  ctx.restore();
}

function drawEffects() {
  const s = view.s;
  for (const sh of shots) {
    ctx.strokeStyle = sh.color;
    ctx.globalAlpha = sh.life / 0.15;
    ctx.lineWidth = 2.5;
    ctx.beginPath(); ctx.moveTo(wx(sh.x1), wy(sh.y1)); ctx.lineTo(wx(sh.x2), wy(sh.y2)); ctx.stroke();
  }
  ctx.globalAlpha = 1;
  for (const p of particles) {
    const k = p.life / p.max;
    ctx.globalAlpha = Math.min(1, k * 1.5);
    if (p.ring) {
      ctx.strokeStyle = p.color;
      ctx.lineWidth = 4 * k;
      ctx.beginPath(); ctx.arc(wx(p.x), wy(p.y), (30 + (1 - k) * 70) * s, 0, TAU); ctx.stroke();
    } else {
      ctx.fillStyle = p.color;
      ctx.beginPath(); ctx.arc(wx(p.x), wy(p.y), p.size * Math.max(0.7, s) * (0.4 + k * 0.6), 0, TAU); ctx.fill();
    }
  }
  ctx.globalAlpha = 1;
  // Falling bombs
  for (const st of strikes) {
    const x = wx(st.t.x), y = wy(st.t.y);
    const k = st.time / 0.9;
    ctx.strokeStyle = 'rgba(255,60,40,0.9)';
    ctx.lineWidth = 3;
    ctx.beginPath(); ctx.arc(x, y, (30 + k * 40) * s, 0, TAU); ctx.stroke();
    ctx.beginPath();
    ctx.moveTo(x - 50 * s, y); ctx.lineTo(x + 50 * s, y);
    ctx.moveTo(x, y - 50 * s); ctx.lineTo(x, y + 50 * s);
    ctx.stroke();
    ctx.font = `${Math.max(20, 32 * s)}px system-ui`;
    ctx.textAlign = 'center';
    ctx.fillText('💣', x, y - k * 220 * s);
  }
  // Swipe trail
  ctx.lineCap = 'round';
  for (const c of cutMarks) {
    ctx.strokeStyle = `rgba(255,255,255,${c.life / 0.35 * 0.8})`;
    ctx.lineWidth = 5 * (c.life / 0.35) + 1;
    ctx.beginPath(); ctx.moveTo(wx(c.x1), wy(c.y1)); ctx.lineTo(wx(c.x2), wy(c.y2)); ctx.stroke();
  }
  for (const f of floats) {
    ctx.globalAlpha = Math.min(1, f.life);
    ctx.font = `900 ${Math.max(14, 20 * s)}px system-ui, sans-serif`;
    ctx.textAlign = 'center';
    ctx.lineWidth = 4;
    ctx.strokeStyle = 'rgba(0,0,0,0.7)';
    ctx.strokeText(f.text, wx(f.x), wy(f.y));
    ctx.fillStyle = f.color;
    ctx.fillText(f.text, wx(f.x), wy(f.y));
  }
  ctx.globalAlpha = 1;
}

function drawDrag() {
  if (!drag) return;
  const s = view.s;
  const a = drag.from;
  const target = towerAt(drag, 1.15);
  const end = target && target !== a ? target : drag;
  let ok = true;
  if (target && target !== a) ok = !hasRoad(a, target) && !blocked(a, target) && a.roads.length < maxRoads(a);
  else ok = !blocked(a, drag) && a.roads.length < maxRoads(a);
  const color = ok ? '#ffffff' : '#ff5a4a';
  ctx.strokeStyle = color;
  ctx.lineWidth = 5 * Math.max(0.8, s);
  ctx.setLineDash([12 * s, 9 * s]);
  ctx.lineDashOffset = -performance.now() / 20;
  ctx.beginPath(); ctx.moveTo(wx(a.x), wy(a.y)); ctx.lineTo(wx(end.x), wy(end.y)); ctx.stroke();
  ctx.setLineDash([]);
  ctx.beginPath(); ctx.arc(wx(a.x), wy(a.y), (towerRadius(a) + 10) * s, 0, TAU); ctx.stroke();
  if (target && target !== a) {
    ctx.beginPath(); ctx.arc(wx(target.x), wy(target.y), (towerRadius(target) + 12) * s, 0, TAU); ctx.stroke();
  }
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
  const x = wx(from.x + (to.x - from.x) * e), y = wy(from.y + (to.y - from.y) * e);
  ctx.globalAlpha = k > 0.85 ? (1 - k) / 0.15 : 1;
  ctx.strokeStyle = 'rgba(255,255,255,0.7)';
  ctx.lineWidth = 4;
  ctx.setLineDash([10, 8]);
  ctx.beginPath(); ctx.moveTo(wx(from.x), wy(from.y)); ctx.lineTo(x, y); ctx.stroke();
  ctx.setLineDash([]);
  ctx.font = '44px system-ui';
  ctx.textAlign = 'center';
  ctx.textBaseline = 'top';
  ctx.fillText('👆', x + 8, y - 6);
  ctx.globalAlpha = 1;
}

function draw() {
  ctx.setTransform(DPR, 0, 0, DPR, 0, 0);
  if (!bg) buildBackground();
  const sx = shake ? (Math.random() - 0.5) * shake : 0, sy = shake ? (Math.random() - 0.5) * shake : 0;
  ctx.setTransform(1, 0, 0, 1, 0, 0);
  ctx.drawImage(bg, 0, 0);
  ctx.setTransform(DPR, 0, 0, DPR, sx * DPR, sy * DPR);
  if (!towers.length) return;
  drawRoads();
  drawUnits();
  for (const t of towers) drawTower(t);
  drawEffects();
  drawDrag();
  drawHand();
  if (armed === 'strike') {
    for (const t of towers) {
      if (t.owner === PLAYER) continue;
      ctx.strokeStyle = `rgba(255,70,50,${0.5 + 0.4 * Math.sin(performance.now() / 120)})`;
      ctx.lineWidth = 3;
      ctx.beginPath(); ctx.arc(wx(t.x), wy(t.y), (towerRadius(t) + 14) * view.s, 0, TAU); ctx.stroke();
    }
  }
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
  const present = [PLAYER, ...aiSides.map(a => a.side), NEUTRAL];
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
function showScreen(id) {
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
  $('play-btn').textContent = `Play · Level ${Math.min(save.level, MAX_LEVEL)}`;
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
    if (n === save.level) b.className = 'current';
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
    b.textContent = maxed ? 'Max' : `● ${cost}`;
    b.disabled = maxed || save.coins < cost;
    b.addEventListener('click', () => {
      if (save.coins < cost || maxed) return;
      save.coins -= cost;
      save.up[u.id]++;
      writeSave();
      Sfx.play('coin');
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
  }, 900);
  if (won) { Sfx.play('win'); for (const t of towers) burst(t.x, t.y, SIDES[PLAYER].light, 14, 180); }
  else Sfx.play('death');
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
    if (level + 1 === 3) unlock = '💣 Airstrike unlocked! Bomb a tower once per battle.';
    if (level + 1 === 6) unlock = '📯 Rally unlocked! Double your marching power for 8 seconds.';
  }
  writeSave();
  $('win-stars').innerHTML = '<span>★</span><span>★</span><span>★</span>';
  const spans = $('win-stars').querySelectorAll('span');
  spans.forEach((sp, i) => setTimeout(() => { if (i < stars) { sp.classList.add('on'); Sfx.play('coin'); } }, 250 + i * 280));
  $('win-stats').textContent = `${fmtTime(gameTime)} · ${stats.captured} towers taken · ${stats.killed} soldiers beaten`;
  $('win-coins').innerHTML = `<span class="coin">●</span> +${coins}`;
  $('win-unlock').textContent = unlock;
  $('win-unlock').classList.toggle('hidden', !unlock);
  $('next-btn').classList.toggle('hidden', level >= MAX_LEVEL);
  $('hud').classList.add('hidden');
  $('abilities').classList.add('hidden');
  showScreen('win');
}

const TIPS = [
  'Take the gray towers near you first. They\'re cheap, and every tower trains soldiers.',
  'Attack from two or three towers at once to break a big tower.',
  'Cut roads to towers that are already safe, so your soldiers stay home to defend.',
  'Workshops train twice as fast. Grab them early.',
  'Forts take half damage. Leave them for later unless you have a big army.',
  'Stay out of cannon range, or send a big wave all at once.',
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
  } else if (state === 'over' || state === 'menu') {
    updateEffects(dt);
  }
  if (state === 'menu') menuDemo(dt);
  draw();
  requestAnimationFrame(frame);
}

// A calm battle between two AI armies plays behind the menu
let demoTimer = 0;
function menuDemo(dt) {
  // Start over when the battle is decided (after a short pause) or has gone on long enough
  if (towers.length && (!alive(2) || !alive(PLAYER))) demoTimer = Math.min(demoTimer, 3);
  if (demoTimer <= 0 || !towers.length) {
    const data = genLevel(9 + Math.floor(Math.random() * 20));
    towers = data.towers.map(([x, y, owner, u, type = 'barracks'], id) => ({ id, bx: x, by: y, x, y, owner, type, units: u, roads: [], flash: 0, pop: 0, reload: 0, aim: 0 }));
    rocks = data.rocks.map(([x, y, r], id) => ({ bx: x, by: y, x, y, r, seed: id }));
    placeWorld();
    units = [];
    aiSides = [{ side: 1, timer: 1, cfg: { think: 1.6, margin: 3, bold: 0.5 } }, { side: 2, timer: 1.4, cfg: { think: 1.6, margin: 3, bold: 0.5 } }];
    bg = null;
    strikes = [];
    demoTimer = 90;
  }
  demoTimer -= dt;
  const g = gameTime;
  // Run the battle without the win check, music or sounds
  for (const t of towers) {
    if (t.owner !== NEUTRAL && t.units < CAP) t.units = Math.min(CAP, t.units + prodRate(t) * dt);
    t.flash = Math.max(0, t.flash - dt * 3);
    t.pop = Math.max(0, t.pop - dt * 4);
    for (const r of t.roads) {
      r.timer -= dt;
      if (r.timer <= 0 && t.units >= 1) { t.units -= 1; spawnUnit(t, r.to); r.timer = sendInterval(t); } else if (r.timer < 0) r.timer = 0;
    }
    if (t.type === 'cannon') updateCannon(t, dt);
  }
  for (const u of units) {
    u.d += UNIT_SPEED * dt;
    const L = dist(u.from, u.to), k = Math.min(1, u.d / L);
    u.x = u.from.x + (u.to.x - u.from.x) * k;
    u.y = u.from.y + (u.to.y - u.from.y) * k;
    if (u.d >= L - towerRadius(u.to) * 0.6) {
      u.dead = true;
      const t = u.to;
      if (t.owner === u.owner) t.units = Math.min(HARD_CAP, t.units + 1);
      else { t.units -= 1 / TYPES[t.type].defense; t.flash = 1; if (t.units < 0) { t.owner = u.owner; t.units = -t.units; t.roads = []; ring(t.x, t.y, SIDES[u.owner].color); } }
    }
  }
  fight();
  units = units.filter(u => !u.dead);
  for (const a of aiSides) {
    a.timer -= dt;
    if (a.timer <= 0) { a.timer = a.cfg.think; aiThink(a.side, a.cfg); }
  }
  gameTime = g + dt;
}

resize();
refreshMenu();
requestAnimationFrame(frame);
