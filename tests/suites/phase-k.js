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
  await page.evaluate(() => { localStorage.setItem('color-claim-howto-seen', '1'); localStorage.setItem('color-claim-tutorial-done', '1'); });
  const menuOff = () => page.evaluate(() => { state = 'menu'; me = null; gameCounter++; showScreen('menu'); });

  // ---------- Streaks ----------
  ok('Menu invites you to start a streak', (await page.textContent('#streak-line')).includes('Start a streak'));
  await page.screenshot({ path: S + '/pk-menu.png' });
  const s1 = await page.evaluate(() => { myMode = 'classic'; myMap = 'square'; startGame(); countdown = 0; const c0 = coins; const r = finishRun(false, 3); return { day: r.streakDay && r.streakDay.day, paid: r.streakDay && r.streakDay.coins, again: finishRun(false, 3).streakDay }; });
  ok('First game of the day starts a streak and pays 20', s1.day === 1 && s1.paid === 20 && s1.again === null, JSON.stringify(s1));
  await menuOff();
  await page.evaluate(() => renderStreak());
  ok('Menu shows the streak after playing', (await page.textContent('#streak-line')).includes('1-day streak!'));
  const s7 = await page.evaluate(() => {
    streak = { last: yesterdayKey(), count: 6, best: 6 };
    startGame(); countdown = 0;
    const star = PETS.find(p => p.id === 'star');
    const before = petOpen(star);
    const r = finishRun(false, 3).streakDay;
    return { r, before, after: petOpen(star) };
  });
  ok('Day 7 pays 150 and unlocks the Star Sprite', s7.r.day === 7 && s7.r.coins === 150 && s7.r.pet && !s7.before && s7.after, JSON.stringify(s7));
  const lost = await page.evaluate(() => { streak = { last: '2020-01-01', count: 5, best: 7 }; const n = streakNow(); startGame(); countdown = 0; return { n, day: finishRun(false, 1).streakDay.day }; });
  ok('Missing a day starts the streak again', lost.n === 0 && lost.day === 1, JSON.stringify(lost));
  const s8 = await page.evaluate(() => { streak = { last: yesterdayKey(), count: 9, best: 9 }; startGame(); countdown = 0; return finishRun(false, 1).streakDay.coins; });
  ok('After day 7 every day pays 100', s8 === 100);
  await page.evaluate(() => { streak = { last: yesterdayKey(), count: 2, best: 9 }; save('color-claim-streak', JSON.stringify(streak)); startGame(); countdown = 0; peakPct = 4; kill(me, me); });
  await page.waitForTimeout(1300);
  ok('Game over shows the streak reward', await page.isVisible('#over-streak') && (await page.textContent('#over-streak')).includes('Day 3 streak! +40 coins'), await page.textContent('#over-streak'));
  await page.click('#again-btn');
  await page.evaluate(() => { countdown = 0; peakPct = 4; kill(me, me); });
  await page.waitForTimeout(1300);
  ok('Only the first game of the day pays the streak', !(await page.isVisible('#over-streak')));
  await page.click('#menu-btn');
  ok('Stats show your streak', await page.evaluate(() => { buildStats(); return document.getElementById('stats-grid').textContent.includes('Day streak'); }));

  // ---------- Pets ----------
  const pet = await page.evaluate(() => {
    myMap = 'square'; startGame(); countdown = 0;
    for (let i = 0; i < 120; i++) update(1 / 60);
    return { pet: me.pet, d: Math.hypot(me.petX - me.x, me.petY - me.y) };
  });
  ok('Your Chick follows you around', pet.pet === 'chick' && pet.d > 0.8 && pet.d < 3, JSON.stringify(pet));
  const botPets = await page.evaluate(() => { let n = 0; for (let g = 0; g < 6; g++) { startGame(); n += players.filter(p => p && p.isBot && p.pet !== 'none').length; } return n; });
  ok('Some bots bring pets', botPets > 0 && botPets < 42, 'bot pets in 6 games: ' + botPets);
  await page.evaluate(() => { startGame(); countdown = 0; cam.zoom = 1.6; });
  await page.waitForTimeout(900);
  await page.screenshot({ path: S + '/pk-pet.png' });
  await menuOff();
  await page.evaluate(() => { coins = 500; renderCoins(); rankBest = 0; streak.best = 0; ownedPets = ['none', 'chick']; lockerTab = 'pets'; showScreen('locker'); buildLocker(); });
  ok('Locker has a Pets tab with 8 pets', await page.locator('#locker-items .item').count() === 8);
  ok('Rank pets say how to unlock them', (await page.textContent('#locker-items')).includes('Reach Silver rank') && (await page.textContent('#locker-items')).includes('Play 7 days in a row'));
  await page.click('#locker-items .item >> nth=2 >> .item-btn');
  ok('Buying the Slime equips it', await page.evaluate(() => myPet === 'slime' && ownedPets.includes('slime') && coins === 380 && localStorage.getItem('color-claim-pet') === 'slime'));
  await page.evaluate(() => { rankBest = 2; buildLocker(); });
  ok('Reaching Gold unlocks the Dragon', await page.evaluate(() => petOpen(PETS.find(p => p.id === 'dragon')) && !petOpen(PETS.find(p => p.id === 'ufo'))));
  await page.screenshot({ path: S + '/pk-locker.png' });
  await page.click('#locker-items .item >> nth=5 >> .item-btn');
  ok('Dragon can be used', await page.evaluate(() => myPet === 'dragon'));
  await menuOff();
  const recPet = await page.evaluate(() => { startGame(); countdown = 0; for (let i = 0; i < 20; i++) update(1 / 60); recordFrame(); return replayFrames[replayFrames.length - 1].ps[1].px > 0 && me.pet === 'dragon'; });
  ok('Replays remember pets', recPet);
  await menuOff();

  // ---------- Conveyor ----------
  const belts = await page.evaluate(() => {
    myMap = 'belts'; startGame(); countdown = 0;
    let cells = 0; for (let i = 0; i < N * N; i++) if (belt[i]) cells++;
    // Find a belt that pushes right and ride it
    const i = belt.findIndex(d => d === 1), x = i % N, y = Math.floor(i / N);
    const run = onBelt => {
      me.x = (onBelt ? x + 3 : 40) + 0.5; me.y = (onBelt ? y + 1 : 40) + 0.5; me.cx = Math.floor(me.x); me.cy = Math.floor(me.y);
      me.angle = me.desired = Math.PI; me.fx.shield = 99; mouse.active = false; // drive left, against the belt
      const x0 = me.x; for (let k = 0; k < 20; k++) move(me, 1 / 60);
      return me.x - x0;
    };
    const on = run(true), off = run(false);
    return { cells, push: +(on - off).toFixed(2), on: +on.toFixed(2), off: +off.toFixed(2) };
  });
  ok('Conveyor belts push you along', belts.cells > 500 && Math.abs(belts.push - 2.6 / 3) < 0.05, JSON.stringify(belts));
  await page.evaluate(() => { startGame(); countdown = 0; cam.zoom = 0.55; me.x = N * 0.25; me.y = N * 0.3; cam.x = me.x; cam.y = me.y; });
  await page.waitForTimeout(900);
  await page.screenshot({ path: S + '/pk-belts.png' });
  await menuOff();

  // ---------- Portals ----------
  const tp = await page.evaluate(() => {
    myMap = 'portals'; startGame(); countdown = 0;
    const a = portals[0], b = portals[a.link];
    me.fx.shield = 99; mouse.active = false;
    me.x = a.x - 3; me.y = a.y; me.cx = Math.floor(me.x); me.cy = Math.floor(me.y); me.angle = me.desired = 0;
    for (let k = 0; k < 40 && Math.hypot(me.x - b.x, me.y - b.y) > 3; k++) { move(me, 1 / 60); checkPortals(me); }
    const out = { n: portals.length, near: +Math.hypot(me.x - b.x, me.y - b.y).toFixed(2), cam: +Math.hypot(cam.x - me.x, cam.y - me.y).toFixed(2), trail: me.trail.length, wait: me.portalWait > time };
    // Can't bounce straight back
    me.x = b.x; me.y = b.y; checkPortals(me);
    out.bounce = Math.hypot(me.x - b.x, me.y - b.y) > 3;
    return out;
  });
  ok('Portals send you to their twin', tp.n === 4 && tp.near < 2.5 && tp.cam < 0.01 && tp.wait, JSON.stringify(tp));
  ok('No instant bounce back', !tp.bounce);
  await page.evaluate(() => { startGame(); countdown = 0; cam.zoom = 0.7; me.x = N * 0.25; me.y = N * 0.22; cam.x = me.x; cam.y = me.y; });
  await page.waitForTimeout(900);
  await page.screenshot({ path: S + '/pk-portals.png' });
  await menuOff();
  const sims = await page.evaluate(() => {
    const out = {};
    for (const m of ['belts', 'portals']) {
      const c = { self: 0, other: 0, stuck: 0, zero: 0, teleports: 0 };
      for (let g = 0; g < 2; g++) {
        myMode = 'classic'; myMap = m; startGame(); countdown = 0; me.isBot = true;
        const o = kill, t = teleport;
        kill = (v, k, h = 'cut') => { const was = v.alive; o(v, k, h); if (was && !v.alive) { if (k === v) c.self++; else c.other++; } };
        teleport = (...a) => { c.teleports++; t(...a); };
        for (let i = 0; i < 150 * 60; i++) { state = 'play'; update(1 / 60); if (!me.alive) { me.alive = true; spawn(me); } for (const p of players) if (p && p.alive) { if (wall[p.cy * N + p.cx]) c.stuck++; if (counts[p.id] === 0) c.zero++; } }
        kill = o; teleport = t;
      }
      out[m] = c;
    }
    state = 'menu'; me = null; gameCounter++;
    return out;
  });
  for (const [m, c] of Object.entries(sims)) ok(`${m}: bots play cleanly`, c.stuck === 0 && c.zero === 0 && c.self <= Math.max(3, c.other * 0.2), JSON.stringify(c));
  const codes = await page.evaluate(() => ['belts', 'portals'].map(m => { const c = { seed: 7, mode: 'timed', map: m, diff: 'easy', score: 9.9 }; return JSON.stringify(readCode(makeCode(c))) === JSON.stringify(c); }));
  ok('Challenge codes work on the new maps', codes.every(Boolean));

  // ---------- Weekly ----------
  await page.evaluate(() => { showScreen('menu'); localStorage.setItem('color-claim-ghost-1', '{"score":1}'); });
  await page.click('#modes .seg-btn:has-text("Weekly")');
  const wk = await page.evaluate(() => ({ desc: document.getElementById('mode-desc').textContent, disabled: [...document.querySelectorAll('#maps .seg-btn')].every(b => b.disabled), best: document.getElementById('menu-best').textContent }));
  ok('Weekly locks the map to this week\'s', wk.disabled && wk.desc.includes("This week's map: " + (await page.evaluate(() => MAPS[weeklyMap()].name))) && wk.desc.includes('Ranked') && wk.best.includes("This week's best"), JSON.stringify(wk));
  const same = await page.evaluate(() => {
    const snap = () => { startGame(); return JSON.stringify([gameMapId, players.filter(Boolean).map(p => [p.name, Math.round(p.x), Math.round(p.y)])]); };
    const a = snap(), b = snap();
    return { same: a === b, map: gameMapId, time: gameMode.time };
  });
  ok('Everyone gets the same start all week', same.same && same.time === 180, JSON.stringify(same));
  await page.evaluate(() => { countdown = 0; updateHud(); });
  ok('No ghost the first time', (await page.textContent('#team-score')).includes('No ghost yet'));
  const run1 = await page.evaluate(() => {
    me.isBot = true; me.fx.shield = 99;
    for (let i = 0; i < 25 * 60 && me.alive; i++) { state = 'play'; update(1 / 60); }
    me.fx.shield = 0;
    me.isBot = false;
    return { rec: ghostRec.pcts.length, path: ghostRec.path.length, t: +playTime.toFixed(1) };
  });
  ok('Your run is recorded 10 times a second', Math.abs(run1.rec - run1.t * 10) <= 2 && run1.path === run1.rec * 2, JSON.stringify(run1));
  await page.evaluate(() => { peakPct = Math.max(peakPct, 2); kill(me, me); });
  await page.waitForTimeout(1300);
  const saved = await page.evaluate(() => { const g = JSON.parse(localStorage.getItem(ghostKey())); return { score: g.score, n: g.pcts.length, old: localStorage.getItem('color-claim-ghost-1'), ranked: document.getElementById('over-rank').classList.contains('hidden') === false, best: document.getElementById('over-best').textContent, code: lastChallenge && lastChallenge.mode }; });
  ok('A new weekly best saves your ghost', saved.score > 0 && saved.n >= run1.rec && saved.best.includes('ghost will race you'), JSON.stringify(saved));
  ok('Old weeks\' ghosts are cleared', saved.old === null);
  ok('Weekly is ranked and shares as a Timed challenge', saved.ranked && saved.code === 'timed');
  await page.click('#again-btn');
  const race = await page.evaluate(() => {
    countdown = 0;
    const frames = Math.min(5 * 60, Math.floor((ghostRun.pcts.length / 10 - 0.5) * 60));
    for (let i = 0; i < frames; i++) update(1 / 60);
    updateHud();
    const g = ghostNow(), P = ghostRun.path, k = Math.floor(playTime * 10);
    return { g: !!g, match: g && Math.abs(g.x - P[k * 2] / 10) < 1.5, hud: document.getElementById('team-score').textContent };
  });
  ok('Next time the ghost races you', race.g && race.match && race.hud.includes('Ghost'), JSON.stringify(race));
  await page.evaluate(() => { cam.zoom = 0.8; });
  await page.waitForTimeout(700);
  await page.screenshot({ path: S + '/pk-weekly.png' });
  const late = await page.evaluate(() => { playTime = ghostRun.pcts.length / 10 + 5; updateHud(); return { g: ghostNow(), hud: document.getElementById('team-score').textContent }; });
  ok('After the ghost\'s run ends, the HUD shows the score to beat', late.g === null && late.hud.includes('Best'), late.hud);
  await menuOff();
  await page.evaluate(() => { myMode = 'classic'; save('color-claim-mode', 'classic'); buildPickers(); });

  // Mobile
  await page.setViewportSize({ width: 390, height: 780 });
  await page.evaluate(() => { resize(); showScreen('menu'); renderStreak(); });
  await page.screenshot({ path: S + '/pk-menu-mobile.png' });
  const wide = await page.evaluate(() => document.documentElement.scrollWidth);
  ok('Menu fits on a phone', wide <= 390, 'scrollWidth=' + wide);
  await page.evaluate(() => { lockerTab = 'pets'; showScreen('locker'); buildLocker(); });
  await page.screenshot({ path: S + '/pk-locker-mobile.png' });

  ok('No page errors', errors.length === 0, errors.join(' | '));
  await browser.close();
})();
