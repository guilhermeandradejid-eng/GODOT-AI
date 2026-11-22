import * as THREE from 'three';
import { unlitMat, shared } from './materials.js';

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
