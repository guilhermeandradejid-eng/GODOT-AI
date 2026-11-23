import * as THREE from 'three';

// =============================================================================
// Animação procedural fluida, guiada pelos 12 princípios da Disney:
//  - SLOW IN / SLOW OUT e TIMING: golpes e gestos são tweens com easing por segmento.
//  - ANTECIPAÇÃO → AÇÃO → FOLLOW-THROUGH: todo ataque tem preparação, golpe rápido,
//    passagem do ponto (overshoot) e recuperação.
//  - OVERLAPPING ACTION: cada articulação segue sua pose-alvo por uma mola amortecida com
//    rigidez própria — quadril responde rápido, mãos e cabeça atrasam um pouco.
//  - SQUASH & STRETCH: escala do corpo com volume preservado, movida por mola "gelatina".
//  - SECONDARY ACTION: cabelo, antena, cachecol, saia e capa reagem à velocidade e à
//    aceleração; respiração, piscar, cabeça que olha para alvos.
//  - ARCOS: braços e pés descrevem arcos (seno/cosseno), quadril sobe e desce no ciclo.
//  - STAGING / EXAGERO / APELO: silhuetas claras, poses-chave exageradas, inclinação
//    nas acelerações e curvas.
// =============================================================================

// ---------------------------------------------------------------- easing
export const ease = {
  linear: (t) => t,
  inQuad: (t) => t * t,
  outQuad: (t) => 1 - (1 - t) * (1 - t),
  inOutQuad: (t) => (t < 0.5 ? 2 * t * t : 1 - Math.pow(-2 * t + 2, 2) / 2),
  inCubic: (t) => t * t * t,
  outCubic: (t) => 1 - Math.pow(1 - t, 3),
  inOutCubic: (t) => (t < 0.5 ? 4 * t * t * t : 1 - Math.pow(-2 * t + 2, 3) / 2),
  outExpo: (t) => (t >= 1 ? 1 : 1 - Math.pow(2, -10 * t)),
  outBack: (t) => { const c1 = 1.70158, c3 = c1 + 1; return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2); },
  inBack: (t) => { const c1 = 1.70158, c3 = c1 + 1; return c3 * t * t * t - c1 * t * t; },
  outElastic: (t) => (t === 0 || t === 1 ? t : Math.pow(2, -10 * t) * Math.sin((t * 10 - 0.75) * ((2 * Math.PI) / 3)) + 1),
  outBounce: (t) => {
    const n1 = 7.5625, d1 = 2.75;
    if (t < 1 / d1) return n1 * t * t;
    if (t < 2 / d1) return n1 * (t -= 1.5 / d1) * t + 0.75;
    if (t < 2.5 / d1) return n1 * (t -= 2.25 / d1) * t + 0.9375;
    return n1 * (t -= 2.625 / d1) * t + 0.984375;
  },
};

// ---------------------------------------------------------------- mola amortecida
export class Spring {
  constructor(w = 20, z = 0.8, x = 0) { this.w = w; this.z = z; this.x = x; this.v = 0; }
  step(target, dt) {
    const n = Math.max(1, Math.ceil((this.w * dt) / 0.35));
    const h = dt / n, w2 = this.w * this.w, c = 2 * this.z * this.w;
    for (let i = 0; i < n; i++) { this.v += (w2 * (target - this.x) - c * this.v) * h; this.x += this.v * h; }
    return this.x;
  }
  kick(v) { this.v += v; }
}

const lerp = (a, b, t) => a + (b - a) * t;
const clamp = (v, a, b) => (v < a ? a : v > b ? b : v);
const wrapPi = (a) => { while (a > Math.PI) a -= Math.PI * 2; while (a < -Math.PI) a += Math.PI * 2; return a; };

// ---------------------------------------------------------------- poses e tweens
// pose = { nome: [x, y, z], ..., _hipY, _hipZ, _sq (squash), _bx/_by/_bz (corpo), _eyes, _brow, _mouth }
function blend(out, p, w) {
  for (const k in p) {
    const v = p[k];
    if (Array.isArray(v)) {
      const o = out[k] || (out[k] = [0, 0, 0]);
      o[0] = lerp(o[0], v[0], w); o[1] = lerp(o[1], v[1], w); o[2] = lerp(o[2], v[2], w);
    } else out[k] = lerp(out[k] ?? 0, v, w);
  }
  return out;
}

/** amostra uma trilha de poses-chave: keys = [[tempo, pose, easing], ...] */
function sampleTrack(keys, t, base) {
  if (t <= keys[0][0]) return blend({ ...clone(base) }, keys[0][1], 1);
  for (let i = 0; i < keys.length - 1; i++) {
    const [ta, pa] = keys[i], [tb, pb, e] = keys[i + 1];
    if (t <= tb) {
      const s = (ease[e] || ease.inOutQuad)((t - ta) / Math.max(1e-4, tb - ta));
      const a = blend(clone(base), pa, 1);
      const b = blend(clone(base), pb, 1);
      return blend(a, b, s);
    }
  }
  return blend(clone(base), keys[keys.length - 1][1], 1);
}
function clone(p) { const o = {}; for (const k in p) o[k] = Array.isArray(p[k]) ? [...p[k]] : p[k]; return o; }

// ---------------------------------------------------------------- ações (tweens com antecipação)
const W = 1.45; // espada alinhada ao antebraço
const ACTIONS = {
  // corte horizontal da direita para a esquerda
  attack1: { dur: 0.3, keys: [
    [0, {}],
    [0.07, { chest: [0.08, -0.65, 0], armR: [-1.25, 0, -1.35], foreR: [-0.5, 0, 0], weapon: [W, 0, 0], armL: [-0.2, 0, 0.5], _hipY: -0.05, thighR: [0.25, 0, 0], thighL: [-0.15, 0, 0], _sq: -0.06, head: [0, 0.35, 0] }, 'outCubic'],
    [0.13, { chest: [0.12, 0.8, 0], armR: [-1.35, 0, 0.95], foreR: [-0.15, 0, 0], weapon: [W, 0, 0], armL: [-0.1, 0, 0.9], _hipY: -0.07, _hipZ: 0.1, thighR: [-0.55, 0, 0], kneeR: [0.2, 0, 0], thighL: [0.4, 0, 0], kneeL: [0.4, 0, 0], _sq: 0.08, head: [0, -0.45, 0], _brow: 1 }, 'outExpo'],
    [0.2, { chest: [0.1, 0.95, 0], armR: [-1.25, 0, 1.15], weapon: [W, 0, 0], armL: [0, 0, 0.8], _hipY: -0.06, _hipZ: 0.1, thighR: [-0.5, 0, 0], thighL: [0.35, 0, 0], kneeL: [0.35, 0, 0], head: [0, -0.5, 0], _brow: 1 }, 'outQuad'],
    [0.3, { chest: [0.05, 0.35, 0], armR: [-0.9, 0, 0.5], weapon: [1.6, 0, 0], armL: [0, 0, 0.3], _hipY: -0.03, _hipZ: 0.05 }, 'inOutCubic'],
  ] },
  // revés da esquerda para a direita
  attack2: { dur: 0.3, keys: [
    [0, {}],
    [0.06, { chest: [0.08, 0.85, 0], armR: [-1.2, 0, 1.0], foreR: [-0.7, 0, 0], weapon: [W, 0, 0], armL: [0.2, 0, 0.3], _hipY: -0.05, thighL: [-0.3, 0, 0], thighR: [0.25, 0, 0], _sq: -0.07, head: [0, -0.3, 0] }, 'outCubic'],
    [0.13, { chest: [0.12, -0.8, 0], armR: [-1.4, 0, -1.4], foreR: [-0.1, 0, 0], weapon: [W, 0, 0], armL: [-0.3, 0, 0.6], _hipY: -0.07, _hipZ: 0.1, thighL: [-0.55, 0, 0], kneeL: [0.2, 0, 0], thighR: [0.4, 0, 0], kneeR: [0.4, 0, 0], _sq: 0.08, head: [0, 0.45, 0], _brow: 1 }, 'outExpo'],
    [0.2, { chest: [0.1, -0.95, 0], armR: [-1.3, 0, -1.6], weapon: [W, 0, 0], armL: [-0.2, 0, 0.5], _hipY: -0.06, _hipZ: 0.1, thighL: [-0.5, 0, 0], thighR: [0.35, 0, 0], kneeR: [0.35, 0, 0], head: [0, 0.5, 0], _brow: 1 }, 'outQuad'],
    [0.3, { chest: [0.05, -0.3, 0], armR: [-0.8, 0, -0.5], weapon: [1.6, 0, 0], _hipY: -0.03, _hipZ: 0.05 }, 'inOutCubic'],
  ] },
  // golpe de cima, com pulinho de antecipação
  attack3: { dur: 0.42, keys: [
    [0, {}],
    [0.13, { chest: [-0.45, 0, 0], spine: [-0.15, 0, 0], armR: [-3.0, 0, -0.15], foreR: [-0.4, 0, 0], armL: [-2.8, 0, 0.3], foreL: [-0.4, 0, 0], weapon: [W, 0, 0], _hipY: 0.1, _sq: 0.16, thighL: [-0.3, 0, 0], kneeL: [0.6, 0, 0], thighR: [0.1, 0, 0], kneeR: [0.4, 0, 0], head: [-0.25, 0, 0], _brow: 1 }, 'outCubic'],
    [0.2, { chest: [0.55, 0, 0], spine: [0.2, 0, 0], armR: [-0.65, 0, -0.1], foreR: [-0.1, 0, 0], armL: [-0.75, 0, 0.25], weapon: [W, 0, 0], _hipY: -0.15, _hipZ: 0.14, _sq: -0.2, thighR: [-0.75, 0, 0], kneeR: [0.9, 0, 0], thighL: [0.45, 0, 0], kneeL: [0.6, 0, 0], head: [0.2, 0, 0], _brow: 1 }, 'outExpo'],
    [0.3, { chest: [0.6, 0, 0], spine: [0.2, 0, 0], armR: [-0.5, 0, -0.1], armL: [-0.6, 0, 0.3], weapon: [W, 0, 0], _hipY: -0.16, _hipZ: 0.14, thighR: [-0.75, 0, 0], kneeR: [0.9, 0, 0], thighL: [0.45, 0, 0], kneeL: [0.6, 0, 0], _brow: 1 }, 'linear'],
    [0.42, { chest: [0.15, 0, 0], armR: [-0.7, 0, -0.2], weapon: [0.8, 0, 0], _hipY: -0.04, _hipZ: 0.05 }, 'inOutCubic'],
  ] },
  spin: { dur: 0.5, keys: [
    [0, { _by: 0, armR: [-1.5, 0, -1.4], weapon: [W, 0, 0], armL: [-0.4, 0, 1.3], _hipY: -0.08, _sq: -0.1 }],
    [0.42, { _by: -Math.PI * 2.15, armR: [-1.55, 0, -1.5], weapon: [W, 0, 0], armL: [-0.3, 0, 1.4], _hipY: -0.1, _sq: 0.05, thighL: [-0.3, 0, 0.2], thighR: [-0.3, 0, -0.2], kneeL: [0.4, 0, 0], kneeR: [0.4, 0, 0], _brow: 1 }, 'outCubic'],
    [0.5, { _by: -Math.PI * 2, armR: [-0.9, 0, -0.6], weapon: [1.0, 0, 0], _hipY: -0.04 }, 'inOutQuad'],
  ] },
  roll: { dur: 0.36, keys: [
    [0, { _sq: -0.15, _hipY: -0.1 }],
    [0.05, { _bx: 0.6, _hipY: -0.15, _sq: -0.2, thighL: [-1.4, 0, 0], thighR: [-1.4, 0, 0], kneeL: [1.8, 0, 0], kneeR: [1.8, 0, 0], armL: [-1.5, 0, 0.5], armR: [-1.5, 0, -0.5], foreL: [-1.2, 0, 0], foreR: [-1.2, 0, 0], head: [0.6, 0, 0], spine: [0.5, 0, 0], _eyes: 0.2 }, 'outQuad'],
    [0.3, { _bx: Math.PI * 2 - 0.2, _hipY: -0.12, thighL: [-1.5, 0, 0], thighR: [-1.5, 0, 0], kneeL: [1.9, 0, 0], kneeR: [1.9, 0, 0], armL: [-1.5, 0, 0.5], armR: [-1.5, 0, -0.5], foreL: [-1.3, 0, 0], foreR: [-1.3, 0, 0], head: [0.6, 0, 0], spine: [0.5, 0, 0], _eyes: 0.2 }, 'inOutQuad'],
    [0.36, { _bx: Math.PI * 2, _hipY: -0.06, _sq: -0.12, thighL: [-0.4, 0, 0], kneeL: [0.6, 0, 0] }, 'outQuad'],
  ] },
  cast: { dur: 0.34, keys: [
    [0, {}],
    [0.1, { chest: [-0.15, -0.5, 0], armL: [-0.4, 0, 1.0], foreL: [-1.6, 0, 0], armR: [-0.3, 0, -0.4], _hipY: -0.04, _sq: -0.06, head: [0, 0.3, 0] }, 'outCubic'],
    [0.18, { chest: [0.15, 0.4, 0], armL: [-1.55, 0, 0.1], foreL: [-0.1, 0, 0], armR: [0.3, 0, -0.5], _hipZ: 0.08, _sq: 0.08, thighL: [-0.45, 0, 0], thighR: [0.3, 0, 0], head: [0, -0.2, 0], _brow: 1 }, 'outBack'],
    [0.34, { chest: [0.05, 0.15, 0], armL: [-1.0, 0, 0.2], foreL: [-0.3, 0, 0], _hipZ: 0.04 }, 'inOutQuad'],
  ] },
  hurt: { dur: 0.32, keys: [
    [0, {}],
    [0.06, { chest: [-0.55, 0.2, 0.15], head: [-0.5, 0, 0.2], armL: [-0.9, 0, 1.3], armR: [-0.9, 0, -1.3], foreL: [-0.6, 0, 0], foreR: [-0.6, 0, 0], _hipZ: -0.08, _sq: 0.18, _eyes: 0.15, _mouth: 1 }, 'outExpo'],
    [0.32, { chest: [-0.1, 0, 0], head: [-0.1, 0, 0], _eyes: 0.6 }, 'outElastic'],
  ] },
  dead: { dur: 0.9, hold: true, keys: [
    [0, {}],
    [0.12, { chest: [-0.4, 0, 0], _sq: 0.15, _eyes: 0.1, armL: [-1.4, 0, 1], armR: [-1.4, 0, -1] }, 'outCubic'],
    [0.6, { _bx: -Math.PI / 2, _bodyY: -0.3, _hipY: 0, armL: [-2.8, 0, 0.6], armR: [-2.8, 0, -0.6], thighL: [-0.3, 0, 0], kneeL: [0.6, 0, 0], _eyes: 0, _sq: -0.08 }, 'outBounce'],
    [0.9, { _bx: -Math.PI / 2, _bodyY: -0.31, _hipY: 0, armL: [-2.9, 0, 0.6], armR: [-2.9, 0, -0.6], _eyes: 0 }, 'inOutQuad'],
  ] },
  wave: { dur: 1.4, keys: [
    [0, {}],
    [0.2, { armR: [-2.7, 0, -0.45], foreR: [-0.4, 0, 0], head: [0, 0, 0.12], _sq: 0.06 }, 'outBack'],
    [0.45, { armR: [-2.75, 0, -0.1], foreR: [-0.2, 0, 0.5], head: [0, 0, 0.12] }, 'inOutQuad'],
    [0.7, { armR: [-2.7, 0, -0.55], foreR: [-0.3, 0, -0.4], head: [0, 0, 0.08] }, 'inOutQuad'],
    [0.95, { armR: [-2.75, 0, -0.1], foreR: [-0.2, 0, 0.5], head: [0, 0, 0.1] }, 'inOutQuad'],
    [1.4, {}, 'inOutCubic'],
  ] },
  victory: { dur: 1.2, keys: [
    [0, {}],
    [0.15, { _hipY: -0.1, _sq: -0.2, armR: [-0.4, 0, -0.3] }, 'outQuad'],
    [0.4, { _hipY: 0.25, _sq: 0.2, armR: [-3.0, 0, -0.2], weapon: [W, 0, 0], armL: [-0.2, 0, 1.0], head: [-0.2, 0, 0], _brow: -1 }, 'outBack'],
    [0.6, { _hipY: 0, _sq: -0.15, armR: [-3.0, 0, -0.2], weapon: [W, 0, 0], armL: [-0.2, 0, 1.0] }, 'inQuad'],
    [1.2, { armR: [-2.9, 0, -0.2], weapon: [W, 0, 0], armL: [0, 0, 0.8] }, 'outElastic'],
  ] },
};

// ---------------------------------------------------------------- animador do humanoide
const JOINTS = {
  // nome: [ω, ζ] — mais rígido = responde rápido; mais mole = atrasa (overlapping)
  hips: [26, 0.8], spine: [22, 0.75], chest: [24, 0.72], head: [16, 0.7],
  armL: [26, 0.72], armR: [32, 0.75], foreL: [24, 0.7], foreR: [28, 0.72], handL: [20, 0.7], handR: [22, 0.7],
  thighL: [34, 0.8], thighR: [34, 0.8], kneeL: [34, 0.8], kneeR: [34, 0.8], footL: [30, 0.8], footR: [30, 0.8],
  weapon: [30, 0.7],
};

export class HumanoidAnimator {
  constructor(rig) {
    this.rig = rig;
    const p = rig.parts;
    this.springs = {};
    for (const [k, [w, z]] of Object.entries(JOINTS)) if (p[k]) this.springs[k] = [new Spring(w, z), new Spring(w, z), new Spring(w, z)];
    this.hipY = new Spring(30, 0.75); this.hipZ = new Spring(26, 0.8);
    this.bx = new Spring(40, 0.85); this.by = new Spring(40, 0.9); this.bz = new Spring(14, 0.6);
    this.sq = new Spring(18, 0.32); // gelatina
    this.bodyY = new Spring(22, 0.6);
    this.eyes = new Spring(40, 0.9, 1); this.brow = new Spring(20, 0.8); this.mouth = new Spring(25, 0.7);
    this.hipBase = p.hips.position.y;
    this.phase = 0;
    this.t = 0;
    this.action = null; this.actT = 0;
    this.loop = null; this.loopT = 0;
    this.prevVel = new THREE.Vector3();
    this.accel = new THREE.Vector3();
    this.speed = 0;
    this.blinkT = 2 + Math.random() * 3; this.blink = 0;
    this.lookYaw = 0;
    this.secondary = (rig.chains || []).map((c) => ({ ...c, sx: new Spring(c.w || 10, c.z || 0.35), sz: new Spring(c.w || 10, c.z || 0.35) }));
    this.prevFacing = null; this.turnRate = 0;
  }

  play(name, dur) {
    const a = ACTIONS[name];
    if (!a) return;
    this.action = { name, def: a, scale: dur ? a.dur / dur : 1 };
    this.actT = 0;
    if (name === 'spin') { this.by.x = 0; this.by.v = 0; }
    if (name === 'roll') { this.bx.x = 0; this.bx.v = 0; }
  }
  setLoop(name) { if (this.loop !== name) { this.loop = name; this.loopT = 0; } }
  squash(amount) { this.sq.kick(amount); }

  /** ctx: { vel: Vector3 (mundo), facing (rad), look (yaw local desejado), charge (0..1) } */
  update(dt, ctx) {
    this.t += dt;
    const p = this.rig.parts;
    // ---- velocidade local e aceleração (para inclinação e física secundária)
    const vel = ctx.vel || this.prevVel;
    this.accel.copy(vel).sub(this.prevVel).divideScalar(Math.max(dt, 1e-4));
    this.prevVel.copy(vel);
    const f = ctx.facing ?? 0, cs = Math.cos(f), sn = Math.sin(f);
    const fwd = vel.x * sn + vel.z * cs;
    const accF = this.accel.x * sn + this.accel.z * cs, accS = this.accel.x * cs - this.accel.z * sn;
    const speed = Math.hypot(vel.x, vel.z);
    this.speed += (speed - this.speed) * Math.min(1, dt * 10);
    if (this.prevFacing !== null) this.turnRate += (wrapPi(f - this.prevFacing) / Math.max(dt, 1e-4) - this.turnRate) * Math.min(1, dt * 8);
    this.prevFacing = f;

    // ---- camada de locomoção (contínua)
    const sp = this.speed;
    const walkW = clamp(sp / 2.2, 0, 1), runW = clamp((sp - 3.2) / 2.0, 0, 1);
    const stride = lerp(0.9, 1.25, runW);
    this.phase += (sp / stride) * Math.PI * dt;
    const ph = this.phase;
    const L = {};
    // idle: respiração e troca de peso
    const br = Math.sin(this.t * 2.2), sway = Math.sin(this.t * 0.9);
    const iw = 1 - walkW;
    L.chest = [0.03 * br * iw, 0, 0.02 * sway * iw];
    L.spine = [0, 0, -0.03 * sway * iw];
    L.head = [-0.03 * br * iw, 0, 0];
    L.armL = [0.04 * br * iw, 0, 0.12 + 0.04 * br * iw];
    L.armR = [0.04 * br * iw, 0, -0.12 - 0.04 * br * iw];
    L.foreL = [-0.18, 0, 0]; L.foreR = [-0.25, 0, 0];
    L.weapon = [2.25, 0, 0.15];
    L._hipY = -0.012 * (br * 0.5 + 0.5) * iw;
    L.hips = [0, 0, 0.04 * sway * iw];
    L.thighL = [0, 0, 0.03 * sway * iw]; L.thighR = [0, 0, 0.03 * sway * iw];
    // caminhada/corrida: contato → descida → passagem → subida
    if (walkW > 0.001) {
      const A = lerp(0.55, 0.85, runW) * walkW;
      const sL = Math.sin(ph), cL = Math.cos(ph);
      const kneeA = lerp(0.75, 1.35, runW) * walkW;
      L.thighL = [-sL * A, 0, 0.02];
      L.thighR = [sL * A, 0, -0.02];
      L.kneeL = [Math.max(0, cL) * kneeA + 0.1 * walkW, 0, 0];
      L.kneeR = [Math.max(0, -cL) * kneeA + 0.1 * walkW, 0, 0];
      L.footL = [sL * 0.35 * walkW - Math.max(0, cL) * 0.3 * walkW, 0, 0];
      L.footR = [-sL * 0.35 * walkW - Math.max(0, -cL) * 0.3 * walkW, 0, 0];
      // braços em arco, opostos às pernas
      const armA = lerp(0.55, 0.95, runW) * walkW;
      L.armL = [sL * armA, 0, 0.14 + 0.06 * runW];
      L.armR = [-sL * armA * 0.8 - 0.1 * runW, 0, -0.14 - 0.06 * runW];
      L.foreL = [-0.3 - Math.max(0, sL) * 0.5 * walkW - 0.7 * runW, 0, 0];
      L.foreR = [-0.35 - Math.max(0, -sL) * 0.4 * walkW - 0.6 * runW, 0, 0];
      // quadril: sobe na passagem, desce no contato; balanço lateral; torção
      L._hipY = (Math.cos(2 * ph) * -0.035 - 0.01) * walkW - 0.03 * runW;
      L.hips = [0, sL * 0.16 * walkW, -cL * 0.05 * walkW];
      L.spine = [0.06 * walkW + 0.12 * runW, -sL * 0.1 * walkW, cL * 0.03 * walkW];
      L.chest = [0.04 * walkW + 0.1 * runW, -sL * 0.18 * walkW, 0];
      L.head = [-0.06 * walkW - 0.12 * runW + Math.cos(2 * ph + 0.6) * 0.03 * walkW, sL * 0.12 * walkW, 0];
      L.weapon = [2.25 + sL * 0.15 * walkW, 0, 0.15];
    }
    // inclinação: aceleração para frente/lado e curvas (banking)
    L._bx = clamp(accF * 0.012 + fwd * 0.018, -0.3, 0.35);
    L._bz = clamp(-accS * 0.01 - this.turnRate * sp * 0.012, -0.3, 0.3);
    L._hipZ = 0;
    L._eyes = 1; L._brow = 0; L._mouth = 0;

    // ---- laços (carga, fala, sentar)
    let pose = L;
    if (this.loop) {
      this.loopT += dt;
      const t = this.loopT;
      let lp = null;
      if (this.loop === 'charge') {
        const tr = Math.sin(t * 55) * 0.025 * (ctx.charge >= 1 ? 1.6 : 1);
        lp = { chest: [0.12, -0.95 + tr, 0], spine: [0.1, -0.2, 0], armR: [-0.5, 0, -1.55], foreR: [-0.2, 0, 0], weapon: [W, 0.2, 0], armL: [-0.6, 0, 0.7], foreL: [-0.9, 0, 0], _hipY: -0.1, thighL: [-0.45, 0, 0.1], kneeL: [0.55, 0, 0], thighR: [0.35, 0, -0.1], kneeR: [0.4, 0, 0], head: [0.05, 0.55, 0], _brow: 1, _sq: -0.05 };
      } else if (this.loop === 'talk') {
        const b = Math.sin(t * 5.5), b2 = Math.sin(t * 2.3);
        lp = { head: [0.06 * b, 0.1 * b2, 0.06 * Math.sin(t * 1.7)], armR: [-0.7 - 0.25 * Math.max(0, b), 0.2, -0.35], foreR: [-0.9 - 0.3 * b2, 0, 0], armL: [-0.1, 0, 0.2], chest: [0.04 * b, 0.06 * b2, 0], _mouth: Math.max(0, Math.sin(t * 14)) };
      } else if (this.loop === 'sit') {
        lp = { _hipY: -0.24, thighL: [-1.5, 0, 0.15], thighR: [-1.5, 0, -0.15], kneeL: [1.45, 0, 0], kneeR: [1.45, 0, 0], armL: [-0.5, 0, 0.25], armR: [-0.5, 0, -0.25], foreL: [-0.5, 0, 0], foreR: [-0.5, 0, 0], chest: [0.12 + 0.03 * Math.sin(t * 1.6), 0, 0], head: [0.1 + 0.05 * Math.sin(t * 0.8), 0.2 * Math.sin(t * 0.3), 0] };
      }
      if (lp) pose = blend(clone(L), lp, 1);
    }
    // ---- ação (tween com antecipação/follow-through) por cima de tudo
    if (this.action) {
      const a = this.action;
      this.actT += dt * a.scale;
      const tt = this.actT;
      if (tt >= a.def.dur && !a.def.hold) this.action = null;
      else {
        const sampled = sampleTrack(a.def.keys, Math.min(tt, a.def.dur), pose);
        // nas bordas da ação, mistura com a pose de baixo (entrada/saída suaves)
        const w = a.def.hold ? 1 : clamp(Math.min(tt / 0.04, (a.def.dur - tt) / 0.06 + 0.3), 0, 1);
        pose = blend(clone(pose), sampled, w);
      }
    }
    // olhar (NPCs e herói mirando)
    if (ctx.look !== undefined) { const h = pose.head || [0, 0, 0]; pose.head = [h[0], clamp(h[1] + ctx.look, -1.1, 1.1), h[2]]; }

    // ---- molas → articulações
    for (const k in this.springs) {
      const tg = pose[k] || [0, 0, 0], s = this.springs[k], j = p[k];
      j.rotation.set(s[0].step(tg[0], dt), s[1].step(tg[1], dt), s[2].step(tg[2], dt));
    }
    p.hips.position.y = this.hipBase + this.hipY.step(pose._hipY || 0, dt);
    p.hips.position.z = this.hipZ.step(pose._hipZ || 0, dt);
    const bx = this.bx.step(pose._bx || 0, dt), by = this.by.step(pose._by || 0, dt), bz = this.bz.step(pose._bz || 0, dt);
    p.body.rotation.set(bx, by, bz);
    // rolamento: o corpo encolhe e sobe um pouco no meio do giro (arco)
    p.body.position.y = 0.4 + Math.sin(Math.min(Math.abs(bx), Math.PI)) * 0.05 + this.bodyY.step(pose._bodyY || 0, dt);
    // squash & stretch com volume preservado (mola gelatinosa)
    const s = clamp(this.sq.step(pose._sq || 0, dt), -0.35, 0.4);
    const sy = 1 + s, sxz = 1 / Math.sqrt(sy);
    p.squash.scale.set(sxz, sy, sxz);

    // ---- rosto: piscar, sobrancelhas, boca
    this.blinkT -= dt;
    if (this.blinkT <= 0) { this.blink = 0.14; this.blinkT = 2.2 + Math.random() * 3.5; if (Math.random() < 0.2) this.blinkT = 0.25; }
    let eyeOpen = pose._eyes ?? 1;
    if (this.blink > 0) { this.blink -= dt; eyeOpen = Math.min(eyeOpen, 0.1); }
    const eo = clamp(this.eyes.step(eyeOpen, dt), 0.06, 1.1);
    for (const e of this.rig.eyes || []) e.scale.y = e.userData.sy * eo;
    const bw = this.brow.step(pose._brow || 0, dt);
    for (const b of this.rig.brows || []) { b.rotation.z = b.userData.side * bw * 0.35; b.position.y = b.userData.y - Math.max(0, bw) * 0.02 + Math.max(0, -bw) * 0.02; }
    if (this.rig.mouth) { const m = clamp(this.mouth.step(pose._mouth || 0, dt), 0, 1.2); this.rig.mouth.scale.set(1 - m * 0.3, 0.4 + m * 1.6, 1); }

    // ---- física secundária (cachecol, cabelo, saia, capa): reage à velocidade e à aceleração
    const localF = fwd, localS = vel.x * cs - vel.z * sn;
    for (const c of this.secondary) {
      const tx = c.base[0] + clamp(localF * c.kv + accF * c.ka, -c.max, c.max) + Math.sin(this.t * c.flutter + c.ph) * c.amp * (0.3 + Math.min(1, sp / 3));
      const tz = c.base[2] + clamp(-localS * c.kv * 0.6 - accS * c.ka * 0.6, -c.max, c.max);
      c.obj.rotation.x = c.sx.step(tx, dt);
      c.obj.rotation.z = c.sz.step(tz, dt);
    }
  }
}

// ---------------------------------------------------------------- utilidades para outros bichos
export function angleSpring(w = 12, z = 0.85) {
  const s = new Spring(w, z);
  return {
    get value() { return s.x; },
    set value(v) { s.x = v; s.v = 0; },
    step(target, dt) { const d = wrapPi(target - s.x); return s.step(s.x + d, dt); },
  };
}
