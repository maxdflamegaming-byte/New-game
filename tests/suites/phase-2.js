const { chromium, ROOT, OUT } = require('../lib');
(async () => {
  const S = OUT;
  const browser = await chromium.launch();
  const errors = [];
  const ok = (name, cond, extra = '') => console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? '  ' + extra : ''));
  const ctx = await browser.newContext({ viewport: { width: 1000, height: 700 } });
  let page = await ctx.newPage();
  page.on('pageerror', e => errors.push(e.message));
  await page.goto('file://' + ROOT + '/color-claim/index.html');
  await page.waitForTimeout(300);
  ok('Fresh player: only Classic unlocked', await page.evaluate(() => SKINS.filter(isUnlocked).length === 1));
  await page.click('[data-open="locker"]');
  ok('Locked skins show how to unlock them', (await page.textContent('#locker-items')).includes('Play 3 games'));
  await page.evaluate(() => { stats = { games: 10, kills: 10, wins: 3, bestPct: 20 }; buildLocker(); });
  await page.click('#locker-items .item >> nth=4 >> .item-btn');
  ok('Can pick an unlocked skin', await page.evaluate(() => mySkin === 'cat'));
  await page.screenshot({ path: S + '/p2-menu.png' });
  await page.click('#locker [data-back]');

  // Unlock flow at game over
  await page.evaluate(() => { stats = { games: 2, kills: 0, wins: 0, bestPct: 0 }; localStorage.setItem('color-claim-howto-seen', '1'); });
  await page.click('#play-btn');
  await page.evaluate(() => { for (const p of players) if (p && p.isBot) { p.alive = false; p.respawn = 999; } peakPct = 12; kill(me, me); });
  await page.waitForTimeout(1200);
  ok('Game over announces new unlocks', (await page.textContent('#over-unlock')).includes('Stripes') && (await page.textContent('#over-unlock')).includes('Dots'), await page.textContent('#over-unlock'));
  ok('Stats saved', await page.evaluate(() => JSON.parse(localStorage.getItem('color-claim-stats')).games === 3));

  // Power-ups
  await page.click('#again-btn');
  const res = await page.evaluate(() => {
    const out = {};
    for (const p of players) if (p && p.isBot && p.id > 3) { p.alive = false; p.respawn = 999; }
    const bot = players[2];
    countdown = 0;
    for (const p of players) if (p) p.fx.shield = 0;
    // Speed
    powerups = [{ x: me.x, y: me.y, kind: 'speed', age: 1 }];
    updatePowerups(0.01);
    out.speed = speedOf(me) / SPEED;
    // Shield: a bot crossing my trail doesn't knock me out
    me.fx.speed = 0;
    powerups = [{ x: me.x, y: me.y, kind: 'shield', age: 1 }];
    updatePowerups(0.01);
    const cell = me.cy * N + me.cx + 6;
    trail[cell] = me.id; me.trail.push(cell);
    visit(bot, cell % N, Math.floor(cell / N));
    out.shieldSaved = me.alive;
    // Shield doesn't save you from your own trail
    // Freeze: others slow to half
    me.fx.shield = 0;
    powerups = [{ x: me.x, y: me.y, kind: 'freeze', age: 1 }];
    updatePowerups(0.01);
    out.botSpeedWhenFrozen = speedOf(bot) / SPEED;
    out.mySpeedWhenIFroze = speedOf(me) / SPEED;
    for (let i = 0; i < 60 * 5; i++) updatePowerups(1 / 60);
    out.freezeWearsOff = freezer === null && speedOf(bot) === SPEED;
    return out;
  });
  ok('Speed power-up = 1.6x', Math.abs(res.speed - 1.6) < 1e-9);
  ok('Shield: enemy crossing your trail does not knock you out', res.shieldSaved);
  ok('Freeze: others at half speed, you at full', res.botSpeedWhenFrozen === 0.5 && res.mySpeedWhenIFroze === 1);
  ok('Freeze wears off', res.freezeWearsOff);
  // Visual check with effects active
  await page.evaluate(() => {
    startGame();
    me.skin = 'stripes';
    players[2].x = me.x + 4; players[2].y = me.y + 2; players[2].skin = 'ninja';
    players[3].x = me.x - 4; players[3].y = me.y + 3; players[3].skin = 'robot';
    me.fx.shield = 5; players[3].fx.speed = 5; players[2].fx.freeze = 0;
    powerups = [{ x: me.x + 5, y: me.y - 4, kind: 'speed', age: 1 }, { x: me.x - 6, y: me.y - 3, kind: 'shield', age: 1 }, { x: me.x + 1, y: me.y + 6, kind: 'freeze', age: 1 }];
  });
  await page.waitForTimeout(250);
  await page.screenshot({ path: S + '/p2-game.png' });

  // 5-minute bot simulation: regressions + power-ups being used
  const sim = await page.evaluate(() => {
    startGame();
    const deaths = { self: 0, other: 0 };
    let grabs = 0, zeroLandAlive = 0;
    const origKill = kill, origGrab = grabPowerup;
    kill = (v, k, how = 'cut') => { const was = v.alive; origKill(v, k, how); if (was && !v.alive) deaths[k === v ? 'self' : 'other']++; };
    grabPowerup = (p, pu) => { grabs++; origGrab(p, pu); };
    me.isBot = true;
    for (let i = 0; i < 5 * 60 * 60; i++) {
      update(1 / 60);
      if (!me.alive) { me.alive = true; spawn(me); }
      for (const p of players) if (p && p.alive && counts[p.id] === 0) zeroLandAlive++;
    }
    return { deaths, grabs, zeroLandAlive };
  });
  ok('5-min sim: power-ups get used', sim.grabs > 10, JSON.stringify(sim));
  ok('5-min sim: nobody alive with zero land', sim.zeroLandAlive === 0);
  ok('5-min sim: self-crashes stay rare', sim.deaths.self <= 10);

  // Phone menu fits and scrolls
  const phone = await browser.newPage({ viewport: { width: 390, height: 700 }, isMobile: true, hasTouch: true });
  phone.on('pageerror', e => errors.push('phone: ' + e.message));
  await phone.goto('file://' + ROOT + '/color-claim/index.html');
  await phone.waitForTimeout(300);
  await phone.screenshot({ path: S + '/p2-phone-menu.png' });
  await phone.evaluate(() => { localStorage.setItem('color-claim-howto-seen', '1'); document.querySelector('#play-btn').scrollIntoView(); });
  await phone.tap('#play-btn');
  ok('Phone: Play button reachable', await phone.evaluate(() => state === 'play'));
  console.log('errors', errors);
  await browser.close();
})();
