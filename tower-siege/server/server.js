'use strict';

// Tower Siege server: PvP matches, trophies, the leaderboard and clans.
// - Accounts: each phone gets an id and a secret token the first time it connects. The server
//   keeps the trophies, so they can't just be typed in.
// - PvP: pairs players (quick match by trophies, or a 4-letter friend code) and passes messages
//   between the two. One player, the host, runs the battle and sends what's happening; the other,
//   the guest, sends its moves. When the host reports the result, the server updates trophies.
//   If a player's connection drops mid-match, the match waits up to 15 seconds for them to
//   come back (the other player is told to wait); after that, the one who stayed wins.
// - Leaderboard: the top players and clans. Clans: create, search, join, leave, and the leader
//   can remove members. A clan's trophies are its members' trophies added up.
// Players and clans are saved with store.js (Postgres when DATABASE_URL is set, else a file).
//   node server.js            (listens on $PORT, or 8090)
const http = require('http');
const crypto = require('crypto');
const { WebSocketServer } = require('ws');
const { openStore } = require('./store');

const PROTOCOL = 4;
const PORT = Number(process.env.PORT) || 8090;
const GRACE_MS = Number(process.env.RECONNECT_MS) || 15000; // how long a match waits for a dropped player
const WIN = 30, LOSS = 15;
const CONFIRM_MS = Number(process.env.CONFIRM_MS) || 8000; // how long a result waits for the other player's word
const PAIR_LIMIT = 3;        // trophies change for the same two players at most this many times a day
const CLAN_SIZE = 25, TOP = 50;
const EMBLEMS = ['🦁', '🐺', '🦅', '🐉', '🦈', '🐻', '⚡', '🔥', '❄️', '🌟', '🚀', '🛡️', '⚔️', '👑', '🍀', '💎'];
const COLORS = ['#3d9bff', '#ff5257', '#ffc21f', '#45d35a', '#a66bff', '#ff8a3d', '#2ec3e0', '#ff6fb5'];

const clean = (s, max) => String(s || '').replace(/[^\p{L}\p{N} _.-]/gu, '').replace(/\s+/g, ' ').trim().slice(0, max);
const hash = s => crypto.createHash('sha256').update(s).digest('hex');

// Names everyone can see (players and clans) can't contain these. Names are checked with
// spaces, dots and accents taken out and look-alike digits read as letters ("f.u.c.k",
// "sh1t"). Only words that don't hide inside ordinary ones are listed.
const BANNED = [
  // English
  'fuck', 'shit', 'bitch', 'cunt', 'nigger', 'nigga', 'faggot', 'whore', 'slut', 'pussy', 'bastard',
  'retard', 'penis', 'vagina', 'porn', 'rapist', 'hitler', 'wanker', 'motherf',
  // Spanish and Portuguese
  'hijodeputa', 'putamadre', 'mierda', 'pendejo', 'cabron', 'gilipollas', 'caralho', 'buceta', 'foder', 'merda', 'viado', 'arrombado',
  // Hindi (in Latin letters)
  'chutiya', 'chutia', 'madarchod', 'bhenchod', 'behenchod', 'bhosdi', 'lavda',
  // Indonesian
  'bangsat', 'kontol', 'memek', 'ngentot', 'bajingan', 'jancok',
  // Russian
  'хуй', 'хуе', 'пизд', 'блять', 'бляд', 'ебан', 'ебат', 'сука', 'мудак', 'пидор', 'гандон',
  // Turkish
  'orospu', 'siktir', 'sikerim', 'yarrak', 'amcik', 'pezevenk',
];
const fold = s => String(s).toLowerCase().normalize('NFKD').replace(/[\u0300-\u036f]/g, '')
  .replace(/[\s_.-]/g, '').replace(/0/g, 'o').replace(/1/g, 'i').replace(/3/g, 'e').replace(/4/g, 'a').replace(/5/g, 's').replace(/7/g, 't');
const rude = s => { const f = fold(s); return BANNED.some(w => f.includes(w)); };
// A name as it's kept: cleaned, and '' if it's rude
const allowedName = (s, max = 16) => { const n = clean(s, max); return n && !rude(n) ? n : ''; };
const REPORTS = 3;           // different players reporting a name before it's replaced
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

// New accounts from one address: a phone network shares one address between many people,
// so the limit is generous; it stops a script making thousands
const NEW_PER_HOUR = Number(process.env.NEW_PER_HOUR) || 30;
const made = new Map();       // address -> times accounts were made in the last hour
function login(msg, ip) {
  let p = players.get(String(msg.id || ''));
  if (p && p.tokenHash === hash(String(msg.token || ''))) {
    p.seen = Date.now();
    return { p };
  }
  const now = Date.now();
  const recent = (made.get(ip) || []).filter(t => now - t < 3600e3);
  if (recent.length >= NEW_PER_HOUR) return {};
  recent.push(now);
  made.set(ip, recent);
  // A new account starts at 0 trophies (what the phone says it had isn't trusted)
  const token = crypto.randomBytes(18).toString('hex');
  p = {
    id: newId(), tokenHash: hash(token), name: allowedName(msg.name) || 'Player',
    trophies: 0, wins: 0, losses: 0, clan: null, created: now, seen: now,
  };
  players.set(p.id, p);
  savePlayer(p);
  return { p, token };
}
setInterval(() => {
  const now = Date.now();
  for (const [ip, list] of made) if (list.every(t => now - t >= 3600e3)) made.delete(ip);
}, 600e3).unref();

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
  // Only players who have finished a match
  const ranked = [...players.values()].filter(p => p.wins + p.losses > 0).sort((a, b) => b.trophies - a.trophies || a.created - b.created);
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
const away = new Map();      // player id -> { match, role } for players whose connection dropped mid-match

const send = (ws, msg) => { if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg)); };
const info = ws => ({ name: ws.player.name, trophies: ws.player.trophies, tag: tagOf(ws.player) });

function unqueue(ws) {
  queue = queue.filter(q => q !== ws);
  for (const [code, host] of rooms) if (host === ws) rooms.delete(code);
}

function pair(host, guest) {
  unqueue(host);
  unqueue(guest);
  const seed = Math.floor(Math.random() * 1e9);
  const match = { host, guest, done: false, seed, timers: {}, claims: {} };
  host.peer = guest; guest.peer = host;
  host.match = guest.match = match;
  send(host, { t: 'match', role: 'host', seed, opp: info(guest) });
  send(guest, { t: 'match', role: 'guest', seed, opp: info(host) });
  matches++;
}

// ---------- Results ----------
// Both players say who won, each from its own copy of the battle (the host runs it; the guest
// sees it through the host's updates, and gets a full one just before the result). Trophies
// only change when they agree, so a changed app that just claims a win gets a draw.
const other = role => (role === 'host' ? 'guest' : 'host');
function claim(match, role, winner, why) {
  if (match.done || match.claims[role]) return;
  match.claims[role] = { winner, why };
  if (match.claims[other(role)]) return decide(match);
  // Wait for the other side's word; if it has gone, this one stands
  match.confirmTimer = setTimeout(() => decide(match), CONFIRM_MS);
}
function decide(match) {
  clearTimeout(match.confirmTimer);
  if (match.done) return;
  const h = match.claims.host, g = match.claims.guest;
  if (h && g) return h.winner === g.winner && h.winner !== 'none' ? settle(match, h.winner, h.why || g.why) : settle(match, null, 'dispute');
  const only = h || g;
  if (only.winner === 'none') return settle(match, null, 'dispute');
  const ws = match[h ? 'guest' : 'host'];
  // Still connected but said nothing (or nothing that makes sense): no trophies change
  if (ws.readyState === ws.OPEN) return settle(match, null, 'dispute');
  settle(match, only.winner, only.why);
}

// The same two players only win and lose trophies against each other a few times a day
// (so two accounts can't feed each other trophies)
const pairs = new Map();      // "id1|id2" -> { day, n }
function pairCounts(a, b) {
  const key = [a.id, b.id].sort().join('|'), day = Math.floor(Date.now() / 864e5);
  const e = pairs.get(key);
  if (!e || e.day !== day) { pairs.set(key, { day, n: 1 }); return true; }
  e.n++;
  return e.n <= PAIR_LIMIT;
}
setInterval(() => {
  const day = Math.floor(Date.now() / 864e5);
  for (const [k, e] of pairs) if (e.day !== day) pairs.delete(k);
}, 3600e3).unref();

// Record a result: winner is 'host', 'guest' or null for a draw
function settle(match, winner, why) {
  if (match.done) return;
  match.done = true;
  clearTimeout(match.confirmTimer);
  if (why === 'dispute') {
    for (const ws of [match.host, match.guest]) ws.player.disputes = (ws.player.disputes || 0) + 1;
    console.log(`[server] disputed result: ${match.host.player.id} vs ${match.guest.player.id}`);
  }
  if (winner && !pairCounts(match.host.player, match.guest.player)) { winner = null; why = 'again'; }
  for (const role of Object.keys(match.timers)) {
    clearTimeout(match.timers[role]);
    if (away.get(match[role].player.id)?.match === match) away.delete(match[role].player.id);
  }
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

// The connection dropped mid-match: keep the match for a while, and tell the other player to wait
function hold(ws) {
  const match = ws.match, peer = ws.peer;
  const role = match.host === ws ? 'host' : 'guest';
  ws.peer = null; ws.match = null;
  away.set(ws.player.id, { match, role });
  send(peer, { t: 'wait', secs: Math.round(GRACE_MS / 1000) });
  match.timers[role] = setTimeout(() => forfeit(match, role), GRACE_MS);
}

// They didn't come back in time (or came back without the match): the other player wins
function forfeit(match, role) {
  if (match.done) return;
  const other = match[role === 'host' ? 'guest' : 'host'];
  if (other.match === match) {
    other.peer = null; other.match = null;
    send(other, { t: 'gone' });
  }
  settle(match, role === 'host' ? 'guest' : 'host', 'left');
}

// A player who dropped out of a match is back: put them back in it
function rejoin(ws) {
  const a = away.get(ws.player.id);
  if (!a || a.match.done) { send(ws, { t: 'resume', ok: false }); return; }
  away.delete(ws.player.id);
  const { match, role } = a;
  clearTimeout(match.timers[role]);
  delete match.timers[role];
  match[role] = ws;
  ws.match = match;
  const peer = match[role === 'host' ? 'guest' : 'host'];
  ws.peer = peer;
  if (peer.match === match) {
    peer.peer = ws;
    send(peer, { t: 'back' });
  }
  send(ws, { t: 'resume', ok: true, role, seed: match.seed, opp: info(peer) });
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
wss.on('connection', (ws, req) => {
  // Behind the host's proxy, the phone's address is the first one it forwards
  ws.ip = String(req.headers['x-forwarded-for'] || '').split(',')[0].trim() || req.socket.remoteAddress || '';
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
    // Who won, from each side's point of view: w 1 = me, 2 = the other player, 0 = a draw,
    // anything else = the battle isn't over as far as I can see
    if (msg.t === 'end') {
      const match = ws.match || ws.ending;
      if (!match || match.done) return;
      const role = match.host === ws ? 'host' : match.guest === ws ? 'guest' : null;
      if (!role) return;
      const w = Number(msg.w);
      const winner = w === 1 ? role : w === 2 ? other(role) : w === 0 ? null : 'none';
      const why = String(msg.why || '').slice(0, 10);
      if (role === 'host') {
        // The host ran the battle: the guest hears the result (and answers with its own word)
        const peer = ws.peer;
        if (peer) {
          if (peer.readyState === peer.OPEN) peer.send(JSON.stringify({ t: 'end', w: msg.w, why }));
          peer.peer = null; peer.match = null; peer.ending = match;
        }
      }
      ws.peer = null; ws.match = null; ws.ending = match;
      claim(match, role, winner, why);
      return;
    }

    // Changes to names and clans: at most one every half second
    const changes = ['name', 'mkclan', 'joinclan', 'leaveclan', 'kick', 'report'];
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
        if (name && rude(name)) return send(ws, { t: 'me', you: publicPlayer(p), rude: true });
        if (name) { p.name = name; savePlayer(p); dirtyTop(); }
        send(ws, { t: 'me', you: publicPlayer(p) });
        break;
      }
      case 'report': {
        // A player's or clan's name someone finds offensive. Once 3 different players (who have
        // played a match, so new accounts can't gang up) report it, it's replaced.
        const isClan = msg.kind === 'clan';
        const target = isClan ? clans.get(String(msg.id || '')) : players.get(String(msg.id || ''));
        if (target && target.id !== p.id && p.wins + p.losses > 0) {
          target.reports = target.reports || [];
          if (!target.reports.includes(p.id)) target.reports.push(p.id);
          if (target.reports.length >= REPORTS) {
            target.reports = [];
            if (isClan) {
              target.name = 'Clan ' + target.id.slice(0, 4);
              target.tag = 'C' + target.id.slice(0, 3).toUpperCase();
            } else target.name = 'Player ' + target.id.slice(0, 4);
            console.log(`[server] reported ${isClan ? 'clan' : 'player'} ${target.id} renamed`);
            dirtyTop();
          }
          if (isClan) saveClan(target); else savePlayer(target);
        }
        send(ws, { t: 'reported' });
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
        if (rude(name) || rude(tag)) return send(ws, { t: 'clanerr', msg: 'Please pick a friendlier name.' });
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
    if (ws.match && !ws.match.done && ws.player) hold(ws);
    else unpair(ws);
  });
});

function hello(ws, msg) {
  if (msg.v !== PROTOCOL) { send(ws, { t: 'old', v: PROTOCOL }); return; }
  if (ws.player) return;
  const { p, token } = login(msg, ws.ip);
  if (!p) { send(ws, { t: 'busy' }); ws.close(); return; }
  // A name typed while offline is kept
  const name = allowedName(msg.name);
  if (name && name !== p.name) { p.name = name; savePlayer(p); }
  ws.player = p;
  send(ws, { t: 'welcome', online: wss.clients.size, you: publicPlayer(p), token });
  if (msg.back) {
    // Back after a drop the server hasn't noticed yet (a phone switching from Wi-Fi to mobile
    // data leaves its old connection hanging): keep that match's place and take it over
    for (const c of wss.clients) {
      if (c !== ws && c.player && c.player.id === p.id && c.match && !c.match.done) {
        hold(c);
        c.terminate();
      }
    }
    rejoin(ws);
  } else if (away.has(p.id)) forfeit(away.get(p.id).match, away.get(p.id).role); // a fresh start: that match is lost
}

// Drop connections that stopped answering
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.alive) { ws.terminate(); continue; }
    ws.alive = false;
    ws.ping();
  }
}, 10000).unref();

setInterval(() => {
  console.log(`[server] ${wss.clients.size} connected, ${queue.length} waiting, ${rooms.size} rooms, ${matches} matches, ${players.size} players, ${clans.size} clans`);
}, 60000).unref();

async function start() {
  store = await openStore();
  for (const [k, v] of store.all) {
    if (k.startsWith('p:')) players.set(v.id, v);
    else if (k.startsWith('c:')) clans.set(v.id, v);
  }
  // Forget accounts that never finished a match and haven't been back for 30 days
  const old = Date.now() - 30 * 864e5;
  for (const p of [...players.values()]) {
    if (p.wins + p.losses === 0 && !p.clan && (p.seen || p.created || 0) < old) {
      players.delete(p.id);
      store.del('p:' + p.id);
    }
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
