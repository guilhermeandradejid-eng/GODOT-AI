import * as THREE from 'three';
import { toonMat } from './materials.js';
import { toWorld, TERRAIN_HEAD } from './world.js';
import { mulberry32 } from './noise.js';

// Grama em tufos (3 lâminas), instanciada em blocos. As normais apontam para cima e a cor vem
// da mesma função do terreno na raiz do tufo — a grama "é" o chão, só que com volume e vento.
// Fica na camada 1: não gera contorno nem sombra.

function tuftGeometry() {
  const pos = [];
  const blades = [[0, 0, 0.36, 0.0], [0.07, 0.04, 0.3, 2.1], [-0.06, 0.05, 0.27, 4.2], [0.02, -0.07, 0.24, 5.3]];
  for (const [ox, oz, h, a] of blades) {
    const w = 0.055, lx = Math.cos(a) * 0.09, lz = Math.sin(a) * 0.09;
    const px = -Math.sin(a) * w, pz = Math.cos(a) * w;
    pos.push(ox - px, 0, oz - pz, ox + px, 0, oz + pz, ox + lx, h, oz + lz);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(new Array(pos.length).fill(0).map((_, i) => (i % 3 === 1 ? 1 : 0)), 3));
  return g;
}

export function buildGrass(world, scene, exclude) {
  const rng = mulberry32(77);
  const geo = tuftGeometry();
  const mat = toonMat({
    key: 'grass', wind: 0.22, normalUp: true, side: THREE.DoubleSide, uniforms: world.textures(),
    vertHead: 'varying vec3 vRoot; varying float vTip;',
    vertBody: 'vRoot = vbRoot.xyz; vTip = position.y / 0.36;',
    fragHead: TERRAIN_HEAD + '\nvarying vec3 vRoot; varying float vTip;',
    albedoGLSL: `vec4 mm = mapMask(vRoot);
      float dith = (vb_bayer(gl_FragCoord.xy) - 0.5) * 0.07;
      vec3 g = grassAlbedo(vec3(vRoot.x, vRoot.y, vRoot.z), mm, dith);
      if (vTip > 0.62) g = g * vec3(1.1, 1.1, 1.02) + vec3(0.03, 0.03, 0.0);
      diffuseColor.rgb = g;`,
  });
  const CH = 10, chunks = new Map();
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), s = new THREE.Vector3(), p = new THREE.Vector3(), up = new THREE.Vector3(0, 1, 0);
  const step = 0.42;
  for (let v = -46; v < 44; v += step) {
    for (let u = -38; u < 38; u += step) {
      const uu = u + (rng() - 0.5) * step, vv = v + (rng() - 0.5) * step;
      const mk = world.maskAt(uu, vv);
      if (mk.path > 0.32 || mk.sand > 0.3 || mk.plaza > 0.25) continue;
      if (world.slopeAt(uu, vv) > 0.4) continue;
      const w = toWorld(uu, vv);
      const h = world.heightAt(w.x, w.z);
      if (h < -0.3) continue;
      if (exclude && exclude(w.x, w.z)) continue;
      const key = Math.floor(uu / CH) + ',' + Math.floor(vv / CH);
      if (!chunks.has(key)) chunks.set(key, []);
      const sc = 0.75 + rng() * 0.6 + (mk.dark > 0.5 ? 0.25 : 0);
      chunks.get(key).push([w.x, h, w.z, rng() * Math.PI * 2, sc]);
    }
  }
  let total = 0;
  for (const list of chunks.values()) {
    const im = new THREE.InstancedMesh(geo, mat, list.length);
    list.forEach(([x, y, z, a, sc], i) => {
      q.setFromAxisAngle(up, a); s.set(sc, sc * (0.8 + (i % 5) * 0.1), sc); p.set(x, y, z);
      m4.compose(p, q, s); im.setMatrixAt(i, m4);
    });
    im.computeBoundingSphere();
    im.layers.set(1);
    im.frustumCulled = true;
    scene.add(im);
    total += list.length;
  }
  return total;
}

// florzinhas: pontos coloridos acima da grama
export function buildFlowers(world, scene, zones, exclude) {
  const rng = mulberry32(19);
  const geo = new THREE.OctahedronGeometry(0.075, 0);
  geo.translate(0, 0.3, 0);
  const mat = toonMat({ key: 'flower', wind: 0.2, normalUp: true, outline: 0 });
  const colors = ['#f6f1e0', '#f4d35e', '#ef8fa8', '#9db7f0', '#f29e4c', '#e85d75'].map((c) => new THREE.Color(c));
  const items = [];
  for (const z of zones) {
    const n = z.n;
    for (let i = 0; i < n; i++) {
      const a = rng() * Math.PI * 2, r = Math.sqrt(rng()) * z.r;
      const uu = z.c[0] + Math.cos(a) * r, vv = z.c[1] + Math.sin(a) * r * (z.squash || 1);
      const mk = world.maskAt(uu, vv);
      if (mk.path > 0.3 || mk.sand > 0.3 || mk.plaza > 0.2 || world.slopeAt(uu, vv) > 0.3) continue;
      const w = toWorld(uu, vv);
      if (exclude && exclude(w.x, w.z)) continue;
      const h = world.heightAt(w.x, w.z);
      if (h < -0.3) continue;
      // em grupinhos da mesma cor
      const col = z.colors ? colors[z.colors[Math.floor(rng() * z.colors.length)]] : colors[Math.floor((vnoise2(uu, vv)) * colors.length) % colors.length];
      items.push([w.x, h, w.z, col]);
    }
  }
  const im = new THREE.InstancedMesh(geo, mat, items.length);
  const m4 = new THREE.Matrix4();
  items.forEach(([x, y, z, c], i) => { m4.makeTranslation(x, y, z); im.setMatrixAt(i, m4); im.setColorAt(i, c); });
  im.computeBoundingSphere();
  im.layers.set(1);
  scene.add(im);
  return items.length;
}
function vnoise2(u, v) { const s = Math.sin(Math.floor(u * 0.5) * 12.9898 + Math.floor(v * 0.5) * 78.233) * 43758.5453; return s - Math.floor(s); }
