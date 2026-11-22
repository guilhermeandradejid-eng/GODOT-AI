import * as THREE from 'three';
import { mergeGeometries } from 'three/examples/jsm/utils/BufferGeometryUtils.js';
import { mat, toonMat, unlitMat } from './materials.js';
import { toWorld, toUV, PLACES, PATHS, riverV, LH } from './world.js';
import { mulberry32, vnoise, fbm } from './noise.js';

// =============================================================================
// Cenário: árvores (copas "fofas" com normais esféricas), arbustos, pedras, casas
// em enxaimel, cercas, poço, barraca do mercador, ponte, portão do bosque e ruínas.
// =============================================================================

const rng = mulberry32(1234);
const ni = (g) => (g.index ? g.toNonIndexed() : g);
const R = (a, b) => a + rng() * (b - a);

export function box(w, h, d, color, o = {}) {
  const g = new THREE.BoxGeometry(w, h, d);
  if (o.base) g.translate(0, h / 2, 0);
  const m = new THREE.Mesh(g, o.material || mat(color, o.matOpts || {}));
  m.castShadow = o.cast ?? true; m.receiveShadow = true;
  if (o.p) m.position.set(...o.p);
  if (o.r) m.rotation.set(...o.r);
  return m;
}

// ---------------------------------------------------------------- copas
function blob(r, detail, seed, squash = 0.85) {
  const g = new THREE.IcosahedronGeometry(r, detail);
  const p = g.attributes.position;
  const v = new THREE.Vector3();
  for (let i = 0; i < p.count; i++) {
    v.fromBufferAttribute(p, i);
    const n = vnoise(v.x * 3 + seed, v.y * 3 + v.z * 2 - seed);
    v.multiplyScalar(1 + (n - 0.5) * 0.28);
    v.y *= squash;
    p.setXYZ(i, v.x, v.y, v.z);
  }
  return g;
}

/** normais esféricas em relação a `c` misturadas com as normais da própria bolha */
function sphericalNormals(g, c, k = 0.7) {
  g.computeVertexNormals();
  const p = g.attributes.position, n = g.attributes.normal;
  const v = new THREE.Vector3(), nn = new THREE.Vector3();
  for (let i = 0; i < p.count; i++) {
    v.fromBufferAttribute(p, i).sub(c).normalize();
    nn.fromBufferAttribute(n, i).lerp(v, k).normalize();
    n.setXYZ(i, nn.x, nn.y, nn.z);
  }
  return g;
}

function crownOak(seed) {
  const parts = [];
  const top = 2.05;
  const spots = [[0, top, 0, 0.95], [0.55, top - 0.25, 0.25, 0.62], [-0.5, top - 0.2, -0.3, 0.66], [0.15, top + 0.5, -0.1, 0.62], [-0.2, top - 0.35, 0.55, 0.55], [0.3, top - 0.3, -0.55, 0.55]];
  spots.forEach(([x, y, z, r], i) => { const b = blob(r, 1, seed + i * 3.1); b.translate(x, y, z); parts.push(b); });
  const g = mergeGeometries(parts.map(ni));
  return sphericalNormals(g, new THREE.Vector3(0, top + 0.05, 0), 0.75);
}
function crownPine() {
  const parts = [];
  const tiers = [[1.0, 1.05, 0.95], [0.78, 0.95, 1.65], [0.52, 0.85, 2.3], [0.28, 0.6, 2.85]];
  for (const [r, h, y] of tiers) { const c = new THREE.ConeGeometry(r, h, 8, 1); c.translate(0, y, 0); parts.push(c); }
  const g = mergeGeometries(parts.map(ni));
  return sphericalNormals(g, new THREE.Vector3(0, 1.4, 0), 0.35);
}
function crownBush(seed) {
  const parts = [];
  [[0, 0.32, 0, 0.42], [0.3, 0.25, 0.12, 0.3], [-0.28, 0.24, -0.1, 0.32], [0.05, 0.5, -0.05, 0.28]].forEach(([x, y, z, r], i) => { const b = blob(r, 1, seed + i, 0.8); b.translate(x, y, z); parts.push(b); });
  return sphericalNormals(mergeGeometries(parts.map(ni)), new THREE.Vector3(0, 0.25, 0), 0.7);
}
function trunkGeo(h = 1.7, r0 = 0.2, r1 = 0.12) {
  const t = new THREE.CylinderGeometry(r1, r0, h, 6, 1); t.translate(0, h / 2, 0);
  const b = new THREE.CylinderGeometry(0.04, 0.07, 0.6, 5); b.rotateZ(-0.9); b.translate(0.28, h * 0.62, 0);
  const root = new THREE.CylinderGeometry(0.05, 0.12, 0.3, 5); root.rotateZ(1.2); root.translate(-0.2, 0.08, 0.05);
  return mergeGeometries([t, b, root].map(ni));
}
function rockGeo(seed) {
  const g = new THREE.DodecahedronGeometry(0.5, 0);
  const p = g.attributes.position, v = new THREE.Vector3();
  for (let i = 0; i < p.count; i++) {
    v.fromBufferAttribute(p, i);
    const n = vnoise(v.x * 2 + seed, v.z * 2 + v.y);
    v.multiplyScalar(0.8 + n * 0.4); v.y = v.y * 0.62 + 0.18;
    p.setXYZ(i, v.x, v.y, v.z);
  }
  g.computeVertexNormals();
  return g;
}

// ---------------------------------------------------------------- instâncias
class Instancer {
  constructor(geo, material, { cast = true, layer = 0 } = {}) { this.geo = geo; this.mat = material; this.items = []; this.cast = cast; this.layer = layer; }
  add(x, y, z, rot = 0, s = 1, color = null, sy = null) { this.items.push({ x, y, z, rot, s, sy: sy ?? s, color }); }
  build(scene) {
    if (!this.items.length) return null;
    const im = new THREE.InstancedMesh(this.geo, this.mat, this.items.length);
    const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), up = new THREE.Vector3(0, 1, 0);
    this.items.forEach((it, i) => {
      q.setFromAxisAngle(up, it.rot);
      m4.compose(new THREE.Vector3(it.x, it.y, it.z), q, new THREE.Vector3(it.s, it.sy, it.s));
      im.setMatrixAt(i, m4);
      if (it.color) im.setColorAt(i, it.color);
    });
    im.castShadow = this.cast; im.receiveShadow = true;
    im.computeBoundingSphere();
    if (this.layer) im.layers.set(this.layer);
    scene.add(im);
    return im;
  }
}

const C = (h) => new THREE.Color(h);
const OAK = ['#5f9b46', '#6aa84b', '#558f45', '#4e8644', '#6f9f3f'];
const OAK_DARK = ['#4f8448', '#457a47', '#3f7046'];
const AUTUMN = ['#d6913c', '#cf7038', '#e2b448'];
const BLOSSOM = ['#eaa6bb', '#f0bccb'];
const PINE = ['#3e7552', '#477f55', '#386b4e'];
const ROCK = ['#a49aa2', '#958b96', '#b1a7a8'];

export function buildScenery(world, scene) {
  const occupied = []; // círculos (x,z,r) onde não espalhar
  const block = (x, z, r) => occupied.push([x, z, r]);
  const blocked = (x, z, pad = 0) => occupied.some(([ox, oz, r]) => (x - ox) ** 2 + (z - oz) ** 2 < (r + pad) ** 2);

  const trunkMat = toonMat({ color: 0xffffff, outline: 0.8, key: 'trunk' });
  const leafMat = toonMat({ color: 0xffffff, wind: 0.025, outline: 0.65, key: 'leaf' });
  const bushMat = toonMat({ color: 0xffffff, wind: 0.05, outline: 0.6, key: 'bush' });
  const rockMat = toonMat({ color: 0xffffff, flat: true, outline: 0.8, key: 'rock' });
  const sets = {
    oakTrunk: new Instancer(trunkGeo(), trunkMat),
    oak: [new Instancer(crownOak(1), leafMat), new Instancer(crownOak(7), leafMat)],
    pineTrunk: new Instancer(trunkGeo(0.9, 0.16, 0.12), trunkMat),
    pine: new Instancer(crownPine(), leafMat),
    bush: [new Instancer(crownBush(2), bushMat), new Instancer(crownBush(9), bushMat)],
    rock: [new Instancer(rockGeo(1), rockMat), new Instancer(rockGeo(5), rockMat), new Instancer(rockGeo(9), rockMat)],
  };

  const addTree = (x, z, kind = 'oak', s = 1, colors = null, collide = true) => {
    const y = world.heightAt(x, z) - 0.05;
    const rot = R(0, Math.PI * 2);
    if (kind === 'pine') {
      sets.pineTrunk.add(x, y, z, rot, s, C('#6e5040'));
      sets.pine.add(x, y, z, rot, s, C((colors || PINE)[Math.floor(rng() * (colors || PINE).length)]));
    } else {
      sets.oakTrunk.add(x, y, z, rot, s, C(rng() < 0.5 ? '#7b5b45' : '#6f513f'));
      const pal = colors || OAK;
      sets.oak[rng() < 0.5 ? 0 : 1].add(x, y, z, rot, s, C(pal[Math.floor(rng() * pal.length)]));
    }
    if (collide) world.addCircle(x, z, 0.32 * s);
    block(x, z, 1.1 * s);
  };
  const addBush = (x, z, s = 1, dark = false) => {
    const y = world.heightAt(x, z) - 0.04;
    const pal = dark ? ['#4a7a45', '#3f6f46'] : ['#5d9447', '#6aa04a', '#548a45'];
    sets.bush[rng() < 0.5 ? 0 : 1].add(x, y, z, R(0, 6.28), s, C(pal[Math.floor(rng() * pal.length)]));
    block(x, z, 0.5 * s);
  };
  const addRock = (x, z, s = 1, collide = true) => {
    const y = world.heightAt(x, z) - 0.1 * s;
    sets.rock[Math.floor(rng() * 3)].add(x, y, z, R(0, 6.28), s, C(ROCK[Math.floor(rng() * ROCK.length)]), s * R(0.7, 1.1));
    if (collide && s > 0.5) world.addCircle(x, z, 0.4 * s);
    block(x, z, 0.6 * s);
  };

  // ------------------------------------------------ estruturas da vila
  const village = new THREE.Group(); village.name = 'Vila';
  scene.add(village);
  const houses = [
    { at: [-9.6, 23.6], w: 3.4, d: 2.8, rot: 0, roof: '#c9653f', wall: '#ecdcbc', name: 'Casa do Ancião' },
    { at: [9.8, 23.2], w: 3.0, d: 3.0, rot: Math.PI / 2, roof: '#3f8c8c', wall: '#e7d6b6' },
    { at: [-8.8, 37.2], w: 3.2, d: 2.6, rot: Math.PI / 2, roof: '#8b5b8e', wall: '#eadbc0' },
    { at: [9.4, 37.4], w: 3.6, d: 2.8, rot: 0, roof: '#5b72a6', wall: '#efe0c4', floors: 2 },
    { at: [-13.6, 31], w: 2.6, d: 2.4, rot: Math.PI / 2, roof: '#c9653f', wall: '#e3d2b0' },
  ];
  for (const h of houses) {
    const w = toWorld(...h.at);
    const g = house(h);
    g.position.set(w.x, world.heightAt(w.x, w.z) - 0.05, w.z);
    g.rotation.y = h.rot;
    village.add(g);
    world.addBox(w.x, w.z, h.w / 2 + 0.15, h.d / 2 + 0.15, h.rot);
    block(w.x, w.z, Math.max(h.w, h.d) * 0.85);
  }
  // poço
  {
    const w = toWorld(PLACES.plaza[0] + 1.6, PLACES.plaza[1] - 0.6);
    const g = well(); g.position.set(w.x, world.heightAt(w.x, w.z), w.z); village.add(g);
    world.addCircle(w.x, w.z, 0.78); block(w.x, w.z, 1.2);
  }
  // barraca do mercador
  {
    const w = toWorld(PLACES.merchant[0] + 0.4, PLACES.merchant[1] + 1.1);
    const g = stall(); g.position.set(w.x, world.heightAt(w.x, w.z), w.z); g.rotation.y = -Math.PI / 4; village.add(g);
    world.addBox(w.x, w.z, 1.25, 0.55, -Math.PI / 4); block(w.x, w.z, 1.8);
  }
  // lampiões
  const lamps = [];
  for (const at of [[-3.2, 25.5], [3.6, 25.2], [-3.4, 33.6], [3.4, 33.8], [0.9, 19.5]]) {
    const w = toWorld(...at);
    const g = lamp(); g.position.set(w.x, world.heightAt(w.x, w.z), w.z); village.add(g);
    world.addCircle(w.x, w.z, 0.15); block(w.x, w.z, 0.5);
    lamps.push(g);
  }
  // caixotes, barris, feno, bancos
  const clutter = [
    ['barrel', -7.2, 25.4], ['barrel', -6.6, 25.9], ['crate', 7.6, 25.2], ['crate', 7.8, 25.9, 0.5], ['barrel', 6.2, 30.6],
    ['crate', 6.4, 33.6], ['hay', -11.5, 34.2], ['hay', -12.2, 33.4], ['bench', -3.9, 29.3], ['bench', 3.9, 29.8],
    ['barrel', 11.6, 35.2], ['crate', -6.4, 38.6], ['sign', 2.2, 16.5], ['sign', -2.4, -12.6], ['bench', -11.5, 28.4],
  ];
  for (const [k, u, v, s] of clutter) {
    const w = toWorld(u, v);
    let g;
    if (k === 'barrel') g = barrel(); else if (k === 'crate') g = crate(); else if (k === 'hay') g = hay(); else if (k === 'sign') g = signpost(); else g = bench();
    g.position.set(w.x, world.heightAt(w.x, w.z) + (s || 0), w.z);
    g.rotation.y = R(-0.3, 0.3) + (k === 'bench' ? Math.PI / 4 : 0);
    village.add(g);
    if (k !== 'sign') world.addCircle(w.x, w.z, k === 'bench' ? 0.45 : 0.36);
    block(w.x, w.z, 0.7);
  }
  // varal com roupas (balançam)
  const cloth = [];
  {
    const a = toWorld(-12.6, 26), b = toWorld(-12.4, 29.3);
    const g = clothesline(a, b, world, cloth); village.add(g);
  }
  // cercas
  const fences = [
    [[-15, 22.5], [-13, 20], [-9, 19.5], [-4.5, 20.5]],
    [[4.5, 20.4], [8.5, 19.4], [12.5, 20.2], [15, 23]],
    [[12, 30], [14.2, 31.2], [15, 34]],
    [[-15.2, 35], [-13.2, 38.6], [-11, 40]],
  ];
  for (const pts of fences) village.add(fence(pts, world, block));
  // canteiros de flor junto às casas
  for (const [u, v, c] of [[-7.4, 22.3, '#e85d75'], [7.6, 22.4, '#f4d35e'], [-6.8, 36, '#9db7f0'], [7.4, 36.4, '#ef8fa8']]) {
    const w = toWorld(u, v); const g = flowerBed(c); g.position.set(w.x, world.heightAt(w.x, w.z), w.z); g.rotation.y = Math.PI / 4; village.add(g); block(w.x, w.z, 0.8);
  }

  // ------------------------------------------------ ponte
  {
    const b = world.bridge;
    const g = bridge(b, world); scene.add(g);
  }
  // ------------------------------------------------ portão do bosque
  const gate = forestGate(world);
  scene.add(gate.group);
  block(gate.x, gate.z, 3.5);

  // ------------------------------------------------ ruínas da clareira
  const ruins = new THREE.Group(); ruins.name = 'Ruinas'; scene.add(ruins);
  for (let i = 0; i < 9; i++) {
    const a = (i / 9) * Math.PI * 2 + 0.2;
    if (Math.abs(Math.sin(a) - 1) < 0.15 && Math.cos(a) > -0.3 && Math.cos(a) < 0.3) continue; // entrada (sul)
    const u = Math.cos(a) * 8.2, v = -30 + Math.sin(a) * 7.6;
    if (v > -23.4 && Math.abs(u) < 3) continue;
    const w = toWorld(u, v);
    const g = pillar(i % 3 === 0 ? 2.4 : i % 3 === 1 ? 1.2 : 1.8, i);
    g.position.set(w.x, world.heightAt(w.x, w.z) - 0.1, w.z); g.rotation.y = a;
    ruins.add(g);
    world.addCircle(w.x, w.z, 0.5); block(w.x, w.z, 1.2);
  }
  block(...Object.values(toWorld(0, -30)), 7.5);

  // ------------------------------------------------ áreas livres
  for (const p of [PLACES.spawn, PLACES.plaza, PLACES.meadow, PLACES.hollow, PLACES.plateauW]) { const w = toWorld(...p); block(w.x, w.z, p === PLACES.plaza ? 5.2 : 3); }
  const onPath = (u, v, pad) => { const m = world.maskAt(u, v); return m.path > 0.15 - pad || m.plaza > 0.1; };

  // ------------------------------------------------ espalhar vegetação
  const tryPlace = (u, v, minD) => {
    const w = toWorld(u, v);
    if (blocked(w.x, w.z, minD)) return null;
    if (onPath(u, v, 0)) return null;
    for (const [du, dv] of [[1, 0], [-1, 0], [0, 1], [0, -1]]) if (onPath(u + du * 0.9, v + dv * 0.9, 0)) return null;
    if (world.slopeAt(u, v) > 0.35) return null;
    const h = world.heightAt(w.x, w.z);
    if (h < -0.15) return null;
    const mk = world.maskAt(u, v);
    if (mk.sand > 0.4) return null;
    return { ...w, h, mk };
  };
  // borda (planaltos fora da área jogável): floresta densa
  for (let v = -47; v < 46; v += 1.25) for (let u = -40; u < 40; u += 1.25) {
    const uu = u + R(-0.5, 0.5), vv = v + R(-0.5, 0.5);
    const w = toWorld(uu, vv);
    const h = world.heightAt(w.x, w.z);
    const deep = world.maskAt(uu, vv).dark;
    const outside = !world.walkableUV(uu, vv) || h > 1.5 + (vv < -14 ? LH : 0);
    const dens = outside ? 0.62 : 0.0;
    if (rng() > dens) continue;
    const pl = tryPlace(uu, vv, 0.3);
    if (!pl) continue;
    const pine = vv < -12 || (deep > 0.6 && rng() < 0.5);
    addTree(pl.x, pl.z, pine ? 'pine' : 'oak', R(0.85, 1.35), pine ? null : (rng() < 0.4 ? OAK_DARK : OAK), false);
  }
  // árvores dentro da área jogável (bosquetes)
  const groves = [
    [[-20, 1], 4, 6], [[20, 2], 4, 5], [[-10, 9], 2.5, 3], [[14, 11], 3, 4], [[-21, -8], 3, 4], [[23, -10], 3, 4],
    [[-5, -9], 2, 2], [[6, -10], 2.5, 3], [[-14, 20], 2.5, 3], [[15, 27], 2, 3], [[-17, 13], 3, 4], [[18, 15], 3, 3],
    [[-5, -20], 2, 3], [[5, -21], 2, 3], [[-7, -36], 3, 4], [[7, -36], 3, 4], [[-30, 6], 2, 2],
  ];
  for (const [c, r, n0] of groves) {
    let n = n0;
    for (let i = 0; i < n * 3 && n > 0; i++) {
      const a = R(0, 6.28), d = Math.sqrt(rng()) * r;
      const pl = tryPlace(c[0] + Math.cos(a) * d, c[1] + Math.sin(a) * d, 0.6);
      if (!pl) continue;
      const north = c[1] < -12;
      addTree(pl.x, pl.z, north && rng() < 0.6 ? 'pine' : 'oak', R(0.9, 1.25));
      n--;
      if (n <= 0) break;
    }
  }
  // árvores especiais da vila
  for (const [u, v, pal] of [[-4.2, 22], [5, 21.6], [-12, 36.5], [13.5, 33], [-1, 40.5], [-15, 26]].map((x, i) => [...x, i < 2 ? BLOSSOM : i < 4 ? AUTUMN : OAK])) {
    const pl = tryPlace(u, v, 0.2); if (pl) addTree(pl.x, pl.z, 'oak', R(0.95, 1.15), pal);
  }
  // arbustos e pedras
  for (let i = 0; i < 520; i++) {
    const uu = R(-36, 36), vv = R(-44, 42);
    const pl = tryPlace(uu, vv, 0.25);
    if (!pl) continue;
    const r = rng();
    if (r < 0.55) addBush(pl.x, pl.z, R(0.7, 1.2), pl.mk.dark > 0.5);
    else if (r < 0.8) addRock(pl.x, pl.z, R(0.35, 0.8), false);
    else if (r < 0.88) addRock(pl.x, pl.z, R(0.9, 1.5));
  }
  // pedrinhas na beira do rio
  for (let u = -26; u < 26; u += 1.4) {
    if (rng() < 0.45) continue;
    const side = rng() < 0.5 ? -1 : 1;
    const vv = riverV(u) + side * R(1.6, 2.6);
    const pl = tryPlace(u, vv, 0.1);
    if (pl) addRock(pl.x, pl.z, R(0.25, 0.55), false);
  }

  for (const s of Object.values(sets)) (Array.isArray(s) ? s : [s]).forEach((x) => x.build(scene));

  return { gate, lamps, cloth, blocked };
}

// =============================================================================
// Construtores de peças
// =============================================================================
const WOOD = '#7a5642', WOOD_D = '#5e3f31', WOOD_L = '#9a7050', STONE = '#a59a93', STONE_D = '#8b7f7c';

function house({ w, d, roof, wall, floors = 1 }) {
  const g = new THREE.Group();
  const wh = floors === 2 ? 2.5 : 1.65;
  g.add(box(w + 0.24, 0.38, d + 0.24, STONE, { base: true }));
  g.add(box(w, wh, d, wall, { base: true, p: [0, 0.38, 0] }));
  // enxaimel
  const bw = 0.11;
  for (const sx of [-1, 1]) for (const sz of [-1, 1]) g.add(box(bw * 1.4, wh, bw * 1.4, WOOD_D, { base: true, p: [sx * w / 2, 0.38, sz * d / 2] }));
  for (const y of floors === 2 ? [0.38 + 1.2, 0.38 + wh - 0.06] : [0.38 + wh - 0.06]) {
    g.add(box(w + 0.06, bw, bw, WOOD_D, { p: [0, y, d / 2 + 0.02] }));
    g.add(box(w + 0.06, bw, bw, WOOD_D, { p: [0, y, -d / 2 - 0.02] }));
    g.add(box(bw, bw, d + 0.06, WOOD_D, { p: [w / 2 + 0.02, y, 0] }));
    g.add(box(bw, bw, d + 0.06, WOOD_D, { p: [-w / 2 - 0.02, y, 0] }));
  }
  for (const sx of [-0.5, 0.5]) {
    const br = box(bw, wh * 0.75, bw, WOOD_D, { p: [sx * w * 0.6, 0.38 + wh * 0.45, d / 2 + 0.03], r: [0, 0, sx * 0.7] });
    g.add(br);
  }
  // porta (frente = +z) e janelas
  g.add(box(0.7, 1.15, 0.1, WOOD_D, { base: true, p: [-w * 0.18, 0.38, d / 2 + 0.03] }));
  g.add(box(0.56, 1.02, 0.1, '#6a4534', { base: true, p: [-w * 0.18, 0.38, d / 2 + 0.07] }));
  g.add(box(0.08, 0.08, 0.06, '#e8c36a', { p: [-w * 0.18 + 0.18, 0.95, d / 2 + 0.14] }));
  g.add(box(0.9, 0.08, 0.5, STONE_D, { base: true, p: [-w * 0.18, 0, d / 2 + 0.3] }));
  const win = (x, y, z, ry) => {
    const wg = new THREE.Group();
    wg.add(box(0.62, 0.6, 0.08, WOOD_D));
    const glass = new THREE.Mesh(new THREE.BoxGeometry(0.46, 0.44, 0.06), unlitMat(0xffd98a, { outline: 0.6 }));
    glass.position.z = 0.03; wg.add(glass);
    wg.add(box(0.06, 0.44, 0.04, WOOD_D, { p: [0, 0, 0.07] }));
    wg.add(box(0.46, 0.06, 0.04, WOOD_D, { p: [0, 0, 0.07] }));
    wg.add(box(0.2, 0.56, 0.05, '#4f7fa0', { p: [-0.44, 0, 0.05] }));
    wg.add(box(0.2, 0.56, 0.05, '#4f7fa0', { p: [0.44, 0, 0.05] }));
    wg.add(box(0.72, 0.16, 0.22, WOOD, { p: [0, -0.38, 0.12] }));
    for (let i = 0; i < 4; i++) wg.add(box(0.12, 0.12, 0.12, ['#e85d75', '#f4d35e', '#f6f1e0', '#ef8fa8'][i], { p: [-0.26 + i * 0.17, -0.25, 0.14], cast: false }));
    wg.position.set(x, y, z); wg.rotation.y = ry; g.add(wg);
  };
  win(w * 0.22, 1.25, d / 2 + 0.03, 0);
  win(w / 2 + 0.03, 1.25, 0, Math.PI / 2);
  win(-w / 2 - 0.03, 1.25, -d * 0.15, -Math.PI / 2);
  if (floors === 2) { win(-w * 0.2, 2.35, d / 2 + 0.03, 0); win(w * 0.25, 2.35, d / 2 + 0.03, 0); }
  // telhado de duas águas com fileiras de telhas
  const top = 0.38 + wh;
  const rh = d * 0.62, over = 0.32;
  const half = d / 2 + over;
  const slope = Math.atan2(rh, d / 2);
  const len = Math.hypot(half, rh * (half / (d / 2)));
  const rows = 5;
  const tones = [roof, shade(roof, 0.88)];
  for (const side of [-1, 1]) {
    for (let r = 0; r < rows; r++) {
      const t0 = r / rows;
      const pl = box(w + over * 2 + 0.02, 0.13, len / rows + 0.05, tones[r % 2]);
      const along = (t0 + 0.5 / rows) * len;
      pl.position.set(0, top + rh * (half / (d / 2)) - Math.sin(slope) * along - 0.12 + r * 0.012, side * Math.cos(slope) * along - side * 0.0);
      pl.rotation.x = side * slope;
      g.add(pl);
    }
  }
  g.add(box(w + over * 2 + 0.1, 0.16, 0.2, shade(roof, 0.75), { p: [0, top + rh * (half / (d / 2)) - 0.1, 0] }));
  // empenas
  const tri = new THREE.Shape(); tri.moveTo(-d / 2, 0); tri.lineTo(d / 2, 0); tri.lineTo(0, rh); tri.closePath();
  const tg = new THREE.ExtrudeGeometry(tri, { depth: w - 0.02, bevelEnabled: false });
  tg.rotateY(Math.PI / 2); tg.translate(-(w - 0.02) / 2, top, 0);
  const gm = new THREE.Mesh(tg, mat(wall)); gm.castShadow = true; gm.receiveShadow = true; g.add(gm);
  g.add(box(bw, rh * 0.8, bw, WOOD_D, { base: true, p: [w / 2 + 0.01, top, 0] }));
  g.add(box(bw, rh * 0.8, bw, WOOD_D, { base: true, p: [-w / 2 - 0.01, top, 0] }));
  // chaminé
  const ch = box(0.45, 1.3, 0.45, STONE_D, { base: true, p: [w * 0.28, top + rh * 0.2, -d * 0.18] });
  g.add(ch);
  g.add(box(0.55, 0.12, 0.55, STONE, { p: [w * 0.28, top + rh * 0.2 + 1.3, -d * 0.18] }));
  g.userData.chimney = new THREE.Vector3(w * 0.28, top + rh * 0.2 + 1.45, -d * 0.18);
  return g;
}

function shade(hexc, k) { const c = new THREE.Color(hexc); c.multiplyScalar(k); return '#' + c.getHexString(); }

function well() {
  const g = new THREE.Group();
  const ring = new THREE.Mesh(new THREE.CylinderGeometry(0.72, 0.78, 0.7, 10, 1, true), mat(STONE, { side: THREE.DoubleSide }));
  ring.position.y = 0.35; ring.castShadow = true; ring.receiveShadow = true; g.add(ring);
  const rim = new THREE.Mesh(new THREE.TorusGeometry(0.72, 0.1, 5, 10), mat('#b8aca3'));
  rim.rotation.x = Math.PI / 2; rim.position.y = 0.72; g.add(rim);
  const water = new THREE.Mesh(new THREE.CircleGeometry(0.66, 10), unlitMat(0x3d8bb3)); water.rotation.x = -Math.PI / 2; water.position.y = 0.45; g.add(water);
  for (const s of [-1, 1]) g.add(box(0.1, 1.5, 0.1, WOOD, { base: true, p: [s * 0.66, 0.6, 0] }));
  g.add(box(1.6, 0.08, 0.08, WOOD_D, { p: [0, 1.85, 0] }));
  for (const s of [-1, 1]) { const r = box(1.75, 0.08, 0.72, '#c9653f', { p: [0, 2.12, s * 0.27], r: [s * 0.55, 0, 0] }); g.add(r); }
  g.add(box(0.22, 0.24, 0.22, WOOD_L, { p: [0.15, 1.35, 0] }));
  return g;
}

function stall() {
  const g = new THREE.Group();
  g.add(box(2.4, 0.85, 0.9, WOOD, { base: true }));
  g.add(box(2.5, 0.08, 1.0, WOOD_L, { p: [0, 0.88, 0] }));
  for (const sx of [-1.15, 1.15]) for (const sz of [-0.42, 0.42]) g.add(box(0.09, 2.1, 0.09, WOOD_D, { base: true, p: [sx, 0, sz] }));
  const cols = ['#e9e2cf', '#d4553f'];
  for (let i = 0; i < 6; i++) { const s = box(0.43, 0.06, 1.4, cols[i % 2], { p: [-1.07 + i * 0.43, 2.12, 0.18], r: [-0.32, 0, 0] }); g.add(s); }
  for (let i = 0; i < 6; i++) g.add(box(0.43, 0.2, 0.04, cols[i % 2], { p: [-1.07 + i * 0.43, 1.82, 0.86] }));
  // mercadorias
  const goods = ['#e2563f', '#f2c14e', '#8fbf4a', '#e2563f', '#b36ad1'];
  goods.forEach((c, i) => { const m = new THREE.Mesh(new THREE.IcosahedronGeometry(0.13, 0), mat(c, { flat: true })); m.position.set(-0.9 + i * 0.42, 1.02, 0.05); m.castShadow = true; g.add(m); });
  const pot = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.12, 0.26, 6), mat('#d64f6a')); pot.position.set(0.95, 1.05, -0.25); g.add(pot);
  const pot2 = new THREE.Mesh(new THREE.CylinderGeometry(0.09, 0.12, 0.26, 6), mat('#4fa0d6')); pot2.position.set(0.7, 1.05, -0.3); g.add(pot2);
  return g;
}

function lamp() {
  const g = new THREE.Group();
  g.add(box(0.12, 1.9, 0.12, '#4b4256', { base: true }));
  g.add(box(0.26, 0.14, 0.26, '#4b4256', { base: true }));
  g.add(box(0.5, 0.06, 0.06, '#4b4256', { p: [0.2, 1.85, 0] }));
  const lan = new THREE.Mesh(new THREE.BoxGeometry(0.22, 0.28, 0.22), unlitMat(0xffd27a, { outline: 0.7 }));
  lan.position.set(0.4, 1.66, 0); g.add(lan);
  g.add(box(0.28, 0.06, 0.28, '#4b4256', { p: [0.4, 1.83, 0] }));
  g.userData.light = new THREE.Vector3(0.4, 1.66, 0);
  return g;
}

function barrel() {
  const g = new THREE.Group();
  const b = new THREE.Mesh(new THREE.CylinderGeometry(0.3, 0.3, 0.72, 8), mat('#8a6043')); b.position.y = 0.36; b.castShadow = true; b.receiveShadow = true; g.add(b);
  for (const y of [0.14, 0.58]) { const r = new THREE.Mesh(new THREE.CylinderGeometry(0.315, 0.315, 0.07, 8), mat('#55505e')); r.position.y = y; g.add(r); }
  const lid = new THREE.Mesh(new THREE.CylinderGeometry(0.26, 0.26, 0.02, 8), mat('#a07a55')); lid.position.y = 0.73; g.add(lid);
  return g;
}
function crate() {
  const g = new THREE.Group();
  g.add(box(0.62, 0.55, 0.62, '#b98a57', { base: true }));
  for (const s of [-1, 1]) { g.add(box(0.66, 0.1, 0.1, '#8a6141', { p: [0, 0.27, s * 0.29] })); g.add(box(0.1, 0.1, 0.66, '#8a6141', { p: [s * 0.29, 0.5, 0] })); }
  return g;
}
function hay() {
  const g = new THREE.Group();
  const h = new THREE.Mesh(new THREE.CylinderGeometry(0.45, 0.45, 0.8, 9), mat('#e3c062')); h.rotation.z = Math.PI / 2; h.position.y = 0.45; h.castShadow = true; g.add(h);
  for (const x of [-0.2, 0.2]) { const r = new THREE.Mesh(new THREE.CylinderGeometry(0.46, 0.46, 0.05, 9), mat('#b9903f')); r.rotation.z = Math.PI / 2; r.position.set(x, 0.45, 0); g.add(r); }
  return g;
}
function bench() {
  const g = new THREE.Group();
  g.add(box(1.3, 0.08, 0.38, WOOD_L, { p: [0, 0.42, 0] }));
  for (const s of [-0.5, 0.5]) g.add(box(0.1, 0.42, 0.32, WOOD_D, { base: true, p: [s, 0, 0] }));
  g.add(box(1.3, 0.28, 0.06, WOOD_L, { p: [0, 0.7, -0.17] }));
  return g;
}
function signpost() {
  const g = new THREE.Group();
  g.add(box(0.12, 1.3, 0.12, WOOD_D, { base: true }));
  g.add(box(0.95, 0.32, 0.06, WOOD_L, { p: [0.25, 1.05, 0], r: [0, 0.2, 0] }));
  g.add(box(0.12, 0.12, 0.07, WOOD_D, { p: [0.7, 1.05, 0.06], r: [0, 0, 0.78] }));
  return g;
}
function flowerBed(c) {
  const g = new THREE.Group();
  g.add(box(1.4, 0.22, 0.5, WOOD, { base: true }));
  g.add(box(1.3, 0.06, 0.4, '#5a3f30', { p: [0, 0.22, 0] }));
  for (let i = 0; i < 6; i++) {
    const s = new THREE.Mesh(new THREE.IcosahedronGeometry(0.11, 0), mat(i % 3 === 0 ? '#5e9a46' : c, { flat: true }));
    s.position.set(-0.55 + i * 0.22, 0.34, (i % 2 ? 0.08 : -0.08)); s.castShadow = true; g.add(s);
  }
  return g;
}
function clothesline(a, b, world, cloth) {
  const g = new THREE.Group();
  const ya = world.heightAt(a.x, a.z), yb = world.heightAt(b.x, b.z);
  for (const [p, y] of [[a, ya], [b, yb]]) g.add(box(0.1, 1.7, 0.1, WOOD_D, { base: true, p: [p.x, y, p.z] }));
  const cols = ['#e9e2cf', '#d4553f', '#4f7fa0', '#f2c14e'];
  for (let i = 0; i < 4; i++) {
    const t = (i + 0.7) / 4.6;
    const x = a.x + (b.x - a.x) * t, z = a.z + (b.z - a.z) * t, y = ya + (yb - ya) * t + 1.55;
    const piv = new THREE.Group(); piv.position.set(x, y, z); piv.rotation.y = Math.atan2(b.x - a.x, b.z - a.z) + Math.PI / 2;
    const c = box(0.5, 0.62, 0.03, cols[i], { p: [0, -0.33, 0], matOpts: { side: THREE.DoubleSide } });
    piv.add(c); piv.userData.dynamic = true; g.add(piv); cloth.push(piv);
  }
  const line = box(0.02, 0.02, Math.hypot(b.x - a.x, b.z - a.z), '#e9e2cf', { cast: false });
  line.position.set((a.x + b.x) / 2, (ya + yb) / 2 + 1.6, (a.z + b.z) / 2); line.rotation.y = Math.atan2(b.x - a.x, b.z - a.z);
  g.add(line);
  return g;
}

function fence(pts, world, block) {
  const g = new THREE.Group();
  for (let i = 0; i < pts.length - 1; i++) {
    const a = toWorld(...pts[i]), b = toWorld(...pts[i + 1]);
    const L = Math.hypot(b.x - a.x, b.z - a.z), n = Math.max(1, Math.round(L / 1.1));
    for (let k = 0; k <= n; k++) {
      const t = k / n, x = a.x + (b.x - a.x) * t, z = a.z + (b.z - a.z) * t, y = world.heightAt(x, z);
      if (k < n || i === pts.length - 2) g.add(box(0.13, 0.8, 0.13, WOOD_D, { base: true, p: [x, y - 0.05, z] }));
      if (k < n) {
        const t2 = (k + 1) / n, x2 = a.x + (b.x - a.x) * t2, z2 = a.z + (b.z - a.z) * t2, y2 = world.heightAt(x2, z2);
        for (const hh of [0.32, 0.6]) {
          const r = box(Math.hypot(x2 - x, z2 - z) + 0.05, 0.08, 0.06, WOOD_L);
          r.position.set((x + x2) / 2, (y + y2) / 2 + hh, (z + z2) / 2);
          r.rotation.y = -Math.atan2(z2 - z, x2 - x);
          r.rotation.z = Math.atan2(y2 - y, Math.hypot(x2 - x, z2 - z));
          g.add(r);
        }
        world.addBox((x + x2) / 2, (z + z2) / 2, Math.hypot(x2 - x, z2 - z) / 2, 0.12, -Math.atan2(z2 - z, x2 - x));
        block((x + x2) / 2, (z + z2) / 2, 0.7);
      }
    }
  }
  return g;
}

function bridge(b, world) {
  const g = new THREE.Group();
  g.rotation.y = Math.PI / 4;
  const c = toWorld(b.u, 0);
  g.position.set(c.x, 0, c.z);
  const n = 16;
  for (let i = 0; i < n; i++) {
    const t = (i + 0.5) / n, v = b.v0 + (b.v1 - b.v0) * t;
    const y = b.y + Math.sin(t * Math.PI) * 0.25;
    const p = box(b.hw * 2 + 0.1, 0.12, (b.v1 - b.v0) / n - 0.04, i % 2 ? WOOD_L : '#8d6548', { p: [0, y - 0.06, v], r: [0, (i % 3 - 1) * 0.02, 0] });
    g.add(p);
  }
  for (const s of [-1, 1]) {
    for (let i = 0; i <= 4; i++) {
      const t = i / 4, v = b.v0 + (b.v1 - b.v0) * t, y = b.y + Math.sin(t * Math.PI) * 0.25;
      g.add(box(0.13, 0.75 + (i === 0 || i === 4 ? 0.2 : 0), 0.13, WOOD_D, { base: true, p: [s * (b.hw + 0.02), y - 0.3, v] }));
      if (i < 4) {
        const t2 = (i + 1) / 4, v2 = b.v0 + (b.v1 - b.v0) * t2, y2 = b.y + Math.sin(t2 * Math.PI) * 0.25;
        const r = box(0.08, 0.08, v2 - v + 0.05, WOOD_L, { p: [s * (b.hw + 0.02), (y + y2) / 2 + 0.4, (v + v2) / 2], r: [-Math.atan2(y2 - y, v2 - v), 0, 0] });
        g.add(r);
      }
    }
    // pilares na água
    for (const t of [0.3, 0.7]) { const v = b.v0 + (b.v1 - b.v0) * t; g.add(box(0.2, 1.2, 0.2, WOOD_D, { base: true, p: [s * (b.hw - 0.2), -1.1, v] })); }
  }
  // corrimãos como colisores (laterais)
  for (const s of [-1, 1]) {
    const mid = toWorld(b.u + s * (b.hw + 0.12), (b.v0 + b.v1) / 2);
    world.addBox(mid.x, mid.z, 0.1, (b.v1 - b.v0) / 2 - 0.6, Math.PI / 4);
  }
  return g;
}

function forestGate(world) {
  const g = new THREE.Group();
  const [u, v] = PLACES.gate;
  const c = toWorld(u, v);
  const y = world.heightAt(c.x, c.z);
  g.position.set(c.x, y, c.z);
  g.rotation.y = Math.PI / 4; // local x = u
  const doors = new THREE.Group(); g.add(doors);
  for (const s of [-1, 1]) {
    g.add(box(0.42, 2.6, 0.42, WOOD_D, { base: true, p: [s * 2.3, -0.2, 0] }));
    const cap = new THREE.Mesh(new THREE.ConeGeometry(0.32, 0.4, 4), mat('#6e9a4a')); cap.position.set(s * 2.3, 2.55, 0); cap.rotation.y = Math.PI / 4; g.add(cap);
    const leaf = new THREE.Group(); leaf.position.set(s * 2.1, 0, 0); doors.add(leaf);
    for (let i = 0; i < 5; i++) {
      const hgt = 1.9 + (i % 2) * 0.18;
      const plank = box(0.38, hgt, 0.14, i % 2 ? WOOD : '#6d4a3a', { base: true, p: [-s * (0.21 + i * 0.4), -0.1, 0] });
      leaf.add(plank);
      const tip = new THREE.Mesh(new THREE.ConeGeometry(0.2, 0.3, 4), mat(i % 2 ? WOOD : '#6d4a3a')); tip.position.set(-s * (0.21 + i * 0.4), hgt - 0.0, 0); tip.rotation.y = Math.PI / 4; leaf.add(tip);
    }
    leaf.add(box(2.0, 0.14, 0.08, WOOD_D, { p: [-s * 1.0, 0.5, 0.1] }));
    leaf.add(box(2.0, 0.14, 0.08, WOOD_D, { p: [-s * 1.0, 1.4, 0.1] }));
  }
  // cadeado com runa
  const lock = new THREE.Mesh(new THREE.BoxGeometry(0.34, 0.4, 0.14), unlitMat(0xf2c14e, { outline: 0.8 }));
  lock.position.set(0, 1.05, 0.2); g.add(lock);
  // trepadeiras com espinhos
  const vines = new THREE.Group(); g.add(vines);
  for (let i = 0; i < 14; i++) {
    const t = new THREE.Mesh(new THREE.IcosahedronGeometry(R(0.18, 0.3), 0), mat(i % 3 ? '#4f7d46' : '#6a8f3e', { flat: true }));
    t.position.set(R(-2.2, 2.2), R(0.2, 1.9), R(0.05, 0.3)); t.castShadow = true; vines.add(t);
  }
  for (let i = 0; i < 10; i++) {
    const f = new THREE.Mesh(new THREE.OctahedronGeometry(0.09, 0), mat('#c44d6d', { flat: true }));
    f.position.set(R(-2, 2), R(0.4, 1.8), 0.33); vines.add(f);
  }
  const col = world.addBox(c.x, c.z, 2.4, 0.35, Math.PI / 4);
  return { group: g, doors, lock, vines, collider: col, x: c.x, z: c.z, open: false, t: 0 };
}

function pillar(h, seed) {
  const g = new THREE.Group();
  g.add(box(0.95, 0.3, 0.95, STONE_D, { base: true }));
  const body = new THREE.Mesh(new THREE.CylinderGeometry(0.36, 0.42, h, 7), mat('#b3a9a6'));
  body.position.y = 0.3 + h / 2; body.rotation.z = (seed % 2 ? 0.06 : -0.05); body.castShadow = true; body.receiveShadow = true; g.add(body);
  if (h > 2) g.add(box(0.9, 0.24, 0.9, STONE, { p: [0, 0.3 + h + 0.1, 0] }));
  // musgo
  const moss = new THREE.Mesh(new THREE.IcosahedronGeometry(0.3, 0), mat('#6e9d4c', { flat: true }));
  moss.position.set(0.25, 0.4, 0.2); moss.scale.set(1, 0.5, 1); g.add(moss);
  // pedra caída
  if (h < 1.5) { const r = box(0.6, 0.4, 0.5, '#b3a9a6', { p: [0.8, 0.2, 0.3], r: [0.2, 0.5, 0.1] }); g.add(r); }
  // runa brilhante
  const rune = new THREE.Mesh(new THREE.BoxGeometry(0.16, 0.24, 0.05), unlitMat(0x7fe0c8, { outline: 0.5 }));
  rune.position.set(0, 0.3 + h * 0.55, 0.39); rune.userData.dynamic = true; g.add(rune);
  g.userData.rune = rune;
  return g;
}

/**
 * Junta malhas estáticas de um grupo por material (menos chamadas de desenho).
 * Ignora filhos marcados com userData.dynamic (e seus descendentes).
 */
export function mergeStatic(root) {
  root.updateMatrixWorld(true);
  const inv = new THREE.Matrix4().copy(root.matrixWorld).invert();
  const buckets = new Map();
  const remove = [];
  const visit = (o, dyn) => {
    dyn = dyn || !!o.userData.dynamic;
    if (o.isMesh && !o.isInstancedMesh && !dyn && o.layers.mask === 1) {
      const g = (o.geometry.index ? o.geometry.toNonIndexed() : o.geometry.clone());
      for (const k of Object.keys(g.attributes)) if (!['position', 'normal', 'uv'].includes(k)) g.deleteAttribute(k);
      if (!g.attributes.uv) g.setAttribute('uv', new THREE.Float32BufferAttribute(new Float32Array(g.attributes.position.count * 2), 2));
      g.applyMatrix4(new THREE.Matrix4().multiplyMatrices(inv, o.matrixWorld));
      const key = o.material.uuid + '|' + o.castShadow;
      if (!buckets.has(key)) buckets.set(key, { mat: o.material, cast: o.castShadow, geos: [] });
      buckets.get(key).geos.push(g);
      remove.push(o);
    }
    for (const c of o.children) visit(c, dyn);
  };
  visit(root, false);
  for (const o of remove) o.parent.remove(o);
  for (const { mat: m, cast, geos } of buckets.values()) {
    const merged = mergeGeometries(geos);
    const mesh = new THREE.Mesh(merged, m);
    mesh.castShadow = cast; mesh.receiveShadow = true;
    root.add(mesh);
  }
  return buckets.size;
}
