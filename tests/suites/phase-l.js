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
  await page.evaluate(() => { localStorage.setItem('color-claim-howto-seen', '1'); localStorage.setItem('color-claim-tutorial-done', '1'); });
  const menuOff = () => page.evaluate(() => { state = 'menu'; me = null; gameCounter++; showScreen('menu'); });

  // ---------- Boss Battle ----------
  await page.click('#modes .seg-btn:has-text("Boss Battle")');
  ok('Boss Battle is on the mode picker', (await page.textContent('#mode-desc')).includes('King'));
  await page.click('#play-btn');
  await page.waitForTimeout(300);
  const b0 = await page.evaluate(() => ({ n: players.filter(Boolean).length, hp: king.hp, max: king.maxHp, track: Music.track, ranked: isRanked(), land: counts[king.id] }));
  ok('Just you and the King, with 5 hearts', b0.n === 2 && b0.hp === 5 && b0.max === 5 && b0.land > 50, JSON.stringify(b0));
  ok('Boss music plays and the mode is not ranked', b0.track === 'boss' && !b0.ranked);
  await page.evaluate(() => { countdown = 0; updateHud(); });
  ok('Boss bar shows the King\'s hearts', await page.isVisible('#boss-bar') && await page.locator('#boss-bar svg.on').count() === 5);
  const hit = await page.evaluate(() => {
    king.fx.shield = 0;
    const i = king.cy * N + king.cx + 1; trail[i] = king.id; king.trail.push(i);
    kill(king, me);
    const after = { hp: king.hp, alive: king.alive, trail: king.trail.length, shield: king.fx.shield > 0, feed: feed.map(f => f.text).join('|') };
    kill(king, me);
    after.hp2 = king.hp;
    return after;
  });
  ok('Cutting the King takes a heart', hit.hp === 4 && hit.alive && hit.trail === 0 && hit.feed.includes('You hit the King'), JSON.stringify(hit));
  ok('He is safe for a moment after a hit', hit.shield && hit.hp2 === 4);
  const sw = await page.evaluate(() => {
    king.fx.shield = 0;
    for (let i = 0; i < N * N; i++) if (owner[i] === king.id) setOwner(i, me.id);
    kill(king, me, 'swallow');
    return { hp: king.hp, alive: king.alive, land: counts[king.id] };
  });
  ok('Swallowing him costs a heart and he escapes to a new home', sw.hp === 3 && sw.alive && sw.land > 50, JSON.stringify(sw));
  await page.waitForTimeout(900);
  const guards = await page.evaluate(() => players.filter(p => p && (p.name === 'Guard' || p.name === 'Knight')).map(p => p.persona));
  ok('At half health he calls two guards', guards.length === 2 && guards.every(p => p === 'hunter'), guards.join(','));
  await page.evaluate(() => { cam.zoom = 0.8; king.fx.shield = 0; });
  await page.waitForTimeout(700);
  await page.screenshot({ path: S + '/pl-boss.png' });
  const rage = await page.evaluate(() => {
    const v0 = speedOf(king);
    king.fx.shield = 0; kill(king, me); king.fx.shield = 0; kill(king, me);
    return { hp: king.hp, rage: !!king.rage, faster: speedOf(king) > v0 };
  });
  ok('On his last heart he gets faster', rage.hp === 1 && rage.rage && rage.faster, JSON.stringify(rage));
  const wins0 = await page.evaluate(() => stats.bossWins || 0);
  await page.evaluate(() => { king.fx.shield = 0; me.fx.shield = 99; kill(king, me); });
  ok('The last hit knocks him out', await page.evaluate(() => !king.alive));
  await page.waitForTimeout(2900);
  const won = await page.evaluate(() => ({ title: document.getElementById('over-title').textContent, reason: document.getElementById('over-reason').textContent, share: document.getElementById('challenge-share').classList.contains('hidden'), trophy: !!achieved.kingslayer, wins: stats.bossWins }));
  ok('Beating the King wins the game', won.title.includes('win') && won.reason === 'You defeated the King!', JSON.stringify(won));
  ok('Boss bar hides on the game over screen', !(await page.isVisible('#boss-bar')));
  ok('Kingslayer trophy and boss win counted', won.trophy && won.wins === wins0 + 1 && won.share);
  await page.click('#again-btn');
  await page.evaluate(() => { countdown = 0; });
  await page.evaluate(() => { me.fx.shield = 0; kill(me, king); });
  await page.waitForTimeout(1500);
  const l1 = await page.evaluate(() => ({ lives, alive: me.alive, state, over: document.getElementById('over').classList.contains('show') }));
  ok('You have 3 lives in a Boss Battle', l1.lives === 2 && l1.alive && l1.state === 'play' && !l1.over, JSON.stringify(l1));
  await page.evaluate(() => { me.fx.shield = 0; kill(me, king); });
  await page.waitForTimeout(1500);
  await page.evaluate(() => { me.fx.shield = 0; kill(me, king); });
  await page.waitForTimeout(1300);
  ok('Losing all 3 lives ends the game', await page.isVisible('#over') && await page.evaluate(() => lives === 1));
  const hearts = await page.evaluate(() => { const o = {}; for (const d of ['easy', 'hard']) { myDiff = d; startGame(); o[d] = king.hp; } myDiff = 'normal'; return o; });
  ok('Easy King has 3 hearts, Hard has 7', hearts.easy === 3 && hearts.hard === 7, JSON.stringify(hearts));
  await menuOff();
  await page.evaluate(() => { myMode = 'classic'; save('color-claim-mode', 'classic'); buildPickers(); });

  // ---------- Trophies page 2 ----------
  const tp = await page.evaluate(() => {
    startGame(); countdown = 0;
    // Eye of the Storm, Ghostbuster
    myMap = 'storm'; startGame(); countdown = 0; peakPct = 5;
    const a = finishRun(true, 5).fresh.map(t => t.id);
    myMode = 'weekly'; startGame(); countdown = 0; ghostRun = { score: 1, path: [0, 0], pcts: [0] }; peakPct = 3;
    run.beatGhost = 3 > ghostRun.score;
    const b = finishRun(false, 3).fresh.map(t => t.id);
    myMode = 'classic'; myMap = 'square';
    return { a, b, total: ACHIEVEMENTS.length, p2: ACHIEVEMENTS.filter(x => x.page === 2).length };
  });
  ok('New trophies can be earned', tp.a.includes('eye') && tp.b.includes('ghostbuster'), JSON.stringify(tp));
  await menuOff();
  await page.evaluate(() => { stats.teleports = 4; trophyPage = 1; });
  await page.evaluate(() => openScreen('trophies'));
  const pg1 = await page.locator('#trophy-list li').count();
  ok('Trophies come in 2 pages', await page.locator('#trophy-pages button').count() === 2 && pg1 === 19 && (await page.textContent('#trophy-count')).includes(`/ ${tp.total}`), `page 1: ${pg1}, total ${tp.total}`);
  await page.click('#trophy-pages button >> nth=1');
  const pg2 = await page.textContent('#trophy-list');
  ok('Page 2 lists the new trophies with progress', await page.locator('#trophy-list li').count() === tp.p2 && pg2.includes('Kingslayer') && pg2.includes('4 / 10'), 'page 2: ' + tp.p2);
  await page.screenshot({ path: S + '/pl-trophies.png' });
  await page.click('#trophies [data-back]');

  // ---------- Map codes ----------
  const codes = await page.evaluate(() => {
    const out = {};
    const empty = new Uint8Array(CUSTOM_SIZE * CUSTOM_SIZE);
    out.emptyLen = mapToCode(empty).length;
    const same = cells => { const back = codeToMap(mapToCode(cells)); return !!back && back.every((v, i) => v === cells[i]); };
    // A typical drawn map: mirrored blocks and lines
    const m = new Uint8Array(CUSTOM_SIZE * CUSTOM_SIZE);
    for (let y = 10; y < 70; y += 12) for (let x = 5; x < 75; x++) if (!edProtected(x, y) && (x % 20) < 14) m[y * CUSTOM_SIZE + x] = 1;
    for (let y = 20; y < 30; y++) for (let x = 20; x < 28; x++) m[y * CUSTOM_SIZE + x] = m[y * CUSTOM_SIZE + 79 - x] = 1;
    out.typical = same(m);
    out.typicalLen = mapToCode(m).length;
    // Random noise (worst case)
    const r = new Uint8Array(CUSTOM_SIZE * CUSTOM_SIZE);
    for (let i = 0; i < r.length; i++) { const x = i % CUSTOM_SIZE, y = Math.floor(i / CUSTOM_SIZE); r[i] = !edProtected(x, y) && Math.random() < 0.5 ? 1 : 0; }
    out.noise = same(r);
    const code = mapToCode(m);
    out.typo = codeToMap(code.slice(0, 10) + (code[10] === 'A' ? 'B' : 'A') + code.slice(11));
    out.junk = codeToMap('hello');
    // Walls painted into the start area are cleared
    const bad = new Uint8Array(CUSTOM_SIZE * CUSTOM_SIZE).fill(1);
    const cleaned = codeToMap(mapToCode(bad));
    out.clearStart = cleaned[40 * CUSTOM_SIZE + 40] === 0 && cleaned[0] === 1;
    return out;
  });
  ok('Map codes round-trip exactly', codes.typical && codes.noise, JSON.stringify(codes));
  ok('Map codes are short for normal maps', codes.emptyLen < 20 && codes.typicalLen < 300, `empty ${codes.emptyLen}, typical ${codes.typicalLen}`);
  ok('Bad map codes are rejected', codes.typo === null && codes.junk === null);
  ok('A shared map never blocks the start area', codes.clearStart);
  await page.evaluate(() => openScreen('editor'));
  await page.evaluate(() => { editorLoadSlot(0); for (let x = 10; x < 70; x++) editor.cells[20 * CUSTOM_SIZE + x] = 1; drawEditor(); });
  await page.click('#editor-share');
  const code = await page.inputValue('#map-code-text');
  ok('Editor gives a code for the map', /^MAP-[A-Za-z0-9_-]+-[0-9A-Z]$/.test(code) && await page.isVisible('#map-code'), code);
  await page.click('#map-code-copy');
  await page.waitForTimeout(200);
  ok('Copy puts the code on the clipboard', (await page.evaluate(() => navigator.clipboard.readText())) === code);
  await page.evaluate(() => editorLoadSlot(1));
  await page.fill('#map-import-text', 'MAP-nope-Z');
  await page.click('#map-import');
  ok('A wrong code shows a message', (await page.textContent('#map-import-info')).includes("doesn't look right"));
  await page.fill('#map-import-text', code);
  await page.click('#map-import');
  const loaded = await page.evaluate(() => editor.cells[20 * CUSTOM_SIZE + 10] === 1 && editor.cells[20 * CUSTOM_SIZE + 9] === 0);
  ok('Loading a code puts the map in the editor', loaded && (await page.textContent('#map-import-info')).includes('slot 2'));
  await page.screenshot({ path: S + '/pl-editor.png' });
  await page.click('#editor-save');
  ok('The loaded map can be saved and played', await page.evaluate(() => { const m = loadCustomMaps()[1]; myMode = 'classic'; startGame(); const w = wall[20 * N + 30]; state = 'menu'; me = null; gameCounter++; showScreen('menu'); return !!m && myMap === 'custom1' && w === 1; }));
  await page.evaluate(() => { myMap = 'square'; save('color-claim-map', 'square'); buildPickers(); });

  // ---------- Music and sounds ----------
  await page.click('.nav-btn[data-open="settings"]');
  ok('Settings has a Music style row', (await page.textContent('#settings-list')).includes('Music style'));
  await page.click('#settings-list li >> nth=8 >> .seg-btn >> nth=1');
  const tr = await page.evaluate(() => { const o = { setting: settings.track, saved: JSON.parse(localStorage.getItem('color-claim-settings')).track }; startGame(); o.game = Music.track; myMode = 'boss'; startGame(); o.boss = Music.track; myMode = 'classic'; state = 'menu'; me = null; gameCounter++; showScreen('menu'); return o; });
  ok('Night track is picked and saved; bosses get their own', tr.setting === 'night' && tr.saved === 'night' && tr.game === 'night' && tr.boss === 'boss', JSON.stringify(tr));
  const audio = await page.evaluate(async () => {
    const played = [];
    if (Sfx.muted) Sfx.toggle();
    for (const t of Music.tracks) { Music.track = t; Music.start(); await new Promise(r => setTimeout(r, 250)); played.push(t + ':' + Music.playing); Music.stop(); }
    for (const snd of ['portal', 'saw', 'belt', 'rumble', 'roar', 'bosshit', 'bossdown']) Sfx.play(snd);
    return played;
  });
  ok('All 3 music tracks play', audio.length === 3 && audio.every(a => a.endsWith(':true')), audio.join(' '));
  const snd = await page.evaluate(() => {
    const heard = [];
    const o = Sfx.play; Sfx.play = n => { heard.push(n); };
    myMap = 'portals'; startGame(); countdown = 0;
    const a = portals[0]; me.fx.shield = 99; mouse.active = false;
    me.x = a.x - 3; me.y = a.y; me.cx = Math.floor(me.x); me.cy = Math.floor(me.y); me.angle = me.desired = 0;
    for (let k = 0; k < 40; k++) { move(me, 1 / 60); checkPortals(me); }
    myMap = 'belts'; startGame(); countdown = 0;
    const i = belt.findIndex(d => d); me.x = (i % N) + 0.5; me.y = Math.floor(i / N) - 0.5; me.cx = Math.floor(me.x); me.cy = Math.floor(me.y); me.angle = me.desired = Math.PI / 2;
    for (let k = 0; k < 20; k++) move(me, 1 / 60);
    Sfx.play = o; myMap = 'square'; state = 'menu'; me = null; gameCounter++;
    return heard;
  });
  ok('Portals and belts have their own sounds', snd.includes('portal') && snd.includes('belt'), snd.join(','));
  await page.evaluate(() => { settings.track = 'sunny'; saveSettings(); showScreen('menu'); });

  // Mobile boss bar
  await page.setViewportSize({ width: 390, height: 780 });
  await page.evaluate(() => { resize(); myMode = 'boss'; startGame(); countdown = 0; updateHud(); });
  await page.waitForTimeout(400);
  await page.screenshot({ path: S + '/pl-boss-mobile.png' });
  const bar = await page.locator('#boss-bar').boundingBox(), hud = await page.locator('#hud .left').boundingBox();
  ok('Boss bar fits on a phone without covering the HUD', bar && bar.x >= 0 && bar.x + bar.width <= 390 && bar.y > hud.y + hud.height - 2, JSON.stringify({ bar, hud }));
  await page.evaluate(() => { myMode = 'classic'; save('color-claim-mode', 'classic'); });

  ok('No page errors', errors.length === 0, errors.join(' | '));
  await browser.close();
})();
