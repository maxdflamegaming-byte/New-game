'use strict';

// Tower Siege server: PvP matches, trophies, the leaderboard and clans.
// - Accounts: each phone gets an id and a secret token the first time it connects. The server
//   keeps the trophies, so they can't just be typed in.
// - PvP: pairs players (quick match by trophies, or a 4-letter friend code) and passes messages
//   between the two. One player, the host, runs the battle and sends what's happening; the other,
//   the guest, sends its moves. When the host reports the result, the server updates trophies.
// - Leaderboard: the top players and clans. Clans: create, search, join, leave, and the leader
//   can remove members. A clan's trophies are its members' trophies added up.
// Players and clans are saved with store.js (Postgres when DATABASE_URL is set, else a file).
//   node server.js            (listens on $PORT, or 8090)
const http = require('http');
const crypto = require('crypto');
const { WebSocketServer } = require('ws');
const { openStore } = require('./store');

const PROTOCOL = 2;
const PORT = Number(process.env.PORT) || 8090;
const WIN = 30, LOSS = 15, MAX_START_TROPHIES = 300;
const CLAN_SIZE = 25, TOP = 50;
const EMBLEMS = ['🦁', '🐺', '🦅', '🐉', '🦈', '🐻', '⚡', '🔥', '❄️', '🌟', '🚀', '🛡️', '⚔️', '👑', '🍀', '💎'];
const COLORS = ['#3d9bff', '#ff5257', '#ffc21f', '#45d35a', '#a66bff', '#ff8a3d', '#2ec3e0', '#ff6fb5'];

const clean = (s, max) => String(s || '').replace(/[^\p{L}\p{N} _.-]/gu, '').replace(/\s+/g, ' ').trim().slice(0, max);
const hash = s => crypto.createHash('sha256').update(s).digest('hex');
const newId = () => crypto.randomBytes(6).toString('hex');

let store;
const players = new Map();   // id -> { id, tokenHash, name, trophies, wins, losses, clan, created }
const clans = new Map();     // id -> { id, name, tag, emblem, color, leader, members: [ids], created }

const savePlayer = p => store.set('p:' + p.id, p);
const saveClan = c => store.set('c:' + c.id, c);

// ---------- Players ----------
function publicPlayer(p) {
  const c = p.clan && clans.get(p.clan);
  return { id: p.id, name: p.name, trophies: p.trophies, wins: p.wins, losses: p.losses, clan: c ? clanSummary(c) : null };
}
const tagOf = p => (p.clan && clans.get(p.clan)?.tag) || '';

function login(msg) {
  let p = players.get(String(msg.id || ''));
  if (p && p.tokenHash === hash(String(msg.token || ''))) return { p };
  // A new account; a phone that played before this server keeps a little of what it had
  const token = crypto.randomBytes(18).toString('hex');
  p = {
    id: newId(), tokenHash: hash(token), name: clean(msg.name, 16) || 'Player',
    trophies: Math.max(0, Math.min(MAX_START_TROPHIES, Math.floor(Number(msg.trophies) || 0))),
    wins: 0, losses: 0, clan: null, created: Date.now(),
  };
  players.set(p.id, p);
  savePlayer(p);
  return { p, token };
}

// ---------- Clans ----------
const clanTrophies = c => c.members.reduce((a, id) => a + (players.get(id)?.trophies || 0), 0);
function clanSummary(c) {
  return { id: c.id, name: c.name, tag: c.tag, emblem: c.emblem, color: c.color, members: c.members.length, trophies: clanTrophies(c) };
}
function clanDetails(c) {
  const members = c.members.map(id => players.get(id)).filter(Boolean)
    .map(p => ({ id: p.id, name: p.name, trophies: p.trophies, leader: p.id === c.leader }))
    .sort((a, b) => b.trophies - a.trophies);
  return { ...clanSummary(c), leader: c.leader, list: members };
}
function leaveClan(p) {
  const c = p.clan && clans.get(p.clan);
  p.clan = null;
  savePlayer(p);
  if (!c) return;
  c.members = c.members.filter(id => id !== p.id);
  if (!c.members.length) { clans.delete(c.id); store.del('c:' + c.id); return; }
  // The member with the most trophies takes over
  if (c.leader === p.id) c.leader = c.members.slice().sort((a, b) => (players.get(b)?.trophies || 0) - (players.get(a)?.trophies || 0))[0];
  saveClan(c);
}

// ---------- Leaderboard (cached for a few seconds; it sorts everyone) ----------
let topCache = null, topAt = 0;
function top() {
  if (topCache && Date.now() - topAt < 5000) return topCache;
  const ranked = [...players.values()].filter(p => p.wins + p.losses > 0 || p.trophies > 0).sort((a, b) => b.trophies - a.trophies || a.created - b.created);
  const rank = new Map(ranked.map((p, i) => [p.id, i + 1]));
  topCache = {
    rank,
    players: ranked.slice(0, TOP).map(p => ({ id: p.id, name: p.name, tag: tagOf(p), trophies: p.trophies })),
    clans: [...clans.values()].map(clanSummary).sort((a, b) => b.trophies - a.trophies).slice(0, TOP),
  };
  topAt = Date.now();
  return topCache;
}
const dirtyTop = () => { topCache = null; };

// ---------- Matches ----------
const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain', 'Access-Control-Allow-Origin': '*' });
  res.end(`Tower Siege server, protocol ${PROTOCOL}. ${wss.clients.size} connected, ${players.size} players, ${clans.size} clans.\n`);
});
const wss = new WebSocketServer({ server, maxPayload: 256 * 1024 });

let queue = [];              // players looking for a quick match
const rooms = new Map();     // friend code -> the player who made it
let matches = 0;

const send = (ws, msg) => { if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg)); };
const info = ws => ({ name: ws.player.name, trophies: ws.player.trophies, tag: tagOf(ws.player) });

function unqueue(ws) {
  queue = queue.filter(q => q !== ws);
  for (const [code, host] of rooms) if (host === ws) rooms.delete(code);
}

function pair(host, guest) {
  unqueue(host);
  unqueue(guest);
  const match = { host, guest, done: false };
  host.peer = guest; guest.peer = host;
  host.match = guest.match = match;
  const seed = Math.floor(Math.random() * 1e9);
  send(host, { t: 'match', role: 'host', seed, opp: info(guest) });
  send(guest, { t: 'match', role: 'guest', seed, opp: info(host) });
  matches++;
}

// Record a result: winner is 'host', 'guest' or null for a draw
function settle(match, winner, why) {
  if (match.done) return;
  match.done = true;
  const sides = { host: match.host, guest: match.guest };
  for (const [role, ws] of Object.entries(sides)) {
    const p = ws.player;
    let delta = 0;
    if (winner === role) { delta = WIN; p.wins++; }
    else if (winner) { delta = -Math.min(LOSS, p.trophies); p.losses++; }
    p.trophies += delta;
    savePlayer(p);
    send(ws, { t: 'result', delta, why, you: publicPlayer(p) });
  }
  dirtyTop();
}

// This player is done with the match. Leaving one that isn't over counts as a loss.
function unpair(ws) {
  const peer = ws.peer, match = ws.match;
  ws.peer = null; ws.match = null;
  if (peer && peer.peer === ws) {
    peer.peer = null; peer.match = null;
    if (match && !match.done) send(peer, { t: 'gone' });
  }
  if (match && !match.done) settle(match, match.host === ws ? 'guest' : 'host', 'left');
}

function newCode() {
  const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  for (;;) {
    let code = '';
    for (let i = 0; i < 4; i++) code += letters[Math.floor(Math.random() * letters.length)];
    if (!rooms.has(code)) return code;
  }
}

// ---------- Messages ----------
wss.on('connection', ws => {
  ws.player = null;
  ws.peer = null;
  ws.match = null;
  ws.alive = true;
  ws.lastChange = 0;
  ws.on('pong', () => { ws.alive = true; });

  ws.on('message', (data, isBinary) => {
    if (isBinary) return;
    const text = data.toString();
    let msg;
    try { msg = JSON.parse(text); } catch { return; }
    if (!msg || typeof msg.t !== 'string') return;
    if (msg.t === 'hello') return hello(ws, msg);
    if (!ws.player) return;
    const p = ws.player;

    // Battle messages go straight to the other player
    if (msg.t === 'snap' || msg.t === 'cmd') {
      if (ws.peer && ws.peer.readyState === ws.OPEN) ws.peer.send(text);
      return;
    }
    // Only the host says who won (it runs the battle)
    if (msg.t === 'end') {
      const match = ws.match;
      if (!match || match.host !== ws) return;
      const peer = ws.peer;
      if (peer) {
        if (peer.readyState === peer.OPEN) peer.send(text);
        peer.peer = null; peer.match = null;
      }
      ws.peer = null; ws.match = null;
      settle(match, msg.w === 1 ? 'host' : msg.w === 2 ? 'guest' : null, String(msg.why || '').slice(0, 10));
      return;
    }

    // Changes to names and clans: at most one every half second
    const changes = ['name', 'mkclan', 'joinclan', 'leaveclan', 'kick'];
    if (changes.includes(msg.t)) {
      if (Date.now() - ws.lastChange < 500) return send(ws, { t: 'clanerr', msg: 'Slow down a little.' });
      ws.lastChange = Date.now();
    }

    switch (msg.t) {
      case 'find': {
        if (ws.peer) return;
        unqueue(ws);
        // The closest trophy count wins; anyone will do (but never yourself in another tab)
        const opp = queue.filter(q => q.readyState === q.OPEN && q.player.id !== p.id)
          .sort((a, b) => Math.abs(a.player.trophies - p.trophies) - Math.abs(b.player.trophies - p.trophies))[0];
        if (opp) pair(opp, ws);
        else { queue.push(ws); send(ws, { t: 'waiting' }); }
        break;
      }
      case 'room': {
        if (ws.peer) return;
        unqueue(ws);
        const code = newCode();
        rooms.set(code, ws);
        send(ws, { t: 'room', code });
        break;
      }
      case 'join': {
        if (ws.peer) return;
        const host = rooms.get(String(msg.code || '').toUpperCase().trim());
        if (!host || host === ws || host.readyState !== host.OPEN || host.player.id === p.id) { send(ws, { t: 'noroom' }); return; }
        pair(host, ws);
        break;
      }
      case 'cancel':
        unqueue(ws);
        break;
      case 'leave':
        unqueue(ws);
        unpair(ws);
        break;

      case 'name': {
        const name = clean(msg.name, 16);
        if (name) { p.name = name; savePlayer(p); dirtyTop(); }
        send(ws, { t: 'me', you: publicPlayer(p) });
        break;
      }
      case 'whoami':
        send(ws, { t: 'me', you: publicPlayer(p) });
        break;
      case 'top': {
        const t = top();
        send(ws, { t: 'top', players: t.players, clans: t.clans, rank: t.rank.get(p.id) || 0, you: publicPlayer(p) });
        break;
      }
      case 'clans': {
        const q = clean(msg.q, 20).toLowerCase();
        let list = [...clans.values()];
        if (q) list = list.filter(c => c.name.toLowerCase().includes(q) || c.tag.toLowerCase() === q);
        send(ws, { t: 'clans', list: list.map(clanSummary).sort((a, b) => b.trophies - a.trophies).slice(0, TOP) });
        break;
      }
      case 'clan': {
        const c = clans.get(String(msg.id || ''));
        if (!c) return send(ws, { t: 'clanerr', msg: 'That clan doesn\'t exist any more.' });
        send(ws, { t: 'clan', clan: clanDetails(c) });
        break;
      }
      case 'mkclan': {
        if (p.clan && clans.has(p.clan)) return send(ws, { t: 'clanerr', msg: 'Leave your clan first.' });
        const name = clean(msg.name, 20), tag = clean(msg.tag, 4).toUpperCase().replace(/[^A-Z0-9]/g, '');
        if (name.length < 3) return send(ws, { t: 'clanerr', msg: 'A clan name needs at least 3 letters.' });
        if (tag.length < 2) return send(ws, { t: 'clanerr', msg: 'A clan tag needs 2 to 4 letters or numbers.' });
        if ([...clans.values()].some(c => c.tag === tag)) return send(ws, { t: 'clanerr', msg: `The tag [${tag}] is taken. Try another.` });
        if ([...clans.values()].some(c => c.name.toLowerCase() === name.toLowerCase())) return send(ws, { t: 'clanerr', msg: 'A clan with that name already exists.' });
        const c = {
          id: newId(), name, tag,
          emblem: EMBLEMS.includes(msg.emblem) ? msg.emblem : EMBLEMS[0],
          color: COLORS.includes(msg.color) ? msg.color : COLORS[0],
          leader: p.id, members: [p.id], created: Date.now(),
        };
        clans.set(c.id, c);
        saveClan(c);
        p.clan = c.id;
        savePlayer(p);
        dirtyTop();
        send(ws, { t: 'clan', clan: clanDetails(c), you: publicPlayer(p) });
        break;
      }
      case 'joinclan': {
        const c = clans.get(String(msg.id || ''));
        if (!c) return send(ws, { t: 'clanerr', msg: 'That clan doesn\'t exist any more.' });
        if (p.clan === c.id) return send(ws, { t: 'clan', clan: clanDetails(c), you: publicPlayer(p) });
        if (c.members.length >= CLAN_SIZE) return send(ws, { t: 'clanerr', msg: 'That clan is full.' });
        if (p.clan) leaveClan(p);
        c.members.push(p.id);
        saveClan(c);
        p.clan = c.id;
        savePlayer(p);
        dirtyTop();
        send(ws, { t: 'clan', clan: clanDetails(c), you: publicPlayer(p) });
        break;
      }
      case 'leaveclan':
        leaveClan(p);
        dirtyTop();
        send(ws, { t: 'me', you: publicPlayer(p) });
        break;
      case 'kick': {
        const c = p.clan && clans.get(p.clan);
        const target = players.get(String(msg.id || ''));
        if (!c || c.leader !== p.id || !target || target.clan !== c.id || target.id === p.id) return send(ws, { t: 'clanerr', msg: 'Only the leader can remove members.' });
        leaveClan(target);
        dirtyTop();
        send(ws, { t: 'clan', clan: clanDetails(c), you: publicPlayer(p) });
        break;
      }
    }
  });

  ws.on('close', () => {
    unqueue(ws);
    unpair(ws);
  });
});

function hello(ws, msg) {
  if (msg.v !== PROTOCOL) { send(ws, { t: 'old', v: PROTOCOL }); return; }
  if (ws.player) return;
  const { p, token } = login(msg);
  // A name typed while offline is kept
  const name = clean(msg.name, 16);
  if (name && name !== p.name) { p.name = name; savePlayer(p); }
  ws.player = p;
  send(ws, { t: 'welcome', online: wss.clients.size, you: publicPlayer(p), token });
}

// Drop connections that stopped answering
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.alive) { ws.terminate(); continue; }
    ws.alive = false;
    ws.ping();
  }
}, 30000).unref();

setInterval(() => {
  console.log(`[server] ${wss.clients.size} connected, ${queue.length} waiting, ${rooms.size} rooms, ${matches} matches, ${players.size} players, ${clans.size} clans`);
}, 60000).unref();

async function start() {
  store = await openStore();
  for (const [k, v] of store.all) {
    if (k.startsWith('p:')) players.set(v.id, v);
    else if (k.startsWith('c:')) clans.set(v.id, v);
  }
  server.listen(PORT, () => console.log(`[server] Tower Siege server on port ${PORT}, protocol ${PROTOCOL}, ${store.kind} storage, ${players.size} players, ${clans.size} clans`));
}

// Save everything before the host stops the server
for (const sig of ['SIGTERM', 'SIGINT']) {
  process.on(sig, async () => {
    try { await store?.close(); } catch { /* exiting anyway */ }
    process.exit(0);
  });
}

if (require.main === module) start().catch(err => { console.error(err); process.exit(1); });
module.exports = { start };
