'use strict';

// Background music made in code: a looping four-chord progression with bass,
// an arpeggio and soft hi-hats. Respects the sound mute (Sfx.muted).
const Music = (() => {
  let ac = null, master = null, hatBuf = null, timer = null;
  let nextTime = 0, step = 0, playing = false;
  let enabled = true;
  try { enabled = localStorage.getItem('music-on') !== '0'; } catch { /* storage unavailable */ }

  const BPM = 112;
  const STEP = 60 / BPM / 2; // eighth notes
  // C major, A minor, F major, G major (MIDI note numbers)
  const CHORDS = [[48, 55, 60, 64], [45, 52, 57, 60], [41, 48, 53, 57], [43, 50, 55, 59]];
  const ARP = [0, 1, 2, 3, 2, 1, 2, 3];
  const freq = n => 440 * Math.pow(2, (n - 69) / 12);

  function note(f, t, dur, type, vol) {
    const o = ac.createOscillator(), g = ac.createGain();
    o.type = type;
    o.frequency.setValueAtTime(f, t);
    g.gain.setValueAtTime(0.0001, t);
    g.gain.exponentialRampToValueAtTime(vol, t + 0.01);
    g.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    o.connect(g).connect(master);
    o.start(t);
    o.stop(t + dur + 0.02);
  }

  function hat(t) {
    const src = ac.createBufferSource(), g = ac.createGain();
    src.buffer = hatBuf;
    g.gain.setValueAtTime(0.02, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.05);
    src.connect(g).connect(master);
    src.start(t);
  }

  function schedule() {
    while (nextTime < ac.currentTime + 0.15) {
      const chord = CHORDS[Math.floor(step / 16) % CHORDS.length]; // two bars per chord
      const s = step % 8;
      if (s === 0 || s === 4) note(freq(chord[0] - 12), nextTime, STEP * 3.5, 'triangle', 0.12);
      note(freq(chord[ARP[s]] + 12), nextTime, STEP * 0.9, 'square', 0.022);
      if (s % 2 === 1) hat(nextTime);
      nextTime += STEP;
      step++;
    }
  }

  function start() {
    if (playing || !enabled || (typeof Sfx !== 'undefined' && Sfx.muted)) return;
    try {
      if (!ac) {
        const AC = window.AudioContext || window.webkitAudioContext;
        if (!AC) return;
        ac = new AC();
        hatBuf = ac.createBuffer(1, Math.floor(ac.sampleRate * 0.05), ac.sampleRate);
        const d = hatBuf.getChannelData(0);
        for (let i = 0; i < d.length; i++) d[i] = Math.random() * 2 - 1;
      }
      if (ac.state === 'suspended') ac.resume();
      master = ac.createGain();
      master.gain.setValueAtTime(0.0001, ac.currentTime);
      master.gain.exponentialRampToValueAtTime(0.5, ac.currentTime + 1);
      master.connect(ac.destination);
      nextTime = ac.currentTime + 0.05;
      step = 0;
      timer = setInterval(schedule, 40);
      playing = true;
    } catch { /* audio not available */ }
  }

  function stop() {
    if (!playing) return;
    clearInterval(timer);
    playing = false;
    const m = master;
    try {
      m.gain.cancelScheduledValues(ac.currentTime);
      m.gain.setValueAtTime(m.gain.value, ac.currentTime);
      m.gain.exponentialRampToValueAtTime(0.0001, ac.currentTime + 0.4);
      setTimeout(() => m.disconnect(), 500);
    } catch { /* audio not available */ }
  }

  return {
    start,
    stop,
    get enabled() { return enabled; },
    get playing() { return playing; },
    toggle() {
      enabled = !enabled;
      try { localStorage.setItem('music-on', enabled ? '1' : '0'); } catch { /* storage unavailable */ }
      return enabled;
    },
  };
})();
