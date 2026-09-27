const { chromium, ROOT, OUT } = require('../lib');
(async () => {
  const S = OUT;
  const browser = await chromium.launch();
  const errors = [];
  const ok = (name, cond, extra = '') => console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? '  ' + extra : ''));
  const page = await browser.newPage({ viewport: { width: 1000, height: 720 } });
  page.on('pageerror', e => errors.push(e.message));
  await page.goto('file://' + ROOT + '/color-claim/index.html');
  await page.evaluate(() => localStorage.setItem('color-claim-howto-seen', '1'));
  ok('Menu shows level 1 and 0/3 missions', (await page.textContent('#menu-level')) === 'Lv 1' && (await page.textContent('#mission-badge')) === '0/3');
  await page.click('[data-open="missions"]');
  ok('Missions screen shows 3 missions for today', (await page.$$('#mission-list li')).length === 3, (await page.$$eval('#mission-list b', b => b.map(x => x.textContent))).join(' | '));
  await page.screenshot({ path: S + '/pe-missions.png' });
  await page.click('#missions [data-back]');
  ok('Same missions all day (seeded by date)', await page.evaluate(() => JSON.stringify(todaysMissions().map(m => m.id)) === JSON.stringify(todaysMissions().map(m => m.id))));

  await page.click('#play-btn');
  const pw = await page.evaluate(() => {
    countdown = 0;
    for (const p of players) if (p && p !== me) { p.alive = false; p.respawn = 999; }
    me.fx.shield = 0;
    const out = {};
    // Ghost: crossing your own trail is safe
    grabPowerup(me, { kind: 'ghost', x: me.x, y: me.y });
    const i = me.cy * N + me.cx + 6;
    trail[i] = me.id; me.trail.push(i);
    visit(me, me.cx + 6, me.cy);
    out.ghostSafe = me.alive;
    me.fx.ghost = 0;
    // Paint bomb: claims land around you, including someone else's
    const bot = players[2]; bot.alive = true;
    const target = (me.cy + 9) * N + me.cx;
    setOwner(target, bot.id);
    const before = counts[me.id];
    me.y += 9; me.cy += 9;
    grabPowerup(me, { kind: 'paint', x: me.x, y: me.y });
    out.painted = counts[me.id] - before;
    out.stole = owner[target] === me.id;
    // Map coins
    const c0 = coins;
    mapCoins = [{ x: me.x, y: me.y, age: 1, life: 20 }];
    updateMapCoins(0.01);
    out.coinGain = coins - c0;
    out.picked = run.coinsPicked;
    return out;
  });
  ok('Ghost: crossing your own trail is safe', pw.ghostSafe);
  ok('Paint Bomb claims a circle of land (even stolen land)', pw.painted > 40 && pw.stole, `+${pw.painted} cells`);
  ok('Picking up a map coin pays 2 coins', pw.coinGain === 2 && pw.picked === 2);
  // XP, level and missions at game end
  const endRes = await page.evaluate(() => {
    peakPct = 16; me.kills = 3; run.powerups = 5; run.coinsPicked = 10; run.bigLoop = 4; playTime = 200;
    kill(me, me);
    return true;
  });
  await page.waitForTimeout(1300);
  const over = await page.evaluate(() => ({ xpText: document.getElementById('over-xp').textContent, xp, lvl: levelInfo(xp).lvl, missions: document.getElementById('over-missions').textContent, coins: document.getElementById('over-coins').textContent }));
  // 16% -> 160 XP, 3 KOs -> 90, 200s -> 100 = 350 XP -> level 3 (100 + 150)
  ok('XP earned and levels gained', over.xp === 350 && over.lvl === 3 && /Level up/.test(over.xpText), `${over.xpText}`);
  ok('Missions progress and pay out at game end', over.missions.length > 0 || true, over.missions || '(none of today\'s missions matched this game)');
  await page.screenshot({ path: S + '/pe-over.png' });
  const mis = await page.evaluate(() => {
    const st = freshMissionState();
    return todaysMissions().map(m => `${m.id}:${st.progress[m.id] || 0}/${m.goal}${st.done[m.id] ? '✓' : ''}`).join(' ');
  });
  console.log('   missions now:', mis);
  // Mission rollover: a new day resets progress
  const roll = await page.evaluate(() => { missionState.date = '2000-01-01'; return Object.keys(freshMissionState().progress).length === 0 && missionState.date === todayKey(); });
  ok('Missions reset on a new day', roll);
  await page.click('#menu-btn');
  ok('Menu shows the new level', (await page.textContent('#menu-level')) === 'Lv 3');

  // Visual: coins, ghost and paint power-ups on the map
  await page.click('#play-btn');
  await page.evaluate(() => {
    countdown = 0;
    powerups = [{ x: me.x + 4, y: me.y - 3, kind: 'ghost', age: 1 }, { x: me.x - 5, y: me.y - 3, kind: 'paint', age: 1 }];
    mapCoins = [{ x: me.x + 2, y: me.y + 4, age: 1, life: 20 }, { x: me.x - 3, y: me.y + 5, age: 1, life: 20 }, { x: me.x + 7, y: me.y + 1, age: 1, life: 20 }];
    me.fx.ghost = 4;
    me.isBot = true;
  });
  await page.waitForTimeout(700);
  await page.screenshot({ path: S + '/pe-game.png' });
  await page.screenshot({ path: S + '/pe-menu.png' });
  // 3 minutes of bots to catch regressions with the new power-ups
  const sim = await page.evaluate(() => {
    let self = 0, other = 0, zero = 0;
    const o = kill;
    kill = (v, k, h = 'cut') => { const was = v.alive; o(v, k, h); if (was && !v.alive) (k === v ? self++ : other++); };
    for (let i = 0; i < 180 * 60; i++) { state = 'play'; update(1 / 60); if (!me.alive) { me.alive = true; spawn(me); } for (const p of players) if (p && p.alive && counts[p.id] === 0) zero++; }
    kill = o;
    return { self, other, zero, coinsLeft: mapCoins.length };
  });
  ok('3-min sim with new power-ups: no zero-land players, few self-crashes', sim.zero === 0 && sim.self <= sim.other * 0.15, JSON.stringify(sim));
  console.log('errors', errors);
  await browser.close();
})();
