const { chromium, ROOT, OUT } = require('../lib');
(async () => {
  const S = OUT;
  const browser = await chromium.launch();
  const errors = [];
  const ok = (name, cond) => console.log((cond ? 'PASS ' : 'FAIL ') + name);

  // ---------- Color Claim ----------
  let page = await browser.newPage({ viewport: { width: 1000, height: 650 } });
  page.on('pageerror', e => errors.push('cc: ' + e.message));
  await page.goto('file://' + ROOT + '/color-claim/index.html');
  await page.evaluate(() => localStorage.setItem('color-claim-howto-seen', '1'));
  await page.click('#play-btn');
  await page.waitForTimeout(300);
  await page.click('#pause-btn');
  ok('CC pause button pauses', await page.isVisible('#paused'));
  await page.click('#resume-btn');
  ok('CC resume works', await page.evaluate(() => state === 'play'));
  const muteBefore = await page.evaluate(() => Sfx.muted);
  await page.click('#mute-btn');
  ok('CC mute button toggles', await page.evaluate(m => Sfx.muted !== m, muteBefore));
  await page.click('#mute-btn');
  // Spawn never steals land
  ok('CC spawn never steals land', await page.evaluate(() => {
    for (let i = 0; i < N * N; i++) if (!owner[i] && Math.random() < 0.9) setOwner(i, me.id);
    const mine = counts[me.id];
    const bot = players[2]; kill(bot, me); 
    for (let t = 0; t < 20; t++) spawn(bot);
    return counts[me.id] === mine;
  }));
  // Bumps: safe player wins, outsider with longer trail loses
  ok('CC bump: player on own land beats outsider', await page.evaluate(() => {
    startGame();
    countdown = 0;
    for (const p of players) if (p) p.fx.shield = 0;
    const bot = players[3];
    for (const p of players) if (p && p !== me && p !== bot) { p.alive = false; p.respawn = 999; }
    bot.x = me.x + 0.3; bot.y = me.y; bot.cx = Math.floor(bot.x); bot.cy = Math.floor(bot.y);
    checkBumps();
    return me.alive && !bot.alive;
  }));
  await page.waitForTimeout(200);
  ok('CC bump: both outside, longer trail loses', await page.evaluate(() => {
    startGame();
    countdown = 0;
    for (const p of players) if (p) p.fx.shield = 0;
    const bot = players[3];
    for (const p of players) if (p && p !== me && p !== bot) { p.alive = false; p.respawn = 999; }
    me.x = me.cx + 0.5; bot.x = me.x + 0.3; bot.y = me.y; bot.cx = me.cx; bot.cy = me.cy;
    // pretend both are outside their land
    setOwner(me.cy * N + me.cx, 0);
    me.trail = [1, 2, 3]; bot.trail = [4, 5, 6, 7, 8];
    checkBumps();
    return me.alive && !bot.alive;
  }));
  await page.evaluate(() => startGame());
  await page.evaluate(() => { me.isBot = true; });
  await page.waitForTimeout(6000);
  await page.screenshot({ path: S + '/f-cc.png' });
  await page.close();

  // ---------- Glow Survivors ----------
  page = await browser.newPage({ viewport: { width: 1000, height: 650 } });
  page.on('pageerror', e => errors.push('sv: ' + e.message));
  await page.goto('file://' + ROOT + '/survivors/index.html');
  await page.click('#play-btn');
  await page.waitForTimeout(300);
  await page.click('#pause-btn');
  ok('SV pause button pauses', await page.isVisible('#paused'));
  await page.click('#resume-btn');
  ok('SV resume works', await page.evaluate(() => state === 'play'));
  ok('SV swarm respects enemy limit', await page.evaluate(() => {
    for (let i = 0; i < 345; i++) makeEnemy('basic', player.x + 2000 + i, player.y + 2000);
    spawnSwarm();
    const n = enemies.length, boss = enemies.some(e => e.type === 'boss');
    enemies = [];
    return n <= MAX_ENEMIES + 1 && boss;
  }));
  // Show every pickup + a boss for the screenshot
  await page.evaluate(() => {
    player.hp = player.maxHp = 1e6;
    pickups.push({ x: player.x - 120, y: player.y - 60, kind: 'heart', seed: 0 }, { x: player.x - 40, y: player.y - 60, kind: 'magnet', seed: 1 },
      { x: player.x + 40, y: player.y - 60, kind: 'bomb', seed: 2 }, { x: player.x + 120, y: player.y - 60, kind: 'chest', seed: 3 });
    makeEnemy('boss', player.x, player.y + 170);
    inputDir = () => ({ x: 0, y: 0 });
  });
  await page.waitForTimeout(400);
  await page.screenshot({ path: S + '/f-sv.png' });
  await page.close();

  // ---------- Phone layout ----------
  page = await browser.newPage({ viewport: { width: 390, height: 800 }, hasTouch: true, isMobile: true });
  page.on('pageerror', e => errors.push('mobile: ' + e.message));
  await page.goto('file://' + ROOT + '/color-claim/index.html');
  await page.evaluate(() => localStorage.setItem('color-claim-howto-seen', '1'));
  await page.tap('#play-btn');
  await page.waitForTimeout(1500);
  await page.tap('#pause-btn');
  ok('Phone: tap pause works (Color Claim)', await page.isVisible('#paused'));
  await page.tap('#resume-btn');
  await page.screenshot({ path: S + '/f-mobile.png' });
  await page.goto('file://' + ROOT + '/survivors/index.html');
  await page.tap('#play-btn');
  await page.waitForTimeout(800);
  await page.tap('#pause-btn');
  ok('Phone: tap pause works (Survivors)', await page.isVisible('#paused'));
  console.log('errors', errors);
  await browser.close();
})();
