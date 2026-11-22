import * as THREE from 'three';
import { mergeGeometries } from 'three/addons/utils/BufferGeometryUtils.js';

// Cidade em volta do prédio: o escritório é o 7º andar (y = 0); a rua fica em y = GROUND.
// Geometria estática é agrupada por material (poucos draw calls). Carros, pedestres,
// nuvens e pássaros se movem. `setTime(t)` controla o ciclo 09h → 18h.
export const GROUND = -28;

function rng(seed) {
  return () => { seed |= 0; seed = (seed + 0x6d2b79f5) | 0; let t = Math.imul(seed ^ (seed >>> 15), 1 | seed); t = (t + Math.imul(t ^ (t >>> 7), 61 | t)) ^ t; return ((t ^ (t >>> 14)) >>> 0) / 4294967296; };
}

// ---------------------------------------------------------------- texturas
function windowTextures(seed = 1, style = 0) {
  // 1 andar (3,5 m) x 2 janelas (6 m) por repetição
  const R = rng(seed);
  const W = 512, H = 256;
  const c = document.createElement('canvas'); c.width = W; c.height = H;
  const g = c.getContext('2d');
  const e = document.createElement('canvas'); e.width = W; e.height = H;
  const ge = e.getContext('2d');
  g.fillStyle = '#ffffff'; g.fillRect(0, 0, W, H);
  // linha de laje e textura leve
  g.fillStyle = 'rgba(0,0,0,0.10)'; g.fillRect(0, H - 22, W, 22);
  g.fillStyle = 'rgba(255,255,255,0.6)'; g.fillRect(0, H - 26, W, 4);
  ge.fillStyle = '#000'; ge.fillRect(0, 0, W, H);
  const n = style === 1 ? 3 : 2;
  const cw = W / n;
  for (let x = 0; x < n; x++) {
    const px = x * cw + cw * 0.14, py = H * 0.16, w = cw * 0.72, h = H * 0.6;
    g.fillStyle = '#3b4566'; g.fillRect(px - 6, py - 6, w + 12, h + 12); // moldura
    const grd = g.createLinearGradient(px, py, px + w * 0.6, py + h);
    grd.addColorStop(0, '#bfe0f7'); grd.addColorStop(0.55, '#7fa6cf'); grd.addColorStop(1, '#55759e');
    g.fillStyle = grd; g.fillRect(px, py, w, h);
    g.fillStyle = 'rgba(255,255,255,0.35)';
    g.beginPath(); g.moveTo(px + w * 0.1, py); g.lineTo(px + w * 0.35, py); g.lineTo(px + w * 0.05, py + h); g.lineTo(px, py + h); g.lineTo(px, py + h * 0.4); g.fill();
    g.fillStyle = '#3b4566'; g.fillRect(px + w / 2 - 3, py, 6, h);
    g.fillStyle = 'rgba(0,0,0,0.18)'; g.fillRect(px - 10, py + h + 6, w + 20, 10); // peitoril
    if (R() < 0.6) { g.fillStyle = ['#ffb36b', '#ff7b9c', '#7ad1c1', '#ffd23f'][Math.floor(R() * 4)]; g.fillRect(px, py, w, h * 0.22); } // persiana
    if (R() < 0.5) { ge.fillStyle = R() < 0.75 ? '#ffcf7a' : '#cfe8ff'; ge.fillRect(px, py, w, h); }
  }
  const map = new THREE.CanvasTexture(c); map.colorSpace = THREE.SRGBColorSpace; map.wrapS = map.wrapT = THREE.RepeatWrapping; map.anisotropy = 8;
  const emap = new THREE.CanvasTexture(e); emap.colorSpace = THREE.SRGBColorSpace; emap.wrapS = emap.wrapT = THREE.RepeatWrapping;
  return { map, emap };
}

function roadTexture() {
  const c = document.createElement('canvas'); c.width = 64; c.height = 256;
  const g = c.getContext('2d');
  g.fillStyle = '#4a4f5c'; g.fillRect(0, 0, 64, 256);
  for (let i = 0; i < 400; i++) { g.fillStyle = `rgba(255,255,255,${Math.random() * 0.05})`; g.fillRect(Math.random() * 64, Math.random() * 256, 2, 2); }
  g.fillStyle = '#ffd23f'; g.fillRect(30, 0, 4, 120);
  g.fillStyle = '#e9eef7'; g.fillRect(2, 0, 3, 256); g.fillRect(59, 0, 3, 256);
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.wrapS = t.wrapT = THREE.RepeatWrapping; t.anisotropy = 8;
  return t;
}

function grassTexture() {
  const c = document.createElement('canvas'); c.width = 128; c.height = 128;
  const g = c.getContext('2d');
  g.fillStyle = '#86c873'; g.fillRect(0, 0, 128, 128);
  for (let i = 0; i < 600; i++) { g.fillStyle = Math.random() < 0.5 ? 'rgba(40,110,40,0.25)' : 'rgba(200,255,150,0.18)'; g.fillRect(Math.random() * 128, Math.random() * 128, 2, 3); }
  const t = new THREE.CanvasTexture(c); t.colorSpace = THREE.SRGBColorSpace; t.wrapS = t.wrapT = THREE.RepeatWrapping;
  return t;
}

// caixa com UV em escala de mundo (janelas a cada `tile` metros)
function buildingGeo(w, h, d, tileW = 6, tileH = 3.5) {
  const g = new THREE.BoxGeometry(w, h, d);
  const uv = g.attributes.uv;
  // grupos: +x, -x, +y, -y, +z, -z (4 vértices cada)
  const dims = [[d, h], [d, h], [w, d], [w, d], [w, h], [w, h]];
  for (let f = 0; f < 6; f++) for (let k = 0; k < 4; k++) {
    const i = f * 4 + k;
    uv.setXY(i, uv.getX(i) * Math.max(1, Math.round(dims[f][0] / tileW)), uv.getY(i) * dims[f][1] / tileH);
  }
  return g;
}

class Batch {
  constructor() { this.parts = new Map(); }
  add(geo, matKey, x = 0, y = 0, z = 0, ry = 0, sx = 1, sy = 1, sz = 1) {
    const g = geo.index ? geo.clone() : geo.clone();
    const m = new THREE.Matrix4().compose(new THREE.Vector3(x, y, z), new THREE.Quaternion().setFromEuler(new THREE.Euler(0, ry, 0)), new THREE.Vector3(sx, sy, sz));
    g.applyMatrix4(m);
    if (!this.parts.has(matKey)) this.parts.set(matKey, []);
    this.parts.get(matKey).push(g);
  }
  build(materials, parent, { cast = false, receive = true } = {}) {
    for (const [k, list] of this.parts) {
      // separa por grupo de material quando a geometria tem grupos (prédios: lados vs telhado)
      const merged = mergeGeometries(list.map((g) => { const n = g.index ? g.toNonIndexed() : g; n.clearGroups(); return n; }), false);
      const mesh = new THREE.Mesh(merged, materials[k]);
      mesh.castShadow = cast; mesh.receiveShadow = receive;
      mesh.matrixAutoUpdate = false; mesh.updateMatrix();
      parent.add(mesh);
    }
  }
}

// ---------------------------------------------------------------- cidade
export class City {
  constructor(scene) {
    this.scene = scene;
    this.group = new THREE.Group();
    scene.add(this.group);
    const R = rng(7);

    // céu (domo com gradiente e brilho do sol)
    this.skyU = {
      top: { value: new THREE.Color(0x5aa8ff) }, horizon: { value: new THREE.Color(0xd9efff) },
      bottom: { value: new THREE.Color(0x9ab0c8) }, sunDir: { value: new THREE.Vector3(0, 1, 0) }, sunColor: { value: new THREE.Color(0xfff2c0) },
    };
    const sky = new THREE.Mesh(new THREE.SphereGeometry(600, 32, 16), new THREE.ShaderMaterial({
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

    // materiais
    const winA = windowTextures(3, 0), winB = windowTextures(11, 1);
    this.winMats = [];
    const bcols = [0xe8dcc8, 0xc9d3e0, 0xf1c9a5, 0xb8c7b0, 0xd9b8c4, 0xa9b8cc, 0xeee4d0];
    const mats = {};
    bcols.forEach((c, i) => {
      const w = i % 2 ? winA : winB;
      const m = new THREE.MeshStandardMaterial({ color: c, map: w.map, emissive: 0xffffff, emissiveMap: w.emap, emissiveIntensity: 0, roughness: 0.6, metalness: 0.05 });
      mats['b' + i] = m; this.winMats.push(m);
    });
    mats.roof = new THREE.MeshStandardMaterial({ color: 0x8a8f9c, roughness: 0.9 });
    mats.roof2 = new THREE.MeshStandardMaterial({ color: 0x6a7080, roughness: 0.9 });
    mats.trim = new THREE.MeshStandardMaterial({ color: 0xf4efe6, roughness: 0.7 });
    mats.metal = new THREE.MeshStandardMaterial({ color: 0xb5bcc9, roughness: 0.5, metalness: 0.3 });
    mats.dark = new THREE.MeshStandardMaterial({ color: 0x3b4566, roughness: 0.7 });
    mats.red = new THREE.MeshStandardMaterial({ color: 0xe0653f, roughness: 0.7 });
    const road = roadTexture();
    mats.side = new THREE.MeshStandardMaterial({ color: 0xc9c2b4, roughness: 0.95 });
    mats.curb = new THREE.MeshStandardMaterial({ color: 0xe9e4da, roughness: 0.9 });
    const grass = grassTexture(); grass.repeat.set(1, 1);
    mats.grass = new THREE.MeshStandardMaterial({ color: 0xffffff, map: grass, roughness: 1 });
    mats.leaf = new THREE.MeshStandardMaterial({ color: 0x4fb36a, roughness: 0.9, flatShading: true });
    mats.leaf2 = new THREE.MeshStandardMaterial({ color: 0x3f9a58, roughness: 0.9, flatShading: true });
    mats.leaf3 = new THREE.MeshStandardMaterial({ color: 0xe0a33f, roughness: 0.9, flatShading: true });
    mats.trunk = new THREE.MeshStandardMaterial({ color: 0x8e5b34, roughness: 0.9 });
    mats.water = new THREE.MeshStandardMaterial({ color: 0x5fb6e6, roughness: 0.15, metalness: 0.1 });
    mats.stripe = new THREE.MeshStandardMaterial({ color: 0xf4efe6, roughness: 0.8 });
    this.lampMat = new THREE.MeshStandardMaterial({ color: 0xfff2c0, emissive: 0xffc46b, emissiveIntensity: 0 });
    mats.lamp = this.lampMat;
    this.mats = mats;

    const B = new Batch();
    const G = GROUND;
    const boxG = new THREE.BoxGeometry(1, 1, 1);
    const cylG = new THREE.CylinderGeometry(0.5, 0.5, 1, 12);
    const sphG = new THREE.IcosahedronGeometry(1, 1);
    const coneG = new THREE.ConeGeometry(1, 1, 7);

    // chão
    const ground = new THREE.Mesh(new THREE.PlaneGeometry(1400, 1400), new THREE.MeshStandardMaterial({ color: 0x5a6070, roughness: 1 }));
    ground.rotation.x = -Math.PI / 2; ground.position.y = G - 0.05; ground.receiveShadow = true; this.group.add(ground);

    // ruas: linhas em x (correm em z) e em z (correm em x)
    const SX = [-26, 26, -78, 78, -130, 130], SZ = [-24, 22, -76, 74, -128];
    const RW = 9;
    road.repeat.set(1, 1);
    const roadMat = new THREE.MeshStandardMaterial({ map: road, roughness: 0.95 });
    const roadZ = road.clone(); roadZ.needsUpdate = true; roadZ.repeat.set(1, 400 / 10);
    const rmZ = new THREE.MeshStandardMaterial({ map: roadZ, roughness: 0.95 });
    for (const x of SX) { const m = new THREE.Mesh(new THREE.PlaneGeometry(RW, 400), rmZ); m.rotation.x = -Math.PI / 2; m.position.set(x, G, -40); m.receiveShadow = true; this.group.add(m); }
    const roadX = road.clone(); roadX.needsUpdate = true; roadX.repeat.set(1, 400 / 10);
    const rmX = new THREE.MeshStandardMaterial({ map: roadX, roughness: 0.95 });
    for (const z of SZ) { const m = new THREE.Mesh(new THREE.PlaneGeometry(RW, 400), rmX); m.rotation.x = -Math.PI / 2; m.rotation.z = Math.PI / 2; m.position.set(0, G + 0.01, z); m.receiveShadow = true; this.group.add(m); }
    roadMat.dispose();

    // quarteirões
    const xs = [-200, ...SX.slice().sort((a, b) => a - b), 200];
    const zs = [-200, ...SZ.slice().sort((a, b) => a - b), 200];
    for (let i = 0; i < xs.length - 1; i++) for (let j = 0; j < zs.length - 1; j++) {
      const x0 = xs[i] + RW / 2, x1 = xs[i + 1] - RW / 2, z0 = zs[j] + RW / 2, z1 = zs[j + 1] - RW / 2;
      const cx = (x0 + x1) / 2, cz = (z0 + z1) / 2, w = x1 - x0, d = z1 - z0;
      if (w < 4 || d < 4) continue;
      // calçada
      B.add(boxG, 'side', cx, G + 0.12, cz, 0, w, 0.24, d);
      B.add(boxG, 'curb', cx, G + 0.13, cz, 0, w + 0.3, 0.2, d + 0.3);
      const isHome = cx > -26 && cx < 26 && cz > -24 && cz < 22;
      if (isHome) { this.homeBlock(B, cx, cz, w, d, R); continue; }
      // escolhe: parque ou prédios
      const dist = Math.hypot(cx, cz);
      if ((i + j) % 5 === 2 && dist < 150) { this.park(B, cx, cz, w, d, R); continue; }
      // subdivide em lotes
      const nx = w > 40 ? 2 : 1, nz = d > 40 ? 2 : 1;
      for (let a = 0; a < nx; a++) for (let b = 0; b < nz; b++) {
        const lw = w / nx, ld = d / nz;
        const lx = x0 + lw * (a + 0.5), lz = z0 + ld * (b + 0.5);
        const bw = lw - 3 - R() * 4, bd = ld - 3 - R() * 4;
        // altura: atrás pode ser alto (skyline); dos lados, mais baixo para não tapar o escritório
        let maxTop;
        if (lz < -70) maxTop = 10 + R() * 40;            // skyline ao fundo
        else if (lz < -20) maxTop = Math.abs(lx) < 50 ? -12 + R() * 14 : 0 + R() * 20;
        else if (Math.abs(lx) < 60) maxTop = -10 + R() * 8;
        else maxTop = 0 + R() * 18;
        if (lz > 18) maxTop = -10 + R() * 10;
        const h = Math.max(8, maxTop - G);
        this.building(B, lx, lz, bw, h, bd, R);
      }
    }

    B.build(mats, this.group, { cast: false, receive: true });

    // prédio do escritório (abaixo da laje) + fachada
    this.homeTower();

    // elementos animados
    this.cars = []; this.peds = []; this.birds = [];
    this.spawnCars(R, SX, SZ);
    this.spawnPeds(R, SX, SZ);
    this.spawnClouds(R);
    this.spawnBirds(R);
    this.lights = [];
  }

  building(B, x, z, w, h, d, R) {
    const G = GROUND;
    const k = 'b' + Math.floor(R() * 7);
    const geo = buildingGeo(w, h, d);
    B.add(geo, k, x, G + h / 2, z);
    // telhado
    B.add(new THREE.BoxGeometry(1, 1, 1), 'roof', x, G + h + 0.05, z, 0, w + 0.05, 0.12, d + 0.05);
    B.add(new THREE.BoxGeometry(1, 1, 1), 'trim', x, G + h + 0.35, z, 0, w + 0.4, 0.6, 0.4 + 0 * d);
    // platibanda (4 lados)
    for (const [ox, oz, sw, sd] of [[0, d / 2, w + 0.4, 0.4], [0, -d / 2, w + 0.4, 0.4], [w / 2, 0, 0.4, d], [-w / 2, 0, 0.4, d]]) B.add(new THREE.BoxGeometry(1, 1, 1), 'trim', x + ox, G + h + 0.35, z + oz, 0, sw, 0.6, sd);
    // térreo com toldo / vitrine
    B.add(new THREE.BoxGeometry(1, 1, 1), 'dark', x, G + 1.8, z + d / 2 + 0.05, 0, w * 0.9, 3.0, 0.2);
    B.add(new THREE.BoxGeometry(1, 1, 1), R() < 0.5 ? 'red' : 'trim', x, G + 3.5, z + d / 2 + 0.7, 0, w * 0.8, 0.15, 1.4);
    // coisas no telhado
    const top = G + h;
    const n = 1 + Math.floor(R() * 4);
    for (let i = 0; i < n; i++) {
      const px = x + (R() - 0.5) * (w - 4), pz = z + (R() - 0.5) * (d - 4);
      const t = R();
      if (t < 0.4) { B.add(new THREE.BoxGeometry(1, 1, 1), 'metal', px, top + 0.7, pz, 0, 2.2, 1.4, 1.6); B.add(new THREE.CylinderGeometry(0.5, 0.5, 1, 12), 'dark', px, top + 1.45, pz, 0, 1.0, 0.1, 1.0); }
      else if (t < 0.65) { B.add(new THREE.CylinderGeometry(0.5, 0.5, 1, 12), 'trim', px, top + 1.6, pz, 0, 2.4, 2.6, 2.4); for (const [a, b] of [[-0.8, -0.8], [0.8, 0.8], [-0.8, 0.8], [0.8, -0.8]]) B.add(new THREE.BoxGeometry(1, 1, 1), 'dark', px + a, top + 0.2, pz + b, 0, 0.2, 0.5, 0.2); }
      else if (t < 0.8) { B.add(new THREE.CylinderGeometry(0.5, 0.5, 1, 6), 'metal', px, top + 3, pz, 0, 0.15, 6, 0.15); B.add(new THREE.IcosahedronGeometry(1, 0), 'red', px, top + 6.1, pz, 0, 0.25, 0.25, 0.25); }
      else { // jardim no telhado
        B.add(new THREE.BoxGeometry(1, 1, 1), 'grass', px, top + 0.25, pz, 0, 4, 0.3, 3);
        for (let q = 0; q < 3; q++) B.add(new THREE.IcosahedronGeometry(1, 1), q % 2 ? 'leaf' : 'leaf2', px + (q - 1) * 1.2, top + 1.0, pz, 0, 0.8, 0.9, 0.8);
      }
    }
  }

  park(B, cx, cz, w, d, R) {
    const G = GROUND;
    B.add(new THREE.BoxGeometry(1, 1, 1), 'grass', cx, G + 0.28, cz, 0, w - 2, 0.1, d - 2);
    if (R() < 0.7) { B.add(new THREE.CylinderGeometry(1, 1, 1, 24), 'water', cx, G + 0.36, cz, 0, Math.min(w, d) * 0.18, 0.1, Math.min(w, d) * 0.18); B.add(new THREE.CylinderGeometry(1, 1, 1, 24), 'curb', cx, G + 0.33, cz, 0, Math.min(w, d) * 0.2, 0.15, Math.min(w, d) * 0.2); }
    const n = Math.floor((w * d) / 60);
    for (let i = 0; i < n; i++) {
      const x = cx + (R() - 0.5) * (w - 6), z = cz + (R() - 0.5) * (d - 6);
      if (Math.hypot(x - cx, z - cz) < Math.min(w, d) * 0.25) continue;
      this.tree(B, x, z, 0.8 + R() * 0.7, R);
    }
  }

  tree(B, x, z, s, R) {
    const G = GROUND;
    B.add(new THREE.CylinderGeometry(0.5, 0.5, 1, 6), 'trunk', x, G + 1.2 * s, z, 0, 0.35 * s, 2.4 * s, 0.35 * s);
    const leaf = R() < 0.15 ? 'leaf3' : R() < 0.5 ? 'leaf' : 'leaf2';
    if (R() < 0.3) B.add(new THREE.ConeGeometry(1, 1, 7), leaf, x, G + 3.6 * s, z, 0, 1.5 * s, 4 * s, 1.5 * s);
    else { B.add(new THREE.IcosahedronGeometry(1, 1), leaf, x, G + 3.2 * s, z, 0, 1.6 * s, 1.5 * s, 1.6 * s); B.add(new THREE.IcosahedronGeometry(1, 1), leaf, x + 0.6 * s, G + 3.9 * s, z + 0.3 * s, 0, 1.0 * s, 1.0 * s, 1.0 * s); }
  }

  homeBlock(B, cx, cz, w, d, R) {
    const G = GROUND;
    // praça em volta do prédio com árvores e postes
    for (let i = 0; i < 18; i++) {
      const side = i % 4;
      let x, z;
      if (side === 0) { x = -18 + (i / 18) * 36; z = d / 2 + cz - 2; }
      else if (side === 1) { x = -18 + (i / 18) * 36; z = cz - d / 2 + 2; }
      else if (side === 2) { x = cx - w / 2 + 2; z = -16 + (i / 18) * 32; }
      else { x = cx + w / 2 - 2; z = -16 + (i / 18) * 32; }
      this.tree(B, x, z, 0.9 + R() * 0.4, R);
    }
    // canteiros
    for (const sx of [-1, 1]) B.add(new THREE.BoxGeometry(1, 1, 1), 'grass', 17 * sx, G + 0.4, 0, 0, 3, 0.35, 24);
    // postes de luz
    for (const [x, z] of [[-20, -18], [20, -18], [-20, 14], [20, 14], [-20, -2], [20, -2]]) this.lamp(B, x, z);
  }

  lamp(B, x, z) {
    const G = GROUND;
    B.add(new THREE.CylinderGeometry(0.5, 0.5, 1, 8), 'dark', x, G + 2.5, z, 0, 0.18, 5, 0.18);
    B.add(new THREE.BoxGeometry(1, 1, 1), 'dark', x, G + 5.0, z, 0, 0.9, 0.15, 0.3);
    B.add(new THREE.BoxGeometry(1, 1, 1), 'lamp', x, G + 4.9, z, 0, 0.7, 0.08, 0.25);
  }

  homeTower() {
    const G = GROUND;
    const w = 25.6, d = 16.8, h = -1.2 - G;
    const tex = windowTextures(5, 1);
    tex.map.repeat.set(1, 1);
    const m = new THREE.MeshStandardMaterial({ color: 0xd9dfe9, map: tex.map, emissive: 0xffffff, emissiveMap: tex.emap, emissiveIntensity: 0, roughness: 0.5 });
    this.winMats.push(m);
    const tower = new THREE.Mesh(buildingGeo(w, h, d, 5, 3.5), m);
    tower.position.set(0, G + h / 2, 0); tower.receiveShadow = true;
    this.group.add(tower);
    // faixas entre andares
    for (let i = 1; i < 8; i++) {
      const s = new THREE.Mesh(new THREE.BoxGeometry(w + 0.3, 0.25, d + 0.3), this.mats.trim);
      s.position.set(0, -1.2 - i * 3.5, 0); this.group.add(s);
    }
    // letreiro na fachada
    const c = document.createElement('canvas'); c.width = 1024; c.height = 160;
    const g = c.getContext('2d');
    g.fillStyle = '#1d2540'; g.beginPath(); g.roundRect(4, 4, 1016, 152, 40); g.fill();
    g.fillStyle = '#ffd23f'; g.font = 'bold 96px Fredoka, sans-serif'; g.textAlign = 'center'; g.textBaseline = 'middle';
    g.fillText('CONTÁBIL & CIA', 512, 84);
    const st = new THREE.CanvasTexture(c); st.colorSpace = THREE.SRGBColorSpace;
    const sign = new THREE.Mesh(new THREE.PlaneGeometry(11, 1.7), new THREE.MeshStandardMaterial({ map: st, emissive: 0xffffff, emissiveMap: st, emissiveIntensity: 0.25, roughness: 0.5 }));
    sign.position.set(0, -2.6, d / 2 + 0.2); this.group.add(sign);
    this.signMat = sign.material;
    // entrada no térreo
    const ent = new THREE.Mesh(new THREE.BoxGeometry(8, 4, 0.6), this.mats.dark); ent.position.set(0, G + 2, d / 2 + 0.2); this.group.add(ent);
    const awn = new THREE.Mesh(new THREE.BoxGeometry(10, 0.3, 3), this.mats.red); awn.position.set(0, G + 4.3, d / 2 + 1.5); this.group.add(awn);
  }

  spawnCars(R, SX, SZ) {
    const cols = [0xff5a5a, 0x3d7bff, 0xffd23f, 0x2fc46b, 0xf4efe6, 0x2a2f3d, 0xff8a2b, 0x7ad1c1];
    const mk = (col, taxi) => {
      const g = new THREE.Group();
      const body = new THREE.Mesh(new THREE.BoxGeometry(1.9, 0.7, 4), new THREE.MeshStandardMaterial({ color: col, roughness: 0.35, metalness: 0.2 }));
      body.position.y = 0.65; g.add(body);
      const cab = new THREE.Mesh(new THREE.BoxGeometry(1.7, 0.65, 2.1), new THREE.MeshStandardMaterial({ color: 0x9fd8ff, roughness: 0.1, metalness: 0.3 }));
      cab.position.set(0, 1.3, -0.2); g.add(cab);
      const roof = new THREE.Mesh(new THREE.BoxGeometry(1.75, 0.1, 1.9), body.material); roof.position.set(0, 1.66, -0.2); g.add(roof);
      if (taxi) { const t = new THREE.Mesh(new THREE.BoxGeometry(0.7, 0.25, 0.3), new THREE.MeshStandardMaterial({ color: 0xffffff, emissive: 0xffd23f, emissiveIntensity: 0.4 })); t.position.set(0, 1.85, -0.2); g.add(t); }
      const wm = new THREE.MeshStandardMaterial({ color: 0x1d2540, roughness: 0.8 });
      for (const [x, z] of [[-0.9, 1.3], [0.9, 1.3], [-0.9, -1.3], [0.9, -1.3]]) { const w = new THREE.Mesh(new THREE.CylinderGeometry(0.38, 0.38, 0.3, 12), wm); w.rotation.z = Math.PI / 2; w.position.set(x, 0.38, z); g.add(w); }
      const hl = new THREE.MeshStandardMaterial({ color: 0xfff6d0, emissive: 0xfff2b0, emissiveIntensity: 0.3 });
      for (const x of [-0.6, 0.6]) { const l = new THREE.Mesh(new THREE.BoxGeometry(0.4, 0.2, 0.05), hl); l.position.set(x, 0.75, 2.01); g.add(l); }
      const tl = new THREE.MeshStandardMaterial({ color: 0xff3b3b, emissive: 0xff2020, emissiveIntensity: 0.6 });
      for (const x of [-0.65, 0.65]) { const l = new THREE.Mesh(new THREE.BoxGeometry(0.35, 0.18, 0.05), tl); l.position.set(x, 0.8, -2.01); g.add(l); }
      g.userData.hl = hl;
      g.traverse((o) => { if (o.isMesh) { o.castShadow = false; o.receiveShadow = false; } });
      return g;
    };
    for (let i = 0; i < 30; i++) {
      const alongZ = i % 2 === 0;
      const line = alongZ ? SX[Math.floor(R() * 4)] : SZ[Math.floor(R() * 3)];
      const dir = R() < 0.5 ? 1 : -1;
      const car = mk(cols[Math.floor(R() * cols.length)], R() < 0.15);
      const lane = line + dir * 2.1 * (alongZ ? -1 : 1);
      const s = (R() - 0.5) * 360;
      car.position.set(alongZ ? lane : s, GROUND, alongZ ? s : lane);
      car.rotation.y = alongZ ? (dir > 0 ? 0 : Math.PI) : (dir > 0 ? Math.PI / 2 : -Math.PI / 2);
      this.group.add(car);
      this.cars.push({ mesh: car, alongZ, dir, speed: 9 + R() * 8, phase: R() * 10 });
    }
  }

  spawnPeds(R, SX, SZ) {
    const cols = [0xff5a5a, 0x3d7bff, 0xffd23f, 0x2fc46b, 0xb07cff, 0xff8a2b, 0xf4efe6];
    const skins = [0xf2c29b, 0x9a6440, 0xc68a5e, 0xf6d2b5];
    for (let i = 0; i < 46; i++) {
      const g = new THREE.Group();
      const b = new THREE.Mesh(new THREE.CapsuleGeometry(0.28, 0.5, 4, 8), new THREE.MeshStandardMaterial({ color: cols[i % cols.length], roughness: 0.8 }));
      b.position.y = 0.6; g.add(b);
      const h = new THREE.Mesh(new THREE.SphereGeometry(0.26, 10, 8), new THREE.MeshStandardMaterial({ color: skins[i % 4], roughness: 0.8 }));
      h.position.y = 1.35; g.add(h);
      if (i % 3 === 0) { const u = new THREE.Mesh(new THREE.ConeGeometry(0.7, 0.4, 8), new THREE.MeshStandardMaterial({ color: cols[(i + 2) % cols.length] })); u.position.y = 1.9; g.add(u); }
      const alongZ = i % 2 === 0;
      const line = alongZ ? SX[Math.floor(R() * 4)] : SZ[Math.floor(R() * 3)];
      const off = (R() < 0.5 ? -1 : 1) * 5.6;
      const dir = R() < 0.5 ? 1 : -1;
      const s = (R() - 0.5) * 300;
      g.position.set(alongZ ? line + off : s, GROUND + 0.24, alongZ ? s : line + off);
      g.rotation.y = alongZ ? (dir > 0 ? 0 : Math.PI) : (dir > 0 ? Math.PI / 2 : -Math.PI / 2);
      this.group.add(g);
      this.peds.push({ mesh: g, alongZ, dir, speed: 1.1 + R() * 0.8, phase: R() * 6 });
    }
  }

  spawnClouds(R) {
    this.clouds = [];
    const m = new THREE.MeshStandardMaterial({ color: 0xffffff, roughness: 1, emissive: 0xffffff, emissiveIntensity: 0.15 });
    this.cloudMat = m;
    for (let i = 0; i < 16; i++) {
      const g = new THREE.Group();
      const n = 4 + Math.floor(R() * 4);
      for (let k = 0; k < n; k++) {
        const s = new THREE.Mesh(new THREE.IcosahedronGeometry(1, 2), m);
        const r = 3 + R() * 4;
        s.scale.set(r, r * 0.75, r);
        s.position.set((k - n / 2) * 4 + R() * 2, R() * 2, R() * 3);
        g.add(s);
      }
      g.position.set((R() - 0.5) * 400, 20 + R() * 45, -60 - R() * 220);
      this.group.add(g);
      this.clouds.push({ g, speed: 1.5 + R() * 2.5 });
    }
  }

  spawnBirds(R) {
    const m = new THREE.MeshStandardMaterial({ color: 0x2a2f3d, side: THREE.DoubleSide, roughness: 0.9 });
    for (let i = 0; i < 9; i++) {
      const g = new THREE.Group();
      const body = new THREE.Mesh(new THREE.SphereGeometry(0.18, 8, 6), m); body.scale.set(0.7, 0.7, 1.4); g.add(body);
      const wings = [];
      for (const s of [-1, 1]) {
        const w = new THREE.Group();
        const p = new THREE.Mesh(new THREE.PlaneGeometry(0.8, 0.3), m); p.position.x = 0.4 * s; p.rotation.x = -Math.PI / 2; w.add(p);
        g.add(w); wings.push(w);
      }
      this.group.add(g);
      this.birds.push({ g, wings, r: 18 + R() * 25, h: 4 + R() * 10, speed: 0.2 + R() * 0.15, phase: R() * 6.28, cx: (R() - 0.5) * 30, cz: -20 - R() * 30 });
    }
  }

  // ---------------------------------------------------------------- ciclo do dia
  // t: 0 (09:00) → 1 (18:00)
  setTime(t, L) {
    const smooth = (a, b, x) => { const k = Math.min(1, Math.max(0, (x - a) / (b - a))); return k * k * (3 - 2 * k); };
    const eve = smooth(0.62, 1.0, t);     // fim de tarde
    const morn = 1 - smooth(0.0, 0.25, t); // manhã
    // sol: da esquerda (manhã) para a direita (tarde), sempre um pouco à frente
    const az = -1.05 + t * 2.1;
    const el = 0.35 + Math.sin(Math.PI * Math.min(1, t * 0.95 + 0.04)) * 0.75 - eve * 0.25;
    const dir = new THREE.Vector3(Math.sin(az) * Math.cos(el), Math.sin(el), Math.cos(az) * Math.cos(el) * 0.75 + 0.25).normalize();
    L.sun.position.copy(dir).multiplyScalar(30);
    const noonC = new THREE.Color(0xfff4e2), mornC = new THREE.Color(0xffe0b0), eveC = new THREE.Color(0xffb27a);
    L.sun.color.copy(noonC).lerp(mornC, morn * 0.7).lerp(eveC, eve);
    L.sun.intensity = 2.9 - eve * 0.7;
    if (L.officeLight) L.officeLight.intensity = 0.4 + eve * 2.2;
    L.hemi.color.set(0xdfeaff).lerp(new THREE.Color(0xffc89e), eve * 0.8);
    L.hemi.groundColor.set(0x7a6a58).lerp(new THREE.Color(0x5a4a68), eve);
    L.hemi.intensity = 1.35 - eve * 0.2;
    // céu
    const top = new THREE.Color(0x4a9cff).lerp(new THREE.Color(0x7fb6ff), morn * 0.5).lerp(new THREE.Color(0x4a4f9a), eve);
    const hor = new THREE.Color(0xd2ecff).lerp(new THREE.Color(0xffe6c8), morn * 0.6).lerp(new THREE.Color(0xffa36a), eve);
    this.skyU.top.value.copy(top); this.skyU.horizon.value.copy(hor);
    this.skyU.bottom.value.copy(hor).lerp(new THREE.Color(0x6a7890), 0.5);
    this.skyU.sunDir.value.copy(dir);
    this.skyU.sunColor.value.copy(L.sun.color);
    if (this.scene.fog) this.scene.fog.color.copy(hor).lerp(new THREE.Color(0x8fa6c8), 0.25);
    // janelas e postes acendem no fim do dia
    const lit = 0.1 + eve * 1.4;
    for (const m of this.winMats) m.emissiveIntensity = lit;
    this.lampMat.emissiveIntensity = smooth(0.8, 0.95, t) * 3;
    for (const c of this.cars) c.mesh.userData.hl.emissiveIntensity = 0.3 + eve * 2.5;
    this.signMat.emissiveIntensity = 0.25 + eve * 1.2;
    this.cloudMat.color.set(0xffffff).lerp(new THREE.Color(0xffc8a8), eve * 0.8);
    this.eve = eve;
  }

  update(dt, time) {
    for (const c of this.cars) {
      const p = c.mesh.position;
      // "semáforo": para de vez em quando perto dos cruzamentos
      const slow = 0.6 + 0.4 * Math.max(0, Math.sin(time * 0.35 + c.phase));
      const v = c.speed * slow * dt * c.dir;
      if (c.alongZ) { p.z += v; if (p.z > 190) p.z = -190; if (p.z < -190) p.z = 190; }
      else { p.x += v; if (p.x > 190) p.x = -190; if (p.x < -190) p.x = 190; }
    }
    for (const q of this.peds) {
      const p = q.mesh.position;
      const v = q.speed * dt * q.dir;
      if (q.alongZ) { p.z += v; if (Math.abs(p.z) > 150) p.z *= -0.99; } else { p.x += v; if (Math.abs(p.x) > 150) p.x *= -0.99; }
      q.mesh.children[0].position.y = 0.6 + Math.abs(Math.sin(time * 8 * q.speed + q.phase)) * 0.12;
      q.mesh.children[0].rotation.z = Math.sin(time * 8 * q.speed + q.phase) * 0.08;
    }
    for (const c of this.clouds) { c.g.position.x += c.speed * dt; if (c.g.position.x > 220) c.g.position.x = -220; }
    for (const b of this.birds) {
      const a = time * b.speed + b.phase;
      b.g.position.set(b.cx + Math.cos(a) * b.r, b.h + Math.sin(a * 2.3) * 1.5, b.cz + Math.sin(a) * b.r * 0.6);
      b.g.rotation.y = -a;
      const f = Math.sin(time * 14 + b.phase) * 0.7;
      b.wings[0].rotation.z = f; b.wings[1].rotation.z = -f;
    }
  }
}
