// Auto graphics: the resolution steps down when frames are slow and back up when smooth
const { chromium, ROOT } = require('../lib');
(async () => {
  const browser = await chromium.launch();
  const errors = [];
  const ok = (name, cond, extra = '') => console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? '  ' + extra : ''));
  const ctx = await browser.newContext({ viewport: { width: 412, height: 915 }, deviceScaleFactor: 3, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', e => errors.push(e.message));
  await page.goto('file://' + ROOT + '/color-claim/index.html');
  await page.evaluate(() => { localStorage.setItem('color-claim-howto-seen', '1'); });

  const start = await page.evaluate(() => ({ gfx: settings.gfx, quality, scale: renderScale(), w: canvas.width }));
  ok('Graphics start on Auto, one step down on a phone', start.gfx === 'auto' && start.quality === 1 && start.scale === 1.5 && start.w === Math.round(412 * 1.5), JSON.stringify(start));

  const down = await page.evaluate(() => {
    myMode = 'classic'; myMap = 'square'; startGame(); countdown = 0;
    const seen = [];
    for (let i = 0; i < 200; i++) { watchFrameRate(28); if (seen[seen.length - 1] !== quality) seen.push(quality); } // ~36 fps
    return { seen, scale: renderScale(), saved: localStorage.getItem('color-claim-quality'), w: canvas.width };
  });
  ok('Slow frames step the resolution down, and it is remembered', down.seen[0] === 1 && down.seen.length >= 2 && down.scale < 1.5 && down.saved === String(down.seen[down.seen.length - 1]) && down.w === Math.round(412 * down.scale), JSON.stringify(down));

  const bottom = await page.evaluate(() => { for (let i = 0; i < 2000; i++) watchFrameRate(45); return { quality, scale: renderScale(), fx: hiGfx() }; });
  ok('Very slow frames go all the way to 1x with the extra effects off', bottom.quality === 4 && bottom.scale === 1 && !bottom.fx, JSON.stringify(bottom));

  const up = await page.evaluate(() => {
    perf.tooSlow = 2; // levels 0-2 were too slow this session
    for (let i = 0; i < 6000; i++) watchFrameRate(16.7); // 100 s at 60 fps
    return { quality, fx: hiGfx() };
  });
  ok('Smooth play steps back up, but never to a level that was too slow', up.quality === 3 && up.fx, JSON.stringify(up));

  const idle = await page.evaluate(() => { const q = quality; state = 'paused'; for (let i = 0; i < 500; i++) watchFrameRate(60); state = 'play'; return q === quality; });
  ok('Slow frames while paused or on menus change nothing', idle);

  const modes = await page.evaluate(() => {
    const out = {};
    for (const g of ['high', 'low']) { settings.gfx = gfxMode = g; resize(); for (let i = 0; i < 500; i++) watchFrameRate(60); out[g] = { scale: renderScale(), fx: hiGfx(), w: canvas.width }; }
    settings.gfx = gfxMode = 'auto'; resize();
    return out;
  });
  ok('Sharpest draws at 2x with effects, Fastest at 1x without, and neither changes by itself', modes.high.scale === 2 && modes.high.fx && modes.high.w === 824 && modes.low.scale === 1 && !modes.low.fx, JSON.stringify(modes));

  // An old save with Graphics: High becomes Auto once
  const page2 = await ctx.newPage();
  await page2.goto('file://' + ROOT + '/color-claim/index.html');
  await page2.evaluate(() => { localStorage.removeItem('color-claim-gfx-auto'); localStorage.setItem('color-claim-settings', JSON.stringify({ gfx: 'high' })); });
  await page2.reload();
  const migrated = await page2.evaluate(() => settings.gfx);
  ok('Old High setting becomes Auto', migrated === 'auto', migrated);
  await page2.evaluate(() => { settings.gfx = 'high'; saveSettings(); });
  await page2.reload();
  ok('Choosing Sharpest afterwards sticks', await page2.evaluate(() => settings.gfx === 'high'));

  await page.evaluate(() => { state = 'menu'; me = null; gameCounter++; showScreen('menu'); openScreen('settings'); });
  const row = await page.evaluate(() => [...document.querySelectorAll('#settings-list li')].find(li => li.textContent.startsWith('Graphics')).textContent);
  ok('Settings shows Auto, Sharpest and Fastest', /Auto.*Sharpest.*Fastest/.test(row), row);
  ok('No page errors', errors.length === 0, errors.join(' | '));
  await browser.close();
})();
