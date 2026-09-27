const { chromium, ROOT, OUT } = require('../lib');
const fs = require('fs');
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

  // ---------- Themes ----------
  const th = await page.evaluate(() => ({ season: seasonTheme(), id: themeId(), month: new Date().getMonth(), all: Object.keys(THEMES) }));
  ok('The season picks the map look', th.id === th.season && th.season === ['snow', 'snow', 'garden', 'garden', 'garden', 'desert', 'desert', 'desert', 'space', 'space', 'space', 'snow'][th.month], JSON.stringify(th));
  for (const t of ['snow', 'garden', 'desert', 'space', 'classic']) {
    await page.evaluate(t => { settings.gfx = 'low'; settings.theme = t; myMode = 'classic'; myMap = 'pillars'; startGame(); countdown = 0; cam.zoom = 0.7; time = 5; }, t);
    await page.waitForTimeout(500);
    await page.screenshot({ path: `${S}/pn-theme-${t}.png` });
    const pxs = await page.evaluate(() => [0.2, 0.35, 0.5, 0.65, 0.8].map(f => { const d = canvas.getContext('2d').getImageData(3, Math.floor(canvas.height * f), 1, 1).data; return [d[0], d[1], d[2]]; }));
    const want = await page.evaluate(t => [THEMES[t].floor, THEMES[t].check].map(h => [1, 3, 5].map(i => parseInt(h.slice(i, i + 2), 16))), t);
    ok(`${t} look paints its own floor`, pxs.some(px => want.some(w => px.every((v, i) => Math.abs(v - w[i]) <= 2))), `${JSON.stringify(pxs)} vs ${JSON.stringify(want)}`);
  }
  await menuOff();
  await page.evaluate(() => { settings.theme = 'season'; settings.gfx = 'high'; saveSettings(); });
  await page.click('.nav-btn[data-open="settings"]');
  ok('Settings has a Map look row', (await page.textContent('#settings-list')).includes('Map look') && (await page.textContent('#settings-list')).includes('Season ('));
  await page.click('#settings [data-back]');
  await page.click('.nav-btn[data-open="season"]');
  ok('Season pass names the season look', (await page.textContent('#season-head')).includes(' maps'));
  await page.click('#season [data-back]');

  // ---------- Upgrades ----------
  await page.evaluate(() => { coins = 1000; renderCoins(); upgrades = {}; save('color-claim-upgrades', '{}'); });
  await page.evaluate(() => openScreen('upgrades'));
  ok('Upgrades screen lists the 5 power-ups', await page.locator('#upgrade-list li').count() === 5 && (await page.textContent('#upgrade-list')).includes('Lasts 4.0 s'));
  await page.screenshot({ path: S + '/pn-upgrades.png' });
  await page.click('#upgrade-list .item-btn[data-kind="speed"]');
  await page.click('#upgrade-list .item-btn[data-kind="speed"]');
  const up = await page.evaluate(() => ({ lvl: upLevel('speed'), coins, saved: JSON.parse(localStorage.getItem('color-claim-upgrades')).speed, text: document.querySelector('#upgrade-list li').textContent }));
  ok('Buying upgrades costs 100 then 200 and is saved', up.lvl === 2 && up.coins === 700 && up.saved === 2 && up.text.includes('Lasts 5.6 s'), JSON.stringify(up));
  await page.click('#upgrade-list .item-btn[data-kind="speed"]');
  const maxed = await page.evaluate(() => ({ lvl: upLevel('speed'), btn: document.querySelector('.item-btn[data-kind="speed"]').textContent, trophy: !!achieved.maxed }));
  ok('Level 3 is the max and earns Maxed Out', maxed.lvl === 3 && maxed.btn === 'Maxed' && maxed.trophy, JSON.stringify(maxed));
  await page.click('#upgrades [data-back]');
  const eff = await page.evaluate(() => {
    upgrades.paint = 2;
    myMode = 'classic'; myMap = 'square'; startGame(); countdown = 0;
    grabPowerup(me, { x: me.x, y: me.y, kind: 'speed' });
    const bot = players.find(p => p && p.isBot);
    grabPowerup(bot, { x: bot.x, y: bot.y, kind: 'speed' });
    const mine = me.fx.speed, theirs = bot.fx.speed;
    const c0 = counts[me.id]; paintBomb(me); const painted = counts[me.id] - c0;
    upgrades.paint = 0; const c1 = counts[bot.id]; paintBomb(bot); const botPainted = counts[bot.id] - c1;
    myMode = 'duo'; startGame(); grabPowerup(me, { x: me.x, y: me.y, kind: 'speed' }); const duo = me.fx.speed;
    myMode = 'classic';
    return { mine, theirs, painted, botPainted, duo };
  });
  ok('Your upgraded Speed lasts longer (bots get the normal time)', Math.abs(eff.mine - 6.4) < 0.01 && eff.theirs === 4, JSON.stringify(eff));
  ok('Upgraded Paint Bomb paints more', eff.painted > eff.botPainted + 10, JSON.stringify(eff));
  ok('Upgrades are off in 2-player games', eff.duo === 4);
  await menuOff();

  // ---------- Daily puzzle ----------
  await page.click('#modes .seg-btn:has-text("Puzzle")');
  const pz = await page.evaluate(() => ({ desc: document.getElementById('mode-desc').textContent, p: dailyPuzzle(), same: JSON.stringify(dailyPuzzle()) === JSON.stringify(dailyPuzzle()), maps: [...document.querySelectorAll('#maps .seg-btn')].every(b => b.disabled), inPicker: document.getElementById('maps').textContent.includes('Puzzle box') }));
  ok("Puzzle mode shows today's puzzle", pz.desc.includes('Today: ' + pz.p.text) && pz.same && pz.maps && !pz.inPicker, pz.desc);
  const kinds = await page.evaluate(() => { const k = new Set(); for (let d = 1; d <= 28; d++) k.add(dailyPuzzle(`2026-02-${String(d).padStart(2, '0')}`).kind); return [...k].sort(); });
  ok('Puzzles vary day to day (claim, knockout, single loop)', kinds.join() === 'claim,ko,loop', kinds.join());
  await page.click('#play-btn');
  await page.waitForTimeout(200);
  const g = await page.evaluate(() => ({ n: N, bots: players.filter(p => p && p.isBot).length, time: gameMode.time, walls: wall.reduce((a, v) => a + (v ? 1 : 0), 0), ranked: isRanked(), map: gameMapId, pu: MODES.puzzle.powerups }));
  ok('Puzzle is a small box with a few bots and a timer', g.n === 40 && g.bots === (pz.p.kind === 'ko' ? 4 : 2) && g.time === pz.p.time && g.walls > 0 && !g.ranked && g.map === 'puzzle', JSON.stringify(g));
  await page.evaluate(() => { countdown = 0; updateHud(); });
  ok('HUD shows the puzzle goal and the clock', (await page.textContent('#team-score')).includes(pz.p.text) && await page.isVisible('#timer'));
  await page.screenshot({ path: S + '/pn-puzzle.png' });
  const solve = await page.evaluate(() => {
    const c0 = coins;
    // Solve it straight away: 3 stars
    if (puzzle.kind === 'claim') { let need = Math.ceil(playCells * (puzzle.goal + 0.5) / 100) - counts[me.id]; for (let i = 0; i < N * N && need > 0; i++) if (!wall[i] && !owner[i]) { setOwner(i, me.id); need--; } }
    else if (puzzle.kind === 'ko') me.kills = puzzle.goal;
    else run.bigLoop = puzzle.goal + 1;
    playTime = 5;
    update(1 / 60);
    return { state, stars: puzzleStars, c0 };
  });
  ok('Reaching the goal solves the puzzle with stars', solve.state === 'won' && solve.stars === 3, JSON.stringify(solve));
  await page.waitForTimeout(1700);
  const res = await page.evaluate(c0 => ({ title: document.getElementById('over-title').textContent, best: document.getElementById('over-best').textContent, paid: coins - c0, saved: localStorage.getItem('color-claim-puzzle-' + todayKey()), trophy: !!achieved.puzzlepro, share: document.getElementById('challenge-share').classList.contains('hidden') }), solve.c0);
  ok('Game over shows the stars and pays 90 coins the first time', res.title.includes('Puzzle solved') && res.best.includes('★★★') && res.best.includes('+90 coins') && res.saved === '3', JSON.stringify(res));
  ok('Puzzle Pro trophy, and no challenge code for puzzles', res.trophy && res.share);
  await page.click('#again-btn');
  const again = await page.evaluate(() => { const c0 = coins; countdown = 0; playTime = puzzle.time - 1; if (puzzle.kind === 'ko') me.kills = puzzle.goal; else if (puzzle.kind === 'loop') run.bigLoop = 99; else { let need = Math.ceil(playCells * (puzzle.goal + 0.5) / 100) - counts[me.id]; for (let i = 0; i < N * N && need > 0; i++) if (!wall[i] && !owner[i]) { setOwner(i, me.id); need--; } } update(1 / 60); return { c0, stars: puzzleStars }; });
  await page.waitForTimeout(1700);
  const res2 = await page.evaluate(c0 => ({ paid: coins - c0, best: document.getElementById('over-best').textContent }), again.c0);
  ok('A slower solve gets fewer stars and no extra coins', again.stars === 1 && res2.best.includes('★☆☆') && res2.best.includes('Best today: ★★★') && !res2.best.includes('coins'), JSON.stringify({ again, res2 }));
  await page.click('#again-btn');
  await page.evaluate(() => { countdown = 0; playTime = puzzle.time + 0.1; update(1 / 60); });
  await page.waitForTimeout(900);
  ok("Running out of time fails the puzzle", (await page.textContent('#over-reason')).includes("Time's up"));
  await page.click('#menu-btn');
  await page.evaluate(() => { myMode = 'classic'; save('color-claim-mode', 'classic'); buildPickers(); });
  ok('Daily and Weekly maps never pick the puzzle box', await page.evaluate(() => { for (let d = 1; d <= 28; d++) { if (PLAY_MAPS()[hashStr(`2026-03-${d}`) % PLAY_MAPS().length] === 'puzzle') return false; } return !PLAY_MAPS().includes('puzzle'); }));

  // ---------- Photo mode ----------
  await page.evaluate(() => { myMode = 'classic'; myMap = 'square'; startGame(); countdown = 0; me.pet = 'dragon'; });
  await page.waitForTimeout(1500);
  await page.keyboard.press('p');
  await page.click('#photo-btn');
  const p0 = await page.evaluate(() => ({ state, hud: document.getElementById('hud').classList.contains('hidden'), bar: !document.getElementById('photo-bar').classList.contains('hidden'), t: time }));
  ok('Photo mode opens from the pause screen and hides the HUD', p0.state === 'photo' && p0.hud && p0.bar, JSON.stringify(p0));
  await page.waitForTimeout(400);
  ok('The game stays frozen in photo mode', await page.evaluate(t => time === t, p0.t));
  await page.click('#photo-filters .seg-btn:has-text("Retro")');
  ok('Filters preview on the screen', await page.evaluate(() => canvas.style.filter.includes('sepia')));
  await page.click('#photo-stickers [data-sticker="love"]');
  await page.mouse.click(700, 300);
  await page.mouse.click(420, 420);
  ok('Tapping adds stickers', await page.evaluate(() => photo.stickers.length === 2 && photo.stickers[0].id === 'love'));
  await page.evaluate(() => { const z = document.getElementById('photo-zoom'); z.value = 1.4; z.dispatchEvent(new Event('input')); });
  ok('Zoom slider zooms the camera', await page.evaluate(() => Math.abs(cam.zoom - 1.4) < 0.01));
  await page.waitForTimeout(300);
  await page.screenshot({ path: S + '/pn-photo.png' });
  await page.click('#photo-snap');
  await page.waitForSelector('#photo-result:not(.hidden)');
  const shot = await page.evaluate(async () => {
    const buf = new Uint8Array(await photo.blob.arrayBuffer());
    let bin = ''; for (let i = 0; i < buf.length; i += 8192) bin += String.fromCharCode(...buf.subarray(i, i + 8192));
    const img = document.getElementById('photo-img');
    await img.decode();
    return { b64: btoa(bin), w: img.naturalWidth, h: img.naturalHeight, cw: canvas.width, ch: canvas.height, type: photo.blob.type };
  });
  fs.writeFileSync(S + '/pn-photo-out.png', Buffer.from(shot.b64, 'base64'));
  ok('Taking a photo makes a framed PNG', shot.type === 'image/png' && shot.w === shot.cw + 72 && shot.h === shot.ch + 36 + 70, JSON.stringify({ w: shot.w, h: shot.h, cw: shot.cw, ch: shot.ch }));
  const sepia = require('child_process').execSync(`python3 -c "
from PIL import Image
im=Image.open('${S}/pn-photo-out.png').convert('RGB'); w,h=im.size
px=[im.getpixel((x,y)) for x in range(60,w-60,97) for y in range(60,h-120,89)]
warm=sum(1 for r,g,b in px if r>=g>=b); print(warm, len(px))"`).toString().trim().split(' ').map(Number);
  ok('The Retro filter is baked into the photo', sepia[0] / sepia[1] > 0.9, `${sepia[0]} of ${sepia[1]} pixels are sepia-toned`);
  await page.click('#photo-close');
  await page.click('#photo-done');
  ok('Done goes back to the pause screen with no filter left on', await page.evaluate(() => state === 'paused' && canvas.style.filter === '' && document.getElementById('paused').classList.contains('show')));
  await page.click('#resume-btn');
  ok('Resuming carries on the game', await page.evaluate(() => state === 'play'));
  await menuOff();

  // Mobile
  await page.setViewportSize({ width: 390, height: 780 });
  await page.evaluate(() => { resize(); startGame(); countdown = 0; state = 'paused'; openPhoto(); });
  await page.waitForTimeout(300);
  await page.screenshot({ path: S + '/pn-photo-mobile.png' });
  const bar = await page.locator('#photo-bar').boundingBox();
  ok('Photo toolbar fits on a phone', bar && bar.x >= 0 && bar.x + bar.width <= 390 && bar.y > 200, JSON.stringify(bar));
  await page.evaluate(() => closePhoto());

  ok('No page errors', errors.length === 0, errors.join(' | '));
  await browser.close();
})();
