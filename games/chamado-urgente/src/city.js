import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';
import { toonMat } from './toon.js';

// Cidade-maquete em volta do prédio. O escritório é o 7º andar (y = 0); a rua fica em y = GROUND.
// Direção de arte: paleta pastel, toon, formas simples com relevo (sacadas, coroas, toldos),
// sombra de contato por cor de vértice; o desfoque tilt-shift (main.js) faz o resto.
export const GROUND = -28;
const G = GROUND;

function rng(seed) {
  return () => { seed |= 0; seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}
const canvas = (w, h) => { const c = document.createElement('canvas'); c.width = w; c.height = h; return [c, c.getContext('2d')]; };
const ctex = (c, rep = true) => { const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; if (rep) t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 8; return t; };

// ---------------------------------------------------------------- fachadas
// cada repetição = 1 andar (3,5 m) x 1 módulo (3 m)
function facade(kind, seed) {
  const R = rng(seed);
  const W = 128, H = 150;
  const [c, g] = canvas(W, H); const [e, ge] = canvas(W, H);
  ge.fillStyle = '#000'; ge.fillRect(0, 0, W, H);
  const glass = (x, y, w, h) => {
    const grd = g.createLinearGradient(x, y, x + w, y + h);
    grd.addColorStop(0, '#d3ecff'); grd.addColorStop(0.5, '#8fb9e0'); grd.addColorStop(1, '#6a92c0');
    g.fillStyle = grd; g.fillRect(x, y, w, h);
    g.fillStyle = 'rgba(255,255,255,0.45)'; g.beginPath(); g.moveTo(x + w * 0.15, y); g.lineTo(x + w * 0.45, y); g.lineTo(x + w * 0.1, y + h); g.lineTo(x, y + h); g.lineTo(x, y + h * 0.5); g.fill();
    if (R() < 0.5) { ge.fillStyle = R() < 0.8 ? '#ffd08a' : '#d8ecff'; ge.fillRect(x, y, w, h); }
  };
  if (kind === 'punched') { // predinho: parede + janela com moldura branca e peitoril
    g.fillStyle = '#ffffff'; g.fillRect(0, 0, W, H);
    g.fillStyle = 'rgba(0,0,0,0.05)'; for (let y = 0; y < H; y += 10) g.fillRect(0, y, W, 1);
    const x = 30, y = 30, w = 68, h = 80;
    g.fillStyle = '#f4f1ea'; g.fillRect(x - 7, y - 7, w + 14, h + 14);
    glass(x, y, w, h);
    g.fillStyle = '#f4f1ea'; g.fillRect(x + w / 2 - 3, y, 6, h); g.fillRect(x, y + h * 0.4, w, 5);
    g.fillStyle = 'rgba(0,0,0,0.22)'; g.fillRect(x - 10, y + h + 7, w + 20, 7);
    g.fillStyle = '#f4f1ea'; g.fillRect(x - 10, y + h + 3, w + 20, 6);
  } else if (kind === 'glass') { // pele de vidro
    g.fillStyle = '#e9eef5'; g.fillRect(0, 0, W, H);
    glass(4, 4, W - 8, H - 30);
    g.fillStyle = '#5d6b8a'; g.fillRect(0, 0, 4, H); g.fillRect(W / 2 - 2, 4, 4, H - 30);
    g.fillStyle = '#ffffff'; g.fillRect(0, H - 26, W, 26);
    g.fillStyle = 'rgba(0,0,0,0.12)'; g.fillRect(0, H - 26, W, 3);
  } else { // residencial: porta-janela alta
    g.fillStyle = '#ffffff'; g.fillRect(0, 0, W, H);
    const x = 26, y = 18, w = 76, h = 110;
    g.fillStyle = '#f4f1ea'; g.fillRect(x - 6, y - 6, w + 12, h + 12);
    glass(x, y, w, h);
    g.fillStyle = '#f4f1ea'; g.fillRect(x + w / 2 - 3, y, 6, h);
    const cols = ['#ff9b7a', '#7ad1c1', '#ffd36b', '#9fb4ff', '#ffffff'];
    if (R() < 0.7) { g.fillStyle = cols[Math.floor(R() * cols.length)]; g.fillRect(x, y, w, 22); g.fillStyle = 'rgba(0,0,0,0.15)'; for (let i = 0; i < w; i += 8) g.fillRect(x + i, y, 3, 22); }
  }
  return { map: ctex(c), emap: ctex(e) };
}

function sidewalkTex() {
  const [c, g] = canvas(128, 128);
  g.fillStyle = '#e6dccb'; g.fillRect(0, 0, 128, 128);
  g.strokeStyle = 'rgba(120,100,80,0.25)'; g.lineWidth = 2;
  for (let i = 0; i <= 128; i += 32) { g.beginPath(); g.moveTo(i, 0); g.lineTo(i, 128); g.moveTo(0, i); g.lineTo(128, i); g.stroke(); }
  for (let i = 0; i < 300; i++) { g.fillStyle = `rgba(0,0,0,${Math.random() * 0.04})`; g.fillRect(Math.random() * 128, Math.random() * 128, 3, 3); }
  return ctex(c);
}
function roadTex() {
  const [c, g] = canvas(128, 256);
  g.fillStyle = '#4b5366'; g.fillRect(0, 0, 128, 256);
  for (let i = 0; i < 500; i++) { g.fillStyle = `rgba(255,255,255,${Math.random() * 0.05})`; g.fillRect(Math.random() * 128, Math.random() * 256, 2, 2); }
  g.fillStyle = '#ffffff'; g.fillRect(61, 0, 6, 120);
  g.fillStyle = 'rgba(255,255,255,0.8)'; g.fillRect(6, 0, 4, 256); g.fillRect(118, 0, 4, 256);
  return ctex(c);
}
function grassTex() {
  const [c, g] = canvas(128, 128);
  g.fillStyle = '#9ad37d'; g.fillRect(0, 0, 128, 128);
  for (let i = 0; i < 500; i++) { g.fillStyle = Math.random() < 0.5 ? 'rgba(60,130,60,0.25)' : 'rgba(220,255,170,0.25)'; g.fillRect(Math.random() * 128, Math.random() * 128, 2, 4); }
  return ctex(c);
}
function billboardTex(lines, bg, fg) {
  const [c, g] = canvas(512, 256);
  g.fillStyle = bg; g.fillRect(0, 0, 512, 256);
  g.fillStyle = fg; g.textAlign = 'center'; g.textBaseline = 'middle';
  g.font = 'bold 76px Fredoka, sans-serif'; g.fillText(lines[0], 256, 96);
  g.font = 'bold 40px Fredoka, sans-serif'; g.fillText(lines[1], 256, 186);
  g.strokeStyle = fg; g.lineWidth = 12; g.strokeRect(6, 6, 500, 244);
  return ctex(c, false);
}

// caixa com UV em módulos de fachada (u por 3 m, v por andar)
function facadeBox(w, h, d) {
  const g = new THREE.BoxGeometry(w, h, d);
  const uv = g.attributes.uv;
  const dims = [[d, h], [d, h], [w, d], [w, d], [w, h], [w, h]];
  for (let f = 0; f < 6; f++) for (let k = 0; k < 4; k++) {
    const i = f * 4 + k;
    uv.setXY(i, uv.getX(i) * Math.max(1, Math.round(dims[f][0] / 3)), uv.getY(i) * (dims[f][1] / 3.5));
  }
  return g;
}

// ---------------------------------------------------------------- lote de geometria estática
class Batch {
  constructor() { this.parts = new Map(); this._m = new THREE.Matrix4(); }
  // ao: escurece perto do chão (sombra de contato falsa)
  add(geo, key, x = 0, y = 0, z = 0, ry = 0, sx = 1, sy = 1, sz = 1, ao = true) {
    const g = geo.index ? geo.toNonIndexed() : geo.clone();
    g.clearGroups();
    this._m.compose(new THREE.Vector3(x, y, z), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, ry, 0)), new THREE.Vector3(sx, sy, sz));
    g.applyMatrix4(this._m);
    const pos = g.attributes.position;
    const col = new Float32Array(pos.count * 3);
    for (let i = 0; i < pos.count; i++) {
      const k = ao ? 0.6 + 0.4 * Math.min(1, Math.max(0, (pos.getY(i) - G) / 7)) : 1;
      col[i * 3] = col[i * 3 + 1] = col[i * 3 + 2] = k;
    }
    g.setAttribute('color', new THREE.BufferAttribute(col, 3));
    for (const a of Object.keys(g.attributes)) if (!['position', 'normal', 'uv', 'color'].includes(a)) g.deleteAttribute(a);
    if (!this.parts.has(key)) this.parts.set(key, []);
    this.parts.get(key).push(g);
  }
  build(materials, parent) {
    for (const [k, list] of this.parts) {
      const mesh = new THREE.Mesh(mergeGeometries(list, false), materials[k]);
      mesh.receiveShadow = true; mesh.matrixAutoUpdate = false; mesh.updateMatrix();
      parent.add(mesh);
    }
  }
}

const BOX = new THREE.BoxGeometry(1, 1, 1);
const CYL = new THREE.CylinderGeometry(0.5, 0.5, 1, 14);
const CYL6 = new THREE.CylinderGeometry(0.5, 0.5, 1, 6);
const BALL = new THREE.IcosahedronGeometry(1, 2);
const CONE = new THREE.ConeGeometry(1, 1, 8);
const DISC = new THREE.CircleGeometry(1, 20).rotateX(-Math.PI / 2);

// paleta pastel (fachadas)
const WALLS = [0xf6e3c6, 0xf2b8a2, 0xc9e2c4, 0xbfd6ee, 0xf8d78a, 0xe7c5e8, 0xf4efe6, 0xffc7a8, 0xb8e0dc];
const GLASS = [0xcfe6f5, 0xd9e8f0, 0xc2dcef];

export class City {
  constructor(scene) {
    this.scene = scene;
    this.group = new THREE.Group();
    scene.add(this.group);
    const R = rng(21);

    // céu
    this.skyU = {
      top: { value: new THREE.Color(0x5aa8ff) }, horizon: { value: new THREE.Color(0xd9efff) },
      bottom: { value: new THREE.Color(0x9ab0c8) }, sunDir: { value: new THREE.Vector3(0, 1, 0) }, sunColor: { value: new THREE.Color(0xfff2c0) },
    };
    const sky = new THREE.Mesh(new THREE.SphereGeometry(900, 32, 16), new THREE.ShaderMaterial({
      uniforms: this.skyU, side: THREE.BackSide, depthWrite: false, fog: false,
      vertexShader: 'varying vec3 vP; void main(){ vP = normalize(position); gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
      fragmentShader: `uniform vec3 top, horizon, bottom, sunDir, sunColor; varying vec3 vP;
        void main(){ float h = vP.y;
          vec3 c = h > 0.0 ? mix(horizon, top, pow(clamp(h,0.0,1.0), 0.6)) : mix(horizon, bottom, pow(clamp(-h*3.0,0.0,1.0), 0.7));
          float s = max(dot(vP, normalize(sunDir)), 0.0);
          c += sunColor * (pow(s, 600.0) * 4.0 + pow(s, 12.0) * 0.35);
          gl_FragColor = vec4(c, 1.0); }`,
    }));
    sky.frustumCulled = false;
    this.group.add(sky);

    // ---------- materiais
    const T = (p) => toonMat({ vertexColors: true, ...p });
    const mats = {};
    this.winMats = [];
    const fac = { punched: [facade('punched', 3), facade('punched', 9)], glass: [facade('glass', 5)], res: [facade('res', 7), facade('res', 13)] };
    WALLS.forEach((c, i) => {
      for (const kind of ['punched', 'res']) {
        const f = fac[kind][i % fac[kind].length];
        const m = T({ color: c, map: f.map, emissive: 0xffffff, emissiveMap: f.emap, emissiveIntensity: 0 });
        mats[kind + i] = m; this.winMats.push(m);
      }
    });
    GLASS.forEach((c, i) => { const m = T({ color: c, map: fac.glass[0].map, emissive: 0xffffff, emissiveMap: fac.glass[0].emap, emissiveIntensity: 0 }); mats['glass' + i] = m; this.winMats.push(m); });
    const plain = { roof: 0xb9b3aa, roofDark: 0x8d8a92, trim: 0xfbf7ef, dark: 0x3b4566, metal: 0xd5dae3, red: 0xff7b6b, yellow: 0xffd36b, teal: 0x5cc8b8, blue: 0x6fa8ff, pink: 0xff9bb8, white: 0xffffff, trunk: 0x9a6a44, leaf: 0x6cc36e, leaf2: 0x4fae66, leaf3: 0xf0b75a, leaf4: 0x8fd48a, water: 0x7ccdf0, bench: 0xc98f5a, solar: 0x3a5a9a, planter: 0xd8c8b0, curb: 0xf4efe6 };
    for (const [k, c] of Object.entries(plain)) mats[k] = T({ color: c });
    mats.side = T({ map: sidewalkTex() });
    mats.grass = T({ map: grassTex() });
    this.lampMat = T({ color: 0xfff2c0, emissive: 0xffc46b, emissiveIntensity: 0 }); mats.lamp = this.lampMat;
    mats.blob = new THREE.MeshBasicMaterial({ color: 0x1d2540, transparent: true, opacity: 0.22, depthWrite: false });
    this.mats = mats;

    const B = new Batch();
    const S = new Batch(); // sombras-blob

    // ---------- chão e ruas
    const ground = new THREE.Mesh(new THREE.PlaneGeometry(1600, 1600), toonMat({ color: 0x9bbf88 }));
    ground.rotation.x = -Math.PI / 2; ground.position.y = G - 0.08; ground.receiveShadow = true; this.group.add(ground);
    const SX = [-26, 26, -80, 80, -134, 134], SZ = [-24, 22, -78, 76, -132];
    const RW = 10;
    const rt = roadTex();
    const rz = rt.clone(); rz.repeat.set(1, 50); rz.needsUpdate = true;
    const rx = rt.clone(); rx.repeat.set(1, 50); rx.needsUpdate = true;
    for (const x of SX) { const m = new THREE.Mesh(new THREE.PlaneGeometry(RW, 500), toonMat({ map: rz })); m.rotation.x = -Math.PI / 2; m.position.set(x, G, -60); m.receiveShadow = true; this.group.add(m); }
    for (const z of SZ) { const m = new THREE.Mesh(new THREE.PlaneGeometry(RW, 500), toonMat({ map: rx })); m.rotation.x = -Math.PI / 2; m.rotation.z = Math.PI / 2; m.position.set(0, G + 0.01, z); m.receiveShadow = true; this.group.add(m); }
    // cruzamentos + faixas de pedestre
    for (const x of SX) for (const z of SZ) {
      B.add(BOX, 'dark', x, G + 0.015, z, 0, RW, 0.01, RW, false);
      for (let i = -3; i <= 3; i++) {
        B.add(BOX, 'white', x + i * 1.3, G + 0.03, z + RW / 2 + 1.4, 0, 0.7, 0.02, 2.4, false);
        B.add(BOX, 'white', x + i * 1.3, G + 0.03, z - RW / 2 - 1.4, 0, 0.7, 0.02, 2.4, false);
        B.add(BOX, 'white', x + RW / 2 + 1.4, G + 0.03, z + i * 1.3, 0, 2.4, 0.02, 0.7, false);
        B.add(BOX, 'white', x - RW / 2 - 1.4, G + 0.03, z + i * 1.3, 0, 2.4, 0.02, 0.7, false);
      }
    }

    // ---------- quarteirões
    const xs = [-260, ...SX.slice().sort((a, b) => a - b), 260];
    const zs = [-260, ...SZ.slice().sort((a, b) => a - b), 200];
    for (let i = 0; i < xs.length - 1; i++) for (let j = 0; j < zs.length - 1; j++) {
      const x0 = xs[i] + RW / 2, x1 = xs[i + 1] - RW / 2, z0 = zs[j] + RW / 2, z1 = zs[j + 1] - RW / 2;
      const cx = (x0 + x1) / 2, cz = (z0 + z1) / 2, w = x1 - x0, d = z1 - z0;
      B.add(BOX, 'curb', cx, G + 0.15, cz, 0, w, 0.3, d, false);
      B.add(BOX, 'side', cx, G + 0.16, cz, 0, w - 0.4, 0.3, d - 0.4, false);
      if (cx > -26 && cx < 26 && cz > -24 && cz < 22) { this.plaza(B, S, R); continue; }
      const dist = Math.hypot(cx, cz * 1.3);
      if (((i * 7 + j * 3) % 6 === 1 && dist < 220) || (cz > 30 && dist < 120 && R() < 0.5)) { this.park(B, S, cx, cz, w, d, R); continue; }
      for (let t = x0 + 4; t < x1 - 2; t += 9) { this.tree(B, S, t, z1 - 1.6, 0.7, R); this.tree(B, S, t, z0 + 1.6, 0.7, R); }
      const nx = Math.max(1, Math.round(w / 22)), nz = Math.max(1, Math.round(d / 22));
      for (let a = 0; a < nx; a++) for (let b = 0; b < nz; b++) {
        const lw = (w - 6) / nx, ld = (d - 6) / nz;
        const lx = x0 + 3 + lw * (a + 0.5), lz = z0 + 3 + ld * (b + 0.5);
        const bw = lw - 2 - R() * 3, bd = ld - 2 - R() * 3;
        // perto do escritório, prédios baixos (dá para ver os telhados); ao fundo, torres
        const back = lz < -30;
        const far = Math.hypot(lx, lz) > 120;
        let floors;
        if (lz > 18) floors = 2 + Math.floor(R() * 3);
        else if (!back && Math.abs(lx) < 60) floors = 3 + Math.floor(R() * 3);
        else if (back && lz > -80 && Math.abs(lx) < 50) floors = 4 + Math.floor(R() * 4);
        else floors = far ? 8 + Math.floor(R() * 14) : 5 + Math.floor(R() * 8);
        this.building(B, lx, lz, bw, bd, floors, R);
      }
    }
    B.build(mats, this.group);
    S.build(mats, this.group);
    this.homeTower();
    this.billboards();

    this.cars = []; this.peds = []; this.birds = [];
    this.spawnCars(R, SX, SZ);
    this.spawnPeds(R, SX, SZ);
    this.spawnClouds(R);
    this.spawnBirds(R);
    this.eve = 0;
  }

  // ---------------------------------------------------------------- prédios
  building(B, x, z, w, d, floors, R) {
    const h = floors * 3.5 + 1;
    const r = R();
    const kind = floors >= 9 && r < 0.6 ? 'glass' : r < 0.55 ? 'punched' : 'res';
    const ci = Math.floor(R() * (kind === 'glass' ? GLASS.length : WALLS.length));
    const key = kind + ci;
    const top = G + h;
    // térreo com vitrine e toldo
    B.add(BOX, kind === 'glass' ? 'dark' : 'trim', x, G + 2.2, z, 0, w + 0.3, 4.4, d + 0.3);
    const awn = ['red', 'yellow', 'teal', 'blue', 'pink'][Math.floor(R() * 5)];
    B.add(BOX, awn, x, G + 3.7, z + d / 2 + 0.9, 0, w * 0.8, 0.25, 1.8);
    B.add(BOX, 'dark', x, G + 1.6, z + d / 2 + 0.16, 0, w * 0.72, 2.6, 0.1);
    if (kind === 'glass' && floors > 12 && R() < 0.7) {
      // torre com recuo: corpo + coroa menor
      const h1 = h * 0.7;
      B.add(facadeBox(w, h1 - 4.4, d), key, x, G + 4.4 + (h1 - 4.4) / 2, z);
      B.add(BOX, 'trim', x, G + h1 + 0.25, z, 0, w + 0.6, 0.5, d + 0.6);
      const w2 = w * 0.7, d2 = d * 0.7, h2 = h - h1;
      B.add(facadeBox(w2, h2, d2), key, x, G + h1 + h2 / 2, z);
      B.add(BOX, 'trim', x, top + 0.3, z, 0, w2 + 0.6, 0.6, d2 + 0.6);
      B.add(CYL6, 'metal', x, top + 4, z, 0, 0.3, 8, 0.3);
      B.add(BALL, 'red', x, top + 8.2, z, 0, 0.35, 0.35, 0.35);
      return;
    }
    B.add(facadeBox(w, h - 4.4, d), key, x, G + 4.4 + (h - 4.4) / 2, z);
    if (kind !== 'glass') for (let f = 1; f < floors; f++) B.add(BOX, 'trim', x, G + 4.4 + f * 3.5 - 0.05, z, 0, w + 0.25, 0.22, d + 0.25);
    if (kind === 'res') {
      for (let f = 1; f < floors; f++) for (let m = -w / 2 + 1.5; m < w / 2 - 1; m += 3) {
        if (R() < 0.35) continue;
        B.add(BOX, 'trim', x + m, G + 4.4 + f * 3.5 - 3.2, z + d / 2 + 0.55, 0, 2.4, 0.18, 1.1);
        B.add(BOX, 'white', x + m, G + 4.4 + f * 3.5 - 2.65, z + d / 2 + 1.05, 0, 2.4, 0.9, 0.08);
      }
    }
    B.add(BOX, 'roof', x, top - 0.05, z, 0, w - 0.2, 0.2, d - 0.2, false);
    for (const [ox, oz, sw, sd] of [[0, d / 2, w + 0.3, 0.4], [0, -d / 2, w + 0.3, 0.4], [w / 2, 0, 0.4, d], [-w / 2, 0, 0.4, d]]) B.add(BOX, 'trim', x + ox, top + 0.35, z + oz, 0, sw, 0.7, sd, false);
    this.rooftop(B, x, z, w, d, top, R);
  }

  rooftop(B, x, z, w, d, top, R) {
    const used = [];
    const n = 2 + Math.floor(R() * 4);
    for (let i = 0; i < n; i++) {
      const px = x + (R() - 0.5) * (w - 5), pz = z + (R() - 0.5) * (d - 5);
      if (used.some(([a, b]) => Math.hypot(a - px, b - pz) < 3.5)) continue;
      used.push([px, pz]);
      const t = R();
      if (t < 0.22) { // ar-condicionado
        B.add(BOX, 'metal', px, top + 0.6, pz, 0, 2, 1.2, 1.4); B.add(CYL, 'dark', px, top + 1.22, pz, 0, 1.1, 0.06, 1.1);
      } else if (t < 0.4) { // caixa d'água
        B.add(CYL, 'trim', px, top + 2.1, pz, 0, 2.4, 2.0, 2.4);
        B.add(CONE, 'roofDark', px, top + 3.4, pz, 0, 1.3, 0.6, 1.3);
        for (const [a, b] of [[-0.8, -0.8], [0.8, 0.8], [-0.8, 0.8], [0.8, -0.8]]) B.add(BOX, 'dark', px + a, top + 0.55, pz + b, 0, 0.18, 1.1, 0.18);
      } else if (t < 0.55) { // painéis solares
        for (let k = 0; k < 3; k++) { const p = new THREE.BoxGeometry(1.6, 0.08, 1.0).rotateX(-0.35); B.add(p, 'solar', px - 1.8 + k * 1.8, top + 0.55, pz); B.add(BOX, 'metal', px - 1.8 + k * 1.8, top + 0.25, pz, 0, 0.1, 0.5, 0.1); }
      } else if (t < 0.75) { // jardim
        B.add(BOX, 'planter', px, top + 0.3, pz, 0, 4, 0.6, 2.6);
        B.add(BOX, 'grass', px, top + 0.62, pz, 0, 3.6, 0.06, 2.2, false);
        for (let k = 0; k < 3; k++) B.add(BALL, ['leaf', 'leaf2', 'leaf4'][k], px - 1.2 + k * 1.2, top + 1.2, pz + (R() - 0.5) * 0.6, 0, 0.6, 0.6, 0.6);
      } else if (t < 0.87) { // casinha da escada
        B.add(BOX, 'trim', px, top + 1.4, pz, 0, 2.4, 2.8, 2.2); B.add(BOX, 'dark', px, top + 1.1, pz + 1.12, 0, 0.9, 1.9, 0.05);
      } else { // antena
        B.add(CYL6, 'metal', px, top + 2.5, pz, 0, 0.14, 5, 0.14); B.add(BALL, 'red', px, top + 5.1, pz, 0, 0.18, 0.18, 0.18);
      }
    }
  }

  tree(B, S, x, z, s, R) {
    B.add(CYL6, 'trunk', x, G + 0.3 + 1.0 * s, z, 0, 0.32 * s, 2.0 * s, 0.32 * s);
    const leaf = ['leaf', 'leaf2', 'leaf4', 'leaf', 'leaf3'][Math.floor(R() * 5)];
    if (R() < 0.25) B.add(CONE, leaf, x, G + 3.2 * s, z, 0, 1.4 * s, 3.4 * s, 1.4 * s);
    else {
      B.add(BALL, leaf, x, G + 2.9 * s, z, 0, 1.45 * s, 1.35 * s, 1.45 * s);
      B.add(BALL, leaf, x + 0.5 * s, G + 3.5 * s, z + 0.2 * s, 0, 0.95 * s, 0.9 * s, 0.95 * s);
    }
    S.add(DISC, 'blob', x + 0.3, G + 0.33, z + 0.2, 0, 1.6 * s, 1, 1.6 * s, false);
  }

  bench(B, x, z, ry) {
    B.add(BOX, 'bench', x, G + 0.75, z, ry, 1.8, 0.12, 0.6);
    B.add(BOX, 'bench', x - Math.sin(ry) * 0.3, G + 1.1, z - Math.cos(ry) * 0.3, ry, 1.8, 0.5, 0.1);
    for (const s of [-0.7, 0.7]) B.add(BOX, 'dark', x + Math.cos(ry) * s, G + 0.5, z - Math.sin(ry) * s, ry, 0.1, 0.5, 0.5);
  }

  lamp(B, x, z) {
    B.add(CYL6, 'dark', x, G + 2.8, z, 0, 0.18, 5.2, 0.18);
    B.add(BALL, 'lamp', x, G + 5.5, z, 0, 0.45, 0.45, 0.45);
    B.add(CYL, 'dark', x, G + 5.9, z, 0, 0.6, 0.12, 0.6);
  }

  park(B, S, cx, cz, w, d, R) {
    B.add(BOX, 'grass', cx, G + 0.33, cz, 0, w - 3, 0.06, d - 3, false);
    const r = Math.min(w, d) * 0.16;
    if (R() < 0.75) {
      B.add(CYL, 'curb', cx, G + 0.5, cz, 0, r * 2.3, 0.4, r * 2.3);
      B.add(CYL, 'water', cx, G + 0.66, cz, 0, r * 2, 0.1, r * 2, false);
      B.add(CYL, 'curb', cx, G + 1.2, cz, 0, 0.8, 1.6, 0.8);
    }
    B.add(BOX, 'side', cx, G + 0.34, cz, 0, w - 3, 0.06, 2.2, false);
    B.add(BOX, 'side', cx, G + 0.345, cz, 0, 2.2, 0.06, d - 3, false);
    const n = Math.floor((w * d) / 70);
    for (let i = 0; i < n; i++) {
      const x = cx + (R() - 0.5) * (w - 8), z = cz + (R() - 0.5) * (d - 8);
      if (Math.hypot(x - cx, z - cz) < r * 1.6 || Math.abs(x - cx) < 2 || Math.abs(z - cz) < 2) continue;
      this.tree(B, S, x, z, 0.8 + R() * 0.6, R);
    }
    this.bench(B, cx + 4, cz + 2.2, 0); this.bench(B, cx - 4, cz - 2.2, Math.PI);
  }

  plaza(B, S, R) {
    // praça em volta do prédio: canteiros, árvores, bancos, postes, quiosque
    for (const s of [-1, 1]) {
      const px = 17.5 * s;
      B.add(BOX, 'planter', px, G + 0.55, -3, 0, 4.5, 0.5, 22);
      B.add(BOX, 'grass', px, G + 0.82, -3, 0, 4.1, 0.06, 21.6, false);
      for (let z = -12; z <= 6; z += 4.5) this.tree(B, S, px, z, 0.85 + R() * 0.25, R);
      this.bench(B, 14.2 * s, -9, s > 0 ? -Math.PI / 2 : Math.PI / 2);
      this.bench(B, 14.2 * s, 3, s > 0 ? -Math.PI / 2 : Math.PI / 2);
      this.lamp(B, 14.6 * s, -14); this.lamp(B, 14.6 * s, 9);
    }
    for (let x = -18; x <= 18; x += 6) this.tree(B, S, x, -17.5, 0.8, R);
    for (let k = 0; k < 4; k++) B.add(new THREE.TorusGeometry(0.4, 0.05, 6, 12, Math.PI), 'dark', -6 + k * 0.8, G + 0.3, 13.8, Math.PI / 2);
    B.add(BOX, 'yellow', 8, G + 1.3, 15, 0, 3, 2.2, 2); B.add(BOX, 'red', 8, G + 2.6, 15.2, 0, 3.6, 0.25, 2.6);
  }

  // ---------------------------------------------------------------- prédio do escritório
  homeTower() {
    const w = 25.6, d = 16.8, h = -1.2 - G;
    const f = facade('punched', 17);
    const m = toonMat({ color: 0xf2e6d4, map: f.map, emissive: 0xffffff, emissiveMap: f.emap, emissiveIntensity: 0 });
    this.winMats.push(m);
    const tower = new THREE.Mesh(facadeBox(w, h - 4.4, d), m);
    tower.position.set(0, G + 4.4 + (h - 4.4) / 2, 0); tower.receiveShadow = true;
    this.group.add(tower);
    const trim = toonMat({ color: 0xfbf7ef });
    for (let i = 0; i < 7; i++) {
      const s = new THREE.Mesh(new THREE.BoxGeometry(w + 0.35, 0.28, d + 0.35), trim);
      s.position.set(0, G + 4.4 + i * 3.5, 0); this.group.add(s);
    }
    const base = new THREE.Mesh(new THREE.BoxGeometry(w + 0.6, 4.4, d + 0.6), toonMat({ color: 0x3b4566 }));
    base.position.set(0, G + 2.2, 0); this.group.add(base);
    const glassDoor = new THREE.Mesh(new THREE.BoxGeometry(8, 3.2, 0.2), toonMat({ color: 0x9fd0f0 }));
    glassDoor.position.set(0, G + 1.7, d / 2 + 0.25); this.group.add(glassDoor);
    const awn = new THREE.Mesh(new THREE.BoxGeometry(11, 0.35, 3.2), toonMat({ color: 0xff7b6b }));
    awn.position.set(0, G + 4.0, d / 2 + 1.6); this.group.add(awn);
    const [c, g] = canvas(1024, 160);
    g.fillStyle = '#1d2540'; g.beginPath(); g.roundRect(4, 4, 1016, 152, 40); g.fill();
    g.fillStyle = '#ffd23f'; g.font = 'bold 96px Fredoka, sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle';
    g.fillText('CONTÁBIL & CIA', 512, 84);
    const sign = new THREE.Mesh(new THREE.PlaneGeometry(11, 1.7), new THREE.MeshBasicMaterial({ map: ctex(c, false) }));
    sign.position.set(0, -2.7, d / 2 + 0.25); this.group.add(sign);
    this.signMat = sign.material;
  }

  billboards() {
    const ads = [
      [['TI SOFRE?', 'Ligue 0800-REINICIA'], '#ffd23f', '#1d2540', -40, G + 26, -42, 0.25],
      [['Wi-Fi GRÁTIS', '(senha: 12345678)'], '#ff7b6b', '#ffffff', 44, G + 22, -38, -0.3],
      [['CAFÉ DO ZÉ', 'o combustível da TI'], '#5cc8b8', '#1d2540', -8, G + 30, -96, 0],
    ];
    for (const [lines, bg, fg, x, y, z, ry] of ads) {
      const g = new THREE.Group();
      const board = new THREE.Mesh(new THREE.PlaneGeometry(10, 5), new THREE.MeshBasicMaterial({ map: billboardTex(lines, bg, fg) }));
      board.position.y = 4; g.add(board);
      const back = new THREE.Mesh(new THREE.BoxGeometry(10.4, 5.4, 0.3), toonMat({ color: 0x3b4566 })); back.position.set(0, 4, -0.2); g.add(back);
      for (const s of [-3, 3]) { const p = new THREE.Mesh(new THREE.BoxGeometry(0.3, 2, 0.3), toonMat({ color: 0x3b4566 })); p.position.set(s, 0.5, -0.2); g.add(p); }
      g.position.set(x, y, z); g.rotation.y = ry;
      this.group.add(g);
    }
  }

  // ---------------------------------------------------------------- vida
  spawnCars(R, SX, SZ) {
    const cols = [0xff6b6b, 0x5b8cff, 0xffd36b, 0x4fc98a, 0xf4efe6, 0x3b4566, 0xff9b54, 0x7ad1c1, 0xc98bff];
    const glassM = toonMat({ color: 0x9fd8ff });
    const wheelM = toonMat({ color: 0x1d2540 });
    const blobM = new THREE.MeshBasicMaterial({ color: 0x1d2540, transparent: true, opacity: 0.25, depthWrite: false });
    const mk = (col, kind) => {
      const g = new THREE.Group();
      const bodyM = toonMat({ color: col });
      const L = kind === 'bus' ? 9 : kind === 'van' ? 4.6 : 4;
      const body = new THREE.Mesh(new THREE.BoxGeometry(2, kind === 'bus' ? 2.6 : 0.8, L), bodyM);
      body.position.y = kind === 'bus' ? 1.7 : 0.75; g.add(body);
      if (kind === 'bus') {
        const win = new THREE.Mesh(new THREE.BoxGeometry(2.05, 0.9, L - 1), glassM); win.position.y = 2.2; g.add(win);
      } else {
        const cab = new THREE.Mesh(new THREE.BoxGeometry(1.8, kind === 'van' ? 1.1 : 0.75, kind === 'van' ? 3.2 : 2.1), glassM);
        cab.position.set(0, kind === 'van' ? 1.6 : 1.45, kind === 'van' ? -0.4 : -0.2); g.add(cab);
        const roof = new THREE.Mesh(new THREE.BoxGeometry(1.85, 0.12, kind === 'van' ? 3.2 : 1.9), bodyM); roof.position.set(0, kind === 'van' ? 2.2 : 1.86, kind === 'van' ? -0.4 : -0.2); g.add(roof);
        if (kind === 'taxi') { const t = new THREE.Mesh(new THREE.BoxGeometry(0.7, 0.28, 0.3), toonMat({ color: 0xffffff, emissive: 0xffd23f, emissiveIntensity: 0.5 })); t.position.set(0, 2.05, -0.2); g.add(t); }
      }
      for (const z of [L / 2 - 0.9, -L / 2 + 0.9]) for (const x of [-0.95, 0.95]) { const w = new THREE.Mesh(new THREE.CylinderGeometry(0.42, 0.42, 0.32, 12), wheelM); w.rotation.z = Math.PI / 2; w.position.set(x, 0.42, z); g.add(w); }
      const hl = toonMat({ color: 0xfff6d0, emissive: 0xfff2b0, emissiveIntensity: 0.3 });
      for (const x of [-0.65, 0.65]) { const l = new THREE.Mesh(new THREE.BoxGeometry(0.4, 0.22, 0.06), hl); l.position.set(x, 0.85, L / 2 + 0.01); g.add(l); }
      const blob = new THREE.Mesh(new THREE.PlaneGeometry(2.6, L + 0.6), blobM); blob.rotation.x = -Math.PI / 2; blob.position.y = 0.05; g.add(blob);
      g.userData.hl = hl;
      return g;
    };
    for (let i = 0; i < 36; i++) {
      const alongZ = i % 2 === 0;
      const line = alongZ ? SX[Math.floor(R() * 4)] : SZ[Math.floor(R() * 3)];
      const dir = R() < 0.5 ? 1 : -1;
      const kind = R() < 0.08 ? 'bus' : R() < 0.15 ? 'van' : R() < 0.15 ? 'taxi' : 'car';
      const car = mk(kind === 'taxi' ? 0xffd23f : kind === 'bus' ? 0xff7b6b : cols[Math.floor(R() * cols.length)], kind);
      const lane = line + dir * 2.4 * (alongZ ? -1 : 1);
      const s = (R() - 0.5) * 400;
      car.position.set(alongZ ? lane : s, G, alongZ ? s : lane);
      car.rotation.y = alongZ ? (dir > 0 ? 0 : Math.PI) : (dir > 0 ? Math.PI / 2 : -Math.PI / 2);
      this.group.add(car);
      this.cars.push({ mesh: car, alongZ, dir, speed: kind === 'bus' ? 7 : 9 + R() * 7, phase: R() * 10 });
    }
  }

  spawnPeds(R, SX, SZ) {
    const cols = [0xff6b6b, 0x5b8cff, 0xffd36b, 0x4fc98a, 0xc98bff, 0xff9b54, 0xf4efe6, 0x7ad1c1];
    const skins = [0xf2c29b, 0x9a6440, 0xc68a5e, 0xf6d2b5];
    const capG = new THREE.CapsuleGeometry(0.3, 0.45, 4, 8), headG = new THREE.SphereGeometry(0.3, 12, 8);
    for (let i = 0; i < 60; i++) {
      const g = new THREE.Group();
      const b = new THREE.Mesh(capG, toonMat({ color: cols[i % cols.length] })); b.position.y = 0.65; g.add(b);
      const h = new THREE.Mesh(headG, toonMat({ color: skins[i % 4] })); h.position.y = 1.4; g.add(h);
      if (i % 4 === 0) { const u = new THREE.Mesh(new THREE.ConeGeometry(0.75, 0.4, 10), toonMat({ color: cols[(i + 3) % cols.length] })); u.position.y = 2.0; g.add(u); }
      if (i % 5 === 1) { const dog = new THREE.Mesh(new THREE.CapsuleGeometry(0.15, 0.35, 4, 8), toonMat({ color: 0xc98f5a })); dog.rotation.x = Math.PI / 2; dog.position.set(0.6, 0.3, 0.4); g.add(dog); }
      const alongZ = i % 2 === 0;
      const line = alongZ ? SX[Math.floor(R() * 4)] : SZ[Math.floor(R() * 3)];
      const off = (R() < 0.5 ? -1 : 1) * 6.6;
      const dir = R() < 0.5 ? 1 : -1;
      const s = (R() - 0.5) * 320;
      g.position.set(alongZ ? line + off : s, G + 0.3, alongZ ? s : line + off);
      g.rotation.y = alongZ ? (dir > 0 ? 0 : Math.PI) : (dir > 0 ? Math.PI / 2 : -Math.PI / 2);
      this.group.add(g);
      this.peds.push({ mesh: g, alongZ, dir, speed: 1.1 + R() * 0.8, phase: R() * 6 });
    }
    // gente sentada nos bancos da praça
    [[14.2, -9], [-14.2, 3], [14.2, 3]].forEach(([x, z], k) => {
      const g = new THREE.Group();
      const b = new THREE.Mesh(capG, toonMat({ color: cols[k + 2] })); b.position.y = 0.95; g.add(b);
      const h = new THREE.Mesh(headG, toonMat({ color: skins[k] })); h.position.y = 1.7; g.add(h);
      g.position.set(x, G + 0.3, z); this.group.add(g);
    });
  }

  spawnClouds(R) {
    this.clouds = [];
    const m = toonMat({ color: 0xffffff, emissive: 0xffffff, emissiveIntensity: 0.25 });
    this.cloudMat = m;
    for (let i = 0; i < 18; i++) {
      const g = new THREE.Group();
      const n = 4 + Math.floor(R() * 4);
      for (let k = 0; k < n; k++) {
        const s = new THREE.Mesh(new THREE.IcosahedronGeometry(1, 2), m);
        const r = 3 + R() * 4;
        s.scale.set(r, r * 0.7, r);
        s.position.set((k - n / 2) * 4 + R() * 2, R() * 2, R() * 3);
        g.add(s);
      }
      g.position.set((R() - 0.5) * 500, 25 + R() * 45, -80 - R() * 300);
      this.group.add(g);
      this.clouds.push({ g, speed: 1.5 + R() * 2.5 });
    }
  }

  spawnBirds(R) {
    const m = new THREE.MeshBasicMaterial({ color: 0x3b4566, side: THREE.DoubleSide });
    for (let i = 0; i < 10; i++) {
      const g = new THREE.Group();
      const body = new THREE.Mesh(new THREE.SphereGeometry(0.18, 8, 6), m); body.scale.set(0.7, 0.7, 1.4); g.add(body);
      const wings = [];
      for (const s of [-1, 1]) {
        const w = new THREE.Group();
        const p = new THREE.Mesh(new THREE.PlaneGeometry(0.8, 0.3), m); p.position.x = 0.4 * s; p.rotation.x = -Math.PI / 2; w.add(p);
        g.add(w); wings.push(w);
      }
      this.group.add(g);
      this.birds.push({ g, wings, r: 14 + R() * 20, h: -14 + R() * 8, speed: 0.2 + R() * 0.15, phase: R() * 6.28, cx: (R() - 0.5) * 60, cz: -55 - R() * 40 });
    }
  }

  // ---------------------------------------------------------------- ciclo do dia (t: 0 = 09h, 1 = 18h)
  setTime(t, L) {
    const smooth = (a, b, x) => { const k = Math.min(1, Math.max(0, (x - a) / (b - a))); return k * k * (3 - 2 * k); };
    const eve = smooth(0.62, 1.0, t);
    const morn = 1 - smooth(0.0, 0.25, t);
    const az = -1.05 + t * 2.1;
    const el = 0.35 + Math.sin(Math.PI * Math.min(1, t * 0.95 + 0.04)) * 0.75 - eve * 0.25;
    const dir = new THREE.Vector3(Math.sin(az) * Math.cos(el), Math.sin(el), Math.cos(az) * Math.cos(el) * 0.75 + 0.25).normalize();
    L.sun.position.copy(dir).multiplyScalar(30);
    const noonC = new THREE.Color(0xfff6ea), mornC = new THREE.Color(0xffe6c0), eveC = new THREE.Color(0xffb886);
    L.sun.color.copy(noonC).lerp(mornC, morn * 0.7).lerp(eveC, eve);
    // toon: luz mais contida (o gradiente já dá contraste)
    L.sun.intensity = 1.7 - eve * 0.35;
    if (L.officeLight) L.officeLight.intensity = 0.25 + eve * 1.4;
    L.hemi.color.set(0xe6efff).lerp(new THREE.Color(0xffd2b0), eve * 0.7);
    L.hemi.groundColor.set(0x8a7a68).lerp(new THREE.Color(0x6a5a78), eve);
    L.hemi.intensity = 1.05 - eve * 0.1;
    const top = new THREE.Color(0x5aa8ff).lerp(new THREE.Color(0x8cc0ff), morn * 0.5).lerp(new THREE.Color(0x5a5fa8), eve);
    const hor = new THREE.Color(0xd8efff).lerp(new THREE.Color(0xffe8cc), morn * 0.6).lerp(new THREE.Color(0xffb27a), eve);
    this.skyU.top.value.copy(top); this.skyU.horizon.value.copy(hor);
    this.skyU.bottom.value.copy(hor).lerp(new THREE.Color(0x9fb4a0), 0.5);
    this.skyU.sunDir.value.copy(dir);
    this.skyU.sunColor.value.copy(L.sun.color);
    if (this.scene.fog) this.scene.fog.color.copy(hor).lerp(new THREE.Color(0xc8dcf0), 0.35);
    const lit = 0.05 + eve * 1.2;
    for (const m of this.winMats) m.emissiveIntensity = lit;
    this.lampMat.emissiveIntensity = smooth(0.78, 0.95, t) * 2.5;
    for (const c of this.cars) c.mesh.userData.hl.emissiveIntensity = 0.3 + eve * 2.2;
    this.cloudMat.color.set(0xffffff).lerp(new THREE.Color(0xffc8a8), eve * 0.8);
    this.eve = eve;
  }

  update(dt, time) {
    for (const c of this.cars) {
      const p = c.mesh.position;
      const slow = 0.6 + 0.4 * Math.max(0, Math.sin(time * 0.35 + c.phase));
      const v = c.speed * slow * dt * c.dir;
      if (c.alongZ) { p.z += v; if (p.z > 220) p.z = -220; if (p.z < -220) p.z = 220; }
      else { p.x += v; if (p.x > 220) p.x = -220; if (p.x < -220) p.x = 220; }
    }
    for (const q of this.peds) {
      const p = q.mesh.position;
      const v = q.speed * dt * q.dir;
      if (q.alongZ) { p.z += v; if (Math.abs(p.z) > 170) p.z *= -0.99; } else { p.x += v; if (Math.abs(p.x) > 170) p.x *= -0.99; }
      q.mesh.children[0].position.y = 0.65 + Math.abs(Math.sin(time * 8 * q.speed + q.phase)) * 0.14;
      q.mesh.rotation.z = Math.sin(time * 8 * q.speed + q.phase) * 0.06;
    }
    for (const c of this.clouds) { c.g.position.x += c.speed * dt; if (c.g.position.x > 260) c.g.position.x = -260; }
    for (const b of this.birds) {
      const a = time * b.speed + b.phase;
      b.g.position.set(b.cx + Math.cos(a) * b.r, b.h + Math.sin(a * 2.3) * 1.5, b.cz + Math.sin(a) * b.r * 0.6);
      b.g.rotation.y = -a;
      const f = Math.sin(time * 14 + b.phase) * 0.7;
      b.wings[0].rotation.z = f; b.wings[1].rotation.z = -f;
    }
  }
}
