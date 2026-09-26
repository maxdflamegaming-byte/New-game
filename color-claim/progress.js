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
  { id: 'golden', name: 'Golden', desc: 'Reach Gold rank', test: () => rankBest >= 2 },
  // Page 2
  { id: 'kingslayer', name: 'Kingslayer', desc: 'Defeat the King in a Boss Battle', test: (r, s) => (s.bossWins || 0) >= 1, page: 2 },
  { id: 'diamond', name: 'Diamond', desc: 'Reach Diamond rank', test: () => rankBest >= 4, page: 2 },
  { id: 'ghostbuster', name: 'Ghostbuster', desc: 'Beat your own ghost in the Weekly', test: r => !!r.beatGhost, page: 2 },
  { id: 'onfire', name: 'On Fire', desc: 'Play 7 days in a row', test: () => (streak.best || 0) >= 7, progress: () => [streakNow(), 7], page: 2 },
  { id: 'portals', name: 'Now You See Me', desc: 'Go through 10 portals', test: (r, s) => (s.teleports || 0) >= 10, progress: s => [s.teleports || 0, 10], page: 2 },
  { id: 'eye', name: 'Eye of the Storm', desc: 'Win a game on the Storm map', test: r => r.won && r.map === 'storm', page: 2 },
  { id: 'lumberjack', name: 'Saw Survivor', desc: 'Survive 3 minutes on the Saw Mill map', test: r => r.map === 'saws' && r.time >= 180, page: 2 },
  { id: 'petlover', name: 'Pet Lover', desc: 'Own 4 pets', test: () => PETS.filter(pt => pt.id !== 'none' && petOpen(pt)).length >= 4, progress: () => [PETS.filter(pt => pt.id !== 'none' && petOpen(pt)).length, 4], page: 2 },
  { id: 'chatty', name: 'Chatterbox', desc: 'Send 25 emotes', test: (r, s) => (s.emotes || 0) >= 25, progress: s => [s.emotes || 0, 25], page: 2 },
  { id: 'bosshunter', name: 'Boss Hunter', desc: 'Beat the King, the Queen and the Wizard', test: (r, s) => ['king', 'queen', 'wizard'].every(b => ((s.bossBeaten || {})[b] || 0) > 0), progress: s => [['king', 'queen', 'wizard'].filter(b => ((s.bossBeaten || {})[b] || 0) > 0).length, 3], page: 2 },
  { id: 'warwinner', name: 'War Winner', desc: 'Win a weekly clan war', test: (r, s) => (s.clanWars || 0) >= 1, page: 2 },
  { id: 'questmaster', name: 'Questmaster', desc: 'Finish a whole weekly quest chain', test: (r, s) => (s.questChains || 0) >= 1, page: 2 },
];
let achieved = loadJSON('color-claim-achievements', {});

function runSnapshot(won = false) {
  return {
    peak: peakPct, kills: me ? me.kills : 0, time: playTime, bigLoop: run.bigLoop, freezeKO: run.freezeKO, giantKO: run.giantKO,
    beatGhost: run.beatGhost, map: gameMapId, mode: gameModeId, won,
  };
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
  stats.emotes = (stats.emotes || 0) + (run.emotes || 0);
  stats.teleports = (stats.teleports || 0) + (run.teleports || 0);
  if (gameModeId === 'boss' && won) {
    stats.bossWins = (stats.bossWins || 0) + 1;
    stats.bossBeaten = stats.bossBeaten || {};
    const kind = king ? king.kind : 'king';
    stats.bossBeaten[kind] = (stats.bossBeaten[kind] || 0) + 1;
  }

  const ranked = isRanked() ? rankGameResult(won) : null;
  const streakDay = tickStreak();
  const questsDone = updateQuests({
    ...runSnapshot(won), powerups: run.powerups, coinsPicked: run.coinsPicked, diff: gameDiffId,
  });
  const clanResult = addClanPoints(score, won);
  const earned = Math.round((Math.round(score * 2) + me.kills * 5 + (won ? 50 : 0)) * (eventOn('double') ? 2 : 1) * gameDiff.coins);
  addCoins(earned);
  const fresh = [...run.trophies, ...checkAchievements(runSnapshot(won))];
  const xpGain = Math.round((score * 10 + me.kills * 30 + (won ? 150 : 0) + playTime / 2) * (eventOn('xp') ? 1.5 : 1));
  const { levelsUp, levelCoins } = addXp(xpGain);
  const missionsDone = updateMissions({
    ...runSnapshot(), powerups: run.powerups, coinsPicked: run.coinsPicked, mode: gameModeId, map: gameMapId, diff: gameDiffId, won,
  });
  const missionCoins = missionsDone.reduce((a, m) => a + m.reward, 0);
  const seasonRewards = addSeasonXp(xpGain);
  save('color-claim-stats', JSON.stringify(stats));
  return { earned, fresh, xpGain, levelsUp, levelCoins, missionsDone, missionCoins, seasonRewards, ranked, streakDay, questsDone, clanResult };
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

// ---------- Ranked ladder ----------
// Solo games against bots move you up (or down) the ladder, depending on where you finish.
// Each tier has 3 divisions of 100 points (III, II, I); Champion is the top.
const RANKS = [
  { name: 'Bronze', at: 0, color: '#c98a5a', reward: 0 },
  { name: 'Silver', at: 300, color: '#9aa7bd', reward: 100 },
  { name: 'Gold', at: 600, color: '#f5b400', reward: 200 },
  { name: 'Platinum', at: 900, color: '#2ec4b6', reward: 300 },
  { name: 'Diamond', at: 1200, color: '#4f8cff', reward: 400 },
  { name: 'Champion', at: 1500, color: '#b06bff', reward: 600 },
];
const RANKED_MODES = ['classic', 'timed', 'daily', 'weekly', 'marathon'];
const RP_PLACE = [30, 20, 12, 6, -2, -6, -10, -14];
let rp = Math.max(0, Number(load('color-claim-rp', 0)) || 0);
let rankBest = Number(load('color-claim-rank-best', 0)) || 0; // highest tier ever reached (its reward is paid once)

function rankInfo(points) {
  let tier = 0;
  while (tier + 1 < RANKS.length && points >= RANKS[tier + 1].at) tier++;
  const r = RANKS[tier], champ = tier === RANKS.length - 1, into = points - r.at;
  const div = champ ? '' : ['III', 'II', 'I'][Math.min(2, Math.floor(into / 100))];
  return { tier, name: r.name, color: r.color, div, label: champ ? r.name : `${r.name} ${div}`, into: champ ? 100 : into % 100, champ };
}

const isRanked = () => RANKED_MODES.includes(gameModeId) && !challenge && !gameMapId.startsWith('custom');

// Where you finished: 1st if you won; otherwise by land against everyone still standing
// (if you were knocked out, the biggest you got counts)
function finishPlace(won) {
  if (won) return 1;
  const field = players.filter(p => p && p !== me && !p.isBoss && p.alive);
  return 1 + field.filter(p => (me.alive ? counts[p.id] > counts[me.id] : pct(p) > peakPct)).length;
}

function rankGameResult(won) {
  const place = finishPlace(won);
  const before = rankInfo(rp);
  const knocked = !won && !me.alive;
  let gain = (RP_PLACE[place - 1] ?? -14) + (won ? 10 : 0) + Math.min(10, me.kills * 2) - (knocked ? 4 : 0);
  gain *= gain > 0 ? { easy: 0.5, normal: 1, hard: 1.5 }[gameDiffId] : { easy: 1, normal: 1, hard: 0.75 }[gameDiffId] * (1 + before.tier * 0.15);
  // You can drop a division, but never out of a tier you've reached
  const next = Math.max(RANKS[before.tier].at, rp + Math.round(gain));
  gain = next - rp;
  rp = next;
  save('color-claim-rp', rp);
  const after = rankInfo(rp);
  let rewardCoins = 0;
  for (let t = rankBest + 1; t <= after.tier; t++) rewardCoins += RANKS[t].reward;
  if (after.tier > rankBest) {
    rankBest = after.tier;
    save('color-claim-rank-best', rankBest);
    addCoins(rewardCoins);
  }
  stats.bestRp = Math.max(stats.bestRp || 0, rp);
  renderRankNav();
  return { place, gain, before, after, promoted: after.tier > before.tier, rewardCoins };
}

// A shield in the tier's colour, with a star
function rankIcon(tier, size = 22) {
  const c = RANKS[tier].color;
  return `<svg class="rank-icon" width="${size}" height="${size}" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2l8 3v6c0 5-3.5 9-8 11-4.5-2-8-6-8-11V5z" fill="${c}" stroke="${shade(c, -0.3)}" stroke-width="1.5"/><path d="M12 7l1.5 3.1 3.3.5-2.4 2.3.6 3.3-3-1.6-3 1.6.6-3.3-2.4-2.3 3.3-.5z" fill="#fff" opacity="0.92"/></svg>`;
}

function renderRankNav() {
  const r = rankInfo(rp);
  $('rank-nav-icon').innerHTML = rankIcon(r.tier, 18);
  $('rank-nav-label').textContent = r.label;
}

const ordinal = n => n + (['th', 'st', 'nd', 'rd'][(n % 100 > 10 && n % 100 < 14) || n % 10 > 3 ? 0 : n % 10]);

function showRankResult(res) {
  const box = $('over-rank');
  box.classList.toggle('hidden', !res);
  if (!res) return;
  const r = res.after;
  const sign = res.gain > 0 ? '+' : res.gain < 0 ? '−' : '±';
  const promo = res.promoted ? `<b class="promo">Promoted to ${r.name}!${res.rewardCoins ? ` +${res.rewardCoins} coins` : ''}</b>` : '';
  box.innerHTML = `${rankIcon(r.tier, 26)}<span><b style="color:${shade(r.color, -0.25)}">${r.label}</b> · ${sign}${Math.abs(res.gain)} RP <small>(${ordinal(res.place)} place)</small></span>`
    + `<span class="xpbar"><span style="width:${r.into}%;background:${r.color}"></span></span>${promo}`;
  if (res.promoted) {
    Sfx.play('rankup');
    toast(`Promoted to ${r.name}!`);
  }
}

function buildRank() {
  const r = rankInfo(rp);
  const nextTier = RANKS[r.tier + 1];
  const nextAt = r.champ ? null : r.div === 'I' ? nextTier.at : RANKS[r.tier].at + (Math.floor((rp - RANKS[r.tier].at) / 100) + 1) * 100;
  $('rank-card').innerHTML = `${rankIcon(r.tier, 64)}<b style="color:${shade(r.color, -0.25)}">${r.label}</b><span>${rp} RP</span>`
    + `<span class="xpbar wide"><span style="width:${r.into}%;background:${r.color}"></span></span>`
    + `<small>${r.champ ? 'Top of the ladder!' : `${nextAt - rp} RP to ${rankInfo(nextAt).label}`}</small>`;
  $('rank-ladder').innerHTML = RANKS.map((t, i) => {
    const cls = i === r.tier ? 'here' : i < r.tier ? 'done' : '';
    const reward = i === 0 ? '' : i <= rankBest ? `✓ +${t.reward}` : `+${t.reward} <span class="coin"></span>`;
    return `<li class="${cls}">${rankIcon(i, 26)}<b>${t.name}</b><span>${t.at} RP</span><small>${reward}</small></li>`;
  }).reverse().join('');
}

// ---------- Daily streak ----------
// Finish a game every day to keep your streak going. The first game each day pays out,
// more for every day in a row, and day 7 unlocks the Star Sprite pet.
const STREAK_COINS = [20, 30, 40, 50, 60, 80, 150]; // days 1-7; every day after that pays 100
let streak = loadJSON('color-claim-streak', { last: '', count: 0, best: 0 });
const streakPay = day => (day <= 7 ? STREAK_COINS[day - 1] : 100);

function yesterdayKey() {
  const d = new Date();
  d.setDate(d.getDate() - 1);
  return `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, '0')}-${String(d.getDate()).padStart(2, '0')}`;
}
// The streak still counts if you played today or yesterday
const streakNow = () => (streak.last === todayKey() || streak.last === yesterdayKey() ? streak.count : 0);

function tickStreak() {
  if (streak.last === todayKey()) return null;
  streak.count = streak.last === yesterdayKey() ? streak.count + 1 : 1;
  streak.last = todayKey();
  streak.best = Math.max(streak.best || 0, streak.count);
  save('color-claim-streak', JSON.stringify(streak));
  const coinsWon = streakPay(streak.count);
  addCoins(coinsWon);
  renderStreak();
  return { day: streak.count, coins: coinsWon, pet: streak.count === 7 };
}

const FLAME = '<svg class="flame" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2c1 4 5 6 5 11a5 5 0 0 1-10 0c0-2 1-3.5 2-4.5 0 2 1 3 2 3-1-3 0-6 1-9.5z" fill="#ff8c42"/><path d="M12 12c.6 2 2.5 2.8 2.5 5a2.5 2.5 0 0 1-5 0c0-1.5 1.2-2.5 2.5-5z" fill="#ffd23f"/></svg>';

function renderStreak() {
  const n = streakNow(), playedToday = streak.last === todayKey();
  const pips = Array.from({ length: 7 }, (_, i) => `<i class="${i < Math.min(n, 7) ? 'on' : ''}${i === 6 ? ' star' : ''}"></i>`).join('');
  const next = streakPay(n + 1);
  const text = !n ? `Start a streak: finish a game today for +${next} coins`
    : playedToday ? `<b>${n}-day streak!</b> Come back tomorrow for +${next}`
    : `<b>${n}-day streak</b> · play today to keep it (+${next})`;
  $('streak-line').innerHTML = `${FLAME}<span>${text}</span><span class="pips" title="Day 7 unlocks the Star Sprite pet">${pips}</span>`;
}

// ---------- Weekly quest chain ----------
// Five quests a week, one after another, each paying more than the last. The chain is the
// same for everyone that week (picked from the week number): 2 easy, 2 medium, 1 hard.
const QUEST_POOL = {
  easy: [
    { id: 'play5', text: 'Play 5 games', goal: 5, add: () => 1 },
    { id: 'claim30', text: 'Claim 30% in total', goal: 30, add: r => Math.floor(r.peak) },
    { id: 'ko5', text: 'Knock out 5 players', goal: 5, add: r => r.kills },
    { id: 'power6', text: 'Grab 6 power-ups', goal: 6, add: r => r.powerups },
  ],
  medium: [
    { id: 'maps3', text: 'Play on 3 different maps', goal: 3, maps: true },
    { id: 'win2', text: 'Win 2 games', goal: 2, add: r => (r.won ? 1 : 0) },
    { id: 'one20', text: 'Claim 20% in one game', goal: 1, add: r => (r.peak >= 20 ? 1 : 0) },
    { id: 'weekly2', text: 'Finish 2 Weekly games', goal: 2, add: r => (r.mode === 'weekly' ? 1 : 0) },
    { id: 'coins15', text: 'Pick up 15 coins on the map', goal: 15, add: r => r.coinsPicked },
  ],
  hard: [
    { id: 'boss', text: 'Beat a boss', goal: 1, add: r => (r.mode === 'boss' && r.won ? 1 : 0) },
    { id: 'ko15', text: 'Knock out 15 players', goal: 15, add: r => r.kills },
    { id: 'one30', text: 'Claim 30% in one game', goal: 1, add: r => (r.peak >= 30 ? 1 : 0) },
    { id: 'hardwin', text: 'Win a game against Hard bots', goal: 1, add: r => (r.won && r.diff === 'hard' ? 1 : 0) },
  ],
};
const QUEST_REWARDS = [50, 75, 100, 150, 300];

function weeklyQuests() {
  const rng = mulberry32(hashStr('color-claim-quests-' + weekInfo().week));
  const pick = (list, n) => { const l = list.slice(), out = []; while (out.length < n) out.push(l.splice(Math.floor(rng() * l.length), 1)[0]); return out; };
  return [...pick(QUEST_POOL.easy, 2), ...pick(QUEST_POOL.medium, 2), ...pick(QUEST_POOL.hard, 1)]
    .map((q, i) => ({ ...q, reward: QUEST_REWARDS[i] }));
}

let questState = loadJSON('color-claim-quests', {});
function freshQuestState() {
  if (questState.week !== weekInfo().week) questState = { week: weekInfo().week, step: 0, progress: 0, maps: [] };
  return questState;
}

// Moves the current quest along (one step per game at most)
function updateQuests(r) {
  const st = freshQuestState(), chain = weeklyQuests();
  if (st.step >= chain.length) return [];
  const q = chain[st.step];
  if (q.maps) {
    if (!st.maps.includes(r.map)) st.maps.push(r.map);
    st.progress = st.maps.length;
  } else st.progress = Math.min(q.goal, st.progress + q.add(r));
  const done = [];
  if (st.progress >= q.goal) {
    addCoins(q.reward);
    done.push({ ...q, step: st.step + 1 });
    st.step++;
    st.progress = 0;
    st.maps = [];
    if (st.step === chain.length) stats.questChains = (stats.questChains || 0) + 1;
  }
  save('color-claim-quests', JSON.stringify(st));
  return done;
}

function buildQuests() {
  const st = freshQuestState(), chain = weeklyQuests();
  $('quest-list').innerHTML = chain.map((q, i) => {
    const state = i < st.step ? 'done' : i === st.step ? 'now' : 'locked';
    const n = i === st.step ? st.progress : i < st.step ? q.goal : 0;
    const body = state === 'locked' ? `<b>Quest ${i + 1}</b><span class="prog">Finish quest ${i} to unlock</span>`
      : `<b>${q.text}</b><span class="bar"><span style="width:${(n / q.goal) * 100}%"></span></span><span class="prog">${n} / ${q.goal}</span>`;
    return `<li class="${state}"><span class="check">${state === 'done' ? '✓' : state === 'locked' ? Icons.lock : i + 1}</span><span class="t">${body}</span>`
      + `<span class="reward">+${q.reward} <span class="coin"></span></span></li>`;
  }).join('');
  $('quest-head').textContent = st.step >= chain.length ? 'Chain complete! New quests on Monday.' : `Quest ${st.step + 1} of ${chain.length} · ${weekInfo().daysLeft} days left`;
}

// ---------- Clan ----------
// Start a clan with a name, a short tag and an emblem. Every game earns clan points (CP),
// which level your clan up, and each week your clan races a rival clan in a clan war.
const CLAN_EMBLEMS = {
  shield: 'M12 2l8 3v6c0 5-3.5 9-8 11-4.5-2-8-6-8-11V5z',
  star: 'M12 2l2.9 6.3 6.9.7-5.2 4.6 1.5 6.8L12 17l-6.1 3.4 1.5-6.8L2.2 9l6.9-.7z',
  crown: 'M3 8l4.5 4L12 5l4.5 7L21 8l-2 11H5z',
  bolt: 'M13 2L4 14h6l-1 8 9-12h-6z',
  heart: 'M12 21s-8-5.5-8-11a4.5 4.5 0 0 1 8-2.8A4.5 4.5 0 0 1 20 10c0 5.5-8 11-8 11z',
};
const RIVALS = [['Pixel Pirates', 'PXP'], ['Neon Ninjas', 'NEON'], ['Turbo Toads', 'TOAD'], ['Square Squad', 'SQD'], ['Loop Legends', 'LOOP'], ['Trail Blazers', 'BLZ']];
const CLAN_LEVEL_CP = 300;
let clan = loadJSON('color-claim-clan', null);

function clanEmblem(emblem, color, size = 22) {
  return `<svg class="emblem" width="${size}" height="${size}" viewBox="0 0 24 24" aria-hidden="true"><path d="${CLAN_EMBLEMS[emblem] || CLAN_EMBLEMS.shield}" fill="${color}" stroke="${shade(color, -0.3)}" stroke-width="1.5" stroke-linejoin="round"/></svg>`;
}

// This week's rival clan, and how many points they will have scored by the end of the week
function rivalClan(week = weekInfo().week) {
  const h = hashStr('color-claim-rival-' + week);
  const [name, tag] = RIVALS[h % RIVALS.length];
  return { name, tag, target: 250 + (h % 400) };
}
function weekProgress() {
  const d = new Date();
  const monday = new Date(d.getFullYear(), d.getMonth(), d.getDate() - ((d.getDay() + 6) % 7));
  return clamp((d - monday) / (7 * 86400000), 0, 1);
}
const rivalScoreNow = () => Math.round(rivalClan().target * weekProgress());
const clanLevel = cp => Math.floor(cp / CLAN_LEVEL_CP) + 1;
const saveClan = () => save('color-claim-clan', JSON.stringify(clan));

// A new week: settle last week's war
function settleClanWar() {
  if (!clan || !clan.war || clan.war.week === weekInfo().week) return null;
  const rival = rivalClan(clan.war.week), won = clan.war.cp > rival.target;
  clan.lastWar = { rival: rival.name, you: clan.war.cp, them: rival.target, won };
  if (won) {
    addCoins(250);
    stats.clanWars = (stats.clanWars || 0) + 1;
    save('color-claim-stats', JSON.stringify(stats));
  }
  clan.war = { week: weekInfo().week, cp: 0 };
  saveClan();
  return clan.lastWar;
}

function addClanPoints(score, won) {
  if (!clan || gameMode.duo) return null;
  settleClanWar();
  const gain = Math.round((Math.round(score) + (won ? 20 : 0) + me.kills * 3) * (gameMode.teams ? 1.5 : 1));
  const before = clanLevel(clan.cp);
  clan.cp += gain;
  clan.war.cp += gain;
  const after = clanLevel(clan.cp);
  if (after > before) addCoins((after - before) * 50);
  saveClan();
  return { gain, level: after, levelUp: after > before };
}

function createClan(name, tag, color, emblem) {
  clan = { ...(clan || { cp: 0, war: { week: weekInfo().week, cp: 0 } }), name, tag, color, emblem };
  saveClan();
  renderClanNav();
}

function renderClanNav() {
  $('clan-nav').innerHTML = clan ? `${clanEmblem(clan.emblem, COLORS[clan.color], 18)} [${escapeHtml(clan.tag)}]` : 'Clan';
}

let clanForm = null; // { name, tag, color, emblem } while creating or editing
function buildClan() {
  const box = $('clan-body');
  if (!clan || clanForm) {
    const f = clanForm || (clanForm = { name: '', tag: '', color: myColor, emblem: 'shield' });
    box.innerHTML = `<p class="small">${clan ? 'Change your clan:' : "You're not in a clan yet. Start one! Every game earns clan points, and each week your clan takes on a rival clan."}</p>
      <input id="clan-name" maxlength="16" placeholder="Clan name" value="${escapeHtml(f.name)}" autocomplete="off" spellcheck="false">
      <input id="clan-tag" class="code-input" maxlength="4" placeholder="TAG" value="${escapeHtml(f.tag)}" autocomplete="off" spellcheck="false">
      <div class="seg" id="clan-emblems">${Object.keys(CLAN_EMBLEMS).map(e => `<button class="seg-btn${e === f.emblem ? ' picked' : ''}" data-emblem="${e}" aria-label="${e}">${clanEmblem(e, COLORS[f.color], 24)}</button>`).join('')}</div>
      <div class="seg" id="clan-colors">${COLORS.map((c, i) => `<button class="swatch${i === f.color ? ' picked' : ''}" style="background:${c}" data-color="${i}" aria-label="Color ${i + 1}"></button>`).join('')}</div>
      <p id="clan-error" class="small"></p>
      <div class="row"><button id="clan-save">${clan ? 'Save' : 'Start clan'}</button>${clan ? '<button id="clan-cancel" class="secondary">Cancel</button>' : ''}</div>`;
    $('clan-name').addEventListener('input', e => { f.name = e.target.value; });
    $('clan-tag').addEventListener('input', e => { e.target.value = e.target.value.toUpperCase().replace(/[^A-Z0-9]/g, ''); f.tag = e.target.value; });
    box.querySelectorAll('[data-emblem]').forEach(b => b.addEventListener('click', () => { f.emblem = b.dataset.emblem; buildClan(); }));
    box.querySelectorAll('[data-color]').forEach(b => b.addEventListener('click', () => { f.color = Number(b.dataset.color); buildClan(); }));
    $('clan-save').addEventListener('click', () => {
      const name = f.name.trim().slice(0, 16), tag = f.tag.trim();
      if (!name || tag.length < 2) { $('clan-error').textContent = 'Give your clan a name and a tag of 2 to 4 letters.'; return; }
      createClan(name, tag, f.color, f.emblem);
      clanForm = null;
      toast(`Welcome to ${name}!`);
      Sfx.play('trophy');
      buildClan();
    });
    if (clan) $('clan-cancel').addEventListener('click', () => { clanForm = null; buildClan(); });
    return;
  }
  settleClanWar();
  const color = COLORS[clan.color], lvl = clanLevel(clan.cp), into = clan.cp % CLAN_LEVEL_CP;
  const rival = rivalClan(), them = rivalScoreNow(), you = clan.war.cp, top = Math.max(you, them, 1);
  const last = clan.lastWar ? `<p class="small">Last week: ${clan.lastWar.won ? `<b class="good">won</b> against ${clan.lastWar.rival} (${clan.lastWar.you} vs ${clan.lastWar.them}) +250 coins` : `lost to ${clan.lastWar.rival} (${clan.lastWar.you} vs ${clan.lastWar.them})`}</p>` : '';
  box.innerHTML = `<div class="clan-card">${clanEmblem(clan.emblem, color, 56)}<b style="color:${shade(color, -0.2)}">${escapeHtml(clan.name)}</b><span>[${escapeHtml(clan.tag)}] · Level ${lvl} · ${clan.cp} CP</span>
      <span class="xpbar wide"><span style="width:${(into / CLAN_LEVEL_CP) * 100}%;background:${color}"></span></span><small>${CLAN_LEVEL_CP - into} CP to level ${lvl + 1} (+50 coins)</small></div>
    <div class="clan-war"><b>Clan war vs ${rival.name} [${rival.tag}]</b><small>${weekInfo().daysLeft} days left · the winner at the end of the week gets 250 coins</small>
      <div class="war-row"><span>${escapeHtml(clan.tag)}</span><span class="xpbar wide"><span style="width:${(you / top) * 100}%;background:${color}"></span></span><b>${you}</b></div>
      <div class="war-row"><span>${rival.tag}</span><span class="xpbar wide"><span style="width:${(them / top) * 100}%;background:#8d97ab"></span></span><b>${them}</b></div>
      <small>${you > them ? "You're ahead. Keep it up!" : 'Play games to earn clan points (Teams games earn 1.5×).'}</small></div>
    ${last}
    <div class="row"><button id="clan-edit" class="nav-btn">Edit clan</button><button id="clan-leave" class="nav-btn">Leave clan</button></div>`;
  $('clan-edit').addEventListener('click', () => { clanForm = { name: clan.name, tag: clan.tag, color: clan.color, emblem: clan.emblem }; buildClan(); });
  $('clan-leave').addEventListener('click', () => {
    if ($('clan-leave').dataset.sure !== '1') { $('clan-leave').dataset.sure = '1'; $('clan-leave').textContent = 'Tap again: you lose your CP'; return; }
    clan = null;
    save('color-claim-clan', 'null');
    renderClanNav();
    buildClan();
  });
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
  $('map-code').classList.add('hidden');
  $('map-import-info').textContent = '';
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

// Map codes: the wall grid as run lengths (a varint per run, walls and floor taking turns),
// base64url encoded, with a check letter to catch copy mistakes
function mapToCode(cells) {
  const bytes = [];
  let cur = 0, runLen = 0;
  const flush = () => { let n = runLen; do { bytes.push((n & 127) | (n > 127 ? 128 : 0)); n >>= 7; } while (n); };
  for (let i = 0; i < cells.length; i++) {
    if (cells[i] === cur) { runLen++; continue; }
    flush();
    cur = cells[i];
    runLen = 1;
  }
  flush();
  const body = btoa(String.fromCharCode(...bytes)).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
  return `MAP-${body}-${(hashStr(body) % 36).toString(36).toUpperCase()}`;
}

function codeToMap(text) {
  const m = /^MAP-([A-Za-z0-9_-]+)-([0-9A-Z])$/.exec(text.trim().replace(/\s+/g, ''));
  if (!m || (hashStr(m[1]) % 36).toString(36).toUpperCase() !== m[2]) return null;
  let bin;
  try { bin = atob(m[1].replace(/-/g, '+').replace(/_/g, '/')); } catch { return null; }
  const cells = new Uint8Array(CUSTOM_SIZE * CUSTOM_SIZE);
  let pos = 0, cur = 0, i = 0;
  while (i < bin.length) {
    let n = 0, shift = 0, b;
    do { b = bin.charCodeAt(i++); n |= (b & 127) << shift; shift += 7; } while (b & 128 && i < bin.length);
    if (pos + n > cells.length) return null;
    if (cur) cells.fill(1, pos, pos + n);
    pos += n;
    cur ^= 1;
  }
  if (pos !== cells.length) return null;
  // The start area always stays clear
  for (let y = 0; y < CUSTOM_SIZE; y++) for (let x = 0; x < CUSTOM_SIZE; x++) if (edProtected(x, y)) cells[y * CUSTOM_SIZE + x] = 0;
  return cells;
}

$('editor-share').addEventListener('click', () => {
  $('map-code-text').value = mapToCode(editor.cells);
  $('map-code').classList.remove('hidden');
  $('map-code-text').select();
});
$('map-code-copy').addEventListener('click', async () => {
  const text = $('map-code-text').value;
  try { await navigator.clipboard.writeText(text); toast('Map code copied!'); } catch { $('map-code-text').select(); toast('Select the code and copy it'); }
});
$('map-import').addEventListener('click', () => {
  const cells = codeToMap($('map-import-text').value);
  if (!cells) { $('map-import-info').textContent = "That code doesn't look right. Check it and try again."; return; }
  editor.cells = cells;
  drawEditor();
  $('map-import-info').textContent = `Loaded into slot ${editor.slot + 1}. Press Save map to keep it.`;
  Sfx.play('coin');
});
$('editor-save').addEventListener('click', () => {
  const maps = loadCustomMaps();
  while (maps.length < 3) maps.push(null);
  maps[editor.slot] = { name: `My map ${editor.slot + 1}`, cells: packCells(editor.cells) };
  save('color-claim-maps', JSON.stringify(maps));
  myMap = 'custom' + editor.slot;
  save('color-claim-map', myMap);
  if (fixedMap(myMode)) { myMode = 'classic'; save('color-claim-mode', myMode); }
  buildPickers();
  showScreen('menu');
  toast(`Saved My map ${editor.slot + 1}. It's picked on the menu.`);
});

// ---------- Challenge codes ----------
// A code holds a game's seed, mode, map, bot difficulty and score, plus a check letter to catch typos.
// Your friend gets the same starting map and bots and tries to beat your score.
const CODE_MODES = ['classic', 'timed', 'marathon', 'team'];
const CODE_MAPS = ['square', 'round', 'pillars', 'maze', 'islands', 'saws', 'storm', 'belts', 'portals'];
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
  if (id === 'rank') buildRank();
  if (id === 'clan') { clanForm = null; buildClan(); }
  if (id === 'missions') buildQuests();
  if (id === 'editor') editorLoadSlot(editor.slot);
  showScreen(id);
}
document.querySelectorAll('[data-open]').forEach(b => b.addEventListener('click', () => openScreen(b.dataset.open)));
document.querySelectorAll('[data-back]').forEach(b => b.addEventListener('click', () => showScreen('menu')));

// ---------- Locker ----------
let lockerTab = 'skins';
let ownedPets = loadJSON('color-claim-owned-pets', ['none', 'chick']);
const RANK_NAMES = ['Bronze', 'Silver', 'Gold', 'Platinum', 'Diamond', 'Champion'];
const petOpen = pet => pet.price === 0 || pet.id === 'none' || ownedPets.includes(pet.id)
  || (pet.rank && rankBest >= pet.rank) || (pet.streak && (streak.best || 0) >= pet.streak);
if (!petOpen(PETS.find(pt => pt.id === myPet) || PETS[0])) myPet = 'chick';

function petPreview(petId) {
  const c = document.createElement('canvas');
  c.width = c.height = 88;
  drawPet(c.getContext('2d'), petId, 44, 50, 46, 0.4);
  if (petId === 'none') {
    const g = c.getContext('2d');
    g.strokeStyle = '#aab4c8';
    g.lineWidth = 4;
    g.beginPath();
    g.arc(44, 44, 20, 0, TAU);
    g.moveTo(30, 58);
    g.lineTo(58, 30);
    g.stroke();
  }
  return c;
}
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
  const items = lockerTab === 'pets'
    ? PETS.map(pet => ({
      id: pet.id, name: pet.name, canvas: petPreview(pet.id), open: petOpen(pet), equipped: pet.id === myPet,
      price: pet.price, locked: !pet.price && pet.price !== 0 && pet.id !== 'none',
      how: pet.rank ? `Reach ${RANK_NAMES[pet.rank]} rank` : pet.streak ? `Play ${pet.streak} days in a row` : '',
      equip: () => { myPet = pet.id; save('color-claim-pet', pet.id); },
      buy: () => { ownedPets.push(pet.id); save('color-claim-owned-pets', JSON.stringify(ownedPets)); },
    }))
    : lockerTab === 'skins'
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
    } else if (it.locked) {
      btn.innerHTML = `${Icons.lock} Locked`;
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
    if (!it.open && it.how && !it.season) card.insertAdjacentHTML('beforeend', `<span class="how">${it.locked ? '' : 'or: '}${it.how}</span>`);
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

// ---------- Badges ----------
// Wear any trophy you've earned as a badge under your name
let myBadge = load('color-claim-badge', '');
function badgeName() {
  const a = myBadge && achieved[myBadge] && ACHIEVEMENTS.find(x => x.id === myBadge);
  return a ? a.name : '';
}

// ---------- Trophies ----------
let trophyPage = 1;
function buildTrophies() {
  const got = ACHIEVEMENTS.filter(a => achieved[a.id]).length;
  $('trophy-count').textContent = `${got} / ${ACHIEVEMENTS.length} unlocked · ${ACH_REWARD} coins each · wear one as a badge under your name`;
  $('trophy-pages').innerHTML = [1, 2].map(n => {
    const list = ACHIEVEMENTS.filter(a => (a.page || 1) === n);
    return `<button class="seg-btn${n === trophyPage ? ' picked' : ''}" data-page="${n}">Page ${n} <small>${list.filter(a => achieved[a.id]).length}/${list.length}</small></button>`;
  }).join('');
  $('trophy-pages').querySelectorAll('button').forEach(b => b.addEventListener('click', () => { trophyPage = Number(b.dataset.page); buildTrophies(); }));
  $('trophy-list').innerHTML = ACHIEVEMENTS.filter(a => (a.page || 1) === trophyPage).map(a => {
    const done = !!achieved[a.id];
    let extra = '';
    if (!done && a.progress) {
      const [n, max] = a.progress(stats);
      extra = `<span class="bar"><span style="width:${Math.min(100, (n / max) * 100)}%"></span></span><span class="prog">${Math.min(n, max)} / ${max}</span>`;
    }
    const wear = done ? `<button class="wear-btn${myBadge === a.id ? ' on' : ''}" data-badge="${a.id}">${myBadge === a.id ? 'Wearing' : 'Wear'}</button>` : '';
    return `<li class="${done ? 'done' : ''}">${Icons.trophy}<span class="t"><b>${a.name}</b><span>${a.desc}</span>${extra}</span>${wear}</li>`;
  }).join('');
  document.querySelectorAll('.wear-btn').forEach(b => b.addEventListener('click', () => {
    myBadge = myBadge === b.dataset.badge ? '' : b.dataset.badge;
    save('color-claim-badge', myBadge);
    buildTrophies();
  }));
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
    ['Rank', rankInfo(rp).label],
    ['Day streak', streakNow()],
    ['Bosses beaten', Object.values(s.bossBeaten || {}).reduce((a, b) => a + b, 0)],
    ['Clan points', clan ? clan.cp : '–'],
    ['Best streak', streak.best || 0],
    ['Most RP', s.bestRp || 0],
  ];
  const modes = ['classic', 'timed', 'marathon', 'team', 'daily', 'weekly'].map(m => [m === 'daily' ? "Today's Daily" : m === 'weekly' ? "This week's Weekly" : `${MODES[m].name} best`, `${bestFor(m).toFixed(1)}%`]);
  $('stats-grid').innerHTML = [...tiles, ...modes].map(([k, v]) => `<div class="tile"><b>${v}</b><span>${k}</span></div>`).join('');
}

// ---------- Settings ----------
function buildSettings() {
  const rows = [
    { label: 'Sound effects', value: !Sfx.muted, options: [[true, 'On'], [false, 'Off']], set: v => { if (v === Sfx.muted) toggleMute(); } },
    { label: 'Music', value: Music.enabled, options: [[true, 'On'], [false, 'Off']], set: v => { if (v !== Music.enabled) toggleMusic(); } },
    { label: 'Vibration', value: settings.vibrate, options: [[true, 'On'], [false, 'Off']], set: v => { settings.vibrate = v; buzz(30); } },
    { label: 'Colorblind patterns', value: settings.patterns, options: [[true, 'On'], [false, 'Off']], set: v => { settings.patterns = v; } },
    { label: 'Bot emotes', value: settings.emotes, options: [[true, 'On'], [false, 'Off']], set: v => { settings.emotes = v; } },
    { label: 'Screen shake', value: settings.shake, options: [[true, 'On'], [false, 'Off']], set: v => { settings.shake = v; } },
    { label: 'Touch controls', value: settings.controls, options: [['joystick', 'Joystick'], ['turn', 'Tap to turn']], set: v => { settings.controls = v; } },
    { label: 'Joystick size', value: settings.stickSize, options: [['normal', 'Normal'], ['large', 'Large']], set: v => { settings.stickSize = v; } },
    { label: 'Music style', value: settings.track, options: [['sunny', 'Sunny'], ['night', 'Night']], set: v => { settings.track = v; Music.track = v; } },
    { label: 'Text size', value: settings.bigText, options: [[false, 'Normal'], [true, 'Large']], set: v => { settings.bigText = v; applyA11y(); } },
    { label: 'High contrast', value: settings.contrast, options: [[false, 'Off'], [true, 'On']], set: v => { settings.contrast = v; applyA11y(); } },
    { label: 'Game speed', value: settings.speed, options: [['normal', 'Normal'], ['slow', 'Slower']], set: v => { settings.speed = v; } },
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
renderRankNav();
renderStreak();
renderClanNav();
applyA11y();
{
  const war = settleClanWar();
  if (war) later(800, () => toast(war.won ? `Your clan won the war against ${war.rival}! +250 coins` : `Your clan lost the war against ${war.rival}. New war this week!`));
}
showScreen('menu');
requestAnimationFrame(frame);
