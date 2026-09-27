const { chromium, ROOT, OUT } = require('../lib');
(async () => {
  const S = OUT;
  const browser = await chromium.launch();
  const errors = [];
  const ok = (name, cond, extra = '') => console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? '  ' + extra : ''));
  const page = await browser.newPage({ viewport: { width: 1100, height: 760 } });
  page.on('pageerror', e => errors.push(e.message));
  await page.goto('file://' + ROOT + '/color-claim/index.html');
  await page.evaluate(() => { localStorage.setItem('color-claim-howto-seen', '1'); localStorage.setItem('color-claim-tutorial-done', '1'); localStorage.removeItem('color-claim-last-killer'); });
  const menuOff = () => page.evaluate(() => { state = 'menu'; me = null; gameCounter++; showScreen('menu'); });

  // ---------- Bug fixes ----------
  const shield = await page.evaluate(() => {
    myMode = 'classic'; myMap = 'square'; startGame(); countdown = 0;
    const a = players[3], b = players[4];
    a.fx.shield = 5; b.fx.shield = 0;
    const i = 10 * N + 10; trail[i] = a.id; a.trail = [i]; setOwner(i, 0);
    b.trail = []; visit(b, 10, 10);
    return { aAlive: a.alive, cell: trail[i] === a.id, bTrail: b.trail.includes(i) };
  });
  ok("Crossing a shielded player's trail doesn't steal the cell", shield.aAlive && shield.cell && !shield.bTrail, JSON.stringify(shield));
  const spawns = await page.evaluate(() => {
    const bad = [];
    for (const m of ['maze', 'islands', 'pillars', 'round']) for (let k = 0; k < 8; k++) {
      myMode = 'duo'; myMap = m; startGame();
      for (const p of [me, p2]) if (wall[p.cy * N + p.cx] || counts[p.id] < 13) bad.push(`${m}:${p.name}:${counts[p.id]}`);
    }
    myMode = 'classic';
    return bad;
  });
  ok('2-player spawns always land on open ground with a full start patch', spawns.length === 0, spawns.join(', '));
  const safeWin = await page.evaluate(() => {
    myMode = 'classic'; myMap = 'square'; startGame(); countdown = 0; me.fx.shield = 0;
    state = 'won'; kill(me, players[3]);
    const alive = me.alive; state = 'play';
    return alive;
  });
  ok("You can't be knocked out during your victory", safeWin);
  const boss = await page.evaluate(() => { myMode = 'boss'; startGame(); countdown = 0; king.fx.shield = 0; king.hp = 1; kill(king, me); const st = state; myMode = 'classic'; return st; });
  ok('Beating a boss wins at once', boss === 'won');
  await menuOff();

  // ---------- Speed ----------
  const perf = await page.evaluate(() => {
    myMode = 'marathon'; settings.theme = 'classic'; startGame(); countdown = 0;
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) setOwner(y * N + x, 1 + ((Math.floor(x / 13) + Math.floor(y / 11)) % 8));
    cam.zoom = 0.65; state = 'paused';
    const frame = () => { draw(1 / 60); ctx.getImageData(0, 0, 1, 1); };
    for (let i = 0; i < 5; i++) frame();
    const t0 = performance.now(); for (let i = 0; i < 60; i++) frame();
    const ms = (performance.now() - t0) / 60;
    state = 'menu'; me = null; gameCounter++;
    return +ms.toFixed(2);
  });
  ok('A full frame on the biggest map draws in under 12 ms (software rendering)', perf < 12, perf + ' ms');
  ok('The vignette is a CSS layer, not painted each frame', await page.evaluate(() => getComputedStyle(document.getElementById('vignette')).position === 'fixed'));

  // ---------- Hype ----------
  const combo = await page.evaluate(() => {
    myMode = 'classic'; myMap = 'square'; startGame(); countdown = 0;
    const c0 = coins;
    for (let k = 0; k < 3; k++) hypeCapture(1);
    return { combo: hype.combo, coins: coins - c0, best: run.bestCombo, queue: hype.queue.map(q => q.text) };
  });
  ok('Quick loops build a combo that pays coins', combo.combo === 3 && combo.coins === 4 + 6 && combo.best === 3 && combo.queue.includes('COMBO ×3!'), JSON.stringify(combo));
  await page.waitForTimeout(300);
  ok('The combo meter shows in the HUD', await page.isVisible('#combo') && (await page.textContent('#combo')).includes('×3'));
  const decay = await page.evaluate(() => { for (let i = 0; i < 400; i++) update(1 / 60), updateHype(1 / 60, 1 / 60); return hype.combo; });
  ok('The combo runs out if you wait too long', decay === 0);
  const kos = await page.evaluate(() => {
    hype.queue = []; hype.kos = [];
    const [a, b] = players.filter(p => p && p !== me && p.alive); // bots still in the game
    a.fx.shield = b.fx.shield = 0;
    kill(a, me); kill(b, me);
    return hype.queue.map(q => q.text);
  });
  ok('Two quick knockouts: DOUBLE KO!', kos.includes('DOUBLE KO!'), kos.join(','));
  await page.waitForTimeout(150);
  ok('Callouts pop up on screen', await page.isVisible('#callout') && /KO|COMBO/.test(await page.textContent('#callout')), await page.textContent('#callout'));
  await page.screenshot({ path: S + '/pp-callout.png' });
  const close = await page.evaluate(() => { hype.queue = []; const c0 = coins; hype.nearMiss = 2; hypeCapture(0.5); return { q: hype.queue.map(q => q.text), paid: coins - c0 }; });
  ok('Getting home just in time: CLOSE CALL!', close.q.includes('CLOSE CALL!') && close.paid >= 3, JSON.stringify(close));
  const big = await page.evaluate(() => { hype.queue = []; hype.comboTimer = 0; hypeCapture(6); const a = hype.queue.map(q => q.text); hype.queue = []; hype.comboTimer = 0; hypeCapture(12); return { a, b: hype.queue.map(q => q.text), flash: screenFlash }; });
  ok('Big loops: MEGA LOOP! and GIGA LOOP!', big.a.includes('MEGA LOOP!') && big.b.includes('GIGA LOOP!') && big.flash > 0, JSON.stringify(big));
  const shut = await page.evaluate(() => {
    hype.queue = [];
    const v = players.find(p => p && p !== me && p.alive); v.fx.shield = 0;
    let need = Math.ceil(playCells * 0.15) - counts[v.id];
    for (let i = 0; i < N * N && need > 0; i++) if (!wall[i] && !owner[i]) { setOwner(i, v.id); need--; }
    const c0 = coins; kill(v, me);
    return { q: hype.queue.map(q => q.text), paid: coins - c0 };
  });
  ok('Knocking out the leader: SHUTDOWN!', shut.q.includes('SHUTDOWN!'), JSON.stringify(shut));
  const parts = await page.evaluate(() => { particles = []; const v = players.find(p => p && p.isBot && p.alive && counts[p.id] > 10); v.fx.shield = 0; kill(v, me); return particles.length; });
  ok('Knocked-out land shatters into tiles', parts > 40, 'particles ' + parts);
  // Revenge
  await page.evaluate(() => { me.fx.shield = 0; kill(me, players[7]); });
  await page.waitForTimeout(1300);
  const killerName = await page.evaluate(() => localStorage.getItem('color-claim-last-killer'));
  ok('The bot that got you is remembered', !!killerName, killerName);
  ok('Game over nudges you about revenge', (await page.textContent('#over-nudge')).includes(killerName));
  const podium = await page.evaluate(() => ({ steps: document.querySelectorAll('#over-podium .podium-step:not(.empty)').length, visible: !document.getElementById('over-podium').classList.contains('hidden') }));
  ok('Game over shows a podium', podium.visible && podium.steps === 3, JSON.stringify(podium));
  await page.screenshot({ path: S + '/pp-over.png' });
  await page.click('#again-btn');
  const rev = await page.evaluate(name => { countdown = 0; const t = hype.revenge; const c0 = coins; hype.queue = []; t.fx.shield = 0; kill(t, me); return { marked: !!t && t.name === name, q: hype.queue.map(q => q.text), paid: coins - c0 }; }, killerName);
  ok('Next game they are marked, and knocking them out is REVENGE!', rev.marked && rev.q.includes('REVENGE!') && rev.paid >= 10, JSON.stringify(rev));
  // Milestones, comeback, last seconds
  const marks = await page.evaluate(() => {
    hype.queue = []; hype.wasLow = true; hype.top = false; hype.rankTimer = 0;
    let need = Math.ceil(playCells * 0.26) - counts[me.id];
    for (let i = 0; i < N * N && need > 0; i++) if (!wall[i] && !owner[i] && !trail[i]) { setOwner(i, me.id); need--; }
    updateHype(1 / 60, 1 / 60);
    return hype.queue.map(q => q.text);
  });
  ok('Milestones and COMEBACK! callouts', marks.includes('10% CLAIMED') && marks.includes('DOMINATING!') && marks.includes('COMEBACK!'), marks.join(','));
  const ticks = await page.evaluate(() => { myMode = 'timed'; startGame(); countdown = 0; hype.queue = []; playTime = 170.5; updateHype(1 / 60, 1 / 60); myMode = 'classic'; return hype.queue.map(q => q.text); });
  ok('Timed games count down the last 10 seconds', ticks.includes('10 SECONDS!'), ticks.join(','));
  const slow = await page.evaluate(() => { myMode = 'classic'; startGame(); countdown = 0; win(); return { slowmo, st: state }; });
  ok('Winning plays in slow motion with a VICTORY! callout', slow.slowmo > 1 && slow.st === 'won');
  await page.waitForTimeout(200);
  ok('VICTORY! shows', (await page.textContent('#callout')).includes('VICTORY'));
  await page.screenshot({ path: S + '/pp-victory.png' });
  await page.waitForTimeout(2600);
  ok('...then the results', await page.isVisible('#over') && (await page.textContent('#over-title')).includes('win'));
  await page.click('#menu-btn');
  const hud = await page.evaluate(() => { startGame(); countdown = 0; updateHud(); return document.getElementById('kills').textContent; });
  ok('The HUD shows your place', /^#\d+ of \d+ · 0 knockouts$/.test(hud), hud);
  const noHype = await page.evaluate(() => { myMode = 'duo'; startGame(); countdown = 0; hype.queue = []; callout('TEST'); myMode = 'classic'; return hype.queue.length; });
  ok('No callouts in 2-player games', noHype === 0);

  ok('No page errors', errors.length === 0, errors.join(' | '));
  await browser.close();
})();
