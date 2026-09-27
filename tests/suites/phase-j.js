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

  // ---------- Emotes ----------
  await page.evaluate(() => { myMode = 'classic'; myMap = 'square'; startGame(); countdown = 0; });
  await page.keyboard.press('1');
  const e1 = await page.evaluate(() => me.emote && me.emote.id);
  await page.keyboard.press('2');
  const e2 = await page.evaluate(() => me.emote && me.emote.id);
  ok('Key 1 shows the "Hi" emote', e1 === 'hi');
  ok('Emotes have a short cooldown', e2 === 'hi');
  await page.waitForTimeout(300);
  await page.screenshot({ path: S + '/pj-emote.png' });
  await page.click('#emote-btn');
  ok('Smiley button opens a tray of 6 emotes', await page.isVisible('#emote-tray') && await page.locator('#emote-tray .emote-btn').count() === 6);
  await page.screenshot({ path: S + '/pj-tray.png' });
  await page.evaluate(() => { emoteCooldown = 0; });
  await page.click('.emote-btn[data-emote="gg"]');
  ok('Picking one sends it and closes the tray', await page.evaluate(() => me.emote.id === 'gg') && !(await page.isVisible('#emote-tray')));
  const reply = await page.evaluate(async () => {
    const bot = players.find(p => p && p.isBot);
    bot.x = me.x + 3; bot.y = me.y; bot.emoteWait = 0;
    for (const p of players) if (p && p.isBot && p !== bot) { p.x = 5; p.y = 5; }
    for (let k = 0; k < 6 && !bot.emote; k++) {
      emoteCooldown = 0; bot.emoteWait = 0; playerEmote('hi');
      await new Promise(r => setTimeout(r, 1300));
    }
    return bot.emote && bot.emote.id;
  });
  ok('A nearby bot answers your emote', !!reply, reply);
  const gone = await page.evaluate(() => { me.emote = { id: 'lol', t: 0 }; for (let i = 0; i < 140; i++) update(1 / 60); return me.emote; });
  ok('Emotes fade after a couple of seconds', gone === null);
  const off = await page.evaluate(() => { settings.emotes = false; const b = players.find(p => p && p.isBot && p.alive); b.emote = null; b.emoteWait = 0; botEmote(b, 'grr'); const r = b.emote; settings.emotes = true; return r; });
  ok('Bot emotes can be turned off', off === null || off === undefined);
  await page.evaluate(() => { state = 'menu'; me = null; gameCounter++; showScreen('settings'); buildSettings(); });
  ok('Settings has a Bot emotes row', (await page.textContent('#settings-list')).includes('Bot emotes'));
  await page.evaluate(() => showScreen('menu'));

  // ---------- Ranked ladder ----------
  const tiers = await page.evaluate(() => [0, 150, 299, 300, 650, 1199, 1500, 2400].map(v => rankInfo(v).label));
  ok('Rank tiers and divisions', tiers.join('|') === 'Bronze III|Bronze II|Bronze I|Silver III|Gold III|Platinum I|Champion|Champion', tiers.join('|'));
  const promo = await page.evaluate(() => {
    rp = 290; rankBest = 0; const c0 = coins;
    myMode = 'classic'; myMap = 'square'; myDiff = 'normal'; startGame(); countdown = 0;
    const res = rankGameResult(true);
    return { rp, label: res.after.label, gain: res.gain, promoted: res.promoted, coins: coins - c0, best: rankBest };
  });
  ok('Winning gives +40 RP and a promotion pays coins', promo.gain === 40 && promo.label === 'Silver III' && promo.promoted && promo.coins === 100 && promo.best === 1, JSON.stringify(promo));
  const floor = await page.evaluate(() => {
    rp = 305; startGame(); countdown = 0;
    for (const p of players) if (p && p.isBot) { for (let i = 0; i < 200; i++) setOwner(i + p.id * 300, p.id); }
    peakPct = 0; me.alive = false;
    const res = rankGameResult(false);
    return { rp, place: res.place, gain: res.gain };
  });
  ok("Losing can't drop you out of a tier you've reached", floor.rp === 300 && floor.place === 8 && floor.gain === -5, JSON.stringify(floor));
  const hard = await page.evaluate(() => { rp = 0; myDiff = 'hard'; startGame(); countdown = 0; const g = rankGameResult(true).gain; myDiff = 'normal'; return g; });
  ok('Hard bots give 1.5x points', hard === 60, 'gain=' + hard);
  const gold = await page.evaluate(() => { rp = 590; rankBest = 1; startGame(); countdown = 0; peakPct = 30; const r = finishRun(true, 30); return { tier: rankInfo(rp).name, golden: !!achieved.golden, trophy: r.fresh.some(a => a.id === 'golden') }; });
  ok('Reaching Gold earns the Golden trophy', gold.tier === 'Gold' && gold.golden && gold.trophy, JSON.stringify(gold));
  // Full game over flow in a ranked mode
  await page.evaluate(() => { rp = 100; startGame(); countdown = 0; peakPct = 12; kill(me, me); });
  await page.waitForTimeout(1300);
  ok('Game over shows your rank change', await page.isVisible('#over-rank') && /Bronze .* RP/.test(await page.textContent('#over-rank')), await page.textContent('#over-rank'));
  await page.screenshot({ path: S + '/pj-over.png' });
  await page.click('#menu-btn');
  ok('Menu shows your rank', (await page.textContent('.rank-nav')).includes('Bronze'), await page.textContent('.rank-nav'));
  await page.click('.rank-nav');
  ok('Rank screen lists the 6 tiers', await page.isVisible('#rank') && await page.locator('#rank-ladder li').count() === 6 && (await page.textContent('#rank-card')).includes('RP'));
  await page.screenshot({ path: S + '/pj-rank.png' });
  await page.click('#rank [data-back]');
  const unranked = await page.evaluate(() => {
    const out = {};
    for (const m of ['team', 'duo', 'cup']) { myMode = m; startGame(); countdown = 0; out[m] = isRanked(); state = 'menu'; me = null; gameCounter++; }
    myMode = 'classic'; challenge = { seed: 5, mode: 'classic', map: 'square', diff: 'normal', score: 5 }; startGame(); out.challenge = isRanked(); challenge = null;
    state = 'menu'; me = null; gameCounter++; showScreen('menu');
    return out;
  });
  ok('Teams, 2 Players, Cup and challenges are not ranked', Object.values(unranked).every(v => !v), JSON.stringify(unranked));
  await page.evaluate(() => { myMode = 'classic'; buildPickers(); });
  const d1 = await page.textContent('#mode-desc');
  await page.evaluate(() => { myMode = 'team'; buildPickers(); });
  const d2 = await page.textContent('#mode-desc');
  await page.evaluate(() => { myMode = 'classic'; buildPickers(); });
  ok('Mode description says which modes are ranked', d1.includes('Ranked') && !d2.includes('Ranked'));
  await page.evaluate(() => { showScreen('stats'); buildStats(); });
  ok('Stats show your rank', (await page.textContent('#stats-grid')).includes('Rank'));
  await page.evaluate(() => showScreen('menu'));

  // ---------- Saw Mill ----------
  const saw = await page.evaluate(() => {
    myMode = 'classic'; myMap = 'saws'; startGame(); countdown = 0;
    const n = saws.length, start = saws.map(sw => [sw.x, sw.y]);
    for (let i = 0; i < 30; i++) update(1 / 60);
    const moved = saws.every((sw, k) => Math.hypot(sw.x - start[k][0], sw.y - start[k][1]) > 0.1) && saws.some((sw, k) => Math.hypot(sw.x - start[k][0], sw.y - start[k][1]) > 1);
    // A bot's trail under a saw is cut
    const sw = saws[0], bot = players.find(p => p && p.isBot && p.alive);
    bot.fx.shield = 0;
    const i = Math.floor(sw.y) * N + Math.floor(sw.x);
    trail[i] = bot.id; bot.trail.push(i);
    updateHazards(0);
    const cut = !bot.alive;
    // A shielded bot is safe
    const b2 = players.find(p => p && p.isBot && p.alive && p !== bot);
    b2.fx.shield = 3;
    trail[i] = b2.id; b2.trail.push(i);
    updateHazards(0);
    const shielded = b2.alive;
    trail[i] = 0; b2.trail = [];
    return { n, moved, cut, shielded, feed: feed.map(f => f.text).join(' | ') };
  });
  ok('Saw Mill has moving saws', saw.n === 5 && saw.moved, JSON.stringify(saw));
  ok('A saw cuts any trail it touches', saw.cut && saw.feed.includes('A saw cut'));
  ok('A shield protects you from saws', saw.shielded);
  await page.evaluate(() => { cam.zoom = 0.7; me.fx.shield = 0; });
  await page.waitForTimeout(800);
  await page.screenshot({ path: S + '/pj-saws.png' });
  await page.evaluate(() => { const sw = saws[1]; const i = Math.floor(sw.y) * N + Math.floor(sw.x); me.fx.shield = 0; trail[i] = me.id; me.trail.push(i); updateHazards(0); });
  await page.waitForTimeout(1300);
  ok('Getting sawn ends your game with a reason', (await page.textContent('#over-reason')) === 'A saw cut your trail!');

  // ---------- Storm ----------
  const st = await page.evaluate(() => {
    myMode = 'classic'; myMap = 'storm'; startGame(); countdown = 0;
    const cells0 = playCells;
    // Park a shielded bot in the corner, then fast-forward to the first warning
    const bot = players.find(p => p && p.isBot && p.alive);
    bot.isBot = false; bot.fx.shield = 99; window.cornerBot = bot;
    storm.clock = STORM_WARN + 0.05;
    for (let i = 0; i < 10; i++) update(1 / 60);
    const warn = storm.phase;
    updateHud();
    const hud = $('storm-info').textContent;
    return { cells0, warn, hud, to: +(storm.to / N).toFixed(2) };
  });
  ok('The storm warns before it closes in', st.warn === 'warn' && /Storm closes in \d+s!/.test(st.hud) && st.to === 0.56, JSON.stringify(st));
  await page.evaluate(() => { cam.zoom = 0.45; });
  await page.waitForTimeout(700);
  await page.screenshot({ path: S + '/pj-storm-warn.png' });
  const st2 = await page.evaluate(() => {
    const bot = window.cornerBot;
    me.fx.shield = 99;
    const stormKills = [], o = kill;
    kill = (v, k, h = 'cut') => { const was = v.alive; o(v, k, h); if (was && !v.alive && h === 'storm') stormKills.push(v.name); };
    for (let i = 0; i < 12 * 60; i++) { if (bot.alive) { bot.x = bot.y = 3.5; bot.cx = bot.cy = 3; } update(1 / 60); }
    let outside = 0, inside = 0;
    for (let y = 0; y < N; y++) for (let x = 0; x < N; x++) {
      const d = Math.hypot(x + 0.5 - N / 2, y + 0.5 - N / 2);
      if (d > storm.r && wall[y * N + x] !== 3) outside++;
      if (d < storm.r - 1 && wall[y * N + x] === 3) inside++;
    }
    let owned = 0; for (let i = 0; i < N * N; i++) if (wall[i] && (owner[i] || trail[i])) owned++;
    kill = o;
    const total = players.filter(p => p && p.alive).reduce((a, p) => a + pct(p), 0);
    return { phase: storm.phase, r: +(storm.r / N).toFixed(2), cells: playCells, outside, inside, owned, cornerAlive: bot.alive, total: +total.toFixed(1), feed: stormKills.join(',') + ' / ' + bot.name };
  });
  ok('The storm shrinks the arena', st2.r === 0.56 && st2.cells < st.cells0 && st2.outside === 0 && st2.inside === 0, JSON.stringify(st2));
  ok('Nothing is owned inside the storm', st2.owned === 0);
  ok('The storm catches players even through a shield', st2.cornerAlive === false && st2.feed.split(' / ')[0].split(',').includes(st2.feed.split(' / ')[1]), st2.feed);
  ok('Land shares still add up', st2.total <= 100.01);
  const rec = await page.evaluate(() => { for (let i = 0; i < 30; i++) { update(1 / 60); recordFrame(); } const f = replayFrames[replayFrames.length - 1]; return !!f.wall && f.saws.length === 0 && !!f.storm; });
  ok('Replays record the storm', rec);
  await page.evaluate(() => { startGame(); countdown = 0; mouse.active = false; storm.r = N * 0.45; me.fx.shield = 0; me.x = N / 2 + storm.r - 1.5; me.y = N / 2; me.cx = Math.floor(me.x); me.cy = Math.floor(me.y); storm.phase = 'shrink'; storm.from = storm.r; storm.to = storm.r - 3; storm.clock = 0.01; update(1 / 60); });
  await page.waitForTimeout(1300);
  ok('Getting caught by the storm ends your game', (await page.textContent('#over-reason')) === 'The storm caught you!', await page.textContent('#over-reason'));
  const codes = await page.evaluate(() => ['saws', 'storm'].map(m => { const c = { seed: 99, mode: 'classic', map: m, diff: 'hard', score: 12.5 }; return JSON.stringify(readCode(makeCode(c))) === JSON.stringify(c); }));
  ok('Challenge codes work on the new maps', codes.every(Boolean));
  ok('New maps are in the map picker', await page.evaluate(() => { showScreen('menu'); buildPickers(); return document.getElementById('maps').textContent; }).then(t => t.includes('Saw Mill') && t.includes('Storm')));

  // Bots on the new maps
  const sims = await page.evaluate(() => {
    const out = {};
    for (const m of ['saws', 'storm']) {
      const c = { self: 0, hazard: 0, other: 0, stuck: 0, zero: 0 };
      for (let g = 0; g < 2; g++) {
        myMode = 'classic'; myMap = m; startGame(); countdown = 0; me.isBot = true;
        const o = kill;
        kill = (v, k, h = 'cut') => { const was = v.alive; o(v, k, h); if (was && !v.alive) { if (h === 'saw' || h === 'storm') c.hazard++; else if (k === v) c.self++; else c.other++; } };
        for (let i = 0; i < 150 * 60; i++) { state = 'play'; update(1 / 60); if (!me.alive) { me.alive = true; spawn(me); } for (const p of players) if (p && p.alive) { if (wall[p.cy * N + p.cx]) c.stuck++; if (counts[p.id] === 0) c.zero++; } }
        kill = o;
      }
      out[m] = c;
    }
    state = 'menu'; me = null; gameCounter++;
    return out;
  });
  for (const [m, c] of Object.entries(sims)) ok(`${m}: bots play cleanly`, c.stuck === 0 && c.zero === 0 && c.self <= Math.max(3, c.other * 0.2) && c.hazard <= c.other * 0.5, JSON.stringify(c));

  // ---------- GIF ----------
  await page.evaluate(() => { showScreen('menu'); myMap = 'saws'; startGame(); countdown = 0; me.isBot = true; });
  await page.waitForTimeout(3000);
  await page.evaluate(() => { me.isBot = false; me.emote = { id: 'cool', t: 0 }; });
  await page.waitForTimeout(600);
  await page.evaluate(() => { peakPct = Math.max(peakPct, 3); kill(me, me); });
  await page.waitForTimeout(1300);
  ok('Game over offers a GIF', await page.isVisible('#gif-btn'));
  const nFrames = await page.evaluate(() => replayFrames.length);
  const t0 = Date.now();
  await page.click('#gif-btn');
  await page.waitForSelector('#gif-img:not(.hidden)', { timeout: 60000 });
  const took = Date.now() - t0;
  const gif = await page.evaluate(async () => {
    const buf = new Uint8Array(await (await fetch(gifUrl)).arrayBuffer());
    let bin = ''; for (let i = 0; i < buf.length; i += 8192) bin += String.fromCharCode(...buf.subarray(i, i + 8192));
    const img = document.getElementById('gif-img');
    return { b64: btoa(bin), w: img.naturalWidth, h: img.naturalHeight, save: !document.getElementById('gif-save').classList.contains('hidden'), status: document.getElementById('gif-status').textContent, ctxOk: ctx === canvas.getContext('2d'), W, H };
  });
  fs.writeFileSync(S + '/replay.gif', Buffer.from(gif.b64, 'base64'));
  ok('GIF is made and shown', gif.w === 320 && gif.h === 320 && gif.save, `${took} ms, ${gif.status}`);
  ok('Drawing is back on the screen after the GIF', gif.ctxOk && gif.W === 1100 && gif.H === 760);
  const pil = require('child_process').execSync(`python3 -c "
from PIL import Image, ImageSequence
im=Image.open('${S}/replay.gif'); n=sum(1 for _ in ImageSequence.Iterator(im)); print(n, im.size[0], im.info.get('loop'))"`).toString().trim();
  ok('GIF decodes with every replay frame and loops', pil === `${nFrames} 320 0`, pil + ' vs ' + nFrames);
  await page.screenshot({ path: S + '/pj-gif.png' });
  await page.click('#again-btn');
  ok('A new game clears the old GIF', await page.evaluate(() => gifUrl === null && document.getElementById('gif-img').classList.contains('hidden')));

  // Mobile
  await page.setViewportSize({ width: 390, height: 780 });
  await page.evaluate(() => { resize(); myMap = 'storm'; startGame(); countdown = 0; storm.clock = 3; update(1 / 60); updateHud(); document.getElementById('emote-tray').classList.remove('hidden'); });
  await page.waitForTimeout(500);
  await page.screenshot({ path: S + '/pj-mobile.png' });
  const tray = await page.locator('#emote-tray').boundingBox();
  ok('Emote tray fits on a phone', tray && tray.x >= 0 && tray.x + tray.width <= 390, JSON.stringify(tray));
  await page.evaluate(() => { state = 'menu'; me = null; gameCounter++; showScreen('rank'); buildRank(); });
  await page.screenshot({ path: S + '/pj-rank-mobile.png' });
  const wide = await page.evaluate(() => document.documentElement.scrollWidth);
  ok('Rank screen fits on a phone', wide <= 390, 'scrollWidth=' + wide);

  ok('No page errors', errors.length === 0, errors.join(' | '));
  await browser.close();
})();
