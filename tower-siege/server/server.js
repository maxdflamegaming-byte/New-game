'use strict';

// Tower Siege PvP server. It pairs players into 1-vs-1 matches (quick match by trophies, or a
// friend code) and passes messages between the two. One player, the host, runs the battle and
// sends what's happening about 10 times a second; the other, the guest, sends its moves.
// The server keeps nothing after a match ends.
//   node server.js            (listens on $PORT, or 8090)
const http = require('http');
const { WebSocketServer } = require('ws');

const PROTOCOL = 1;
const PORT = Number(process.env.PORT) || 8090;
const RELAY = new Set(['snap', 'cmd', 'end', 'emote']);

const server = http.createServer((req, res) => {
  res.writeHead(200, { 'Content-Type': 'text/plain', 'Access-Control-Allow-Origin': '*' });
  res.end(`Tower Siege server, protocol ${PROTOCOL}. ${wss.clients.size} connected.\n`);
});
const wss = new WebSocketServer({ server, maxPayload: 256 * 1024 });

let queue = [];              // players looking for a quick match
const rooms = new Map();     // friend code -> the player who made it

const send = (ws, msg) => { if (ws.readyState === ws.OPEN) ws.send(JSON.stringify(msg)); };
const info = ws => ({ name: ws.name, trophies: ws.trophies });

function unqueue(ws) {
  queue = queue.filter(q => q !== ws);
  for (const [code, host] of rooms) if (host === ws) rooms.delete(code);
}

function pair(host, guest) {
  unqueue(host);
  unqueue(guest);
  host.peer = guest;
  guest.peer = host;
  const seed = Math.floor(Math.random() * 1e9);
  send(host, { t: 'match', role: 'host', seed, opp: info(guest) });
  send(guest, { t: 'match', role: 'guest', seed, opp: info(host) });
  matches++;
}

// The match is over for this player; tell the other one if they're still there
function unpair(ws, why = 'gone') {
  const peer = ws.peer;
  ws.peer = null;
  if (peer && peer.peer === ws) {
    peer.peer = null;
    send(peer, { t: why });
  }
}

function newCode() {
  const letters = 'ABCDEFGHJKLMNPQRSTUVWXYZ';
  for (;;) {
    let code = '';
    for (let i = 0; i < 4; i++) code += letters[Math.floor(Math.random() * letters.length)];
    if (!rooms.has(code)) return code;
  }
}

let matches = 0;
wss.on('connection', ws => {
  ws.name = 'Player';
  ws.trophies = 0;
  ws.peer = null;
  ws.alive = true;
  ws.on('pong', () => { ws.alive = true; });

  ws.on('message', (data, isBinary) => {
    if (isBinary) return;
    const text = data.toString();
    let msg;
    try { msg = JSON.parse(text); } catch { return; }
    if (!msg || typeof msg.t !== 'string') return;

    // Battle messages go straight to the other player, untouched
    if (RELAY.has(msg.t)) {
      if (ws.peer && ws.peer.readyState === ws.OPEN) ws.peer.send(text);
      if (msg.t === 'end') unpair(ws, 'over');
      return;
    }
    switch (msg.t) {
      case 'hello':
        if (msg.v !== PROTOCOL) { send(ws, { t: 'old', v: PROTOCOL }); return; }
        ws.name = String(msg.name || 'Player').replace(/[^\p{L}\p{N} _.-]/gu, '').slice(0, 16) || 'Player';
        ws.trophies = Math.max(0, Math.min(99999, Math.floor(Number(msg.trophies) || 0)));
        send(ws, { t: 'welcome', online: wss.clients.size });
        break;
      case 'find': {
        if (ws.peer) return;
        unqueue(ws);
        // The closest trophy count wins; anyone will do
        const opp = queue.filter(q => q.readyState === q.OPEN)
          .sort((a, b) => Math.abs(a.trophies - ws.trophies) - Math.abs(b.trophies - ws.trophies))[0];
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
        const code = String(msg.code || '').toUpperCase().trim();
        const host = rooms.get(code);
        if (!host || host === ws || host.readyState !== host.OPEN) { send(ws, { t: 'noroom' }); return; }
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
    }
  });

  ws.on('close', () => {
    unqueue(ws);
    unpair(ws);
  });
});

// Drop connections that stopped answering
setInterval(() => {
  for (const ws of wss.clients) {
    if (!ws.alive) { ws.terminate(); continue; }
    ws.alive = false;
    ws.ping();
  }
}, 30000).unref();

setInterval(() => {
  console.log(`[server] ${wss.clients.size} connected, ${queue.length} waiting, ${rooms.size} rooms, ${matches} matches so far`);
}, 60000).unref();

server.listen(PORT, () => console.log(`[server] Tower Siege server on port ${PORT}, protocol ${PROTOCOL}`));
