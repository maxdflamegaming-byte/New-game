const { chromium, ROOT, OUT } = require('../lib');
const fs = require('fs');
(async () => {
  const S = OUT;
  const browser = await chromium.launch();
  const errors = [];
  const ok = (name, cond, extra = '') => console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? '  ' + extra : ''));
  const page = await browser.newPage({ viewport: { width: 390, height: 844 }, hasTouch: true });
  page.on('pageerror', e => errors.push(e.message));
  await page.goto('file://' + ROOT + '/color-claim/index.html');
  await page.evaluate(() => { localStorage.setItem('color-claim-howto-seen', '1'); localStorage.setItem('color-claim-tutorial-done', '1'); });
  const menuOff = () => page.evaluate(() => { state = 'menu'; me = null; gameCounter++; showScreen('menu'); });

  // ---------- Smarter bots ----------
  const gang = await page.evaluate(() => {
    myMode = 'classic'; myMap = 'square'; myDiff = 'normal'; startGame(); countdown = 0;
    // Give yourself a big lead
    let need = Math.ceil(playCells * 0.2) - counts[me.id];
    for (let i = 0; i < N * N && need > 0; i++) if (!wall[i] && !owner[i] && !trail[i]) { setOwner(i, me.id); need--; }
    gangTimer = 0; updateGang(0.1);
    const leader = gangLeader === me, toastText = document.getElementById('toast').textContent;
    // Compare how often a bot goes for your trail with and without the gang-up
    me.x = 40.5; me.y = 40.5; me.cx = 40; me.cy = 40; me.trail = [40 * N + 41, 40 * N + 42, 40 * N + 43, 40 * N + 44, 40 * N + 45];
    me.fx.shield = 0;
    const bot = players.find(p => p && p.isBot);
    bot.x = me.x + 20; bot.y = me.y; bot.aggro = 0.05; bot.persona = 'turtle';
    const tries = n => { let hunts = 0; for (let k = 0; k < n; k++) { bot.mode = 'idle'; bot.wp = []; bot.trail = [1]; think(bot); if (bot.mode === 'hunt') hunts++; } bot.trail = []; return hunts; };
    const withGang = tries(400);
    gangLeader = null;
    const without = tries(400);
    return { leader, toastText, withGang, without };
  });
  ok('A runaway leader gets ganged up on', gang.leader && gang.toastText.includes('teaming up'), gang.toastText);
  ok('Bots go for the leader far more often', gang.withGang > gang.without * 2 && gang.withGang > 40, JSON.stringify(gang));
  const lurk = await page.evaluate(() => {
    startGame(); countdown = 0;
    const bot = players.find(p => p && p.isBot); bot.persona = 'hunter'; bot.mode = 'idle'; bot.wp = []; bot.trail = []; bot.fx.shield = 0;
    me.x = bot.x + 12; me.y = bot.y; me.trail = []; me.fx.shield = 0;
    const o = Math.random; Math.random = () => 0.01;
    think(bot);
    const mode1 = bot.mode, spot = bot.lurkSpot, own = spot && owner[Math.floor(spot.y) * N + Math.floor(spot.x)] === bot.id;
    // Your trail shows up nearby: the ambusher pounces
    const cy = Math.floor(me.y);
    me.trail = [0, 1, 2, 3, 4].map(k => cy * N + Math.floor(me.x) + k).filter(i => !owner[i] || owner[i] === me.id);
    for (const i of me.trail) trail[i] = me.id;
    think(bot);
    Math.random = o;
    return { mode1, own, mode2: bot.mode };
  });
  ok('Hunters lie in wait at the edge of their own land', lurk.mode1 === 'lurk' && lurk.own, JSON.stringify(lurk));
  ok('...and pounce when your trail appears', lurk.mode2 === 'hunt', JSON.stringify(lurk));
  await menuOff();

  // ---------- Custom rules ----------
  await page.click('#modes .seg-btn:has-text("Custom")');
  ok('Custom mode shows 5 rule rows', await page.isVisible('#rules') && await page.locator('#rules .rule-row').count() === 5);
  for (const [rule, text] of [['speed', 'Fast'], ['bots', '2'], ['power', 'Lots'], ['size', 'Giant'], ['goal', '3:00']]) await page.click(`#rules [data-rule="${rule}"] .seg-btn:has-text("${text}")`);
  const saved = await page.evaluate(() => JSON.parse(localStorage.getItem('color-claim-rules')));
  ok('Rules are saved', saved.speed === 'fast' && saved.bots === 2 && saved.power === 'lots' && saved.size === 'giant' && saved.goal === 'timed', JSON.stringify(saved));
  ok('Mode description sums up the rules', (await page.textContent('#mode-desc')).includes('Fast speed · 2 bots') && (await page.textContent('#mode-desc')).includes('half coins, not ranked'));
  await page.screenshot({ path: S + '/po-custom.png' });
  const cg = await page.evaluate(() => {
    startGame(); countdown = 0;
    const r = { n: N, bots: players.filter(p => p && p.isBot).length, time: gameMode.time, win: gameMode.win, speed: +(speedOf(me) / SPEED).toFixed(2), power: gameMode.powerups, ranked: isRanked() };
    peakPct = 20; me.kills = 0;
    const c0 = coins; r.earned = finishRun(false, 20).earned;
    return r;
  });
  ok('A custom game follows the rules', cg.n === 120 && cg.bots === 2 && cg.time === 180 && cg.win === 0 && cg.speed === 1.35 && cg.power === 9 && !cg.ranked, JSON.stringify(cg));
  ok('Custom games pay half coins', cg.earned === 20, 'earned ' + cg.earned);
  const normal = await page.evaluate(() => { myMode = 'classic'; startGame(); return { speed: speedOf(me) / SPEED, n: N }; });
  ok('Other modes use normal rules', normal.speed === 1 && normal.n === 80);
  await menuOff();
  await page.evaluate(() => { myMode = 'classic'; save('color-claim-mode', 'classic'); buildPickers(); });
  ok('Rules panel hides in other modes', !(await page.isVisible('#rules')));

  // ---------- Holidays ----------
  const hol = await page.evaluate(() => {
    const at = d => { holidayClock = d; holidayCache.at = 0; const h = holidayNow(); return h ? h.id : null; };
    const out = { sep: at('2026-09-27T12:00'), oct15: at('2026-10-15T12:00'), nov3: at('2026-11-03T12:00'), dec20: at('2026-12-20T12:00'), jan3: at('2027-01-03T12:00'), jan8: at('2027-01-08T12:00'), feb10: at('2027-02-10T12:00') };
    holidayClock = '2026-09-27T12:00'; holidayCache.at = 0;
    const soon = holidaySoon();
    out.soon = soon && `${soon.id} in ${soon.days}`;
    return out;
  });
  ok('Holiday dates: Halloween, Winter Fest (over New Year) and Hearts Week', hol.sep === null && hol.oct15 === 'halloween' && hol.nov3 === null && hol.dec20 === 'winter' && hol.jan3 === 'winter' && hol.jan8 === null && hol.feb10 === 'hearts', JSON.stringify(hol));
  ok('A "coming soon" banner shows before an event', hol.soon === 'halloween in 4', hol.soon);
  await page.evaluate(() => renderHoliday());
  ok('Home shows the upcoming event', await page.isVisible('#holiday-banner') && (await page.textContent('#holiday-banner')).includes('Starts in 4 days'));
  await page.evaluate(() => { holidayClock = '2026-10-15T12:00'; holidayCache.at = 0; holidayProgress = {}; ownedSkins = ownedSkins.filter(s => s !== 'pumpkin'); renderHoliday(); });
  ok('During Halloween the banner shows your pumpkin count', (await page.textContent('#holiday-banner')).includes('0 / 40 for the Pumpkin skin'));
  await page.screenshot({ path: S + '/po-halloween-home.png' });
  const ht = await page.evaluate(() => ({ theme: themeId(), picked: (settings.theme = 'classic', themeId()) }));
  await page.evaluate(() => { settings.theme = 'season'; });
  ok('Halloween gives the maps a spooky look (unless you pick a look)', ht.theme === 'spooky' && ht.picked === 'classic', JSON.stringify(ht));
  await page.evaluate(() => openScreen('locker'));
  ok('The Pumpkin skin is an event reward in the Shop', (await page.textContent('#locker-items')).includes('Pumpkin') && (await page.textContent('#locker-items')).includes('Event reward'));
  await page.evaluate(() => showScreen('menu'));
  const pick = await page.evaluate(() => {
    myMode = 'classic'; startGame(); countdown = 0;
    const before = coins;
    for (let k = 0; k < 40; k++) { mapCoins = [{ x: me.x, y: me.y, age: 1, life: 20 }]; updateMapCoins(0.01); }
    return { n: holidayProgress.halloween, skin: ownedSkins.includes('pumpkin'), coins: coins - before };
  });
  ok('Collecting 40 pumpkins unlocks the Pumpkin skin (and still pays coins)', pick.n === 40 && pick.skin && pick.coins >= 80, JSON.stringify(pick));
  await page.evaluate(() => { cam.zoom = 0.9; mapCoins = [{ x: me.x + 3, y: me.y - 2, age: 1, life: 20 }, { x: me.x - 4, y: me.y + 3, age: 1, life: 20 }]; me.skin = 'pumpkin'; });
  await page.waitForTimeout(800);
  await page.screenshot({ path: S + '/po-halloween-game.png' });
  const skinsDrawn = await page.evaluate(() => ['pumpkin', 'snowman', 'cupid'].map(sk => { const c = document.createElement('canvas'); c.width = c.height = 60; drawBody(c.getContext('2d'), { color: '#4f8cff', dark: '#2f55b8', skin: sk, blink: 1, hueOff: 0 }, 40, 0); return sk; }).length);
  ok('All 3 holiday skins draw', skinsDrawn === 3);
  await menuOff();
  await page.evaluate(() => { holidayClock = null; holidayCache.at = 0; renderHoliday(); });

  // ---------- Player card ----------
  await page.evaluate(() => { myName = 'Ace'; clan = { name: 'Loop Lords', tag: 'LL1', color: 4, emblem: 'crown', cp: 10, war: { week: weekInfo().week, cp: 0 } }; openScreen('profile'); });
  ok('Profile has a player card button', await page.isVisible('#profile-card-btn'));
  await page.click('#profile-card-btn');
  await page.waitForSelector('#card-result:not(.hidden)', { timeout: 10000 });
  const card = await page.evaluate(async () => {
    const img = document.getElementById('card-img'); await img.decode();
    const buf = new Uint8Array(await cardBlob.arrayBuffer());
    let bin = ''; for (let i = 0; i < buf.length; i += 8192) bin += String.fromCharCode(...buf.subarray(i, i + 8192));
    return { w: img.naturalWidth, h: img.naturalHeight, type: cardBlob.type, b64: btoa(bin), save: !!document.getElementById('card-save').href };
  });
  fs.writeFileSync(S + '/po-card.png', Buffer.from(card.b64, 'base64'));
  ok('Player card is a 900 × 1200 picture you can save', card.w === 900 && card.h === 1200 && card.type === 'image/png' && card.save, `${card.w}x${card.h}`);
  await page.screenshot({ path: S + '/po-card-modal.png' });
  await page.click('#card-close');
  ok('Closing the card hides it', !(await page.isVisible('#card-result')));
  const wide = await page.evaluate(() => document.documentElement.scrollWidth);
  ok('Everything fits on a phone', wide <= 390, 'scrollWidth=' + wide);

  ok('No page errors', errors.length === 0, errors.join(' | '));
  await browser.close();
})();
