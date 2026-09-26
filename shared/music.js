'use strict';

// Background music made in code: a looping four-chord progression with bass,
// an arpeggio and soft hi-hats. There are a few tracks to pick from (Music.track).
// Respects the sound mute (Sfx.muted).
const Music = (() => {
  let ac = null, master = null, hatBuf = null, timer = null;
  let nextTime = 0, step = 0, playing = false;
  let enabled = true;
  try { enabled = localStorage.getItem('music-on') !== '0'; } catch { /* storage unavailable */ }

  // Chords are MIDI note numbers; each lasts two bars of eighth notes
  const TRACKS = {
    // C major, A minor, F major, G major: bright and bouncy
    sunny: {
      bpm: 112, chords: [[48, 55, 60, 64], [45, 52, 57, 60], [41, 48, 53, 57], [43, 50, 55, 59]],
      arp: [0, 1, 2, 3, 2, 1, 2, 3], bassEvery: 4, bass: ['triangle', 0.12], lead: ['square', 0.022], hatEvery: 2,
    },
    // A minor 7, F major 7, D minor 7, E major: slower and dreamy
    night: {
      bpm: 90, chords: [[45, 52, 55, 60], [41, 48, 52, 57], [38, 45, 48, 53], [40, 47, 52, 56]],
      arp: [0, 2, 1, 3, 2, 1, 3, 2], bassEvery: 8, bass: ['sine', 0.16], lead: ['triangle', 0.045], hatEvery: 4,
    },
    // D minor, B flat, C, A: fast and tense, with a kick drum
    boss: {
      bpm: 142, chords: [[50, 57, 62, 65], [46, 53, 58, 62], [48, 55, 60, 64], [45, 52, 57, 61]],
      arp: [0, 3, 1, 3, 2, 3, 1, 3], bassEvery: 1, bass: ['sawtooth', 0.045], lead: ['square', 0.02], hatEvery: 1, kick: true,
    },
  };
  let track = 'sunny';
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

  function kick(t) {
    const o = ac.createOscillator(), g = ac.createGain();
    o.frequency.setValueAtTime(140, t);
    o.frequency.exponentialRampToValueAtTime(40, t + 0.12);
    g.gain.setValueAtTime(0.25, t);
    g.gain.exponentialRampToValueAtTime(0.0001, t + 0.15);
    o.connect(g).connect(master);
    o.start(t);
    o.stop(t + 0.17);
  }

  function schedule() {
    const T = TRACKS[track] || TRACKS.sunny, STEP = 60 / T.bpm / 2; // eighth notes
    while (nextTime < ac.currentTime + 0.15) {
      const chord = T.chords[Math.floor(step / 16) % T.chords.length]; // two bars per chord
      const s = step % 8;
      if (s % T.bassEvery === 0) note(freq(chord[0] - 12), nextTime, STEP * Math.min(3.5, T.bassEvery * 0.9), T.bass[0], T.bass[1]);
      note(freq(chord[T.arp[s]] + 12), nextTime, STEP * 0.9, T.lead[0], T.lead[1]);
      if ((s + 1) % T.hatEvery === 0) hat(nextTime);
      if (T.kick && s % 4 === 0) kick(nextTime);
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
    get track() { return track; },
    // Switching tracks takes effect on the next note, so it can change mid-song
    set track(id) { if (TRACKS[id]) track = id; },
    tracks: Object.keys(TRACKS),
    get playing() { return playing; },
    toggle() {
      enabled = !enabled;
      try { localStorage.setItem('music-on', enabled ? '1' : '0'); } catch { /* storage unavailable */ }
      return enabled;
    },
  };
})();
