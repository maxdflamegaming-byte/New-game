const { chromium, ROOT, OUT } = require('../lib');
(async () => {
  const S = OUT;
  const browser = await chromium.launch();
  const errors = [];
  const ok = (name, cond, extra = '') => console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? '  ' + extra : ''));
  const ctx = await browser.newContext({ viewport: { width: 1100, height: 760 }, permissions: ['clipboard-read', 'clipboard-write'] });
  const page = await ctx.newPage();
  page.on('pageerror', e => errors.push(e.message));
  await page.goto('file://' + ROOT + '/color-claim/index.html');
  await page.evaluate(() => localStorage.setItem('color-claim-howto-seen', '1'));

  // ---- Difficulty ----
  await page.click('#diffs .seg-btn:has-text("Hard")');
  ok('Difficulty picker saves', await page.evaluate(() => myDiff === 'hard' && localStorage.getItem('color-claim-diff') === 'hard'), await page.textContent('#mode-desc'));
  const diff = await page.evaluate(() => {
    const out = {};
    for (const d of ['easy', 'normal', 'hard']) { myDiff = d; startGame(); out[d] = +(speedOf(players[3]) / SPEED).toFixed(2); }
    myDiff = 'normal';
    return out;
  });
  ok('Easy bots are slower and Hard bots faster', diff.easy < diff.normal && diff.normal < diff.hard, JSON.stringify(diff));
  await page.screenshot({ path: S + '/ph-menu.png' });

  // ---- New maps: bots play 90 s on each with no one stuck in walls ----
  const maps = await page.evaluate(() => {
    const out = {};
    for (const m of ['maze', 'islands']) {
      let stuck = 0, self = 0, other = 0, zero = 0;
      for (let g = 0; g < 6; g++) { // 6 games, so one unlucky game doesn't decide it
      myMode = 'classic'; myMap = m; startGame(); me.isBot = true;
      const o = kill;
      kill = (v, k, h = 'cut') => { const was = v.alive; o(v, k, h); if (was && !v.alive) (k === v ? self++ : other++); };
      for (let i = 0; i < 90 * 60; i++) { state = 'play'; update(1 / 60); if (!me.alive) { me.alive = true; spawn(me); } for (const p of players) if (p && p.alive) { if (isWallAt(p.x, p.y)) stuck++; if (counts[p.id] === 0) zero++; } }
      kill = o;
      }
      out[m] = { floor: Math.round(playCells / (N * N) * 100), stuck, self, other, zero, alive: players.filter(p => p && p.alive).length };
    }
    return out;
  });
  for (const [m, r] of Object.entries(maps)) ok(`${m} map: playable with bots`, r.stuck === 0 && r.zero === 0 && r.self <= Math.max(4, (r.self + r.other) * 0.2) && r.alive >= 6, JSON.stringify(r));
  for (const m of ['maze', 'islands']) {
    await page.evaluate(m => { myMap = m; startGame(); countdown = 0; cam.zoom = 0.45; BASE_CELL = 9; for (const p of players) if (p && p !== me) p.isBot = true; }, m);
    await page.waitForTimeout(1500);
    await page.screenshot({ path: `${S}/ph-${m}.png` });
    await page.evaluate(() => { resize(); });
  }

  // ---- Challenge codes ----
  const round = await page.evaluate(() => {
    const c = { seed: 3141592653, mode: 'timed', map: 'maze', diff: 'hard', score: 23.4 };
    const code = makeCode(c);
    const back = readCode(code);
    const typo = readCode(code.slice(0, 3) + (code[3] === 'A' ? 'B' : 'A') + code.slice(4));
    return { code, same: JSON.stringify(back) === JSON.stringify(c), typo };
  });
  ok('Challenge codes round-trip', round.same, round.code);
  ok('A typo in the code is rejected', round.typo === null);
  // Make a code from a finished game
  const firstLayout = await page.evaluate(() => { myMode = 'classic'; myMap = 'pillars'; myDiff = 'normal'; startGame(); const l = JSON.stringify(players.filter(Boolean).map(p => [p.name, Math.round(p.x), Math.round(p.y)])); countdown = 0; peakPct = 12.3; kill(me, me); return l; });
  await page.waitForTimeout(1200);
  ok('Game over offers "Challenge a friend"', await page.isVisible('#challenge-make'));
  await page.click('#challenge-make');
  const code = await page.inputValue('#challenge-code-text');
  await page.click('#challenge-copy');
  const clip = await page.evaluate(() => navigator.clipboard.readText().catch(() => ''));
  ok('The code can be copied', clip === code, code);
  // Friend enters the code
  await page.click('#menu-btn');
  await page.evaluate(() => openScreen('challenge'));
  await page.fill('#challenge-input', code.toLowerCase());
  ok('Entering a code shows what it is', (await page.textContent('#challenge-info')).includes('Pillars'), await page.textContent('#challenge-info'));
  await page.screenshot({ path: S + '/ph-challenge.png' });
  await page.click('#challenge-play');
  const secondLayout = await page.evaluate(() => JSON.stringify(players.filter(Boolean).map(p => [p.name, Math.round(p.x), Math.round(p.y)])));
  ok('The challenge starts with the same bots and starting map', firstLayout === secondLayout);
  await page.waitForTimeout(300);
  ok('The HUD shows the score to beat', (await page.textContent('#team-score')).includes('12.3'), await page.textContent('#team-score'));
  await page.evaluate(() => { countdown = 0; peakPct = 15; kill(me, me); });
  await page.waitForTimeout(1200);
  ok('Beating the score counts as a win', (await page.textContent('#challenge-result')).includes('beaten') && await page.evaluate(() => stats.challenges === 1 && !!achieved.challenger));
  await page.click('#menu-btn');
  ok('Leaving the challenge returns to normal games', await page.evaluate(() => challenge === null));

  // ---- Cup: 3 rounds ----
  await page.click('#modes .seg-btn:has-text("Cup")');
  const c0 = await page.evaluate(() => coins);
  await page.click('#play-btn');
  const cupInfo = await page.evaluate(() => ({ maps: cup.maps, round: cup.round, time: gameMode.time, map: gameMapId }));
  ok('Cup: 3 rounds on 3 different maps', new Set(cupInfo.maps).size === 3 && cupInfo.map === cupInfo.maps[0] && cupInfo.time === 120, cupInfo.maps.join(','));
  const names1 = await page.evaluate(() => players.filter(Boolean).map(p => p.name).join());
  for (let r = 1; r <= 3; r++) {
    await page.evaluate(() => { countdown = 0; for (const p of players) if (p) p.fx.shield = 0; for (let i = 0; i < N * N * 0.3; i++) if (!wall[i] && !owner[i]) setOwner(i, me.id); playTime = 119.95; });
    await page.waitForTimeout(2400);
    ok(`Cup round ${r}: standings shown`, await page.isVisible('#cup') && (await page.$$('#cup-table tr')).length === 8, (await page.textContent('#cup-title')).trim());
    if (r === 1) {
      const names2 = await page.evaluate(() => Object.keys(cup.points).sort().join());
      ok('Cup: the same players in every round', names2 === names1.split(',').sort().join());
      await page.screenshot({ path: S + '/ph-cup.png' });
    }
    await page.click('#cup-next');
  }
  const after = await page.evaluate(() => ({ cup, coins, cups: stats.cups, champ: !!achieved.champion, state }));
  ok('Winning the Cup pays the prize and the Champion trophy', after.cups === 1 && after.champ && after.coins - c0 >= 150 && after.cup === null && after.state === 'menu', `+${after.coins - c0} coins`);
  console.log('errors', errors);
  await browser.close();
})();
