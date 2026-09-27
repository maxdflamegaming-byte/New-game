const { chromium, ROOT, OUT } = require('../lib');
(async () => {
  const S = OUT;
  const browser = await chromium.launch();
  const errors = [];
  const ok = (name, cond, extra = '') => console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? '  ' + extra : ''));
  const page = await browser.newPage({ viewport: { width: 1000, height: 700 } });
  page.on('pageerror', e => errors.push(e.message));
  await page.goto('file://' + ROOT + '/color-claim/index.html');
  await page.evaluate(() => localStorage.setItem('color-claim-howto-seen', '1'));

  // Menu pickers
  await page.click('#modes .seg-btn >> nth=2'); // Daily
  ok('Daily locks the map picker', await page.evaluate(() => [...document.querySelectorAll('#maps .seg-btn')].every(b => b.disabled)), await page.textContent('#mode-desc'));
  await page.click('#modes .seg-btn >> nth=0');
  await page.click('#maps .seg-btn >> nth=2');
  ok('Picking a mode and map is saved', await page.evaluate(() => localStorage.getItem('color-claim-mode') === 'classic' && localStorage.getItem('color-claim-map') === 'pillars'));
  await page.screenshot({ path: S + '/pb-menu.png' });

  // Simulate every mode x map with bots only
  const sims = await page.evaluate(() => {
    const out = [];
    for (const mode of ['classic', 'timed', 'marathon']) {
      for (const map of ['square', 'round', 'pillars']) {
        myMode = mode; myMap = map;
        startGame();
        me.isBot = true;
        let self = 0, other = 0, badWall = 0, zeroLand = 0, stuckIn = 0;
        const orig = kill;
        kill = (v, k, how = 'cut') => { const was = v.alive; orig(v, k, how); if (was && !v.alive) (k === v ? self++ : other++); };
        for (let i = 0; i < 90 * 60; i++) {
          if (state !== 'play') { state = 'play'; }
          update(1 / 60);
          if (!me.alive) { me.alive = true; spawn(me); }
          for (const p of players) if (p && p.alive) { if (isWallAt(p.x, p.y)) stuckIn++; if (counts[p.id] === 0) zeroLand++; }
        }
        kill = orig;
        for (let i = 0; i < N * N; i++) if (wall[i] && (owner[i] || trail[i])) badWall++;
        let total = 0; for (const p of players) if (p) total += counts[p.id];
        out.push({ mode, map, N, self, other, badWall, stuckIn, zeroLand, sumPctOk: total <= playCells, leaderPct: Math.max(...players.filter(Boolean).map(p => pct(p))).toFixed(1) });
      }
    }
    return out;
  });
  for (const r of sims) {
    ok(`90s ${r.mode}/${r.map}: no walls entered or claimed`, r.badWall === 0 && r.stuckIn === 0 && r.zeroLand === 0 && r.sumPctOk, JSON.stringify(r));
  }
  const selfTotal = sims.reduce((a, r) => a + r.self, 0), otherTotal = sims.reduce((a, r) => a + r.other, 0);
  ok('Bots rarely crash into their own trail on any map', selfTotal <= otherTotal * 0.15, `self ${selfTotal} vs other ${otherTotal}`);

  // Timed: the clock ends the game with a ranking
  await page.evaluate(() => { myMode = 'timed'; myMap = 'square'; startGame(); countdown = 0; for (const p of players) if (p) p.fx.shield = 5; });
  await page.waitForTimeout(300);
  await page.screenshot({ path: S + '/pb-timed.png' });
  ok('Timed HUD shows the clock', await page.isVisible('#timer') && !(await page.isVisible('#goal')), await page.textContent('#timer'));
  await page.evaluate(() => { playTime = 179.9; });
  await page.waitForTimeout(2500);
  ok("Time's up ends the game with your rank", (await page.textContent('#over-reason')).includes("Time's up"), await page.textContent('#over-reason'));

  // Daily: same starting map twice
  const daily = await page.evaluate(() => {
    myMode = 'daily';
    const snap = () => { startGame(); return JSON.stringify(players.filter(Boolean).map(p => [p.name, p.skin, Math.round(p.x), Math.round(p.y)])) + gameMapId; };
    const a = snap(), b = snap();
    return { same: a === b, map: gameMapId, expected: dailyMap() };
  });
  ok('Daily gives the same starting map every time today', daily.same && daily.map === daily.expected, daily.map);
  const notDaily = await page.evaluate(() => {
    myMode = 'classic'; myMap = 'square';
    const snap = () => { startGame(); return JSON.stringify(players.filter(Boolean).map(p => [Math.round(p.x), Math.round(p.y)])); };
    return snap() !== snap();
  });
  ok('Other modes are random each game', notDaily);

  // Marathon
  ok('Marathon uses a bigger map and a 60% goal', await page.evaluate(() => { myMode = 'marathon'; startGame(); return N === 120 && gameMode.win === 60; }));

  // Screenshots of the new maps
  for (const map of ['round', 'pillars']) {
    await page.evaluate(m => { myMode = 'classic'; myMap = m; startGame(); countdown = 0; cam.zoom = 0.45; BASE_CELL = 9; }, map);
    await page.waitForTimeout(1200);
    await page.screenshot({ path: `${S}/pb-${map}.png` });
  }
  console.log('errors', errors);
  await browser.close();
})();
