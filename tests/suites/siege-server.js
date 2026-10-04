// Tower Siege server, without browsers: matching, the old-version check, and what happens when a
// player's connection drops mid-match (the other is told to wait; coming back resumes the match;
// not coming back in time, or starting afresh, loses it).
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
  const server = spawn(process.execPath, [path.join(dir, 'server.js')], { env: { ...process.env, PORT: String(PORT), DATA_FILE: dataFile, DATABASE_URL: '', RECONNECT_MS: '1500' } });
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
    c.send({ t: 'hello', v: extra.v ?? 3, id: account.id, token: account.token, name, trophies: 0, ...extra });
    const w = await c.wait(extra.v === 2 ? 'old' : 'welcome');
    if (w && w.t === 'welcome') c.account = { id: w.you.id, token: w.token || account.token };
    c.first = w;
    return c;
  }

  const old = await client('Old', {}, { v: 2 });
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
  server.kill();
})();
