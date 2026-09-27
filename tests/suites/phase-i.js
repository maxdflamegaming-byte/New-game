const { chromium, ROOT, OUT } = require('../lib');
(async () => {
  const S = OUT;
  const browser = await chromium.launch();
  const errors = [];
  const ok = (name, cond, extra = '') => console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? '  ' + extra : ''));
  const ctx = await browser.newContext({ viewport: { width: 1100, height: 760 } });
  const page = await ctx.newPage();
  page.on('pageerror', e => errors.push(e.message));
  await page.goto('file://' + ROOT + '/color-claim/index.html');

  // ---- Personalities ----
  const pers = await page.evaluate(() => {
    myMode = 'classic'; myMap = 'square'; startGame();
    const bots = players.filter(p => p && p.isBot);
    return { ids: bots.map(p => p.persona), turtle: bots.find(p => p.persona === 'turtle'), coll: bots.find(p => p.persona === 'collector') };
  });
  ok('Every bot gets a personality', pers.ids.every(Boolean) && new Set(pers.ids).size >= 4, pers.ids.join(','));
  ok('Turtles flee early, collectors grab more', pers.turtle.fleeDist === 8 && pers.coll.grabChance === 0.9);
  const sim = await page.evaluate(() => {
    me.isBot = true; let self = 0, zero = 0;
    const o = kill; kill = (v, k, h = 'cut') => { const was = v.alive; o(v, k, h); if (was && !v.alive && k === v) self++; };
    for (let i = 0; i < 60 * 60; i++) { state = 'play'; update(1 / 60); if (!me.alive) { me.alive = true; spawn(me); } for (const p of players) if (p && p.alive && counts[p.id] === 0) zero++; }
    kill = o; return { self, zero };
  });
  ok('Bots with personalities play 60 s cleanly', sim.zero === 0 && sim.self <= 4, JSON.stringify(sim));
  await page.evaluate(() => { startGame(); countdown = 0; cam.zoom = 0.8; });
  await page.waitForTimeout(1200);
  await page.screenshot({ path: S + '/pi-tags.png' });
  await page.evaluate(() => { kill(me, me); });
  await page.waitForTimeout(1200);

  // ---- Replay ----
  ok('Game over offers "Watch replay"', await page.isVisible('#replay-btn'));
  const frames = await page.evaluate(() => replayFrames.length);
  ok('Replay keeps at most 10 seconds', frames > 5 && frames <= 100, 'frames=' + frames);
  await page.click('#replay-btn');
  await page.waitForTimeout(600);
  ok('Replay plays with its bar and no HUD', await page.evaluate(() => state === 'replay') && await page.isVisible('#replay-bar') && !(await page.isVisible('#hud')));
  await page.screenshot({ path: S + '/pi-replay.png' });
  await page.click('#replay-skip');
  ok('Skip returns to the game over screen', await page.evaluate(() => state === 'over') && await page.isVisible('#over') && !(await page.isVisible('#replay-bar')));
  await page.click('#replay-btn');
  await page.waitForTimeout(frames * 100 + 800);
  ok('Replay ends by itself', await page.evaluate(() => state === 'over') && await page.isVisible('#over'));
  const after = await page.evaluate(() => ({ alive: me.alive, pct: pct(me) }));
  ok('Real game state is restored after the replay', after.alive === false, JSON.stringify(after));
  await page.click('#menu-btn');

  // ---- Badges ----
  await page.evaluate(() => { achieved.land5 = todayKey(); });
  await page.evaluate(() => openScreen('trophies'));
  ok('Earned trophies have a Wear button, locked ones do not', await page.locator('.wear-btn').count() === await page.evaluate(() => Object.keys(achieved).length));
  await page.click('.wear-btn[data-badge="land5"]');
  ok('Wearing a badge saves it', await page.evaluate(() => myBadge === 'land5' && localStorage.getItem('color-claim-badge') === 'land5' && badgeName() === 'Land Grab'), await page.textContent('.wear-btn[data-badge="land5"]'));
  await page.click('[data-back]:visible');
  await page.evaluate(() => { localStorage.setItem('color-claim-howto-seen', '1'); startGame(); countdown = 0; });
  await page.waitForTimeout(1300);
  ok('Badge shows on the leaderboard', (await page.textContent('#board')).includes('Land Grab'));
  await page.screenshot({ path: S + '/pi-badge.png' });
  await page.evaluate(() => { state = 'menu'; me = null; gameCounter++; showScreen('trophies'); buildTrophies(); });
  await page.click('.wear-btn[data-badge="land5"]');
  ok('Pressing again takes the badge off', await page.evaluate(() => myBadge === '' && badgeName() === ''));
  await page.evaluate(() => showScreen('menu'));

  // ---- Tutorial ----
  const coins0 = await page.evaluate(() => { localStorage.removeItem('color-claim-howto-seen'); localStorage.removeItem('color-claim-tutorial-done'); return coins; });
  await page.click('#play-btn');
  ok('First Play shows how-to with a tutorial button', await page.isVisible('#howto') && await page.isVisible('#tutorial-btn'));
  await page.click('#tutorial-btn');
  await page.waitForTimeout(300);
  const t0 = await page.evaluate(() => ({ mode: gameMode.tutorial, bots: players.filter(p => p && p.isBot).length, pu: powerups.length, text: document.getElementById('tutorial-text').textContent }));
  ok('Tutorial starts with no bots and no power-ups', t0.mode && t0.bots === 0 && t0.pu === 0, JSON.stringify(t0));
  ok('Tutorial panel shows step 1', await page.isVisible('#tutorial-panel') && (await page.textContent('#tutorial-step')) === 'Step 1 of 5');
  // Steps 1 and 2: play them for real by letting the bot brain steer
  const s12 = await page.evaluate(() => {
    me.isBot = true; me.aggro = 0; me.greed = 20; me.loopScale = 0.8;
    const seen = [];
    for (let i = 0; i < 40 * 60 && tut.step < 2; i++) { update(1 / 60); if (!seen.includes(tut.step)) seen.push(tut.step); }
    me.isBot = false;
    return { step: tut.step, seen, pu: powerups.length };
  });
  ok('Leaving land and looping home finish steps 1 and 2', s12.step === 2 && s12.pu === 1, JSON.stringify(s12));
  await page.waitForTimeout(400);
  await page.screenshot({ path: S + '/pi-tut-powerup.png' });
  const s3 = await page.evaluate(() => {
    if (!me.alive) spawn(me, N / 2, N / 2); // the practice run can end in a crash; the real tutorial respawns you
    const p = powerups[0]; me.x = p.x; me.y = p.y;
    for (let i = 0; i < 10 && tut.step === 2; i++) update(1 / 60);
    return { step: tut.step, dummy: !!(tut.dummy && tut.dummy.alive), name: tut.dummy && tut.dummy.name };
  });
  ok('Grabbing the power-up brings the practice bot', s3.step === 3 && s3.dummy, JSON.stringify(s3));
  const dummyTrail = await page.evaluate(() => { let most = 0; for (let i = 0; i < 180; i++) { update(1 / 60); most = Math.max(most, tut.dummy.trail.length); } return most; });
  ok('Practice bot draws a trail to cut', dummyTrail > 0, 'trail=' + dummyTrail);
  await page.waitForTimeout(300);
  await page.screenshot({ path: S + '/pi-tut-dummy.png' });
  // Dying in the tutorial respawns instead of ending the game
  await page.evaluate(() => kill(me, me));
  await page.waitForTimeout(1300);
  ok('Dying in the tutorial respawns you', await page.evaluate(() => me.alive && state === 'play') && !(await page.isVisible('#over')));
  const s4 = await page.evaluate(() => { kill(tut.dummy, me); update(1 / 60); return tut.step; });
  ok('Knocking out the practice bot finishes step 4', s4 === 4);
  const s5 = await page.evaluate(() => {
    let need = Math.ceil(playCells * 0.16) - counts[me.id];
    for (let i = 0; i < N * N && need > 0; i++) if (!wall[i] && owner[i] !== me.id) { if (owner[i]) counts[owner[i]]--; owner[i] = me.id; counts[me.id]++; need--; }
    update(1 / 60);
    return { step: tut.step, state };
  });
  ok('Claiming 15% completes the tutorial', s5.step === 5 && s5.state === 'won', JSON.stringify(s5));
  await page.waitForTimeout(2600);
  const fin = await page.evaluate(c0 => ({ menu: state === 'menu', paid: coins - c0, flag: localStorage.getItem('color-claim-tutorial-done'), on: tutorialOn }), coins0);
  ok('Tutorial pays 50 coins and returns to the menu', fin.menu && fin.paid === 50 && fin.flag === '1' && !fin.on, JSON.stringify(fin));
  ok('Menu shows after the tutorial', await page.isVisible('#menu') && !(await page.isVisible('#tutorial-panel')));
  // Second run: skip, no second payout
  const c1 = await page.evaluate(() => coins);
  await page.evaluate(() => showHowto(false));
  await page.click('#tutorial-btn');
  await page.waitForTimeout(300);
  await page.click('#tutorial-skip');
  ok('Skip leaves the tutorial', await page.evaluate(() => state === 'menu' && !tutorialOn) && await page.isVisible('#menu'));
  await page.evaluate(() => { tut.step = 4; tutorialOn = true; startGame(); countdown = 0; tut.step = 4; let need = Math.ceil(playCells * 0.16) - counts[me.id]; for (let i = 0; i < N * N && need > 0; i++) if (!wall[i] && owner[i] !== me.id) { owner[i] = me.id; counts[me.id]++; need--; } update(1 / 60); });
  await page.waitForTimeout(2600);
  ok('Finishing again pays nothing extra', await page.evaluate(c => coins === c, c1));
  // Normal game after tutorial is normal
  const norm = await page.evaluate(() => { myMode = 'classic'; startGame(); return { tut: !!gameMode.tutorial, bots: players.filter(p => p && p.isBot).length }; });
  ok('A normal game after the tutorial has bots again', !norm.tut && norm.bots >= 5, JSON.stringify(norm));
  ok('Tutorial mode is hidden from the mode picker', !(await page.textContent('#modes')).includes('Tutorial'));

  // Mobile layout
  await page.setViewportSize({ width: 390, height: 780 });
  await page.evaluate(() => { resize(); tutorialOn = true; tut = { step: 0, dummy: null }; startGame(); countdown = 0; renderTutorial(); });
  await page.waitForTimeout(500);
  await page.screenshot({ path: S + '/pi-mobile.png' });
  const box = await page.locator('#tutorial-panel').boundingBox();
  ok('Tutorial panel fits on a phone', box && box.x >= 0 && box.x + box.width <= 390, JSON.stringify(box));

  ok('No page errors', errors.length === 0, errors.join(' | '));
  await browser.close();
})();
