const { chromium, ROOT, OUT } = require('../lib');
(async () => {
  const S = OUT;
  const browser = await chromium.launch();
  const errors = [];
  const ok = (name, cond, extra = '') => console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? '  ' + extra : ''));
  const page = await browser.newPage({ viewport: { width: 1100, height: 720 } });
  page.on('pageerror', e => errors.push(e.message));
  await page.goto('file://' + ROOT + '/color-claim/index.html');
  await page.evaluate(() => localStorage.setItem('color-claim-howto-seen', '1'));

  // ---------- 2 players ----------
  await page.click('#modes .seg-btn:has-text("2 Players")');
  await page.click('#play-btn');
  const duo = await page.evaluate(() => ({ p2: !!p2 && !p2.isBot, n: players.filter(Boolean).length, bots: players.filter(p => p && p.isBot).length, ids: players.filter(Boolean).map(p => p.id).join(',') }));
  ok('2 Players: two humans and 6 bots', duo.p2 && duo.n === 8 && duo.bots === 6, duo.ids);
  await page.evaluate(() => { me.fx.shield = p2.fx.shield = 99; }); // bots can't knock anyone out mid-test
  await page.waitForTimeout(3200);
  const a = await page.evaluate(() => ({ m: [me.x, me.y], p: [p2.x, p2.y] }));
  await page.keyboard.down('d'); await page.keyboard.down('ArrowLeft');
  await page.waitForTimeout(600);
  await page.keyboard.up('d'); await page.keyboard.up('ArrowLeft');
  const b = await page.evaluate(() => ({ m: [me.x, me.y], p: [p2.x, p2.y], mAng: Math.cos(me.angle), pAng: Math.cos(p2.angle) }));
  ok('WASD steers Player 1 and the arrows steer Player 2', b.mAng > 0.8 && b.pAng < -0.8, `P1 dir ${b.mAng.toFixed(2)}, P2 dir ${b.pAng.toFixed(2)}`);
  await page.screenshot({ path: S + '/pg-duo.png' });
  await page.evaluate(() => { for (const p of players) if (p) p.fx.shield = 0; kill(p2, players[4]); });
  await page.waitForTimeout(1200);
  ok('When Player 2 is knocked out, Player 1 wins', (await page.textContent('#over-title')).includes(await page.evaluate(() => me.name)), await page.textContent('#over-title'));
  ok("2-player games don't pay coins", await page.evaluate(() => coins === 0 && stats.games === 0));
  await page.click('#menu-btn');

  // Tall screen: top/bottom split
  await page.setViewportSize({ width: 500, height: 800 });
  await page.click('#play-btn');
  await page.waitForTimeout(3300);
  await page.screenshot({ path: S + '/pg-duo-tall.png' });
  await page.evaluate(() => { state = 'over'; showScreen('over'); });
  await page.click('#menu-btn');
  await page.setViewportSize({ width: 1100, height: 720 });
  await page.click('#modes .seg-btn:has-text("Classic")');

  // ---------- Map editor ----------
  await page.evaluate(() => openScreen('editor'));
  ok('Map editor opens', await page.isVisible('#editor-canvas'));
  const box = await page.$eval('#editor-canvas', c => { const r = c.getBoundingClientRect(); return { x: r.left, y: r.top, w: r.width }; });
  // Draw a line with the mouse in the top-left quarter (mirror adds 3 copies)
  await page.mouse.move(box.x + box.w * 0.1, box.y + box.w * 0.2);
  await page.mouse.down();
  for (let i = 0; i <= 20; i++) await page.mouse.move(box.x + box.w * (0.1 + i * 0.015), box.y + box.w * 0.2);
  await page.mouse.up();
  // Try painting the protected middle
  await page.mouse.click(box.x + box.w / 2, box.y + box.w / 2);
  const ed = await page.evaluate(() => ({ walls: editor.cells.reduce((a, v) => a + v, 0), middle: editor.cells[40 * 80 + 40] }));
  ok('Drawing adds walls, mirrored into 4 corners', ed.walls >= 4 * 20, `${ed.walls} wall cells`);
  ok('The middle stays clear', ed.middle === 0);
  await page.screenshot({ path: S + '/pg-editor.png' });
  await page.click('#editor-save');
  ok('Saving picks the custom map on the menu', await page.evaluate(() => myMap === 'custom0') && (await page.textContent('#maps')).includes('My map 1'));
  await page.click('#play-btn');
  const custom = await page.evaluate(() => { let w = 0; for (let i = 0; i < N * N; i++) if (wall[i]) w++; return { w, N, alive: me.alive }; });
  ok('Playing the custom map loads its walls', custom.w === ed.walls && custom.N === 80 && custom.alive, `${custom.w} walls`);
  await page.evaluate(() => { countdown = 0; me.isBot = true; });
  await page.waitForTimeout(1500);
  await page.screenshot({ path: S + '/pg-custom-play.png' });
  const sim = await page.evaluate(() => {
    let bad = 0;
    for (let i = 0; i < 60 * 60; i++) { state = 'play'; update(1 / 60); if (!me.alive) { me.alive = true; spawn(me); } for (const p of players) if (p && p.alive && isWallAt(p.x, p.y)) bad++; }
    return bad;
  });
  ok('60 s on the custom map: nobody inside walls', sim === 0);
  await page.evaluate(() => { me.isBot = false; kill(me, me); });
  await page.waitForTimeout(1200);

  // ---------- Season pass ----------
  const sea = await page.evaluate(() => {
    season = {}; // start this check from tier 0
    const before = { coins, skins: ownedSkins.slice(), fx: ownedFx.slice() };
    const r1 = addSeasonXp(150 * 10); // reach tier 10
    const r2 = addSeasonXp(150 * 10); // reach tier 20
    const r3 = addSeasonXp(5000);     // nothing past 20
    const items = seasonNow().items;
    return { tiers1: r1.length, tiers2: r2.length, extra: r3.length, fx: ownedFx.includes(items.fx), skin: ownedSkins.includes(items.skin), tier: season.tier, coinGain: coins - before.coins };
  });
  ok('Season pass: 20 tiers pay out once each', sea.tiers1 === 10 && sea.tiers2 === 10 && sea.extra === 0 && sea.tier === 20, `+${sea.coinGain} coins`);
  ok("Season pass: tier 10 and 20 give the season's trail and skin", sea.fx && sea.skin);
  await page.click('#menu-btn');
  await page.click('[data-open="season"]');
  ok('Season screen shows 20 tiers', (await page.$$('#season-tiers .tier')).length === 20, (await page.textContent('#season-head')).trim().split('\n')[0]);
  await page.screenshot({ path: S + '/pg-season.png' });
  await page.click('#season [data-back]');
  await page.click('[data-open="locker"]');
  const other = await page.evaluate(() => SKINS.filter(s => s.need && s.need.stat === 'season' && !ownedSkins.includes(s.id)).map(s => s.name));
  const txt = await page.textContent('#locker-items');
  ok("The other season's skin can't be bought", other.length === 1 && txt.includes('Season reward'), other.join(','));
  console.log('errors', errors);
  await browser.close();
})();
