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
  { id: 'lightning', name: 'Lightning', price: 0, season: true },
  { id: 'snow', name: 'Snowflakes', price: 0, season: true },
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
  { id: 'giant', name: 'Giant Slayer', desc: 'Knock out the Giant', test: r => r.giantKO },
  { id: 'team', name: 'Team Player', desc: 'Win a Teams game', test: (r, s) => (s.teamWins || 0) >= 1 },
  { id: 'champion', name: 'Champion', desc: 'Win the Cup', test: (r, s) => (s.cups || 0) >= 1 },
  { id: 'challenger', name: 'Challenger', desc: "Beat a friend's challenge", test: (r, s) => (s.challenges || 0) >= 1 },
  { id: 'collector', name: 'Collector', desc: 'Own 5 skins', test: () => SKINS.filter(isUnlocked).length >= 5, progress: () => [SKINS.filter(isUnlocked).length, 5] },
  { id: 'regular', name: 'Regular', desc: 'Play 25 games', test: (r, s) => s.games >= 25, progress: s => [s.games, 25] },
];
let achieved = loadJSON('color-claim-achievements', {});

function runSnapshot() {
  return { peak: peakPct, kills: me ? me.kills : 0, time: playTime, bigLoop: run.bigLoop, freezeKO: run.freezeKO, giantKO: run.giantKO };
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
  if (gameModeId === 'team' && won) stats.teamWins = (stats.teamWins || 0) + 1;
  if (run.giantKO) stats.giants = (stats.giants || 0) + 1;

  const earned = Math.round((Math.round(score * 2) + me.kills * 5 + (won ? 50 : 0)) * (eventOn('double') ? 2 : 1) * gameDiff.coins);
  addCoins(earned);
  const fresh = [...run.trophies, ...checkAchievements(runSnapshot())];
  const xpGain = Math.round((score * 10 + me.kills * 30 + (won ? 150 : 0) + playTime / 2) * (eventOn('xp') ? 1.5 : 1));
  const { levelsUp, levelCoins } = addXp(xpGain);
  const missionsDone = updateMissions({
    ...runSnapshot(), powerups: run.powerups, coinsPicked: run.coinsPicked, mode: gameModeId, map: gameMapId, diff: gameDiffId, won,
  });
  const missionCoins = missionsDone.reduce((a, m) => a + m.reward, 0);
  const seasonRewards = addSeasonXp(xpGain);
  save('color-claim-stats', JSON.stringify(stats));
  return { earned, fresh, xpGain, levelsUp, levelCoins, missionsDone, missionCoins, seasonRewards };
}

// ---------- Player level ----------
// Every game gives XP. Each level needs 50 more XP than the last, and pays a coin bonus.
let xp = Number(load('color-claim-xp', 0)) || 0;

function levelInfo(total) {
  let lvl = 1, need = 100, rem = total;
  while (rem >= need) { rem -= need; lvl++; need = 100 + (lvl - 1) * 50; }
  return { lvl, into: rem, need };
}

function addXp(n) {
  const before = levelInfo(xp).lvl;
  xp += n;
  save('color-claim-xp', xp);
  const after = levelInfo(xp).lvl;
  let reward = 0;
  for (let L = before + 1; L <= after; L++) reward += 20 + L * 5;
  addCoins(reward);
  return { levelsUp: after - before, levelCoins: reward };
}

function renderLevel() {
  const lv = levelInfo(xp);
  $('menu-level').textContent = `Lv ${lv.lvl}`;
  $('menu-xp').style.width = `${(lv.into / lv.need) * 100}%`;
  $('level-badge').title = `${lv.into} / ${lv.need} XP to level ${lv.lvl + 1}`;
}

// ---------- Daily missions ----------
// Three missions a day, the same for everyone (picked from the date). Rewards pay out automatically.
const MISSION_POOL = [
  { id: 'play3', text: 'Play 3 games', goal: 3, reward: 25, add: () => 1 },
  { id: 'ko3', text: 'Knock out 3 players', goal: 3, reward: 40, add: r => r.kills },
  { id: 'power5', text: 'Grab 5 power-ups', goal: 5, reward: 30, add: r => r.powerups },
  { id: 'coins10', text: 'Pick up 10 coins on the map', goal: 10, reward: 30, add: r => r.coinsPicked },
  { id: 'claim15', text: 'Claim 15% in one game', goal: 1, reward: 40, add: r => (r.peak >= 15 ? 1 : 0) },
  { id: 'loop3', text: 'Claim 3% with a single loop', goal: 1, reward: 35, add: r => (r.bigLoop >= 3 ? 1 : 0) },
  { id: 'survive3', text: 'Survive 3 minutes in one game', goal: 1, reward: 35, add: r => (r.time >= 180 ? 1 : 0) },
  { id: 'timed', text: 'Play a Timed game', goal: 1, reward: 25, add: r => (r.mode === 'timed' ? 1 : 0) },
  { id: 'daily', text: 'Play the Daily map', goal: 1, reward: 30, add: r => (r.mode === 'daily' ? 1 : 0) },
  { id: 'round', text: 'Play a game on the Round map', goal: 1, reward: 25, add: r => (r.map === 'round' ? 1 : 0) },
  { id: 'pillars', text: 'Play a game on the Pillars map', goal: 1, reward: 25, add: r => (r.map === 'pillars' ? 1 : 0) },
  { id: 'win', text: 'Win a game', goal: 1, reward: 60, add: r => (r.won ? 1 : 0) },
  { id: 'teams', text: 'Play a Teams game', goal: 1, reward: 30, add: r => (r.mode === 'team' ? 1 : 0) },
  { id: 'cup', text: 'Play a Cup round', goal: 1, reward: 30, add: r => (r.mode === 'cup' ? 1 : 0) },
  { id: 'hard', text: 'Play a game with Hard bots', goal: 1, reward: 40, add: r => (r.diff === 'hard' ? 1 : 0) },
  { id: 'maze', text: 'Play a game on the Maze map', goal: 1, reward: 25, add: r => (r.map === 'maze' ? 1 : 0) },
];

function todaysMissions() {
  const rng = mulberry32(hashStr('color-claim-missions-' + todayKey()));
  const pool = MISSION_POOL.slice();
  const picked = [];
  while (picked.length < 3) picked.push(pool.splice(Math.floor(rng() * pool.length), 1)[0]);
  return picked;
}

let missionState = loadJSON('color-claim-missions', {});
function freshMissionState() {
  if (missionState.date !== todayKey()) missionState = { date: todayKey(), progress: {}, done: {} };
  return missionState;
}

function updateMissions(r) {
  const st = freshMissionState();
  const completed = [];
  for (const m of todaysMissions()) {
    if (st.done[m.id]) continue;
    st.progress[m.id] = Math.min(m.goal, (st.progress[m.id] || 0) + m.add(r));
    if (st.progress[m.id] >= m.goal) {
      st.done[m.id] = true;
      addCoins(m.reward);
      completed.push(m);
    }
  }
  save('color-claim-missions', JSON.stringify(st));
  renderMissionBadge();
  return completed;
}

function renderMissionBadge() {
  const st = freshMissionState();
  const done = todaysMissions().filter(m => st.done[m.id]).length;
  $('mission-badge').textContent = `${done}/3`;
  $('mission-badge').classList.toggle('all', done === 3);
}

function buildMissions() {
  const st = freshMissionState();
  $('mission-list').innerHTML = todaysMissions().map(m => {
    const n = st.progress[m.id] || 0, done = !!st.done[m.id];
    return `<li class="${done ? 'done' : ''}"><span class="check">${done ? '✓' : ''}</span><span class="t"><b>${m.text}</b>
      <span class="bar"><span style="width:${(n / m.goal) * 100}%"></span></span><span class="prog">${n} / ${m.goal}</span></span>
      <span class="reward">+${m.reward} <span class="coin"></span></span></li>`;
  }).join('');
}

// ---------- Weekly event banner ----------
function renderEvent() {
  const { event, daysLeft } = weekInfo();
  $('event-banner').innerHTML = `<b>This week: ${event.name}</b><span>${event.desc} · ends in ${daysLeft} day${daysLeft === 1 ? '' : 's'}</span>`;
}

// ---------- Season pass ----------
// Each calendar month is a season. XP you earn fills 20 tiers; every tier pays out, and
// tiers 10 and 20 give that season's trail effect and skin (yours to keep).
const SEASON_TIERS = 20, SEASON_TIER_XP = 150;
const SEASON_ITEMS = [{ fx: 'lightning', skin: 'crystal' }, { fx: 'snow', skin: 'tiger' }];
const MONTHS = ['January', 'February', 'March', 'April', 'May', 'June', 'July', 'August', 'September', 'October', 'November', 'December'];

function seasonNow() {
  const d = new Date();
  const end = new Date(d.getFullYear(), d.getMonth() + 1, 1);
  return {
    key: `${d.getFullYear()}-${d.getMonth() + 1}`,
    name: `${MONTHS[d.getMonth()]} season`,
    items: SEASON_ITEMS[(d.getFullYear() * 12 + d.getMonth()) % SEASON_ITEMS.length],
    daysLeft: Math.ceil((end - d) / 86400000),
  };
}

let season = loadJSON('color-claim-season', {});
function freshSeason() {
  const now = seasonNow();
  if (season.key !== now.key) season = { key: now.key, xp: 0, tier: 0 };
  return season;
}

function seasonReward(tier) {
  const { items } = seasonNow();
  if (tier === 10) return { fx: items.fx, text: `${TRAIL_FX.find(f => f.id === items.fx).name} trail` };
  if (tier === 20) return { skin: items.skin, text: `${SKINS.find(k => k.id === items.skin).name} skin` };
  const c = 20 + tier * 2;
  return { coins: c, text: `${c} coins` };
}

function addSeasonXp(n) {
  const st = freshSeason();
  st.xp += n;
  const newTier = Math.min(SEASON_TIERS, Math.floor(st.xp / SEASON_TIER_XP));
  const rewards = [];
  for (let t = st.tier + 1; t <= newTier; t++) {
    const r = seasonReward(t);
    if (r.coins) addCoins(r.coins);
    if (r.skin && !ownedSkins.includes(r.skin)) { ownedSkins.push(r.skin); save('color-claim-owned-skins', JSON.stringify(ownedSkins)); }
    if (r.fx && !ownedFx.includes(r.fx)) { ownedFx.push(r.fx); save('color-claim-owned-fx', JSON.stringify(ownedFx)); }
    rewards.push({ tier: t, ...r });
  }
  st.tier = newTier;
  save('color-claim-season', JSON.stringify(st));
  return rewards;
}

function buildSeason() {
  const st = freshSeason(), now = seasonNow();
  const into = st.tier >= SEASON_TIERS ? SEASON_TIER_XP : st.xp - st.tier * SEASON_TIER_XP;
  $('season-head').innerHTML = `<span><b>${now.name}</b> · tier ${st.tier} / ${SEASON_TIERS} · ends in ${now.daysLeft} day${now.daysLeft === 1 ? '' : 's'}</span>
    <span class="xpbar wide"><span style="width:${(into / SEASON_TIER_XP) * 100}%"></span></span>
    <small>${st.tier >= SEASON_TIERS ? 'Season complete!' : `${into} / ${SEASON_TIER_XP} XP to tier ${st.tier + 1}`}</small>`;
  const box = $('season-tiers');
  box.innerHTML = '';
  for (let t = 1; t <= SEASON_TIERS; t++) {
    const r = seasonReward(t);
    const cell = document.createElement('div');
    cell.className = 'tier' + (t <= st.tier ? ' got' : '') + (r.coins ? '' : ' big');
    cell.innerHTML = `<span class="n">${t}</span>`;
    if (r.skin) cell.appendChild(skinPreview(r.skin));
    else if (r.fx) cell.appendChild(fxPreview(r.fx));
    else cell.insertAdjacentHTML('beforeend', '<span class="coin"></span>');
    cell.insertAdjacentHTML('beforeend', `<small>${r.text}</small>`);
    box.appendChild(cell);
  }
}

// ---------- Map editor ----------
// Paint walls on an 80 x 80 grid. The middle stays clear so there's room to start.
const editor = { slot: 0, cells: new Uint8Array(CUSTOM_SIZE * CUSTOM_SIZE), tool: 1, brush: 1, mirror: true, drawing: false };
const edCanvas = $('editor-canvas'), edCtx = edCanvas.getContext('2d');
const edProtected = (x, y) => Math.hypot(x - CUSTOM_SIZE / 2, y - CUSTOM_SIZE / 2) < 7;

function editorLoadSlot(slot) {
  editor.slot = slot;
  const saved = loadCustomMaps()[slot];
  editor.cells = saved ? unpackCells(saved.cells) : new Uint8Array(CUSTOM_SIZE * CUSTOM_SIZE);
  buildEditor();
}

function drawEditor() {
  const C = edCanvas.width / CUSTOM_SIZE;
  edCtx.fillStyle = '#f5f7fc';
  edCtx.fillRect(0, 0, edCanvas.width, edCanvas.height);
  edCtx.fillStyle = '#edf0f8';
  for (let y = 0; y < CUSTOM_SIZE; y++) for (let x = (y % 2); x < CUSTOM_SIZE; x += 2) edCtx.fillRect(x * C, y * C, C, C);
  edCtx.fillStyle = 'rgba(79, 140, 255, 0.18)';
  edCtx.beginPath();
  edCtx.arc(CUSTOM_SIZE / 2 * C, CUSTOM_SIZE / 2 * C, 7 * C, 0, Math.PI * 2);
  edCtx.fill();
  edCtx.fillStyle = '#5a6680';
  for (let i = 0; i < editor.cells.length; i++) {
    if (editor.cells[i]) edCtx.fillRect((i % CUSTOM_SIZE) * C, Math.floor(i / CUSTOM_SIZE) * C, Math.ceil(C), Math.ceil(C));
  }
}

function editorPaint(e) {
  const r = edCanvas.getBoundingClientRect();
  const x = Math.floor(((e.clientX - r.left) / r.width) * CUSTOM_SIZE), y = Math.floor(((e.clientY - r.top) / r.height) * CUSTOM_SIZE);
  const pts = [[x, y]];
  if (editor.mirror) pts.push([CUSTOM_SIZE - 1 - x, y], [x, CUSTOM_SIZE - 1 - y], [CUSTOM_SIZE - 1 - x, CUSTOM_SIZE - 1 - y]);
  for (const [px, py] of pts) {
    for (let dy = -editor.brush + 1; dy < editor.brush; dy++) {
      for (let dx = -editor.brush + 1; dx < editor.brush; dx++) {
        const cx = px + dx, cy = py + dy;
        if (cx < 0 || cy < 0 || cx >= CUSTOM_SIZE || cy >= CUSTOM_SIZE || edProtected(cx, cy)) continue;
        editor.cells[cy * CUSTOM_SIZE + cx] = editor.tool;
      }
    }
  }
  drawEditor();
}

edCanvas.addEventListener('pointerdown', e => { editor.drawing = true; edCanvas.setPointerCapture(e.pointerId); editorPaint(e); });
edCanvas.addEventListener('pointermove', e => { if (editor.drawing) editorPaint(e); });
edCanvas.addEventListener('pointerup', () => { editor.drawing = false; });
edCanvas.addEventListener('pointercancel', () => { editor.drawing = false; });

function buildEditor() {
  const seg = (boxId, options, current, onPick) => {
    const box = $(boxId);
    box.innerHTML = '';
    for (const [val, text] of options) {
      const b = document.createElement('button');
      b.className = 'seg-btn' + (val === current ? ' picked' : '');
      b.textContent = text;
      b.addEventListener('click', () => onPick(val));
      box.appendChild(b);
    }
  };
  const saved = loadCustomMaps();
  seg('editor-slots', [0, 1, 2].map(i => [i, saved[i] ? saved[i].name : `Map ${i + 1} (empty)`]), editor.slot, editorLoadSlot);
  seg('editor-tool', [[1, 'Wall'], [0, 'Eraser']], editor.tool, v => { editor.tool = v; buildEditor(); });
  seg('editor-brush', [[1, 'Small'], [2, 'Big']], editor.brush, v => { editor.brush = v; buildEditor(); });
  seg('editor-mirror', [[true, 'Mirror on'], [false, 'Mirror off']], editor.mirror, v => { editor.mirror = v; buildEditor(); });
  drawEditor();
}

$('editor-clear').addEventListener('click', () => { editor.cells.fill(0); drawEditor(); });
$('editor-save').addEventListener('click', () => {
  const maps = loadCustomMaps();
  while (maps.length < 3) maps.push(null);
  maps[editor.slot] = { name: `My map ${editor.slot + 1}`, cells: packCells(editor.cells) };
  save('color-claim-maps', JSON.stringify(maps));
  myMap = 'custom' + editor.slot;
  save('color-claim-map', myMap);
  if (MODES[myMode].daily) { myMode = 'classic'; save('color-claim-mode', myMode); }
  buildPickers();
  showScreen('menu');
  toast(`Saved My map ${editor.slot + 1}. It's picked on the menu.`);
});

// ---------- Challenge codes ----------
// A code holds a game's seed, mode, map, bot difficulty and score, plus a check letter to catch typos.
// Your friend gets the same starting map and bots and tries to beat your score.
const CODE_MODES = ['classic', 'timed', 'marathon', 'team'];
const CODE_MAPS = ['square', 'round', 'pillars', 'maze', 'islands'];
const CODE_DIFFS = ['easy', 'normal', 'hard'];
let lastChallenge = null;

function makeCode(c) {
  const body = [c.seed.toString(36), `${CODE_MODES.indexOf(c.mode)}${CODE_MAPS.indexOf(c.map)}${CODE_DIFFS.indexOf(c.diff)}`, Math.round(c.score * 10).toString(36)].join('-');
  return (body + '-' + (hashStr(body) % 36).toString(36)).toUpperCase();
}

function readCode(text) {
  const parts = text.trim().toLowerCase().replace(/\s+/g, '').split('-');
  if (parts.length !== 4) return null;
  const body = parts.slice(0, 3).join('-');
  if ((hashStr(body) % 36).toString(36) !== parts[3] || parts[1].length !== 3) return null;
  const [m, mp, d] = parts[1].split('').map(Number);
  const c = { seed: parseInt(parts[0], 36) >>> 0, mode: CODE_MODES[m], map: CODE_MAPS[mp], diff: CODE_DIFFS[d], score: parseInt(parts[2], 36) / 10 };
  return c.mode && c.map && c.diff && Number.isFinite(c.seed) && Number.isFinite(c.score) ? c : null;
}

function describeChallenge(c) {
  return `${MODES[c.mode].name} · ${MAPS[c.map].name} map · ${DIFFICULTY[c.diff].name} bots · beat ${c.score.toFixed(1)}%`;
}

function challengeBeaten() {
  stats.challenges = (stats.challenges || 0) + 1;
  save('color-claim-stats', JSON.stringify(stats));
  for (const a of checkAchievements(runSnapshot())) { toast(`🏆 ${a.name}! +${ACH_REWARD} coins`); Sfx.play('trophy'); }
}

$('challenge-make').addEventListener('click', () => {
  if (!lastChallenge) return;
  const code = makeCode(lastChallenge);
  $('challenge-code').classList.remove('hidden');
  $('challenge-code-text').value = code;
  $('challenge-code-text').select();
});
$('challenge-copy').addEventListener('click', async () => {
  const input = $('challenge-code-text');
  try {
    await navigator.clipboard.writeText(input.value);
    $('challenge-copy').textContent = 'Copied!';
  } catch {
    input.select(); // copying isn't allowed here: the code is selected so it can be copied by hand
    $('challenge-copy').textContent = 'Select & copy';
  }
  setTimeout(() => { $('challenge-copy').textContent = 'Copy'; }, 1500);
});
$('challenge-input').addEventListener('input', () => {
  const c = readCode($('challenge-input').value);
  $('challenge-info').textContent = c ? describeChallenge(c) : $('challenge-input').value.trim() ? "That code doesn't look right. Check it and try again." : '';
  $('challenge-info').className = 'small ' + (c ? 'ok' : 'bad');
  $('challenge-play').disabled = !c;
});
$('challenge-play').addEventListener('click', () => {
  const c = readCode($('challenge-input').value);
  if (!c) return;
  challenge = c;
  startGame();
});

// ---------- Cup ----------
function showCup(roundCoins) {
  const done = cup.round > 3;
  const rows = Object.entries(cup.points).sort((a, b) => b[1] - a[1]);
  const place = rows.findIndex(([n]) => n === cup.meName) + 1;
  $('cup-title').textContent = done ? (place === 1 ? '🏆 You won the Cup!' : `Cup over: you finished #${place}`) : `Round ${cup.round - 1} of 3 done`;
  $('cup-table').innerHTML = rows.map(([name, pts], i) =>
    `<tr class="${name === cup.meName ? 'me' : ''}"><td>${i + 1}</td><td>${escapeHtml(name)}</td><td>+${cup.last[name] || 0}</td><td><b>${pts}</b></td></tr>`
  ).join('');
  let prize = 0;
  if (done) {
    prize = [150, 75, 40][place - 1] || 0;
    addCoins(prize);
    if (place === 1) {
      stats.cups = (stats.cups || 0) + 1;
      save('color-claim-stats', JSON.stringify(stats));
      for (const a of checkAchievements(runSnapshot())) toast(`🏆 ${a.name}! +${ACH_REWARD} coins`);
      Sfx.play('win');
    }
  }
  $('cup-note').innerHTML = `+${roundCoins} <span class="coin"></span> this round` + (done && prize ? ` · <b>+${prize} cup prize</b>` : '')
    + (done ? '' : ` · Next map: ${MAPS[cup.maps[cup.round - 1]].name}`);
  $('cup-next').textContent = done ? 'Back to menu' : `Play round ${cup.round}`;
  showScreen('cup');
}
$('cup-next').addEventListener('click', () => {
  if (cup && cup.round <= 3) startGame();
  else { cup = null; state = 'menu'; me = null; showScreen('menu'); }
});
$('cup-quit').addEventListener('click', () => { cup = null; state = 'menu'; me = null; showScreen('menu'); });

// ---------- Menu navigation ----------
function openScreen(id) {
  if (id === 'locker') buildLocker();
  if (id === 'settings') buildSettings();
  if (id === 'trophies') buildTrophies();
  if (id === 'stats') buildStats();
  if (id === 'missions') buildMissions();
  if (id === 'season') buildSeason();
  if (id === 'editor') editorLoadSlot(editor.slot);
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
      price: SKIN_PRICE, how: sk.need && sk.need.text, season: sk.need && sk.need.stat === 'season',
      equip: () => { mySkin = sk.id; save('color-claim-skin', sk.id); },
      buy: () => { ownedSkins.push(sk.id); save('color-claim-owned-skins', JSON.stringify(ownedSkins)); },
    }))
    : TRAIL_FX.map(fx => ({
      id: fx.id, name: fx.name, canvas: fxPreview(fx.id), open: ownedFx.includes(fx.id), equipped: fx.id === myFx,
      price: fx.price, season: fx.season,
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
    } else if (it.season) {
      btn.textContent = 'Season reward';
      btn.disabled = true;
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
    if (!it.open && it.how && !it.season) card.insertAdjacentHTML('beforeend', `<span class="how">or: ${it.how}</span>`);
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
    ['Giants beaten', s.giants || 0],
  ];
  const modes = ['classic', 'timed', 'marathon', 'team', 'daily'].map(m => [m === 'daily' ? "Today's Daily" : `${MODES[m].name} best`, `${bestFor(m).toFixed(1)}%`]);
  $('stats-grid').innerHTML = [...tiles, ...modes].map(([k, v]) => `<div class="tile"><b>${v}</b><span>${k}</span></div>`).join('');
}

// ---------- Settings ----------
function buildSettings() {
  const rows = [
    { label: 'Sound effects', value: !Sfx.muted, options: [[true, 'On'], [false, 'Off']], set: v => { if (v === Sfx.muted) toggleMute(); } },
    { label: 'Music', value: Music.enabled, options: [[true, 'On'], [false, 'Off']], set: v => { if (v !== Music.enabled) toggleMusic(); } },
    { label: 'Vibration', value: settings.vibrate, options: [[true, 'On'], [false, 'Off']], set: v => { settings.vibrate = v; buzz(30); } },
    { label: 'Colorblind patterns', value: settings.patterns, options: [[true, 'On'], [false, 'Off']], set: v => { settings.patterns = v; } },
    { label: 'Screen shake', value: settings.shake, options: [[true, 'On'], [false, 'Off']], set: v => { settings.shake = v; } },
    { label: 'Touch controls', value: settings.controls, options: [['joystick', 'Joystick'], ['turn', 'Tap to turn']], set: v => { settings.controls = v; } },
    { label: 'Joystick size', value: settings.stickSize, options: [['normal', 'Normal'], ['large', 'Large']], set: v => { settings.stickSize = v; } },
  ];
  const box = $('settings-list');
  box.innerHTML = '';
  for (const row of rows) {
    const li = document.createElement('li');
    li.innerHTML = `<span>${row.label}</span>`;
    const seg = document.createElement('div');
    seg.className = 'seg';
    for (const [val, text] of row.options) {
      const b = document.createElement('button');
      b.className = 'seg-btn' + (val === row.value ? ' picked' : '');
      b.textContent = text;
      b.addEventListener('click', () => { row.set(val); saveSettings(); buildSettings(); });
      seg.appendChild(b);
    }
    li.appendChild(seg);
    box.appendChild(li);
  }
  $('controls-help').textContent = settings.controls === 'turn'
    ? 'Tap to turn: hold the left or right half of the screen to turn that way. Great for one thumb.'
    : 'Joystick: put your finger down anywhere and drag the way you want to go.';
}

// ---------- Install as an app ----------
let installPrompt = null;
window.addEventListener('beforeinstallprompt', e => {
  e.preventDefault();
  installPrompt = e;
  $('install-btn').classList.remove('hidden');
});
$('install-btn').addEventListener('click', async () => {
  if (!installPrompt) return;
  installPrompt.prompt();
  await installPrompt.userChoice.catch(() => null);
  installPrompt = null;
  $('install-btn').classList.add('hidden');
});
window.addEventListener('appinstalled', () => $('install-btn').classList.add('hidden'));

// Offline support: the service worker keeps a copy of the game (only works over http/https)
if ('serviceWorker' in navigator && location.protocol.startsWith('http')) {
  navigator.serviceWorker.register('sw.js').catch(() => { /* offline play just won't be available */ });
}

// ---------- Start up ----------
allocWorld(80);
buildSwatches();
buildPickers();
renderCoins();
renderLevel();
renderMissionBadge();
renderEvent();
showScreen('menu');
requestAnimationFrame(frame);
