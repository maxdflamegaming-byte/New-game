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
const UPGRADES = [
  { id: 'damage', icon: '⚔️', name: 'Sharper Bolts', desc: '+30% damage', apply: p => { p.damage *= 1.3; } },
  { id: 'rate', icon: '⚡', name: 'Quick Cast', desc: '+25% fire rate', apply: p => { p.fireRate *= 1.25; } },
  { id: 'multi', icon: '✨', name: 'Split Shot', desc: '+1 bolt per cast', max: 5, apply: p => { p.shots += 1; } },
  { id: 'pierce', icon: '🎯', name: 'Piercing', desc: 'Bolts pass through +1 enemy', max: 4, apply: p => { p.pierce += 1; } },
  { id: 'orb', icon: '🌀', name: 'Orbiting Blade', desc: '+1 blade circles you', max: 6, apply: p => { p.orbs += 1; } },
  { id: 'speed', icon: '👟', name: 'Swift Boots', desc: '+12% move speed', max: 5, apply: p => { p.speed *= 1.12; } },
  { id: 'heart', icon: '❤️', name: 'Big Heart', desc: '+25 max HP & full heal', apply: p => { p.maxHp += 25; p.hp = p.maxHp; } },
  { id: 'magnet', icon: '🧲', name: 'Magnet', desc: '+50% pickup range', max: 4, apply: p => { p.magnet *= 1.5; } },
  { id: 'regen', icon: '🌿', name: 'Regeneration', desc: 'Heal +1 HP per second', max: 5, apply: p => { p.regen += 1; } },
];

// ---------- Enemy types ----------
const ENEMY_TYPES = {
  basic: { r: 13, hp: 10, speed: 85, color: '#ff4d6d', xp: 1, dmg: 10 },
  fast: { r: 9, hp: 8, speed: 145, color: '#ffd23f', xp: 2, dmg: 8 },
  tank: { r: 24, hp: 70, speed: 55, color: '#b06bff', xp: 6, dmg: 20 },
};

// ---------- Input ----------
const keys = new Set();
const stick = { active: false, id: null, ox: 0, oy: 0, x: 0, y: 0 };

window.addEventListener('keydown', e => {
  const k = e.key.toLowerCase();
  keys.add(k);
  if (state === 'levelup' && ['1', '2', '3'].includes(k)) pickUpgrade(Number(k) - 1);
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
let player, enemies, bullets, gems, particles, texts;
let time, kills, spawnTimer, shootTimer, orbAngle, shake, nextSwarm, choices = [];

function resetWorld() {
  player = {
    x: 0, y: 0, r: 14, hp: 100, maxHp: 100, speed: 210, hurt: 0,
    level: 1, xp: 0, xpNext: 4,
    damage: 10, fireRate: 2, shots: 1, pierce: 0, bulletSpeed: 500,
    magnet: 100, orbs: 0, regen: 0, taken: {},
  };
  enemies = [];
  bullets = [];
  gems = [];
  particles = [];
  texts = [];
  time = 0;
  kills = 0;
  spawnTimer = 0;
  shootTimer = 0;
  orbAngle = 0;
  shake = 0;
  nextSwarm = 60;
}

function startGame() {
  resetWorld();
  stick.active = false;
  state = 'play';
  showScreen(null);
}

function togglePause() {
  state = state === 'play' ? 'paused' : 'play';
  showScreen(state === 'paused' ? 'paused' : null);
}

function gameOver() {
  state = 'over';
  const survived = Math.floor(time);
  const isBest = survived > best;
  if (isBest) { best = survived; saveBest(best); }
  $('over-stats').textContent = `You survived ${fmtTime(survived)} · Level ${player.level} · ${kills} kills`;
  $('over-best').textContent = isBest ? '🏆 New best time!' : `Best time: ${fmtTime(best)}`;
  showScreen('over');
}

function showScreen(id) {
  for (const el of document.querySelectorAll('.screen')) el.classList.toggle('show', el.id === id);
  $('hud').classList.toggle('hidden', state === 'menu' || state === 'over');
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
  player.xpNext = Math.floor(4 + player.level * 2.5);
  state = 'levelup';
  const pool = UPGRADES.filter(u => !u.max || (player.taken[u.id] || 0) < u.max);
  choices = shuffle(pool).slice(0, 3);
  const cards = $('cards');
  cards.innerHTML = '';
  choices.forEach((u, i) => {
    const btn = document.createElement('button');
    btn.className = 'card';
    btn.innerHTML = `<span class="icon">${u.icon}</span>
      <span class="text"><span class="name">${u.name}</span><span class="desc">${u.desc}</span></span>
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
  state = 'play';
  showScreen(null);
  if (player.xp >= player.xpNext) levelUp();
}

// ---------- Spawning ----------
function makeEnemy(typeName, x, y) {
  const t = ENEMY_TYPES[typeName];
  const minutes = time / 60;
  const hp = t.hp * (1 + minutes * 0.4);
  enemies.push({
    x, y, r: t.r, hp, maxHp: hp, speed: t.speed * (1 + minutes * 0.05),
    color: t.color, xp: t.xp, dmg: t.dmg, flash: 0, orbCd: 0, dead: false,
  });
}

function spawnEnemy() {
  const a = Math.random() * Math.PI * 2;
  const dist = Math.hypot(W, H) / 2 + 40;
  const minutes = time / 60;
  const roll = Math.random();
  let type = 'basic';
  if (minutes > 2 && roll < 0.12) type = 'tank';
  else if (minutes > 0.75 && roll < 0.35) type = 'fast';
  makeEnemy(type, player.x + Math.cos(a) * dist, player.y + Math.sin(a) * dist);
}

function spawnSwarm() {
  const count = 16 + Math.floor(time / 60) * 6;
  const dist = Math.hypot(W, H) / 2 + 20;
  for (let i = 0; i < count; i++) {
    const a = (i / count) * Math.PI * 2;
    makeEnemy('basic', player.x + Math.cos(a) * dist, player.y + Math.sin(a) * dist);
  }
  showBanner('SWARM!');
}

// ---------- Combat ----------
function burst(x, y, color, n) {
  for (let i = 0; i < n; i++) {
    const a = Math.random() * Math.PI * 2, s = rand(60, 220);
    particles.push({ x, y, vx: Math.cos(a) * s, vy: Math.sin(a) * s, life: rand(0.3, 0.6), color });
  }
}

function hurtEnemy(e, dmg, kx = 0, ky = 0) {
  if (e.dead) return;
  e.hp -= dmg;
  e.flash = 0.08;
  e.x += kx;
  e.y += ky;
  texts.push({ x: e.x + rand(-6, 6), y: e.y - e.r, text: String(Math.round(dmg)), life: 0.5 });
  if (e.hp <= 0) {
    e.dead = true;
    kills++;
    gems.push({ x: e.x, y: e.y, v: e.xp });
    burst(e.x, e.y, e.color, 10);
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

// ---------- Update ----------
function update(dt) {
  time += dt;

  // Player movement & regen
  const dir = inputDir();
  player.x += dir.x * player.speed * dt;
  player.y += dir.y * player.speed * dt;
  player.hurt = Math.max(0, player.hurt - dt);
  player.hp = Math.min(player.maxHp, player.hp + player.regen * dt);

  // Spawning
  spawnTimer -= dt;
  if (spawnTimer <= 0 && enemies.length < 300) {
    spawnEnemy();
    spawnTimer = Math.max(0.1, 0.7 - time * 0.003);
  }
  if (time >= nextSwarm) {
    spawnSwarm();
    nextSwarm += 60;
  }

  // Auto-shoot at the nearest enemy
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
    }
  }

  // Bullets
  for (const b of bullets) {
    b.x += b.vx * dt;
    b.y += b.vy * dt;
    b.life -= dt;
    for (const e of enemies) {
      if (e.dead || b.hits.has(e)) continue;
      if ((e.x - b.x) ** 2 + (e.y - b.y) ** 2 < (e.r + 5) ** 2) {
        b.hits.add(e);
        const s = Math.hypot(b.vx, b.vy);
        hurtEnemy(e, player.damage, (b.vx / s) * 6, (b.vy / s) * 6);
        if (b.pierce-- <= 0) { b.life = 0; break; }
      }
    }
  }
  bullets = bullets.filter(b => b.life > 0);

  // Orbiting blades
  orbAngle += dt * 3.2;
  const orbR = 70;
  for (let i = 0; i < player.orbs; i++) {
    const a = orbAngle + (i / player.orbs) * Math.PI * 2;
    const ox = player.x + Math.cos(a) * orbR, oy = player.y + Math.sin(a) * orbR;
    for (const e of enemies) {
      if (e.dead || e.orbCd > 0) continue;
      if ((e.x - ox) ** 2 + (e.y - oy) ** 2 < (e.r + 10) ** 2) {
        e.orbCd = 0.35;
        const dx = e.x - player.x, dy = e.y - player.y, d = Math.hypot(dx, dy) || 1;
        hurtEnemy(e, player.damage * 0.7, (dx / d) * 10, (dy / d) * 10);
      }
    }
  }

  // Enemies: chase, separate, touch damage
  for (const e of enemies) {
    e.flash = Math.max(0, e.flash - dt);
    e.orbCd = Math.max(0, e.orbCd - dt);
    const dx = player.x - e.x, dy = player.y - e.y, d = Math.hypot(dx, dy) || 1;
    e.x += (dx / d) * e.speed * dt;
    e.y += (dy / d) * e.speed * dt;
    if (d < e.r + player.r && player.hurt <= 0 && !e.dead) {
      player.hp -= e.dmg;
      player.hurt = 0.5;
      shake = 8;
      burst(player.x, player.y, '#3ad7ff', 8);
    }
  }
  for (let i = 0; i < enemies.length; i++) {
    const a = enemies[i];
    for (let j = i + 1; j < enemies.length; j++) {
      const b = enemies[j];
      const dx = b.x - a.x, dy = b.y - a.y, min = a.r + b.r;
      const d2 = dx * dx + dy * dy;
      if (d2 < min * min && d2 > 0.01) {
        const d = Math.sqrt(d2), push = (min - d) / 2;
        const nx = dx / d, ny = dy / d;
        a.x -= nx * push; a.y -= ny * push;
        b.x += nx * push; b.y += ny * push;
      }
    }
  }
  enemies = enemies.filter(e => !e.dead);

  // XP gems
  for (const g of gems) {
    const dx = player.x - g.x, dy = player.y - g.y, d = Math.hypot(dx, dy) || 1;
    if (d < player.magnet) {
      const pull = 420 * dt;
      g.x += (dx / d) * pull;
      g.y += (dy / d) * pull;
    }
    if (d < player.r + 8) { g.taken = true; gainXp(g.v); }
  }
  gems = gems.filter(g => !g.taken);

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
  shake = Math.max(0, shake - dt * 30);

  if (player.hp <= 0) {
    player.hp = 0;
    burst(player.x, player.y, '#3ad7ff', 40);
    gameOver();
  }
}

// ---------- Drawing ----------
function circle(x, y, r, color) {
  ctx.fillStyle = color;
  ctx.beginPath();
  ctx.arc(x, y, r, 0, Math.PI * 2);
  ctx.fill();
}

function draw() {
  ctx.fillStyle = '#0b0d17';
  ctx.fillRect(0, 0, W, H);

  const camX = player.x - W / 2 + rand(-shake, shake);
  const camY = player.y - H / 2 + rand(-shake, shake);

  // Grid so movement is visible
  const g = 64;
  ctx.strokeStyle = 'rgba(120, 140, 255, 0.07)';
  ctx.lineWidth = 1;
  ctx.beginPath();
  for (let x = -(((camX % g) + g) % g); x < W; x += g) { ctx.moveTo(x, 0); ctx.lineTo(x, H); }
  for (let y = -(((camY % g) + g) % g); y < H; y += g) { ctx.moveTo(0, y); ctx.lineTo(W, y); }
  ctx.stroke();

  ctx.save();
  ctx.translate(-camX, -camY);

  // Gems
  for (const gm of gems) {
    const s = gm.v > 2 ? 7 : 5;
    circle(gm.x, gm.y, s * 2, 'rgba(58, 215, 255, 0.12)');
    ctx.fillStyle = gm.v > 2 ? '#8cffb0' : '#3ad7ff';
    ctx.beginPath();
    ctx.moveTo(gm.x, gm.y - s);
    ctx.lineTo(gm.x + s, gm.y);
    ctx.lineTo(gm.x, gm.y + s);
    ctx.lineTo(gm.x - s, gm.y);
    ctx.fill();
  }

  // Enemies (cute blobs that look at you)
  for (const e of enemies) {
    circle(e.x, e.y, e.r + 4, e.color + '22');
    circle(e.x, e.y, e.r, e.flash > 0 ? '#ffffff' : e.color);
    const dx = player.x - e.x, dy = player.y - e.y, d = Math.hypot(dx, dy) || 1;
    const lx = (dx / d) * e.r * 0.25, ly = (dy / d) * e.r * 0.25;
    const eo = e.r * 0.35, er = Math.max(2, e.r * 0.18);
    circle(e.x - eo + lx, e.y - e.r * 0.15 + ly, er, '#0b0d17');
    circle(e.x + eo + lx, e.y - e.r * 0.15 + ly, er, '#0b0d17');
    if (e.hp < e.maxHp && e.r > 20) {
      ctx.fillStyle = 'rgba(0,0,0,0.5)';
      ctx.fillRect(e.x - e.r, e.y + e.r + 5, e.r * 2, 4);
      ctx.fillStyle = e.color;
      ctx.fillRect(e.x - e.r, e.y + e.r + 5, e.r * 2 * (e.hp / e.maxHp), 4);
    }
  }

  // Bullets
  for (const b of bullets) {
    circle(b.x, b.y, 9, 'rgba(140, 243, 255, 0.2)');
    circle(b.x, b.y, 4.5, '#e8fdff');
  }

  // Orbiting blades
  for (let i = 0; i < player.orbs; i++) {
    const a = orbAngle + (i / player.orbs) * Math.PI * 2;
    const ox = player.x + Math.cos(a) * 70, oy = player.y + Math.sin(a) * 70;
    circle(ox, oy, 14, 'rgba(176, 107, 255, 0.2)');
    circle(ox, oy, 8, '#d6b3ff');
  }

  // Player
  if (state !== 'over' && !(player.hurt > 0 && Math.floor(player.hurt * 20) % 2 === 0)) {
    circle(player.x, player.y, player.r + 10, 'rgba(58, 215, 255, 0.15)');
    circle(player.x, player.y, player.r, '#3ad7ff');
    circle(player.x, player.y, player.r * 0.5, '#e8fdff');
  }

  // Particles & damage numbers
  for (const p of particles) {
    ctx.globalAlpha = Math.min(1, p.life * 2);
    circle(p.x, p.y, 3, p.color);
  }
  ctx.globalAlpha = 1;
  ctx.font = 'bold 13px system-ui, sans-serif';
  ctx.textAlign = 'center';
  for (const t of texts) {
    ctx.globalAlpha = Math.min(1, t.life * 3);
    ctx.fillStyle = '#fff';
    ctx.fillText(t.text, t.x, t.y);
  }
  ctx.globalAlpha = 1;
  ctx.restore();

  // Touch joystick
  if (stick.active && state === 'play') {
    ctx.strokeStyle = 'rgba(255, 255, 255, 0.25)';
    ctx.lineWidth = 2;
    ctx.beginPath();
    ctx.arc(stick.ox, stick.oy, 50, 0, Math.PI * 2);
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
}

// ---------- Main loop ----------
let last = performance.now();
function frame(now) {
  const dt = Math.min(0.05, (now - last) / 1000);
  last = now;
  if (state === 'play') update(dt);
  draw();
  if (state !== 'menu') updateHud();
  requestAnimationFrame(frame);
}

$('play-btn').addEventListener('click', () => { if (state === 'menu') startGame(); });
$('again-btn').addEventListener('click', () => { if (state === 'over') startGame(); });
$('resume-btn').addEventListener('click', () => { if (state === 'paused') togglePause(); });

resetWorld();
showScreen('menu');
requestAnimationFrame(frame);
