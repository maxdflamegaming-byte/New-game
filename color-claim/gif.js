'use strict';

// A small animated GIF encoder (GIF89a): one 256-colour palette shared by every frame,
// LZW-compressed pixels, and a loop-forever flag. Used to save instant replays.

class ByteWriter {
  constructor() {
    this.buf = new Uint8Array(1 << 16);
    this.len = 0;
  }
  byte(b) {
    if (this.len === this.buf.length) {
      const bigger = new Uint8Array(this.buf.length * 2);
      bigger.set(this.buf);
      this.buf = bigger;
    }
    this.buf[this.len++] = b;
  }
  word(w) {
    this.byte(w & 255);
    this.byte((w >> 8) & 255);
  }
  text(s) {
    for (let i = 0; i < s.length; i++) this.byte(s.charCodeAt(i));
  }
  bytes() {
    return this.buf.slice(0, this.len);
  }
}

class GifWriter {
  // palette: 256 [r, g, b] colours
  constructor(width, height, palette) {
    this.w = width;
    this.h = height;
    const out = (this.out = new ByteWriter());
    out.text('GIF89a');
    out.word(width);
    out.word(height);
    out.byte(0xf7); // global colour table of 256 colours
    out.byte(0); // background colour
    out.byte(0); // square pixels
    for (let i = 0; i < 256; i++) {
      const [r, g, b] = palette[i] || [0, 0, 0];
      out.byte(r);
      out.byte(g);
      out.byte(b);
    }
    // Loop forever
    out.byte(0x21);
    out.byte(0xff);
    out.byte(11);
    out.text('NETSCAPE2.0');
    out.byte(3);
    out.byte(1);
    out.word(0);
    out.byte(0);
  }

  // indices: one palette index per pixel; delay in hundredths of a second
  addFrame(indices, delay) {
    const out = this.out;
    out.byte(0x21); // graphic control: how long to show this frame
    out.byte(0xf9);
    out.byte(4);
    out.byte(0x04); // leave the frame in place, no transparency
    out.word(delay);
    out.byte(0);
    out.byte(0);
    out.byte(0x2c); // image covering the whole canvas
    out.word(0);
    out.word(0);
    out.word(this.w);
    out.word(this.h);
    out.byte(0);
    out.byte(8); // LZW minimum code size
    const data = lzwEncode(indices);
    for (let p = 0; p < data.length; p += 255) {
      const n = Math.min(255, data.length - p);
      out.byte(n);
      for (let k = 0; k < n; k++) out.byte(data[p + k]);
    }
    out.byte(0);
  }

  finish() {
    this.out.byte(0x3b);
    return this.out.bytes();
  }
}

// Variable-width LZW for 8-bit indices, as GIF expects it
function lzwEncode(indices) {
  const CLEAR = 256, EOI = 257;
  const out = new ByteWriter();
  let codeSize = 9, next = EOI + 1;
  let dict = new Map();
  let cur = 0, bits = 0;
  const emit = code => {
    cur |= code << bits;
    bits += codeSize;
    while (bits >= 8) {
      out.byte(cur & 255);
      cur >>= 8;
      bits -= 8;
    }
  };
  emit(CLEAR);
  let prefix = indices[0];
  for (let i = 1; i < indices.length; i++) {
    const k = indices[i];
    const key = (prefix << 8) | k;
    const hit = dict.get(key);
    if (hit !== undefined) {
      prefix = hit;
      continue;
    }
    emit(prefix);
    if (next === 4096) {
      emit(CLEAR);
      next = EOI + 1;
      codeSize = 9;
      dict = new Map();
    } else {
      if (next >= 1 << codeSize) codeSize++;
      dict.set(key, next++);
    }
    prefix = k;
  }
  emit(prefix);
  emit(EOI);
  if (bits > 0) out.byte(cur & 255);
  return out.bytes();
}

// Picks a palette for a set of RGBA frames: the 256 most common colours (the game is
// mostly flat colours), then maps every pixel to its nearest palette colour.
class GifPalette {
  constructor() {
    this.count = new Uint32Array(32768);
    this.sum = new Float64Array(32768 * 3);
  }
  static bin(r, g, b) {
    return ((r >> 3) << 10) | ((g >> 3) << 5) | (b >> 3);
  }
  sample(rgba) {
    for (let i = 0; i < rgba.length; i += 4) {
      const b = GifPalette.bin(rgba[i], rgba[i + 1], rgba[i + 2]);
      this.count[b]++;
      this.sum[b * 3] += rgba[i];
      this.sum[b * 3 + 1] += rgba[i + 1];
      this.sum[b * 3 + 2] += rgba[i + 2];
    }
  }
  build() {
    const bins = [];
    for (let b = 0; b < 32768; b++) if (this.count[b]) bins.push(b);
    bins.sort((a, b) => this.count[b] - this.count[a]);
    this.colors = bins.slice(0, 256).map(b => {
      const n = this.count[b];
      return [0, 1, 2].map(c => Math.round(this.sum[b * 3 + c] / n));
    });
    while (this.colors.length < 256) this.colors.push([0, 0, 0]);
    this.lookup = new Int16Array(32768).fill(-1);
    return this.colors;
  }
  index(rgba) {
    const px = new Uint8Array(rgba.length / 4);
    for (let i = 0, p = 0; i < rgba.length; i += 4, p++) {
      const r = rgba[i], g = rgba[i + 1], b = rgba[i + 2];
      const bin = GifPalette.bin(r, g, b);
      let best = this.lookup[bin];
      if (best < 0) {
        let bestD = Infinity;
        for (let c = 0; c < 256; c++) {
          const [pr, pg, pb] = this.colors[c];
          const d = (pr - r) ** 2 * 2 + (pg - g) ** 2 * 3 + (pb - b) ** 2;
          if (d < bestD) { bestD = d; best = c; }
        }
        this.lookup[bin] = best;
      }
      px[p] = best;
    }
    return px;
  }
}
