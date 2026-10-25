// Tower Siege server, without browsers: matching, the old-version check, and what happens when a
// player's connection drops mid-match (the other is told to wait; coming back resumes the match;
// not coming back in time, or starting afresh, loses it). Then the safeguards: results count only
// when both players agree, the same two players can't farm trophies, new accounts start at 0 and
// are limited per address, the leaderboard only shows players who've played, rude names are
// refused, and names reported by 3 players are replaced.
const path = require('path');
const fs = require('fs');
const { spawn } = require('child_process');
// No browser needed, so this doesn't load ../lib (which needs Playwright); CI runs it on its own
const ROOT = path.resolve(__dirname, '../..');
const OUT = process.env.TEST_OUT || path.join(__dirname, '../output');
fs.mkdirSync(OUT, { recursive: true });
(async () => {
  const ok = (name, cond, extra = '') => console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? '  ' + extra : ''));
  const dir = path.join(ROOT, 'tower-siege/server');
  let WebSocket;
  try { WebSocket = require(path.join(dir, 'node_modules/ws')); } catch {
    ok('ws is installed (cd tower-siege/server && npm install)', false);
    return;
  }
  const PORT = 8098;
  const dataFile = path.join(OUT, 'siege-server-data.json');
  fs.rmSync(dataFile, { force: true });
  const server = spawn(process.execPath, [path.join(dir, 'server.js')], { env: { ...process.env, PORT: String(PORT), DATA_FILE: dataFile, DATABASE_URL: '', RECONNECT_MS: '1500', CONFIRM_MS: '700', NEW_PER_HOUR: '30' } });
  await new Promise(r => setTimeout(r, 800));
  const sleep = ms => new Promise(r => setTimeout(r, ms));

  // A bare client: keeps every message, can wait for one of a type
  async function client(name, account = {}, extra = {}) {
    const ws = new WebSocket(`ws://127.0.0.1:${PORT}`);
    const c = { ws, got: [], name };
    ws.on('message', d => c.got.push(JSON.parse(d)));
    await new Promise(r => ws.on('open', r));
    c.send = m => ws.send(JSON.stringify(m));
    c.wait = async (t, ms = 4000) => {
      for (let i = 0; i < ms / 50; i++) {
        const m = c.got.find(x => x.t === t);
        if (m) { c.got = c.got.filter(x => x !== m); return m; }
        await sleep(50);
      }
      return null;
    };
    c.send({ t: 'hello', v: extra.v ?? 4, id: account.id, token: account.token, name, trophies: 0, ...extra });
    const w = await c.wait(extra.v !== undefined && extra.v < 4 ? 'old' : 'welcome');
    if (w && w.t === 'welcome') c.account = { id: w.you.id, token: w.token || account.token };
    c.first = w;
    return c;
  }

  const old = await client('Old', {}, { v: 3 });
  ok('An old version of the game is told to update', old.first?.t === 'old');
  old.ws.close();

  // A match
  let host = await client('Hana');
  let guest = await client('Gus');
  host.send({ t: 'find' });
  await host.wait('waiting');
  guest.send({ t: 'find' });
  const mh = await host.wait('match'), mg = await guest.wait('match');
  ok('Two players are matched', mh?.role === 'host' && mg?.role === 'guest' && mh.seed === mg.seed);

  // The guest drops and comes back
  guest.ws.close();
  const w = await host.wait('wait');
  ok('When the guest drops, the host is told to wait', w?.secs === 2, JSON.stringify(w));
  const acct = guest.account;
  guest = await client('Gus', acct, { back: true });
  const res = await guest.wait('resume');
  ok('The guest gets back into its match', res?.ok === true && res.role === 'guest' && res.seed === mh.seed && res.opp?.name === 'Hana', JSON.stringify(res));
  ok('The host is told the guest is back', !!(await host.wait('back')));
  host.send({ t: 'snap', tm: 1, tw: [], k: 1, u: [] });
  ok("The host's updates reach the guest again", !!(await guest.wait('snap')));
  guest.send({ t: 'cmd', c: 'link', a: 1, b: 2 });
  ok("The guest's moves reach the host again", !!(await host.wait('cmd')));

  // The guest drops and doesn't come back in time
  guest.ws.close();
  await host.wait('wait');
  const gone = await host.wait('gone', 4000);
  const result = await host.wait('result');
  ok('If the guest stays away too long, the host wins', !!gone && result?.delta === 30, JSON.stringify(result));
  guest = await client('Gus', acct, { back: true });
  ok('Coming back too late finds no match', (await guest.wait('resume'))?.ok === false);

  // The phone switched networks: it's back before the server noticed the old connection died
  host.send({ t: 'find' });
  await host.wait('waiting');
  guest.send({ t: 'find' });
  const m3 = await host.wait('match');
  await guest.wait('match');
  const stale = guest;
  guest = await client('Gus', acct, { back: true });
  const res3 = await guest.wait('resume');
  ok('Coming back while the old connection still hangs takes over the match', res3?.ok === true && res3.seed === m3?.seed, JSON.stringify(res3));
  ok('...the host is told the guest is back', !!(await host.wait('back')));
  host.send({ t: 'snap', tm: 1, tw: [], k: 1, u: [] });
  ok("...the host's updates reach the new connection", !!(await guest.wait('snap')));
  await sleep(300);
  ok('...and the old connection is closed', stale.ws.readyState >= WebSocket.CLOSING);
  guest.send({ t: 'leave' });
  await host.wait('result');
  await sleep(200);
  host.got = [];
  guest.got = [];

  // A fresh start (the app was closed) while a match waits: that match is lost straight away
  host.send({ t: 'find' });
  await host.wait('waiting');
  guest.send({ t: 'find' });
  await host.wait('match');
  await guest.wait('match');
  guest.ws.close();
  await host.wait('wait');
  guest = await client('Gus', acct);
  const gone2 = await host.wait('gone', 1000);
  const r2 = await host.wait('result');
  ok('Starting afresh instead of reconnecting loses the waiting match at once', !!gone2 && r2?.delta === 30);

  host.ws.close();
  guest.ws.close();

  // ----- Results both players agree on -----
  // A friend match between a and b; each then says who won from its own side (1 = me, 2 = them,
  // -1 = not over, null = says nothing). Returns both result messages.
  async function play(a, b, aSays, bSays) {
    a.send({ t: 'room' });
    const room = await a.wait('room');
    b.send({ t: 'join', code: room.code });
    await a.wait('match');
    await b.wait('match');
    if (aSays !== null) a.send({ t: 'end', w: aSays });
    if (aSays !== null) await b.wait('end');
    if (bSays !== null) b.send({ t: 'end', w: bSays });
    return [await a.wait('result', 3000), await b.wait('result', 3000)];
  }
  const ann = await client('Ann'), ben = await client('Ben');
  let [ra, rb] = await play(ann, ben, 1, 2);
  ok('A result both players agree on counts', ra?.delta === 30 && rb?.delta === 0 && rb?.you.losses === 1, JSON.stringify([ra, rb]));
  [ra, rb] = await play(ann, ben, 1, -1);
  ok("A host claiming a win the other game doesn't see is a draw", ra?.delta === 0 && rb?.delta === 0 && ra?.why === 'dispute', JSON.stringify(ra));
  [ra, rb] = await play(ann, ben, 1, 1);
  ok('Both claiming the win is a draw', ra?.delta === 0 && ra?.why === 'dispute');
  [ra, rb] = await play(ann, ben, 1, null);
  ok('A connected player who says nothing makes it a draw', ra?.delta === 0 && ra?.why === 'dispute');
  // The guest's game closes right after the result: the host's word stands
  ann.send({ t: 'room' });
  const room2 = await ann.wait('room');
  ben.send({ t: 'join', code: room2.code });
  await ann.wait('match');
  await ben.wait('match');
  ann.send({ t: 'end', w: 1 });
  await ben.wait('end');
  ben.ws.close();
  ra = await ann.wait('result', 3000);
  ok("If the other player's game has closed, the result stands", ra?.delta === 30, JSON.stringify(ra));

  // ----- Two accounts can't farm trophies off each other -----
  const cat = await client('Cat'), dan = await client('Dan');
  for (let i = 0; i < 3; i++) await play(cat, dan, 1, 2);
  [ra, rb] = await play(cat, dan, 1, 2);
  ok('The same two players only win trophies off each other 3 times a day', ra?.delta === 0 && ra?.why === 'again', JSON.stringify(ra));

  // ----- Accounts and the leaderboard -----
  const liar = await client('Liar', {}, { trophies: 99999 });
  ok('A new account starts at 0 trophies, whatever the app says', liar.first?.you.trophies === 0);
  cat.send({ t: 'top' });
  const top = await cat.wait('top');
  ok('Only players who have finished a match are on the leaderboard', top && !top.players.some(p => p.name === 'Liar') && top.players.some(p => p.name === 'Cat'), JSON.stringify(top?.players));

  // ----- Names -----
  const rude = await client('Sh1t Lord');
  ok('A rude name is refused', rude.first?.you.name === 'Player');
  rude.send({ t: 'name', name: 'F.u.c.k' });
  ok('...when changed later too', (await rude.wait('me'))?.rude === true);
  await sleep(550);
  rude.send({ t: 'mkclan', name: 'Puta Madre', tag: 'PM' });
  ok('...and for clans', (await rude.wait('clanerr'))?.msg === 'Please pick a friendlier name.');
  const eve = await client('EvilName');
  for (const r of [ann, cat, dan]) { r.send({ t: 'report', kind: 'player', id: eve.account.id }); await r.wait('reported'); await sleep(550); }
  eve.send({ t: 'whoami' });
  const me = await eve.wait('me');
  ok('A name reported by 3 players who have played is replaced', me?.you.name.startsWith('Player '), me?.you.name);
  liar.send({ t: 'report', kind: 'player', id: cat.account.id });
  await liar.wait('reported');
  cat.send({ t: 'whoami' });
  ok("...and players who haven't played can't report", (await cat.wait('me'))?.you.name === 'Cat');

  // ----- Many new accounts from one address -----
  let busy = false;
  for (let i = 0; i < 30 && !busy; i++) {
    const ws = new WebSocket(`ws://127.0.0.1:${PORT}`);
    await new Promise(r => ws.on('open', r));
    const reply = await new Promise(r => { ws.on('message', d => r(JSON.parse(d))); ws.send(JSON.stringify({ t: 'hello', v: 4, name: 'Bot' + i })); });
    busy = reply.t === 'busy';
    ws.close();
  }
  ok('Too many new accounts from one address are refused for a while', busy);

  for (const c of [ann, cat, dan, liar, rude, eve]) c.ws.close();
  server.kill();
})();
