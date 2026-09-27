const { chromium, ROOT, OUT } = require('../lib');
(async () => {
  const S = OUT;
  const browser = await chromium.launch();
  const errors = [];
  const ok = (name, cond, extra = '') => console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? '  ' + extra : ''));
  const ctx = await browser.newContext({ viewport: { width: 400, height: 780 }, isMobile: true, hasTouch: true });
  const page = await ctx.newPage();
  page.on('pageerror', e => errors.push(e.message));
  page.on('console', m => { if (m.type() === 'error') errors.push(m.text()); });
  await page.addInitScript(() => { window.__buzz = []; navigator.vibrate = p => { window.__buzz.push(p); return true; }; });
  await page.goto('http://127.0.0.1:8765/color-claim/');
  await page.evaluate(() => localStorage.setItem('color-claim-howto-seen', '1'));

  // PWA basics
  const manifest = await page.evaluate(async () => (await fetch('manifest.webmanifest')).json());
  ok('Manifest loads with icons', manifest.name === 'Color Claim' && manifest.icons.length === 2);
  const swReady = await page.evaluate(() => Promise.race([navigator.serviceWorker.ready.then(() => true), new Promise(r => setTimeout(() => r(false), 8000))]));
  ok('Service worker installs', swReady);
  await page.reload();
  await page.waitForTimeout(500);
  const cached = await page.evaluate(async () => (await (await caches.open((await caches.keys()).find(k => k.startsWith('color-claim-')))).keys()).map(r => r.url.split('/').slice(-2).join('/')));
  ok('Game files are cached for offline play', ['color-claim/game.js', 'shared/music.js', 'color-claim/icon-512.png'].every(f => cached.includes(f)), cached.length + ' files');
  await ctx.setOffline(true);
  await page.reload();
  ok('Game still loads with no internet', await page.evaluate(() => typeof startGame === 'function' && document.querySelector('#menu').classList.contains('show')));
  await ctx.setOffline(false);

  // Settings screen
  await page.tap('[data-open="settings"]');
  ok('Settings screen opens', await page.isVisible('#settings') && (await page.$$('#settings-list li')).length === 14);
  await page.screenshot({ path: S + '/pd-settings.png' });
  await page.tap('#settings-list li >> nth=6 >> .seg-btn >> nth=1'); // Tap to turn
  await page.tap('#settings-list li >> nth=5 >> .seg-btn >> nth=1'); // Screen shake off
  ok('Settings are saved', await page.evaluate(() => { const s = JSON.parse(localStorage.getItem('color-claim-settings')); return s.controls === 'turn' && s.shake === false; }));
  await page.tap('#settings [data-back]');

  // Tap to turn
  await page.tap('#play-btn');
  await page.evaluate(() => { countdown = 0; for (const p of players) if (p && p !== me) { p.alive = false; p.respawn = 999; } });
  const a0 = await page.evaluate(() => me.angle);
  await page.evaluate(() => {
    const ev = (type, x) => canvas.dispatchEvent(new PointerEvent(type, { pointerId: 7, pointerType: 'touch', clientX: x, clientY: 500, bubbles: true }));
    ev('pointerdown', 350); // right half
  });
  await page.waitForTimeout(400);
  const a1 = await page.evaluate(() => me.angle);
  await page.screenshot({ path: S + '/pd-turn.png' });
  await page.evaluate(() => canvas.dispatchEvent(new PointerEvent('pointerup', { pointerId: 7, pointerType: 'touch', bubbles: true })));
  ok('Holding the right side turns right', a1 - a0 > 0.8, `turned ${(a1 - a0).toFixed(2)} rad`);
  const a2 = await page.evaluate(() => me.angle);
  await page.waitForTimeout(300);
  ok('Letting go goes straight again', Math.abs((await page.evaluate(() => me.angle)) - a2) < 0.05);

  // Vibration
  await page.evaluate(() => { grabPowerup(me, { kind: 'speed', x: me.x, y: me.y }); me.fx.shield = 0; kill(me, me); });
  ok('Phone vibrates on events', await page.evaluate(() => window.__buzz.includes(15) && window.__buzz.includes(300)), JSON.stringify(await page.evaluate(() => window.__buzz)));
  await page.waitForTimeout(1200);
  await page.evaluate(() => { settings.vibrate = false; window.__buzz = []; buzz(50); });
  ok('Vibration can be turned off', await page.evaluate(() => window.__buzz.length === 0));

  // Bigger touch buttons
  await page.tap('#again-btn');
  await page.waitForTimeout(200);
  const btn = await page.$eval('#pause-btn', b => b.getBoundingClientRect().width);
  ok('Buttons are bigger on touch screens', btn >= 44, btn + 'px');
  console.log('errors', errors);
  await browser.close();
})();
