'use strict';

// Where the server keeps players and clans: a key → JSON value store, all loaded into memory
// at start and written back as things change.
//   DATABASE_URL set: a Postgres database (for example a free Neon database). Use this on hosts
//                     whose disk is wiped on restart, like Render's free plan.
//   otherwise:        a JSON file (DATA_FILE, default data.json next to this file).
const fs = require('fs');
const path = require('path');

async function openStore({ databaseUrl = process.env.DATABASE_URL, file = process.env.DATA_FILE, pg = null } = {}) {
  if (databaseUrl || pg) return openPostgres(databaseUrl, pg);
  return openFile(file || path.join(__dirname, 'data.json'));
}

async function openFile(file) {
  const all = new Map();
  try {
    const data = JSON.parse(fs.readFileSync(file, 'utf8'));
    for (const [k, v] of Object.entries(data)) all.set(k, v);
  } catch { /* no file yet */ }
  let timer = null;
  const flush = () => {
    timer = null;
    const tmp = file + '.tmp';
    fs.writeFileSync(tmp, JSON.stringify(Object.fromEntries(all)));
    fs.renameSync(tmp, file);
  };
  const later = () => { if (!timer) timer = setTimeout(flush, 1000); };
  return {
    kind: 'file',
    all,
    set(k, v) { all.set(k, v); later(); },
    del(k) { all.delete(k); later(); },
    async close() { if (timer) { clearTimeout(timer); flush(); } },
  };
}

async function openPostgres(url, pgModule) {
  const { Pool } = pgModule || require('pg');
  const pool = pgModule ? new Pool() : new Pool({ connectionString: url, ssl: /localhost|127\.0\.0\.1/.test(url) ? false : { rejectUnauthorized: false }, max: 3 });
  // Make the table the first time (checked by hand, which also works with the pg-mem test database)
  const exists = (await pool.query("select 1 from information_schema.tables where table_name = 'tower_siege'")).rows.length > 0;
  if (!exists) await pool.query('create table tower_siege (k text primary key, v jsonb not null)');
  const all = new Map();
  for (const row of (await pool.query('select k, v from tower_siege')).rows) all.set(row.k, row.v);
  // Writes go out in order, a key at a time; only the latest value of a key matters
  const dirty = new Map();
  let running = null;
  const pump = async () => {
    while (dirty.size) {
      const [k, v] = dirty.entries().next().value;
      dirty.delete(k);
      try {
        if (v === undefined) await pool.query('delete from tower_siege where k = $1', [k]);
        else await pool.query('insert into tower_siege (k, v) values ($1, $2) on conflict (k) do update set v = excluded.v', [k, JSON.stringify(v)]);
      } catch (err) {
        console.error('[store] write failed, will retry:', err.message);
        if (!dirty.has(k)) dirty.set(k, v);
        await new Promise(r => setTimeout(r, 2000));
      }
    }
    running = null;
  };
  const write = (k, v) => { dirty.set(k, v); if (!running) running = pump(); };
  return {
    kind: 'postgres',
    all,
    set(k, v) { all.set(k, v); write(k, v); },
    del(k) { all.delete(k); write(k, undefined); },
    async close() { if (running) await running; await pool.end(); },
  };
}

module.exports = { openStore };
