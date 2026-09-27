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
  await page.screenshot({ path: S + '/pc-menu.png' });
  ok('Menu shows 0 coins for a new player', (await page.textContent('#menu .coin-count')) === '0');

  // Play a game and end it: coins + achievements
  await page.click('#play-btn');
  const res = await page.evaluate(() => {
    countdown = 0;
    for (const p of players) if (p) p.fx.shield = 0;
    // Pretend: claimed 12%, 2 knockouts, grabbed power-ups
    peakPct = 12; me.kills = 2; run.powerups = 3; run.bigLoop = 6;
    return true;
  });
  await page.waitForTimeout(1300); // live achievement check runs every second
  ok('Achievements pop up during the game', await page.evaluate(() => !!achieved.land5 && !!achieved.ko1 && !!achieved.loop5));
  await page.evaluate(() => kill(me, me));
  await page.waitForTimeout(1300);
  const over = await page.evaluate(() => ({ coinsText: document.getElementById('over-coins').textContent, coins, stats: { ...stats } }));
  // 12% -> 24, 2 KOs -> 10, three trophies -> 75
  ok('Coins paid out for the game', /^\+34 /.test(over.coinsText.trim()) && over.coins >= 34 + 75, `${over.coinsText.trim()} total=${over.coins}`);
  ok('Stats updated (games, KOs, power-ups)', over.stats.games === 1 && over.stats.kills === 2 && over.stats.powerups === 3 && over.stats.bestKills === 2);
  await page.screenshot({ path: S + '/pc-over.png' });

  // Locker: buy a trail effect and a skin
  await page.click('#menu-btn');
  await page.evaluate(() => { coins = 100; renderCoins(); });
  await page.click('[data-open="locker"]');
  ok('Locker opens with skins', await page.isVisible('#locker') && (await page.$$('#locker-items .item')).length === 16);
  const buyable = await page.$$eval('#locker-items .item-btn', bs => bs.map(b => [b.textContent.trim(), b.disabled]));
  ok('Skins cost 150 and are disabled when you cannot afford them', buyable.some(([t, d]) => t.startsWith('Buy · 150') && d), JSON.stringify(buyable.slice(0, 3)));
  await page.click('#locker .tab[data-tab="trails"]');
  await page.click('#locker-items .item >> nth=1 >> .item-btn'); // Sparkles, 80 coins
  ok('Buying a trail effect spends coins and equips it', await page.evaluate(() => coins === 100 - 80 && myFx === 'sparkle' && ownedFx.includes('sparkle')));
  await page.screenshot({ path: S + '/pc-locker.png' });
  await page.evaluate(() => { coins = 500; renderCoins(); lockerTab = 'skins'; buildLocker(); });
  await page.click('#locker-items .item >> nth=5 >> .item-btn'); // Confetti
  ok('Buying a skin unlocks and equips it', await page.evaluate(() => mySkin === 'confetti' && isUnlocked(SKINS.find(s => s.id === 'confetti')) && coins === 350));
  ok('Purchases survive a reload', await page.evaluate(() => JSON.parse(localStorage.getItem('color-claim-owned-skins')).includes('confetti') && localStorage.getItem('color-claim-fx') === 'sparkle'));

  // Trail effect in game
  await page.click('[data-back]:visible');
  await page.click('#play-btn');
  await page.evaluate(() => { countdown = 0; me.isBot = true; });
  await page.waitForTimeout(2500);
  ok('Trail effect particles appear while outside your land', await page.evaluate(() => fxParts.length > 0 || me.trail.length === 0));
  await page.screenshot({ path: S + '/pc-fx.png' });
  await page.evaluate(() => { me.isBot = false; kill(me, me); });
  await page.waitForTimeout(1200);

  // Trophies & stats screens
  await page.click('#menu-btn');
  await page.evaluate(() => openScreen('trophies'));
  ok('Trophies screen lists all 19', (await page.$$('#trophy-list li')).length === 19, await page.textContent('#trophy-count'));
  await page.screenshot({ path: S + '/pc-trophies.png' });
  await page.click('#trophies [data-back]');
  await page.evaluate(() => openScreen('stats'));
  ok('Stats screen shows games played', (await page.textContent('#stats-grid')).includes('Games played'));
  await page.screenshot({ path: S + '/pc-stats.png' });
  console.log('errors', errors);
  await browser.close();
})();
