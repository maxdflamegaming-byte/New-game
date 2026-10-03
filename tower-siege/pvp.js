'use strict';

// PvP for Tower Siege: online 1-vs-1, two players on one phone, and practice against a bot.
// Online, one phone (the host) runs the battle and sends what's happening to the other (the
// guest) about 10 times a second; the guest sends its moves. The server (server/server.js)
// only pairs players and passes messages. Each player sees their own army in blue at the bottom:
// the guest's copy swaps blue and red and turns the field around.

const PVP_PROTOCOL = 1;
const PVP_SERVER = new URLSearchParams(location.search).get('server') || 'wss://tower-siege-server.onrender.com';
const PVP_TIME = 180;            // a match lasts at most 3 minutes; then the bigger army wins
const SNAP_EVERY = 0.1;          // seconds between the host's updates
const WIN_TROPHIES = 30, LOSS_TROPHIES = 15;
const LEAGUES = [
  { name: 'Bronze', min: 0, color: '#e0965a' },
  { name: 'Silver', min: 150, color: '#c3cede' },
  { name: 'Gold', min: 400, color: '#ffc928' },
  { name: 'Platinum', min: 800, color: '#5fe0d0' },
  { name: 'Diamond', min: 1500, color: '#8ec5ff' },
];
const leagueOf = trophies => LEAGUES.filter(l => trophies >= l.min).pop();

let pvp = null;                  // the current PvP match: { kind, snapT, events, over, unitsById }
const swapSide = s => (s === 1 ? 2 : s === 2 ? 1 : s);
function isGuest() { return mode === 'online' && Net.role === 'guest'; }

// ---------- Connection ----------
const Net = {
  ws: null,
  role: null,       // 'host' or 'guest' during a match
  opp: null,        // { name, trophies }
  ready: false,

  // Connect and say hello. A free server may be asleep, so keep trying for up to a minute.
  connect(status) {
    if (this.ready && this.ws?.readyState === WebSocket.OPEN) return Promise.resolve();
    const started = Date.now();
    return new Promise((resolve, reject) => {
      const attempt = () => {
        let ws;
        try { ws = new WebSocket(PVP_SERVER); } catch { reject(new Error('down')); return; }
        let welcomed = false;
        ws.onopen = () => ws.send(JSON.stringify({ t: 'hello', v: PVP_PROTOCOL, name: save.name, trophies: save.trophies }));
        ws.onmessage = ev => {
          let msg;
          try { msg = JSON.parse(ev.data); } catch { return; }
          if (!welcomed) {
            if (msg.t === 'welcome') { welcomed = true; this.ws = ws; this.ready = true; resolve(); }
            else if (msg.t === 'old') { ws.close(); reject(new Error('old')); }
            return;
          }
          onNet(msg);
        };
        ws.onclose = () => {
          if (welcomed) { if (this.ws === ws) { this.ready = false; this.ws = null; onNetLost(); } return; }
          if (Date.now() - started > 60000) { reject(new Error('down')); return; }
          status?.('Waking up the server… (this can take up to a minute)');
          setTimeout(attempt, 3000);
        };
      };
      attempt();
    });
  },
  send(msg) {
    if (this.ws?.readyState === WebSocket.OPEN) this.ws.send(JSON.stringify(msg));
  },
  leave() {
    this.send({ t: 'leave' });
    this.role = null;
  },
};

function onNet(msg) {
  switch (msg.t) {
    case 'waiting':
      $('wait-text').textContent = 'Looking for an opponent…';
      break;
    case 'room':
      $('wait-text').textContent = 'Send this code to a friend. The match starts when they join.';
      $('wait-code').textContent = msg.code;
      $('wait-code').classList.remove('hidden');
      break;
    case 'noroom':
      showScreen('pvp');
      pvpStatus('No room with that code. Check the letters and try again.');
      break;
    case 'match':
      clearInterval(waitTimer);
      Net.role = msg.role;
      Net.opp = msg.opp;
      showVs(() => startPvP('online', msg.seed));
      break;
    case 'snap':
      if (isGuest() && pvp && !pvp.over) applySnap(msg);
      break;
    case 'cmd':
      if (mode === 'online' && Net.role === 'host' && pvp && !pvp.over) applyCmd(msg);
      break;
    case 'end':
      if (isGuest() && pvp && !pvp.over) finishPvp(swapSide(msg.w), msg.why);
      break;
    case 'gone':
      if (mode === 'online' && pvp && !pvp.over) {
        finishPvp(PLAYER, 'left');
      } else if (screenOpen === 'pvp-vs') {
        showScreen('pvp');
        pvpStatus('Your opponent left before the match started.');
      }
      break;
  }
}
// Our own connection dropped
function onNetLost() {
  if (mode === 'online' && pvp && !pvp.over) finishPvp(null, 'lost');
  else if (screenOpen === 'pvp-wait') { showScreen('pvp'); pvpStatus('Lost the connection to the server.'); }
}

// ---------- Screens ----------
function pvpStatus(text) { $('pvp-status').textContent = text || ''; }

function avatarHtml(name, side) {
  const letter = (name || '?').trim().charAt(0).toUpperCase() || '?';
  return `<div class="avatar" style="background:${SIDES[side].color};border-color:${SIDES[side].dark}">${letter}</div>`;
}

function openPvp() {
  if (!save.name) { save.name = 'Commander' + (100 + Math.floor(Math.random() * 900)); writeSave(); }
  refreshPvpCard();
  pvpStatus('');
  showScreen('pvp');
}
function refreshPvpCard() {
  $('pvp-name').value = save.name;
  const lg = leagueOf(save.trophies);
  $('pvp-trophies').textContent = save.trophies;
  $('pvp-league').textContent = `${lg.name} league · ${save.pvpWins} wins`;
  $('pvp-league').style.background = lg.color;
  $('pvp-avatar').outerHTML = avatarHtml(save.name, PLAYER).replace('class="avatar"', 'class="avatar" id="pvp-avatar"');
}

let waitTimer = 0;
async function findMatch(room = null) {
  clearInterval(waitTimer);
  showScreen('pvp-wait');
  $('wait-code').classList.add('hidden');
  $('wait-practice').classList.add('hidden');
  $('wait-text').textContent = 'Connecting…';
  const t0 = Date.now();
  waitTimer = setInterval(() => {
    const s = Math.floor((Date.now() - t0) / 1000);
    $('wait-time').textContent = fmtTime(s);
    // Nobody around? Offer a practice match (it's a bot, and it says so)
    if (s >= 20 && !room) $('wait-practice').classList.remove('hidden');
  }, 500);
  try {
    await Net.connect(text => { $('wait-text').textContent = text; });
  } catch (err) {
    clearInterval(waitTimer);
    showScreen('pvp');
    pvpStatus(err.message === 'old'
      ? 'This version of the game is too old for the server. Please update it.'
      : 'Can\'t reach the PvP server right now. Try 2 players on one phone, or practice against a bot.');
    return;
  }
  if (screenOpen !== 'pvp-wait') return; // cancelled while connecting
  if (room === 'create') Net.send({ t: 'room' });
  else if (room) Net.send({ t: 'join', code: room });
  else Net.send({ t: 'find' });
}
function cancelFind() {
  clearInterval(waitTimer);
  Net.send({ t: 'cancel' });
  openPvp();
}

// The "you vs them" card before an online match
function showVs(then) {
  const me = { name: save.name, trophies: save.trophies }, them = Net.opp || { name: 'Player', trophies: 0 };
  const card = (p, side) => `<div class="vs-card" style="--c:${SIDES[side].color};--d:${SIDES[side].dark}">
    ${avatarHtml(p.name, side)}<b>${escapeHtml(p.name)}</b><span>🏆 ${p.trophies} · ${leagueOf(p.trophies).name}</span></div>`;
  $('vs-row').innerHTML = card(me, PLAYER) + '<div class="vs">VS</div>' + card(them, 2);
  showScreen('pvp-vs');
  sfx('go');
  setTimeout(() => { if (screenOpen === 'pvp-vs') then(); }, 2200);
}
function escapeHtml(s) {
  return String(s).replace(/[&<>"']/g, c => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
}

// ---------- Starting a match ----------
function startPvP(kind, seed) {
  mode = kind;
  level = 0;
  sceneTheme = THEMES[seed % THEMES.length];
  state = 'play';
  loadTowers(genLevel(14, { pvp: true, seed }), 1000 + (seed % 997));
  // The guest's copy: their army (red on the host) shows as blue
  if (isGuest()) for (const t of towers) t.owner = swapSide(t.owner);
  aiSides = kind === 'practice' ? [{ side: 2, timer: 2.5, cfg: { think: 2.2, margin: 4, bold: 0.5 } }] : [];
  gameTime = 0; rally = 0; armed = null; shake = 0;
  stats = { captured: 0, lost: 0, killed: 0 };
  linksMade = 0; cutsMade = 0; handShown = false;
  charges = { strike: 0, rally: 0 };
  pvp = { kind, seed, snapT: 0, events: [], over: false, unitsById: new Map() };
  clearPointers();
  showScreen(null);
  $('hud').classList.remove('hidden');
  $('abilities').classList.add('hidden');
  $('speed-btn').classList.add('hidden');
  $('level-label').textContent = kind === 'duo' ? '2 Players' : kind === 'practice' ? 'Practice' : 'vs ' + (Net.opp?.name || 'Player');
  hintData = kind === 'duo' ? 'Blue plays from the bottom, red from the top. Drag from your own buildings!'
    : 'PvP: take every enemy building, or have the bigger army when the 3 minutes are up';
  hintTimer = 8;
  setHint(hintData);
  Music.track = 'boss';
  Music.start();
}

function pvpRestart() {
  if (!pvp) return openPvp();
  if (pvp.kind === 'online') { Net.leave(); findMatch(); }
  else startPvP(pvp.kind, Math.floor(Math.random() * 1e9));
}

// ---------- Host: send the battle, take the guest's moves ----------
function pvpEvent(e) {
  if (mode !== 'online' || !pvp || isGuest()) return;
  if (e[0] === 'cl' && pvp.events.length > 60) return;
  pvp.events.push(e);
}
function hostTick(dt) {
  if (!pvp || pvp.over) return;
  pvp.snapT -= dt;
  if (pvp.snapT > 0) return;
  pvp.snapT = SNAP_EVERY;
  Net.send({
    t: 'snap',
    tm: Math.round(gameTime * 100) / 100,
    tw: towers.map(t => [Math.round(t.units * 10), t.owner, t.roads.map(r => r.to.id)]),
    u: units.map(u => [u.id, u.from.id, u.to.id, Math.round(u.d), u.power, u.owner, Math.round(u.lane)]),
    ev: pvp.events.splice(0),
  });
}
function applyCmd(m) {
  const a = towers[m.a], b = towers[m.b];
  if (!a || !b || a.owner !== 2) return;
  if (m.c === 'link') tryLink(a, b, 2);
  else if (m.c === 'cut') {
    const i = a.roads.findIndex(r => r.to === b);
    if (i >= 0) cutRoad(a, i);
  }
}

// ---------- Guest: show what the host sends ----------
function applySnap(m) {
  const old = pvp.unitsById;
  // Effects first, while the soldiers they mention still exist here
  for (const e of m.ev || []) guestEvent(e, old);
  gameTime = m.tm;
  m.tw.forEach(([u10, owner, roadIds], i) => {
    const t = towers[i];
    if (!t) return;
    const side = swapSide(owner), n = u10 / 10;
    if (side === t.owner && n > t.units + 0.5) t.pop = 1;
    if (side === t.owner && n < t.units - 0.5) t.flash = 1;
    t.owner = side;
    t.units = n;
    t.roads = roadIds.map(id => t.roads.find(r => r.to.id === id) || { to: towers[id], timer: 0, born: gameTime });
  });
  const next = new Map();
  units = [];
  for (const [id, from, to, d, power, owner, lane] of m.u) {
    let u = old.get(id);
    if (!u) u = { id, from: towers[from], to: towers[to], lane: -lane, d };
    if (!u.from || !u.to) continue;
    // Keep the smooth local position unless it has drifted
    u.d = Math.abs(u.d - d) > 40 ? d : u.d + (d - u.d) * 0.5;
    u.power = power;
    u.owner = swapSide(owner);
    placeUnit(u);
    next.set(id, u);
    units.push(u);
  }
  pvp.unitsById = next;
}
function guestEvent(e, old) {
  if (e[0] === 'cap') {
    const t = towers[e[1]], side = swapSide(e[2]);
    if (!t) return;
    const was = t.owner;
    t.owner = side;
    R3D.capture(t.x, t.y, side);
    if (side === PLAYER) { stats.captured++; sfx('capture'); floatText(t, 'Captured!', SIDES[PLAYER].light); }
    else if (was === PLAYER) { stats.lost++; sfx('warn'); shake = Math.max(shake, 6); floatText(t, 'Lost!', SIDES[side].light); }
  } else if (e[0] === 'cl') {
    const a = old.get(e[1]), b = old.get(e[2]);
    const u = a || b;
    if (u) {
      if (a && b && (a.owner === PLAYER || b.owner === PLAYER)) stats.killed++;
      R3D.clash(u.x, u.y, a?.owner ?? 1, b?.owner ?? 2);
    }
  } else if (e[0] === 'sh') {
    const t = towers[e[1]], u = old.get(e[2]);
    if (t && u) {
      shells.push({ x1: t.x, y1: t.y, x2: u.x, y2: u.y, h: 50, time: 0.18, dur: 0.18 });
      R3D.muzzle(t, u.x, u.y);
      R3D.hit(u.x, u.y, u.owner);
    }
  }
}
function guestUpdate(dt) {
  gameTime += dt;
  for (const t of towers) {
    t.flash = Math.max(0, t.flash - dt * 3);
    t.pop = Math.max(0, t.pop - dt * 4);
  }
  // Soldiers keep marching between updates, so they move smoothly
  for (const u of units) {
    const L = dist(u.from, u.to);
    u.d = Math.min(u.d + unitSpeed(u) * dt, L - towerRadius(u.to) * 0.5);
    placeUnit(u);
  }
  updateEffects(dt);
  if (hintData) { hintTimer -= dt; if (hintTimer <= 0) { hintData = null; setHint(null); } }
}

// ---------- The end of a match ----------
function pvpCheckEnd() {
  if (!pvp || pvp.over || isGuest()) return;
  const blue = alive(1), red = alive(2);
  let winner = null, why = '';
  if (!blue || !red) winner = blue ? 1 : red ? 2 : 0;
  else if (gameTime >= PVP_TIME) {
    const tot = sideTotals();
    winner = tot[1] > tot[2] ? 1 : tot[2] > tot[1] ? 2 : 0;
    why = 'time';
  }
  if (winner === null) return;
  if (mode === 'online') Net.send({ t: 'end', w: winner, why });
  finishPvp(winner, why);
}

// winner: our side numbering (1 = us online), 0 = a draw, null = no result (connection lost)
function finishPvp(winner, why) {
  pvp.over = true;
  state = 'over';
  clearPointers();
  setHint(null);
  Music.stop();
  let trophies = 0;
  if (mode === 'online' && winner !== null) {
    if (winner === PLAYER) { trophies = WIN_TROPHIES; save.pvpWins++; }
    else if (winner !== 0) { trophies = -Math.min(LOSS_TROPHIES, save.trophies); save.pvpLosses++; }
    save.trophies += trophies;
    if (winner === PLAYER) save.coins += 20;
    writeSave();
  }
  const happy = mode === 'duo' || winner === PLAYER;
  sfx(happy ? 'win' : 'death');
  if (happy && winner) for (const t of towers) if (t.owner === winner) R3D.capture(t.x, t.y, winner);
  setTimeout(() => showPvpEnd(winner, why, trophies), 1100);
}

function showPvpEnd(winner, why, trophies) {
  const title = $('end-title');
  let text;
  if (mode === 'duo') text = winner === 1 ? 'Blue wins!' : winner === 2 ? 'Red wins!' : 'Draw!';
  else text = winner === PLAYER ? 'Victory!' : winner === 0 ? 'Draw!' : winner === null ? 'Disconnected' : 'Defeat';
  title.textContent = text;
  title.className = 'ribbon ' + (mode === 'duo' ? (winner === 2 ? 'red' : 'win') : winner === PLAYER ? 'win' : 'lose');
  $('end-why').textContent = {
    time: 'Time\'s up! The bigger army wins.',
    left: 'Your opponent left the match.',
    lost: 'The connection to the server was lost. No trophies were lost.',
  }[why] || (winner === PLAYER || mode === 'duo' ? 'Every enemy building taken!' : 'Your last building has fallen.');
  const tr = $('end-trophies');
  tr.classList.toggle('hidden', mode !== 'online' || winner === null);
  tr.innerHTML = `🏆 ${trophies >= 0 ? '+' : ''}${trophies} <small>${save.trophies} total</small>` + (trophies > 0 ? ' <span class="coin"></span> +20' : '');
  tr.className = 'trophy-change ' + (trophies > 0 ? 'up' : trophies < 0 ? 'down' : '') + (mode !== 'online' || winner === null ? ' hidden' : '');
  const lg = leagueOf(save.trophies);
  $('end-league').textContent = mode === 'online' ? `${lg.name} league` : mode === 'practice' ? 'Practice matches don\'t change your trophies' : '';
  $('again-btn').textContent = mode === 'online' ? 'Find a new match' : 'Play again';
  $('hud').classList.add('hidden');
  showScreen('pvp-end');
}

// ---------- Buttons ----------
$('pvp-btn').addEventListener('click', () => { Sfx.unlock(); openPvp(); });
$('pvp-name').addEventListener('change', () => {
  const name = $('pvp-name').value.replace(/[^\p{L}\p{N} _.-]/gu, '').trim().slice(0, 16);
  if (name) { save.name = name; writeSave(); }
  refreshPvpCard();
});
$('find-btn').addEventListener('click', () => { Sfx.unlock(); findMatch(); });
$('room-btn').addEventListener('click', () => findMatch('create'));
$('join-btn').addEventListener('click', () => {
  const code = $('code-input').value.toUpperCase().replace(/[^A-Z]/g, '');
  if (code.length !== 4) { pvpStatus('A room code has 4 letters.'); return; }
  findMatch(code);
});
$('duo-btn').addEventListener('click', () => { Sfx.unlock(); startPvP('duo', Math.floor(Math.random() * 1e9)); });
$('practice-btn').addEventListener('click', () => { Sfx.unlock(); startPvP('practice', Math.floor(Math.random() * 1e9)); });
$('wait-practice').addEventListener('click', () => { clearInterval(waitTimer); Net.send({ t: 'cancel' }); startPvP('practice', Math.floor(Math.random() * 1e9)); });
$('wait-cancel').addEventListener('click', cancelFind);
$('again-btn').addEventListener('click', pvpRestart);
$('end-pvp-btn').addEventListener('click', () => { if (mode === 'online') Net.leave(); openPvp(); });

// ---------- Start (this is the last script, so everything is loaded) ----------
if (!R3D.init(canvas, SIDES)) {
  document.body.innerHTML = '<p style="padding:24px;text-align:center">Tower Siege needs WebGL, which this browser doesn\'t support.</p>';
} else {
  resize();
  refreshMenu();
  requestAnimationFrame(frame);
}
