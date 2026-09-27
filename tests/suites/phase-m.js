const { chromium, ROOT, OUT } = require('../lib');
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

  // ---------- Bosses ----------
  await page.click('#modes .seg-btn:has-text("Boss Battle")');
  const pick0 = await page.evaluate(() => ({ shown: !document.getElementById('bosses').classList.contains('hidden'), n: document.querySelectorAll('#bosses .seg-btn').length, locked: [...document.querySelectorAll('#bosses .seg-btn')].map(b => b.disabled) }));
  ok('Boss picker shows 3 bosses, Queen and Wizard locked at first', pick0.shown && pick0.n === 3 && JSON.stringify(pick0.locked) === '[false,true,true]', JSON.stringify(pick0));
  await page.evaluate(() => { stats.bossBeaten = { king: 1 }; buildPickers(); });
  ok('Beating the King unlocks the Queen', await page.evaluate(() => !document.querySelectorAll('#bosses .seg-btn')[1].disabled && document.querySelectorAll('#bosses .seg-btn')[2].disabled));
  await page.click('#bosses .seg-btn >> nth=1');
  ok('Mode description explains the Queen', (await page.textContent('#mode-desc')).includes('Queen: Drops spiky traps'));
  await page.click('#play-btn');
  await page.waitForTimeout(200);
  const q = await page.evaluate(() => ({ name: king.name, kind: king.kind, hp: king.hp }));
  ok('The Queen has an extra heart', q.name === 'Queen' && q.kind === 'queen' && q.hp === 6, JSON.stringify(q));
  const trap = await page.evaluate(() => {
    countdown = 0;
    // She drops traps while she's out of her land
    king.trail = [1, 2, 3, 4, 5]; king.trapTimer = 0; king.x = 30.5; king.y = 30.5; king.angle = 0;
    updateBoss(1 / 60);
    const n = traps.length, t = traps[0];
    king.trail = [];
    // A bot's trail over a trap is cut; the Queen's own isn't
    const bot = makePlayer(players.length, 'Victim', '#8bd346', true, 'classic'); bot.team = bot.id; players.push(bot); spawn(bot, 10, 10); bot.fx.shield = 0;
    const i = Math.floor(t.y) * N + Math.floor(t.x);
    trail[i] = bot.id; bot.trail.push(i);
    updateBoss(1 / 60);
    const cut = !bot.alive;
    trail[i] = king.id; king.trail = [i];
    updateBoss(1 / 60);
    const queenSafe = king.alive;
    trail[i] = 0; king.trail = [];
    return { n, cut, queenSafe, feed: feed.map(f => f.text).join('|') };
  });
  ok('The Queen drops traps that cut trails', trap.n === 1 && trap.cut && trap.feed.includes('ran into a trap'), JSON.stringify(trap));
  ok("Her own trail is safe from her traps", trap.queenSafe);
  await page.evaluate(() => { traps.push({ x: me.x + 4, y: me.y - 2, life: 18 }, { x: me.x - 5, y: me.y + 3, life: 18 }); cam.zoom = 1; });
  await page.waitForTimeout(600);
  await page.screenshot({ path: S + '/pm-queen.png' });
  await page.evaluate(() => { me.fx.shield = 0; const t = traps[0]; const i = Math.floor(t.y) * N + Math.floor(t.x); trail[i] = me.id; me.trail.push(i); lives = 1; updateBoss(1 / 60); });
  await page.waitForTimeout(1300);
  ok('Running into a trap ends your game with a reason', (await page.textContent('#over-reason')).includes("Queen's trap"), await page.textContent('#over-reason'));
  const trapsAfter = await page.evaluate(() => { startGame(); countdown = 0; const n = traps.length; king.fx.shield = 0; king.hp = 1; kill(king, me); return { n, after: traps.length }; });
  ok('Traps are cleared between games and when she falls', trapsAfter.n === 0 && trapsAfter.after === 0);
  await menuOff();
  const wiz = await page.evaluate(() => {
    stats.bossBeaten = { king: 1, queen: 1 }; myBoss = 'wizard'; buildPickers();
    startGame(); countdown = 0;
    const k = king, home = counts[k.id];
    // He's out with a trail and you come close: he blinks home and his trail vanishes
    const cells = [];
    for (let d = 1; d <= 14; d++) { const i = k.cy * N + k.cx + d; if (!owner[i] && !wall[i]) { trail[i] = k.id; cells.push(i); } }
    const lastCell = cells[cells.length - 1];
    k.x = (lastCell % N) + 0.5; k.y = k.cy + 0.5;
    k.trail = cells;
    k.cx = Math.floor(k.x);
    me.x = (cells[1] % N) + 0.5; me.y = Math.floor(cells[1] / N) + 2.5;
    k.blinkTimer = 0;
    const o = Math.random; Math.random = () => 0.1;
    updateBoss(1 / 60);
    Math.random = o;
    return { hp: k.hp, name: k.name, trail: k.trail.length, left: cells.filter(i => trail[i] === k.id).length, home: owner[k.cy * N + k.cx] === k.id, timer: k.blinkTimer > 5, feed: feed.map(f => f.text).join('|') };
  });
  ok('The Wizard has 2 extra hearts', wiz.hp === 7 && wiz.name === 'Wizard', JSON.stringify(wiz));
  ok('The Wizard blinks home and wipes his trail when you get close', wiz.trail === 0 && wiz.left === 0 && wiz.home && wiz.timer && wiz.feed.includes('blinked away'));
  await page.evaluate(() => { cam.zoom = 0.9; cam.x = king.x; cam.y = king.y; });
  await page.waitForTimeout(500);
  await page.screenshot({ path: S + '/pm-wizard.png' });
  const beat = await page.evaluate(() => { king.fx.shield = 0; king.hp = 1; me.fx.shield = 99; kill(king, me); return true; });
  await page.waitForTimeout(2800);
  ok('Beating the Wizard counts for Boss Hunter', await page.evaluate(() => stats.bossBeaten.wizard === 1 && !!achieved.bosshunter && document.getElementById('over-reason').textContent === 'You defeated the Wizard!'));
  await menuOff();
  await page.evaluate(() => { myMode = 'classic'; myBoss = 'king'; save('color-claim-mode', 'classic'); buildPickers(); });
  ok('Boss picker hides in other modes', await page.evaluate(() => document.getElementById('bosses').classList.contains('hidden')));

  // ---------- Clan ----------
  await page.click('#clan-nav');
  ok('Clan screen invites you to start one', (await page.textContent('#clan-body')).includes('not in a clan'));
  await page.click('#clan-save');
  ok('A clan needs a name and a tag', (await page.textContent('#clan-error')).includes('2 to 4 letters'));
  await page.fill('#clan-name', 'Loop Lords');
  await page.fill('#clan-tag', 'll!1');
  ok('Tags are cleaned to capitals and numbers', (await page.inputValue('#clan-tag')) === 'LL1');
  await page.click('[data-emblem="crown"]');
  await page.click('#clan-colors [data-color="4"]');
  await page.click('#clan-save');
  const c1 = await page.evaluate(() => ({ clan, nav: document.getElementById('clan-nav').textContent, body: document.getElementById('clan-body').textContent }));
  ok('Starting a clan saves it and shows the clan card', c1.clan.name === 'Loop Lords' && c1.clan.tag === 'LL1' && c1.clan.emblem === 'crown' && c1.clan.color === 4 && c1.nav.includes('[LL1]') && c1.body.includes('Clan war vs'), JSON.stringify(c1.clan));
  await page.screenshot({ path: S + '/pm-clan.png' });
  await page.click('#clan [data-back]');
  const tags = await page.evaluate(() => {
    myMode = 'classic'; startGame(); const solo = me.clanTag;
    myMode = 'team'; startGame(); const mates = players.filter(p => p && p.team === 0 && p !== me).map(p => p.clanTag), foes = players.filter(p => p && p.team === 1).map(p => p.clanTag);
    myMode = 'classic';
    return { solo, mates, foes, rival: rivalClan().tag };
  });
  ok('Your clan tag shows on your name', tags.solo === 'LL1');
  ok('In Teams your teammates wear your tag and the other team is the rival clan', tags.mates.every(t => t === 'LL1') && tags.foes.every(t => t === tags.rival), JSON.stringify(tags));
  await page.evaluate(() => { startGame(); countdown = 0; cam.zoom = 1.3; });
  await page.waitForTimeout(500);
  await page.screenshot({ path: S + '/pm-tag.png' });
  const cp = await page.evaluate(() => {
    const c0 = clan.cp, w0 = clan.war.cp;
    me.kills = 2; peakPct = 12;
    const r = finishRun(true, 12).clanResult;
    return { gain: r.gain, cp: clan.cp - c0, war: clan.war.cp - w0 };
  });
  ok('Games earn clan points (score + win + knockouts)', cp.gain === 12 + 20 + 6 && cp.cp === cp.gain && cp.war === cp.gain, JSON.stringify(cp));
  const lvl = await page.evaluate(() => { const c0 = coins; clan.cp = 295; startGame(); countdown = 0; peakPct = 10; const r = finishRun(false, 10).clanResult; return { lvl: r.level, up: r.levelUp, coins: coins - c0 }; });
  ok('Every 300 CP is a clan level worth 50 coins', lvl.lvl === 2 && lvl.up && lvl.coins >= 50, JSON.stringify(lvl));
  const war = await page.evaluate(() => {
    const week = weekInfo().week, rival = rivalClan(week - 1);
    clan.war = { week: week - 1, cp: rival.target + 1 };
    const c0 = coins, w0 = stats.clanWars || 0;
    const r = settleClanWar();
    const won = { ...r, paid: coins - c0, wars: (stats.clanWars || 0) - w0, fresh: clan.war.week === week && clan.war.cp === 0 };
    clan.war = { week: week - 1, cp: 0 };
    const lost = settleClanWar();
    return { won, lost };
  });
  ok('Winning last week\'s clan war pays 250 coins', war.won.won && war.won.paid === 250 && war.won.wars === 1 && war.won.fresh, JSON.stringify(war.won));
  ok('Losing a clan war pays nothing', war.lost.won === false);
  ok('War Winner trophy', await page.evaluate(() => { startGame(); countdown = 0; return finishRun(false, 1).fresh.some(a => a.id === 'warwinner') || !!achieved.warwinner; }));
  await menuOff();
  await page.click('#clan-nav');
  ok('Clan card shows last week\'s war', (await page.textContent('#clan-body')).includes('Last week'));
  await page.click('#clan-leave');
  ok('Leaving asks twice', await page.evaluate(() => !!clan) && (await page.textContent('#clan-leave')).includes('Tap again'));
  await page.click('#clan-leave');
  ok('Leaving the clan removes it', await page.evaluate(() => clan === null && document.getElementById('clan-nav').textContent === 'Clan'));
  await page.click('#clan [data-back]');

  // ---------- Weekly quests ----------
  const qc = await page.evaluate(() => {
    const chain = weeklyQuests();
    const easy = QUEST_POOL.easy.map(x => x.id), med = QUEST_POOL.medium.map(x => x.id), hard = QUEST_POOL.hard.map(x => x.id);
    return { n: chain.length, rewards: chain.map(x => x.reward), same: JSON.stringify(chain.map(x => x.id)) === JSON.stringify(weeklyQuests().map(x => x.id)),
      order: easy.includes(chain[0].id) && easy.includes(chain[1].id) && med.includes(chain[2].id) && med.includes(chain[3].id) && hard.includes(chain[4].id) };
  });
  ok('Five quests a week: easy, easy, medium, medium, hard', qc.n === 5 && qc.order && qc.same && qc.rewards.join() === '50,75,100,150,300', JSON.stringify(qc));
  const qrun = await page.evaluate(() => {
    questState = { week: weekInfo().week, step: 0, progress: 0, maps: [] };
    const chain = weeklyQuests(), got = [];
    // Play "perfect" games until the chain is done, one step per game
    let games = 0;
    const r = { peak: 40, kills: 20, time: 300, won: true, mode: 'boss', map: 'square', diff: 'hard', powerups: 10, coinsPicked: 20 };
    const maps = ['square', 'round', 'maze', 'pillars'];
    while (questState.step < 5 && games < 40) {
      r.map = maps[games % maps.length]; r.mode = games % 2 ? 'weekly' : 'boss';
      for (const d of updateQuests(r)) got.push(d.step);
      games++;
    }
    return { got, games, chains: stats.questChains };
  });
  ok('Quests unlock one after another and finishing all counts a chain', qrun.got.join() === '1,2,3,4,5' && qrun.chains >= 1, JSON.stringify(qrun));
  await page.evaluate(() => { questState = { week: weekInfo().week, step: 2, progress: 0, maps: [] }; });
  await page.click('.nav-btn[data-open="missions"]');
  const ql = await page.evaluate(() => ({ n: document.querySelectorAll('#quest-list li').length, done: document.querySelectorAll('#quest-list li.done').length, now: document.querySelectorAll('#quest-list li.now').length, locked: document.querySelectorAll('#quest-list li.locked').length, head: document.getElementById('quest-head').textContent }));
  ok('Missions screen shows the quest chain', ql.n === 5 && ql.done === 2 && ql.now === 1 && ql.locked === 2 && ql.head.includes('Quest 3 of 5'), JSON.stringify(ql));
  await page.screenshot({ path: S + '/pm-quests.png' });
  await page.click('#missions [data-back]');
  await page.evaluate(() => { questState = { week: weekInfo().week, step: 0, progress: weeklyQuests()[0].goal, maps: [] }; startGame(); countdown = 0; peakPct = 5; kill(me, me); });
  await page.waitForTimeout(1300);
  const over = await page.textContent('#over-missions');
  ok('Game over lists finished quests', over.includes('Weekly quest 1:') && await page.evaluate(() => questState.step === 1), over);
  await page.click('#menu-btn');

  // ---------- Accessibility ----------
  await page.click('.nav-btn[data-open="settings"]');
  const rows = await page.evaluate(() => [...document.querySelectorAll('#settings-list li > span')].map(s => s.textContent));
  ok('Settings has Text size, High contrast and Game speed', rows.includes('Text size') && rows.includes('High contrast') && rows.includes('Game speed') && rows.length === 14, rows.join(', '));
  const fs0 = await page.evaluate(() => parseFloat(getComputedStyle(document.querySelector('#settings .small')).fontSize));
  await page.click('#settings-list li >> nth=9 >> .seg-btn >> nth=1');
  await page.click('#settings-list li >> nth=10 >> .seg-btn >> nth=1');
  await page.click('#settings-list li >> nth=11 >> .seg-btn >> nth=1');
  const a = await page.evaluate(() => ({ big: document.body.classList.contains('big-text'), contrast: document.body.classList.contains('contrast'), speed: settings.speed, saved: JSON.parse(localStorage.getItem('color-claim-settings')), fs: parseFloat(getComputedStyle(document.querySelector('#settings .small')).fontSize) }));
  ok('Large text makes the text bigger', a.big && a.fs > fs0, `${fs0}px -> ${a.fs}px`);
  ok('High contrast and slower speed switch on and are saved', a.contrast && a.speed === 'slow' && a.saved.bigText && a.saved.contrast && a.saved.speed === 'slow');
  await page.screenshot({ path: S + '/pm-settings.png' });
  const slow = await page.evaluate(() => new Promise(res => {
    myMode = 'classic'; startGame(); countdown = 0;
    const t0 = playTime, r0 = performance.now();
    setTimeout(() => res({ ratio: (playTime - t0) / ((performance.now() - r0) / 1000) }), 1500);
  }));
  ok('Slower speed runs the game at 75%', slow.ratio > 0.6 && slow.ratio < 0.85, 'game seconds per real second: ' + slow.ratio.toFixed(2));
  await page.evaluate(() => { cam.zoom = 1.2; });
  await page.waitForTimeout(400);
  await page.screenshot({ path: S + '/pm-contrast-game.png' });
  await page.reload();
  ok('Accessibility settings stay on after a reload', await page.evaluate(() => document.body.classList.contains('big-text') && document.body.classList.contains('contrast')));
  await page.evaluate(() => { settings.bigText = false; settings.contrast = false; settings.speed = 'normal'; saveSettings(); applyA11y(); });

  // Mobile
  await page.setViewportSize({ width: 390, height: 780 });
  await page.evaluate(() => { resize(); clan = { name: 'Loop Lords', tag: 'LL1', color: 4, emblem: 'crown', cp: 120, war: { week: weekInfo().week, cp: 40 } }; renderClanNav(); clanForm = null; showScreen('clan'); buildClan(); });
  await page.screenshot({ path: S + '/pm-clan-mobile.png' });
  const wide = await page.evaluate(() => document.documentElement.scrollWidth);
  ok('Clan screen fits on a phone', wide <= 390, 'scrollWidth=' + wide);

  ok('No page errors', errors.length === 0, errors.join(' | '));
  await browser.close();
})();
