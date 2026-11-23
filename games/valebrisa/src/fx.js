import * as THREE from 'three';
import { unlitMat, shared, toonMat as _toonMat } from './materials.js';
import { TOON } from './style.js';

// =============================================================================
// Efeitos: partículas em "pixels" (cubinhos opacos), cortes de espada em crescente,
// ondas de choque, avisos vermelhos no chão (enchem até o impacto) e números de dano.
// Tudo na camada 1 (sem contorno, sem sombra).
// =============================================================================

const MAXP = 900;

export class FX {
  constructor(scene, renderer, uiRoot) {
    this.scene = scene;
    this.pr = renderer;
    this.ui = uiRoot;
    const geo = new THREE.BoxGeometry(1, 1, 1);
    this.pmesh = new THREE.InstancedMesh(geo, new THREE.MeshBasicMaterial({ color: 0xffffff }), MAXP);
    this.pmesh.layers.set(1);
    this.pmesh.frustumCulled = false;
    this.pmesh.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(MAXP * 3), 3);
    scene.add(this.pmesh);
    this.parts = [];
    this.free = [];
    for (let i = MAXP - 1; i >= 0; i--) this.free.push(i);
    this.m4 = new THREE.Matrix4();
    this.zero = new THREE.Matrix4().makeScale(0, 0, 0);
    for (let i = 0; i < MAXP; i++) this.pmesh.setMatrixAt(i, this.zero);
    this.items = []; // malhas temporárias
    this.texts = [];
    this.col = new THREE.Color();
  }

  particle(p, o = {}) {
    const i = this.free.pop();
    if (i === undefined) return;
    const life = o.life ?? 0.5;
    this.parts.push({
      i, x: p.x, y: p.y, z: p.z,
      vx: o.vx ?? 0, vy: o.vy ?? 0, vz: o.vz ?? 0,
      g: o.g ?? 0, drag: o.drag ?? 0, life, max: life, size: o.size ?? 0.08, shrink: o.shrink ?? true,
      color: new THREE.Color(o.color ?? 0xffffff), color2: o.color2 ? new THREE.Color(o.color2) : null, floor: o.floor,
    });
  }

  burst(p, n, o = {}) {
    for (let k = 0; k < n; k++) {
      const a = Math.random() * Math.PI * 2, sp = (o.speed ?? 3) * (0.4 + Math.random() * 0.8);
      const up = o.up ?? 2;
      this.particle({ x: p.x + (Math.random() - 0.5) * (o.spread ?? 0.2), y: p.y + (Math.random() - 0.5) * (o.spread ?? 0.2), z: p.z + (Math.random() - 0.5) * (o.spread ?? 0.2) }, {
        vx: Math.cos(a) * sp, vz: Math.sin(a) * sp, vy: up * (0.5 + Math.random()),
        g: o.g ?? -9, drag: o.drag ?? 1.5, life: (o.life ?? 0.5) * (0.6 + Math.random() * 0.7), size: (o.size ?? 0.09) * (0.7 + Math.random() * 0.6),
        color: Array.isArray(o.color) ? o.color[Math.floor(Math.random() * o.color.length)] : o.color, color2: o.color2, floor: o.floor,
      });
    }
  }

  dust(p, n = 4, color = 0xd9c9a8) {
    if (TOON && this.puffMesh) {
      for (let k = 0; k < Math.max(1, Math.ceil(n / 2)); k++) this.puff({ x: p.x + (Math.random() - 0.5) * 0.3, y: p.y + 0.08, z: p.z + (Math.random() - 0.5) * 0.3 }, { vx: (Math.random() - 0.5) * 1.2, vz: (Math.random() - 0.5) * 1.2, vy: 0.5, size: 0.11 + Math.random() * 0.08, life: 0.45, color: new THREE.Color(color).lerp(new THREE.Color(0xffffff), 0.35) });
      return;
    }
    this.burst({ x: p.x, y: p.y + 0.08, z: p.z }, n, { speed: 1.2, up: 0.8, g: 0.5, drag: 3, life: 0.45, size: 0.13, color, spread: 0.3 });
  }

  hitSpark(p, color = 0xffffff) {
    this.burst(p, 10, { speed: 5, up: 2.5, g: -6, drag: 4, life: 0.28, size: 0.08, color: [color, 0xffe9a8, 0xffffff] });
  }

  /** corte de espada: crescente horizontal */
  slash(pos, angle, { radius = 1.35, arc = 2.2, color = 0xffffff, color2 = 0xbfe6ff, y = 0.55, dir = 1, life = 0.14, thick = 0.5 } = {}) {
    const g = new THREE.Group();
    const mk = (r0, r1, c, yo) => {
      const geo = new THREE.RingGeometry(r0, r1, 14, 1, -arc / 2, arc);
      geo.rotateX(-Math.PI / 2);
      const m = new THREE.Mesh(geo, unlitMat(c, { transparent: true, side: THREE.DoubleSide, depthWrite: false }));
      m.position.y = yo; m.layers.set(1); g.add(m); return m;
    };
    mk(radius - thick, radius, color, 0);
    mk(radius - thick * 0.45, radius + 0.04, color2, 0.01);
    g.position.set(pos.x, pos.y + y, pos.z);
    g.rotation.y = angle - Math.PI / 2;
    if (dir < 0) g.scale.x = -1;
    this.scene.add(g);
    this.items.push({ obj: g, life, max: life, kind: 'slash' });
    return g;
  }

  ring(pos, { r0 = 0.3, r1 = 3, color = 0xffffff, life = 0.35, y = 0.08, width = 0.25 } = {}) {
    const geo = new THREE.RingGeometry(1 - width, 1, 28);
    geo.rotateX(-Math.PI / 2);
    const m = new THREE.Mesh(geo, unlitMat(color, { transparent: true, side: THREE.DoubleSide, depthWrite: false }));
    m.layers.set(1);
    m.position.set(pos.x, pos.y + y, pos.z);
    this.scene.add(m);
    this.items.push({ obj: m, life, max: life, kind: 'ring', r0, r1 });
    return m;
  }

  /** aviso no chão: anel + preenchimento que cresce até a hora do impacto */
  telegraph(pos, radius, duration, color = 0xff4a4a) {
    const mat = new THREE.ShaderMaterial({
      transparent: true, depthWrite: false,
      uniforms: { uP: { value: 0 }, uColor: { value: new THREE.Color(color) }, uTime: shared.uTime, uNormalPass: shared.uNormalPass },
      vertexShader: 'varying vec2 vUv; void main(){ vUv = uv; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
      fragmentShader: `uniform float uP; uniform vec3 uColor; uniform float uTime; uniform float uNormalPass; varying vec2 vUv;
        void main(){
          if (uNormalPass > 0.5) discard;
          float d = length(vUv - 0.5) * 2.0;
          if (d > 1.0) discard;
          float edge = step(0.84, d);
          float inner = step(0.76, d) * (1.0 - edge);
          float fill = step(d, uP);
          float stripes = step(0.5, fract((vUv.x + vUv.y) * 6.0 - uTime * 1.5));
          float a = max(edge, fill * 0.55 + (1.0 - fill) * stripes * 0.25 + inner * 0.35);
          if (a < 0.05) discard;
          vec3 c = uColor;
          if (edge > 0.5 && step(0.75, fract(uTime * 4.0)) > 0.5) c = vec3(1.0, 0.85, 0.8);
          if (inner > 0.5) c *= 0.6;
          gl_FragColor = vec4(c, a);
        }`,
    });
    const geo = new THREE.PlaneGeometry(radius * 2, radius * 2);
    geo.rotateX(-Math.PI / 2);
    const m = new THREE.Mesh(geo, mat);
    m.layers.set(1);
    m.renderOrder = 2;
    m.position.set(pos.x, pos.y + 0.06, pos.z);
    this.scene.add(m);
    const it = { obj: m, life: duration, max: duration, kind: 'tele', mat };
    this.items.push(it);
    return it;
  }

  /** número de dano / texto flutuante */
  text(pos, str, cls = '') {
    const el = document.createElement('div');
    el.className = 'dmg ' + cls;
    el.textContent = str;
    this.ui.appendChild(el);
    this.texts.push({ el, p: pos.clone(), t: 0, life: cls.includes('big') ? 1.3 : 0.8, vx: (Math.random() - 0.5) * 0.6 });
  }

  update(dt) {
    // partículas
    const m4 = this.m4;
    for (let k = this.parts.length - 1; k >= 0; k--) {
      const p = this.parts[k];
      p.life -= dt;
      if (p.life <= 0) { this.pmesh.setMatrixAt(p.i, this.zero); this.free.push(p.i); this.parts.splice(k, 1); continue; }
      p.vy += p.g * dt;
      const d = Math.exp(-p.drag * dt);
      p.vx *= d; p.vz *= d; p.vy *= p.drag > 2 ? d : 1;
      p.x += p.vx * dt; p.y += p.vy * dt; p.z += p.vz * dt;
      if (p.floor !== undefined && p.y < p.floor) { p.y = p.floor; p.vy *= -0.3; p.vx *= 0.6; p.vz *= 0.6; }
      const t = p.life / p.max;
      const s = p.shrink ? p.size * (0.35 + 0.65 * t) : p.size;
      // tamanho em degraus (fica "pixelado")
      const sq = Math.max(0.045, Math.round(s / 0.045) * 0.045);
      m4.makeScale(sq, sq, sq); m4.setPosition(p.x, p.y, p.z);
      this.pmesh.setMatrixAt(p.i, m4);
      if (p.color2) { this.col.copy(p.color2).lerp(p.color, t); this.pmesh.setColorAt(p.i, this.col); }
      else this.pmesh.setColorAt(p.i, p.color);
    }
    this.pmesh.instanceMatrix.needsUpdate = true;
    this.updateJuice(dt);
    if (this.pmesh.instanceColor) this.pmesh.instanceColor.needsUpdate = true;

    // malhas temporárias
    for (let k = this.items.length - 1; k >= 0; k--) {
      const it = this.items[k];
      it.life -= dt;
      const t = 1 - Math.max(0, it.life) / it.max;
      if (it.kind === 'slash') {
        const op = it.life / it.max;
        it.obj.children.forEach((c) => { c.material.opacity = op > 0.5 ? 1 : op * 2; });
        it.obj.scale.y = 1;
        const s = 1 + t * 0.12; it.obj.scale.x = Math.sign(it.obj.scale.x) * s; it.obj.scale.z = s;
      } else if (it.kind === 'ring') {
        const r = it.r0 + (it.r1 - it.r0) * (1 - (1 - t) * (1 - t));
        it.obj.scale.set(r, 1, r);
        it.obj.material.opacity = 1 - t;
      } else if (it.kind === 'swirl') {
        const e = 1 - Math.pow(1 - t, 3);
        it.obj.scale.setScalar(it.s0 + (it.s1 - it.s0) * e);
        it.obj.rotation[it.obj.rotation.x ? 'z' : 'y'] += it.spin * (1 - t) * dt * 3;
        it.obj.position.y += it.rise * dt * (1 - t);
        it.obj.material.opacity = t < 0.6 ? 1 : 1 - (t - 0.6) / 0.4;
      } else if (it.kind === 'impact') {
        const r = it.r0 + (it.r1 - it.r0) * (1 - Math.pow(1 - t, 2));
        it.obj.scale.setScalar(r);
        it.obj.material.opacity = 1 - t * t;
      } else if (it.kind === 'tele') {
        it.mat.uniforms.uP.value = Math.floor(t * 10) / 10;
      }
      if (it.life <= 0 && !it.keep) {
        this.scene.remove(it.obj);
        it.obj.traverse((o) => { if (o.geometry) o.geometry.dispose(); if (o.material) o.material.dispose(); });
        this.items.splice(k, 1);
      }
    }

    // textos
    const sp = { x: 0, y: 0 };
    for (let k = this.texts.length - 1; k >= 0; k--) {
      const tx = this.texts[k];
      tx.t += dt;
      if (tx.t > tx.life) { tx.el.remove(); this.texts.splice(k, 1); continue; }
      const hop = tx.t < 0.25 ? Math.sin((tx.t / 0.25) * Math.PI) * 0.45 : 0;
      const p = tx.p.clone(); p.y += 1.3 + hop + tx.t * 0.35; p.x += tx.vx * tx.t; p.z -= tx.vx * tx.t;
      this.pr.project(p, sp);
      const s = this.pr.pixelScale / (this.pr.W / window.innerWidth);
      tx.el.style.transform = `translate(${Math.round(sp.x / s) * s}px, ${Math.round(sp.y / s) * s}px) translate(-50%, -50%)`;
      tx.el.style.opacity = tx.t > tx.life - 0.2 ? '0' : '1';
    }
  }

  clear() {
    for (const it of this.items) { this.scene.remove(it.obj); }
    this.items = [];
    for (const tx of this.texts) tx.el.remove();
    this.texts = [];
  }
}

// =============================================================================
// Juice estilo desenho animado: fumacinhas redondas (puffs), espirais de vento,
// estrelinhas de impacto, anel de impacto, rastro da espada.
// =============================================================================

const MAXPUFF = 260, MAXSTAR = 80, MAXSWIRL = 24;
const easeOutBack = (t) => { const c1 = 1.9, c3 = c1 + 1; return 1 + c3 * Math.pow(t - 1, 3) + c1 * Math.pow(t - 1, 2); };

function spiralGeo(turns = 1.6, r0 = 0.05, r1 = 0.55, w = 0.09, seg = 40) {
  const pos = [], idx = [];
  for (let i = 0; i <= seg; i++) {
    const t = i / seg, a = t * turns * Math.PI * 2, r = r0 + (r1 - r0) * t;
    const ww = w * Math.sin(Math.min(1, t * 1.4) * Math.PI * 0.5) * (1 - t * 0.35);
    const cx = Math.cos(a), cz = Math.sin(a);
    pos.push(cx * (r - ww), 0, cz * (r - ww), cx * (r + ww), 0, cz * (r + ww));
    if (i < seg) { const b = i * 2; idx.push(b, b + 1, b + 2, b + 1, b + 3, b + 2); }
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setIndex(idx);
  return g;
}
function starGeo() {
  const sh = new THREE.Shape();
  const n = 4;
  for (let i = 0; i <= n * 2; i++) {
    const a = (i / (n * 2)) * Math.PI * 2 + Math.PI / 2, r = i % 2 ? 0.32 : 1;
    if (i === 0) sh.moveTo(Math.cos(a) * r, Math.sin(a) * r); else sh.lineTo(Math.cos(a) * r, Math.sin(a) * r);
  }
  return new THREE.ShapeGeometry(sh);
}

FX.prototype.initJuice = function (camera) {
  this.cam = camera;
  // puffs: bolinhas sólidas com sombreado toon (fumaça de desenho animado)
  const pg = new THREE.IcosahedronGeometry(1, 2);
  this.puffMat = _toonMat({ color: 0xffffff, outline: 0, key: 'puff', cel: true });
  this.puffMesh = new THREE.InstancedMesh(pg, this.puffMat, MAXPUFF);
  this.puffMesh.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(MAXPUFF * 3).fill(1), 3);
  this.puffMesh.layers.set(1); this.puffMesh.frustumCulled = false;
  this.scene.add(this.puffMesh);
  this.puffs = []; this.puffFree = [];
  for (let i = MAXPUFF - 1; i >= 0; i--) { this.puffFree.push(i); this.puffMesh.setMatrixAt(i, this.zero); }
  // estrelinhas (billboard)
  this.starMesh = new THREE.InstancedMesh(starGeo(), new THREE.MeshBasicMaterial({ color: 0xffffff, side: THREE.DoubleSide }), MAXSTAR);
  this.starMesh.instanceColor = new THREE.InstancedBufferAttribute(new Float32Array(MAXSTAR * 3).fill(1), 3);
  this.starMesh.layers.set(1); this.starMesh.frustumCulled = false; this.starMesh.renderOrder = 4;
  this.scene.add(this.starMesh);
  this.stars = []; this.starFree = [];
  for (let i = MAXSTAR - 1; i >= 0; i--) { this.starFree.push(i); this.starMesh.setMatrixAt(i, this.zero); }
  // espirais
  this.swirlGeos = [spiralGeo(1.6), spiralGeo(2.2, 0.04, 0.5, 0.07), spiralGeo(1.2, 0.1, 0.7, 0.11)];
  this.swirls = [];
  // rastro da espada
  this.trails = [];
};

FX.prototype.puff = function (p, o = {}) {
  const i = this.puffFree.pop();
  if (i === undefined) return;
  const life = o.life ?? 0.55;
  this.puffs.push({ i, x: p.x, y: p.y, z: p.z, vx: o.vx ?? 0, vy: o.vy ?? 0.6, vz: o.vz ?? 0, drag: o.drag ?? 3, g: o.g ?? 0, life, max: life, size: o.size ?? 0.25, color: new THREE.Color(o.color ?? 0xffffff) });
};
/** "poof": anel de fumacinhas saltando para fora */
FX.prototype.poof = function (p, o = {}) {
  const n = o.n ?? 9, sp = o.speed ?? 3, col = o.color ?? 0xffffff;
  for (let k = 0; k < n; k++) {
    const a = (k / n) * Math.PI * 2 + Math.random() * 0.4;
    const s = sp * (0.6 + Math.random() * 0.6);
    this.puff({ x: p.x + Math.cos(a) * 0.2, y: p.y + (o.y ?? 0.3) + Math.random() * 0.2, z: p.z + Math.sin(a) * 0.2 }, { vx: Math.cos(a) * s, vz: Math.sin(a) * s, vy: (o.up ?? 1.5) * (0.5 + Math.random()), size: (o.size ?? 0.28) * (0.7 + Math.random() * 0.6), life: (o.life ?? 0.6) * (0.75 + Math.random() * 0.5), drag: 4, color: Array.isArray(col) ? col[k % col.length] : col });
  }
};
FX.prototype.star = function (p, o = {}) {
  const i = this.starFree.pop();
  if (i === undefined) return;
  const a = Math.random() * Math.PI * 2, sp = o.speed ?? 3;
  const life = o.life ?? 0.45;
  this.stars.push({ i, x: p.x, y: p.y, z: p.z, vx: Math.cos(a) * sp, vy: (o.up ?? 2) + Math.random() * 1.5, vz: Math.sin(a) * sp, rot: Math.random() * 6, spin: (Math.random() - 0.5) * 12, life, max: life, size: o.size ?? 0.18, color: new THREE.Color(o.color ?? 0xffe680), g: o.g ?? -9 });
};
FX.prototype.stars3 = function (p, n = 4, o = {}) { for (let k = 0; k < n; k++) this.star(p, o); };
FX.prototype.swirl = function (p, o = {}) {
  const geo = this.swirlGeos[o.kind ?? Math.floor(Math.random() * 3)];
  const m = new THREE.Mesh(geo, unlitMat(o.color ?? 0xffffff, { transparent: true, side: THREE.DoubleSide, depthWrite: false }));
  m.layers.set(1); m.renderOrder = 3;
  m.position.set(p.x, p.y + (o.y ?? 0.4), p.z);
  if (o.vertical) { m.rotation.x = Math.PI / 2; m.rotation.z = o.angle ?? 0; }
  else m.rotation.y = o.angle ?? Math.random() * 6;
  this.scene.add(m);
  const life = o.life ?? 0.6;
  this.items.push({ obj: m, life, max: life, kind: 'swirl', s0: o.s0 ?? 0.4, s1: o.size ?? 1.6, spin: o.spin ?? 5, rise: o.rise ?? 0.6 });
};
/** anel de impacto de desenho animado: disco claro que estoura e some */
FX.prototype.impact = function (p, o = {}) {
  const g = new THREE.RingGeometry(0.55, 1, 20);
  const m = new THREE.Mesh(g, unlitMat(o.color ?? 0xffffff, { transparent: true, side: THREE.DoubleSide, depthWrite: false }));
  m.layers.set(1); m.renderOrder = 4;
  m.position.set(p.x, p.y, p.z);
  if (this.cam) m.quaternion.copy(this.cam.quaternion);
  this.scene.add(m);
  const life = o.life ?? 0.16;
  this.items.push({ obj: m, life, max: life, kind: 'impact', r0: o.r0 ?? 0.15, r1: o.size ?? 0.9 });
};

/** rastro de espada: guarda as posições da base e da ponta a cada quadro */
export class SwordTrail {
  constructor(fx, color = 0xffffff, edge = 0x9fe3ff, n = 16) {
    this.n = n; this.pts = []; this.active = false;
    const g = new THREE.BufferGeometry();
    this.pos = new Float32Array(n * 2 * 3);
    this.alpha = new Float32Array(n * 2);
    this.side = new Float32Array(n * 2);
    for (let i = 0; i < n; i++) { this.side[i * 2] = 0; this.side[i * 2 + 1] = 1; }
    const idx = [];
    for (let i = 0; i < n - 1; i++) { const b = i * 2; idx.push(b, b + 1, b + 2, b + 1, b + 3, b + 2); }
    g.setIndex(idx);
    g.setAttribute('position', new THREE.BufferAttribute(this.pos, 3));
    g.setAttribute('aAlpha', new THREE.BufferAttribute(this.alpha, 1));
    g.setAttribute('aSide', new THREE.BufferAttribute(this.side, 1));
    this.geo = g;
    this.mat = new THREE.ShaderMaterial({
      transparent: true, depthWrite: false, side: THREE.DoubleSide,
      uniforms: { uCore: { value: new THREE.Color(color) }, uEdge: { value: new THREE.Color(edge) }, uNormalPass: shared.uNormalPass },
      vertexShader: 'attribute float aAlpha; attribute float aSide; varying float vA; varying float vS; void main(){ vA = aAlpha; vS = aSide; gl_Position = projectionMatrix * modelViewMatrix * vec4(position,1.0); }',
      fragmentShader: `uniform vec3 uCore; uniform vec3 uEdge; uniform float uNormalPass; varying float vA; varying float vS;
        void main(){ if (uNormalPass > 0.5 || vA < 0.02) discard; float e = smoothstep(0.55, 1.0, vS);
          vec3 c = mix(uEdge * 1.3, uCore * 1.8, e); gl_FragColor = vec4(c, min(1.0, vA * 1.4) * mix(0.5, 1.0, e)); }`,
    });
    this.mesh = new THREE.Mesh(g, this.mat);
    this.mesh.layers.set(1); this.mesh.frustumCulled = false; this.mesh.renderOrder = 3;
    fx.scene.add(this.mesh);
  }
  push(base, tip) { this.pts.unshift([base.clone(), tip.clone(), 1]); if (this.pts.length > this.n) this.pts.pop(); }
  update(dt) {
    for (const p of this.pts) p[2] -= dt * (this.active ? 3.2 : 7);
    while (this.pts.length && this.pts[this.pts.length - 1][2] <= 0) this.pts.pop();
    for (let i = 0; i < this.n; i++) {
      const p = this.pts[Math.min(i, this.pts.length - 1)];
      if (!p) { this.alpha[i * 2] = this.alpha[i * 2 + 1] = 0; continue; }
      const a = i < this.pts.length ? Math.max(0, p[2]) * (1 - i / this.n) : 0;
      this.pos.set([p[0].x, p[0].y, p[0].z], i * 6); this.pos.set([p[1].x, p[1].y, p[1].z], i * 6 + 3);
      this.alpha[i * 2] = a; this.alpha[i * 2 + 1] = a;
    }
    this.geo.attributes.position.needsUpdate = true; this.geo.attributes.aAlpha.needsUpdate = true;
  }
}

FX.prototype.updateJuice = function (dt) {
  if (!this.puffMesh) return;
  const m4 = this.m4, q = new THREE.Quaternion(), sv = new THREE.Vector3(), pv = new THREE.Vector3();
  for (let k = this.puffs.length - 1; k >= 0; k--) {
    const p = this.puffs[k];
    p.life -= dt;
    if (p.life <= 0) { this.puffMesh.setMatrixAt(p.i, this.zero); this.puffFree.push(p.i); this.puffs.splice(k, 1); continue; }
    const d = Math.exp(-p.drag * dt);
    p.vx *= d; p.vz *= d; p.vy = p.vy * d + p.g * dt;
    p.x += p.vx * dt; p.y += p.vy * dt; p.z += p.vz * dt;
    const t = 1 - p.life / p.max;
    const s = p.size * (t < 0.3 ? easeOutBack(t / 0.3) : 1 - Math.pow((t - 0.3) / 0.7, 2));
    m4.compose(pv.set(p.x, p.y, p.z), q, sv.setScalar(Math.max(0.001, s)));
    this.puffMesh.setMatrixAt(p.i, m4);
    this.puffMesh.setColorAt(p.i, p.color);
  }
  this.puffMesh.instanceMatrix.needsUpdate = true; this.puffMesh.instanceColor.needsUpdate = true;
  const cq = this.cam ? this.cam.quaternion : q;
  for (let k = this.stars.length - 1; k >= 0; k--) {
    const s = this.stars[k];
    s.life -= dt;
    if (s.life <= 0) { this.starMesh.setMatrixAt(s.i, this.zero); this.starFree.push(s.i); this.stars.splice(k, 1); continue; }
    s.vy += s.g * dt; s.x += s.vx * dt; s.y += s.vy * dt; s.z += s.vz * dt; s.rot += s.spin * dt;
    const t = 1 - s.life / s.max;
    const sc = s.size * (t < 0.25 ? easeOutBack(t / 0.25) : 1 - Math.pow((t - 0.25) / 0.75, 3));
    const rq = cq.clone().multiply(new THREE.Quaternion().setFromAxisAngle(new THREE.Vector3(0, 0, 1), s.rot));
    m4.compose(pv.set(s.x, s.y, s.z), rq, sv.setScalar(Math.max(0.001, sc)));
    this.starMesh.setMatrixAt(s.i, m4); this.starMesh.setColorAt(s.i, s.color);
  }
  this.starMesh.instanceMatrix.needsUpdate = true; this.starMesh.instanceColor.needsUpdate = true;
  for (const tr of this.trails) tr.update(dt);
};
