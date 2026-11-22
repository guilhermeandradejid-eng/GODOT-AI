import * as THREE from 'three';
import { toonMat, unlitMat } from './materials.js';

// =============================================================================
// Personagens "chibi" montados com primitivas (cabeça grande, corpo curto) e animados
// por poses procedurais. As poses são amostradas a 12 quadros/s ("animação em 2s"),
// como em sprites; o deslocamento no mundo continua suave. A direção é presa em 8 lados.
// =============================================================================

const ANIM_FPS = 12;

export class Rig {
  constructor(flash) {
    this.flash = flash || { value: 0 };
    this.mats = new Map();
    this.root = new THREE.Group();
    this.parts = {};
  }
  m(color, opts = {}) {
    const k = color + JSON.stringify(opts);
    if (!this.mats.has(k)) this.mats.set(k, toonMat({ color, flash: this.flash, outline: 0.95, ...opts }));
    return this.mats.get(k);
  }
  mesh(geo, color, parent, pos, opts = {}) {
    const mm = new THREE.Mesh(geo, opts.unlit ? unlitMat(color, { outline: 0.9 }) : this.m(color, opts.mat || {}));
    mm.castShadow = opts.cast ?? true; mm.receiveShadow = true;
    if (pos) mm.position.set(...pos);
    if (opts.rot) mm.rotation.set(...opts.rot);
    if (opts.scale) mm.scale.set(...opts.scale);
    (parent || this.root).add(mm);
    return mm;
  }
  pivot(parent, pos, name) {
    const g = new THREE.Group(); g.position.set(...pos); (parent || this.root).add(g);
    if (name) this.parts[name] = g;
    return g;
  }
}

const B = (w, h, d, oy = 0) => { const g = new THREE.BoxGeometry(w, h, d); if (oy) g.translate(0, oy, 0); return g; };
const SPH = (r, ws = 10, hs = 8) => new THREE.SphereGeometry(r, ws, hs);

// ---------------------------------------------------------------- humanoide
/**
 * look: { skin, hair, hairStyle, tunic, tunic2, pants, boots, scarf, weapon, hat, beard, eyes, height }
 */
export function buildHumanoid(look, flash) {
  const r = new Rig(flash);
  const L = { skin: '#f2c9a0', hair: '#7a3f2c', tunic: '#3f7fae', tunic2: '#2f5f88', pants: '#4b3d5e', boots: '#5e3f31', ...look };
  const body = r.pivot(r.root, [0, 0, 0], 'body');
  const hips = r.pivot(body, [0, 0.4, 0], 'hips');
  // pernas
  for (const s of [-1, 1]) {
    const leg = r.pivot(hips, [s * 0.1, 0, 0], s < 0 ? 'legR' : 'legL');
    r.mesh(B(0.14, 0.26, 0.14, -0.13), L.pants, leg);
    r.mesh(B(0.16, 0.13, 0.22, -0.32), L.boots, leg, [0, 0, 0.03]);
  }
  // tronco
  const chest = r.pivot(hips, [0, 0.02, 0], 'chest');
  r.mesh(B(0.42, 0.36, 0.3, 0.18), L.tunic, chest);
  r.mesh(B(0.48, 0.14, 0.34, 0.03), L.tunic2, chest);
  r.mesh(B(0.44, 0.06, 0.32, 0.12), L.belt || '#5e3f31', chest);
  r.mesh(B(0.08, 0.07, 0.04), '#e8c36a', chest, [0.06, 0.12, 0.17]);
  if (L.cape) { const cape = r.pivot(chest, [0, 0.34, -0.15], 'cape'); r.mesh(B(0.44, 0.5, 0.05, -0.25), L.cape, cape); }
  if (L.pack) r.mesh(B(0.3, 0.3, 0.14, 0.2), '#8a6043', chest, [0, 0.02, -0.21]);
  // braços
  for (const s of [-1, 1]) {
    const arm = r.pivot(chest, [s * 0.27, 0.32, 0], s < 0 ? 'armR' : 'armL');
    r.mesh(B(0.12, 0.3, 0.12, -0.13), L.sleeve || L.tunic, arm);
    const hand = r.pivot(arm, [0, -0.3, 0], s < 0 ? 'handR' : 'handL');
    r.mesh(SPH(0.075, 6, 5), L.glove || L.skin, hand);
  }
  // cabeça
  const head = r.pivot(chest, [0, 0.38, 0], 'head');
  r.mesh(SPH(0.3, 12, 10), L.skin, head, [0, 0.27, 0], { scale: [1.05, 0.96, 1] });
  // olhos e bochechas
  const eyeC = L.eyes || '#2a2235';
  for (const s of [-1, 1]) {
    const e = r.mesh(B(0.06, 0.1, 0.04), eyeC, head, [s * 0.1, 0.25, 0.28], { cast: false });
    r.parts[s < 0 ? 'eyeL' : 'eyeR'] = e;
    r.mesh(B(0.025, 0.035, 0.02), '#ffffff', head, [s * 0.1 + 0.012, 0.275, 0.3], { cast: false, unlit: true });
    r.mesh(B(0.06, 0.03, 0.02), '#e89a8a', head, [s * 0.17, 0.17, 0.26], { cast: false });
  }
  // cabelo
  if (L.hairStyle !== 'bald') {
    const hairG = new THREE.SphereGeometry(0.325, 12, 9, 0, Math.PI * 2, 0, Math.PI * 0.56);
    r.mesh(hairG, L.hair, head, [0, 0.3, -0.015], { scale: [1.06, 1.0, 1.04], rot: [-0.32, 0, 0] });
    if (L.hairStyle === 'spiky' || !L.hairStyle) {
      [[-0.14, 0.47, 0.18, 0.5], [0.0, 0.5, 0.2, 0.0], [0.15, 0.46, 0.17, -0.5], [0.05, 0.58, -0.05, 0.2], [-0.2, 0.38, -0.18, 0.9]].forEach(([x, y, z, rz]) => {
        r.mesh(new THREE.ConeGeometry(0.09, 0.22, 5), L.hair, head, [x, y, z], { rot: [0.9, 0, rz] });
      });
      r.mesh(B(0.5, 0.08, 0.16), L.hair, head, [0, 0.44, 0.16], { rot: [0.5, 0, 0] });
    } else if (L.hairStyle === 'long') {
      r.mesh(B(0.56, 0.42, 0.18, -0.12), L.hair, head, [0, 0.35, -0.2]);
      r.mesh(B(0.52, 0.09, 0.14), L.hair, head, [0, 0.44, 0.18], { rot: [0.5, 0, 0] });
    } else if (L.hairStyle === 'bun') {
      r.mesh(SPH(0.13, 7, 6), L.hair, head, [0, 0.62, -0.12]);
      r.mesh(B(0.52, 0.09, 0.14), L.hair, head, [0, 0.44, 0.18], { rot: [0.5, 0, 0] });
    }
  }
  if (L.hat === 'wizard') {
    r.mesh(new THREE.CylinderGeometry(0.42, 0.42, 0.05, 10), L.hatColor || '#5a4a8c', head, [0, 0.48, 0]);
    r.mesh(new THREE.ConeGeometry(0.24, 0.55, 8), L.hatColor || '#5a4a8c', head, [0, 0.75, -0.05], { rot: [-0.25, 0, 0] });
  } else if (L.hat === 'bandana') {
    r.mesh(new THREE.SphereGeometry(0.33, 10, 6, 0, Math.PI * 2, 0, Math.PI * 0.3), L.hatColor || '#d4553f', head, [0, 0.33, 0]);
  }
  if (L.beard) {
    r.mesh(B(0.36, 0.3, 0.14, -0.1), L.beard, head, [0, 0.16, 0.24]);
    r.mesh(B(0.2, 0.06, 0.05), L.beard, head, [0, 0.21, 0.31]);
  }
  // cachecol
  if (L.scarf) {
    r.mesh(new THREE.TorusGeometry(0.17, 0.06, 4, 8), L.scarf, chest, [0, 0.36, 0], { rot: [Math.PI / 2, 0, 0] });
    const tail = r.pivot(chest, [0.08, 0.36, -0.16], 'scarf');
    r.mesh(B(0.12, 0.05, 0.4, 0), L.scarf, tail, [0, 0, -0.2]);
  }
  // arma
  if (L.weapon === 'sword') {
    const w = r.pivot(r.parts.handR, [0, -0.02, 0.04], 'weapon');
    r.mesh(B(0.05, 0.15, 0.05, 0), '#5e3f31', w, [0, 0, 0], { rot: [Math.PI / 2, 0, 0] });
    r.mesh(B(0.22, 0.05, 0.07), '#e8c36a', w, [0, 0, 0.09]);
    const blade = r.mesh(B(0.07, 0.03, 0.62, 0), '#e3ebf2', w, [0, 0, 0.42]);
    r.parts.blade = blade;
    r.mesh(B(0.025, 0.035, 0.6), '#a7b6c8', w, [0.025, 0.01, 0.41], { cast: false });
  } else if (L.weapon === 'staff') {
    const w = r.pivot(r.parts.handR, [0, 0, 0], 'weapon');
    r.mesh(B(0.06, 1.2, 0.06, 0.25), '#7a5642', w);
    r.mesh(new THREE.OctahedronGeometry(0.1, 0), '#7fe0c8', w, [0, 0.9, 0], { unlit: true });
  }
  r.root.userData.rig = r;
  return r;
}

// ---------------------------------------------------------------- inimigos
export function buildSlime(color = '#6cc56a', flash) {
  const r = new Rig(flash);
  const body = r.pivot(r.root, [0, 0, 0], 'body');
  const blobG = new THREE.SphereGeometry(0.42, 12, 9);
  blobG.translate(0, 0.32, 0);
  const p = blobG.attributes.position;
  for (let i = 0; i < p.count; i++) { const y = p.getY(i); if (y < 0.12) p.setY(i, 0.12 - (0.12 - y) * 0.35); }
  blobG.computeVertexNormals();
  r.mesh(blobG, color, body, null, { scale: [1.1, 0.95, 1.1] });
  r.mesh(SPH(0.1, 6, 5), '#ffffff', body, [-0.17, 0.55, 0.22], { unlit: true, cast: false, scale: [1, 0.6, 0.5] });
  for (const s of [-1, 1]) {
    r.mesh(B(0.09, 0.16, 0.05), '#1f2a2a', body, [s * 0.13, 0.4, 0.42], { cast: false });
    r.mesh(B(0.035, 0.05, 0.02), '#ffffff', body, [s * 0.13 + 0.02, 0.44, 0.45], { cast: false, unlit: true });
  }
  r.mesh(B(0.12, 0.04, 0.03), '#1f2a2a', body, [0, 0.28, 0.44], { cast: false });
  r.root.userData.rig = r;
  return r;
}

export function buildMushroom(flash, cap = '#d4553f') {
  const r = new Rig(flash);
  const body = r.pivot(r.root, [0, 0, 0], 'body');
  r.mesh(new THREE.CylinderGeometry(0.22, 0.28, 0.5, 8), '#efe3c8', body, [0, 0.27, 0]);
  for (const s of [-1, 1]) {
    r.mesh(B(0.06, 0.11, 0.04), '#2a2235', body, [s * 0.09, 0.34, 0.24], { cast: false });
    const foot = r.pivot(body, [s * 0.12, 0.06, 0], s < 0 ? 'legL' : 'legR');
    r.mesh(B(0.14, 0.1, 0.2), '#c9b48c', foot, [0, -0.02, 0.04]);
  }
  const capP = r.pivot(body, [0, 0.55, 0], 'cap');
  const capG = new THREE.SphereGeometry(0.5, 12, 8, 0, Math.PI * 2, 0, Math.PI * 0.5);
  r.mesh(capG, cap, capP, [0, -0.05, 0], { scale: [1, 0.75, 1] });
  r.mesh(new THREE.CylinderGeometry(0.5, 0.42, 0.08, 12), '#c9a88a', capP, [0, -0.06, 0]);
  [[0.2, 0.22, 0.2], [-0.25, 0.18, 0.1], [0.0, 0.32, -0.12], [-0.05, 0.18, 0.34], [0.32, 0.14, -0.18]].forEach(([x, y, z]) => r.mesh(SPH(0.075, 6, 4), '#f6f1e0', capP, [x, y - 0.04, z], { scale: [1, 0.5, 1] }));
  r.root.userData.rig = r;
  return r;
}

export function buildBeetle(flash) {
  const r = new Rig(flash);
  const body = r.pivot(r.root, [0, 0, 0], 'body');
  const shell = new THREE.SphereGeometry(0.5, 12, 8, 0, Math.PI * 2, 0, Math.PI * 0.55);
  r.mesh(shell, '#6a4fa0', body, [0, 0.18, -0.05], { scale: [0.85, 0.8, 1.1] });
  r.mesh(B(0.03, 0.3, 0.8), '#4b3878', body, [0, 0.52, -0.05], { cast: false });
  r.mesh(SPH(0.24, 8, 6), '#3a2f4f', body, [0, 0.28, 0.48]);
  r.mesh(new THREE.ConeGeometry(0.08, 0.42, 5), '#e9dcc0', body, [0, 0.42, 0.72], { rot: [1.1, 0, 0] });
  for (const s of [-1, 1]) r.mesh(B(0.07, 0.07, 0.03), '#ffcf4a', body, [s * 0.12, 0.32, 0.68], { unlit: true, cast: false });
  for (let i = 0; i < 3; i++) for (const s of [-1, 1]) {
    const leg = r.pivot(body, [s * 0.34, 0.18, 0.25 - i * 0.28], `leg${i}${s}`);
    r.mesh(B(0.26, 0.05, 0.05, 0), '#2e2540', leg, [s * 0.1, -0.06, 0], { rot: [0, 0, s * -0.6] });
  }
  r.root.userData.rig = r;
  return r;
}

export function buildStumpBoss(flash) {
  const r = new Rig(flash);
  const body = r.pivot(r.root, [0, 0, 0], 'body');
  const trunk = new THREE.CylinderGeometry(1.15, 1.45, 2.3, 11, 3);
  trunk.translate(0, 1.15, 0);
  const p = trunk.attributes.position;
  for (let i = 0; i < p.count; i++) { const x = p.getX(i), z = p.getZ(i), a = Math.atan2(z, x); const k = 1 + Math.sin(a * 5) * 0.05 + Math.sin(a * 11) * 0.03; p.setX(i, x * k); p.setZ(i, z * k); }
  trunk.computeVertexNormals();
  r.mesh(trunk, '#7b5a48', body);
  // anéis no topo
  r.mesh(new THREE.CylinderGeometry(1.08, 1.08, 0.08, 11), '#d9b98a', body, [0, 2.32, 0]);
  r.mesh(new THREE.TorusGeometry(0.62, 0.05, 3, 11), '#b78f62', body, [0, 2.37, 0], { rot: [Math.PI / 2, 0, 0], cast: false });
  r.mesh(new THREE.TorusGeometry(0.3, 0.05, 3, 9), '#b78f62', body, [0, 2.37, 0], { rot: [Math.PI / 2, 0, 0], cast: false });
  // musgo e broto
  r.mesh(SPH(0.5, 8, 6), '#6e9d4c', body, [-0.55, 2.3, -0.3], { scale: [1.2, 0.4, 1] });
  r.mesh(SPH(0.35, 8, 6), '#5c8a46', body, [0.6, 2.28, 0.2], { scale: [1, 0.35, 1.1] });
  const sap = r.pivot(body, [0.15, 2.36, -0.2], 'sapling');
  r.mesh(B(0.06, 0.5, 0.06, 0.25), '#6e5040', sap);
  r.mesh(SPH(0.24, 7, 5), '#8bc45a', sap, [0, 0.55, 0], { mat: { wind: 0.1 } });
  // rosto entalhado
  const face = r.pivot(body, [0, 1.35, 1.2], 'face');
  for (const s of [-1, 1]) {
    r.mesh(B(0.36, 0.24, 0.12), '#2b1f2a', face, [s * 0.36, 0.1, 0], { rot: [0, 0, s * 0.25] });
    const eye = r.mesh(B(0.14, 0.12, 0.05), '#ffb347', face, [s * 0.36, 0.08, 0.06], { unlit: true, cast: false });
    r.parts[s < 0 ? 'eyeL' : 'eyeR'] = eye;
    r.mesh(B(0.42, 0.08, 0.1), '#4e3a33', face, [s * 0.36, 0.34, 0.04], { rot: [0, 0, s * -0.35] });
  }
  const mouth = r.pivot(face, [0, -0.42, 0], 'mouth');
  r.mesh(B(0.7, 0.22, 0.12), '#2b1f2a', mouth);
  for (let i = 0; i < 4; i++) r.mesh(B(0.1, 0.1, 0.05), '#e9dcc0', mouth, [-0.24 + i * 0.16, 0.08, 0.05], { cast: false });
  // cascas
  for (let i = 0; i < 9; i++) {
    const a = (i / 9) * Math.PI * 2 + 0.3;
    if (Math.abs(a - Math.PI / 2) < 0.5) continue;
    const bark = r.mesh(B(0.18, 1.6 + (i % 3) * 0.3, 0.12, 0), '#6a4b3c', body, [Math.cos(a) * 1.28, 1.0, Math.sin(a) * 1.28]);
    bark.rotation.y = -a + Math.PI / 2;
  }
  // braços-galho
  for (const s of [-1, 1]) {
    const arm = r.pivot(body, [s * 1.2, 1.6, 0.1], s < 0 ? 'armL' : 'armR');
    r.mesh(new THREE.CylinderGeometry(0.16, 0.26, 1.4, 6), '#6f513f', arm, [s * 0.55, -0.2, 0], { rot: [0, 0, s * 1.15] });
    const tw = r.pivot(arm, [s * 1.15, -0.5, 0], s < 0 ? 'clawL' : 'clawR');
    for (let k = 0; k < 3; k++) r.mesh(new THREE.ConeGeometry(0.08, 0.5, 4), '#5e4335', tw, [0, -0.15, (k - 1) * 0.14], { rot: [(k - 1) * 0.4, 0, Math.PI + s * 0.3] });
    r.mesh(SPH(0.25, 6, 5), '#6aa04a', arm, [s * 0.5, 0.05, 0.15], { mat: { wind: 0.06 } });
  }
  // raízes
  for (let i = 0; i < 7; i++) {
    const a = (i / 7) * Math.PI * 2;
    const root = r.mesh(new THREE.CylinderGeometry(0.08, 0.24, 1.1, 5), '#6a4b3c', body, [Math.cos(a) * 1.55, 0.18, Math.sin(a) * 1.55]);
    root.rotation.set(0, -a, Math.PI / 2 - 0.25); root.rotation.order = 'YZX';
  }
  r.root.userData.rig = r;
  return r;
}

// ---------------------------------------------------------------- animação
export class Animator {
  constructor(rig) {
    this.rig = rig;
    this.state = 'idle';
    this.t = 0;
    this.acc = 0;
    this.frameT = 0;
    this.dir = 0;
  }
  set(state, restart = false) {
    if (state !== this.state || restart) { this.state = state; this.t = 0; this.frameT = 0; this.acc = 1; }
  }
  update(dt) {
    this.t += dt;
    this.acc += dt;
    if (this.acc >= 1 / ANIM_FPS) {
      this.acc %= 1 / ANIM_FPS;
      this.frameT = this.t;
      return true;
    }
    return false;
  }
}

const P = (o, x = 0, y = 0, z = 0) => { if (o) o.rotation.set(x, y, z); };

/** aplica pose do humanoide. `t` = tempo no estado, `k` = progresso 0..1 para ações */
export function poseHumanoid(rig, state, t, k = 0, extra = {}) {
  const p = rig.parts;
  // neutro
  P(p.body); P(p.hips); P(p.chest); P(p.head); P(p.armL, 0, 0, 0.12); P(p.armR, 0, 0, -0.12); P(p.legL); P(p.legR);
  P(p.weapon, -0.15, 0, 0);
  p.body.position.set(0, 0, 0);
  p.hips.position.y = 0.4;
  if (p.scarf) P(p.scarf, 0.25 + Math.sin(t * 6) * 0.15, Math.sin(t * 4) * 0.25, 0);
  if (p.cape) P(p.cape, 0.12 + Math.sin(t * 3) * 0.04);
  switch (state) {
    case 'idle': {
      const b = Math.sin(t * 2.6);
      p.hips.position.y = 0.4 + (b > 0.3 ? -0.012 : 0);
      P(p.armL, 0, 0, 0.14 + b * 0.04); P(p.armR, 0.25, 0, -0.14 - b * 0.04);
      P(p.weapon, -0.45, 0, 0);
      P(p.head, 0, Math.sin(t * 0.7) * 0.08, 0);
      break;
    }
    case 'walk': case 'run': {
      const sp = state === 'run' ? 11 : 9;
      const s = Math.sin(t * sp), c = Math.cos(t * sp);
      P(p.legL, s * 0.75); P(p.legR, -s * 0.75);
      P(p.armL, -s * 0.7, 0, 0.15); P(p.armR, s * 0.5 + 0.2, 0, -0.15);
      P(p.weapon, -0.2 - s * 0.3, 0, 0);
      p.hips.position.y = 0.4 + Math.abs(c) * 0.05;
      P(p.chest, 0.08); P(p.head, -0.05);
      if (p.scarf) P(p.scarf, 0.9 + Math.sin(t * 14) * 0.2, Math.sin(t * 9) * 0.2, 0);
      if (p.cape) P(p.cape, 0.45 + Math.sin(t * 12) * 0.08);
      break;
    }
    case 'attack1': { // corte da direita para a esquerda
      const a = k < 0.25 ? k / 0.25 : 1;
      P(p.chest, 0.05, 0.6 - a * 1.3, 0);
      P(p.armR, -1.4, 0, -1.2 + a * 1.9);
      P(p.weapon, 1.45, 0, 0);
      P(p.armL, 0.3, 0, 0.5);
      P(p.legL, -0.3); P(p.legR, 0.35);
      break;
    }
    case 'attack2': { // revés
      const a = k < 0.25 ? k / 0.25 : 1;
      P(p.chest, 0.05, -0.7 + a * 1.35, 0);
      P(p.armR, -1.4, 0, 0.7 - a * 1.9);
      P(p.weapon, 1.45, 0, 0);
      P(p.armL, 0.2, 0, 0.3);
      P(p.legL, 0.35); P(p.legR, -0.3);
      break;
    }
    case 'attack3': { // golpe de cima
      const a = k < 0.3 ? k / 0.3 : 1;
      P(p.chest, -0.25 + a * 0.6);
      P(p.armR, -2.9 + a * 2.1, 0, -0.1); P(p.armL, -2.7 + a * 2.0, 0, 0.3);
      P(p.weapon, 1.5, 0, 0);
      p.hips.position.y = 0.4 - a * 0.08;
      P(p.legL, -0.5 * a); P(p.legR, 0.5 * a);
      break;
    }
    case 'charge': {
      const sh = Math.sin(t * 60) * 0.03;
      P(p.chest, 0.1, 0.9 + sh, 0);
      P(p.armR, -0.6, 0, -1.6); P(p.weapon, 1.5, 0, 0);
      P(p.armL, -0.4, 0, 0.6);
      P(p.legL, -0.4); P(p.legR, 0.4);
      p.hips.position.y = 0.36;
      break;
    }
    case 'spin': {
      p.body.rotation.y = -k * Math.PI * 2.2;
      P(p.armR, -1.5, 0, -1.4); P(p.weapon, 1.5, 0, 0); P(p.armL, -0.3, 0, 1.2);
      p.hips.position.y = 0.36;
      break;
    }
    case 'roll': {
      p.body.rotation.x = k * Math.PI * 2;
      p.body.position.y = Math.sin(k * Math.PI) * 0.15 + 0.1;
      p.body.position.z = 0;
      P(p.legL, -1.2); P(p.legR, -1.2); P(p.armL, -1.4, 0, 0.4); P(p.armR, -1.4, 0, -0.4); P(p.head, 0.4);
      break;
    }
    case 'cast': {
      const a = Math.min(1, k / 0.3);
      P(p.armR, -1.5 * a, 0, -0.1); P(p.armL, -1.2 * a, 0, 0.3); P(p.weapon, -1.2, 0, 0);
      P(p.chest, -0.1 * a);
      break;
    }
    case 'hurt': {
      P(p.chest, -0.35); P(p.head, -0.3); P(p.armL, -0.5, 0, 0.7); P(p.armR, -0.5, 0, -0.7);
      p.hips.position.y = 0.38;
      break;
    }
    case 'dead': {
      const a = Math.min(1, k);
      p.body.rotation.x = -a * Math.PI / 2;
      p.body.position.y = 0.12 * a;
      P(p.armL, -2.6 * a, 0, 0.3); P(p.armR, -2.6 * a, 0, -0.3);
      break;
    }
    case 'talk': {
      const b = Math.sin(t * 5);
      P(p.head, b * 0.08, Math.sin(t * 1.3) * 0.1, 0);
      P(p.armR, -0.6 - b * 0.2, 0, -0.3);
      P(p.armL, 0, 0, 0.15);
      P(p.weapon, -1.2, 0, 0);
      break;
    }
    case 'wave': {
      P(p.armR, -2.6, 0, -0.3 + Math.sin(t * 10) * 0.35); P(p.armL, 0, 0, 0.15);
      P(p.head, 0, 0, Math.sin(t * 3) * 0.08);
      break;
    }
    case 'victory': {
      P(p.armR, -3.0, 0, -0.2); P(p.weapon, 1.5, 0, 0); P(p.armL, 0, 0, 0.6);
      p.hips.position.y = 0.4 + Math.abs(Math.sin(t * 6)) * 0.12;
      break;
    }
    case 'sit': {
      p.hips.position.y = 0.2;
      P(p.legL, -1.5); P(p.legR, -1.5); P(p.armL, -0.4, 0, 0.2); P(p.armR, -0.4, 0, -0.2);
      P(p.head, 0.1 + Math.sin(t * 1.5) * 0.05);
      break;
    }
  }
}

export const snap8 = (a) => Math.round(a / (Math.PI / 4)) * (Math.PI / 4);
