'use strict';

// ---------- Canvas setup ----------
const canvas = document.getElementById('game');
const ctx = canvas.getContext('2d');
let W = 0, H = 0;

function resize() {
  const dpr = Math.min(window.devicePixelRatio || 1, 2);
  W = window.innerWidth;
  H = window.innerHeight;
  canvas.width = W * dpr;
  canvas.height = H * dpr;
  canvas.style.width = W + 'px';
  canvas.style.height = H + 'px';
  ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
}
window.addEventListener('resize', resize);
resize();

// ---------- Helpers ----------
const $ = id => document.getElementById(id);
const TAU = Math.PI * 2;
const rand = (a, b) => a + Math.random() * (b - a);
const fmtTime = s => `${Math.floor(s / 60)}:${String(Math.floor(s % 60)).padStart(2, '0')}`;

function shuffle(arr) {
  const a = arr.slice();
  for (let i = a.length - 1; i > 0; i--) {
    const j = Math.floor(Math.random() * (i + 1));
    [a[i], a[j]] = [a[j], a[i]];
  }
  return a;
}

function loadBest() {
  try { return Number(localStorage.getItem('glow-survivors-best')) || 0; } catch { return 0; }
}
function saveBest(v) {
  try { localStorage.setItem('glow-survivors-best', String(v)); } catch { /* storage unavailable */ }
}

// ---------- Upgrades ----------
// `desc` can be a function of the current level so new weapons read differently from upgrades.
const UPGRADES = [
  { id: 'damage', icon: '⚔️', name: 'Sharper Magic', desc: '+30% damage for every weapon', apply: p => { p.damage *= 1.3; } },
  { id: 'rate', icon: '⚡', name: 'Quick Cast', desc: '+25% bolt fire rate', apply: p => { p.fireRate *= 1.25; } },
  { id: 'multi', icon: '✨', name: 'Split Shot', desc: '+1 bolt per cast', max: 5, apply: p => { p.shots += 1; } },
  { id: 'pierce', icon: '🎯', name: 'Piercing', desc: 'Bolts pass through +1 enemy', max: 4, apply: p => { p.pierce += 1; } },
  { id: 'orb', icon: '🌀', name: 'Orbiting Blade', desc: lv => (lv ? '+1 blade' : 'A blade circles around you'), max: 6, apply: p => { p.orbs += 1; } },
  { id: 'lightning', icon: '🌩️', name: 'Storm Call', desc: lv => (lv ? '+1 lightning strike' : 'Lightning strikes random enemies'), max: 5, apply: p => { p.lightning += 1; } },
  { id: 'aura', icon: '🔥', name: 'Fire Aura', desc: lv => (lv ? 'Bigger, hotter aura' : 'Burn every enemy near you'), max: 5, apply: p => { p.aura += 1; } },
  { id: 'crit', icon: '🍀', name: 'Lucky Hits', desc: '+10% critical hit chance', max: 4, apply: p => { p.crit += 0.1; } },
  { id: 'speed', icon: '👟', name: 'Swift Boots', desc: '+12% move speed', max: 3, apply: p => { p.speed *= 1.12; } },
  { id: 'heart', icon: '❤️', name: 'Big Heart', desc: '+25 max HP & full heal', apply: p => { p.maxHp += 25; p.hp = p.maxHp; } },
  { id: 'magnet', icon: '🧲', name: 'Magnet', desc: '+50% pickup range', max: 4, apply: p => { p.magnet *= 1.5; } },
  { id: 'regen', icon: '🌿', name: 'Regeneration', desc: 'Heal +1 HP per second', max: 5, apply: p => { p.regen += 1; } },
];

// ---------- Enemy types ----------
const ENEMY_TYPES = {
  basic: { r: 13, hp: 10, speed: 85, color: '#ff4d6d', xp: 1, dmg: 10 },
  fast: { r: 9, hp: 8, speed: 145, color: '#ffd23f', xp: 2, dmg: 8 },
  tank: { r: 24, hp: 70, speed: 55, color: '#b06bff', xp: 6, dmg: 20 },
  boss: { r: 40, hp: 500, speed: 62, color: '#ff8c42', xp: 30, dmg: 30 },
};

const PICKUP_GLOW = { heart: '#ff4d6d', magnet: '#3ad7ff', bomb: '#ffd23f', chest: '#ffd23f' };
const MAX_ENEMIES = 350;

// Background stars at two depths for a parallax effect
const stars = Array.from({ length: 140 }, () => ({
  x: Math.random() * 4000, y: Math.random() * 4000,
  depth: Math.random() < 0.6 ? 0.15 : 0.4,
  size: rand(0.6, 1.8), tw: rand(0, TAU),
}));

// ---------- Input ----------
const keys = new Set();
const stick = { active: false, id: null, ox: 0, oy: 0, x: 0, y: 0 };

window.addEventListener('keydown', e => {
  const k = e.key.toLowerCase();
  keys.add(k);
  Sfx.unlock();
  if (state === 'levelup' && ['1', '2', '3'].includes(k)) pickUpgrade(Number(k) - 1);
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
  if (state !== 'play') return;
  stick.active = true;
  stick.id = e.pointerId;
  stick.ox = stick.x = e.clientX;
  stick.oy = stick.y = e.clientY;
  canvas.setPointerCapture(e.pointerId);
});
canvas.addEventListener('pointermove', e => {
  if (stick.active && e.pointerId === stick.id) {
    stick.x = e.clientX;
    stick.y = e.clientY;
  }
});
const endStick = e => { if (e.pointerId === stick.id) stick.active = false; };
canvas.addEventListener('pointerup', endStick);
canvas.addEventListener('pointercancel', endStick);

function inputDir() {
  let x = 0, y = 0;
  if (keys.has('a') || keys.has('arrowleft')) x -= 1;
  if (keys.has('d') || keys.has('arrowright')) x += 1;
  if (keys.has('w') || keys.has('arrowup')) y -= 1;
  if (keys.has('s') || keys.has('arrowdown')) y += 1;
  if (stick.active) {
    const dx = stick.x - stick.ox, dy = stick.y - stick.oy, d = Math.hypot(dx, dy);
    if (d > 8) {
      const m = Math.min(d, 50) / 50;
      x += (dx / d) * m;
      y += (dy / d) * m;
    }
  }
  const len = Math.hypot(x, y);
  if (len > 1) { x /= len; y /= len; }
  return { x, y };
}

// ---------- Game state ----------
let state = 'menu';
let best = loadBest();
let player, enemies, bullets, gems, pickups, particles, texts, rings, bolts, trailPts;
let time, kills, spawnTimer, shootTimer, lightTimer, auraTimer, orbAngle, nextSwarm;
let shake, hurtFlash, whiteFlash, gemMergeTimer, nextEnemyId = 0, choices = [];
const cam = { x: 0, y: 0 };

function resetWorld() {
  player = {
    x: 0, y: 0, r: 14, hp: 100, maxHp: 100, speed: 210, hurt: 0,
    level: 1, xp: 0, xpNext: 4, facing: 0,
    damage: 10, fireRate: 2, shots: 1, pierce: 0, bulletSpeed: 500, crit: 0.1,
    magnet: 100, orbs: 0, lightning: 0, aura: 0, regen: 0, taken: {},
  };
  enemies = [];
  bullets = [];
  gems = [];
  pickups = [];
  particles = [];
  texts = [];
  rings = [];
  bolts = [];
  trailPts = [];
  time = 0;
  kills = 0;
  spawnTimer = 0;
  shootTimer = 0;
  lightTimer = 1;
  auraTimer = 0;
  orbAngle = 0;
  nextSwarm = 60;
  shake = 0;
  hurtFlash = 0;
  whiteFlash = 0;
  gemMergeTimer = 1;
  cam.x = cam.y = 0;
}

function startGame() {
  resetWorld();
  stick.active = false;
  state = 'play';
  showScreen(null);
  updateInventory();
}

function togglePause() {
  state = state === 'play' ? 'paused' : 'play';
  showScreen(state === 'paused' ? 'paused' : null);
}

function toggleMute() {
  Sfx.toggle();
  $('mute-btn').innerHTML = Icons.sound(!Sfx.muted);
}

function gameOver() {
  state = 'over';
  Sfx.play('death');
  const survived = Math.floor(time);
  const isBest = survived > best;
  if (isBest) { best = survived; saveBest(best); }
  $('over-stats').textContent = `You survived ${fmtTime(survived)} · Level ${player.level} · ${kills} kills`;
  $('over-best').textContent = isBest ? '🏆 New best time!' : `Best time: ${fmtTime(best)}`;
  setTimeout(() => { if (state === 'over') showScreen('over'); }, 900);
}

function showScreen(id) {
  for (const el of document.querySelectorAll('.screen')) el.classList.toggle('show', el.id === id);
  $('hud').classList.toggle('hidden', state === 'menu' || (state === 'over' && id === 'over'));
  $('menu-best').textContent = fmtTime(best);
}

let bannerTimeout;
function showBanner(text) {
  const el = $('banner');
  el.textContent = text;
  el.classList.add('show');
  clearTimeout(bannerTimeout);
  bannerTimeout = setTimeout(() => el.classList.remove('show'), 1600);
}

// ---------- Leveling ----------
function gainXp(v) {
  player.xp += v;
  if (state === 'play' && player.xp >= player.xpNext) levelUp();
}

function levelUp() {
  player.xp -= player.xpNext;
  player.level++;
  player.xpNext = Math.floor(4 + player.level * 2.5 + player.level * player.level * 0.15);
  Sfx.play('levelup');
  openUpgradeMenu('Level up!');
}

function openUpgradeMenu(title) {
  state = 'levelup';
  $('levelup-title').textContent = title;
  const pool = UPGRADES.filter(u => !u.max || (player.taken[u.id] || 0) < u.max);
  choices = shuffle(pool).slice(0, 3);
  const cards = $('cards');
  cards.innerHTML = '';
  choices.forEach((u, i) => {
    const lv = player.taken[u.id] || 0;
    const desc = typeof u.desc === 'function' ? u.desc(lv) : u.desc;
    const tag = lv ? `Lv ${lv} → ${lv + 1}` : 'NEW!';
    const btn = document.createElement('button');
    btn.className = 'card';
    btn.style.animationDelay = `${i * 0.07}s`;
    btn.innerHTML = `<span class="icon">${u.icon}</span>
      <span class="text"><span class="tag${lv ? '' : ' new'}">${tag}</span><span class="name">${u.name}</span><span class="desc">${desc}</span></span>
      <span class="key">[${i + 1}]</span>`;
    btn.addEventListener('click', () => pickUpgrade(i));
    cards.appendChild(btn);
  });
  showScreen('levelup');
}

function pickUpgrade(i) {
  const u = choices[i];
  if (!u || state !== 'levelup') return;
  u.apply(player);
  player.taken[u.id] = (player.taken[u.id] || 0) + 1;
  updateInventory();
  state = 'play';
  showScreen(null);

  // Shockwave: push nearby enemies away so you get a breather
  rings.push({ x: player.x, y: player.y, r: 10, max: 180, life: 0.5, maxLife: 0.5, color: '#8cf3ff', width: 6 });
  for (const e of enemies) {
    const dx = e.x - player.x, dy = e.y - player.y, d = Math.hypot(dx, dy) || 1;
    if (d < 180 && e.type !== 'boss') { e.x += (dx / d) * 70; e.y += (dy / d) * 70; }
  }
  if (player.xp >= player.xpNext) levelUp();
}

function updateInventory() {
  $('inv').innerHTML = UPGRADES.filter(u => player.taken[u.id])
    .map(u => `<span title="${u.name}">${u.icon}<b>${player.taken[u.id]}</b></span>`).join('');
}

// ---------- Spawning ----------
function makeEnemy(typeName, x, y) {
  const t = ENEMY_TYPES[typeName];
  const minutes = time / 60;
  const hp = t.hp * (1 + minutes * (typeName === 'boss' ? 0.8 : 0.4) + minutes * minutes * 0.06);
  const e = {
    id: nextEnemyId++, type: typeName, x, y, r: t.r, hp, maxHp: hp, speed: t.speed * (1 + minutes * 0.07),
    color: t.color, xp: t.xp, dmg: t.dmg * (1 + minutes * 0.1), flash: 0, orbCd: 0, auraCd: 0,
    dead: false, age: 0, seed: Math.random() * TAU,
  };
  enemies.push(e);
  return e;
}

function spawnEnemy() {
  const a = Math.random() * TAU;
  const dist = Math.hypot(W, H) / 2 + 40;
  const minutes = time / 60;
  const roll = Math.random();
  let type = 'basic';
  if (minutes > 2 && roll < 0.12) type = 'tank';
  else if (minutes > 0.75 && roll < 0.35) type = 'fast';
  makeEnemy(type, player.x + Math.cos(a) * dist, player.y + Math.sin(a) * dist);
}

function spawnSwarm() {
  const count = Math.min(16 + Math.floor(time / 60) * 6, Math.max(0, MAX_ENEMIES - enemies.length));
  const dist = Math.hypot(W, H) / 2 + 20;
  for (let i = 0; i < count; i++) {
    const a = (i / count) * TAU;
    makeEnemy('basic', player.x + Math.cos(a) * dist, player.y + Math.sin(a) * dist).speed *= 1.3;
  }
  const a = Math.random() * TAU;
  makeEnemy('boss', player.x + Math.cos(a) * (dist + 40), player.y + Math.sin(a) * (dist + 40));
  showBanner('BOSS + SWARM!');
  Sfx.play('warn');
  shake = 10;
}

// ---------- Spatial grid ----------
// Enemies are sorted into square buckets each frame, so "what's near this point?"
// only looks at a few buckets instead of every enemy on the map.
const BUCKET = 64;
let buckets = new Map();
const bucketKey = (bx, by) => (bx + 50000) * 100000 + (by + 50000);

function buildGrid() {
  buckets = new Map();
  for (const e of enemies) {
    const k = bucketKey(Math.floor(e.x / BUCKET), Math.floor(e.y / BUCKET));
    const b = buckets.get(k);
    if (b) b.push(e);
    else buckets.set(k, [e]);
  }
}

function nearby(x, y, r) {
  const out = [];
  const x0 = Math.floor((x - r) / BUCKET), x1 = Math.floor((x + r) / BUCKET);
  const y0 = Math.floor((y - r) / BUCKET), y1 = Math.floor((y + r) / BUCKET);
  for (let bx = x0; bx <= x1; bx++) {
    for (let by = y0; by <= y1; by++) {
      const b = buckets.get(bucketKey(bx, by));
      if (b) for (const e of b) out.push(e);
    }
  }
  return out;
}

// ---------- Combat ----------
function burst(x, y, color, n, speed = 220) {
  for (let i = 0; i < n; i++) {
    const a = Math.random() * TAU, s = rand(speed * 0.25, speed);
    particles.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: rand(0.3, 0.7), size: rand(2, 4), color });
  }
}

function hurtEnemy(e, baseDmg, kx = 0, ky = 0) {
  if (e.dead) return;
  const crit = Math.random() < player.crit;
  const dmg = crit ? baseDmg * 2 : baseDmg;
  e.hp -= dmg;
  e.flash = 0.08;
  if (e.type !== 'boss') { e.x += kx; e.y += ky; }
  texts.push({ x: e.x + rand(-8, 8), y: e.y - e.r, text: String(Math.round(dmg)), life: 0.6, crit });
  Sfx.play('hit');
  if (e.hp <= 0) killEnemy(e);
}

function killEnemy(e) {
  e.dead = true;
  kills++;
  burst(e.x, e.y, e.color, e.type === 'boss' ? 60 : 12, e.type === 'boss' ? 400 : 220);
  rings.push({ x: e.x, y: e.y, r: e.r * 0.5, max: e.r * 2.2, life: 0.3, maxLife: 0.3, color: e.color, width: 3 });
  Sfx.play('pop');

  if (e.type === 'boss') {
    for (let i = 0; i < 12; i++) gems.push({ x: e.x + rand(-40, 40), y: e.y + rand(-40, 40), v: 3, seed: rand(0, TAU) });
    pickups.push({ x: e.x, y: e.y, kind: 'chest', seed: 0 });
    shake = 14;
    Sfx.play('boom');
    return;
  }
  gems.push({ x: e.x, y: e.y, v: e.xp, seed: rand(0, TAU) });
  const luck = e.type === 'tank' ? 3 : 1;
  const r = Math.random();
  if (r < 0.012 * luck) pickups.push({ x: e.x, y: e.y, kind: 'heart', seed: rand(0, TAU) });
  else if (r < 0.018 * luck) pickups.push({ x: e.x, y: e.y, kind: 'magnet', seed: rand(0, TAU) });
  else if (r < 0.023 * luck) pickups.push({ x: e.x, y: e.y, kind: 'bomb', seed: rand(0, TAU) });
}

function collectPickup(pk) {
  pk.taken = true;
  if (pk.kind === 'heart') {
    player.hp = Math.min(player.maxHp, player.hp + 30);
    texts.push({ x: player.x, y: player.y - 24, text: '+30 HP', life: 0.9, heal: true });
    burst(player.x, player.y, '#ff4d6d', 14);
    Sfx.play('pickup');
  } else if (pk.kind === 'magnet') {
    for (const g of gems) g.pulled = true;
    rings.push({ x: player.x, y: player.y, r: 10, max: Math.max(W, H), life: 0.6, maxLife: 0.6, color: '#3ad7ff', width: 4 });
    Sfx.play('pickup');
  } else if (pk.kind === 'bomb') {
    whiteFlash = 1;
    shake = 16;
    Sfx.play('boom');
    rings.push({ x: player.x, y: player.y, r: 10, max: Math.max(W, H), life: 0.5, maxLife: 0.5, color: '#ffd23f', width: 10 });
    for (const e of enemies) {
      if (Math.hypot(e.x - player.x, e.y - player.y) < Math.max(W, H)) {
        hurtEnemy(e, e.type === 'boss' ? e.maxHp * 0.2 : e.hp + 1);
      }
    }
  } else if (pk.kind === 'chest') {
    burst(pk.x, pk.y, '#ffd23f', 40, 320);
    Sfx.play('chest');
    openUpgradeMenu('🎁 Treasure!');
  }
}

function nearestEnemy(range) {
  let bestE = null, bestD = range * range;
  for (const e of enemies) {
    const d = (e.x - player.x) ** 2 + (e.y - player.y) ** 2;
    if (d < bestD) { bestD = d; bestE = e; }
  }
  return bestE;
}

function auraRadius() { return 55 + player.aura * 18; }

function lightningPath(x, y) {
  const pts = [];
  let px = x + rand(-60, 60), py = y - 320;
  for (let i = 0; i <= 8; i++) {
    const t = i / 8;
    pts.push({ x: px + (x - px) * t + (i && i < 8 ? rand(-18, 18) : 0), y: py + (y - py) * t });
  }
  return pts;
}

// ---------- Update ----------
function update(dt) {
  time += dt;

  // Player movement & regen
  const dir = inputDir();
  player.x += dir.x * player.speed * dt;
  player.y += dir.y * player.speed * dt;
  if (dir.x || dir.y) player.facing = Math.atan2(dir.y, dir.x);
  player.hurt = Math.max(0, player.hurt - dt);
  player.hp = Math.min(player.maxHp, player.hp + player.regen * dt);
  trailPts.unshift({ x: player.x, y: player.y });
  if (trailPts.length > 10) trailPts.pop();

  // Smooth camera
  const k = Math.min(1, dt * 8);
  cam.x += (player.x - cam.x) * k;
  cam.y += (player.y - cam.y) * k;

  // Spawning
  spawnTimer -= dt;
  if (spawnTimer <= 0 && enemies.length < MAX_ENEMIES) {
    // Later on, several enemies arrive at once
    const n = 1 + Math.floor(time / 120);
    for (let i = 0; i < n && enemies.length < MAX_ENEMIES; i++) spawnEnemy();
    spawnTimer = Math.max(0.1, 0.7 - time * 0.003);
  }
  if (time >= nextSwarm) {
    spawnSwarm();
    nextSwarm += 60;
  }

  // Magic bolts: auto-aim at the nearest enemy
  shootTimer -= dt;
  if (shootTimer <= 0) {
    const target = nearestEnemy(520);
    if (target) {
      shootTimer = 1 / player.fireRate;
      const base = Math.atan2(target.y - player.y, target.x - player.x);
      for (let i = 0; i < player.shots; i++) {
        const a = base + (i - (player.shots - 1) / 2) * 0.16;
        bullets.push({
          x: player.x, y: player.y,
          vx: Math.cos(a) * player.bulletSpeed, vy: Math.sin(a) * player.bulletSpeed,
          life: 1.2, pierce: player.pierce, hits: new Set(),
        });
      }
      Sfx.play('shoot');
    }
  }

  buildGrid();
  for (const b of bullets) {
    b.x += b.vx * dt;
    b.y += b.vy * dt;
    b.life -= dt;
    for (const e of nearby(b.x, b.y, 50)) {
      if (e.dead || b.hits.has(e)) continue;
      if ((e.x - b.x) ** 2 + (e.y - b.y) ** 2 < (e.r + 5) ** 2) {
        b.hits.add(e);
        const s = Math.hypot(b.vx, b.vy);
        hurtEnemy(e, player.damage, (b.vx / s) * 6, (b.vy / s) * 6);
        burst(b.x, b.y, '#e8fdff', 3, 120);
        if (b.pierce-- <= 0) { b.life = 0; break; }
      }
    }
  }
  bullets = bullets.filter(b => b.life > 0);

  // Orbiting blades
  orbAngle += dt * 3.2;
  for (let i = 0; i < player.orbs; i++) {
    const a = orbAngle + (i / player.orbs) * TAU;
    const ox = player.x + Math.cos(a) * 70, oy = player.y + Math.sin(a) * 70;
    for (const e of nearby(ox, oy, 50)) {
      if (e.dead || e.orbCd > 0) continue;
      if ((e.x - ox) ** 2 + (e.y - oy) ** 2 < (e.r + 10) ** 2) {
        e.orbCd = 0.35;
        const dx = e.x - player.x, dy = e.y - player.y, d = Math.hypot(dx, dy) || 1;
        hurtEnemy(e, player.damage * 0.7, (dx / d) * 10, (dy / d) * 10);
      }
    }
  }

  // Lightning: strikes random enemies on screen
  if (player.lightning > 0) {
    lightTimer -= dt;
    if (lightTimer <= 0) {
      lightTimer = 1.3;
      const visible = enemies.filter(e => !e.dead && Math.abs(e.x - player.x) < W / 2 && Math.abs(e.y - player.y) < H / 2);
      for (const e of shuffle(visible).slice(0, player.lightning)) {
        bolts.push({ pts: lightningPath(e.x, e.y), life: 0.18 });
        rings.push({ x: e.x, y: e.y, r: 4, max: 34, life: 0.25, maxLife: 0.25, color: '#c7f0ff', width: 3 });
        hurtEnemy(e, player.damage * 2.2);
      }
      if (visible.length) Sfx.play('zap');
    }
  }

  // Fire aura: burns everything close to you
  if (player.aura > 0) {
    auraTimer -= dt;
    if (auraTimer <= 0) {
      auraTimer = 0.4;
      const r = auraRadius();
      for (const e of nearby(player.x, player.y, r + 40)) {
        if (!e.dead && (e.x - player.x) ** 2 + (e.y - player.y) ** 2 < (r + e.r) ** 2) {
          hurtEnemy(e, player.damage * (0.3 + player.aura * 0.12));
          if (Math.random() < 0.5) burst(e.x, e.y, '#ff8c42', 2, 80);
        }
      }
    }
  }

  // Enemies: chase, separate, touch damage
  for (const e of enemies) {
    e.age += dt;
    e.flash = Math.max(0, e.flash - dt);
    e.orbCd = Math.max(0, e.orbCd - dt);
    const dx = player.x - e.x, dy = player.y - e.y, d = Math.hypot(dx, dy) || 1;
    e.x += (dx / d) * e.speed * dt;
    e.y += (dy / d) * e.speed * dt;
    if (d < e.r + player.r && player.hurt <= 0 && !e.dead) {
      player.hp -= e.dmg;
      player.hurt = 0.5;
      shake = 8;
      hurtFlash = 1;
      burst(player.x, player.y, '#3ad7ff', 8);
      Sfx.play('hurt');
    }
  }
  for (const a of enemies) {
    for (const b of nearby(a.x, a.y, a.r + 40)) {
      if (b.id <= a.id) continue; // handle each pair once
      const dx = b.x - a.x, dy = b.y - a.y, min = a.r + b.r;
      const d2 = dx * dx + dy * dy;
      if (d2 < min * min && d2 > 0.01) {
        const d = Math.sqrt(d2), push = (min - d) / 2;
        const nx = dx / d, ny = dy / d;
        const wa = a.type === 'boss' ? 0.1 : 1, wb = b.type === 'boss' ? 0.1 : 1;
        a.x -= nx * push * wa; a.y -= ny * push * wa;
        b.x += nx * push * wb; b.y += ny * push * wb;
      }
    }
  }
  enemies = enemies.filter(e => !e.dead);

  // XP gems
  for (const g of gems) {
    const dx = player.x - g.x, dy = player.y - g.y, d = Math.hypot(dx, dy) || 1;
    if (g.pulled || d < player.magnet) {
      const pull = (g.pulled ? 700 : 420) * dt;
      g.x += (dx / d) * Math.min(pull, d);
      g.y += (dy / d) * Math.min(pull, d);
    }
    if (d < player.r + 8) {
      g.taken = true;
      Sfx.play('gem');
      gainXp(g.v);
    }
  }
  gems = gems.filter(g => !g.taken);

  gemMergeTimer -= dt;
  if (gemMergeTimer <= 0) {
    gemMergeTimer = 1;
    // Normally only off-screen gems merge; if lots are lying around, anything out of reach does
    const far = gems.length > 150 ? player.magnet : Math.max(W, H);
    const faraway = gems.filter(g => !g.pulled && Math.hypot(g.x - player.x, g.y - player.y) > far);
    if (faraway.length > 15) {
      const keep = faraway[0];
      for (const g of faraway) g.taken = true;
      gems = gems.filter(g => !g.taken);
      gems.push({ x: keep.x, y: keep.y, v: faraway.reduce((sum, g) => sum + g.v, 0), seed: keep.seed });
    }
  }

  // Pickups
  for (const pk of pickups) {
    if (Math.hypot(player.x - pk.x, player.y - pk.y) < player.r + 16) collectPickup(pk);
  }
  pickups = pickups.filter(pk => !pk.taken);

  // Effects
  for (const p of particles) {
    p.x += p.vx * dt;
    p.y += p.vy * dt;
    p.vx *= 0.92;
    p.vy *= 0.92;
    p.life -= dt;
  }
  particles = particles.filter(p => p.life > 0);
  for (const t of texts) { t.y -= 40 * dt; t.life -= dt; }
  texts = texts.filter(t => t.life > 0);
  for (const r of rings) { r.life -= dt; r.r += (r.max - r.r) * Math.min(1, dt * 10); }
  rings = rings.filter(r => r.life > 0);
  for (const b of bolts) b.life -= dt;
  bolts = bolts.filter(b => b.life > 0);
  shake = Math.max(0, shake - dt * 30);
  hurtFlash = Math.max(0, hurtFlash - dt * 3);
  whiteFlash = Math.max(0, whiteFlash - dt * 3);

  if (player.hp <= 0) {
    player.hp = 0;
    burst(player.x, player.y, '#3ad7ff', 60, 400);
    rings.push({ x: player.x, y: player.y, r: 10, max: 200, life: 0.6, maxLife: 0.6, color: '#3ad7ff', width: 6 });
    gameOver();
  }
}

// Death effects keep animating on the game over screen
function updateEffects(dt) {
  for (const p of particles) { p.x += p.vx * dt; p.y += p.vy * dt; p.vx *= 0.92; p.vy *= 0.92; p.life -= dt; }
  particles = particles.filter(p => p.life > 0);
  for (const r of rings) { r.life -= dt; r.r += (r.max - r.r) * Math.min(1, dt * 10); }
  rings = rings.filter(r => r.life > 0);
  shake = Math.max(0, shake - dt * 30);
}

// ---------- Drawing ----------
function circle(x, y, r, color) {
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.arc(x, y, r, 0, TAU);
  ctx.fill();
}

function drawBackground(camX, camY) {
  ctx.fillStyle = '#0b0d17';
  ctx.fillRect(0, 0, W, H);

  for (const s of stars) {
    const x = (((s.x - camX * s.depth) % W) + W) % W;
    const y = (((s.y - camY * s.depth) % H) + H) % H;
    ctx.globalAlpha = 0.35 + 0.35 * Math.sin(time * 2 + s.tw);
    circle(x, y, s.size, s.depth > 0.3 ? '#cfe0ff' : '#7f8fc4');
  }
  ctx.globalAlpha = 1;

  const g = 64;
  ctx.strokeStyle = 'rgba(120, 140, 255, 0.06)';
  ctx.lineWidth = 1;
  ctx.beginPath();
  for (let x = -(((camX % g) + g) % g); x < W; x += g) { ctx.moveTo(x, 0); ctx.lineTo(x, H); }
  for (let y = -(((camY % g) + g) % g); y < H; y += g) { ctx.moveTo(0, y); ctx.lineTo(W, y); }
  ctx.stroke();
}

function drawCrown(x, y, w) {
  const h = w * 0.7;
  ctx.fillStyle = '#ffd23f';
  ctx.strokeStyle = '#b8860b';
  ctx.lineWidth = 2;
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

function drawPickup(kind, x, y) {
  ctx.save();
  ctx.translate(x, y);
  if (kind === 'heart') {
    ctx.fillStyle = '#ff4d6d';
    ctx.beginPath();
    ctx.moveTo(0, 9);
    ctx.bezierCurveTo(-14, -1, -9, -13, 0, -5);
    ctx.bezierCurveTo(9, -13, 14, -1, 0, 9);
    ctx.fill();
    circle(-4, -5, 2.5, 'rgba(255, 255, 255, 0.6)');
  } else if (kind === 'magnet') {
    ctx.lineWidth = 6;
    ctx.strokeStyle = '#ff4d6d';
    ctx.beginPath();
    ctx.arc(0, 0, 8, Math.PI, 0, true);
    ctx.stroke();
    ctx.fillStyle = '#e8ecff';
    ctx.fillRect(-11, -8, 6, 6);
    ctx.fillRect(5, -8, 6, 6);
  } else if (kind === 'bomb') {
    circle(0, 3, 10, '#2a2f45');
    circle(-3, 0, 3, 'rgba(255, 255, 255, 0.35)');
    ctx.strokeStyle = '#c9a36b';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.moveTo(4, -6);
    ctx.quadraticCurveTo(8, -12, 12, -10);
    ctx.stroke();
    circle(12, -10, 3 + Math.sin(time * 20), '#ffd23f');
  } else if (kind === 'chest') {
    ctx.fillStyle = '#8b5a2b';
    ctx.fillRect(-14, -6, 28, 18);
    ctx.fillStyle = '#a86b33';
    ctx.fillRect(-14, -12, 28, 8);
    ctx.fillStyle = '#ffd23f';
    ctx.fillRect(-14, -5, 28, 3);
    ctx.fillRect(-3, -7, 6, 8);
  }
  ctx.restore();
}

function drawEnemy(e) {
  const born = Math.min(1, e.age * 4);
  const wob = Math.sin(time * 9 + e.seed) * 0.09;
  ctx.save();
  ctx.translate(e.x, e.y);
  ctx.scale(born * (1 - wob), born * (1 + wob));
  circle(0, 0, e.r + 5, e.color + '26');
  circle(0, 0, e.r, e.flash > 0 ? '#ffffff' : e.color);
  circle(-e.r * 0.3, -e.r * 0.35, e.r * 0.28, 'rgba(255, 255, 255, 0.25)');
  const dx = player.x - e.x, dy = player.y - e.y, d = Math.hypot(dx, dy) || 1;
  const lx = (dx / d) * e.r * 0.25, ly = (dy / d) * e.r * 0.25;
  const eo = e.r * 0.35, er = Math.max(2, e.r * 0.18);
  circle(-eo + lx, -e.r * 0.1 + ly, er * 1.5, '#fff');
  circle(eo + lx, -e.r * 0.1 + ly, er * 1.5, '#fff');
  circle(-eo + lx * 1.3, -e.r * 0.1 + ly * 1.3, er, '#0b0d17');
  circle(eo + lx * 1.3, -e.r * 0.1 + ly * 1.3, er, '#0b0d17');
  ctx.restore();
  if (e.type === 'boss') {
    drawCrown(e.x, e.y - e.r - 12 + Math.sin(time * 4) * 3, 30);
  } else if (e.hp < e.maxHp && e.r > 20) {
    ctx.fillStyle = 'rgba(0, 0, 0, 0.5)';
    ctx.fillRect(e.x - e.r, e.y + e.r + 6, e.r * 2, 4);
    ctx.fillStyle = e.color;
    ctx.fillRect(e.x - e.r, e.y + e.r + 6, e.r * 2 * (e.hp / e.maxHp), 4);
  }
}

function draw() {
  const camX = cam.x - W / 2 + rand(-shake, shake);
  const camY = cam.y - H / 2 + rand(-shake, shake);
  drawBackground(camX, camY);

  ctx.save();
  ctx.translate(-camX, -camY);

  // Fire aura (under everything)
  if (player.aura > 0 && state !== 'over') {
    const r = auraRadius() * (1 + Math.sin(time * 6) * 0.04);
    const grad = ctx.createRadialGradient(player.x, player.y, r * 0.2, player.x, player.y, r);
    grad.addColorStop(0, 'rgba(255, 140, 66, 0)');
    grad.addColorStop(0.7, 'rgba(255, 140, 66, 0.12)');
    grad.addColorStop(1, 'rgba(255, 90, 40, 0.35)');
    circle(player.x, player.y, r, grad);
  }

  // Pickups
  for (const pk of pickups) {
    const bob = Math.sin(time * 4 + pk.seed) * 4;
    circle(pk.x, pk.y + bob, 20 + Math.sin(time * 6) * 2, PICKUP_GLOW[pk.kind] + '33');
    drawPickup(pk.kind, pk.x, pk.y + bob);
  }

  // Glowing things use additive blending
  ctx.globalCompositeOperation = 'lighter';
  for (const gm of gems) {
    const big = gm.v >= 10, mid = gm.v > 2;
    const s = big ? 10 : mid ? 7 : 5;
    const y = gm.y + Math.sin(time * 5 + gm.seed) * 2;
    const spin = Math.cos(time * 4 + gm.seed);
    circle(gm.x, y, s * 2.2, big ? 'rgba(255, 93, 115, 0.15)' : mid ? 'rgba(140, 255, 176, 0.12)' : 'rgba(58, 215, 255, 0.12)');
    ctx.fillStyle = big ? '#ff5d73' : mid ? '#8cffb0' : '#3ad7ff';
    ctx.beginPath();
    ctx.moveTo(gm.x, y - s);
    ctx.lineTo(gm.x + s * spin, y);
    ctx.lineTo(gm.x, y + s);
    ctx.lineTo(gm.x - s * spin, y);
    ctx.fill();
  }
  ctx.globalCompositeOperation = 'source-over';

  for (const e of enemies) drawEnemy(e);

  ctx.globalCompositeOperation = 'lighter';
  // Bullets with streaks
  ctx.lineCap = 'round';
  for (const b of bullets) {
    ctx.strokeStyle = 'rgba(140, 243, 255, 0.35)';
    ctx.lineWidth = 6;
    ctx.beginPath();
    ctx.moveTo(b.x - b.vx * 0.04, b.y - b.vy * 0.04);
    ctx.lineTo(b.x, b.y);
    ctx.stroke();
    circle(b.x, b.y, 8, 'rgba(140, 243, 255, 0.25)');
    circle(b.x, b.y, 4, '#e8fdff');
  }

  // Orbiting blades with a short motion trail
  for (let i = 0; i < player.orbs; i++) {
    for (let t = 0; t < 4; t++) {
      const a = orbAngle - t * 0.12 + (i / player.orbs) * TAU;
      const ox = player.x + Math.cos(a) * 70, oy = player.y + Math.sin(a) * 70;
      circle(ox, oy, 9 - t * 1.6, `rgba(214, 179, 255, ${0.8 - t * 0.2})`);
    }
    const a = orbAngle + (i / player.orbs) * TAU;
    circle(player.x + Math.cos(a) * 70, player.y + Math.sin(a) * 70, 16, 'rgba(176, 107, 255, 0.2)');
  }

  // Lightning bolts
  for (const b of bolts) {
    ctx.globalAlpha = b.life / 0.18;
    for (const [w, c] of [[8, 'rgba(120, 200, 255, 0.35)'], [2.5, '#f0fbff']]) {
      ctx.strokeStyle = c;
      ctx.lineWidth = w;
      ctx.beginPath();
      b.pts.forEach((p, i) => (i ? ctx.lineTo(p.x, p.y) : ctx.moveTo(p.x, p.y)));
      ctx.stroke();
    }
  }
  ctx.globalAlpha = 1;

  // Player with an afterimage trail
  if (state !== 'over') {
    for (let i = trailPts.length - 1; i > 0; i -= 2) {
      circle(trailPts[i].x, trailPts[i].y, player.r * (1 - i / 14), `rgba(58, 215, 255, ${0.12 - i * 0.01})`);
    }
    const blink = player.hurt > 0 && Math.floor(player.hurt * 20) % 2 === 0;
    if (!blink) {
      const pulse = 1 + Math.sin(time * 5) * 0.08;
      circle(player.x, player.y, (player.r + 12) * pulse, 'rgba(58, 215, 255, 0.15)');
      circle(player.x, player.y, player.r, '#3ad7ff');
      circle(player.x, player.y, player.r * 0.55, '#e8fdff');
    }
  }

  // Particles & rings
  for (const p of particles) {
    ctx.globalAlpha = Math.min(1, p.life * 2);
    circle(p.x, p.y, p.size, p.color);
  }
  for (const r of rings) {
    ctx.globalAlpha = r.life / r.maxLife;
    ctx.strokeStyle = r.color;
    ctx.lineWidth = r.width * (r.life / r.maxLife);
    ctx.beginPath();
    ctx.arc(r.x, r.y, r.r, 0, TAU);
    ctx.stroke();
  }
  ctx.globalAlpha = 1;
  ctx.globalCompositeOperation = 'source-over';

  // Damage numbers pop in, then float up
  ctx.textAlign = 'center';
  for (const t of texts) {
    const pop = 1 + Math.max(0, t.life - 0.45) * 5;
    const size = (t.crit ? 19 : t.heal ? 16 : 13) * pop;
    ctx.globalAlpha = Math.min(1, t.life * 3);
    ctx.font = `900 ${size}px system-ui, sans-serif`;
    ctx.lineWidth = 3;
    ctx.strokeStyle = 'rgba(0, 0, 0, 0.6)';
    ctx.strokeText(t.text, t.x, t.y);
    ctx.fillStyle = t.crit ? '#ffd23f' : t.heal ? '#8cffb0' : '#fff';
    ctx.fillText(t.text, t.x, t.y);
  }
  ctx.globalAlpha = 1;
  ctx.restore();

  // Screen effects: hurt / low-health vignette, bomb flash
  const low = player.hp / player.maxHp < 0.3 && state === 'play' ? 0.35 + Math.sin(time * 6) * 0.15 : 0;
  const v = Math.max(hurtFlash * 0.6, low);
  if (v > 0) {
    const grad = ctx.createRadialGradient(W / 2, H / 2, Math.min(W, H) * 0.3, W / 2, H / 2, Math.max(W, H) * 0.75);
    grad.addColorStop(0, 'rgba(255, 30, 60, 0)');
    grad.addColorStop(1, `rgba(255, 30, 60, ${v})`);
    ctx.fillStyle = grad;
    ctx.fillRect(0, 0, W, H);
  }
  if (whiteFlash > 0) {
    ctx.fillStyle = `rgba(255, 250, 220, ${whiteFlash * 0.7})`;
    ctx.fillRect(0, 0, W, H);
  }

  // Touch joystick
  if (stick.active && state === 'play') {
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.25)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(stick.ox, stick.oy, 50, 0, TAU);
    ctx.stroke();
    const dx = stick.x - stick.ox, dy = stick.y - stick.oy, d = Math.hypot(dx, dy);
    const m = d > 50 ? 50 / d : 1;
    circle(stick.ox + dx * m, stick.oy + dy * m, 20, 'rgba(255, 255, 255, 0.3)');
  }
}

function updateHud() {
  $('hp-fill').style.width = `${(player.hp / player.maxHp) * 100}%`;
  $('hp-text').textContent = `${Math.ceil(player.hp)} / ${player.maxHp}`;
  $('xp-fill').style.width = `${Math.min(1, player.xp / player.xpNext) * 100}%`;
  $('lvl-text').textContent = `Level ${player.level}`;
  $('time-text').textContent = fmtTime(time);
  $('kills-text').textContent = `${kills} kills`;
  const boss = enemies.find(e => e.type === 'boss');
  $('boss').classList.toggle('hidden', !boss);
  if (boss) $('boss-fill').style.width = `${Math.max(0, boss.hp / boss.maxHp) * 100}%`;
}

// ---------- Main loop ----------
let last = performance.now();
function frame(now) {
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  if (state === 'play') update(dt);
  else if (state === 'over') updateEffects(dt);
  if (state === 'menu') {
    time += dt;
    cam.x += dt * 30;
    drawBackground(cam.x, cam.y);
  } else if (state === 'play' || (state === 'over' && !$('over').classList.contains('show'))) {
    // Behind the pause / level-up / game over screens the last frame stays frozen
    draw();
    updateHud();
  }
  requestAnimationFrame(frame);
}

$('play-btn').addEventListener('click', () => { if (state === 'menu') startGame(); });
$('again-btn').addEventListener('click', () => { if (state === 'over') startGame(); });
$('resume-btn').addEventListener('click', () => { if (state === 'paused') togglePause(); });
$('mute-btn').addEventListener('click', toggleMute);
$('mute-btn').innerHTML = Icons.sound(!Sfx.muted);
$('pause-btn').innerHTML = Icons.pause;
$('pause-btn').addEventListener('click', () => { if (state === 'play') togglePause(); });

resetWorld();
showScreen('menu');
requestAnimationFrame(frame);
