import * as THREE from 'three';
import { toonMat, unlitMat } from './materials.js';
import { HumanoidAnimator } from './anim.js';

// =============================================================================
// Personagens "chibi" montados com primitivas (cabeça grande, corpo curto) e animados
// por poses procedurais. As poses são amostradas a 12 quadros/s ("animação em 2s"),
// como em sprites; o deslocamento no mundo continua suave. A direção é presa em 8 lados.
// =============================================================================

const ANIM_FPS = 240; // animação contínua (antes: 12 quadros/s em degraus)

export class Rig {
  constructor(flash) {
    this.flash = flash || { value: 0 };
    this.mats = new Map();
    this.root = new THREE.Group();
    this.parts = {};
  }
  m(color, opts = {}) {
    const k = color + JSON.stringify(opts);
    if (!this.mats.has(k)) this.mats.set(k, toonMat({ color, flash: this.flash, outline: 0.95, rim: 1, ...opts }));
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
const CAP = (r, len, rs = 8) => { const g = new THREE.CapsuleGeometry(r, len, 4, rs); g.translate(0, -len / 2, 0); return g; };
const ELL = (r, sx, sy, sz, ws = 10, hs = 8) => { const g = new THREE.SphereGeometry(r, ws, hs); g.scale(sx, sy, sz); return g; };

/**
 * Personagem chibi articulado (quadril, coluna, peito, cabeça, braço/antebraço/mão,
 * coxa/canela/pé) com rosto expressivo e peças secundárias com física (cachecol, cabelo,
 * saia, capa). Animado por HumanoidAnimator (anim.js).
 * look: { skin, hair, hairL, hairStyle (spiky|bun|short|long|bald), hat (bandana|wizard|straw),
 *         hatColor, tunic, tunic2, pants, boots, belt, scarf, cape, pack, weapon (sword|staff),
 *         beard, dress, glove, scale, eyes }
 */
export function buildHumanoid(look, flash) {
  const r = new Rig(flash);
  const L = { skin: '#f2c9a0', hair: '#7a3f2c', tunic: '#3f7fae', tunic2: '#2f5f88', pants: '#4b3d5e', boots: '#5e3f31', belt: '#6b4433', scale: 1, ...look };
  L.hairL = L.hairL || shadeHex(L.hair, 1.25);
  r.eyes = []; r.brows = []; r.chains = [];
  const chain = (obj, o) => { r.chains.push({ obj, base: [obj.rotation.x, 0, obj.rotation.z], kv: 0.1, ka: 0.012, max: 1.1, flutter: 8, amp: 0.08, ph: Math.random() * 6, w: 10, z: 0.32, ...o }); return obj; };
  r.root.scale.setScalar(L.scale);

  // corpo gira em torno da cintura (rolamento/giro); o squash escala a partir dos pés
  const body = r.pivot(r.root, [0, 0.4, 0], 'body');
  const squash = r.pivot(body, [0, -0.4, 0], 'squash');
  const hips = r.pivot(squash, [0, 0.4, 0], 'hips');

  // ---- pernas: coxa → joelho → pé (bota arredondada)
  for (const sd of [1, -1]) {
    const S = sd > 0 ? 'L' : 'R';
    const thigh = r.pivot(hips, [sd * 0.085, -0.02, 0], 'thigh' + S);
    r.mesh(CAP(0.07, 0.11), L.pants, thigh);
    const knee = r.pivot(thigh, [0, -0.15, 0], 'knee' + S);
    r.mesh(CAP(0.062, 0.09), L.pants, knee);
    r.mesh(new THREE.CylinderGeometry(0.075, 0.07, 0.06, 10).translate(0, -0.1, 0), L.boots, knee);
    const foot = r.pivot(knee, [0, -0.14, 0], 'foot' + S);
    r.mesh(ELL(0.085, 1, 0.68, 1.45), L.boots, foot, [0, -0.015, 0.035]);
    r.mesh(new THREE.BoxGeometry(0.15, 0.025, 0.22), shadeHex(L.boots, 0.7), foot, [0, -0.065, 0.035], { cast: false });
  }

  // ---- tronco em pera: barriga + peito, cinto, saia que esvoaça
  const spine = r.pivot(hips, [0, 0.02, 0], 'spine');
  r.mesh(ELL(0.17, 1.06, 0.92, 0.9, 14, 10), L.tunic, spine, [0, 0.06, 0]);
  const chest = r.pivot(spine, [0, 0.1, 0], 'chest');
  r.mesh(CAP(0.145, 0.06, 12), L.tunic, chest, [0, 0.13, 0], { scale: [1, 1, 0.86] });
  r.mesh(new THREE.TorusGeometry(0.168, 0.026, 5, 14), L.belt, spine, [0, 0.03, 0], { rot: [Math.PI / 2, 0, 0], scale: [1, 0.92, 1] });
  r.mesh(new THREE.BoxGeometry(0.07, 0.06, 0.03), '#e8c36a', spine, [0, 0.03, 0.16], { cast: false });
  if (L.dress) {
    const sk = r.pivot(spine, [0, 0.02, 0], 'skirt');
    r.mesh(new THREE.CylinderGeometry(0.17, 0.3, 0.34, 14, 1, true).translate(0, -0.17, 0), L.tunic2, sk, null, { mat: { side: THREE.DoubleSide } });
    chain(sk, { kv: 0.06, ka: 0.006, max: 0.35, w: 9, z: 0.4, amp: 0.03 });
  } else {
    const sk = r.pivot(spine, [0, 0.0, 0], 'skirt');
    r.mesh(new THREE.CylinderGeometry(0.172, 0.24, 0.15, 14, 1, true).translate(0, -0.075, 0), L.tunic2, sk, null, { mat: { side: THREE.DoubleSide } });
    chain(sk, { kv: 0.07, ka: 0.008, max: 0.45, w: 12, z: 0.35, amp: 0.04 });
  }

  // ---- braços: ombro (manga bufante) → cotovelo → mão
  for (const sd of [1, -1]) {
    const S = sd > 0 ? 'L' : 'R';
    const arm = r.pivot(chest, [sd * 0.19, 0.17, 0], 'arm' + S);
    r.mesh(new THREE.SphereGeometry(0.072, 10, 8), L.sleeve || L.tunic, arm, [0, -0.01, 0]);
    r.mesh(CAP(0.052, 0.08), L.sleeve || L.tunic, arm);
    const fore = r.pivot(arm, [0, -0.12, 0], 'fore' + S);
    r.mesh(CAP(0.047, 0.07), L.forearm || L.skin, fore);
    const hand = r.pivot(fore, [0, -0.11, 0], 'hand' + S);
    r.mesh(new THREE.SphereGeometry(0.06, 10, 8), L.glove || L.skin, hand, null, { scale: [1, 1.05, 0.9] });
  }
  r.arms = { armL: r.parts.armL, armR: r.parts.armR };

  // ---- cabeça
  const head = r.pivot(chest, [0, 0.24, 0], 'head');
  r.mesh(ELL(0.31, 1.04, 0.95, 0.98, 18, 14), L.skin, head, [0, 0.25, 0]);
  for (const sd of [1, -1]) r.mesh(new THREE.SphereGeometry(0.06, 8, 6), L.skin, head, [sd * 0.31, 0.21, -0.01], { scale: [0.6, 1, 0.9] });
  // olhos grandes com brilho, sobrancelhas, bochechas, boca
  for (const sd of [1, -1]) {
    const e = r.mesh(new THREE.SphereGeometry(0.06, 10, 8), L.eyes || '#2a2235', head, [sd * 0.112, 0.225, 0.27], { cast: false, scale: [0.85, 1.45, 0.5] });
    e.userData.sy = 1.45;
    r.eyes.push(e);
    r.mesh(new THREE.SphereGeometry(0.021, 6, 4), '#ffffff', e, [0.02, 0.026, 0.045], { cast: false, unlit: true, scale: [1 / 0.85, 1 / 1.45, 2] });
    const b = r.mesh(new THREE.BoxGeometry(0.085, 0.02, 0.02), L.hair === 'none' ? '#3a2a2a' : shadeHex(L.hair, 0.8), head, [sd * 0.11, 0.34, 0.272], { cast: false });
    b.userData.side = sd; b.userData.y = 0.34;
    r.brows.push(b);
    r.mesh(ELL(0.04, 1.3, 0.6, 0.4, 8, 6), '#f0a0a0', head, [sd * 0.18, 0.16, 0.25], { cast: false });
  }
  r.mouth = r.mesh(new THREE.BoxGeometry(0.06, 0.018, 0.02), '#6a2f3a', head, [0, 0.135, 0.29], { cast: false });
  r.mesh(new THREE.SphereGeometry(0.022, 6, 4), shadeHex(L.skin, 0.92), head, [0, 0.185, 0.305], { cast: false });

  // ---- cabelo
  const HS = L.hairStyle || 'spiky';
  if (HS !== 'bald') {
    const cap = new THREE.SphereGeometry(0.335, 16, 10, 0, Math.PI * 2, 0, Math.PI * 0.52);
    r.mesh(cap, L.hair, head, [0, 0.29, -0.03], { scale: [1.06, 1.0, 1.06], rot: [-0.5, 0, 0] });
    // franja: mechas que caem sobre a testa
    const fr = HS === 'spiky' ? [[-0.17, 0.47, 0.2, 0.5], [-0.05, 0.5, 0.24, 0.15], [0.08, 0.5, 0.23, -0.2], [0.19, 0.46, 0.18, -0.55]] : [[-0.13, 0.48, 0.22, 0.35], [0.0, 0.5, 0.24, 0], [0.13, 0.48, 0.22, -0.35]];
    for (const [x, y, z, rz] of fr) r.mesh(new THREE.ConeGeometry(0.07, 0.16, 6), L.hair, head, [x, y, z], { rot: [2.4, 0, rz] });
    if (HS === 'spiky') {
      [[-0.2, 0.5, -0.1, 0.7, -0.5], [0.0, 0.58, -0.12, 0.0, -0.7], [0.2, 0.5, -0.12, -0.7, -0.5], [-0.1, 0.44, -0.27, 0.4, -1.2], [0.12, 0.42, -0.27, -0.4, -1.2], [0, 0.34, -0.32, 0, -1.6]]
        .forEach(([x, y, z, rz, rx]) => r.mesh(new THREE.ConeGeometry(0.1, 0.28, 6), L.hair, head, [x, y, z], { rot: [rx, 0, rz] }));
      for (const sd of [1, -1]) r.mesh(new THREE.ConeGeometry(0.06, 0.2, 5), L.hair, head, [sd * 0.29, 0.25, 0.08], { rot: [2.9, 0, sd * -0.2] });
      // "antena" (ahoge) com mola
      const ah = r.pivot(head, [0.03, 0.6, 0.02], 'ahoge');
      r.mesh(new THREE.ConeGeometry(0.035, 0.2, 5).translate(0, 0.1, 0), L.hairL, ah, null, { rot: [0, 0, -0.5] });
      ah.rotation.x = -0.25;
      chain(ah, { kv: -0.12, ka: -0.02, max: 0.9, w: 13, z: 0.18, flutter: 4, amp: 0.05 });
    } else if (HS === 'bun') {
      r.mesh(new THREE.SphereGeometry(0.14, 10, 8), L.hair, head, [0, 0.58, -0.15]);
      r.mesh(new THREE.CylinderGeometry(0.012, 0.012, 0.32, 5), '#e8c36a', head, [0, 0.6, -0.15], { rot: [0, 0, 1.2], cast: false });
    } else if (HS === 'short') {
      for (const sd of [1, -1]) {
        const tail = r.pivot(head, [sd * 0.3, 0.38, -0.08], 'tail' + sd);
        r.mesh(new THREE.ConeGeometry(0.07, 0.22, 6).translate(0, -0.11, 0), L.hair, tail);
        tail.rotation.z = sd * 0.5;
        chain(tail, { kv: 0.12, ka: 0.02, max: 0.9, w: 9, z: 0.25, flutter: 6, amp: 0.1 });
      }
    } else if (HS === 'long') {
      const back = r.pivot(head, [0, 0.36, -0.22], 'longhair');
      r.mesh(CAP(0.17, 0.22, 10), L.hair, back, [0, -0.02, 0], { scale: [1.25, 1, 0.5] });
      back.rotation.x = 0.15;
      chain(back, { kv: 0.1, ka: 0.012, max: 0.8, w: 9, z: 0.35, amp: 0.05 });
    }
  }
  if (L.hat === 'wizard') {
    r.mesh(new THREE.CylinderGeometry(0.42, 0.42, 0.04, 14), L.hatColor || '#5a4a8c', head, [0, 0.46, 0]);
    const tip = r.pivot(head, [0, 0.47, -0.02], 'hattip');
    r.mesh(new THREE.ConeGeometry(0.22, 0.55, 10).translate(0, 0.27, 0), L.hatColor || '#5a4a8c', tip);
    chain(tip, { base: [-0.2, 0, 0], kv: -0.08, max: 0.6, w: 8, z: 0.3 });
  } else if (L.hat === 'bandana') {
    r.mesh(new THREE.SphereGeometry(0.345, 14, 8, 0, Math.PI * 2, 0, Math.PI * 0.42), L.hatColor || '#d4553f', head, [0, 0.28, -0.02], { rot: [-0.25, 0, 0] });
    const knot = r.pivot(head, [0, 0.36, -0.3], 'knot');
    r.mesh(new THREE.BoxGeometry(0.1, 0.035, 0.16).translate(0, 0, -0.08), L.hatColor || '#d4553f', knot);
    knot.rotation.x = 0.4;
    chain(knot, { kv: 0.12, ka: 0.015, max: 1, w: 10, z: 0.3, flutter: 10, amp: 0.15 });
  } else if (L.hat === 'straw') {
    r.mesh(new THREE.CylinderGeometry(0.5, 0.52, 0.035, 16), '#e3c062', head, [0, 0.42, 0]);
    r.mesh(new THREE.CylinderGeometry(0.25, 0.3, 0.18, 14), '#d9b456', head, [0, 0.52, 0]);
    r.mesh(new THREE.CylinderGeometry(0.305, 0.305, 0.045, 14), '#b3402e', head, [0, 0.46, 0], { cast: false });
  }
  if (L.beard) {
    r.mesh(ELL(0.2, 1.05, 0.9, 0.55, 12, 8), L.beard, head, [0, 0.1, 0.18]);
    r.mesh(ELL(0.07, 1.6, 0.5, 0.6, 8, 6), L.beard, head, [0, 0.17, 0.28]);
  }

  // ---- cachecol com ponta em corrente (follow-through)
  if (L.scarf) {
    r.mesh(new THREE.TorusGeometry(0.13, 0.055, 6, 14), L.scarf, chest, [0, 0.2, 0], { rot: [Math.PI / 2, 0, 0] });
    let parent = chest, pos = [0.07, 0.19, -0.13];
    const segs = [[0.1, 0.17], [0.09, 0.15], [0.08, 0.13]];
    segs.forEach(([w, l], i) => {
      const sg = r.pivot(parent, pos, 'scarf' + i);
      r.mesh(new THREE.BoxGeometry(w, 0.035, l).translate(0, 0, -l / 2), i === 2 ? shadeHex(L.scarf, 0.85) : L.scarf, sg);
      sg.rotation.x = i === 0 ? 0.6 : 0.25;
      chain(sg, { kv: 0.16 + i * 0.05, ka: 0.016 + i * 0.006, max: 1.2, flutter: 9 + i * 2, amp: 0.1 + i * 0.06, w: 11 - i * 2, z: 0.3, ph: i * 0.9 });
      parent = sg; pos = [0, 0, -l + 0.01];
    });
  }
  if (L.cape) {
    const cape = r.pivot(chest, [0, 0.2, -0.13], 'cape');
    r.mesh(new THREE.BoxGeometry(0.34, 0.44, 0.03).translate(0, -0.22, 0), L.cape, cape);
    cape.rotation.x = 0.12;
    chain(cape, { kv: 0.1, ka: 0.012, max: 0.9, w: 8, z: 0.38, amp: 0.05 });
  }
  if (L.pack) {
    r.mesh(new THREE.BoxGeometry(0.26, 0.26, 0.13), '#8a6043', chest, [0, 0.1, -0.2]);
    r.mesh(new THREE.CylinderGeometry(0.06, 0.06, 0.3, 8), '#c9b48c', chest, [0, 0.25, -0.2], { rot: [0, 0, Math.PI / 2] });
    r.mesh(new THREE.BoxGeometry(0.2, 0.08, 0.03), '#6b4433', chest, [0, 0.05, -0.27], { cast: false });
  }

  // ---- arma
  if (L.weapon === 'sword') {
    const w = r.pivot(r.parts.handR, [0, -0.01, 0.03], 'weapon');
    r.mesh(new THREE.CylinderGeometry(0.025, 0.025, 0.13, 6), '#5e3f31', w, [0, 0, -0.02], { rot: [Math.PI / 2, 0, 0] });
    r.mesh(new THREE.SphereGeometry(0.035, 6, 5), '#e8c36a', w, [0, 0, -0.1]);
    r.mesh(new THREE.BoxGeometry(0.22, 0.045, 0.06), '#e8c36a', w, [0, 0, 0.06]);
    const blade = r.mesh(new THREE.BoxGeometry(0.07, 0.025, 0.56), '#e3ebf2', w, [0, 0, 0.36]);
    r.mesh(new THREE.ConeGeometry(0.05, 0.12, 4), '#e3ebf2', w, [0, 0, 0.69], { rot: [Math.PI / 2, Math.PI / 4, 0], scale: [1, 1, 0.35] });
    r.mesh(new THREE.BoxGeometry(0.022, 0.03, 0.5), '#a7b6c8', w, [0.022, 0.006, 0.35], { cast: false });
    r.parts.blade = blade;
  } else if (L.weapon === 'staff') {
    const w = r.pivot(r.parts.handR, [0, 0, 0], 'weapon');
    r.mesh(new THREE.CylinderGeometry(0.03, 0.035, 1.2, 6).translate(0, 0.25, 0), '#7a5642', w);
    r.mesh(new THREE.TorusGeometry(0.07, 0.02, 4, 8), '#7a5642', w, [0, 0.88, 0]);
    r.mesh(new THREE.OctahedronGeometry(0.07, 0), '#7fe0c8', w, [0, 0.88, 0], { unlit: true });
  }
  r.root.userData.rig = r;
  r.animator = new HumanoidAnimator(r);
  return r;
}

function shadeHex(h, k) { const c = new THREE.Color(h); c.r = Math.min(1, c.r * k); c.g = Math.min(1, c.g * k); c.b = Math.min(1, c.b * k); return '#' + c.getHexString(); }

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

export const snap8 = (a) => Math.round(a / (Math.PI / 4)) * (Math.PI / 4);
