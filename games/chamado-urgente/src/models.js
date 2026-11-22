import * as THREE from 'three';
import { RoundedBoxGeometry } from 'three/addons/geometries/RoundedBoxGeometry.js';
import { PALETTE } from './config.js';
import * as TX from './textures.js';
import { toonMat } from './toon.js';

// ---------------------------------------------------------------------------
// Fábrica de materiais/geometrias com cache
const matCache = new Map();
export function mat(color, opts = {}) {
  const key = color + JSON.stringify(opts);
  if (!matCache.has(key)) {
    matCache.set(key, toonMat({ color, ...opts }));
  }
  return matCache.get(key);
}

const geoCache = new Map();
function rbox(w, h, d, r) {
  const key = `${w}|${h}|${d}|${r}`;
  if (!geoCache.has(key)) {
    const rr = Math.min(r, w / 2 - 0.001, h / 2 - 0.001, d / 2 - 0.001);
    geoCache.set(key, rr > 0.004 ? new RoundedBoxGeometry(w, h, d, 3, rr) : new THREE.BoxGeometry(w, h, d));
  }
  return geoCache.get(key);
}

export function shadowify(obj, cast = true, receive = true) {
  obj.traverse((o) => { if (o.isMesh) { o.castShadow = cast; o.receiveShadow = receive; } });
  return obj;
}

/** caixa arredondada: centro em (x,y,z) */
export function box(w, h, d, color, x = 0, y = 0, z = 0, r = 0.04, opts) {
  const m = new THREE.Mesh(rbox(w, h, d, r), color instanceof THREE.Material ? color : mat(color, opts));
  m.position.set(x, y, z);
  m.castShadow = true; m.receiveShadow = true;
  return m;
}

export function cyl(rt, rb, h, color, x = 0, y = 0, z = 0, seg = 16, opts) {
  const m = new THREE.Mesh(new THREE.CylinderGeometry(rt, rb, h, seg), color instanceof THREE.Material ? color : mat(color, opts));
  m.position.set(x, y, z);
  m.castShadow = true; m.receiveShadow = true;
  return m;
}

export function sphere(r, color, x = 0, y = 0, z = 0, opts) {
  const m = new THREE.Mesh(new THREE.SphereGeometry(r, 20, 14), color instanceof THREE.Material ? color : mat(color, opts));
  m.position.set(x, y, z);
  m.castShadow = true; m.receiveShadow = true;
  return m;
}

export function capsule(r, len, color) {
  const m = new THREE.Mesh(new THREE.CapsuleGeometry(r, len, 6, 12), color instanceof THREE.Material ? color : mat(color));
  m.castShadow = true;
  return m;
}

// ---------------------------------------------------------------------------
// Mobília

export function makeDesk(screenTex, dividerColor = 0x6fb1c8) {
  const g = new THREE.Group();
  // tampo
  g.add(box(1.75, 0.08, 0.9, PALETTE.desk, 0, 0.74, 0, 0.03));
  g.add(box(1.77, 0.04, 0.92, PALETTE.woodDark, 0, 0.69, 0, 0.02));
  for (const sx of [-0.8, 0.8]) g.add(box(0.07, 0.7, 0.8, PALETTE.metal, sx, 0.35, 0, 0.02));
  // divisória de baia
  g.add(box(1.75, 0.5, 0.07, dividerColor, 0, 1.02, -0.47, 0.03));
  g.add(box(1.79, 0.05, 0.1, PALETTE.wallTrim, 0, 1.28, -0.47, 0.02));
  // gabinete (PC)
  const tower = new THREE.Group();
  tower.add(box(0.24, 0.48, 0.48, 0x2a2f3d, 0, 0.24, 0, 0.04));
  tower.add(box(0.02, 0.38, 0.02, 0x6fb1c8, 0.121, 0.28, 0.2, 0.005, { emissive: 0x6fb1c8, emissiveIntensity: 1.5 }));
  const pcLed = sphere(0.025, mat(0x2fc46b, { emissive: 0x2fc46b, emissiveIntensity: 2 }), 0.12, 0.42, 0.18);
  tower.add(pcLed);
  tower.position.set(0.55, 0, 0.05);
  g.add(tower);
  // monitor
  const mon = new THREE.Group();
  mon.add(box(0.28, 0.03, 0.2, 0x2a2f3d, 0, 0.0, 0, 0.01));
  mon.add(box(0.06, 0.24, 0.05, 0x2a2f3d, 0, 0.12, -0.03, 0.01));
  mon.add(box(0.82, 0.52, 0.06, 0x1d2129, 0, 0.42, 0, 0.03));
  const screenMat = new THREE.MeshBasicMaterial({ map: screenTex, toneMapped: false });
  screenMat.color.setScalar(0.92);
  const screen = new THREE.Mesh(new THREE.PlaneGeometry(0.75, 0.45), screenMat);
  screen.position.set(0, 0.42, 0.032);
  mon.add(screen);
  mon.position.set(0, 0.78, -0.18);
  g.add(mon);
  // teclado, mouse, caneca, papéis
  g.add(box(0.5, 0.03, 0.16, 0xe9eef7, -0.05, 0.795, 0.2, 0.012));
  g.add(box(0.07, 0.03, 0.1, 0xe9eef7, 0.34, 0.795, 0.22, 0.02));
  const mug = cyl(0.05, 0.045, 0.11, [0xff5a5a, 0xffd23f, 0x3d7bff, 0x2fc46b][Math.floor(Math.random() * 4)], -0.6, 0.84, 0.05);
  g.add(mug);
  const papers = box(0.24, 0.03, 0.32, 0xffffff, 0.62, 0.795, -0.1, 0.005); papers.rotation.y = 0.3; g.add(papers);
  shadowify(g);
  return { group: g, screen, screenMat, tower, pcLed, monitor: mon };
}

export function makeChair(color = 0x3b4566) {
  const g = new THREE.Group();
  const base = new THREE.Group();
  for (let i = 0; i < 5; i++) {
    const a = (i / 5) * Math.PI * 2;
    const leg = box(0.32, 0.04, 0.06, 0x2a2f3d, Math.cos(a) * 0.16, 0.06, Math.sin(a) * 0.16, 0.015);
    leg.rotation.y = -a; base.add(leg);
    base.add(sphere(0.04, 0x1d2540, Math.cos(a) * 0.3, 0.04, Math.sin(a) * 0.3));
  }
  g.add(base);
  g.add(cyl(0.035, 0.035, 0.32, PALETTE.metal, 0, 0.24, 0));
  g.add(box(0.5, 0.09, 0.48, color, 0, 0.44, 0, 0.04));
  g.add(box(0.48, 0.5, 0.08, color, 0, 0.75, -0.24, 0.04));
  shadowify(g);
  return g;
}

export function makePrinter() {
  const g = new THREE.Group();
  const body = new THREE.Group();
  g.add(body);
  body.add(box(1.0, 0.72, 0.8, 0xe9eef7, 0, 0.36, 0, 0.06));
  body.add(box(1.02, 0.14, 0.82, 0x9aa3b5, 0, 0.12, 0, 0.04));
  // gavetas de papel
  const tray = box(0.86, 0.12, 0.04, 0xcfd6e4, 0, 0.3, 0.41, 0.02);
  body.add(tray);
  body.add(box(0.86, 0.12, 0.04, 0xcfd6e4, 0, 0.14, 0.41, 0.02));
  body.add(box(0.3, 0.025, 0.03, 0x2a2f3d, 0, 0.3, 0.44, 0.01));
  // scanner / tampa
  body.add(box(0.96, 0.1, 0.76, 0x3b4566, 0, 0.77, 0, 0.04));
  body.add(box(0.7, 0.03, 0.3, 0x2a2f3d, 0, 0.61, 0.38, 0.01)); // saída de papel
  // folhas na saída
  const outPaper = box(0.5, 0.02, 0.28, 0xffffff, 0, 0.64, 0.3, 0.004);
  body.add(outPaper);
  // painel
  const panel = box(0.32, 0.05, 0.18, 0x2a2f3d, 0.3, 0.83, 0.3, 0.02);
  panel.rotation.x = 0.35; body.add(panel);
  const ledMat = new THREE.MeshStandardMaterial({ color: 0x2fc46b, emissive: 0x2fc46b, emissiveIntensity: 2.5 });
  const led = sphere(0.035, ledMat, 0.4, 0.865, 0.33); body.add(led);
  // papel amassado (emperrada)
  const crumple = new THREE.Group();
  for (let i = 0; i < 3; i++) {
    const c = new THREE.Mesh(new THREE.IcosahedronGeometry(0.12 - i * 0.02, 0), mat(0xffffff, { flatShading: true }));
    c.position.set(-0.15 + i * 0.16, 0.7 + i * 0.03, 0.3 - i * 0.04); c.rotation.set(i, i * 2, 0);
    c.castShadow = true; crumple.add(c);
  }
  crumple.visible = false;
  body.add(crumple);
  // marcas de queimado
  const soot = box(1.04, 0.3, 0.84, 0x23201f, 0, 0.62, 0, 0.06, { transparent: true, opacity: 0.0 });
  soot.castShadow = false; body.add(soot);
  shadowify(g);
  return { group: g, body, led, ledMat, crumple, outPaper, tray, soot };
}

export function makeShelf(kind) {
  const g = new THREE.Group();
  const W = 1.5, D = 0.6, H = 1.6;
  for (const sx of [-W / 2, W / 2]) for (const sz of [-D / 2 + 0.03, D / 2 - 0.03]) g.add(box(0.05, H, 0.05, 0x3b4566, sx, H / 2, sz, 0.01));
  const levels = [0.15, 0.62, 1.1, 1.56];
  for (const y of levels) g.add(box(W + 0.04, 0.04, D, 0xcfd6e4, 0, y, 0, 0.01));
  // estoque exposto
  const stock = new THREE.Group();
  for (const y of levels.slice(0, 3)) {
    for (let i = 0; i < 3; i++) {
      const it = makeItemMesh(kind);
      it.position.set(-0.45 + i * 0.45, y + 0.02, 0.02);
      it.rotation.y = (i - 1) * 0.15;
      stock.add(it);
    }
  }
  g.add(stock);
  shadowify(g);
  return g;
}

export function makeRack() {
  const g = new THREE.Group();
  g.add(box(0.9, 2.0, 0.8, 0x23283a, 0, 1.0, 0, 0.04));
  g.add(box(0.8, 1.84, 0.02, 0x161a27, 0, 1.0, 0.41, 0.01));
  const leds = [];
  for (let r = 0; r < 9; r++) {
    g.add(box(0.74, 0.14, 0.03, 0x3b4566, 0, 0.25 + r * 0.19, 0.42, 0.01));
    for (let k = 0; k < 4; k++) {
      const m = new THREE.MeshStandardMaterial({ color: 0x2fc46b, emissive: 0x2fc46b, emissiveIntensity: 2.2 });
      const led = new THREE.Mesh(new THREE.BoxGeometry(0.035, 0.035, 0.02), m);
      led.position.set(-0.3 + k * 0.08, 0.25 + r * 0.19, 0.44);
      g.add(led); leds.push(led);
    }
  }
  // roteador em cima com antenas
  const router = new THREE.Group();
  router.add(box(0.6, 0.1, 0.4, 0xf4efe6, 0, 0.05, 0, 0.04));
  for (const sx of [-0.22, 0, 0.22]) {
    const ant = cyl(0.02, 0.02, 0.34, 0x2a2f3d, sx, 0.25, -0.15); ant.rotation.x = -0.2; router.add(ant);
  }
  const rled = new THREE.MeshStandardMaterial({ color: 0x3fa9ff, emissive: 0x3fa9ff, emissiveIntensity: 2.5 });
  for (let k = 0; k < 4; k++) {
    const l = new THREE.Mesh(new THREE.BoxGeometry(0.04, 0.02, 0.02), rled);
    l.position.set(-0.18 + k * 0.12, 0.07, 0.2); router.add(l);
  }
  router.position.y = 2.0;
  g.add(router);
  shadowify(g);
  return { group: g, leds, routerLed: rled, router };
}

export function makeCoffeeMachine() {
  const g = new THREE.Group();
  g.add(box(1.4, 0.9, 0.7, PALETTE.wood, 0, 0.45, 0, 0.04));
  g.add(box(1.44, 0.06, 0.74, 0xf4efe6, 0, 0.92, 0, 0.02));
  const m = new THREE.Group();
  m.add(box(0.5, 0.62, 0.45, 0x2a2f3d, 0, 0.31, 0, 0.06));
  m.add(box(0.36, 0.14, 0.05, 0xb0122b, 0, 0.5, 0.23, 0.02));
  m.add(box(0.3, 0.04, 0.2, 0x9aa3b5, 0, 0.06, 0.15, 0.01));
  m.add(cyl(0.05, 0.045, 0.1, 0xffffff, 0, 0.13, 0.15));
  const glow = new THREE.MeshStandardMaterial({ color: 0xffd23f, emissive: 0xffb02b, emissiveIntensity: 2 });
  const l = new THREE.Mesh(new THREE.SphereGeometry(0.03, 8, 8), glow); l.position.set(0.17, 0.5, 0.26); m.add(l);
  m.position.set(-0.2, 0.95, -0.05);
  g.add(m);
  // xícaras empilhadas
  for (let i = 0; i < 3; i++) g.add(cyl(0.05, 0.045, 0.09, [0xff5a5a, 0x3d7bff, 0xffd23f][i], 0.35 + i * 0.12, 1.0, 0.1));
  g.add(cyl(0.12, 0.1, 0.25, 0x8e5b34, 0.45, 1.07, -0.15));
  shadowify(g);
  return g;
}

export function makePlant(size = 1) {
  const g = new THREE.Group();
  g.add(cyl(0.22 * size, 0.17 * size, 0.38 * size, PALETTE.pot, 0, 0.19 * size, 0));
  g.add(cyl(0.2 * size, 0.2 * size, 0.04 * size, 0x5a3b26, 0, 0.37 * size, 0));
  const leafMat = mat(PALETTE.plant, { flatShading: true });
  const n = 7;
  for (let i = 0; i < n; i++) {
    const a = (i / n) * Math.PI * 2;
    const leaf = new THREE.Mesh(new THREE.IcosahedronGeometry(0.2 * size, 0), leafMat);
    leaf.scale.set(0.6, 1.5, 0.35);
    leaf.position.set(Math.cos(a) * 0.14 * size, 0.62 * size, Math.sin(a) * 0.14 * size);
    leaf.rotation.set(Math.sin(a) * 0.6, -a, Math.cos(a) * 0.6);
    leaf.castShadow = true; g.add(leaf);
  }
  g.add(new THREE.Mesh(new THREE.IcosahedronGeometry(0.2 * size, 0), mat(0x3f9a58, { flatShading: true })).translateY(0.75 * size));
  shadowify(g);
  return g;
}

export function makeWaterCooler() {
  const g = new THREE.Group();
  g.add(box(0.42, 0.95, 0.42, 0xf4efe6, 0, 0.475, 0, 0.05));
  g.add(cyl(0.18, 0.18, 0.45, mat(0x7fc8ff, { transparent: true, opacity: 0.7, roughness: 0.3 }), 0, 1.18, 0));
  g.add(box(0.06, 0.06, 0.06, 0x3d7bff, -0.08, 0.75, 0.22, 0.01));
  g.add(box(0.06, 0.06, 0.06, 0xff5a5a, 0.08, 0.75, 0.22, 0.01));
  shadowify(g);
  return g;
}

export function makeWorkbench() {
  const g = new THREE.Group();
  g.add(box(2.2, 0.08, 0.85, PALETTE.wood, 0, 0.84, 0, 0.03));
  for (const sx of [-1.0, 1.0]) for (const sz of [-0.35, 0.35]) g.add(box(0.07, 0.8, 0.07, 0x3b4566, sx, 0.4, sz, 0.01));
  g.add(box(2.1, 0.04, 0.75, 0x9aa3b5, 0, 0.25, 0, 0.01));
  // pegboard com ferramentas
  g.add(box(2.2, 1.0, 0.05, 0xd8b07a, 0, 1.45, -0.42, 0.02));
  const tools = [[0xff5a5a, -0.7], [0xffd23f, -0.35], [0x3d7bff, 0.1], [0x2fc46b, 0.5]];
  for (const [c, x] of tools) g.add(box(0.08, 0.35, 0.04, c, x, 1.5, -0.38, 0.02));
  // PC aberto em manutenção
  g.add(box(0.5, 0.45, 0.25, 0x2a2f3d, -0.5, 1.1, 0.05, 0.03));
  g.add(box(0.4, 0.03, 0.3, 0x2fc46b, 0.45, 0.9, 0.1, 0.01));
  shadowify(g);
  return g;
}

export function makeTrash() {
  const g = new THREE.Group();
  g.add(cyl(0.2, 0.16, 0.42, 0x3b4566, 0, 0.21, 0, 14));
  g.add(new THREE.Mesh(new THREE.IcosahedronGeometry(0.1, 0), mat(0xffffff, { flatShading: true })).translateY(0.42));
  shadowify(g);
  return g;
}

export function makeWhiteboard() {
  const g = new THREE.Group();
  g.add(box(2.0, 1.1, 0.05, 0xffffff, 0, 1.6, 0, 0.02));
  g.add(box(2.06, 1.16, 0.03, 0x9aa3b5, 0, 1.6, -0.02, 0.02));
  const scribble = new THREE.Mesh(new THREE.PlaneGeometry(1.8, 0.9), new THREE.MeshBasicMaterial({ map: TX.posterTexture(['SLA', '< 30min!!', '☕ = ♥'], '#ffffff'), transparent: true }));
  scribble.position.set(0, 1.6, 0.03);
  g.add(scribble);
  shadowify(g);
  return g;
}

// ---------------------------------------------------------------------------
// Itens carregáveis

export function makeItemMesh(kind) {
  const g = new THREE.Group();
  if (kind === 'cable') {
    const coilMat = mat(0x3fa9ff, { roughness: 0.5 });
    for (let i = 0; i < 3; i++) {
      const t = new THREE.Mesh(new THREE.TorusGeometry(0.15, 0.035, 8, 24), coilMat);
      t.rotation.x = Math.PI / 2; t.position.y = 0.04 + i * 0.05; t.castShadow = true; g.add(t);
    }
    const plug = box(0.07, 0.06, 0.1, 0xe9eef7, 0.19, 0.09, 0.05, 0.015); g.add(plug);
    g.add(box(0.05, 0.02, 0.03, 0xffd23f, 0.19, 0.09, 0.11, 0.005));
  } else if (kind === 'paper') {
    g.add(box(0.42, 0.14, 0.3, 0xffffff, 0, 0.07, 0, 0.02));
    g.add(box(0.43, 0.145, 0.12, 0x3fa9ff, 0, 0.07, 0, 0.02));
  } else if (kind === 'extinguisher') {
    g.add(cyl(0.1, 0.1, 0.48, 0xff3b3b, 0, 0.26, 0, 16, { roughness: 0.35 }));
    g.add(sphere(0.1, mat(0xff3b3b, { roughness: 0.35 }), 0, 0.5, 0));
    g.add(box(0.12, 0.13, 0.01, 0xffffff, 0, 0.27, 0.1, 0.004));
    g.add(box(0.05, 0.08, 0.05, 0x2a2f3d, 0, 0.62, 0, 0.01));
    const hose = new THREE.Mesh(new THREE.TorusGeometry(0.1, 0.018, 6, 12, Math.PI), mat(0x1d2540));
    hose.position.set(0.0, 0.58, 0.1); hose.rotation.y = Math.PI / 2; g.add(hose);
    g.add(box(0.16, 0.025, 0.04, 0x2a2f3d, 0.06, 0.67, 0, 0.01));
  } else if (kind === 'pendrive') {
    g.add(box(0.2, 0.08, 0.32, 0x2fc46b, 0, 0.04, 0, 0.03));
    g.add(box(0.13, 0.05, 0.12, PALETTE.metal, 0, 0.04, 0.21, 0.01, { metalness: 0.7, roughness: 0.3 }));
    g.add(box(0.12, 0.01, 0.12, 0xffffff, 0, 0.085, -0.03, 0.004));
    g.add(new THREE.Mesh(new THREE.TorusGeometry(0.035, 0.012, 6, 12), mat(0xffd23f)).translateZ(-0.18).translateY(0.04));
  }
  shadowify(g, true, false);
  return g;
}

export function makeLooseCable() {
  // pedaço de cabo partido no chão (problema "cabo")
  const g = new THREE.Group();
  const curve = new THREE.CatmullRomCurve3([
    new THREE.Vector3(-0.5, 0.03, -0.2), new THREE.Vector3(-0.2, 0.03, 0.1), new THREE.Vector3(0.0, 0.03, 0.0), new THREE.Vector3(0.12, 0.1, 0.12),
  ]);
  const t1 = new THREE.Mesh(new THREE.TubeGeometry(curve, 20, 0.025, 6), mat(0x3fa9ff));
  const curve2 = new THREE.CatmullRomCurve3([
    new THREE.Vector3(0.3, 0.1, 0.2), new THREE.Vector3(0.45, 0.03, 0.35), new THREE.Vector3(0.7, 0.03, 0.2),
  ]);
  const t2 = new THREE.Mesh(new THREE.TubeGeometry(curve2, 12, 0.025, 6), mat(0x3fa9ff));
  g.add(t1, t2);
  g.add(sphere(0.04, mat(0xffd23f, { emissive: 0xffb02b, emissiveIntensity: 1.5 }), 0.12, 0.1, 0.12));
  g.add(sphere(0.04, mat(0xffd23f, { emissive: 0xffb02b, emissiveIntensity: 1.5 }), 0.3, 0.1, 0.2));
  shadowify(g, true, false);
  return g;
}
