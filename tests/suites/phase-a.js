const { chromium, ROOT, OUT } = require('../lib');
(async () => {
  const S = OUT;
  const browser = await chromium.launch();
  const errors = [];
  const ok = (name, cond, extra = '') => console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? '  ' + extra : ''));
  const page = await browser.newPage({ viewport: { width: 1000, height: 700 } });
  page.on('pageerror', e => errors.push(e.message));
  await page.goto('file://' + ROOT + '/color-claim/index.html');
  await page.click('#play-btn');
  ok('First Play shows How to play', await page.isVisible('#howto'));
  await page.screenshot({ path: S + '/pa-howto.png' });
  await page.click('#howto-btn');
  ok("Let's go starts the game", await page.evaluate(() => state === 'play'));
  const start = await page.evaluate(() => ({ x: me.x, y: me.y }));
  await page.waitForTimeout(1500);
  await page.screenshot({ path: S + '/pa-countdown.png' });
  const mid = await page.evaluate(() => ({ x: me.x, y: me.y, cd: countdown, bots: players.slice(2).map(p => p.x) }));
  ok('Nobody moves during the countdown', mid.x === start.x && mid.y === start.y && mid.cd > 0);
  await page.waitForTimeout(2000);
  const after = await page.evaluate(() => ({ moved: Math.hypot(me.x - 40.5, me.y - 40.5) > 0.5, shield: me.fx.shield, cd: countdown }));
  ok('Play starts after 3-2-1', after.moved && after.cd <= 0);
  ok('Spawn shield active right after GO', after.shield > 0 && after.shield <= 3, 'shield=' + after.shield.toFixed(2));
  ok('Music plays during the game', await page.evaluate(() => Music.playing || !Music.enabled));
  await page.click('#music-btn');
  ok('Music button turns music off', await page.evaluate(() => !Music.playing && !Music.enabled));
  await page.click('#music-btn');

  // Threat markers
  const th = await page.evaluate(() => {
    countdown = 0;
    for (const p of players) if (p) p.fx.shield = 0;
    // give me a trail and put a bot near it, another far away
    const cells = [];
    for (let k = 1; k <= 8; k++) { const i = me.cy * N + me.cx + k; trail[i] = me.id; me.trail.push(i); cells.push(i); }
    const [near, far] = players.filter(p => p && p !== me && p.alive && !p.isBoss);
    near.x = me.x + 5; near.y = me.y + 3; far.x = me.x - 30; far.y = me.y - 30;
    for (const p of players) if (p && p !== me && p !== near && p !== far) { p.alive = false; p.respawn = 999; }
    me.isBot = false;
    // run the danger part of the update without moving anyone
    const saved = players.map(p => p && { x: p.x, y: p.y });
    update(0.001);
    return { near: threats.includes(near), far: threats.includes(far) };
  });
  ok('Enemy near your trail is marked as a threat', th.near && !th.far);
  await page.evaluate(() => { players[2].x = me.x + 40; players[2].y = me.y; for (let k = 9; k <= 30; k++) { const i = me.cy * N + me.cx + k; trail[i] = me.id; me.trail.push(i); } });
  await page.waitForTimeout(200);
  await page.screenshot({ path: S + '/pa-threat.png' });

  // Bots get bolder as you grow
  const bold = await page.evaluate(() => {
    // Freeze movement, keep you alive with a trail, and keep only one bot
    speedOf = () => 0;
    me.alive = true;
    if (me.trail.length < 4) for (let k = 3; k <= 8; k++) { const i = me.cy * N + me.cx + k; trail[i] = me.id; me.trail.push(i); }
    // Only this bot and you, so we measure hunts on *your* trail
    for (const p of players) if (p && p !== me && p.id !== 4) { p.alive = false; p.respawn = 999; }
    const count = () => {
      let hunts = 0;
      for (let t = 0; t < 400; t++) {
        const bot = players[4];
        bot.alive = true; bot.mode = 'idle'; bot.wp = []; bot.trail = [];
        bot.x = me.x + 20; bot.y = me.y; bot.cx = Math.floor(bot.x); bot.cy = Math.floor(bot.y);
        owner[bot.cy * N + bot.cx] = bot.id;
        think(bot);
        if (bot.mode === 'hunt') hunts++;
      }
      return hunts;
    };
    me.fx.shield = 0;
    const small = count();
    const saved = counts[me.id];
    counts[me.id] = Math.floor(N * N * 0.3);
    const big = count();
    counts[me.id] = saved;
    return { small, big };
  });
  ok('Bots hunt you more when you are big', bold.big > bold.small + 50, JSON.stringify(bold));

  // Second game: no tutorial
  await page.evaluate(() => { state = 'over'; showScreen('over'); });
  await page.click('#menu-btn');
  await page.click('#play-btn');
  ok('How to play only shows the first time', await page.evaluate(() => state === 'play') && !(await page.isVisible('#howto')));
  console.log('errors', errors);
  await browser.close();
})();
