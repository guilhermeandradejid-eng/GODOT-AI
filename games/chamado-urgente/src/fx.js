import * as THREE from 'three';

// Partículas estilizadas ("bolinhas" low-poly) em dois InstancedMesh:
// `lit` (fumaça, poeira, confete — recebem luz) e `glow` (fogo, faíscas — sem luz, com bloom).
class Pool {
  constructor(scene, material, cap, detail = 0) {
    this.cap = cap;
    this.mesh = new THREE.InstancedMesh(new THREE.IcosahedronGeometry(1, detail), material, cap);
    this.mesh.instanceMatrix.setUsage(THREE.DynamicDrawUsage);
    this.mesh.setColorAt(0, new THREE.Color());
    this.mesh.instanceColor.setUsage(THREE.DynamicDrawUsage);
    this.mesh.count = 0;
    this.mesh.frustumCulled = false;
    scene.add(this.mesh);
    this.ps = [];
  }
  add(p) {
    if (this.ps.length >= this.cap) this.ps.shift();
    this.ps.push(p);
  }
}

const _m = new THREE.Matrix4();
const _q = new THREE.Quaternion();
const _e = new THREE.Euler();
const _s = new THREE.Vector3();
const _c = new THREE.Color();
const _p = new THREE.Vector3();

export class FX {
  constructor(scene) {
    this.lit = new Pool(scene, new THREE.MeshStandardMaterial({ roughness: 0.95 }), 900, 1);
    this.lit.mesh.castShadow = false;
    this.glow = new Pool(scene, new THREE.MeshBasicMaterial({ toneMapped: false }), 900);
  }

  emit({ pos, vel = [0, 0, 0], spread = 0.2, vspread = 0.2, life = 1, size = 0.1, size1 = 0, color = 0xffffff, color1 = null, gravity = 0, drag = 0, glow = false, count = 1, intensity = 1 }) {
    const pool = glow ? this.glow : this.lit;
    for (let i = 0; i < count; i++) {
      const l = life * (0.7 + Math.random() * 0.6);
      pool.add({
        x: pos.x + (Math.random() - 0.5) * spread, y: pos.y + (Math.random() - 0.5) * spread * 0.5, z: pos.z + (Math.random() - 0.5) * spread,
        vx: vel[0] + (Math.random() - 0.5) * vspread, vy: vel[1] + (Math.random() - 0.5) * vspread, vz: vel[2] + (Math.random() - 0.5) * vspread,
        t: 0, life: l, s0: size * (0.7 + Math.random() * 0.6), s1: size1, g: gravity, drag,
        c0: new THREE.Color(color).multiplyScalar(intensity), c1: color1 != null ? new THREE.Color(color1).multiplyScalar(intensity) : null,
        rx: Math.random() * 6, ry: Math.random() * 6, spin: (Math.random() - 0.5) * 8,
      });
    }
  }

  // ---- presets ----
  fire(p, k = 1) {
    this.emit({ pos: p, vel: [0, 1.9 * k, 0], spread: 0.6 * k, vspread: 0.6, life: 0.7, size: 0.2 * k, size1: 0.02, color: 0xffd86b, color1: 0xff3b1f, glow: true, intensity: 1.15, count: 3 });
    this.emit({ pos: { x: p.x, y: p.y + 0.15, z: p.z }, vel: [0, 2.6 * k, 0], spread: 0.3 * k, vspread: 0.3, life: 0.45, size: 0.13 * k, size1: 0.0, color: 0xfff6c0, color1: 0xffb02b, glow: true, intensity: 1.3, count: 1 });
    if (Math.random() < 0.6) this.emit({ pos: { x: p.x, y: p.y + 0.7 * k, z: p.z }, vel: [0, 1.3, 0], spread: 0.4, vspread: 0.3, life: 1.8, size: 0.16, size1: 0.5 * k, color: 0x3a3436, color1: 0x8a8486, count: 1 });
  }
  smoke(p, dark = false) {
    this.emit({ pos: p, vel: [0, 0.9, 0], spread: 0.25, vspread: 0.35, life: 1.4, size: 0.08, size1: 0.3, color: dark ? 0x2a2627 : 0xbfc4cf, color1: dark ? 0x6a6466 : 0xeef1f6, count: 1 });
  }
  sparks(p, n = 6) {
    this.emit({ pos: p, vel: [0, 2.2, 0], spread: 0.05, vspread: 3.2, life: 0.4, size: 0.035, size1: 0, color: 0xfff3a0, color1: 0xff9b2b, glow: true, intensity: 1.6, gravity: -9, count: n });
  }
  foam(p, dir) {
    this.emit({ pos: p, vel: [dir.x * 6, 0.6, dir.z * 6], spread: 0.08, vspread: 0.9, life: 0.55, size: 0.06, size1: 0.26, color: 0xffffff, color1: 0xe6f2ff, drag: 2.5, gravity: -2, count: 3 });
  }
  puff(p, n = 6, color = 0xf4efe6) {
    this.emit({ pos: p, vel: [0, 0.5, 0], spread: 0.3, vspread: 1.4, life: 0.45, size: 0.09, size1: 0.0, color, drag: 3, count: n });
  }
  confetti(p) {
    const cols = [0xff5a5a, 0xffd23f, 0x3d7bff, 0x2fc46b, 0xb05cff, 0xff8a2b];
    for (let i = 0; i < 26; i++) this.emit({ pos: p, vel: [0, 4.2, 0], spread: 0.2, vspread: 4, life: 1.2, size: 0.05, size1: 0.03, color: cols[i % cols.length], gravity: -9, drag: 1.2, count: 1 });
  }
  hearts(p) {
    this.emit({ pos: p, vel: [0, 1.6, 0], spread: 0.4, vspread: 0.6, life: 1.0, size: 0.07, size1: 0.0, color: 0xff6fa5, glow: true, intensity: 1.2, count: 6 });
  }
  bits(p) { // "bits" verdes do antivírus
    this.emit({ pos: p, vel: [0, 1.2, 0], spread: 0.6, vspread: 0.8, life: 0.7, size: 0.04, size1: 0.0, color: 0x6ee36e, glow: true, intensity: 1.3, count: 2 });
  }

  update(dt) {
    for (const pool of [this.lit, this.glow]) {
      const ps = pool.ps;
      let n = 0;
      for (let i = 0; i < ps.length; i++) {
        const p = ps[i];
        p.t += dt;
        if (p.t >= p.life) continue;
        const d = Math.max(0, 1 - p.drag * dt);
        p.vx *= d; p.vz *= d; p.vy = p.vy * d + p.g * dt;
        p.x += p.vx * dt; p.y += p.vy * dt; p.z += p.vz * dt;
        if (p.y < 0.02) { p.y = 0.02; p.vy *= -0.3; p.vx *= 0.6; p.vz *= 0.6; }
        p.rx += p.spin * dt; p.ry += p.spin * dt * 0.7;
        const k = p.t / p.life;
        const s = Math.max(0.0001, p.s0 + (p.s1 - p.s0) * k) * (k < 0.12 ? k / 0.12 : 1);
        _q.setFromEuler(_e.set(p.rx, p.ry, 0));
        _m.compose(_p.set(p.x, p.y, p.z), _q, _s.set(s, s, s));
        pool.mesh.setMatrixAt(n, _m);
        if (p.c1) _c.copy(p.c0).lerp(p.c1, k); else _c.copy(p.c0);
        pool.mesh.setColorAt(n, _c);
        ps[n++] = p;
      }
      ps.length = n;
      pool.mesh.count = n;
      pool.mesh.instanceMatrix.needsUpdate = true;
      if (pool.mesh.instanceColor) pool.mesh.instanceColor.needsUpdate = true;
    }
  }
}
