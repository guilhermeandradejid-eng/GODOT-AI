import * as THREE from 'three';
import { shared, MAXL } from './materials.js';
import { S } from './world.js';

// =============================================================================
// Iluminação dinâmica: ciclo de dia (sol/lua que se movem, cores do céu, névoa, color grading
// por hora) e um conjunto de luzes pontuais (lampiões, fogueira, tochas, magia, impactos).
// =============================================================================

const C = (r, g, b) => new THREE.Color(r, g, b);
// chaves por hora do dia; tudo é interpolado
const KEYS = [
  { h: 0, sun: C(0.34, 0.42, 0.72), sky: C(0.2, 0.24, 0.42), bounce: C(0.18, 0.16, 0.26), hi: C(1.05, 1.08, 1.2), rim: C(0.5, 0.6, 1.0),
    fog: C(0.17, 0.2, 0.35), fogP: [0.2, -1.4, 0.55], haze: 0.01, lamps: 1, emis: 1.9, bloom: 1.25, thr: 0.95, cloud: 0.3,
    exp: 1.05, sat: 0.92, con: 1.05, lift: C(0.03, 0.035, 0.075), gain: C(0.9, 0.94, 1.06), sh: C(0.86, 0.92, 1.2), hl: C(1.18, 1.02, 0.8), shafts: 0, moon: true },
  { h: 4.6, sun: C(0.34, 0.42, 0.72), sky: C(0.22, 0.25, 0.44), bounce: C(0.2, 0.17, 0.28), hi: C(1.05, 1.08, 1.2), rim: C(0.55, 0.6, 1.0),
    fog: C(0.24, 0.26, 0.42), fogP: [0.25, -1.3, 0.6], haze: 0.01, lamps: 1, emis: 1.9, bloom: 1.2, thr: 0.95, cloud: 0.3,
    exp: 1.05, sat: 0.92, con: 1.05, lift: C(0.035, 0.04, 0.08), gain: C(0.9, 0.94, 1.06), sh: C(0.88, 0.92, 1.18), hl: C(1.16, 1.02, 0.82), shafts: 0, moon: true },
  { h: 6.2, sun: C(1.0, 0.74, 0.66), sky: C(0.5, 0.48, 0.7), bounce: C(0.52, 0.44, 0.52), hi: C(1.15, 1.0, 0.85), rim: C(1.0, 0.7, 0.8),
    fog: C(0.84, 0.74, 0.8), fogP: [0.15, -1.1, 0.5], haze: 0.013, lamps: 0.6, emis: 1.7, bloom: 1.0, thr: 1.0, cloud: 0.6,
    exp: 1.0, sat: 0.96, con: 1.03, lift: C(0.05, 0.035, 0.07), gain: C(1.02, 0.97, 0.98), sh: C(0.9, 0.9, 1.12), hl: C(1.08, 1.0, 0.94), shafts: 1, moon: false },
  { h: 8.5, sun: C(0.98, 0.9, 0.76), sky: C(0.52, 0.6, 0.84), bounce: C(0.56, 0.54, 0.58), hi: C(1.12, 1.06, 0.92), rim: C(0.9, 0.9, 1.0),
    fog: C(0.82, 0.86, 0.92), fogP: [0.2, -1.2, 0.45], haze: 0.012, lamps: 0, emis: 1.2, bloom: 0.7, thr: 1.05, cloud: 1,
    exp: 1.0, sat: 1.0, con: 1.04, lift: C(0.02, 0.02, 0.04), gain: C(1.0, 0.99, 0.98), sh: C(0.95, 0.97, 1.08), hl: C(1.03, 1.01, 0.97), shafts: 0.8, moon: false },
  { h: 12.5, sun: C(0.95, 0.94, 0.88), sky: C(0.56, 0.62, 0.86), bounce: C(0.58, 0.56, 0.56), hi: C(1.1, 1.06, 0.95), rim: C(0.9, 0.9, 1.0),
    fog: C(0.8, 0.86, 0.94), fogP: [-0.4, -1.2, 0.2], haze: 0.01, lamps: 0, emis: 1.1, bloom: 0.55, thr: 1.08, cloud: 1,
    exp: 1.0, sat: 0.98, con: 1.05, lift: C(0.015, 0.015, 0.035), gain: C(1.0, 1.0, 1.0), sh: C(0.96, 0.98, 1.07), hl: C(1.02, 1.01, 0.98), shafts: 0.4, moon: false },
  { h: 16.3, sun: C(1.0, 0.9, 0.72), sky: C(0.54, 0.56, 0.82), bounce: C(0.62, 0.54, 0.52), hi: C(1.1, 1.03, 0.9), rim: C(1.0, 0.85, 0.7),
    fog: C(0.92, 0.8, 0.7), fogP: [-0.2, -1.2, 0.3], haze: 0.014, lamps: 0, emis: 1.3, bloom: 0.8, thr: 1.02, cloud: 0.9,
    exp: 1.0, sat: 0.98, con: 1.05, lift: C(0.03, 0.018, 0.05), gain: C(1.03, 0.99, 0.93), sh: C(0.92, 0.92, 1.12), hl: C(1.07, 1.0, 0.9), shafts: 1, moon: false },
  { h: 18.2, sun: C(1.0, 0.72, 0.56), sky: C(0.48, 0.42, 0.68), bounce: C(0.58, 0.42, 0.46), hi: C(1.18, 0.95, 0.75), rim: C(1.0, 0.6, 0.5),
    fog: C(0.9, 0.58, 0.52), fogP: [0.0, -1.2, 0.45], haze: 0.018, lamps: 0.6, emis: 1.8, bloom: 1.05, thr: 0.98, cloud: 0.7,
    exp: 1.0, sat: 1.0, con: 1.05, lift: C(0.05, 0.025, 0.07), gain: C(1.04, 0.96, 0.92), sh: C(0.9, 0.88, 1.12), hl: C(1.06, 0.99, 0.9), shafts: 1, moon: false },
  { h: 19.6, sun: C(0.55, 0.42, 0.66), sky: C(0.3, 0.28, 0.52), bounce: C(0.32, 0.24, 0.36), hi: C(1.05, 1.0, 1.1), rim: C(0.8, 0.6, 1.0),
    fog: C(0.42, 0.34, 0.56), fogP: [0.2, -1.3, 0.5], haze: 0.014, lamps: 1, emis: 2.2, bloom: 1.2, thr: 0.95, cloud: 0.4,
    exp: 1.02, sat: 0.95, con: 1.05, lift: C(0.05, 0.03, 0.09), gain: C(0.96, 0.9, 1.06), sh: C(0.88, 0.88, 1.18), hl: C(1.04, 0.98, 1.0), shafts: 0, moon: false },
  { h: 21.5, sun: C(0.34, 0.42, 0.72), sky: C(0.2, 0.24, 0.42), bounce: C(0.18, 0.16, 0.26), hi: C(1.05, 1.08, 1.2), rim: C(0.5, 0.6, 1.0),
    fog: C(0.17, 0.2, 0.35), fogP: [0.2, -1.4, 0.55], haze: 0.01, lamps: 1, emis: 1.9, bloom: 1.25, thr: 0.95, cloud: 0.3,
    exp: 1.05, sat: 0.92, con: 1.05, lift: C(0.03, 0.035, 0.075), gain: C(0.9, 0.94, 1.06), sh: C(0.86, 0.92, 1.2), hl: C(1.18, 1.02, 0.8), shafts: 0, moon: true },
];
KEYS.push({ ...KEYS[0], h: 24 });

export const TIME_PRESETS = { ciclo: null, manha: 8.5, 'meio-dia': 12.5, tarde: 16.3, 'pôr do sol': 18.2, noite: 22.5 };

const U = new THREE.Vector3(S, 0, -S), V = new THREE.Vector3(S, 0, S); // direita / baixo da tela

export class Lighting {
  constructor(scene, renderer, sun) {
    this.scene = scene; this.pr = renderer; this.sun = sun;
    this.hour = 8.5;
    this.speed = 24 / (24 * 60); // 24 min por dia (1 min real = 1 h)
    this.fixed = null;
    this.static = [];   // {pos, color, radius, intensity, flicker, night}
    this.flashes = [];  // {pos, color, radius, intensity, life, max, follow}
    this.cur = {};
    this.sunDir = new THREE.Vector3();
    this.shaftAmt = 0;
    this.lampsOn = 0;
  }

  addStatic(pos, color, radius, intensity, o = {}) { const l = { pos: pos.clone(), color: new THREE.Color(color), radius, intensity, flicker: o.flicker ?? 0, night: o.night ?? true, on: 1 }; this.static.push(l); return l; }
  flash(pos, color, radius = 4, intensity = 1.5, life = 0.25, follow = null) { this.flashes.push({ pos: pos.clone(), color: new THREE.Color(color), radius, intensity, life, max: life, follow }); }

  sample(h) {
    let a = KEYS[0], b = KEYS[1];
    for (let i = 0; i < KEYS.length - 1; i++) if (h >= KEYS[i].h && h <= KEYS[i + 1].h) { a = KEYS[i]; b = KEYS[i + 1]; break; }
    const t = (h - a.h) / Math.max(0.001, b.h - a.h);
    const s = t * t * (3 - 2 * t);
    const out = {};
    for (const k of Object.keys(a)) {
      if (k === 'h') continue;
      const va = a[k], vb = b[k];
      if (va instanceof THREE.Color) out[k] = va.clone().lerp(vb, s);
      else if (Array.isArray(va)) out[k] = va.map((x, i) => x + (vb[i] - x) * s);
      else if (typeof va === 'number') out[k] = va + (vb - va) * s;
      else out[k] = s < 0.5 ? va : vb;
    }
    return out;
  }

  update(dt, focus) {
    if (this.fixed === null) this.hour = (this.hour + dt * this.speed) % 24;
    else this.hour += (this.fixed - this.hour) * Math.min(1, dt * 3);
    const h = this.hour;
    const k = this.sample(h);
    this.cur = k;
    // direção do sol: nasce à direita da tela, passa pela frente e se põe à esquerda
    const day = (h - 5.8) / (18.8 - 5.8);
    let dir;
    if (day > 0 && day < 1) {
      const elev = THREE.MathUtils.degToRad(14 + Math.sin(day * Math.PI) * 46);
      const az = (0.5 - day) * Math.PI * 0.9; // + = direita
      const horiz = U.clone().multiplyScalar(Math.sin(az)).addScaledVector(V, Math.cos(az) * 0.75).addScaledVector(V.clone().negate(), 0.25);
      horiz.normalize();
      dir = horiz.multiplyScalar(Math.cos(elev)).add(new THREE.Vector3(0, Math.sin(elev), 0));
    } else {
      dir = U.clone().multiplyScalar(-0.55).addScaledVector(V, 0.45).add(new THREE.Vector3(0, 1.3, 0)).normalize(); // lua
    }
    this.sunDir.lerp(dir.normalize(), this.sunDir.lengthSq() < 0.1 ? 1 : Math.min(1, dt * 2)).normalize();
    shared.uSunColor.value.copy(k.sun);
    shared.uSkyColor.value.copy(k.sky);
    shared.uBounceColor.value.copy(k.bounce);
    shared.uHiColor.value.copy(k.hi);
    shared.uRimColor.value.copy(k.rim);
    shared.uEmisBoost.value = k.emis;
    shared.uCloud.value = k.cloud;
    const u = this.pr.compMat.uniforms;
    u.uFogColor.value.copy(k.fog);
    u.uFogParams.value.set(k.fogP[0], k.fogP[1], k.fogP[2]);
    u.uHaze.value = k.haze;
    u.uBloom.value = k.bloom;
    this.pr.brightMat.uniforms.uThreshold.value = k.thr;
    u.uExposure.value = k.exp; u.uSat.value = k.sat; u.uContrast.value = k.con;
    u.uLift.value.copy(k.lift); u.uGain.value.copy(k.gain); u.uShadowTint.value.copy(k.sh); u.uHighTint.value.copy(k.hl);
    u.uFocusDepth.value = this.pr.camDist - 6;
    this.shaftAmt = k.shafts;
    this.lampsOn = k.lamps;
    this.scene.background.copy(k.fog).multiplyScalar(0.35);

    // luzes pontuais: flashes primeiro, depois as fixas mais próximas do foco
    const t = shared.uTime.value;
    const list = [];
    for (let i = this.flashes.length - 1; i >= 0; i--) {
      const f = this.flashes[i];
      f.life -= dt;
      if (f.life <= 0) { this.flashes.splice(i, 1); continue; }
      if (f.follow) f.pos.copy(f.follow);
      list.push({ pos: f.pos, color: f.color, radius: f.radius, int: f.intensity * Math.min(1, f.life / f.max * 1.5) });
    }
    const near = this.static.filter((l) => l.on > 0).map((l) => ({ l, d: l.pos.distanceToSquared(focus) })).sort((a, b) => a.d - b.d);
    for (const { l, d } of near) {
      if (list.length >= MAXL || d > 30 * 30) break;
      const night = l.night ? this.lampsOn : 1;
      if (night <= 0.01) continue;
      const fl = l.flicker ? 1 + Math.sin(t * 11 + l.pos.x) * 0.08 * l.flicker + Math.sin(t * 23 + l.pos.z) * 0.05 * l.flicker : 1;
      list.push({ pos: l.pos, color: l.color, radius: l.radius * (l.flicker ? 1 + Math.sin(t * 7) * 0.03 : 1), int: l.intensity * night * fl * l.on });
    }
    const P = shared.uPL.value, PC = shared.uPLC.value;
    list.slice(0, MAXL).forEach((l, i) => { P[i].set(l.pos.x, l.pos.y, l.pos.z, l.radius); PC[i].set(l.color.r, l.color.g, l.color.b, l.int); });
    shared.uPLN.value = Math.min(MAXL, list.length);
  }

  get isNight() { return this.hour > 19.3 || this.hour < 5.6; }
  label() { const h = Math.floor(this.hour), m = Math.floor((this.hour - h) * 60); return `${String(h).padStart(2, '0')}:${String(Math.floor(m / 10) * 10).padStart(2, '0')}`; }
}
