'use strict';

// Runs the browser test suites one after another and prints a summary.
//   node tests/run.js            every suite
//   node tests/run.js phase-p    only suites whose name contains "phase-p"
// Some suites load the game over http (service worker, installing), so a small static
// server for the repo runs while the suites do.
const http = require('http');
const fs = require('fs');
const path = require('path');
const { spawn } = require('child_process');
const { ROOT, OUT, PORT } = require('./lib');

const TYPES = {
  '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json',
  '.webmanifest': 'application/manifest+json', '.png': 'image/png', '.svg': 'image/svg+xml',
};

const server = http.createServer((req, res) => {
  let file = path.join(ROOT, decodeURIComponent(req.url.split('?')[0]));
  if (!file.startsWith(ROOT)) { res.writeHead(403); res.end(); return; }
  if (fs.existsSync(file) && fs.statSync(file).isDirectory()) file = path.join(file, 'index.html');
  fs.readFile(file, (err, data) => {
    if (err) { res.writeHead(404); res.end(); return; }
    res.writeHead(200, { 'Content-Type': TYPES[path.extname(file)] || 'application/octet-stream' });
    res.end(data);
  });
});

server.listen(PORT, '127.0.0.1', async () => {
  const filter = process.argv[2] || '';
  const suites = fs.readdirSync(path.join(__dirname, 'suites')).filter(f => f.endsWith('.js') && f.includes(filter)).sort();
  const failed = [];
  let passes = 0, fails = 0;
  for (const suite of suites) {
    const start = Date.now();
    const run = await new Promise(resolve => {
      const child = spawn(process.execPath, [path.join(__dirname, 'suites', suite)], { cwd: ROOT });
      let out = '';
      child.stdout.on('data', d => (out += d));
      child.stderr.on('data', d => (out += d));
      child.on('close', code => resolve({ code, out }));
    });
    const lines = run.out.split('\n');
    const pass = lines.filter(l => l.startsWith('PASS')).length;
    const bad = lines.filter(l => l.startsWith('FAIL'));
    passes += pass;
    fails += bad.length;
    const crashed = run.code !== 0 || pass + bad.length === 0;
    const secs = ((Date.now() - start) / 1000).toFixed(1);
    console.log(`${bad.length || crashed ? '✗' : '✓'} ${suite.padEnd(14)} ${pass} passed${bad.length ? `, ${bad.length} failed` : ''}  (${secs}s)`);
    for (const l of bad) console.log('    ' + l);
    if (crashed) console.log(run.out.split('\n').slice(-15).map(l => '    ' + l).join('\n'));
    if (bad.length || crashed) failed.push(suite);
  }
  server.close();
  console.log(`\n${passes} passed, ${fails} failed across ${suites.length} suites. Screenshots are in ${path.relative(ROOT, OUT)}/`);
  if (failed.length) console.log('Failing suites: ' + failed.join(', '));
  process.exitCode = failed.length ? 1 : 0;
});
