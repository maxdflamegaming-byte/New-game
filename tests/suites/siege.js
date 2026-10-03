// Tower Siege: roads, marching, fights, captures, the enemy, abilities, winning and saving.
const { chromium, ROOT, OUT } = require('../lib');
(async () => {
  const browser = await chromium.launch();
  const errors = [];
  const ok = (name, cond, extra = '') => console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? '  ' + extra : ''));
  const page = await browser.newPage({ viewport: { width: 420, height: 860 } });
  page.on('pageerror', e => errors.push(e.message));
  await page.goto('file://' + ROOT + '/tower-siege/index.html');
  await page.evaluate(() => localStorage.clear());
  await page.reload();
  await page.waitForTimeout(1500);
  await page.screenshot({ path: OUT + '/ts-menu.png' });
  ok('Menu shows with a battle playing behind it', await page.evaluate(() => state === 'menu' && towers.length > 4 && $('menu').classList.contains('show')));

  // Level 1 and the tutorial hand
  await page.click('#play-btn');
  ok('Play starts level 1', await page.evaluate(() => state === 'play' && level === 1 && towers.length === 4));
  ok('Level 1 shows the hint and the hand', await page.evaluate(() => handShown && !$('hint').classList.contains('hidden')));
  await page.waitForTimeout(500);
  await page.screenshot({ path: OUT + '/ts-level1.png' });

  // A real drag from your tower to a gray one builds a road
  const pts = await page.evaluate(() => {
    const me = towers.find(t => t.owner === PLAYER), g = towers.find(t => t.owner === NEUTRAL);
    const a = R3D.towerScreen(me), b = R3D.towerScreen(g);
    return { a, b };
  });
  await page.mouse.move(pts.a.x, pts.a.y);
  await page.mouse.down();
  await page.mouse.move((pts.a.x + pts.b.x) / 2, (pts.a.y + pts.b.y) / 2, { steps: 5 });
  await page.screenshot({ path: OUT + '/ts-drag.png' });
  await page.mouse.move(pts.b.x, pts.b.y, { steps: 5 });
  await page.mouse.up();
  ok('Dragging builds a road', await page.evaluate(() => towers.find(t => t.owner === PLAYER).roads.length === 1));
  ok('The hand goes away after the first road', await page.evaluate(() => !handShown && $('hint').classList.contains('hidden')));
  await page.waitForTimeout(1200);
  ok('Soldiers march along the road', await page.evaluate(() => units.some(u => u.owner === PLAYER)));
  await page.screenshot({ path: OUT + '/ts-march.png' });

  // Swipe to cut
  const mid = await page.evaluate(() => {
    const me = towers.find(t => t.owner === PLAYER), b = me.roads[0].to;
    return P((me.x + b.x) / 2, (me.y + b.y) / 2, 0);
  });
  await page.mouse.move(mid.x - 60, mid.y - 10);
  await page.mouse.down();
  await page.mouse.move(mid.x + 60, mid.y + 10, { steps: 6 });
  await page.mouse.up();
  ok('Swiping across a road cuts it', await page.evaluate(() => towers.find(t => t.owner === PLAYER).roads.length === 0));

  // Rules, checked directly with the simulation
  const rules = await page.evaluate(() => {
    const r = {};
    for (const a of aiSides) a.timer = 1e9;
    units = [];
    const [me, g1, g2, foe] = towers;
    me.units = 5; me.roads = []; g1.roads = []; g2.roads = [];
    r.oneRoadSmall = tryLink(me, g1, PLAYER) === true && tryLink(me, g2, PLAYER) === 'full';
    me.units = 12;
    r.twoRoads = tryLink(me, g2, PLAYER) === true;
    r.notYours = tryLink(g1, me, PLAYER) === 'not yours';
    r.noDup = tryLink(me, g1, PLAYER) === 'exists';
    // Capture: a gray tower with 2 soldiers falls to the third arriving soldier
    me.roads = [];
    g1.units = 2; g1.owner = NEUTRAL;
    for (let i = 0; i < 3; i++) arrive({ owner: PLAYER, to: g1 });
    r.capture = g1.owner === PLAYER && Math.abs(g1.units - 1) < 1e-9;
    // Reinforce your own
    arrive({ owner: PLAYER, to: g1 });
    r.reinforce = Math.abs(g1.units - 2) < 1e-9;
    // Forts take half damage
    g2.type = 'fort'; g2.owner = NEUTRAL; g2.units = 2;
    for (let i = 0; i < 4; i++) arrive({ owner: PLAYER, to: g2 });
    r.fortHolds = g2.owner === NEUTRAL;
    arrive({ owner: PLAYER, to: g2 });
    r.fortFalls = g2.owner === PLAYER;
    g2.type = 'barracks';
    // Soldiers from two armies cancel out when they meet
    units = [];
    spawnUnit(me, foe); spawnUnit(foe, me);
    for (let i = 0; i < 400 && units.length; i++) { update(0.02); }
    r.meetAndFight = units.length === 0 && foe.owner === 2 && me.owner === PLAYER;
    // Rocks block roads
    rocks = [{ x: (me.x + foe.x) / 2, y: (me.y + foe.y) / 2, r: 30 }];
    me.units = 40; me.roads = [];
    r.rockBlocks = tryLink(me, foe, PLAYER) === 'blocked';
    rocks = [];
    // Levels: 1 road under 10, 2 from 10, 3 from 30 (and 60)
    const lv = u => maxRoads({ units: u });
    r.roadCaps = lv(9) === 1 && lv(10) === 2 && lv(30) === 3 && lv(80) === 3;
    return r;
  });
  for (const [k, v] of Object.entries(rules)) ok('Rule: ' + k, v);

  // Watchtowers shoot passing enemies; tanks take 3 hits
  const watch = await page.evaluate(() => {
    startLevel(1);
    for (const a of aiSides) a.timer = 1e9;
    const [me, g1, , foe] = towers;
    g1.type = 'watch'; g1.owner = 2; g1.units = 5; g1.reload = 0;
    units = [];
    const u = { id: 1, from: me, to: foe, owner: PLAYER, power: 1, d: 0, lane: 0, x: g1.x + 50, y: g1.y };
    const tank = { id: 2, from: me, to: foe, owner: PLAYER, power: 3, d: 0, lane: 0, x: g1.x + 80, y: g1.y };
    units.push(u, tank);
    updateWatch(g1, 0.016);
    const soldierDown = u.dead === true && shells.length === 1;
    g1.reload = 0; updateWatch(g1, 0.016);
    return soldierDown && tank.power === 2 && !tank.dead;
  });
  ok('Watchtowers shoot enemies in range (tanks take 3 hits)', watch);

  // Tank factories send tanks worth 3 soldiers, and a tank beats a soldier
  const tanks = await page.evaluate(() => {
    startLevel(1);
    for (const a of aiSides) a.timer = 1e9;
    const [me, g1, g2, foe] = towers;
    me.type = 'factory'; me.units = 20; me.roads = [];
    tryLink(me, g1, PLAYER);
    update(0.02);
    const sent = units.find(u => u.owner === PLAYER);
    const ok1 = sent && sent.power === 3 && Math.abs(me.units - 17) < 0.2;
    units = [];
    spawnUnit(me, foe, 3); spawnUnit(foe, me, 1);
    me.roads = []; foe.roads = [];
    for (let i = 0; i < 400 && units.length === 2; i++) update(0.02);
    const left = units.filter(u => u.owner === PLAYER);
    return ok1 && left.length === 1 && left[0].power === 2;
  });
  ok('Tank factories send tanks, and tanks beat soldiers', tanks);

  // The enemy attacks on its own
  const ai = await page.evaluate(() => {
    startLevel(4);
    const foe = towers.find(t => t.owner === 2);
    foe.units = 40;
    for (let i = 0; i < 20; i++) aiThink(2, levelData(4).ai);
    return towers.some(t => t.owner === 2 && t.roads.length > 0);
  });
  ok('The enemy builds roads to attack', ai);

  // Airstrike
  await page.evaluate(() => { startLevel(3); });
  ok('Airstrike button appears from level 3', await page.isVisible('#ab-strike'));
  const strike = await page.evaluate(() => {
    for (const a of aiSides) a.timer = 1e9;
    const foe = towers.find(t => t.owner === 2);
    foe.units = 30;
    useAbility('strike');
    const armedOk = armed === 'strike';
    dropStrike(foe);
    for (let i = 0; i < 100; i++) update(0.02);
    return { armedOk, units: foe.units, left: charges.strike };
  });
  ok('Airstrike blows up half a building', strike.armedOk && strike.units < 18 && strike.left === 0, JSON.stringify(strike));

  // Winning pays coins, saves stars and unlocks the next level
  await page.evaluate(() => { startLevel(1); for (const t of towers) if (t.owner === 2) { t.owner = PLAYER; } units = []; update(0.016); });
  await page.waitForTimeout(1400);
  ok('Taking every enemy tower wins', await page.isVisible('#win'));
  await page.waitForTimeout(900);
  await page.screenshot({ path: OUT + '/ts-win.png' });
  const saved = await page.evaluate(() => JSON.parse(localStorage.getItem('tower-siege-save')));
  ok('A win is saved', saved.level === 2 && saved.stars[1] === 3 && saved.coins > 0, JSON.stringify(saved));
  await page.click('#next-btn');
  ok('Next level starts level 2', await page.evaluate(() => state === 'play' && level === 2));

  // Losing
  await page.evaluate(() => { for (const t of towers) if (t.owner === PLAYER) t.owner = 2; units = []; update(0.016); });
  await page.waitForTimeout(1400);
  ok('Losing every tower shows Defeat', await page.isVisible('#lose'));
  await page.screenshot({ path: OUT + '/ts-lose.png' });

  // Upgrades
  await page.evaluate(() => { save.coins = 500; writeSave(); });
  await page.click('#lose-shop-btn');
  await page.click('#buy-drill');
  const up = await page.evaluate(() => ({ lv: save.up.drill, coins: save.coins }));
  ok('Buying an upgrade spends coins', up.lv === 1 && up.coins === 440, JSON.stringify(up));
  await page.screenshot({ path: OUT + '/ts-shop.png' });
  await page.click('#shop .back-btn');
  ok('Back from the shop returns to Defeat', await page.isVisible('#lose'));

  // Level select
  await page.click('#lose .menu-btn2');
  await page.click('#levels-btn');
  const grid = await page.evaluate(() => [...document.querySelectorAll('#level-grid button')].map(b => b.disabled));
  ok('Level select unlocks levels you reached', grid.length === 60 && !grid[0] && !grid[1] && grid[2]);
  await page.screenshot({ path: OUT + '/ts-levels.png' });

  // Every generated level is valid and reachable
  const gen = await page.evaluate(() => {
    const bad = [];
    for (let n = 1; n <= MAX_LEVEL; n++) {
      const d = levelData(n);
      const owners = d.towers.map(t => t[2]);
      if (!owners.includes(1) || !owners.includes(2)) bad.push(n + ':sides');
      if (!connected(d.towers, d.rocks)) bad.push(n + ':cut off');
      for (const t of d.towers) if (t[0] < 40 || t[0] > FW - 40 || t[1] < 40 || t[1] > FH - 40) bad.push(n + ':edge');
    }
    return bad;
  });
  ok('All levels have both armies and no cut-off towers', gen.length === 0, gen.join(' '));

  // A full AI-vs-AI game ends (the AI can actually take towers)
  const full = await page.evaluate(() => {
    startLevel(10);
    aiSides.push({ side: PLAYER, timer: 0.5, cfg: { think: 1.2, margin: 2, bold: 0.6 } });
    let t = 0;
    while (state === 'play' && t < 600) { update(0.05); t += 0.05; }
    return { state, t: Math.round(t), captured: towers.filter(x => x.owner !== NEUTRAL).length };
  });
  ok('An AI-vs-AI battle on level 10 takes towers', full.captured > 4, JSON.stringify(full));

  // Wide screens turn the field on its side
  const land = await browser.newPage({ viewport: { width: 1100, height: 650 } });
  land.on('pageerror', e => errors.push(e.message));
  await land.goto('file://' + ROOT + '/tower-siege/index.html');
  await land.evaluate(() => { save.level = 20; startLevel(18); });
  await land.waitForTimeout(800);
  const l = await land.evaluate(() => {
    const me = towers.find(t => t.owner === PLAYER), foe = towers.find(t => t.owner === 2);
    return { landscape, left: me.x < foe.x, inside: towers.every(t => { const s = R3D.towerScreen(t); return s.x > 0 && s.x < W && s.topY > 40 && s.y < H - 60; }) };
  });
  ok('Landscape puts your base on the left and fits the screen', l.landscape && l.left && l.inside, JSON.stringify(l));
  await land.evaluate(() => {
    for (const a of aiSides) a.cfg = { ...a.cfg, think: 0.6 };
    aiSides.push({ side: PLAYER, timer: 0.2, cfg: { think: 0.8, margin: 2, bold: 0.6 } });
  });
  await land.waitForTimeout(6000);
  await land.screenshot({ path: OUT + '/ts-landscape.png' });

  ok('No page errors', errors.length === 0, errors.join(' | '));
  await browser.close();
})();
