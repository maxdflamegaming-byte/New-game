'use strict';

// Progress between games: coins, the Locker (skins + trail effects), achievements,
// lifetime stats, and the menu screens that show them. Loaded after game.js.

function loadJSON(key, fallback) {
  try {
    const v = JSON.parse(load(key, 'null'));
    return v === null ? fallback : v;
  } catch {
    return fallback;
  }
}

// ---------- Coins ----------
let coins = Number(load('color-claim-coins', 0)) || 0;
const SKIN_PRICE = 150;

function renderCoins() {
  document.querySelectorAll('.coin-count').forEach(el => { el.textContent = coins; });
}

function addCoins(n) {
  if (n <= 0) return;
  coins += n;
  stats.coinsEarned = (stats.coinsEarned || 0) + n;
  save('color-claim-coins', coins);
  renderCoins();
}

function spend(n) {
  if (coins < n) return false;
  coins -= n;
  save('color-claim-coins', coins);
  renderCoins();
  Sfx.play('coin');
  return true;
}

// ---------- Trail effects (bought with coins) ----------
const TRAIL_FX = [
  { id: 'none', name: 'None', price: 0 },
  { id: 'sparkle', name: 'Sparkles', price: 80 },
  { id: 'bubbles', name: 'Bubbles', price: 100 },
  { id: 'hearts', name: 'Hearts', price: 120 },
  { id: 'fire', name: 'Fire', price: 150 },
  { id: 'stars', name: 'Stars', price: 200 },
  { id: 'rainbow', name: 'Rainbow', price: 250 },
];
let ownedFx = loadJSON('color-claim-owned-fx', ['none']);
myFx = ownedFx.includes(myFx) ? myFx : 'none';

// ---------- Achievements ----------
// `test(run, stats)` sees this game's numbers and lifetime stats. `progress` shows a counter.
const ACH_REWARD = 25;
const ACHIEVEMENTS = [
  { id: 'land5', name: 'Land Grab', desc: 'Claim 5% in one game', test: r => r.peak >= 5 },
  { id: 'land25', name: 'Big Shot', desc: 'Claim 25% in one game', test: r => r.peak >= 25 },
  { id: 'loop5', name: 'Huge Loop', desc: 'Claim 5% with a single loop', test: r => r.bigLoop >= 5 },
  { id: 'ko1', name: 'Snip!', desc: 'Knock out another player', test: r => r.kills >= 1 },
  { id: 'ko5', name: 'Trail Terror', desc: 'Get 5 knockouts in one game', test: r => r.kills >= 5 },
  { id: 'coldcut', name: 'Cold Cut', desc: 'Knock someone out while you have Freeze', test: r => r.freezeKO },
  { id: 'time5', name: 'Staying Alive', desc: 'Survive 5 minutes in one game', test: r => r.time >= 300 },
  { id: 'win', name: 'Conqueror', desc: 'Win a game', test: (r, s) => s.wins >= 1 },
  { id: 'timed', name: 'Beat the Clock', desc: 'Finish first in a Timed game', test: (r, s) => (s.timedWins || 0) >= 1 },
  { id: 'daily', name: 'Daily Dose', desc: 'Finish a Daily game', test: (r, s) => (s.dailies || 0) >= 1 },
  { id: 'marathon', name: 'Long Haul', desc: 'Win a Marathon game', test: (r, s) => (s.marathonWins || 0) >= 1 },
  { id: 'power10', name: 'Powered Up', desc: 'Grab 10 power-ups', test: (r, s) => (s.powerups || 0) >= 10, progress: s => [s.powerups || 0, 10] },
  { id: 'collector', name: 'Collector', desc: 'Own 5 skins', test: () => SKINS.filter(isUnlocked).length >= 5, progress: () => [SKINS.filter(isUnlocked).length, 5] },
  { id: 'regular', name: 'Regular', desc: 'Play 25 games', test: (r, s) => s.games >= 25, progress: s => [s.games, 25] },
];
let achieved = loadJSON('color-claim-achievements', {});

function runSnapshot() {
  return { peak: peakPct, kills: me ? me.kills : 0, time: playTime, bigLoop: run.bigLoop, freezeKO: run.freezeKO };
}

function checkAchievements(r) {
  const fresh = ACHIEVEMENTS.filter(a => !achieved[a.id] && a.test(r, stats));
  if (!fresh.length) return fresh;
  for (const a of fresh) achieved[a.id] = todayKey();
  save('color-claim-achievements', JSON.stringify(achieved));
  addCoins(fresh.length * ACH_REWARD);
  save('color-claim-stats', JSON.stringify(stats));
  return fresh;
}

// Called about once a second during a game, so achievements pop up the moment you earn them
function liveAchievementCheck() {
  for (const a of checkAchievements(runSnapshot())) {
    run.trophies.push(a);
    toast(`🏆 ${a.name}! +${ACH_REWARD} coins`);
    Sfx.play('trophy');
  }
}

// End of a game: update lifetime stats, pay out coins, check achievements
function finishRun(won, score) {
  stats.games++;
  stats.kills += me.kills;
  if (won) stats.wins++;
  stats.bestPct = Math.max(stats.bestPct, score);
  stats.bestKills = Math.max(stats.bestKills || 0, me.kills);
  stats.powerups = (stats.powerups || 0) + run.powerups;
  stats.timePlayed = (stats.timePlayed || 0) + playTime;
  stats.claimedTotal = (stats.claimedTotal || 0) + score;
  if (gameModeId === 'daily') stats.dailies = (stats.dailies || 0) + 1;
  if (gameModeId === 'timed' && won) stats.timedWins = (stats.timedWins || 0) + 1;
  if (gameModeId === 'marathon' && won) stats.marathonWins = (stats.marathonWins || 0) + 1;

  const earned = Math.round(score * 2) + me.kills * 5 + (won ? 50 : 0);
  addCoins(earned);
  const fresh = [...run.trophies, ...checkAchievements(runSnapshot())];
  save('color-claim-stats', JSON.stringify(stats));
  return { earned, fresh };
}

// ---------- Menu navigation ----------
function openScreen(id) {
  if (id === 'locker') buildLocker();
  if (id === 'trophies') buildTrophies();
  if (id === 'stats') buildStats();
  showScreen(id);
}
document.querySelectorAll('[data-open]').forEach(b => b.addEventListener('click', () => openScreen(b.dataset.open)));
document.querySelectorAll('[data-back]').forEach(b => b.addEventListener('click', () => showScreen('menu')));

// ---------- Locker ----------
let lockerTab = 'skins';
function refreshLocker() {
  if ($('locker').classList.contains('show')) buildLocker();
}

function skinPreview(skinId) {
  const c = document.createElement('canvas');
  c.width = c.height = 88;
  const g = c.getContext('2d');
  g.translate(44, 40);
  g.rotate(-Math.PI / 2);
  drawBody(g, { color: COLORS[myColor], dark: shade(COLORS[myColor], -0.28), skin: skinId, blink: 1, hueOff: 200 }, 46, 0);
  return c;
}

function fxPreview(fxId) {
  const c = document.createElement('canvas');
  c.width = c.height = 88;
  const g = c.getContext('2d');
  g.fillStyle = alpha(COLORS[myColor], 0.45);
  g.fillRect(8, 40, 56, 12);
  g.fillStyle = COLORS[myColor];
  g.fillRect(62, 34, 22, 22);
  if (fxId !== 'none') {
    [[16, 30, 0.9], [30, 58, 0.7], [44, 26, 1], [24, 46, 0.6], [52, 60, 0.8]].forEach(([x, y, s], k) => {
      drawFxShape(g, { kind: fxId, hue: k * 50, rot: k, life: 1, size: s }, x, y, 16);
    });
  }
  return c;
}

function buildLocker() {
  document.querySelectorAll('#locker .tab').forEach(t => t.classList.toggle('picked', t.dataset.tab === lockerTab));
  const box = $('locker-items');
  box.innerHTML = '';
  const items = lockerTab === 'skins'
    ? SKINS.map(sk => ({
      id: sk.id, name: sk.name, canvas: skinPreview(sk.id), open: isUnlocked(sk), equipped: sk.id === mySkin,
      price: SKIN_PRICE, how: sk.need && sk.need.text,
      equip: () => { mySkin = sk.id; save('color-claim-skin', sk.id); },
      buy: () => { ownedSkins.push(sk.id); save('color-claim-owned-skins', JSON.stringify(ownedSkins)); },
    }))
    : TRAIL_FX.map(fx => ({
      id: fx.id, name: fx.name, canvas: fxPreview(fx.id), open: ownedFx.includes(fx.id), equipped: fx.id === myFx,
      price: fx.price,
      equip: () => { myFx = fx.id; save('color-claim-fx', fx.id); },
      buy: () => { ownedFx.push(fx.id); save('color-claim-owned-fx', JSON.stringify(ownedFx)); },
    }));
  for (const it of items) {
    const card = document.createElement('div');
    card.className = 'item' + (it.equipped ? ' equipped' : '') + (it.open ? '' : ' locked');
    card.appendChild(it.canvas);
    card.insertAdjacentHTML('beforeend', `<b>${it.name}</b>`);
    const btn = document.createElement('button');
    btn.className = 'item-btn';
    if (it.equipped) {
      btn.textContent = 'Equipped';
      btn.disabled = true;
    } else if (it.open) {
      btn.textContent = 'Use';
      btn.addEventListener('click', () => { it.equip(); buildLocker(); });
    } else {
      btn.innerHTML = `Buy · ${it.price} <span class="coin"></span>`;
      btn.disabled = coins < it.price;
      btn.addEventListener('click', () => {
        if (!spend(it.price)) return;
        it.buy();
        it.equip();
        toast(`Unlocked ${it.name}!`);
        liveCheckCollector();
        buildLocker();
      });
    }
    card.appendChild(btn);
    if (!it.open && it.how) card.insertAdjacentHTML('beforeend', `<span class="how">or: ${it.how}</span>`);
    box.appendChild(card);
  }
}
document.querySelectorAll('#locker .tab').forEach(t => t.addEventListener('click', () => { lockerTab = t.dataset.tab; buildLocker(); }));

// Buying skins can complete the Collector achievement right away
function liveCheckCollector() {
  for (const a of checkAchievements({ peak: 0, kills: 0, time: 0, bigLoop: 0, freezeKO: false })) {
    toast(`🏆 ${a.name}! +${ACH_REWARD} coins`);
    Sfx.play('trophy');
  }
}

// ---------- Trophies ----------
function buildTrophies() {
  const got = ACHIEVEMENTS.filter(a => achieved[a.id]).length;
  $('trophy-count').textContent = `${got} / ${ACHIEVEMENTS.length} unlocked · ${ACH_REWARD} coins each`;
  $('trophy-list').innerHTML = ACHIEVEMENTS.map(a => {
    const done = !!achieved[a.id];
    let extra = '';
    if (!done && a.progress) {
      const [n, max] = a.progress(stats);
      extra = `<span class="bar"><span style="width:${Math.min(100, (n / max) * 100)}%"></span></span><span class="prog">${Math.min(n, max)} / ${max}</span>`;
    }
    return `<li class="${done ? 'done' : ''}">${Icons.trophy}<span class="t"><b>${a.name}</b><span>${a.desc}</span>${extra}</span></li>`;
  }).join('');
}

// ---------- Stats ----------
function buildStats() {
  const s = stats;
  const mins = Math.round((s.timePlayed || 0) / 60);
  const tiles = [
    ['Games played', s.games],
    ['Wins', s.wins],
    ['Win rate', s.games ? `${Math.round((s.wins / s.games) * 100)}%` : '–'],
    ['Best claim', `${s.bestPct.toFixed(1)}%`],
    ['Knockouts', s.kills],
    ['Most in one game', s.bestKills || 0],
    ['Power-ups grabbed', s.powerups || 0],
    ['Time played', mins < 60 ? `${mins} min` : `${(mins / 60).toFixed(1)} h`],
    ['Coins earned', s.coinsEarned || 0],
    ['Trophies', `${ACHIEVEMENTS.filter(a => achieved[a.id]).length} / ${ACHIEVEMENTS.length}`],
  ];
  const modes = ['classic', 'timed', 'marathon', 'daily'].map(m => [m === 'daily' ? "Today's Daily" : `${MODES[m].name} best`, `${bestFor(m).toFixed(1)}%`]);
  $('stats-grid').innerHTML = [...tiles, ...modes].map(([k, v]) => `<div class="tile"><b>${v}</b><span>${k}</span></div>`).join('');
}

// ---------- Start up ----------
allocWorld(80);
buildSwatches();
buildPickers();
renderCoins();
showScreen('menu');
requestAnimationFrame(frame);
