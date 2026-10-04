// Tower Siege cross-play: a web player and a Godot player (tower-siege-godot) on the same
// server. They're matched, see the same map, the guest's road reaches the host (whichever
// side Godot is on), both get the result and trophies, and a clan made in Godot shows on the web.
// Each round also drops a connection mid-match: the web guest's in round 1, the Godot guest's in
// round 2; the match must pause on both and carry on.
// Needs Godot 4.7: set GODOT to its path (otherwise this suite is skipped).
const path = require('path');
const fs = require('fs');
const { spawn, spawnSync } = require('child_process');
const { chromium, ROOT, OUT } = require('../lib');
(async () => {
  const ok = (name, cond, extra = '') => console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? '  ' + extra : ''));
  const GODOT = process.env.GODOT;
  if (!GODOT || !fs.existsSync(GODOT)) {
    console.log('PASS Skipped: set GODOT to the Godot 4.7 binary to run the cross-play test');
    return;
  }
  const project = path.join(ROOT, 'tower-siege-godot');
  spawnSync(GODOT, ['--headless', '--path', project, '--import'], { timeout: 180000 });

  const PORT = 8097;
  const dataFile = path.join(OUT, 'siege-crossplay-data.json');
  fs.rmSync(dataFile, { force: true });
  const server = spawn(process.execPath, [path.join(ROOT, 'tower-siege/server/server.js')], { env: { ...process.env, PORT: String(PORT), DATA_FILE: dataFile, DATABASE_URL: '' } });
  await new Promise(r => setTimeout(r, 800));

  const errors = [];
  let gdLog = '';
  // Round 1: Godot searches first and hosts. Round 2: the web player hosts and Godot joins.
  for (const [round, godotFirst] of [[1, true], [2, false]]) {
    // The Godot player
    // Whoever searches first waits in the queue and hosts: in round 2 Godot starts only once
    // the web player is waiting
    let gd = null;
    const startGodot = () => {
      gd = spawn(GODOT, ['--headless', '--path', project, '-s', 'tests/online.gd', '--', `--server=ws://127.0.0.1:${PORT}`, `--name=Godo${round}`, `--clan=GD${round}`, godotFirst ? '--peer-drops' : '--drop']);
      gd.stdout.on('data', d => {
        gdLog += d;
        for (const l of String(d).split('\n')) if (l.startsWith('GD ')) lines.push(l.slice(3));
      });
      gd.stderr.on('data', d => (gdLog += d));
    };
    if (godotFirst) startGodot();
    const lines = [];
    gdLog = '';
    const gdLine = async (prefix, secs = 60) => {
      for (let i = 0; i < secs * 10; i++) {
        const l = lines.find(x => x.startsWith(prefix));
        if (l) return l;
        await new Promise(r => setTimeout(r, 100));
      }
      return null;
    };

    // The web player
    const browser = await chromium.launch();
    const page = await browser.newPage({ viewport: { width: 420, height: 860 } });
    page.on('pageerror', e => errors.push(e.message));
    await page.goto(`file://${ROOT}/tower-siege/index.html?server=ws://127.0.0.1:${PORT}`);
    await page.evaluate(() => localStorage.clear());
    await page.reload();
    await page.click('#pvp-btn');
    await page.fill('#pvp-name', 'Webby' + round);
    await page.dispatchEvent('#pvp-name', 'change');
    if (godotFirst) await gdLine('SEARCHING');
    await page.click('#find-btn');
    if (!godotFirst) {
      await page.waitForFunction(() => $('wait-text').textContent.includes('Looking'), null, { timeout: 60000 }).catch(() => {});
      startGodot();
    }

    const match = await gdLine('MATCH');
    ok(`Round ${round}: Godot finds a match`, match && match.startsWith('MATCH true'), match || gdLog.slice(-600));
    await page.waitForFunction(() => mode === 'online' && state === 'play', null, { timeout: 30000 }).catch(() => {});
    const web = await page.evaluate(() => ({ role: Net.role, map: towers.map(t => [Math.round(t.bx), Math.round(t.by), t.type]) }));
    ok(`Round ${round}: the web player is in the same match, Godot is ${godotFirst ? 'host' : 'guest'}`, web.role && match && match.includes('role=' + (godotFirst ? 'host' : 'guest')) && web.role === (godotFirst ? 'guest' : 'host'), JSON.stringify(web.role) + ' / ' + match);
    const map = await gdLine('MAP');
    ok('Web and Godot see the same map', map && JSON.stringify(JSON.parse(map.slice(4))) === JSON.stringify(web.map));

    if (web.role === 'guest') {
      // The web guest's connection drops: it reconnects and the match carries on
      await page.waitForTimeout(500);
      await page.evaluate(() => Net.ws.close());
      const paused = await page.waitForFunction(() => pvp.paused === 'self' && $('hint').textContent.includes('Reconnecting'), null, { timeout: 5000 }).then(() => true, () => false);
      const back = await page.waitForFunction(() => pvp.paused === null && !pvp.over && Net.ready, null, { timeout: 25000 }).then(() => true, () => false);
      const waited = await gdLine('WAITED');
      ok('The web guest drops, says it is reconnecting, and gets back into the match; the Godot host waits for it', paused && back && waited === 'WAITED true' && (await gdLine('PEER_BACK')) === 'PEER_BACK true', `${paused} ${back} ${waited}`);
      // The web player builds a road; the Godot host must see it
      const pts = await page.evaluate(() => {
        const me = towers.find(t => t.owner === PLAYER);
        const target = towers.filter(t => t.owner === NEUTRAL && !blocked(me, t)).sort((x, y) => dist(x, me) - dist(y, me))[0];
        return { a: R3D.towerScreen(me), b: R3D.towerScreen(target) };
      });
      await page.mouse.move(pts.a.x, pts.a.y);
      await page.mouse.down();
      await page.mouse.move(pts.b.x, pts.b.y, { steps: 8 });
      await page.mouse.up();
      const saw = await gdLine('HOST_SAW_ROAD');
      ok("The web guest's road reaches the Godot host", saw === 'HOST_SAW_ROAD true', saw);
    } else {
      // The Godot guest's connection drops: the web host waits for it, then it builds a road;
      // the web host must see it, then the web host wins
      const resumed = await gdLine('RESUMED');
      ok('The Godot guest drops and gets back in; the web host waited for it', resumed === 'RESUMED true role=guest' && await page.evaluate(() => pvp.waits > 0 && pvp.paused === null), resumed);
      const road = await gdLine('GUEST_ROAD');
      const hostSees = await page.evaluate(() => towers.some(t => t.owner === 2 && t.roads.length > 0));
      ok("The Godot guest's road reaches the web host, and its soldiers show up on Godot", road === 'GUEST_ROAD true' && hostSees, road);
      await page.evaluate(() => { for (const t of towers) if (t.owner === 2) t.owner = PLAYER; units = units.filter(u => u.owner !== 2); });
    }
    await page.waitForSelector('#pvp-end', { state: 'visible', timeout: 30000 }).catch(() => {});
    const result = await gdLine('RESULT');
    const webTitle = await page.textContent('#end-title');
    await page.waitForTimeout(800);
    const webTrophies = await page.evaluate(() => save.trophies);
    const hostWon = web.role === 'host' ? webTitle === 'Victory!' && result && result.includes('title=Defeat') : webTitle === 'Defeat' && result && result.includes('title=Victory!');
    ok('Both see the result (the host wins)', hostWon, `${webTitle} / ${result}`);
    ok('Trophies from the server on both', result && result.startsWith('RESULT true') && (web.role === 'host' ? webTrophies === 30 && result.includes('trophies=0') : webTrophies === 0 && result.includes('trophies=30')), `${webTrophies} / ${result}`);
    await page.screenshot({ path: OUT + `/tsx-web-end-${round}.png` });

    const clan = await gdLine('CLAN');
    ok('Godot creates a clan', clan === 'CLAN clan', clan);
    const top = await gdLine('TOP');
    ok("Godot's leaderboard has both players", top && top.includes('Webby' + round) && top.includes('Godo' + round), top);
    await page.click('#pvp-end .menu-btn2');
    await page.click('#clans-btn');
    await page.waitForSelector('#clan-browse:not(.hidden)', { timeout: 30000 }).catch(() => {});
    await page.fill('#clan-search', 'GD' + round);
    await page.waitForSelector('#clan-list [data-clan]', { timeout: 10000 }).catch(() => {});
    ok("The web player finds the Godot player's clan", (await page.textContent('#clan-list')).includes('Godot Gang GD' + round));


    ok(`Round ${round}: no script errors in Godot`, !/SCRIPT ERROR/.test(gdLog), (gdLog.match(/SCRIPT ERROR.*\n.*\n/) || [''])[0]);
    gd.kill();
    await browser.close();
  }
  ok('No page errors', errors.length === 0, errors.join(' | '));
  server.kill();
})();
