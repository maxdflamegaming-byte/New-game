'use strict';

// The 3D look of Tower Siege, drawn with three.js (vendor/three.min.js): bright cartoon
// colors, a high camera, stacked towers in army colors and chibi soldiers.
// Every model is built in code from simple shapes, so there are no model or texture files.
// game.js runs the battle; this file only draws it. If WebGL isn't available, R3D.ok stays
// false and the game falls back to its flat 2D drawing.
const R3D = (() => {
  const T = window.THREE;
  const api = { ok: false };
  if (!T) return api;

  const TAU = Math.PI * 2;
  const S = 1.65;             // buildings, soldiers and props are drawn this much bigger
  let renderer, scene, camera, sun, hemi, glCanvas;
  let W = 1, H = 1;
  let fw = 900, fh = 1400;
  let sides = [];
  let levelGroup = null;
  let theme = null;
  const models = new Map();   // tower id -> model
  const roads = new Map();    // road key -> mesh
  const v3 = new T.Vector3();
  const dummy = new T.Object3D();
  const m4 = new T.Matrix4(), leg = new T.Matrix4();
  const raycaster = new T.Raycaster();
  const groundPlane = new T.Plane(new T.Vector3(0, 1, 0), 0);

  // Map looks. Each level picks one (see game.js).
  const THEMES = {
    grass: { ground: '#8ed54f', field: '#97dc58', spot: '#7cc743', outer: '#f3dfa6', sky: '#9fdcff', props: 'pine', wall: 'hedge' },
    desert: { ground: '#f4d48d', field: '#f8dd9e', spot: '#ecc77a', outer: '#e8a866', sky: '#ffe9c2', props: 'cactus', wall: 'crate' },
    snow: { ground: '#cfeaf8', field: '#b9e2f6', spot: '#a9d7ef', outer: '#f6fbff', sky: '#dff3ff', props: 'snowpine', wall: 'ice' },
    mine: { ground: '#80405a', field: '#8a4862', spot: '#733650', outer: '#5c2c46', sky: '#4a2338', props: 'crystal', wall: 'rock' },
  };

  // ---------- Materials ----------
  const lam = (color, extra = {}) => new T.MeshLambertMaterial({ color, ...extra });
  const M = {};
  let TEAM = [];
  function makeMaterials() {
    Object.assign(M, {
      wall: lam('#f1f3f7'), wallShade: lam('#cfd5df'), dark: lam('#2d3340'), metal: lam('#6d7684'), steel: lam('#9aa3b1'),
      skin: lam('#ffcfa1'), boot: lam('#3b3f4a'), wood: lam('#a8693a'), woodDark: lam('#7d4b26'), trunk: lam('#8a5a32'),
      leaf: lam('#ffffff'), rock: lam('#9a93a6'), ice: lam('#8fd3f5'), iceTop: lam('#e9f8ff'), snow: lam('#ffffff'),
      crystal: lam('#c06cf0', { emissive: '#4a1670' }), cactus: lam('#5fb346'), barrel: lam('#5d6673'), tire: lam('#30333a'),
      gold: lam('#ffd23f', { emissive: '#6b4a00' }), white: lam('#ffffff'),
    });
    TEAM = sides.map(s => ({ team: lam(s.color), teamDark: lam(s.dark), teamLight: lam(s.light) }));
  }
  const matFor = (kind, side) => (kind.startsWith('team') ? TEAM[side][kind] : M[kind]);

  // ---------- Small geometry helpers ----------
  function box(w, h, d, x = 0, y = 0, z = 0, ry = 0) {
    const g = new T.BoxGeometry(w, h, d);
    if (ry) g.rotateY(ry);
    return g.translate(x, y, z);
  }
  // A hexagonal prism with a flat face toward the camera
  function hex(rt, rb, h, x = 0, y = 0, z = 0) {
    return new T.CylinderGeometry(rt, rb, h, 6).rotateY(Math.PI / 6).translate(x, y, z);
  }
  function cyl(rt, rb, h, seg, x = 0, y = 0, z = 0) {
    return new T.CylinderGeometry(rt, rb, h, seg).translate(x, y, z);
  }
  // Collects shapes by material and merges each group into one mesh (few draw calls)
  class Parts {
    constructor() { this.lists = {}; }
    add(kind, geo) { (this.lists[kind] ||= []).push(geo); return this; }
    build(group, side, shadow = true) {
      for (const [kind, list] of Object.entries(this.lists)) {
        const geo = T.mergeGeometries(list.map(g => (g.index ? g.toNonIndexed() : g)));
        list.forEach(g => g.dispose());
        geo.computeVertexNormals();
        const mesh = new T.Mesh(geo, matFor(kind, side));
        mesh.castShadow = shadow;
        mesh.receiveShadow = true;
        mesh.userData.kind = kind;
        group.add(mesh);
      }
      return group;
    }
  }

  // ---------- Canvas textures ----------
  function canvasTex(w, h, paint, repeat = false) {
    const c = document.createElement('canvas');
    c.width = w; c.height = h;
    paint(c.getContext('2d'), w, h);
    const t = new T.CanvasTexture(c);
    t.colorSpace = T.SRGBColorSpace;
    t.anisotropy = 4;
    if (repeat) t.wrapS = t.wrapT = T.RepeatWrapping;
    return t;
  }
  function rng(seed) {
    return () => {
      seed |= 0; seed = (seed + 0x6d2b79f5) | 0;
      let t = Math.imul(seed ^ (seed >>> 15), 1 | seed);
      t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t;
      return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
    };
  }
  let puffTex, roadTex = [];
  function makeTextures() {
    puffTex = canvasTex(64, 64, (g, w) => {
      const gr = g.createRadialGradient(w / 2, w / 2, 0, w / 2, w / 2, w / 2);
      gr.addColorStop(0, 'rgba(255,255,255,1)');
      gr.addColorStop(0.55, 'rgba(255,255,255,0.75)');
      gr.addColorStop(1, 'rgba(255,255,255,0)');
      g.fillStyle = gr;
      g.fillRect(0, 0, w, w);
    });
    // A see-through strip in the army's color with a dotted middle line
    roadTex = sides.map(s => canvasTex(64, 64, (g, w, h) => {
      g.clearRect(0, 0, w, h);
      g.fillStyle = s.color;
      g.globalAlpha = 0.5;
      g.fillRect(2, 0, w - 4, h);
      g.globalAlpha = 0.9;
      g.fillRect(2, 0, 5, h);
      g.fillRect(w - 7, 0, 5, h);
      g.globalAlpha = 0.95;
      g.fillStyle = s.light;
      g.beginPath(); g.arc(w / 2, h / 2, 5, 0, TAU); g.fill();
    }, true));
  }

  function groundTexture(seed, wWorld, hWorld, margin) {
    const k = 1024 / Math.max(wWorld, hWorld);
    return canvasTex(Math.round(wWorld * k), Math.round(hWorld * k), (g, w, h) => {
      const r = rng(seed);
      g.fillStyle = theme.ground;
      g.fillRect(0, 0, w, h);
      // The battlefield, a little brighter, with soft edges
      const m = margin * k;
      g.save();
      g.shadowColor = theme.spot;
      g.shadowBlur = 40 * k * 2;
      g.fillStyle = theme.field;
      const rr = 60 * k;
      g.beginPath();
      g.moveTo(m + rr, m); g.arcTo(w - m, m, w - m, h - m, rr); g.arcTo(w - m, h - m, m, h - m, rr);
      g.arcTo(m, h - m, m, m, rr); g.arcTo(m, m, w - m, m, rr); g.closePath();
      g.fill();
      g.restore();
      // Soft patches and speckles so the ground isn't flat
      for (let i = 0; i < 70; i++) {
        const x = r() * w, y = r() * h, rad = (40 + r() * 130) * k;
        const pg = g.createRadialGradient(x, y, 0, x, y, rad);
        pg.addColorStop(0, hexA(r() < 0.5 ? theme.spot : '#ffffff', 0.18));
        pg.addColorStop(1, hexA(theme.spot, 0));
        g.fillStyle = pg;
        g.fillRect(x - rad, y - rad, rad * 2, rad * 2);
      }
      for (let i = 0; i < 900; i++) {
        g.fillStyle = hexA(r() < 0.6 ? theme.spot : '#ffffff', 0.35);
        const x = r() * w, y = r() * h;
        g.fillRect(x, y, 2, 2);
      }
      if (theme === THEMES.mine || theme === THEMES.desert) {
        // Cracks in the dry ground
        g.strokeStyle = hexA(theme.spot, 0.8);
        g.lineWidth = 2;
        for (let i = 0; i < 26; i++) {
          let x = r() * w, y = r() * h;
          g.beginPath(); g.moveTo(x, y);
          for (let j = 0; j < 3; j++) { x += (r() - 0.5) * 40; y += (r() - 0.5) * 40; g.lineTo(x, y); }
          g.stroke();
        }
      }
    });
  }
  function hexA(hex, a) {
    const n = parseInt(hex.slice(1), 16);
    return `rgba(${n >> 16},${(n >> 8) & 255},${n & 255},${a})`;
  }

  // ---------- Setup ----------
  api.init = (overlay, sideList) => {
    sides = sideList;
    try {
      glCanvas = document.createElement('canvas');
      glCanvas.id = 'gl';
      overlay.parentNode.insertBefore(glCanvas, overlay);
      renderer = new T.WebGLRenderer({ canvas: glCanvas, antialias: true, powerPreference: 'high-performance' });
    } catch {
      glCanvas?.remove();
      return false;
    }
    renderer.shadowMap.enabled = true;
    renderer.shadowMap.type = T.PCFSoftShadowMap;
    scene = new T.Scene();
    camera = new T.PerspectiveCamera(30, 1, 20, 9000);
    hemi = new T.HemisphereLight('#ffffff', '#8a9a7a', 2.2);
    sun = new T.DirectionalLight('#fff6e8', 2.3);
    sun.castShadow = true;
    sun.shadow.mapSize.set(2048, 2048);
    sun.shadow.bias = -0.0005;
    sun.shadow.normalBias = 0.5;
    sun.shadow.radius = 3;
    scene.add(hemi, sun, sun.target);
    makeMaterials();
    makeTextures();
    makeUnitMeshes();
    makeFxPools();
    api.ok = true;
    return true;
  };

  api.layout = (w, h, dpr, landscape, fieldW, fieldH, top, bottom) => {
    if (!api.ok) return;
    W = w; H = h;
    fw = fieldW; fh = fieldH;
    renderer.setPixelRatio(dpr);
    renderer.setSize(w, h, false);
    glCanvas.style.width = w + 'px';
    glCanvas.style.height = h + 'px';
    camera.aspect = w / h;
    fitCamera(top, bottom);
    // Sun from the upper left, shadows covering the field
    const cx = fw / 2, cz = fh / 2;
    sun.position.set(cx - 450, 1000, cz - 250);
    sun.target.position.set(cx, 0, cz);
    const half = Math.max(fw, fh) * 0.8;
    Object.assign(sun.shadow.camera, { left: -half, right: half, top: half, bottom: -half, near: 100, far: 2800 });
    sun.shadow.camera.updateProjectionMatrix();
  };

  // A high camera, moved until the whole field fits between the HUD bars
  function fitCamera(top, bottom) {
    const pitch = 1.0; // radians above the horizon
    const target = new T.Vector3(fw / 2, 0, fh / 2);
    let d = 2400;
    const pad = 6;
    const corners = [[-20, 0, -40, 120], [fw + 20, 0, -40, 120], [-20, 0, fh + 30, 0], [fw + 20, 0, fh + 30, 0]];
    for (let i = 0; i < 40; i++) {
      camera.position.set(target.x, Math.sin(pitch) * d, target.z + Math.cos(pitch) * d);
      camera.lookAt(target);
      camera.updateProjectionMatrix();
      camera.updateMatrixWorld();
      let x0 = Infinity, x1 = -Infinity, y0 = Infinity, y1 = -Infinity;
      for (const [x, , z, h] of corners) {
        v3.set(x, h, z).project(camera);
        const sx = (v3.x + 1) / 2 * W, sy = (1 - v3.y) / 2 * H;
        x0 = Math.min(x0, sx); x1 = Math.max(x1, sx); y0 = Math.min(y0, sy); y1 = Math.max(y1, sy);
      }
      const availW = W - pad * 2, availH = H - top - bottom - pad * 2;
      const k = Math.max((x1 - x0) / availW, (y1 - y0) / availH);
      d *= Math.pow(k, 0.85);
      const wantY = top + pad + availH / 2;
      target.z += ((y0 + y1) / 2 - wantY) * (fh / Math.max(1, y1 - y0)) * 0.6;
    }
  }

  // ---------- Level scenery ----------
  api.build = (seed, themeName, towers, rocks) => {
    if (!api.ok) return;
    if (levelGroup) {
      scene.remove(levelGroup);
      levelGroup.traverse(o => { o.geometry?.dispose(); if (o.userData.ownTex) o.material.map.dispose(); });
    }
    roads.clear();
    models.clear();
    levelGroup = new T.Group();
    scene.add(levelGroup);
    theme = THEMES[themeName] || THEMES.grass;
    scene.background = new T.Color(theme.outer);
    scene.fog = new T.Fog(theme.outer, 3200, 6500);
    const r = rng(seed);

    // Ground: one big textured plane, the field drawn into it
    const margin = 900;
    const gw = fw + margin * 2, gh = fh + margin * 2;
    const groundMat = new T.MeshLambertMaterial({ map: groundTexture(seed, gw, gh, margin - 50) });
    const ground = new T.Mesh(new T.PlaneGeometry(gw, gh).rotateX(-Math.PI / 2).translate(fw / 2, 0, fh / 2), groundMat);
    ground.userData.ownTex = true;
    ground.receiveShadow = true;
    levelGroup.add(ground);

    // Props around the field (trees, barrels, crates...) and the walls that block roads
    const props = { pine: [], snowpine: [], cactus: [], crystal: [], rock: [], barrel: [], crate: [], tire: [], w_crate: [], w_ice: [], w_hedge: [], w_rock: [] };
    const avoid = (x, z, d) => towers.some(t => Math.hypot(t.x - x, t.y - z) < d);
    for (let i = 0; i < 260; i++) {
      // Outside the field, in a band the camera can see
      const side = Math.floor(r() * 4);
      let x, z;
      const out = 60 + r() * 260;
      if (side === 0) { x = -200 + r() * (fw + 400); z = -out; }
      else if (side === 1) { x = -200 + r() * (fw + 400); z = fh + out; }
      else if (side === 2) { x = -out; z = -200 + r() * (fh + 400); }
      else { x = fw + out; z = -200 + r() * (fh + 400); }
      const k = r();
      const kind = k < 0.62 ? theme.props : k < 0.74 ? 'rock' : k < 0.84 ? 'barrel' : k < 0.93 ? 'crate' : 'tire';
      props[kind].push({ x, z, s: 0.8 + r() * 0.7, a: r() * TAU, c: r() });
    }
    // A few trees inside the field near the edges
    for (let i = 0; i < 40; i++) {
      const edge = Math.floor(r() * 4);
      const inset = 15 + r() * 30;
      let x = r() * fw, z = r() * fh;
      if (edge === 0) z = inset; else if (edge === 1) z = fh - inset; else if (edge === 2) x = inset; else x = fw - inset;
      if (avoid(x, z, 160)) continue;
      props[theme.props].push({ x, z, s: 0.7 + r() * 0.4, a: r() * TAU, c: r() });
    }
    // Walls: each blocking circle gets a few props of the map's wall type
    for (const k of rocks) {
      const rr = rng(Math.round(k.x * 13 + k.y * 7));
      const n = Math.max(2, Math.round(k.r / 18));
      for (let i = 0; i < n; i++) {
        const a = rr() * TAU, d = rr() * k.r * 0.55;
        props['w_' + theme.wall].push({ x: k.x + Math.cos(a) * d, z: k.y + Math.sin(a) * d, s: (k.r / 40) * (0.8 + rr() * 0.3), a: Math.round(rr() * 4) * Math.PI / 2 + (rr() - 0.5) * 0.3, c: rr(), wall: true });
      }
    }
    addProps(props);
    for (const t of towers) syncTower(t);
  };

  // One instanced mesh per prop part, so hundreds of props cost a few draw calls
  function instanced(geo, mat, list, colorFn, shadow = true) {
    if (!list.length) return;
    const im = new T.InstancedMesh(geo, mat, list.length);
    const c = new T.Color();
    list.forEach((p, i) => {
      dummy.position.set(p.x, 0, p.z);
      dummy.rotation.set(0, p.a, 0);
      dummy.scale.setScalar(p.s * S);
      dummy.updateMatrix();
      im.setMatrixAt(i, dummy.matrix);
      if (colorFn) im.setColorAt(i, colorFn(p, c));
    });
    im.castShadow = shadow;
    im.receiveShadow = true;
    levelGroup.add(im);
  }
  function addProps(P) {
    const merge = list => T.mergeGeometries(list.map(g => (g.index ? g.toNonIndexed() : g)));
    // Pine trees (green, or with snow on top)
    const pineGeo = merge([new T.ConeGeometry(17, 22, 7).translate(0, 18, 0), new T.ConeGeometry(14, 19, 7).translate(0, 30, 0), new T.ConeGeometry(10, 16, 7).translate(0, 41, 0)]);
    const trunkGeo = cyl(3, 4, 10, 6, 0, 5, 0);
    for (const kind of ['pine', 'snowpine']) {
      const list = P[kind];
      instanced(trunkGeo, M.trunk, list);
      instanced(pineGeo, M.leaf, list, (p, c) => c.setHSL(0.33 + p.c * 0.04, 0.62, 0.36 + p.c * 0.08));
    }
    if (P.snowpine.length) instanced(merge([new T.ConeGeometry(9, 9, 7).translate(0, 46, 0), new T.ConeGeometry(14, 5, 7).translate(0, 32, 0)]), M.snow, P.snowpine);
    // Cacti
    instanced(merge([cyl(5, 5.5, 34, 8, 0, 17, 0), new T.SphereGeometry(5, 8, 4, 0, TAU, 0, Math.PI / 2).translate(0, 34, 0),
      cyl(3.5, 3.5, 12, 6, 9, 20, 0), cyl(3.5, 3.5, 6, 6, 6, 15, 0).rotateZ(Math.PI / 2).translate(0, 0, 0)]), M.cactus, P.cactus);
    // Crystals
    instanced(merge([new T.OctahedronGeometry(9).scale(0.6, 1.8, 0.6).translate(0, 14, 0), new T.OctahedronGeometry(6).scale(0.6, 1.6, 0.6).rotateZ(0.5).translate(8, 9, 2),
      new T.OctahedronGeometry(5).scale(0.6, 1.5, 0.6).rotateZ(-0.6).translate(-7, 8, -3)]), M.crystal, P.crystal);
    // Rocks
    const rockGeo = new T.DodecahedronGeometry(14, 0).scale(1, 0.7, 1).translate(0, 7, 0);
    instanced(rockGeo, M.rock, P.rock, (p, c) => c.setHSL(0.7, 0.05, 0.55 + p.c * 0.15));
    // Barrels, crates and old tires
    instanced(merge([cyl(7, 7, 16, 10, 0, 8, 0), cyl(7.4, 7.4, 1.6, 10, 0, 4, 0), cyl(7.4, 7.4, 1.6, 10, 0, 12, 0)]), M.barrel, P.barrel);
    instanced(box(18, 18, 18, 0, 9, 0), M.wood, P.crate, (p, c) => c.setHSL(0.07, 0.5, 0.42 + p.c * 0.1));
    instanced(new T.TorusGeometry(8, 3.5, 6, 12).rotateX(Math.PI / 2).translate(0, 3.5, 0), M.tire, P.tire);
    // Wall pieces: crates, ice blocks, hedges or boulders, depending on the map
    instanced(merge([box(24, 22, 24, 0, 11, 0), box(25, 2.5, 4, 0, 11, 12.2), box(25, 2.5, 4, 0, 11, -12.2), box(4, 2.5, 25, 12.2, 11, 0), box(4, 2.5, 25, -12.2, 11, 0)]), M.wood, P.w_crate, (p, c) => c.setHSL(0.07, 0.55, 0.4 + p.c * 0.08));
    instanced(box(25, 20, 25, 0, 10, 0), M.ice, P.w_ice, (p, c) => c.setHSL(0.56, 0.8, 0.62 + p.c * 0.1));
    instanced(box(26, 3, 26, 0, 21.5, 0), M.iceTop, P.w_ice);
    instanced(new T.IcosahedronGeometry(15, 0).scale(1.1, 0.95, 1.1).translate(0, 12, 0), M.leaf, P.w_hedge, (p, c) => c.setHSL(0.31, 0.6, 0.32 + p.c * 0.08));
    instanced(new T.DodecahedronGeometry(16, 0).scale(1, 0.85, 1).translate(0, 11, 0), M.rock, P.w_rock, (p, c) => c.setHSL(0.78, 0.12, 0.42 + p.c * 0.12));
  }

  // ---------- Buildings ----------
  function buildModel(t, lv) {
    const g = new T.Group();
    const P = new Parts();
    const side = t.owner;
    const info = { group: g, flag: null, turret: null, smoke: null, top: 60, range: null };
    if (t.type === 'barracks' || t.type === 'fort') {
      // A stack of hexagonal floors, one more for every level, with a colored cap
      const fort = t.type === 'fort';
      const R = fort ? 40 : 34;
      P.add('wallShade', hex(R + 6, R + 8, 8, 0, 4, 0));
      P.add('team', hex(R + 6.6, R + 6.6, 3, 0, 7, 0));
      let y = 8, r = R;
      const floors = fort ? 1 + Math.ceil(lv / 2) : lv + 1;
      for (let i = 0; i < floors; i++) {
        const h = fort ? 15 : 14;
        P.add('wall', hex(r - 1.5, r, h, 0, y + h / 2, 0));
        P.add('team', hex(r + 0.6, r + 0.6, 3.5, 0, y + h - 2, 0));
        // A window slit on the front faces
        const fz = (r - 1) * Math.cos(Math.PI / 6);
        P.add('dark', box(r * 0.75, 3, 2, 0, y + 6.5, fz));
        for (const s of [-1, 1]) P.add('dark', box(r * 0.55, 3, 2, 0, y + 6.5, fz, s * Math.PI / 3));
        y += h;
        r -= fort ? 1 : 2;
      }
      if (fort) {
        // Bunker: thick armor plates and a gun on each side
        for (let k = 0; k < 6; k++) {
          const a = k * Math.PI / 3 + Math.PI / 6;
          P.add('wallShade', box(10, y - 6, 6, Math.sin(a) * (R + 2), (y + 4) / 2, Math.cos(a) * (R + 2), a));
        }
        for (let k = 0; k < lv; k++) {
          const a = k * TAU / lv + 0.4;
          P.add('metal', new T.CylinderGeometry(2.4, 2.8, 16, 6).rotateX(Math.PI / 2).translate(0, 0, r + 8).rotateY(a).translate(0, y - 8, 0));
        }
      }
      // The cap: the army's color, where the number sits
      P.add('teamDark', hex(r + 3, r + 3, 6, 0, y + 3, 0));
      P.add('team', hex(r - 0.5, r + 3, 5, 0, y + 8.5, 0));
      P.add('dark', box(12, 14, 2, 0, 15, (R + 0.5) * Math.cos(Math.PI / 6) + 1));
      P.add('wallShade', box(15, 2.5, 3, 0, 23, (R + 0.5) * Math.cos(Math.PI / 6) + 1.2));
      info.top = y + 11;
      info.capR = r;
    } else if (t.type === 'factory') {
      // Tank factory: a hall with a big garage door and smoking chimneys
      const h = 26 + lv * 2;
      P.add('wallShade', box(84, 6, 70, 0, 3, 0));
      P.add('wall', box(70, h, 54, 0, 6 + h / 2, 0));
      P.add('team', box(74, 7, 58, 0, 6 + h + 3.5, 0));
      P.add('teamDark', box(74, 3, 58, 0, 6 + h - 0.5, 0));
      P.add('dark', box(34, 20, 2, 0, 16, 27.5));
      for (let i = 0; i < 4; i++) P.add('wallShade', box(34, 1.2, 2.4, 0, 9 + i * 4.5, 28));
      P.add('team', box(38, 3, 3, 0, 27.5, 28));
      // Vents on the roof
      for (let i = 0; i < Math.min(3, lv); i++) {
        P.add('metal', new T.CylinderGeometry(4, 4, 14, 10).rotateX(Math.PI / 2).translate(-20 + i * 13, 6 + h + 10, 22));
        P.add('dark', new T.CylinderGeometry(2.5, 2.5, 14.4, 10).rotateX(Math.PI / 2).translate(-20 + i * 13, 6 + h + 10, 22));
      }
      info.smoke = [];
      const chimneys = Math.min(3, lv);
      for (let i = 0; i < chimneys; i++) {
        const ch = 44 + i * 6;
        const x = 22 - i * 10;
        P.add('metal', cyl(4.5, 5.5, ch, 10, x, 6 + ch / 2, -16));
        P.add('dark', cyl(5.5, 5.5, 3, 10, x, 6 + ch, -16));
        info.smoke.push(new T.Vector3(x, 6 + ch + 3, -16));
      }
      info.top = 6 + h + 12;
    } else {
      // Watchtower: a lookout on four legs with a pointed roof; it shoots at enemies in its circle
      const legH = 34 + lv * 4;
      for (const [x, z] of [[-14, -14], [14, -14], [-14, 14], [14, 14]]) P.add('wall', box(4.5, legH, 4.5, x, legH / 2, z));
      for (const y of [legH * 0.35, legH * 0.7]) {
        P.add('wallShade', box(30, 2.5, 2.5, 0, y, 14));
        P.add('wallShade', box(30, 2.5, 2.5, 0, y, -14));
        P.add('wallShade', box(2.5, 2.5, 30, 14, y, 0));
        P.add('wallShade', box(2.5, 2.5, 30, -14, y, 0));
      }
      P.add('wall', box(40, 4, 40, 0, legH + 2, 0));
      P.add('team', box(40, 9, 3, 0, legH + 8.5, 18.5));
      P.add('team', box(40, 9, 3, 0, legH + 8.5, -18.5));
      P.add('team', box(3, 9, 40, 18.5, legH + 8.5, 0));
      P.add('team', box(3, 9, 40, -18.5, legH + 8.5, 0));
      for (const [x, z] of [[-17, -17], [17, -17], [-17, 17], [17, 17]]) P.add('wall', box(3, 14, 3, x, legH + 11, z));
      P.add('team', new T.ConeGeometry(33, 22, 4).rotateY(Math.PI / 4).translate(0, legH + 29, 0));
      P.add('teamDark', box(46, 2, 46, 0, legH + 18, 0));
      info.top = legH + 42;
      info.muzzle = new T.Vector3(0, legH + 10, 0);
      // The range circle on the ground
      const ring = new T.Mesh(new T.RingGeometry(WATCH_RANGE - 3, WATCH_RANGE, 72).rotateX(-Math.PI / 2), new T.MeshBasicMaterial({ color: '#ffffff', transparent: true, opacity: 0.75, depthWrite: false }));
      ring.position.y = 0.8;
      const fill = new T.Mesh(new T.CircleGeometry(WATCH_RANGE - 3, 72).rotateX(-Math.PI / 2), new T.MeshBasicMaterial({ color: '#ffffff', transparent: true, opacity: 0.12, depthWrite: false }));
      fill.position.y = 0.6;
      g.add(ring, fill);
      info.range = ring;
    }
    P.build(g, side);
    g.position.set(t.x, 0, t.y);
    info.top *= S;
    if (info.muzzle) info.muzzle.multiplyScalar(S);
    if (info.smoke) info.smoke.forEach(v => v.multiplyScalar(S));
    if (info.range) { info.range.scale.setScalar(1 / S); info.range.parent.children.forEach(c => c !== info.range && c.geometry.type === 'CircleGeometry' && c.scale.setScalar(1 / S)); }
    return info;
  }

  function setTeam(info, side) {
    info.group.traverse(o => {
      const k = o.userData.kind;
      if (k && k.startsWith('team')) o.material = TEAM[side][k];
    });
  }

  function syncTower(t) {
    const lv = towerLevel(t);
    let info = models.get(t.id);
    if (!info || info.lv !== lv || info.type !== t.type) {
      if (info) { levelGroup.remove(info.group, info.ring); info.group.traverse(o => o.geometry?.dispose()); }
      info = buildModel(t, lv);
      info.lv = lv; info.type = t.type; info.side = t.owner;
      info.ring = new T.Mesh(new T.RingGeometry(0.88, 1, 48).rotateX(-Math.PI / 2), new T.MeshBasicMaterial({ color: '#ffffff', transparent: true, opacity: 0.8, depthWrite: false }));
      info.ring.position.set(t.x, 1.5, t.y);
      info.ring.visible = false;
      levelGroup.add(info.group, info.ring);
      models.set(t.id, info);
    }
    if (info.side !== t.owner) { setTeam(info, t.owner); info.side = t.owner; }
    info.group.position.set(t.x, 0, t.y);
    info.ring.position.set(t.x, 1.5, t.y);
    return info;
  }

  // ---------- Soldiers and tanks ----------
  const MAX_SOLDIERS = 1200, MAX_TANKS = 240;
  const U = {};
  function makeUnitMeshes() {
    const mk = (geo, mat, n, shadow = false) => {
      const im = new T.InstancedMesh(geo, mat, n);
      im.instanceMatrix.setUsage(T.DynamicDrawUsage);
      im.castShadow = shadow;
      im.frustumCulled = false;
      im.count = 0;
      scene.add(im);
      return im;
    };
    const white = () => lam('#ffffff');
    // Chibi soldier: big head, big helmet in the army's color, small body
    U.body = mk(box(9, 9, 6.5, 0, 11.5, 0), white(), MAX_SOLDIERS, true);
    U.head = mk(new T.SphereGeometry(5.6, 10, 8).translate(0, 21, 0.4), M.skin, MAX_SOLDIERS, true);
    U.helmet = mk(new T.SphereGeometry(6.4, 10, 5, 0, TAU, 0, Math.PI / 2).scale(1, 0.85, 1).translate(0, 22.2, 0), white(), MAX_SOLDIERS);
    U.brim = mk(cyl(7.2, 7.2, 1.4, 12, 0, 22.4, 0), white(), MAX_SOLDIERS);
    U.gun = mk(box(2, 2.4, 15, 5.8, 12, 3), M.dark, MAX_SOLDIERS);
    U.leg = mk(box(3.4, 7, 3.4, 0, -3.5, 0), M.boot, MAX_SOLDIERS * 2);
    // Tank
    U.hull = mk(T.mergeGeometries([box(20, 8, 28, 0, 8, 0), box(16, 3, 8, 0, 9, 15)].map(g => g.toNonIndexed())), white(), MAX_TANKS, true);
    U.track = mk(T.mergeGeometries([box(6, 8, 30, -12.5, 5, 0), box(6, 8, 30, 12.5, 5, 0)].map(g => g.toNonIndexed())), M.boot, MAX_TANKS);
    U.turret = mk(box(14, 7, 14, 0, 15.5, -2), white(), MAX_TANKS, true);
    U.barrel = mk(new T.CylinderGeometry(1.8, 2, 20, 8).rotateX(Math.PI / 2).translate(0, 15.5, 14), M.steel, MAX_TANKS);
  }

  const col = new T.Color();
  function drawUnits(units, time) {
    let s = 0, k = 0;
    for (const u of units) {
      const dx = u.to.x - u.from.x, dz = u.to.y - u.from.y;
      const ang = Math.atan2(dx, dz);
      const team = sides[u.owner];
      if (u.power > 1) {
        if (k >= MAX_TANKS) continue;
        dummy.position.set(u.x, Math.abs(Math.sin(time * 20 + u.id)) * 0.6, u.y);
        dummy.rotation.set(0, ang, 0);
        dummy.scale.setScalar(1.15 * S);
        dummy.updateMatrix();
        for (const p of ['hull', 'track', 'turret', 'barrel']) U[p].setMatrixAt(k, dummy.matrix);
        U.hull.setColorAt(k, col.set(team.color));
        U.turret.setColorAt(k, col.set(team.light));
        k++;
      } else {
        if (s >= MAX_SOLDIERS) continue;
        const ph = time * 14 + u.id * 1.7;
        dummy.position.set(u.x, Math.abs(Math.sin(ph)) * 2.6, u.y);
        dummy.rotation.set(0, ang, Math.sin(ph) * 0.08);
        dummy.scale.setScalar(1.2 * S);
        dummy.updateMatrix();
        for (const p of ['body', 'head', 'helmet', 'brim', 'gun']) U[p].setMatrixAt(s, dummy.matrix);
        U.body.setColorAt(s, col.set(team.dark));
        U.helmet.setColorAt(s, col.set(team.color));
        U.brim.setColorAt(s, col.set(team.color));
        const sw = Math.sin(ph) * 0.8;
        for (let l = 0; l < 2; l++) {
          leg.makeRotationX(l ? sw : -sw);
          leg.setPosition(l ? 2.4 : -2.4, 7, 0);
          m4.multiplyMatrices(dummy.matrix, leg);
          U.leg.setMatrixAt(s * 2 + l, m4);
        }
        s++;
      }
    }
    for (const p of ['body', 'head', 'helmet', 'brim', 'gun']) U[p].count = s;
    U.leg.count = s * 2;
    for (const p of ['hull', 'track', 'turret', 'barrel']) U[p].count = k;
    for (const im of Object.values(U)) {
      im.instanceMatrix.needsUpdate = true;
      if (im.instanceColor) im.instanceColor.needsUpdate = true;
    }
  }

  // ---------- Roads ----------
  function roadGeometry(a, b, grow) {
    const dx = b.x - a.x, dz = b.y - a.y, L = Math.hypot(dx, dz) || 1;
    const ux = dx / L, uz = dz / L, nx = -uz, nz = ux;
    const start = 0, end = Math.max(1, L * grow);
    const w = 20;
    const x0 = a.x + ux * start, z0 = a.y + uz * start, x1 = a.x + ux * end, z1 = a.y + uz * end;
    const v1 = (end - start) / 30;
    const geo = new T.BufferGeometry();
    geo.setAttribute('position', new T.Float32BufferAttribute([
      x0 + nx * w, 0, z0 + nz * w, x0 - nx * w, 0, z0 - nz * w, x1 + nx * w, 0, z1 + nz * w, x1 - nx * w, 0, z1 - nz * w,
    ], 3));
    geo.setAttribute('uv', new T.Float32BufferAttribute([0, 0, 1, 0, 0, v1, 1, v1], 2));
    geo.setIndex([0, 2, 1, 1, 2, 3]);
    return geo;
  }
  const roadMats = [];
  function syncRoads(towers, gameTime) {
    const seen = new Set();
    let order = 0;
    for (const t of towers) {
      for (const r of t.roads) {
        const key = `${t.id}>${r.to.id}:${t.owner}`;
        seen.add(key);
        const grow = Math.min(1, (gameTime - r.born) / 0.25);
        let mesh = roads.get(key);
        if (!mesh) {
          if (!roadMats[t.owner]) roadMats[t.owner] = new T.MeshBasicMaterial({ map: roadTex[t.owner], transparent: true, depthWrite: false, polygonOffset: true, polygonOffsetFactor: -2 });
          mesh = new T.Mesh(roadGeometry(t, r.to, grow), roadMats[t.owner]);
          mesh.userData.grow = grow;
          levelGroup.add(mesh);
          roads.set(key, mesh);
        } else if (mesh.userData.grow < 1) {
          mesh.geometry.dispose();
          mesh.geometry = roadGeometry(t, r.to, grow);
          mesh.userData.grow = grow;
        }
        mesh.position.y = 1 + (order++ % 6) * 0.15;
      }
    }
    for (const [key, mesh] of roads) {
      if (!seen.has(key)) { levelGroup.remove(mesh); mesh.geometry.dispose(); roads.delete(key); }
    }
  }

  // ---------- Effects ----------
  const puffs = [], fires = [], rings = [], shellMeshes = [], bits = [];
  let plane = null;
  function makeFxPools() {
    for (let i = 0; i < 180; i++) {
      const sp = new T.Sprite(new T.SpriteMaterial({ map: puffTex, transparent: true, depthWrite: false, fog: false }));
      sp.visible = false;
      sp.userData = { life: 0 };
      scene.add(sp);
      puffs.push(sp);
    }
    const fireGeo = new T.IcosahedronGeometry(1, 1);
    for (let i = 0; i < 30; i++) {
      const m = new T.Mesh(fireGeo, new T.MeshBasicMaterial({ color: '#ffb347', transparent: true, depthWrite: false }));
      m.visible = false;
      m.userData = { life: 0 };
      scene.add(m);
      fires.push(m);
    }
    // Little colored chunks that fly off when soldiers clash (like confetti)
    const bitGeo = new T.TetrahedronGeometry(4);
    for (let i = 0; i < 220; i++) {
      const m = new T.Mesh(bitGeo, lam('#ffffff'));
      m.visible = false;
      m.userData = { life: 0 };
      scene.add(m);
      bits.push(m);
    }
    const ringGeo = new T.RingGeometry(0.85, 1, 48).rotateX(-Math.PI / 2);
    for (let i = 0; i < 16; i++) {
      const m = new T.Mesh(ringGeo, new T.MeshBasicMaterial({ color: '#ffffff', transparent: true, depthWrite: false }));
      m.visible = false;
      m.userData = { life: 0 };
      scene.add(m);
      rings.push(m);
    }
    const shellGeo = new T.SphereGeometry(3, 8, 6);
    for (let i = 0; i < 40; i++) {
      const m = new T.Mesh(shellGeo, M.dark);
      m.visible = false;
      m.castShadow = true;
      scene.add(m);
      shellMeshes.push(m);
    }
    // The airstrike plane
    plane = new T.Group();
    const P = new Parts();
    P.add('wall', new T.CylinderGeometry(5, 7, 52, 10).rotateX(Math.PI / 2));
    P.add('wall', new T.ConeGeometry(5, 12, 10).rotateX(Math.PI / 2).translate(0, 0, 32));
    P.add('team', box(80, 2, 14, 0, 0, 2));
    P.add('team', box(28, 1.6, 8, 0, 1, -23));
    P.add('team', box(1.6, 14, 10, 0, 7, -23));
    P.add('dark', box(6, 3.5, 10, 0, 4.5, 14));
    P.build(plane, 1);
    plane.visible = false;
    scene.add(plane);
  }
  const take = pool => pool.find(p => !p.visible) || null;

  function puff(x, y, z, color, size, life, vy = 30) {
    const p = take(puffs);
    if (!p) return;
    p.visible = true;
    p.position.set(x, y, z);
    p.material.color.set(color);
    p.userData = { life, max: life, size, vy, vx: (Math.random() - 0.5) * 14, vz: (Math.random() - 0.5) * 14 };
    p.scale.setScalar(size * 0.4);
  }
  function fireball(x, y, z, size, color = '#ffb347') {
    const f = take(fires);
    if (!f) return;
    f.visible = true;
    f.position.set(x, y, z);
    f.material.color.set(color);
    f.userData = { life: 0.45, max: 0.45, size };
  }
  function ring(x, z, color, size) {
    const r = take(rings);
    if (!r) return;
    r.visible = true;
    r.position.set(x, 2, z);
    r.material.color.set(color);
    r.userData = { life: 0.7, max: 0.7, size };
  }
  function chunks(x, z, color, n, speed = 90) {
    for (let i = 0; i < n; i++) {
      const b = take(bits);
      if (!b) return;
      const a = Math.random() * TAU, v = speed * (0.4 + Math.random() * 0.6);
      b.visible = true;
      b.material.color.set(color);
      b.position.set(x, 16, z);
      b.userData = { life: 0.9, vx: Math.cos(a) * v, vz: Math.sin(a) * v, vy: 60 + Math.random() * 70, spin: Math.random() * 10 };
    }
  }

  api.explode = (x, y, big) => {
    const s = big ? 50 : 18;
    fireball(x, s * 0.4, y, s);
    fireball(x + (Math.random() - 0.5) * s, s * 0.3, y + (Math.random() - 0.5) * s, s * 0.6, '#ff7b29');
    for (let i = 0; i < (big ? 10 : 3); i++) puff(x + (Math.random() - 0.5) * s, 6, y + (Math.random() - 0.5) * s, '#7a7a7a', s * 1.4, 1.1 + Math.random() * 0.6, 26);
    if (big) ring(x, y, '#ffd28a', 140);
  };
  api.clash = (x, y, a, b) => {
    chunks(x, y, sides[a].color, 3);
    chunks(x, y, sides[b].color, 3);
  };
  api.hit = (x, y, side) => chunks(x, y, sides[side].color, 4, 70);
  api.capture = (x, y, side) => {
    ring(x, y, sides[side].color, 120);
    ring(x, y, '#ffffff', 90);
    chunks(x, y, sides[side].color, 18, 140);
    for (let i = 0; i < 8; i++) {
      const a = (i / 8) * TAU;
      puff(x + Math.cos(a) * 46, 4, y + Math.sin(a) * 46, '#ffffff', 30, 0.8, 14);
    }
  };
  api.muzzle = (t, tx, ty) => {
    const info = models.get(t.id);
    const y = info?.muzzle ? info.muzzle.y : 30;
    const a = Math.atan2(ty - t.y, tx - t.x);
    fireball(t.x + Math.cos(a) * 18, y, t.y + Math.sin(a) * 18, 6, '#ffe08a');
  };

  function updateFx(dt, towers) {
    for (const p of puffs) {
      if (!p.visible) continue;
      const u = p.userData;
      u.life -= dt;
      if (u.life <= 0) { p.visible = false; continue; }
      const k = 1 - u.life / u.max;
      p.position.x += u.vx * dt; p.position.z += u.vz * dt; p.position.y += u.vy * dt;
      p.scale.setScalar(u.size * (0.4 + k * 0.9));
      p.material.opacity = (1 - k) * 0.8;
    }
    for (const f of fires) {
      if (!f.visible) continue;
      const u = f.userData;
      u.life -= dt;
      if (u.life <= 0) { f.visible = false; continue; }
      const k = 1 - u.life / u.max;
      f.scale.setScalar(u.size * (0.3 + k * 0.8));
      f.material.opacity = 1 - k;
    }
    for (const b of bits) {
      if (!b.visible) continue;
      const u = b.userData;
      u.life -= dt;
      if (u.life <= 0) { b.visible = false; continue; }
      u.vy -= 300 * dt;
      b.position.x += u.vx * dt; b.position.z += u.vz * dt; b.position.y = Math.max(1.5, b.position.y + u.vy * dt);
      if (b.position.y <= 1.5) { u.vx *= 0.8; u.vz *= 0.8; }
      b.rotation.x += u.spin * dt; b.rotation.y += u.spin * dt;
      b.scale.setScalar(Math.min(1, u.life * 3));
    }
    for (const r of rings) {
      if (!r.visible) continue;
      const u = r.userData;
      u.life -= dt;
      if (u.life <= 0) { r.visible = false; continue; }
      const k = 1 - u.life / u.max;
      r.scale.setScalar(20 + u.size * k);
      r.material.opacity = (1 - k) * 0.9;
    }
    // Chimney smoke from tank factories
    for (const t of towers) {
      const info = models.get(t.id);
      if (!info?.smoke || t.owner === 0) continue;
      info.smokeT = (info.smokeT ?? Math.random()) - dt;
      if (info.smokeT <= 0) {
        info.smokeT = 0.4;
        for (const s of info.smoke) puff(t.x + s.x, s.y, t.y + s.z, '#ffffff', 20, 1.6, 26);
      }
    }
  }

  // ---------- Each frame ----------
  let lastTime = performance.now() / 1000;
  api.render = world => {
    if (!api.ok || !levelGroup) return;
    const time = performance.now() / 1000;
    const dt = Math.min(0.05, time - lastTime);
    lastTime = time;
    const { towers, units, shells, strikes, threatOn, highlight } = world;
    for (const t of towers) {
      const info = syncTower(t);
      // Bounce when it gains soldiers, squash when hit
      const pop = 1 + t.pop * 0.06;
      info.group.scale.set(S * pop * (1 + t.flash * 0.03), S * pop * (1 - t.flash * 0.06), S * pop * (1 + t.flash * 0.03));
      if (info.range) {
        info.range.material.color.set(t.owner === 0 ? '#ffffff' : sides[t.owner].light);
        info.range.material.opacity = 0.75;
      }
      // Ground ring: threat, target, or drag highlight
      const hl = highlight(t);
      const threat = t.owner === 1 && threatOn(t) > 0;
      info.ring.visible = !!(hl || threat);
      if (info.ring.visible) {
        const bad = hl === 'bad' || hl === 'target' || (!hl && threat);
        info.ring.material.color.set(bad ? '#ff4a3a' : '#ffffff');
        info.ring.material.opacity = hl && hl !== 'target' ? 0.95 : 0.45 + 0.35 * Math.sin(time * 8);
        info.ring.scale.setScalar(towerRadius(t) + 20);
      }
    }
    syncRoads(towers, world.gameTime);
    for (const m of roadMats) if (m) m.map.offset.y = -time * 1.4;
    drawUnits(units, time);

    // Artillery shells fly in an arc
    shellMeshes.forEach((m, i) => {
      const s = shells[i];
      m.visible = !!s;
      if (!s) return;
      const k = 1 - s.time / s.dur;
      m.position.set(s.x1 + (s.x2 - s.x1) * k, s.h * (1 - k) + 10 * k + 18 * Math.sin(k * Math.PI), s.y1 + (s.y2 - s.y1) * k);
    });

    // Airstrike: a plane flies over the target and the bombs fall
    const st = strikes[0];
    plane.visible = !!st;
    if (st) {
      const k = 1 - st.time / st.dur;
      const dirX = 0.6, dirZ = -0.8;
      const along = (k - 0.8) * 1500;
      plane.position.set(st.t.x + dirX * along, 170, st.t.y + dirZ * along);
      plane.rotation.set(0, Math.atan2(dirX, dirZ), Math.sin(time * 4) * 0.1);
      if (k > 0.55 && Math.random() < 0.5) puff(plane.position.x, 160, plane.position.z, '#ffffff', 14, 0.6, 0);
    }

    updateFx(dt, towers);
    renderer.render(scene, camera);
  };

  // ---------- Screen <-> field ----------
  api.project = (x, y, h = 0) => {
    v3.set(x, h, y).project(camera);
    return { x: (v3.x + 1) / 2 * W, y: (1 - v3.y) / 2 * H };
  };
  api.ground = (sx, sy) => {
    raycaster.setFromCamera({ x: (sx / W) * 2 - 1, y: -(sy / H) * 2 + 1 }, camera);
    const hit = raycaster.ray.intersectPlane(groundPlane, v3);
    return hit ? { x: hit.x, y: hit.z } : null;
  };
  api.towerTop = t => models.get(t.id)?.top || 60;
  // Where a tower is on screen (its middle) and how big it looks
  api.towerScreen = t => {
    const top = api.towerTop(t);
    const c = api.project(t.x, t.y, top * 0.5);
    const e = api.project(t.x + towerRadius(t), t.y, top * 0.5);
    const tp = api.project(t.x, t.y, top);
    return { x: c.x, y: c.y, r: Math.abs(e.x - c.x), topY: tp.y, topX: tp.x };
  };
  api.pxPerUnit = (x, y) => {
    const a = api.project(x, y, 0), b = api.project(x + 100, y, 0);
    return Math.abs(b.x - a.x) / 100;
  };
  return api;
})();
