import * as THREE from 'three';
import { mat, box, sphere, cyl } from './models.js';

// Personagens "chibi": cabeça grande, olhos expressivos que piscam, sobrancelhas e boca
// controladas por expressões (neutral, happy, angry, panic, sad, focused, dizzy, proud).

function capsule(r, len, color) {
  const m = new THREE.Mesh(new THREE.CapsuleGeometry(r, len, 6, 12), color instanceof THREE.Material ? color : mat(color));
  m.castShadow = true;
  return m;
}

const INK = 0x1d2540;

export function makePerson(o = {}) {
  const {
    shirt = 0x3d7bff, pants = 0x2a2f3d, skin = 0xf2c29b, hair = 0x3b2a20, hairStyle = 0,
    headset = false, glasses = false, tie = null, bowtie = null, mustache = false, beard = false,
    hat = null, hatColor = 0xff5a5a, cardigan = null, earrings = null, lashes = false, hoodie = false,
    shoes = 0x1d2540,
  } = o;

  const root = new THREE.Group();
  const rig = new THREE.Group(); root.add(rig);
  const skinMat = mat(skin).clone();

  // pernas
  const legL = new THREE.Group(); legL.position.set(-0.12, 0.3, 0);
  const legR = new THREE.Group(); legR.position.set(0.12, 0.3, 0);
  for (const leg of [legL, legR]) {
    const l = capsule(0.085, 0.14, pants); l.position.y = -0.12; leg.add(l);
    leg.add(box(0.17, 0.11, 0.25, shoes, 0, -0.26, 0.035, 0.05));
    leg.add(box(0.172, 0.03, 0.252, 0xffffff, 0, -0.305, 0.035, 0.012));
    rig.add(leg);
  }

  // tronco
  const body = new THREE.Group(); body.position.y = 0.56; rig.add(body);
  body.add(box(0.5, 0.46, 0.38, shirt, 0, 0, 0, 0.17));
  body.add(box(0.51, 0.07, 0.39, pants, 0, -0.2, 0, 0.04));
  if (hoodie) {
    body.add(box(0.3, 0.12, 0.04, new THREE.Color(shirt).multiplyScalar(0.8).getHex(), 0, -0.08, 0.19, 0.04));
    const hood = new THREE.Mesh(new THREE.TorusGeometry(0.2, 0.07, 8, 16, Math.PI * 1.2), mat(new THREE.Color(shirt).multiplyScalar(0.85).getHex()));
    hood.rotation.set(Math.PI / 2 + 0.3, 0, Math.PI * 0.9); hood.position.set(0, 0.22, -0.04); body.add(hood);
    for (const s of [-1, 1]) body.add(cyl(0.01, 0.01, 0.16, 0xffffff, 0.06 * s, 0.1, 0.2));
  }
  if (cardigan) {
    for (const s of [-1, 1]) body.add(box(0.16, 0.44, 0.4, cardigan, 0.18 * s, 0.0, 0.0, 0.12));
    for (let i = 0; i < 3; i++) body.add(sphere(0.018, 0xf4efe6, 0.1, 0.12 - i * 0.1, 0.205));
  }
  // colarinho
  const collar = new THREE.Mesh(new THREE.TorusGeometry(0.14, 0.035, 6, 18), mat(new THREE.Color(shirt).lerp(new THREE.Color(0xffffff), 0.35).getHex()));
  collar.rotation.x = Math.PI / 2; collar.position.y = 0.22; body.add(collar);
  if (tie) { body.add(box(0.07, 0.28, 0.02, tie, 0, 0.05, 0.2, 0.02)); body.add(box(0.08, 0.06, 0.03, tie, 0, 0.19, 0.2, 0.02)); }
  if (bowtie) for (const s of [-1, 1]) { const b = new THREE.Mesh(new THREE.ConeGeometry(0.05, 0.09, 4), mat(bowtie)); b.rotation.z = (Math.PI / 2) * s; b.position.set(0.045 * s, 0.19, 0.2); body.add(b); }
  // crachá
  const lan = new THREE.Mesh(new THREE.TorusGeometry(0.15, 0.011, 6, 16, Math.PI), mat(0xff5a5a));
  lan.rotation.set(-0.2, 0, Math.PI); lan.position.set(0, 0.2, 0.17); body.add(lan);
  const badge = box(0.11, 0.14, 0.02, 0xffffff, 0.0, 0.0, 0.205, 0.02); body.add(badge);
  body.add(box(0.07, 0.025, 0.005, 0x3d7bff, 0, 0.04, 0.217, 0.003));

  // cabeça
  const head = new THREE.Group(); head.position.y = 0.52; body.add(head);
  const skull = new THREE.Mesh(new THREE.SphereGeometry(0.34, 28, 20), skinMat);
  skull.scale.set(1, 0.94, 0.95); skull.castShadow = true; head.add(skull);
  for (const s of [-1, 1]) head.add(sphere(0.07, skinMat, 0.33 * s, -0.02, 0));
  head.add(sphere(0.04, skinMat, 0, -0.04, 0.32)); // nariz

  // olhos
  const eyeWhite = mat(0xffffff, { roughness: 0.3 });
  const pupilMat = mat(INK, { roughness: 0.2 });
  const eyes = [];
  for (const s of [-1, 1]) {
    const eye = new THREE.Group(); eye.position.set(0.12 * s, 0.04, 0.29);
    const w = new THREE.Mesh(new THREE.SphereGeometry(0.075, 16, 12), eyeWhite); w.scale.set(1, 1.2, 0.5); eye.add(w);
    const pupil = new THREE.Group(); pupil.position.z = 0.03; eye.add(pupil);
    const pm = new THREE.Mesh(new THREE.SphereGeometry(0.048, 14, 10), pupilMat); pm.scale.set(1, 1.15, 0.5); pupil.add(pm);
    const hl = new THREE.Mesh(new THREE.SphereGeometry(0.016, 8, 6), mat(0xffffff, { emissive: 0xffffff, emissiveIntensity: 0.5 })); hl.position.set(0.018, 0.024, 0.02); pupil.add(hl);
    if (lashes) { const la = box(0.05, 0.015, 0.02, INK, 0.06 * s, 0.07, 0.01, 0.006); la.rotation.z = -0.5 * s; eye.add(la); }
    eye.userData.pupil = pupil;
    head.add(eye); eyes.push(eye);
  }
  // sobrancelhas
  const brows = [];
  for (const s of [-1, 1]) {
    const b = box(0.11, 0.028, 0.03, hair === 0xe9eef7 ? 0x9aa3b5 : hair, 0.12 * s, 0.17, 0.3, 0.012);
    b.userData.side = s; head.add(b); brows.push(b);
  }
  // boca: várias formas, uma visível por vez
  const mouth = new THREE.Group(); mouth.position.set(0, -0.13, 0.3); head.add(mouth);
  const inkMat = mat(0x5a1f2a);
  const smile = new THREE.Mesh(new THREE.TorusGeometry(0.06, 0.016, 6, 14, Math.PI), mat(INK)); smile.rotation.z = Math.PI; mouth.add(smile);
  const grin = new THREE.Group();
  const gm = new THREE.Mesh(new THREE.SphereGeometry(0.08, 14, 10, 0, Math.PI * 2, Math.PI / 2, Math.PI / 2), inkMat); gm.scale.set(1, 0.9, 0.4); grin.add(gm);
  grin.add(box(0.1, 0.02, 0.01, 0xffffff, 0, -0.008, 0.02, 0.004));
  mouth.add(grin);
  const open = new THREE.Group();
  const om = new THREE.Mesh(new THREE.SphereGeometry(0.06, 14, 10), inkMat); om.scale.set(1, 1.1, 0.4); open.add(om);
  const tongue = sphere(0.03, 0xff7b8a, 0, -0.035, 0.012); tongue.scale.set(1, 0.6, 0.4); open.add(tongue);
  mouth.add(open);
  const flat = box(0.08, 0.018, 0.02, INK, 0, 0, 0, 0.008); mouth.add(flat);
  const frown = new THREE.Mesh(new THREE.TorusGeometry(0.05, 0.015, 6, 14, Math.PI), mat(INK)); frown.position.y = -0.03; mouth.add(frown);
  const tongueOut = new THREE.Group(); tongueOut.add(box(0.07, 0.016, 0.02, INK, 0, 0, 0, 0.006)); const to = sphere(0.028, 0xff7b8a, 0.02, -0.02, 0.01); to.scale.set(1, 0.8, 0.5); tongueOut.add(to); mouth.add(tongueOut);
  const mouths = { smile, grin, open, flat, frown, tongueOut };
  // bochechas
  const cheekMat = new THREE.MeshStandardMaterial({ color: 0xff8a8a, transparent: true, opacity: 0.45, roughness: 0.8 });
  const cheeks = [];
  for (const s of [-1, 1]) { const c = sphere(0.05, cheekMat, 0.2 * s, -0.07, 0.25); c.scale.z = 0.3; c.castShadow = false; head.add(c); cheeks.push(c); }

  // cabelo
  const hairMat = mat(hair);
  const hcap = (phi, rx, y = 0.03, z = -0.02, r = 0.36) => {
    const m = new THREE.Mesh(new THREE.SphereGeometry(r, 24, 14, 0, Math.PI * 2, 0, Math.PI * phi), hairMat);
    m.rotation.x = rx; m.position.set(0, y, z); m.castShadow = true; head.add(m); return m;
  };
  if (hairStyle === 0) { // curto bagunçado
    hcap(0.5, -0.45);
    for (let i = 0; i < 5; i++) head.add(sphere(0.09, hairMat, -0.16 + i * 0.08, 0.26 - Math.abs(i - 2) * 0.02, 0.17));
  } else if (hairStyle === 1) { // coque
    hcap(0.58, -0.55); head.add(sphere(0.14, hairMat, 0, 0.26, -0.24));
  } else if (hairStyle === 2) { // black power
    for (let i = 0; i < 11; i++) { const a = (i / 11) * Math.PI * 2; head.add(sphere(0.15, hairMat, Math.cos(a) * 0.24, 0.2 + Math.sin(i) * 0.03, Math.sin(a) * 0.22 - 0.06)); }
    head.add(sphere(0.22, hairMat, 0, 0.3, -0.05));
  } else if (hairStyle === 3) { // calvo com lateral
    for (const s of [-1, 1]) { const h = sphere(0.12, hairMat, 0.27 * s, 0.03, -0.1); h.scale.set(0.6, 1, 1.3); head.add(h); }
    head.add(sphere(0.13, hairMat, 0, 0.0, -0.27));
  } else if (hairStyle === 4) { // comprido
    hcap(0.55, -0.4);
    head.add(box(0.62, 0.55, 0.22, hairMat, 0, -0.15, -0.2, 0.1));
    for (const s of [-1, 1]) head.add(box(0.1, 0.45, 0.2, hairMat, 0.3 * s, -0.12, -0.02, 0.05));
  } else if (hairStyle === 5) { // rabo de cavalo
    hcap(0.55, -0.5);
    const pt = capsule(0.08, 0.25, hairMat); pt.position.set(0, 0.05, -0.38); pt.rotation.x = 0.7; head.add(pt);
    head.add(sphere(0.05, 0xff5a8a, 0, 0.14, -0.32));
  } else if (hairStyle === 6) { // espetado
    hcap(0.45, -0.35);
    for (let i = 0; i < 6; i++) { const c = new THREE.Mesh(new THREE.ConeGeometry(0.08, 0.22, 6), hairMat); c.position.set(-0.2 + i * 0.08, 0.32, 0.02 - Math.abs(i - 2.5) * 0.04); c.rotation.set(-0.4, 0, (i - 2.5) * 0.25); c.castShadow = true; head.add(c); }
  }
  if (glasses) {
    const gm2 = mat(INK);
    for (const s of [-1, 1]) { const r = new THREE.Mesh(new THREE.TorusGeometry(0.075, 0.013, 6, 18), gm2); r.position.set(0.12 * s, 0.04, 0.33); head.add(r); }
    head.add(box(0.08, 0.016, 0.016, INK, 0, 0.06, 0.34, 0.006));
  }
  if (mustache) for (const s of [-1, 1]) { const m = capsule(0.035, 0.08, hair === 0xe9eef7 ? 0xcfd6e4 : hair); m.rotation.z = Math.PI / 2 + 0.35 * s; m.position.set(0.06 * s, -0.085, 0.31); head.add(m); }
  if (beard) { const b = sphere(0.24, hairMat, 0, -0.16, 0.12); b.scale.set(1.15, 0.7, 0.85); head.add(b); }
  if (earrings) for (const s of [-1, 1]) head.add(sphere(0.025, mat(earrings, { metalness: 0.6, roughness: 0.3 }), 0.34 * s, -0.1, 0.02));
  if (hat === 'cap') {
    const c = new THREE.Mesh(new THREE.SphereGeometry(0.365, 20, 10, 0, Math.PI * 2, 0, Math.PI * 0.45), mat(hatColor)); c.position.y = 0.04; c.rotation.x = -0.15; head.add(c);
    head.add(box(0.36, 0.03, 0.22, hatColor, 0, 0.13, 0.36, 0.015));
    head.add(sphere(0.03, 0xffffff, 0, 0.4, 0));
  } else if (hat === 'beanie') {
    const c = new THREE.Mesh(new THREE.SphereGeometry(0.37, 20, 10, 0, Math.PI * 2, 0, Math.PI * 0.5), mat(hatColor)); c.position.y = 0.05; c.rotation.x = -0.2; head.add(c);
    const rim = new THREE.Mesh(new THREE.TorusGeometry(0.34, 0.05, 8, 24), mat(new THREE.Color(hatColor).multiplyScalar(0.8).getHex())); rim.rotation.x = Math.PI / 2 - 0.2; rim.position.set(0, 0.08, 0.0); head.add(rim);
    head.add(sphere(0.09, 0xffffff, 0, 0.43, -0.08));
  }
  if (headset) {
    const band = new THREE.Mesh(new THREE.TorusGeometry(0.37, 0.028, 8, 24, Math.PI), mat(0x2a2f3d)); band.position.y = 0.03; head.add(band);
    for (const s of [-1, 1]) { const e = cyl(0.1, 0.1, 0.07, 0x2a2f3d, 0.37 * s, 0.0, 0); e.rotation.z = Math.PI / 2; head.add(e); head.add(cyl(0.07, 0.07, 0.075, 0xff5a5a, 0.375 * s, 0.0, 0).rotateZ(Math.PI / 2)); }
    const boom = capsule(0.014, 0.22, 0x2a2f3d); boom.position.set(-0.3, -0.12, 0.17); boom.rotation.set(0.9, 0, 0.5); head.add(boom);
    head.add(sphere(0.035, 0x2a2f3d, -0.22, -0.2, 0.27));
  }

  // braços
  const mkArm = (side) => {
    const arm = new THREE.Group(); arm.position.set(0.3 * side, 0.15, 0);
    const a = capsule(0.07, 0.17, cardigan ?? shirt); a.position.y = -0.12; arm.add(a);
    const hand = sphere(0.085, skinMat, 0, -0.29, 0); arm.add(hand);
    body.add(arm); return arm;
  };
  const armL = mkArm(-1), armR = mkArm(1);

  // estrelinhas de tontura (escondidas)
  const dizzy = new THREE.Group(); dizzy.position.y = 0.5; dizzy.visible = false; head.add(dizzy);
  for (let i = 0; i < 3; i++) { const s = new THREE.Mesh(new THREE.OctahedronGeometry(0.06), new THREE.MeshBasicMaterial({ color: 0xffd23f, toneMapped: false })); s.scale.y = 0.5; dizzy.add(s); }
  // gota de suor
  const sweat = new THREE.Mesh(new THREE.SphereGeometry(0.05, 10, 8), new THREE.MeshStandardMaterial({ color: 0x9fd8ff, roughness: 0.1, transparent: true, opacity: 0.9 }));
  sweat.scale.set(0.8, 1.3, 0.8); sweat.position.set(0.3, 0.2, 0.15); sweat.visible = false; head.add(sweat);

  const P = {
    root, rig, body, head, legL, legR, armL, armR, eyes, brows, mouth, mouths, cheeks, skull, skinMat, dizzy, sweat,
    expr: 'neutral', blinkT: 1 + Math.random() * 3, blink: 0, lookX: 0, lookY: 0,
  };
  setFace(P, 'neutral');
  return P;
}

const FACES = {
  //           brow angle  brow y  mouth        eyeScaleY pupil  cheeks
  neutral: { ba: 0, by: 0.17, m: 'smile', ey: 1, ps: 1, ch: 0.45 },
  happy: { ba: -0.15, by: 0.19, m: 'grin', ey: 0.55, ps: 1, ch: 0.8 },
  proud: { ba: -0.1, by: 0.19, m: 'grin', ey: 1, ps: 1.05, ch: 0.7 },
  angry: { ba: 0.5, by: 0.15, m: 'open', ey: 0.85, ps: 0.75, ch: 0.9 },
  panic: { ba: -0.45, by: 0.21, m: 'open', ey: 1.25, ps: 0.6, ch: 0.3 },
  sad: { ba: -0.4, by: 0.17, m: 'frown', ey: 0.8, ps: 1, ch: 0.2 },
  focused: { ba: 0.25, by: 0.16, m: 'tongueOut', ey: 0.7, ps: 1, ch: 0.45 },
  dizzy: { ba: -0.3, by: 0.19, m: 'open', ey: 1, ps: 0.5, ch: 0.3 },
  bored: { ba: 0.0, by: 0.15, m: 'flat', ey: 0.6, ps: 1, ch: 0.3 },
};

export function setFace(P, expr) {
  if (P.expr === expr && P._faceSet) return;
  P.expr = expr; P._faceSet = true;
  const f = FACES[expr] || FACES.neutral;
  for (const b of P.brows) { b.rotation.z = -f.ba * b.userData.side; b.position.y = f.by; }
  for (const [k, m] of Object.entries(P.mouths)) m.visible = k === f.m;
  P.faceEye = f.ey;
  for (const e of P.eyes) e.userData.pupil.scale.setScalar(f.ps);
  for (const c of P.cheeks) c.material.opacity = f.ch;
}

// piscar, olhar em volta, tontura e suor — chame todo frame
export function animateFace(P, dt, time, opts = {}) {
  P.blinkT -= dt;
  if (P.blinkT <= 0) { P.blink = 0.14; P.blinkT = 1.8 + Math.random() * 3.5; }
  P.blink = Math.max(0, P.blink - dt);
  const bl = P.blink > 0 ? Math.max(0.08, Math.abs(P.blink - 0.07) / 0.07) : 1;
  for (const e of P.eyes) e.scale.y = (P.faceEye ?? 1) * bl;
  // olhar
  const lx = opts.lookX ?? Math.sin(time * 0.6 + P.root.id) * 0.012;
  const ly = opts.lookY ?? 0;
  for (const e of P.eyes) e.userData.pupil.position.set(lx, ly, 0.03);
  // tontura
  P.dizzy.visible = !!opts.dizzy;
  if (P.dizzy.visible) P.dizzy.children.forEach((s, i) => { const a = time * 7 + (i / 3) * Math.PI * 2; s.position.set(Math.cos(a) * 0.28, Math.sin(a * 2) * 0.04, Math.sin(a) * 0.28); s.rotation.y = a * 2; });
  P.sweat.visible = !!opts.sweat;
  if (P.sweat.visible) { const k = (time * 1.4) % 1; P.sweat.position.set(0.3, 0.22 - k * 0.25, 0.15); P.sweat.material.opacity = 1 - k; }
}
