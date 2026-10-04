// Tower Siege server storage: the Postgres version (tested with pg-mem, a Postgres in memory)
// and the file version keep what they're given, across a restart.
const path = require('path');
const fs = require('fs');
const { ROOT, OUT } = require('../lib');
(async () => {
  const ok = (name, cond, extra = '') => console.log((cond ? 'PASS ' : 'FAIL ') + name + (extra ? '  ' + extra : ''));
  const server = path.join(ROOT, 'tower-siege/server');
  const { openStore } = require(path.join(server, 'store.js'));
  let pgMem;
  try { pgMem = require(path.join(server, 'node_modules/pg-mem')); } catch {
    ok('pg-mem is installed (cd tower-siege/server && npm install)', false);
    return;
  }
  const db = pgMem.newDb();
  const pg = db.adapters.createPg();
  let s = await openStore({ pg });
  ok('Postgres store opens empty', s.kind === 'postgres' && s.all.size === 0);
  s.set('p:1', { id: '1', name: 'Alice', trophies: 30 });
  s.set('p:2', { id: '2', name: 'Bob', trophies: 0 });
  s.set('p:1', { id: '1', name: 'Alice', trophies: 60 });
  s.set('c:x', { id: 'x', tag: 'FOX' });
  s.del('p:2');
  await s.close();
  s = await openStore({ pg });
  ok('Postgres keeps the latest values after a restart', s.all.get('p:1')?.trophies === 60 && s.all.get('c:x')?.tag === 'FOX' && !s.all.has('p:2') && s.all.size === 2, JSON.stringify([...s.all]));
  await s.close();

  const file = path.join(OUT, 'siege-store-test.json');
  fs.rmSync(file, { force: true });
  let f = await openStore({ file, databaseUrl: '' });
  f.set('p:1', { trophies: 45 });
  f.set('p:9', { trophies: 1 });
  f.del('p:9');
  await f.close();
  f = await openStore({ file, databaseUrl: '' });
  ok('File store keeps values after a restart', f.kind === 'file' && f.all.get('p:1')?.trophies === 45 && !f.all.has('p:9'));
  await f.close();
})();
