import * as THREE from 'three';
import { toonMat, shared, GLSL_COMMON } from './materials.js';
import { fbm, vnoise, clamp, smoothstep, lerp } from './noise.js';

// =============================================================================
// Mundo de Valebrisa: campo de alturas em "terraços" (penhascos íngremes com contorno
// orgânico), trilhas que viram rampas suaves, rio com margens de areia/barranco, ponte.
// O desenho é feito em coordenadas de tela (u = direita, v = baixo), e convertido para o
// mundo girado 45° (câmera isométrica).
// =============================================================================

export const S = Math.SQRT1_2;
export const toWorld = (u, v) => ({ x: (u + v) * S, z: (v - u) * S });
export const toUV = (x, z) => ({ u: (x - z) * S, v: (x + z) * S });
export const LH = 1.2;           // altura de um nível
export const WATER_Y = -0.45;
const U0 = -46, U1 = 46, V0 = -56, V1 = 56, CELL = 0.4;

export const hex = (h) => { const c = new THREE.Color(h); return `vec3(${c.r.toFixed(3)},${c.g.toFixed(3)},${c.b.toFixed(3)})`; };

// ---------------------------------------------------------------- formas
const sdEllipse = (u, v, cu, cv, ru, rv) => { const du = (u - cu) / ru, dv = (v - cv) / rv; return (Math.hypot(du, dv) - 1) * Math.min(ru, rv); };
function sdSeg(u, v, a, b) {
  const pu = u - a[0], pv = v - a[1], bu = b[0] - a[0], bv = b[1] - a[1];
  const h = clamp((pu * bu + pv * bv) / (bu * bu + bv * bv), 0, 1);
  return Math.hypot(pu - bu * h, pv - bv * h);
}
const sdPoly = (u, v, pts) => { let d = 1e9; for (let i = 0; i < pts.length - 1; i++) d = Math.min(d, sdSeg(u, v, pts[i], pts[i + 1])); return d; };

export const riverV = (u) => 9.5 + Math.sin(u * 0.13 + 0.5) * 2.2 + Math.sin(u * 0.37) * 0.7;
const riverHW = (u) => 1.5 + vnoise(u * 0.25, 3.3) * 0.6;

// lugares importantes (u, v)
export const PLACES = {
  spawn: [0.5, 27],
  plaza: [0, 29.5],
  elder: [-2.2, 27.4],
  merchant: [4.6, 31.6],
  bridge: [1, riverV(1)],
  meadow: [0, -1],
  hollow: [17, -5.5],
  plateauW: [-16.5, -4.5],
  gate: [0, -15.8],
  clearing: [0, -30],
  pond: [-25, 5],
};

export const PATHS = [
  { w: 1.0, pts: [[0, 31], [0, 25], [0.6, 18], [1, 13.5], [1, 8], [0, 3], [-1, -1], [-0.5, -6], [0, -11], [0, -17], [0, -22], [0, -26]] },
  { w: 0.7, pts: [[-1, -1], [-5, -2], [-9, -3.5], [-13, -4.5], [-16, -4.5]] },
  { w: 0.7, pts: [[-0.5, -6], [4, -5], [9, -5], [13, -5.5], [16.5, -5.5]] },
  { w: 0.55, pts: [[0, 28], [-5, 27], [-9.5, 26]] },
  { w: 0.55, pts: [[0, 28], [5, 26.5], [9.5, 25.5]] },
  { w: 0.55, pts: [[0, 31], [-4, 33], [-8, 35]] },
  { w: 0.55, pts: [[0, 31], [4, 33.5], [8.5, 35]] },
  { w: 0.6, pts: [[-5, -2], [-12, 1], [-20, 4], [-24, 5]] },
];

const PLATEAUS = [
  { c: [-16.5, -4.5], r: 6.5 },
  { c: [17, -5.5], r: 7 },
  { c: [-6.5, 3.5], r: 2.1 },
  { c: [12, 2.5], r: 2.6 },
  { c: [-11, 17], r: 3 },
  { c: [11, 17.5], r: 2.4 },
];

function playableSDF(u, v) {
  let d = sdEllipse(u, v, 0, 30, 16, 10.5);
  d = Math.min(d, sdSeg(u, v, [0, 22], [0, 7]) - 6.5);
  d = Math.min(d, sdEllipse(u, v, 0, -1, 28, 12.5));
  d = Math.min(d, sdEllipse(u, v, -24, 5, 6, 4.5));
  d = Math.min(d, sdSeg(u, v, [0, -10], [0, -21]) - 4.2);
  d = Math.min(d, Math.hypot(u, v + 30) - 10.5);
  return d;
}

// ---------------------------------------------------------------- geração
export class World {
  constructor() {
    this.NU = Math.round((U1 - U0) / CELL) + 1;
    this.NV = Math.round((V1 - V0) / CELL) + 1;
    const N = this.NU * this.NV;
    this.H = new Float32Array(N);
    this.F = new Float32Array(N);
    this.walk = new Uint8Array(N);
    this.mask = new Uint8Array(N * 4);
    this.colliders = [];
    this.bridge = null;
    this.generate();
  }

  idx(i, j) { return j * this.NU + i; }

  generate() {
    const { NU, NV, H, F, mask } = this;
    const bu = 1, bvr = riverV(1), bhw = riverHW(1);
    this.bridge = { u: bu, v0: bvr - bhw - 1.6, v1: bvr + bhw + 1.6, hw: 1.15, y: 0.12 };
    for (let j = 0; j < NV; j++) {
      const v = V0 + j * CELL;
      for (let i = 0; i < NU; i++) {
        const u = U0 + i * CELL;
        const k = j * NU + i;
        const nz = fbm(u * 0.11 + 3, v * 0.11 - 5);
        let d = playableSDF(u, v) + (nz - 0.5) * 4.2;
        const north = clamp((-v - 13.2) / 3.2, 0, 1);
        let f = north + clamp(d * 0.5, 0, 3.2);
        for (const p of PLATEAUS) {
          const dist = Math.hypot(u - p.c[0], v - p.c[1]);
          f += clamp((p.r - dist + (fbm(u * 0.3, v * 0.3 + p.r) - 0.5) * 2.4) * 0.55, 0, 1);
        }
        // rio
        const rD = Math.abs(v - riverV(u)) - riverHW(u);
        const riverOn = d < 1.0;
        if (riverOn) f = Math.min(f, -1 + clamp(rD * 0.75 + 0.45, 0, 1) + Math.max(0, f - 1) * 0);
        // trilhas
        let pm = 0;
        for (const p of PATHS) {
          const pd = sdPoly(u, v, p.pts) + (vnoise(u * 0.9, v * 0.9) - 0.5) * 0.5;
          pm = Math.max(pm, smoothstep(p.w + 0.35, p.w - 0.25, pd));
        }
        const onRiver = riverOn && rD < 0.9;
        const pathSmooth = onRiver ? 0 : pm;
        const bank = riverOn ? smoothstep(2.2, 0.4, rD) * smoothstep(0.42, 0.62, vnoise(u * 0.18 + 9, 2.7)) : 0;
        const tr = Math.floor(f) + smoothstep(0.44, 0.56, f - Math.floor(f));
        const smooth = Math.max(pathSmooth, bank * 0.9);
        F[k] = f;
        H[k] = lerp(tr, f, smooth) * LH;
        // máscaras de superfície
        const plaza = smoothstep(4.4, 3.9, Math.hypot(u - PLACES.plaza[0], v - PLACES.plaza[1]) + (vnoise(u * 1.3, v * 1.3) - 0.5) * 0.5);
        const arena = smoothstep(5.6, 4.8, Math.hypot(u, v + 30) + (vnoise(u, v) - 0.5) * 1.4) * 0.85;
        const sand = riverOn ? smoothstep(1.7, 0.6, rD + (vnoise(u * 0.7, v * 0.7) - 0.5) * 0.8) : 0;
        const pondSand = 0;
        const dark = clamp(smoothstep(-11, -19, v) * 0.75 + clamp((d - 0.5) * 0.25, 0, 1) * 0.6, 0, 1);
        mask[k * 4] = Math.round(clamp(Math.max(pm * (onRiver ? 0 : 1), arena), 0, 1) * 255);
        mask[k * 4 + 1] = Math.round(clamp(Math.max(sand, pondSand), 0, 1) * 255);
        mask[k * 4 + 2] = Math.round(plaza * 255);
        mask[k * 4 + 3] = Math.round(dark * 255);
      }
    }
    // lago do canto oeste (rebaixa)
    for (let j = 0; j < NV; j++) for (let i = 0; i < NU; i++) {
      const u = U0 + i * CELL, v = V0 + j * CELL, k = j * NU + i;
      const pd = sdEllipse(u, v, -26.5, 5.5, 3.6, 2.6) + (vnoise(u * 0.8, v * 0.8) - 0.5) * 0.8;
      if (pd < 1.6) {
        const t = smoothstep(1.6, -0.6, pd);
        H[k] = Math.min(H[k], lerp(H[k], -1.1 * LH, t));
        mask[k * 4 + 1] = Math.max(mask[k * 4 + 1], Math.round(smoothstep(1.8, 0.2, pd) * 255));
        mask[k * 4] = Math.round(mask[k * 4] * smoothstep(0.5, 1.6, pd));
      }
    }
    // caminhabilidade
    let hmin = 1e9, hmax = -1e9;
    for (let j = 0; j < NV; j++) for (let i = 0; i < NU; i++) {
      const k = j * NU + i;
      const h = H[k];
      hmin = Math.min(hmin, h); hmax = Math.max(hmax, h);
      let s = 0;
      if (i < NU - 1) s = Math.max(s, Math.abs(H[k + 1] - h));
      if (i > 0) s = Math.max(s, Math.abs(H[k - 1] - h));
      if (j < NV - 1) s = Math.max(s, Math.abs(H[k + NU] - h));
      if (j > 0) s = Math.max(s, Math.abs(H[k - NU] - h));
      const u = U0 + i * CELL, v = V0 + j * CELL;
      let ok = s / CELL < 0.95 && h > WATER_Y - 0.12;
      if (this.inBridge(u, v)) ok = Math.abs(u - this.bridge.u) < this.bridge.hw - 0.25;
      this.walk[k] = ok ? 1 : 0;
    }
    this.hmin = hmin; this.hmax = hmax;
  }

  inBridge(u, v) { const b = this.bridge; return Math.abs(u - b.u) < b.hw + 0.3 && v > b.v0 && v < b.v1; }

  sampleH(u, v) {
    const fi = clamp((u - U0) / CELL, 0, this.NU - 1.001), fj = clamp((v - V0) / CELL, 0, this.NV - 1.001);
    const i = Math.floor(fi), j = Math.floor(fj), tx = fi - i, ty = fj - j;
    const k = j * this.NU + i, H = this.H;
    return lerp(lerp(H[k], H[k + 1], tx), lerp(H[k + this.NU], H[k + this.NU + 1], tx), ty);
  }

  heightAt(x, z) {
    const { u, v } = toUV(x, z);
    let h = this.sampleH(u, v);
    const b = this.bridge;
    if (Math.abs(u - b.u) < b.hw && v > b.v0 && v < b.v1) {
      const t = (v - b.v0) / (b.v1 - b.v0);
      const deck = b.y + Math.sin(t * Math.PI) * 0.25;
      h = Math.max(h, deck);
    }
    return h;
  }

  walkableUV(u, v) {
    const i = Math.round((u - U0) / CELL), j = Math.round((v - V0) / CELL);
    if (i < 0 || j < 0 || i >= this.NU || j >= this.NV) return false;
    return this.walk[j * this.NU + i] === 1;
  }

  walkable(x, z) { const { u, v } = toUV(x, z); return this.walkableUV(u, v); }

  /** círculo livre de penhascos/água/colisores sólidos */
  freeCircle(x, z, r) {
    if (!this.walkable(x, z)) return false;
    for (let a = 0; a < 6; a++) {
      const ang = (a / 6) * Math.PI * 2;
      if (!this.walkable(x + Math.cos(ang) * r, z + Math.sin(ang) * r)) return false;
    }
    return true;
  }

  maskAt(u, v) {
    const i = clamp(Math.round((u - U0) / CELL), 0, this.NU - 1), j = clamp(Math.round((v - V0) / CELL), 0, this.NV - 1);
    const k = (j * this.NU + i) * 4;
    return { path: this.mask[k] / 255, sand: this.mask[k + 1] / 255, plaza: this.mask[k + 2] / 255, dark: this.mask[k + 3] / 255 };
  }

  slopeAt(u, v) {
    const e = CELL;
    return Math.max(Math.abs(this.sampleH(u + e, v) - this.sampleH(u - e, v)), Math.abs(this.sampleH(u, v + e) - this.sampleH(u, v - e))) / (2 * e);
  }

  /** resolve movimento de um círculo: desliza por penhascos e colisores */
  move(pos, dx, dz, r) {
    let nx = pos.x + dx, nz = pos.z + dz;
    if (!this.freeCircle(nx, nz, r)) {
      if (this.freeCircle(pos.x + dx, pos.z, r)) nz = pos.z;
      else if (this.freeCircle(pos.x, pos.z + dz, r)) nx = pos.x;
      else { nx = pos.x; nz = pos.z; }
    }
    // colisores
    for (const c of this.colliders) {
      if (c.off) continue;
      if (c.type === 'circle') {
        const ddx = nx - c.x, ddz = nz - c.z, rr = c.r + r;
        const d2 = ddx * ddx + ddz * ddz;
        if (d2 < rr * rr && d2 > 1e-8) { const d = Math.sqrt(d2); nx = c.x + (ddx / d) * rr; nz = c.z + (ddz / d) * rr; }
      } else {
        // caixa orientada (ângulo c.a)
        const ca = Math.cos(c.a), sa = Math.sin(c.a);
        const lx = (nx - c.x) * ca - (nz - c.z) * sa, lz = (nx - c.x) * sa + (nz - c.z) * ca;
        const qx = clamp(lx, -c.hx, c.hx), qz = clamp(lz, -c.hz, c.hz);
        const ex = lx - qx, ez = lz - qz, d2 = ex * ex + ez * ez;
        if (d2 < r * r) {
          let px, pz;
          if (d2 > 1e-8) { const d = Math.sqrt(d2); px = qx + (ex / d) * r; pz = qz + (ez / d) * r; }
          else { // dentro: empurra pelo eixo mais próximo
            const ox = c.hx - Math.abs(lx), oz = c.hz - Math.abs(lz);
            if (ox < oz) { px = Math.sign(lx || 1) * (c.hx + r); pz = lz; } else { px = lx; pz = Math.sign(lz || 1) * (c.hz + r); }
          }
          nx = c.x + px * ca + pz * sa; nz = c.z - px * sa + pz * ca;
        }
      }
    }
    if (!this.freeCircle(nx, nz, r * 0.7)) { nx = pos.x; nz = pos.z; }
    pos.x = nx; pos.z = nz;
  }

  addCircle(x, z, r) { const c = { type: 'circle', x, z, r }; this.colliders.push(c); return c; }
  addBox(x, z, hx, hz, a = 0) { const c = { type: 'box', x, z, hx, hz, a }; this.colliders.push(c); return c; }

  // ------------------------------------------------------------ texturas de dados
  textures() {
    if (this._tex) return this._tex;
    const { NU, NV } = this;
    const maskTex = new THREE.DataTexture(this.mask, NU, NV, THREE.RGBAFormat);
    maskTex.magFilter = maskTex.minFilter = THREE.LinearFilter;
    maskTex.needsUpdate = true;
    const hd = new Uint8Array(NU * NV * 4);
    for (let k = 0; k < NU * NV; k++) {
      const t = clamp((this.H[k] - this.hmin) / (this.hmax - this.hmin), 0, 1) * 65535;
      hd[k * 4] = Math.floor(t / 256); hd[k * 4 + 1] = Math.floor(t) % 256; hd[k * 4 + 3] = 255;
    }
    const hTex = new THREE.DataTexture(hd, NU, NV, THREE.RGBAFormat);
    hTex.magFilter = hTex.minFilter = THREE.NearestFilter;
    hTex.needsUpdate = true;
    this._tex = {
      tMask: { value: maskTex }, tHeight: { value: hTex },
      uMapRect: { value: new THREE.Vector4(U0, V0, 1 / (U1 - U0), 1 / (V1 - V0)) },
      uHRange: { value: new THREE.Vector2(this.hmin, this.hmax - this.hmin) },
      uCell: { value: new THREE.Vector2(NU, NV) },
    };
    return this._tex;
  }

  // ------------------------------------------------------------ malhas
  buildTerrainMesh() {
    const { NU, NV, H } = this;
    const pos = new Float32Array(NU * NV * 3);
    for (let j = 0; j < NV; j++) for (let i = 0; i < NU; i++) {
      const k = j * NU + i;
      const w = toWorld(U0 + i * CELL, V0 + j * CELL);
      pos[k * 3] = w.x; pos[k * 3 + 1] = H[k]; pos[k * 3 + 2] = w.z;
    }
    const idx = new Uint32Array((NU - 1) * (NV - 1) * 6);
    let n = 0;
    for (let j = 0; j < NV - 1; j++) for (let i = 0; i < NU - 1; i++) {
      const a = j * NU + i, b = a + 1, c = a + NU, d = c + 1;
      // diagonal escolhida pela menor diferença (penhascos mais limpos)
      if (Math.abs(H[a] - H[d]) < Math.abs(H[b] - H[c])) { idx.set([a, c, d, a, d, b], n); }
      else { idx.set([a, c, b, b, c, d], n); }
      n += 6;
    }
    const g = new THREE.BufferGeometry();
    g.setAttribute('position', new THREE.BufferAttribute(pos, 3));
    g.setIndex(new THREE.BufferAttribute(idx, 1));
    g.computeVertexNormals();
    g.computeBoundingSphere();
    const mat = toonMat({ key: 'terrain', outline: 0.55, uniforms: this.textures(), fragHead: TERRAIN_HEAD, albedoGLSL: 'diffuseColor.rgb = terrainAlbedo(vWPos, normalize(vWNormal));' });
    const mesh = new THREE.Mesh(g, mat);
    mesh.receiveShadow = true;
    mesh.castShadow = true;
    mesh.name = 'Terreno';
    return mesh;
  }

  buildWaterMesh() {
    const g = new THREE.PlaneGeometry(170, 170, 1, 1);
    g.rotateX(-Math.PI / 2);
    const mat = new THREE.ShaderMaterial({
      uniforms: { ...shared, ...this.textures(), uWaterY: { value: WATER_Y } },
      vertexShader: /* glsl */ `
        varying vec3 vWPos; varying vec3 vWNormal;
        void main() { vec4 wp = modelMatrix * vec4(position, 1.0); vWPos = wp.xyz; vWNormal = vec3(0.0,1.0,0.0); gl_Position = projectionMatrix * viewMatrix * wp; }`,
      fragmentShader: GLSL_COMMON + WATER_FS,
      transparent: true, depthWrite: false,
    });
    const m = new THREE.Mesh(g, mat);
    m.position.y = WATER_Y;
    m.name = 'Agua';
    return m;
  }
}

// ---------------------------------------------------------------- GLSL do terreno
export const TERRAIN_HEAD = /* glsl */ `
uniform sampler2D tMask;
uniform vec4 uMapRect;
vec4 mapMask(vec3 wp) {
  float u = (wp.x - wp.z) * 0.70710678, v = (wp.x + wp.z) * 0.70710678;
  return texture2D(tMask, vec2((u - uMapRect.x) * uMapRect.z, (v - uMapRect.y) * uMapRect.w));
}
vec3 pick3(float t, vec3 a, vec3 b, vec3 c) { return t < 0.36 ? a : (t < 0.66 ? b : c); }
vec3 grassAlbedo(vec3 wp, vec4 m, float dith) {
  float n = vb_fbm(wp.xz * 0.09) + (vb_noise(wp.xz * 0.7) - 0.5) * 0.18 + dith;
  vec3 g = pick3(n, ${hex('#97c257')}, ${hex('#7dad4b')}, ${hex('#659846')});
  vec3 f = pick3(n, ${hex('#6c9c4e')}, ${hex('#578249')}, ${hex('#466d48')});
  float dk = m.a + (vb_noise(wp.xz * 0.4) - 0.5) * 0.25;
  g = dk > 0.55 ? f : (dk > 0.3 ? mix(g, f, 0.5) : g);
  // manchas secas/amareladas espalhadas
  float dry = vb_noise(wp.xz * 0.13 + 11.0);
  if (dry > 0.72 && dk < 0.4) g = mix(g, ${hex('#b3b45a')}, 0.45);
  return g;
}
float pebble(vec2 p, float dens) { return vb_hash2(floor(p * 6.0)) > dens ? 1.0 : 0.0; }
vec3 terrainAlbedo(vec3 wp, vec3 wn) {
  vec4 m = mapMask(wp);
  float dith = (vb_bayer(gl_FragCoord.xy) - 0.5) * 0.07;
  float slope = 1.0 - wn.y;
  vec3 col = grassAlbedo(wp, m, dith) * 0.86;
  // chão sob a grama: trevos, florzinhas, terra aparecendo
  vec2 cell = floor(wp.xz * 5.0);
  float h = vb_hash(cell);
  if (h > 0.993) col = vb_hash(cell + 3.1) > 0.5 ? ${hex('#f4efd8')} : ${hex('#f2cf5b')};
  else if (vb_noise(wp.xz * 1.1) > 0.8) col = mix(col, ${hex('#8a7a4c')}, 0.35);
  // terra batida: pedrinhas com sombra, sulcos
  float pn = (vb_noise(wp.xz * 1.6) - 0.5) * 0.34 + (vb_noise(wp.xz * 5.0) - 0.5) * 0.1;
  if (m.r + pn > 0.5) {
    float t = vb_noise(wp.xz * 0.5) + dith;
    col = t < 0.5 ? ${hex('#c9aa7c')} : ${hex('#bc9d70')};
    if (vb_noise(wp.xz * 2.5) > 0.7) col = ${hex('#ae9066')};
    if (pebble(wp.xz, 0.93) > 0.5) col = ${hex('#ddc8a2')};
    else if (pebble(wp.xz - vec2(0.07, 0.07), 0.93) > 0.5) col = ${hex('#9c7a4a')};
    if (m.r + pn < 0.56) col = ${hex('#a9894f')};
    else if (m.r + pn < 0.6) col = mix(col, ${hex('#8f9a4c')}, 0.35);
  }
  // areia com marolas e conchinhas
  if (m.g + pn * 0.8 > 0.5) {
    col = vb_noise(wp.xz * 0.8) + dith < 0.55 ? ${hex('#e9d6a0')} : ${hex('#dcc58b')};
    float rip = sin((wp.x - wp.z) * 9.0 + vb_noise(wp.xz * 1.5) * 4.0);
    if (rip > 0.82) col *= 0.93;
    if (pebble(wp.xz, 0.975) > 0.5) col = ${hex('#f6eee0')};
    else if (pebble(wp.xz - vec2(0.07, 0.07), 0.975) > 0.5) col = ${hex('#b8a070')};
  }
  // pedras da praça com chanfro (luz em cima/esq., sombra embaixo/dir.)
  if (m.b + pn * 0.5 > 0.5) {
    vec2 q = wp.xz * 1.25;
    float row = floor(q.y);
    q.x += mod(row, 2.0) * 0.5;
    vec2 f = fract(q), id = floor(q);
    float tone = vb_hash2(id);
    col = tone < 0.4 ? ${hex('#d6c9b0')} : (tone < 0.8 ? ${hex('#c8b9a0')} : ${hex('#b9a990')});
    if (vb_hash2(id + 7.0) > 0.85) col = mix(col, ${hex('#9fb07a')}, 0.25);
    if (f.x < 0.07 || f.y < 0.09) col = ${hex('#8a7b6e')};
    else if (f.x < 0.14 || f.y < 0.16) col *= 0.88;
    else if (f.x > 0.88 || f.y > 0.88) col *= 1.07;
    if (vb_hash2(floor(wp.xz * 9.0)) > 0.97) col *= 0.92;
  }
  // penhasco: estratos, rachaduras, raízes penduradas, musgo na borda
  if (slope > 0.32) {
    float y = wp.y + (vb_noise(wp.xz * 1.3) - 0.5) * 0.35;
    float band = floor(y * 2.6);
    float fb = fract(y * 2.6);
    float alt = mod(band, 2.0);
    col = alt < 0.5 ? ${hex('#a6948d')} : ${hex('#8f7d80')};
    if (fb > 0.84) col *= 1.12;
    else if (fb < 0.12) col *= 0.82;
    float side = (wp.x - wp.z);
    float cr = vb_noise(vec2(side * 3.0, y * 0.8));
    if (cr > 0.78) col = ${hex('#6c5e6e')};
    float lv = fract(wp.y / ${LH.toFixed(2)} + 0.02);
    float vine = vb_noise(vec2(side * 4.5, 1.0));
    if (lv > 0.86 && vb_noise(wp.xz * 2.0) > 0.3) col = m.a > 0.5 ? ${hex('#4f7b4a')} : ${hex('#72a14e')};
    else if (vine > 0.7 && lv > 1.0 - (vine - 0.7) * 2.6) col = vb_hash2(floor(vec2(side * 12.0, wp.y * 12.0))) > 0.6 ? ${hex('#5a8a46')} : ${hex('#3f6a45')};
    if (lv < 0.1) col *= 0.85;
    if (wp.y < ${(WATER_Y + 0.2).toFixed(2)}) col = ${hex('#7d7a7c')};
  }
  // leito do rio com cáusticas
  if (wp.y < ${(WATER_Y - 0.03).toFixed(2)}) {
    col = mix(col, ${hex('#6f8f80')}, 0.55);
    vec2 cq = wp.xz * 1.4 + vec2(uTime * 0.25, uTime * 0.1);
    float ca = abs(vb_noise(cq) - vb_noise(cq * 1.3 + 4.0 - uTime * 0.2));
    if (ca < 0.05) col = mix(col, ${hex('#d8f2e8')}, 0.6);
  }
  return col;
}
`;

const WATER_FS = /* glsl */ `
uniform sampler2D tHeight;
uniform vec4 uMapRect;
uniform vec2 uHRange;
uniform float uWaterY;
float terrainH(vec3 wp) {
  float u = (wp.x - wp.z) * 0.70710678, v = (wp.x + wp.z) * 0.70710678;
  vec4 t = texture2D(tHeight, vec2((u - uMapRect.x) * uMapRect.z, (v - uMapRect.y) * uMapRect.w));
  return uHRange.x + (t.r * 255.0 * 256.0 + t.g * 255.0) / 65535.0 * uHRange.y;
}
void main() {
  if (uNormalPass > 0.5) { gl_FragColor = vec4(0.5, 0.94, 0.66, 0.08); return; }
  float depth = uWaterY - terrainH(vWPos);
  if (depth < -0.02) discard;
  float u = (vWPos.x - vWPos.z) * 0.70710678, v = (vWPos.x + vWPos.z) * 0.70710678;
  float dth = vb_bayer(gl_FragCoord.xy);
  float t = floor(uTime * 10.0) / 10.0;
  float dd = depth + (dth - 0.5) * 0.12;
  vec3 deep = ${hex('#2f6f9e')}, mid = ${hex('#3f92b8')}, shallow = ${hex('#5cbccb')};
  vec3 col = dd > 0.6 ? deep : (dd > 0.3 ? mid : shallow);
  float alpha = dd > 0.6 ? 0.94 : (dd > 0.3 ? 0.82 : 0.62);
  // reflexo do céu e das nuvens
  vec3 sky = uSkyColor * 1.15 + uSunColor * 0.12;
  col = mix(col, col * sky * 1.25, 0.3);
  float cl = vb_cloud(vWPos.xz * 0.9 + vec2(9.0, 3.0));
  if (cl > 0.5) col = mix(col, uSkyColor * 1.4 + 0.1, 0.22);
  // correnteza e ondinhas
  float s = vb_noise(vec2(u * 0.55 - t * 0.9, v * 2.4));
  float s2 = vb_noise(vec2(u * 1.3 - t * 1.4, v * 4.0) + 7.0);
  if (s > 0.74 && depth > 0.12) col = mix(col, ${hex('#a6e0e6')} * (uSunColor + 0.2), 0.7);
  else if (s2 > 0.8) col *= 1.08;
  // brilho do sol nas ondas (vira bloom)
  float sp = vb_hash(floor(vec2(u, v) * 4.0) + floor(uTime * 3.0));
  if (sp > 0.985 && s2 > 0.55) { col = uSunColor * 2.4 + 0.3; alpha = 1.0; }
  // espuma que vai e volta na margem
  float wave = sin(uTime * 1.6 + u * 0.7 + vb_noise(vec2(u, v) * 1.2) * 4.0) * 0.05;
  if (depth < 0.1 + wave) { col = ${hex('#eef8f2')} * (uSunColor * 0.6 + uSkyColor * 0.5); alpha = 0.95; }
  else if (depth < 0.17 + wave && mod(floor(gl_FragCoord.x + gl_FragCoord.y), 2.0) < 1.0) { col = mix(col, ${hex('#c6ece8')}, 0.6); alpha = 0.85; }
  float cloud = vb_cloud(vWPos.xz) * uCloud;
  col *= 1.0 - cloud * 0.15;
  col += vb_points(col, vWPos, vec3(0.0, 1.0, 0.0)) * 0.8;
  gl_FragColor = vec4(col, alpha);
}`;
