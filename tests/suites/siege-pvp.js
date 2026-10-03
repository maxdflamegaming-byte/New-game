// Tower Siege PvP: two players on a local server, plus 2 players on one phone and practice.
// Needs the server's package installed once: (cd tower-siege/server && npm install)
const path = require('path');
const { spawn } = require('child_process');
const { chromium, ROOT, OUT } = require('../lib');
(async () => {
  const ok = (name, cond, extra = '') => console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? '  ' + extra : ''));
  const PORT = 8099;
  const server = spawn(process.execPath, [path.join(ROOT, 'tower-siege/server/server.js')], { env: { ...process.env, PORT: String(PORT) } });
  let serverLog = '';
  server.stdout.on('data', d => (serverLog += d));
  server.stderr.on('data', d => (serverLog += d));
  await new Promise(r => setTimeout(r, 800));
  ok('The PvP server starts', serverLog.includes('Tower Siege server on port'), serverLog.trim().slice(0, 200));

  // Each player gets their own browser, so neither page is a paused background tab
  const browsers = [];
  const errors = [];
  const open = async () => {
    const br = await chromium.launch();
    browsers.push(br);
    const p = await br.newPage({ viewport: { width: 420, height: 860 } });
    p.on('pageerror', e => errors.push(e.message));
    await p.goto(`file://${ROOT}/tower-siege/index.html?server=ws://127.0.0.1:${PORT}`);
    await p.evaluate(() => localStorage.clear());
    await p.reload();
    return p;
  };
  const a = await open(), b = await open();

  // Both look for a match
  await a.click('#pvp-btn');
  ok('The PvP screen opens', await a.isVisible('#pvp'));
  await a.fill('#pvp-name', 'Alice');
  await a.dispatchEvent('#pvp-name', 'change');
  await a.screenshot({ path: OUT + '/tsp-menu.png' });
  await a.click('#find-btn');
  await a.waitForTimeout(500);
  ok('Searching shows while waiting', await a.isVisible('#pvp-wait'));
  await b.click('#pvp-btn');
  await b.fill('#pvp-name', 'Bob');
  await b.dispatchEvent('#pvp-name', 'change');
  await b.click('#find-btn');
  await a.waitForTimeout(700);
  ok('Both see the VS card', await a.isVisible('#pvp-vs') && await b.isVisible('#pvp-vs'));
  await b.screenshot({ path: OUT + '/tsp-vs.png' });
  await a.waitForTimeout(2600);
  const roles = await Promise.all([a, b].map(p => p.evaluate(() => ({ role: Net.role, mode, state, label: $('level-label').textContent }))));
  ok('The match starts for both', roles.every(r => r.mode === 'online' && r.state === 'play'), JSON.stringify(roles));
  const [host, guest] = roles[0].role === 'host' ? [a, b] : [b, a];
  ok('One is host and one is guest', roles.map(r => r.role).sort().join() === 'guest,host');

  // Same map, mirrored: each sees their own base in blue at the bottom of the screen
  const view = await Promise.all([host, guest].map(p => p.evaluate(() => {
    const mine = towers.find(t => t.owner === PLAYER), theirs = towers.find(t => t.owner === 2);
    return { mineId: mine.id, theirsId: theirs.id, mineLower: R3D.towerScreen(mine).y > R3D.towerScreen(theirs).y, n: towers.length };
  })));
  ok('Each player sees their own army at the bottom', view[0].mineLower && view[1].mineLower, JSON.stringify(view));
  ok('Host and guest have the same map, armies swapped', view[0].n === view[1].n && view[0].mineId === view[1].theirsId && view[0].theirsId === view[1].mineId);

  // The guest drags a road: it reaches the host, and the host's battle comes back
  const pts = await guest.evaluate(() => {
    const me = towers.find(t => t.owner === PLAYER);
    const target = towers.filter(t => t.owner === NEUTRAL && !blocked(me, t)).sort((x, y) => dist(x, me) - dist(y, me))[0];
    const s1 = R3D.towerScreen(me), s2 = R3D.towerScreen(target);
    return { a: s1, b: s2, from: me.id, to: target.id };
  });
  await guest.mouse.move(pts.a.x, pts.a.y);
  await guest.mouse.down();
  await guest.mouse.move(pts.b.x, pts.b.y, { steps: 8 });
  await guest.mouse.up();
  await guest.waitForTimeout(800);
  const hostRoad = await host.evaluate(([f, t]) => towers[f].roads.some(r => r.to.id === t) && towers[f].owner === 2, [pts.from, pts.to]);
  ok("The guest's road is built in the host's battle", hostRoad);
  await guest.waitForFunction(() => units.some(u => u.owner === PLAYER), null, { timeout: 15000 }).catch(() => {});
  const gs = await guest.evaluate(([f, t]) => ({ road: towers[f].roads.some(r => r.to.id === t), mine: units.filter(u => u.owner === PLAYER).length, time: gameTime }), [pts.from, pts.to]);
  ok("The guest sees its road and its soldiers marching", gs.road && gs.mine > 0 && gs.time > 0.3, JSON.stringify(gs));
  await guest.screenshot({ path: OUT + '/tsp-guest.png' });
  await host.screenshot({ path: OUT + '/tsp-host.png' });

  // The guest swipes to cut its road
  // Swipe straight across the road, whichever way it runs on screen
  const sw = await guest.evaluate(([f, t]) => {
    const a = P(towers[f].x, towers[f].y), b = P(towers[t].x, towers[t].y);
    const mx = (a.x + b.x) / 2, my = (a.y + b.y) / 2, L = Math.hypot(b.x - a.x, b.y - a.y) || 1;
    const nx = -(b.y - a.y) / L * 70, ny = (b.x - a.x) / L * 70;
    return { x1: mx - nx, y1: my - ny, x2: mx + nx, y2: my + ny };
  }, [pts.from, pts.to]);
  await guest.mouse.move(sw.x1, sw.y1);
  await guest.mouse.down();
  await guest.mouse.move(sw.x2, sw.y2, { steps: 10 });
  await guest.mouse.up();
  await guest.waitForTimeout(600);
  ok("The guest's cut reaches the host", await host.evaluate(([f, t]) => !towers[f].roads.some(r => r.to.id === t), [pts.from, pts.to]));

  // The host wins by taking everything: both see the result, trophies change
  await host.evaluate(() => { for (const t of towers) if (t.owner === 2) t.owner = PLAYER; units = units.filter(u => u.owner !== 2); });
  await host.waitForTimeout(2200);
  ok('The host sees Victory', await host.isVisible('#pvp-end') && (await host.textContent('#end-title')) === 'Victory!');
  ok('The guest sees Defeat', await guest.isVisible('#pvp-end') && (await guest.textContent('#end-title')) === 'Defeat');
  const tr = await Promise.all([host, guest].map(p => p.evaluate(() => save.trophies)));
  ok('Trophies: the winner gets 30, the loser has none to lose yet', tr[0] === 30 && tr[1] === 0, JSON.stringify(tr));
  await host.screenshot({ path: OUT + '/tsp-win.png' });

  // A friend room by code
  await a.click('#end-pvp-btn');
  await b.click('#end-pvp-btn');
  await a.click('#room-btn');
  await a.waitForSelector('#wait-code:not(.hidden)');
  const code = (await a.textContent('#wait-code')).trim();
  ok('Creating a room shows a 4-letter code', /^[A-Z]{4}$/.test(code), code);
  await b.fill('#code-input', code);
  await b.click('#join-btn');
  await a.waitForTimeout(3200);
  ok('A friend joins with the code and the match starts', await a.evaluate(() => mode === 'online' && state === 'play') && await b.evaluate(() => mode === 'online' && state === 'play'));

  // Leaving gives the other player the win
  await b.evaluate(() => { pause(); });
  ok('Pausing online keeps the match running', await b.evaluate(() => state === 'play' && screenOpen === 'paused'));
  await b.click('#quit-btn');
  await a.waitForTimeout(1800);
  ok('When the opponent leaves, you win', await a.isVisible('#pvp-end') && (await a.textContent('#end-title')) === 'Victory!');

  // 2 players on one phone: blue drags from the bottom, red from the top
  await b.click('#pvp-btn');
  await b.click('#duo-btn');
  const duo = await b.evaluate(() => {
    const red = towers.find(t => t.owner === 2), blue = towers.find(t => t.owner === 1);
    const n = towers.filter(t => t.owner === NEUTRAL && !blocked(red, t) && !blocked(blue, t))[0];
    return { red: R3D.towerScreen(red), blue: R3D.towerScreen(blue), n: R3D.towerScreen(n), redId: red.id, blueId: blue.id, nId: n.id, ai: aiSides.length };
  });
  await b.mouse.move(duo.red.x, duo.red.y);
  await b.mouse.down();
  await b.mouse.move(duo.n.x, duo.n.y, { steps: 6 });
  await b.mouse.up();
  await b.mouse.move(duo.blue.x, duo.blue.y);
  await b.mouse.down();
  await b.mouse.move(duo.n.x, duo.n.y, { steps: 6 });
  await b.mouse.up();
  const duoRoads = await b.evaluate(([r, bl, n]) => ({ red: towers[r].roads.some(x => x.to.id === n), blue: towers[bl].roads.some(x => x.to.id === n) }), [duo.redId, duo.blueId, duo.nId]);
  ok('2 players on one phone: both armies can be steered, no bots', duoRoads.red && duoRoads.blue && duo.ai === 0, JSON.stringify(duoRoads));
  await b.waitForTimeout(1500);
  await b.screenshot({ path: OUT + '/tsp-duo.png' });
  await b.evaluate(() => { for (const t of towers) if (t.owner === 1) t.owner = 2; units = []; update(0.01); });
  await b.waitForTimeout(1500);
  ok('2 players: the result says which color won', (await b.textContent('#end-title')) === 'Red wins!');

  // Practice: a bot that plays red, no trophies, and the time limit decides
  await b.click('#again-btn');
  await b.evaluate(() => { startPvP('practice', 7); });
  ok('Practice has a bot opponent', await b.evaluate(() => mode === 'practice' && aiSides.length === 1 && aiSides[0].side === 2));
  await b.evaluate(() => { const before = save.trophies; window.__tr = before; gameTime = PVP_TIME; towers.find(t => t.owner === 1).units = 99; update(0.01); });
  await b.waitForTimeout(1500);
  ok('After 3 minutes the bigger army wins (no trophies in practice)', (await b.textContent('#end-title')) === 'Victory!' && await b.evaluate(() => save.trophies === window.__tr));

  // No upgrades in PvP
  const fair = await b.evaluate(() => { save.up.drill = 5; startPvP('practice', 9); const t = towers.find(x => x.owner === PLAYER); const r1 = prodRate(t); mode = 'campaign'; const r2 = prodRate(t); mode = 'practice'; return r2 > r1; });
  ok('Upgrades only work in the campaign', fair);

  ok('No page errors', errors.length === 0, errors.join(' | '));
  for (const br of browsers) await br.close();
  server.kill();
})();
