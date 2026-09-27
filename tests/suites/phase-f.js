const { chromium, ROOT, OUT } = require('../lib');
(async () => {
  const S = OUT;
  const browser = await chromium.launch();
  const errors = [];
  const ok = (name, cond, extra = '') => console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? '  ' + extra : ''));
  const page = await browser.newPage({ viewport: { width: 1000, height: 740 } });
  page.on('pageerror', e => errors.push(e.message));
  await page.goto('file://' + ROOT + '/color-claim/index.html');
  await page.evaluate(() => localStorage.setItem('color-claim-howto-seen', '1'));
  ok('Menu shows this week\'s event', (await page.textContent('#event-banner')).startsWith('This week:'), await page.textContent('#event-banner'));
  ok('Teams mode is in the mode picker', (await page.textContent('#modes')).includes('Teams'));
  await page.screenshot({ path: S + '/pf-menu.png' });

  // ---- Teams rules ----
  const t = await page.evaluate(() => {
    myMode = 'team'; myMap = 'square'; startGame(); countdown = 0;
    for (const p of players) if (p) p.fx.shield = 0;
    const out = { teams: players.filter(Boolean).map(p => p.team).join('') };
    const mate = players[2], foe = players[6];
    // teammate crosses my trail: nothing happens
    const i = me.cy * N + me.cx + 7; trail[i] = me.id; me.trail.push(i);
    visit(mate, me.cx + 7, me.cy);
    out.mateSafe = me.alive && mate.alive && trail[i] === me.id;
    // teammates don't bump
    mate.x = me.x + 0.3; mate.y = me.y; mate.cx = me.cx; mate.cy = me.cy;
    setOwner(me.cy * N + me.cx, 0); me.trail.push(me.cy * N + me.cx);
    checkBumps();
    out.noBump = me.alive && mate.alive;
    // enemies still cut
    visit(foe, me.cx + 7, me.cy);
    out.foeCuts = !me.alive;
    return out;
  });
  ok('Teams: you + 3 bots vs 4 bots', t.teams === '00001111', t.teams);
  ok("Teams: a teammate crossing your trail is harmless", t.mateSafe);
  ok('Teams: teammates never bump each other', t.noBump);
  ok('Teams: enemies can still cut you', t.foeCuts);
  await page.waitForTimeout(1200);
  const steal = await page.evaluate(() => {
    startGame(); countdown = 0; for (const p of players) if (p) p.fx.shield = 0;
    // A teammate's land inside my loop is not stolen
    const mate = players[3];
    const inside = (me.cy + 5) * N + me.cx + 5;
    setOwner(inside, mate.id);
    // draw a box loop around it from my land
    const cells = [];
    for (let x = me.cx; x <= me.cx + 8; x++) cells.push([x, me.cy + 3], [x, me.cy + 8]);
    for (let y = me.cy + 3; y <= me.cy + 8; y++) cells.push([me.cx + 8, y]);
    for (const [x, y] of cells) { const i = y * N + x; if (owner[i] !== me.id) { trail[i] = me.id; me.trail.push(i); } }
    capture(me);
    return { mateKept: owner[inside] === mate.id, claimed: counts[me.id] };
  });
  ok("Teams: capturing never steals a teammate's land", steal.mateKept, `me=${steal.claimed} cells`);
  const tw = await page.evaluate(() => {
    for (let i = 0; i < N * N * 0.52; i++) if (!wall[i] && !owner[i]) setOwner(i, players[2].id);
    return teamPct(0);
  });
  await page.waitForTimeout(2200);
  ok('Teams: your team reaching 50% wins the game', (await page.textContent('#over-title')).includes('win') && (await page.textContent('#over-reason')).includes('Your team'), `team ${tw.toFixed(1)}%`);

  // ---- The Giant ----
  await page.click('#menu-btn');
  const g = await page.evaluate(() => {
    myMode = 'classic'; startGame(); countdown = 0;
    for (let i = 0; i < N * N * 0.21; i++) if (!owner[i] && !wall[i]) setOwner(i, me.id);
    update(1 / 60);
    const out = { spawned: !!giant, boss: giant && giant.isBoss, speed: giant && speedOf(giant) / speedOf(players[2]) };
    // Giant hunts your trail
    giant.fx.shield = 0; me.fx.shield = 0;
    for (let k = 1; k <= 6; k++) { const i = (me.cy + 10) * N + me.cx + k; trail[i] = me.id; me.trail.push(i); }
    giant.x = me.x + 3; giant.y = me.y + 12; giant.mode = 'idle'; giant.trail = [7]; giant.wp = [];
    think(giant);
    out.hunts = giant.mode === 'hunt';
    // Beating it pays out
    const c0 = coins;
    kill(giant, me);
    out.reward = coins - c0; out.gone = !giant.alive && giant.respawn === Infinity; out.ko = run.giantKO;
    return out;
  });
  ok('The Giant arrives when you reach 20%', g.spawned && g.boss, `speed x${g.speed && g.speed.toFixed(2)}`);
  ok('The Giant hunts your trail', g.hunts);
  ok('Beating the Giant pays 100 coins and it stays gone', g.reward >= 100 && g.gone && g.ko, `+${g.reward}`);
  await page.evaluate(() => { startGame(); countdown = 0; for (let i = 0; i < N * N * 0.21; i++) if (!owner[i] && !wall[i]) setOwner(i, me.id); cam.zoom = 1; me.isBot = true; });
  await page.waitForTimeout(900);
  await page.evaluate(() => { if (giant) { cam.x = giant.x; cam.y = giant.y; me.x = giant.x - 6; me.y = giant.y; } });
  await page.waitForTimeout(150);
  await page.screenshot({ path: S + '/pf-giant.png' });

  // ---- Weekly events ----
  const ev = await page.evaluate(() => {
    const real = weekInfo;
    const force = id => { weekInfo = () => ({ event: EVENTS.find(e => e.id === id), daysLeft: 3 }); };
    const out = {};
    startGame(); countdown = 0;
    force('speed'); out.speed = speedOf(players[2]) / SPEED;
    force('double'); const c0 = coins; mapCoins = [{ x: me.x, y: me.y, age: 1, life: 9 }]; updateMapCoins(0.01); out.double = coins - c0;
    force('goldrush'); mapCoins = []; for (let i = 0; i < 400; i++) updateMapCoins(0.1); out.rushCoins = mapCoins.length;
    force('frenzy'); powerups = []; for (let i = 0; i < 400; i++) updatePowerups(0.1); out.frenzyPowerups = powerups.length;
    weekInfo = real;
    return out;
  });
  ok('Speed Week: everyone is 20% faster', Math.abs(ev.speed - 1.2) < 1e-9);
  ok('Double Coins: map coins are worth double', ev.double === 4, `+${ev.double}`);
  ok('Gold Rush: many more coins on the map', ev.rushCoins > 6, `${ev.rushCoins} coins`);
  ok('Power-up Frenzy: twice as many power-ups', ev.frenzyPowerups > 4, `${ev.frenzyPowerups} power-ups`);

  // ---- Colorblind patterns ----
  await page.evaluate(() => { settings.patterns = true; startGame(); countdown = 0; me.isBot = true; });
  await page.waitForTimeout(2500);
  await page.screenshot({ path: S + '/pf-patterns.png' });
  ok('Colorblind patterns draw without errors', errors.length === 0);
  await page.evaluate(() => { settings.patterns = false; });

  // ---- Bots in Teams mode + Giant, 3 minutes each ----
  const sim = await page.evaluate(() => {
    const out = {};
    for (const mode of ['team', 'classic']) {
      myMode = mode; myMap = 'square'; startGame();
      me.isBot = true;
      let self = 0, other = 0, zero = 0, allyKills = 0;
      const o = kill;
      kill = (v, k, h = 'cut') => { const was = v.alive; o(v, k, h); if (was && !v.alive) { if (k === v) self++; else other++; if (k !== v && allies(v, k)) allyKills++; } };
      for (let i = 0; i < 180 * 60; i++) {
        state = 'play'; update(1 / 60);
        if (!me.alive) { me.alive = true; spawn(me); }
        if (mode === 'classic' && i === 60 * 60 && !giant) spawnGiant();
        for (const p of players) if (p && p.alive && counts[p.id] === 0) zero++;
      }
      kill = o;
      out[mode] = { self, other, zero, allyKills, giant: !!giant };
    }
    return out;
  });
  ok('Teams sim: teammates never knock each other out', sim.team.allyKills === 0 && sim.team.zero === 0, JSON.stringify(sim.team));
  ok('Giant sim: no zero-land players, few self-crashes', sim.classic.zero === 0 && sim.classic.self <= Math.max(3, sim.classic.other * 0.15), JSON.stringify(sim.classic));
  console.log('errors', errors);
  await browser.close();
})();
