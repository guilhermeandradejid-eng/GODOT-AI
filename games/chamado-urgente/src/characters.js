import * as THREE from 'three';
import { mat, box, sphere, cyl } from './models.js';
import { addOutline } from './toon.js';

// Personagens no estilo "party game": corpo de feijão, cabeça grande, mãos e pés flutuantes,
// olhos de pontinho e expressões gráficas (^ ^, O O, X X). Sombreamento toon + contorno preto.

const INK = 0x1d2540;
const inkMat = new THREE.MeshBasicMaterial({ color: INK });
const mouthMat = new THREE.MeshBasicMaterial({ color: 0x6b1f2e });
const tongueMat = new THREE.MeshBasicMaterial({ color: 0xff7b8a });
const whiteMat = new THREE.MeshBasicMaterial({ color: 0xffffff });
const blushMat = new THREE.MeshBasicMaterial({ color: 0xff9a9a });

function noOutline(m) { m.userData.noOutline = true; m.castShadow = false; return m; }
function capsule(r, len, material) {
  const m = new THREE.Mesh(new THREE.CapsuleGeometry(r, len, 8, 16), material);
  m.castShadow = true; m.receiveShadow = true;
  return m;
}
function arc(r, tube, angle, material) { return new THREE.Mesh(new THREE.TorusGeometry(r, tube, 6, 16, angle), material); }

export function makePerson(o = {}) {
  const {
    shirt = 0x3d7bff, pants = 0x2a2f3d, skin = 0xf2c29b, hair = 0x3b2a20, hairStyle = 0,
    headset = false, glasses = false, tie = null, bowtie = null, mustache = false, beard = false,
    hat = null, hatColor = 0xff5a5a, cardigan = null, earrings = null, lashes = false, hoodie = false,
    shoes = 0x1d2540, outline = 0.024,
  } = o;

  const root = new THREE.Group();
  const rig = new THREE.Group(); root.add(rig);
  const skinMat = mat(skin).clone();
  const shirtMat = mat(shirt), pantsMat = mat(pants), hairMat = mat(hair);

  // pés flutuantes (pivô no quadril para andar/sentar)
  const legL = new THREE.Group(); legL.position.set(-0.13, 0.3, 0);
  const legR = new THREE.Group(); legR.position.set(0.13, 0.3, 0);
  for (const leg of [legL, legR]) {
    const f = sphere(0.1, mat(shoes), 0, -0.24, 0.04); f.scale.set(1, 0.7, 1.35); leg.add(f);
    rig.add(leg);
  }

  // corpo de feijão
  const body = new THREE.Group(); body.position.y = 0.56; rig.add(body);
  const torso = capsule(0.27, 0.2, shirtMat); torso.scale.set(1, 1, 0.85); body.add(torso);
  const hips = capsule(0.262, 0.02, pantsMat); hips.position.y = -0.17; hips.scale.set(1.01, 1, 0.86); body.add(hips);
  if (cardigan) for (const s of [-1, 1]) { const c = capsule(0.2, 0.18, mat(cardigan)); c.position.set(0.13 * s, 0.0, 0.0); c.scale.set(0.75, 1.05, 0.95); body.add(c); }
  if (hoodie) {
    const hood = arc(0.2, 0.08, Math.PI * 1.25, mat(new THREE.Color(shirt).multiplyScalar(0.82).getHex()));
    hood.rotation.set(Math.PI / 2 + 0.35, 0, Math.PI * 0.87); hood.position.set(0, 0.24, -0.06); body.add(hood);
    const pocket = box(0.28, 0.1, 0.05, new THREE.Color(shirt).multiplyScalar(0.85).getHex(), 0, -0.07, 0.22, 0.04); body.add(pocket);
  }
  if (tie) { body.add(box(0.07, 0.22, 0.03, tie, 0, 0.04, 0.235, 0.025)); body.add(box(0.08, 0.06, 0.04, tie, 0, 0.16, 0.235, 0.02)); }
  if (bowtie) for (const s of [-1, 1]) { const b = new THREE.Mesh(new THREE.ConeGeometry(0.055, 0.1, 4), mat(bowtie)); b.rotation.z = (Math.PI / 2) * s; b.position.set(0.05 * s, 0.19, 0.22); body.add(b); }
  // crachá
  const badge = box(0.1, 0.12, 0.03, 0xffffff, -0.11, 0.02, 0.225, 0.02); badge.rotation.z = 0.15; body.add(badge);
  body.add(noOutline(box(0.06, 0.02, 0.01, 0x3d7bff, -0.11, 0.05, 0.242, 0.005)));

  // cabeça
  const head = new THREE.Group(); head.position.y = 0.6; body.add(head);
  const skull = new THREE.Mesh(new THREE.SphereGeometry(0.34, 32, 24), skinMat);
  skull.scale.set(1, 0.93, 0.95); skull.castShadow = true; head.add(skull);

  // rosto: tudo preto chapado (MeshBasic) para ler bem e não parecer "render realista"
  const face = new THREE.Group(); face.position.set(0, 0.0, 0.305); head.add(face);
  const eyes = [];
  for (const s of [-1, 1]) {
    const e = new THREE.Group(); e.position.set(0.115 * s, 0.035, 0); e.rotation.y = 0.32 * s;
    const dot = noOutline(capsule(0.036, 0.05, inkMat)); dot.scale.z = 0.5; e.add(dot);
    const shine = noOutline(new THREE.Mesh(new THREE.SphereGeometry(0.011, 6, 4), whiteMat)); shine.position.set(0.012, 0.03, 0.02); e.add(shine);
    const happy = noOutline(arc(0.045, 0.014, Math.PI, inkMat)); happy.position.y = -0.01; e.add(happy);
    const ring = noOutline(arc(0.048, 0.013, Math.PI * 2, inkMat)); e.add(ring);
    const pin = noOutline(new THREE.Mesh(new THREE.SphereGeometry(0.016, 8, 6), inkMat)); e.add(pin);
    const x1 = noOutline(box(0.1, 0.022, 0.01, inkMat, 0, 0, 0, 0.008)); x1.rotation.z = 0.8; e.add(x1);
    const x2 = noOutline(box(0.1, 0.022, 0.01, inkMat, 0, 0, 0, 0.008)); x2.rotation.z = -0.8; e.add(x2);
    if (lashes) { const l = noOutline(box(0.04, 0.014, 0.01, inkMat, 0.045 * s, 0.045, 0, 0.005)); l.rotation.z = -0.6 * s; e.add(l); }
    e.userData = { dot, shine, happy, ring, pin, x: [x1, x2] };
    face.add(e); eyes.push(e);
  }
  const brows = [];
  for (const s of [-1, 1]) {
    const b = noOutline(box(0.1, 0.026, 0.012, inkMat, 0.115 * s, 0.135, 0.0, 0.01));
    b.rotation.y = 0.32 * s; b.userData.side = s; face.add(b); brows.push(b);
  }
  const mouth = new THREE.Group(); mouth.position.set(0, -0.1, 0.0); face.add(mouth);
  const smile = noOutline(arc(0.05, 0.014, Math.PI, inkMat)); smile.rotation.z = Math.PI; smile.position.y = 0.02;
  const grin = new THREE.Group();
  const gm = noOutline(new THREE.Mesh(new THREE.CircleGeometry(0.065, 20, Math.PI, Math.PI), mouthMat)); grin.add(gm);
  const gt = noOutline(new THREE.Mesh(new THREE.CircleGeometry(0.03, 12, Math.PI, Math.PI), tongueMat)); gt.position.set(0, -0.035, 0.002); grin.add(gt);
  const gl = noOutline(arc(0.065, 0.01, Math.PI, inkMat)); gl.rotation.z = Math.PI; grin.add(gl);
  const gtop = noOutline(box(0.13, 0.018, 0.01, inkMat, 0, 0, 0, 0.006)); grin.add(gtop);
  const open = new THREE.Group();
  const om = noOutline(new THREE.Mesh(new THREE.CircleGeometry(0.05, 20), mouthMat)); om.scale.y = 1.2; open.add(om);
  const ot = noOutline(new THREE.Mesh(new THREE.CircleGeometry(0.025, 12), tongueMat)); ot.position.set(0, -0.03, 0.002); open.add(ot);
  const orim = noOutline(arc(0.05, 0.01, Math.PI * 2, inkMat)); orim.scale.y = 1.2; open.add(orim);
  const flat = noOutline(box(0.08, 0.018, 0.01, inkMat, 0, 0, 0, 0.007));
  const frown = noOutline(arc(0.045, 0.014, Math.PI, inkMat)); frown.position.y = -0.03;
  const wavy = new THREE.Group(); // boca tremida (pânico)
  for (let i = 0; i < 4; i++) { const w = noOutline(arc(0.02, 0.011, Math.PI, inkMat)); w.position.x = -0.06 + i * 0.04; w.rotation.z = i % 2 ? Math.PI : 0; wavy.add(w); }
  const tongueOut = new THREE.Group(); tongueOut.add(noOutline(box(0.07, 0.016, 0.01, inkMat, 0, 0, 0, 0.006)));
  const to = noOutline(new THREE.Mesh(new THREE.CircleGeometry(0.026, 12), tongueMat)); to.position.set(0.025, -0.022, 0.001); tongueOut.add(to);
  const mouths = { smile, grin, open, flat, frown, wavy, tongueOut };
  for (const m of Object.values(mouths)) mouth.add(m);
  const cheeks = [];
  for (const s of [-1, 1]) { const c = noOutline(new THREE.Mesh(new THREE.CircleGeometry(0.045, 16), blushMat)); c.position.set(0.19 * s, -0.06, -0.035); c.rotation.y = 0.55 * s; c.scale.y = 0.6; face.add(c); cheeks.push(c); }

  // cabelo (formas grandes e simples)
  const cap = (phi, rx, y = 0.03, z = -0.02, r = 0.355) => {
    const m = new THREE.Mesh(new THREE.SphereGeometry(r, 28, 16, 0, Math.PI * 2, 0, Math.PI * phi), hairMat);
    m.rotation.x = rx; m.position.set(0, y, z); m.castShadow = true; head.add(m); return m;
  };
  if (hairStyle === 0) { // franja de lado
    cap(0.5, -0.5);
    const f = sphere(0.17, hairMat, -0.1, 0.22, 0.18); f.scale.set(1.5, 0.55, 0.8); f.rotation.z = 0.3; head.add(f);
  } else if (hairStyle === 1) { // coque
    cap(0.56, -0.55); head.add(sphere(0.15, hairMat, 0, 0.28, -0.2));
  } else if (hairStyle === 2) { // black power
    const a = sphere(0.44, hairMat, 0, 0.12, -0.08); a.scale.set(1, 0.85, 0.95); head.add(a);
  } else if (hairStyle === 3) { // careca com laterais
    for (const s of [-1, 1]) { const h = sphere(0.12, hairMat, 0.29 * s, 0.0, -0.08); h.scale.set(0.5, 1, 1.4); head.add(h); }
  } else if (hairStyle === 4) { // comprido
    cap(0.55, -0.4);
    head.add(box(0.66, 0.5, 0.26, hairMat, 0, -0.14, -0.17, 0.12));
  } else if (hairStyle === 5) { // rabo de cavalo
    cap(0.55, -0.5);
    const pt = capsule(0.09, 0.22, hairMat); pt.position.set(0, 0.04, -0.38); pt.rotation.x = 0.8; head.add(pt);
  } else if (hairStyle === 6) { // topete espetado
    cap(0.46, -0.35);
    for (let i = 0; i < 3; i++) { const c = new THREE.Mesh(new THREE.ConeGeometry(0.11, 0.26, 8), hairMat); c.position.set(-0.12 + i * 0.12, 0.33, 0.05 - Math.abs(i - 1) * 0.05); c.rotation.set(-0.5, 0, (i - 1) * 0.35); c.castShadow = true; head.add(c); }
  }
  if (glasses) {
    for (const s of [-1, 1]) { const r = arc(0.07, 0.016, Math.PI * 2, inkMat); r.position.set(0.115 * s, 0.035, 0.32); r.rotation.y = 0.32 * s; head.add(noOutline(r)); }
    head.add(noOutline(box(0.07, 0.016, 0.016, inkMat, 0, 0.05, 0.335, 0.006)));
  }
  if (mustache) { const m = capsule(0.04, 0.12, mat(hair === 0xe9eef7 ? 0xcfd6e4 : hair)); m.rotation.z = Math.PI / 2; m.position.set(0, -0.06, 0.315); m.scale.z = 0.6; head.add(m); }
  if (beard) { const b = sphere(0.25, hairMat, 0, -0.17, 0.08); b.scale.set(1.1, 0.65, 0.9); head.add(b); mouth.position.z = 0.06; mouth.position.y = -0.11; }
  if (earrings) for (const s of [-1, 1]) head.add(sphere(0.03, mat(earrings), 0.33 * s, -0.12, 0.02));
  if (hat === 'cap') {
    const c = new THREE.Mesh(new THREE.SphereGeometry(0.36, 24, 12, 0, Math.PI * 2, 0, Math.PI * 0.45), mat(hatColor)); c.position.y = 0.05; c.rotation.x = -0.12; head.add(c);
    head.add(box(0.34, 0.035, 0.22, hatColor, 0, 0.14, 0.34, 0.016));
  } else if (hat === 'beanie') {
    const c = new THREE.Mesh(new THREE.SphereGeometry(0.37, 24, 12, 0, Math.PI * 2, 0, Math.PI * 0.5), mat(hatColor)); c.position.y = 0.06; c.rotation.x = -0.2; head.add(c);
    const rim = new THREE.Mesh(new THREE.TorusGeometry(0.34, 0.06, 10, 28), mat(new THREE.Color(hatColor).multiplyScalar(0.82).getHex())); rim.rotation.x = Math.PI / 2 - 0.2; rim.position.set(0, 0.09, 0.0); head.add(rim);
    head.add(sphere(0.1, 0xffffff, 0, 0.44, -0.08));
  }
  if (headset) {
    const band = arc(0.37, 0.035, Math.PI, mat(0x2a2f3d)); band.position.y = 0.03; head.add(band);
    for (const s of [-1, 1]) { const e = cyl(0.11, 0.11, 0.08, 0x2a2f3d, 0.37 * s, 0.0, 0); e.rotation.z = Math.PI / 2; head.add(e); const ep = cyl(0.075, 0.075, 0.085, 0xff5a5a, 0.375 * s, 0.0, 0); ep.rotation.z = Math.PI / 2; head.add(ep); }
    const boom = capsule(0.018, 0.2, mat(0x2a2f3d)); boom.position.set(-0.3, -0.14, 0.17); boom.rotation.set(0.9, 0, 0.6); head.add(boom);
    head.add(sphere(0.045, 0x2a2f3d, -0.22, -0.22, 0.26));
  }

  // mãos flutuantes (pivô no ombro)
  const mkArm = (side) => {
    const arm = new THREE.Group(); arm.position.set(0.36 * side, 0.1, 0);
    const hand = sphere(0.095, skinMat, 0, -0.24, 0); arm.add(hand);
    body.add(arm); return arm;
  };
  const armL = mkArm(-1), armR = mkArm(1);

  addOutline(rig, outline);

  // efeitos (sem contorno)
  const dizzy = new THREE.Group(); dizzy.position.y = 0.5; dizzy.visible = false; head.add(dizzy);
  for (let i = 0; i < 3; i++) { const s = new THREE.Mesh(new THREE.OctahedronGeometry(0.065), new THREE.MeshBasicMaterial({ color: 0xffd23f, toneMapped: false })); s.scale.y = 0.5; dizzy.add(s); }
  const sweat = new THREE.Mesh(new THREE.SphereGeometry(0.055, 10, 8), new THREE.MeshBasicMaterial({ color: 0x9fd8ff, transparent: true, opacity: 0.95 }));
  sweat.scale.set(0.8, 1.3, 0.8); sweat.position.set(0.3, 0.2, 0.15); sweat.visible = false; head.add(sweat);

  const P = {
    root, rig, body, head, legL, legR, armL, armR, eyes, brows, mouth, mouths, cheeks, skull, skinMat, dizzy, sweat,
    expr: null, blinkT: 1 + Math.random() * 3, blink: 0,
  };
  setFace(P, 'neutral');
  return P;
}

// eye: dot | happy | ring | x | squint ; brow: ângulo (positivo = bravo) ou null
const FACES = {
  neutral: { eye: 'dot', brow: null, m: 'smile', ch: false },
  happy: { eye: 'happy', brow: null, m: 'grin', ch: true },
  proud: { eye: 'dot', brow: -0.15, m: 'grin', ch: true },
  angry: { eye: 'dot', brow: 0.5, m: 'open', ch: false },
  panic: { eye: 'ring', brow: -0.45, m: 'wavy', ch: false },
  sad: { eye: 'dot', brow: -0.4, m: 'frown', ch: false },
  focused: { eye: 'squint', brow: 0.25, m: 'tongueOut', ch: false },
  dizzy: { eye: 'x', brow: null, m: 'wavy', ch: false },
  bored: { eye: 'squint', brow: 0, m: 'flat', ch: false },
};

export function setFace(P, expr) {
  if (P.expr === expr) return;
  P.expr = expr;
  const f = FACES[expr] || FACES.neutral;
  P.eyeMode = f.eye;
  P.eyes.forEach((e, i) => {
    const u = e.userData;
    const dot = f.eye === 'dot' || f.eye === 'squint';
    u.dot.visible = dot; u.shine.visible = f.eye === 'dot';
    u.dot.scale.y = f.eye === 'squint' && i === 0 ? 0.35 : 1;
    u.happy.visible = f.eye === 'happy';
    u.ring.visible = u.pin.visible = f.eye === 'ring';
    u.x[0].visible = u.x[1].visible = f.eye === 'x';
  });
  for (const b of P.brows) {
    b.visible = f.brow !== null;
    b.rotation.z = -(f.brow ?? 0) * b.userData.side;
    b.position.y = 0.13 + (f.brow !== null && f.brow < 0 ? 0.02 : 0);
  }
  for (const [k, m] of Object.entries(P.mouths)) m.visible = k === f.m;
  for (const c of P.cheeks) c.visible = f.ch;
}

// piscar, tontura e suor — chame todo frame
export function animateFace(P, dt, time, opts = {}) {
  P.blinkT -= dt;
  if (P.blinkT <= 0) { P.blink = 0.12; P.blinkT = 2 + Math.random() * 3.5; }
  P.blink = Math.max(0, P.blink - dt);
  const bl = P.blink > 0 && P.eyeMode === 'dot' ? 0.12 : 1;
  for (const e of P.eyes) e.scale.y = bl;
  if (P.eyeMode === 'x') for (const e of P.eyes) e.rotation.z = time * 6;
  else for (const e of P.eyes) e.rotation.z = 0;
  if (P.expr === 'panic') P.mouths.wavy.position.x = Math.sin(time * 30) * 0.006;
  P.dizzy.visible = !!opts.dizzy;
  if (P.dizzy.visible) P.dizzy.children.forEach((s, i) => { const a = time * 7 + (i / 3) * Math.PI * 2; s.position.set(Math.cos(a) * 0.3, Math.sin(a * 2) * 0.04, Math.sin(a) * 0.3); s.rotation.y = a * 2; });
  P.sweat.visible = !!opts.sweat;
  if (P.sweat.visible) { const k = (time * 1.4) % 1; P.sweat.position.set(0.3, 0.22 - k * 0.25, 0.15); P.sweat.material.opacity = 1 - k; }
}
