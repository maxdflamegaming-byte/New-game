'use strict';

// Tiny synthesized sound effects, so the games need no audio files.
const Sfx = (() => {
  let ac = null;
  let muted = false;
  try { muted = localStorage.getItem('sfx-muted') === '1'; } catch { /* storage unavailable */ }
  const lastPlayed = {};

  function audio() {
    if (!ac) {
      const AC = window.AudioContext || window.webkitAudioContext;
      if (!AC) return null;
      ac = new AC();
    }
    if (ac.state === 'suspended') ac.resume();
    return ac;
  }

  function tone({ freq = 440, to = freq, dur = 0.12, type = 'sine', vol = 0.1, delay = 0 }) {
    const a = audio();
    if (!a) return;
    const t = a.currentTime + delay;
    const o = a.createOscillator(), g = a.createGain();
    o.type = type;
    o.frequency.setValueAtTime(freq, t);
    o.frequency.exponentialRampToValueAtTime(Math.max(1, to), t + dur);
    g.gain.setValueAtTime(vol, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g).connect(a.destination);
    o.start(t);
    o.stop(t + dur + 0.02);
  }

  function noise({ dur = 0.2, vol = 0.1, delay = 0 }) {
    const a = audio();
    if (!a) return;
    const t = a.currentTime + delay;
    const buf = a.createBuffer(1, Math.floor(a.sampleRate * dur), a.sampleRate);
    const data = buf.getChannelData(0);
    for (let i = 0; i < data.length; i++) data[i] = (Math.random() * 2 - 1) * (1 - i / data.length);
    const src = a.createBufferSource(), g = a.createGain();
    src.buffer = buf;
    g.gain.setValueAtTime(vol, t);
    src.connect(g).connect(a.destination);
    src.start(t);
  }

  const arp = (notes, step, opts) => notes.forEach((f, i) => tone({ freq: f, dur: step * 1.6, delay: i * step, ...opts }));

  const SOUNDS = {
    shoot: { gap: 0.06, fn: () => tone({ freq: 900, to: 500, dur: 0.05, type: 'square', vol: 0.015 }) },
    hit: { gap: 0.04, fn: () => tone({ freq: 220, to: 120, dur: 0.05, type: 'triangle', vol: 0.05 }) },
    pop: { gap: 0.03, fn: () => tone({ freq: rand(500, 700), to: 1300, dur: 0.08, vol: 0.05 }) },
    gem: { gap: 0.04, fn: () => tone({ freq: rand(1100, 1400), to: 1800, dur: 0.05, vol: 0.035 }) },
    levelup: { gap: 0.3, fn: () => arp([523, 659, 784, 1047], 0.07, { type: 'triangle', vol: 0.08 }) },
    hurt: { gap: 0.2, fn: () => tone({ freq: 240, to: 70, dur: 0.22, type: 'sawtooth', vol: 0.08 }) },
    death: { gap: 0.5, fn: () => { tone({ freq: 400, to: 40, dur: 0.7, type: 'sawtooth', vol: 0.1 }); noise({ dur: 0.5, vol: 0.08 }); } },
    zap: { gap: 0.08, fn: () => { noise({ dur: 0.12, vol: 0.06 }); tone({ freq: 1600, to: 300, dur: 0.1, type: 'square', vol: 0.025 }); } },
    boom: { gap: 0.2, fn: () => { noise({ dur: 0.6, vol: 0.18 }); tone({ freq: 120, to: 30, dur: 0.5, vol: 0.15 }); } },
    pickup: { gap: 0.1, fn: () => arp([880, 1320], 0.06, { vol: 0.07 }) },
    chest: { gap: 0.3, fn: () => arp([659, 784, 988, 1319, 1568], 0.06, { type: 'triangle', vol: 0.08 }) },
    warn: { gap: 1, fn: () => arp([110, 98], 0.18, { type: 'square', vol: 0.06 }) },
    capture: { gap: 0.1, fn: () => arp([523, 784], 0.06, { type: 'triangle', vol: 0.08 }) },
    cut: { gap: 0.1, fn: () => { noise({ dur: 0.15, vol: 0.1 }); arp([784, 1175], 0.05, { type: 'square', vol: 0.04 }); } },
    speed: { gap: 0.2, fn: () => { noise({ dur: 0.25, vol: 0.06 }); tone({ freq: 300, to: 1400, dur: 0.25, type: 'sawtooth', vol: 0.04 }); } },
    shield: { gap: 0.2, fn: () => arp([392, 587, 784], 0.07, { type: 'sine', vol: 0.09 }) },
    freeze: { gap: 0.3, fn: () => arp([2093, 1760, 1568, 1319], 0.05, { type: 'sine', vol: 0.05 }) },
    beep: { gap: 0.3, fn: () => tone({ freq: 660, dur: 0.12, type: 'square', vol: 0.06 }) },
    go: { gap: 0.3, fn: () => arp([784, 1175], 0.07, { type: 'square', vol: 0.07 }) },
    coin: { gap: 0.05, fn: () => arp([988, 1319], 0.05, { type: 'square', vol: 0.05 }) },
    trophy: { gap: 0.5, fn: () => arp([784, 988, 1175, 1568], 0.08, { type: 'triangle', vol: 0.09 }) },
    win: { gap: 1, fn: () => arp([523, 659, 784, 1047, 1319, 1568], 0.09, { type: 'triangle', vol: 0.09 }) },
  };

  function rand(a, b) { return a + Math.random() * (b - a); }

  return {
    play(name) {
      const s = SOUNDS[name];
      if (muted || !s) return;
      const now = performance.now() / 1000;
      if (now - (lastPlayed[name] || 0) < s.gap) return;
      lastPlayed[name] = now;
      try { s.fn(); } catch { /* audio not available */ }
    },
    toggle() {
      muted = !muted;
      try { localStorage.setItem('sfx-muted', muted ? '1' : '0'); } catch { /* storage unavailable */ }
      if (!muted) audio();
      return muted;
    },
    get muted() { return muted; },
    unlock() { if (!muted) audio(); },
  };
})();
