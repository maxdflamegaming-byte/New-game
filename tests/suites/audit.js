// Plays bots-only games on every mode and map and checks the board stays consistent
// (land counts, trails, walls, players on the map, no runaway effect lists).
const { chromium, ROOT } = require('../lib');
(async () => {
  const b = await chromium.launch(); const page = await b.newPage({ viewport: { width: 1100, height: 760 } }); const errs = [];
  page.on('pageerror', e => errs.push(e.message)); page.on('console', m => { if (m.type() === 'error' && !m.text().startsWith('Failed to load resource')) errs.push('console: ' + m.text()); });
  await page.goto('file://' + ROOT + '/color-claim/index.html');
  const r = await page.evaluate(() => {
    localStorage.setItem('color-claim-howto-seen', '1');
    const issues = {}; const note = (k, v) => { issues[k] = (issues[k] || 0) + 1; if (!issues[k + '_ex']) issues[k + '_ex'] = v; };
    const modes = ['classic', 'timed', 'marathon', 'team', 'duo', 'cup', 'boss', 'puzzle', 'custom', 'weekly', 'daily'];
    const maps = ['square', 'round', 'pillars', 'maze', 'islands', 'saws', 'storm', 'belts', 'portals'];
    let games = 0, frames = 0, ends = {};
    for (const mode of modes) for (const map of (['daily', 'weekly', 'puzzle', 'cup'].includes(mode) ? ['square'] : maps)) {
      myMode = mode; myMap = map; startGame(); countdown = 0; games++;
      for (const p of players) if (p && !p.isBoss) { p.isBot = true; if (!p.persona) givePersonality(p, 'wildcard'); }
      const endReal = endGame, endD = endDuo;
      let ended = null;
      endGame = (w, reason) => { ended = ended || ('game:' + (w ? 'won' : 'lost')); };
      endDuo = () => { ended = ended || 'duo'; };
      for (let i = 0; i < 100 * 60 && !ended; i++) {
        state = state === 'won' ? 'won' : 'play';
        update(1 / 60); frames++;
        if (!me.alive && !ended && state === 'play' && !gameMode.duo && !gameMode.boss) { me.alive = true; spawn(me); }
        if (i % 30) continue;
        // invariants
        const cnt = new Int32Array(64);
        for (let k = 0; k < N * N; k++) { if (owner[k]) cnt[owner[k]]++; if (wall[k] && (owner[k] || trail[k])) note('owned/trail wall cell', mode + '/' + map); if (trail[k] && (!players[trail[k]] || !players[trail[k]].alive)) note('orphan trail', mode + '/' + map); }
        for (const p of players) {
          if (!p) continue;
          if (cnt[p.id] !== counts[p.id]) note('counts mismatch', `${mode}/${map} ${p.name} ${cnt[p.id]} vs ${counts[p.id]}`);
          if (!p.alive) continue;
          if (!Number.isFinite(p.x) || !Number.isFinite(p.y)) note('NaN pos', mode + '/' + map + ' ' + p.name);
          if (p.x < 0 || p.y < 0 || p.x > N || p.y > N) note('out of map', mode + '/' + map);
          if (wall[p.cy * N + p.cx]) note('in wall', `${mode}/${map} ${p.name}`);
          for (const t of p.trail) if (trail[t] !== p.id && trail[t] !== 0) note('trail list mismatch', mode + '/' + map);
          if (counts[p.id] === 0) note('alive with no land', `${mode}/${map} ${p.name} ${p.mode}`);
        }
        let played = 0; for (let k = 0; k < N * N; k++) if (!wall[k]) played++;
        if (played !== playCells) note('playCells wrong', `${mode}/${map} ${played} vs ${playCells}`);
        if (particles.length > 3000 || fades.length > 200 || flashes.length > 200 || floats.length > 200 || feed.length > 50) note('array growth', `${mode} p${particles.length} f${fades.length} fl${flashes.length} fe${feed.length}`);
      }
      endGame = endReal; endDuo = endD;
      ends[ended || 'none'] = (ends[ended || 'none'] || 0) + 1;
      state = 'menu'; me = null; gameCounter++;
    }
    return { games, frames, ends, issues };
  });
  const ok = (name, cond, extra = '') => console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? '  ' + extra : ''));
  const found = Object.keys(r.issues).filter(k => !k.endsWith('_ex'));
  ok(`${r.games} bot games (${r.frames} frames) keep the board consistent`, found.length === 0, found.map(k => `${k} x${r.issues[k]} (${r.issues[k + '_ex']})`).join('; '));
  ok('Every mode and map was played', r.games === 67, `${r.games} games`);
  ok('No page errors', errs.length === 0, errs.slice(0, 5).join(' | '));
  await b.close();
})();
