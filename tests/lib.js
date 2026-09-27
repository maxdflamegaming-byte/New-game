'use strict';

// Shared setup for the test suites: where the game files are, where screenshots go,
// and Playwright (a local install if there is one, otherwise the global one).
const path = require('path');
const fs = require('fs');
const { execSync } = require('child_process');

const ROOT = path.resolve(__dirname, '..');
const OUT = process.env.TEST_OUT || path.join(__dirname, 'output');
fs.mkdirSync(OUT, { recursive: true });

function playwright() {
  try {
    return require('playwright');
  } catch {
    return require(path.join(execSync('npm root -g').toString().trim(), 'playwright'));
  }
}

module.exports = { ROOT, OUT, PORT: 8765, ...playwright() };
