const { chromium, ROOT, OUT } = require('../lib');
(async () => {
  const S = OUT;
  const browser = await chromium.launch();
  const errors = [];
  const ok = (name, cond, extra = '') => console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? '  ' + extra : ''));
  const page = await browser.newPage({ viewport: { width: 1100, height: 760 } });
  page.on('pageerror', e => errors.push(e.message));
  await page.goto('file://' + ROOT + '/color-claim/index.html');
  await page.evaluate(() => { localStorage.setItem('color-claim-howto-seen', '1'); settings.theme = 'classic'; });

  // ---------- Animated skins ----------
  const skins = await page.evaluate(() => {
    const render = (skin, t) => {
      const c = document.createElement('canvas'); c.width = c.height = 80;
      const g = c.getContext('2d'); g.translate(40, 36);
      drawBody(g, { color: '#4f8cff', dark: '#2f5fbf', skin, blink: 1, hueOff: 0 }, 50, t);
      return g.getImageData(0, 0, 80, 80).data;
    };
    const diff = (a, b) => { let n = 0; for (let i = 0; i < a.length; i += 4) if (Math.abs(a[i] - b[i]) + Math.abs(a[i + 1] - b[i + 1]) + Math.abs(a[i + 2] - b[i + 2]) > 30) n++; return n; };
    const out = {};
    for (const sk of SKINS) out[sk.id] = diff(render(sk.id, 0.1), render(sk.id, 0.9));
    return out;
  });
  const animated = ['stripes', 'dots', 'confetti', 'galaxy', 'lava', 'crystal', 'tiger', 'rainbow'];
  ok('Skin patterns move over time', animated.every(id => skins[id] > 20), JSON.stringify(skins));
  ok('Plain skins stay still', skins.classic < 5 && skins.shades < 5, JSON.stringify({ classic: skins.classic, shades: skins.shades }));
  await page.evaluate(() => { coins = 600; renderCoins(); lockerTab = 'skins'; showScreen('locker'); buildLocker(); });
  ok('Locker has 16 skins including Galaxy and Lava', await page.locator('#locker-items .item').count() === 16 && (await page.textContent('#locker-items')).includes('Galaxy'));
  const galaxy = page.locator('#locker-items .item', { hasText: 'Galaxy' });
  ok('Galaxy costs 250 coins', (await galaxy.locator('.item-btn').textContent()).includes('250'));
  await galaxy.locator('.item-btn').click();
  ok('Buying Galaxy equips it', await page.evaluate(() => mySkin === 'galaxy' && coins === 350 && ownedSkins.includes('galaxy')));
  await page.screenshot({ path: S + '/gx2-locker.png' });
  await page.evaluate(() => showScreen('menu'));
  await page.evaluate(() => { myMode = 'classic'; myMap = 'square'; startGame(); countdown = 0; cam.zoom = 1.8; for (const p of players) if (p && p.isBot) p.skin = ['lava', 'galaxy', 'stripes', 'crystal', 'tiger', 'confetti', 'dots'][p.id % 7]; });
  await page.waitForTimeout(700);
  await page.screenshot({ path: S + '/gx2-skins.png' });

  // ---------- Camera ----------
  const cam1 = await page.evaluate(() => {
    startGame(); countdown = 0; mouse.active = false; me.fx.shield = 99;
    me.angle = me.desired = 0;
    const run = fps => {
      for (const i of me.trail) trail[i] = 0; me.trail = []; me.alive = true;
      me.x = 20.5; me.y = 40.5; me.cx = 20; me.cy = 40; cam.x = me.x; cam.y = me.y; me.angle = me.desired = 0;
      for (let i = 0; i < fps; i++) { move(me, 1 / fps); updateCamera(1 / fps); }
      return { lead: +(cam.x - me.x).toFixed(2), camx: +cam.x.toFixed(2), mex: +me.x.toFixed(2) };
    };
    return { f30: run(30), f144: run(144) };
  });
  ok('Camera looks ahead of where you are going', cam1.f144.lead > 0.3 && cam1.f144.lead < 2.5, JSON.stringify(cam1));
  ok('Camera moves the same at 30 and 144 fps', Math.abs(cam1.f30.camx - cam1.f144.camx) < 0.35, JSON.stringify(cam1));
  const zoom = await page.evaluate(() => { const z0 = cam.zoom; me.fx.speed = 3; for (let i = 0; i < 120; i++) updateCamera(1 / 60); const z1 = cam.zoom; me.fx.speed = 0; return { z0: +z0.toFixed(3), z1: +z1.toFixed(3) }; });
  ok('Camera zooms out a little with Speed', zoom.z1 < zoom.z0, JSON.stringify(zoom));

  // ---------- Water ----------
  await page.evaluate(() => { myMap = 'islands'; startGame(); countdown = 0; cam.zoom = 0.8; me.fx.shield = 99; me.isBot = true; });
  await page.waitForTimeout(400);
  const w = await page.evaluate(() => {
    const g = canvas.getContext('2d'), dpr = canvas.width / W;
    // Find a patch of open sea on screen
    let sx = -1, sy = -1;
    for (let y = 40; y < H - 40 && sx < 0; y += 11) for (let x = 40; x < W - 40; x += 13) {
      const cx = Math.floor((x + cam.x * CELL - W / 2) / CELL), cy = Math.floor((y + cam.y * CELL - H / 2) / CELL);
      if (cx >= 0 && cy >= 0 && cx < N && cy < N && wall[cy * N + cx] === 2) { let ok = true; for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) if (wall[(cy + dy) * N + cx + dx] !== 2) ok = false; if (ok) { sx = x; sy = y; break; } }
    }
    const px = () => { const d = g.getImageData(Math.floor(sx * dpr), Math.floor(sy * dpr), 1, 1).data; return [d[0], d[1], d[2]]; };
    const mini = (() => { const i = wall.findIndex(v => v === 2); return [miniImg.data[i * 4], miniImg.data[i * 4 + 1], miniImg.data[i * 4 + 2], miniImg.data[i * 4 + 3]]; })();
    return { sx, sy, sample: px(), mini };
  });
  ok('Islands sit in a blue sea', w.sx > 0 && w.sample[2] > w.sample[0] + 40, JSON.stringify(w));
  ok('The minimap shows the sea', w.mini[2] > 200 && w.mini[3] === 255, JSON.stringify(w.mini));
  const moving = await page.evaluate(async () => {
    const g = canvas.getContext('2d'), dpr = canvas.width / W;
    const grab = () => g.getImageData(0, 0, canvas.width, canvas.height).data;
    const x0 = cam.x * CELL - W / 2, y0 = cam.y * CELL - H / 2;
    // Compare only pixels over deep water, away from players
    const pts = [];
    for (let y = 20; y < H - 150; y += 3) for (let x = 170; x < W - 20; x += 3) {
      const cx = Math.floor((x + x0) / CELL), cy = Math.floor((y + y0) / CELL);
      if (cx < 2 || cy < 2 || cx >= N - 2 || cy >= N - 2) continue;
      let deep = true; for (let dy = -2; dy <= 2; dy++) for (let dx = -2; dx <= 2; dx++) if (wall[(cy + dy) * N + cx + dx] !== 2) deep = false;
      if (deep && players.every(p => !p || Math.hypot(p.x - cx, p.y - cy) > 6)) pts.push(Math.floor(y * dpr) * canvas.width + Math.floor(x * dpr));
    }
    state = 'paused'; time = 1; draw(0); const a = grab(); time = 2.3; draw(0); const b = grab(); state = 'play';
    let changed = 0; for (const i of pts) if (Math.abs(a[i * 4] - b[i * 4]) + Math.abs(a[i * 4 + 2] - b[i * 4 + 2]) > 20) changed++;
    return { pts: pts.length, changed };
  });
  ok('The waves move', moving.pts > 50 && moving.changed > moving.pts * 0.01, JSON.stringify(moving));
  await page.waitForTimeout(1500);
  await page.screenshot({ path: S + '/gx2-islands.png' });
  for (const t of ['space', 'desert']) {
    await page.evaluate(t => { settings.theme = t; }, t);
    await page.waitForTimeout(300);
    await page.screenshot({ path: `${S}/gx2-islands-${t}.png` });
  }
  await page.evaluate(() => { settings.gfx = 'low'; });
  await page.waitForTimeout(400);
  await page.evaluate(() => { settings.gfx = 'high'; settings.theme = 'season'; state = 'menu'; me = null; gameCounter++; showScreen('menu'); });

  ok('No page errors', errors.length === 0, errors.join(' | '));
  await browser.close();
})();
