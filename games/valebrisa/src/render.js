import * as THREE from 'three';
import { shared } from './materials.js';

// =============================================================================
// Pipeline de "pixel art 3D":
//  1. a cena é desenhada numa resolução baixa (≈ 300 px de altura), com 1 px de borda extra;
//  2. um segundo passe (mesmos materiais, uNormalPass=1) grava normais + profundidade,
//     sem grama nem efeitos (camada 1), para achar arestas;
//  3. a composição detecta silhuetas (contorno escuro da própria cor) e arestas convexas
//     (brilho claro), aplica correção de cor/vinheta e amplia com "nearest" em escala inteira;
//  4. a câmera ortográfica anda presa ao grid de pixels; o resto subpixel vira um deslocamento
//     na ampliação, então o movimento fica suave sem os pixels "nadarem".
// =============================================================================

const COMPOSITE_VS = /* glsl */ `
varying vec2 vUv;
void main() { vUv = uv; gl_Position = vec4(position.xy, 0.0, 1.0); }`;

const COMPOSITE_FS = /* glsl */ `
precision highp float;
uniform sampler2D tColor;
uniform sampler2D tNormal;
uniform sampler2D tDepth;
uniform sampler2D tBloom;
uniform vec2 uLowRes;      // tamanho do alvo baixo (com borda)
uniform vec2 uOut;         // tamanho do canvas em px
uniform float uScale;      // px de tela por px do jogo
uniform vec2 uOffset;      // deslocamento subpixel (em px do jogo)
uniform float uNear, uFar;
uniform float uDepthK;     // profundidade -> unidades de mundo
uniform mat4 uInvViewProj;
uniform float uTime;
uniform float uHitFlash;
uniform float uVignette;
uniform float uFade;
uniform vec3 uFadeColor;
uniform float uOutlines;
// pós
uniform float uAO;
uniform float uBloom;
uniform vec3 uFogColor;
uniform vec3 uFogParams;   // topo, base, densidade
uniform float uHaze;
uniform float uFocusDepth;
// color grading
uniform float uExposure;
uniform float uSat;
uniform float uContrast;
uniform vec3 uLift;
uniform vec3 uGain;
uniform vec3 uShadowTint;
uniform vec3 uHighTint;

float lin(vec2 uv) { return texture2D(tDepth, uv).r * uDepthK; }
float bayer(vec2 fc) {
  ivec2 p = ivec2(mod(fc, 4.0));
  int i = p.x + p.y * 4;
  int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
  return (float(m[i]) + 0.5) / 16.0;
}
float hash(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float noise(vec2 p) { vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(hash(i), hash(i + vec2(1, 0)), u.x), mix(hash(i + vec2(0, 1)), hash(i + vec2(1, 1)), u.x), u.y); }
float luma(vec3 c) { return dot(c, vec3(0.3, 0.59, 0.11)); }

float normalEdge(vec3 n, vec3 nn, float depthDiff) {
  float normalDiff = dot(n - nn, vec3(1.0));
  float ni = clamp(smoothstep(-0.01, 0.01, normalDiff), 0.0, 1.0);
  float di = clamp(sign(depthDiff * 0.25 + 0.0025), 0.0, 1.0);
  return (1.0 - dot(n, nn)) * di * ni;
}

void main() {
  vec2 fc = gl_FragCoord.xy;
  vec2 game = (fc - 0.5 * uOut) / uScale + 0.5 * uLowRes + uOffset;
  vec2 px = floor(game) + 0.5;
  vec2 texel = 1.0 / uLowRes;
  vec2 uv = px * texel;
  float dth = bayer(px);

  vec3 col = texture2D(tColor, uv).rgb;
  vec4 nc = texture2D(tNormal, uv);
  bool geo = nc.a > 0.001;
  float d = lin(uv);

  // ---- oclusão de ambiente (vincos: os dois vizinhos mais perto que o plano)
  if (geo && uAO > 0.0) {
    float occ = 0.0;
    vec2 dirs[4];
    dirs[0] = vec2(1.0, 0.0); dirs[1] = vec2(0.0, 1.0); dirs[2] = vec2(0.7, 0.7); dirs[3] = vec2(0.7, -0.7);
    for (int i = 0; i < 4; i++) {
      for (int k = 1; k <= 2; k++) {
        vec2 o = dirs[i] * texel * float(k * 3);
        float a = lin(uv + o), b = lin(uv - o);
        float crease = (2.0 * d - a - b);
        float rangeOk = step(abs(d - a), 2.5) * step(abs(d - b), 2.5);
        occ += clamp(crease * 1.6, 0.0, 1.0) * rangeOk;
      }
    }
    occ = clamp(occ / 4.0, 0.0, 1.0);
    occ = floor(occ * 3.0 + 0.5 + (dth - 0.5) * 0.5) / 3.0;
    col *= 1.0 - occ * uAO;
  }

  // ---- traço externo de anime: pixel de fundo encostado num personagem vira tinta
  bool inked = false;
  if (uOutlines > 0.5) {
    vec2 o4[4];
    o4[0] = vec2(0.0, texel.y); o4[1] = vec2(0.0, -texel.y); o4[2] = vec2(texel.x, 0.0); o4[3] = vec2(-texel.x, 0.0);
    for (int i = 0; i < 4; i++) {
      vec4 nn4 = texture2D(tNormal, uv + o4[i]);
      if (nn4.a > 0.97 && (!geo || nc.a < 0.97) && (geo ? d - lin(uv + o4[i]) > 0.3 : true)) inked = true;
    }
    if (inked) col = vec3(0.1, 0.08, 0.15) + col * 0.15;
  }

  // ---- contornos e brilho de aresta
  if (geo && uOutlines > 0.5 && !inked) {
    vec3 n = normalize(nc.rgb * 2.0 - 1.0);
    vec2 offs[4];
    offs[0] = vec2(0.0, texel.y); offs[1] = vec2(0.0, -texel.y); offs[2] = vec2(texel.x, 0.0); offs[3] = vec2(-texel.x, 0.0);
    float dEdge = 0.0;
    float nEdge = 0.0;
    for (int i = 0; i < 4; i++) {
      vec2 o = uv + offs[i];
      vec4 nn4 = texture2D(tNormal, o);
      float dn = nn4.a > 0.001 ? lin(o) : uFar * 2.0;
      dEdge += clamp((dn - d) - 0.45, 0.0, 1.0);
      if (nn4.a > 0.001) nEdge += normalEdge(n, normalize(nn4.rgb * 2.0 - 1.0), dn - d);
    }
    dEdge = dEdge > 0.0 ? 1.0 : 0.0;
    nEdge = smoothstep(0.18, 0.5, nEdge);
    float strength = nc.a;
    if (strength > 0.97) {
      // personagem anime: por dentro só um vinco leve entre partes sobrepostas
      if (dEdge > 0.0) col = mix(col, col * vec3(0.55, 0.5, 0.65), 0.6);
    } else if (dEdge > 0.0) col = mix(col, col * vec3(0.32, 0.3, 0.42), strength);
    else col = mix(col, col * vec3(1.18, 1.15, 1.05) + vec3(0.05, 0.05, 0.03), nEdge * strength * 0.85);
  }

  // ---- névoa de altura (com fiapos) e neblina de profundidade
  vec4 ndc = vec4(uv * 2.0 - 1.0, texture2D(tDepth, uv).r * 2.0 - 1.0, 1.0);
  vec4 wp = uInvViewProj * ndc; wp /= wp.w;
  float fog = clamp((uFogParams.x - wp.y) / max(uFogParams.x - uFogParams.y, 0.001), 0.0, 1.0);
  fog *= uFogParams.z * (0.65 + 0.7 * noise(wp.xz * 0.18 + vec2(uTime * 0.05, uTime * 0.02)));
  float haze = geo ? clamp((d - uFocusDepth) * uHaze, 0.0, 0.55) : 0.55;
  float f = clamp(fog + haze, 0.0, 0.85);
  f = floor(f * 10.0 + 0.5 + (dth - 0.5) * 0.5) / 10.0;
  col = mix(col, uFogColor, f);

  // ---- bloom (meia resolução, amostrado no centro do pixel do jogo)
  col += texture2D(tBloom, uv).rgb * uBloom;

  // ---- color grading
  col *= uExposure;
  float l = luma(col);
  col *= mix(uShadowTint, uHighTint, smoothstep(0.08, 0.85, l));
  col = (col - 0.42) * uContrast + 0.42;
  l = luma(col);
  col = mix(vec3(l), col, uSat);
  col = uLift + col * uGain;
  // compressão suave dos altos (HDR -> tela)
  float mx = max(col.r, max(col.g, col.b));
  if (mx > 0.85) col *= (0.85 + (mx - 0.85) / (1.0 + (mx - 0.85) * 1.1)) / mx;

  // vinheta em degraus
  vec2 q = uv - 0.5;
  float v = dot(q * vec2(1.0, 1.25), q * vec2(1.0, 1.25));
  float vig = floor(smoothstep(0.12, 0.55, v) * 4.0) / 4.0;
  col *= 1.0 - vig * uVignette;

  col = mix(col, vec3(1.0, 0.95, 0.9), uHitFlash);
  col = mix(col, uFadeColor, uFade);
  // dither final (evita faixas no bloom/névoa)
  col += (dth - 0.5) / 160.0;
  gl_FragColor = vec4(max(col, 0.0), 1.0);
}`;

const BRIGHT_FS = /* glsl */ `
uniform sampler2D tColor; uniform vec2 uTexel; uniform float uThreshold; varying vec2 vUv;
void main() {
  vec3 c = vec3(0.0);
  c += texture2D(tColor, vUv + uTexel * vec2(-0.5, -0.5)).rgb;
  c += texture2D(tColor, vUv + uTexel * vec2(0.5, -0.5)).rgb;
  c += texture2D(tColor, vUv + uTexel * vec2(-0.5, 0.5)).rgb;
  c += texture2D(tColor, vUv + uTexel * vec2(0.5, 0.5)).rgb;
  c *= 0.25;
  float l = max(c.r, max(c.g, c.b));
  float k = clamp((l - uThreshold) / 0.4, 0.0, 1.0);
  gl_FragColor = vec4(c * k * k, 1.0);
}`;
const BLUR_FS = /* glsl */ `
uniform sampler2D tSrc; uniform vec2 uDir; varying vec2 vUv;
void main() {
  vec3 c = texture2D(tSrc, vUv).rgb * 0.227;
  c += (texture2D(tSrc, vUv + uDir * 1.385).rgb + texture2D(tSrc, vUv - uDir * 1.385).rgb) * 0.316;
  c += (texture2D(tSrc, vUv + uDir * 3.231).rgb + texture2D(tSrc, vUv - uDir * 3.231).rgb) * 0.07;
  gl_FragColor = vec4(c, 1.0);
}`;

export class PixelRenderer {
  constructor(canvas) {
    THREE.ColorManagement.enabled = false;
    this.renderer = new THREE.WebGLRenderer({ canvas, antialias: false, powerPreference: 'high-performance', preserveDrawingBuffer: false });
    this.renderer.outputColorSpace = THREE.LinearSRGBColorSpace;
    this.renderer.toneMapping = THREE.NoToneMapping;
    this.renderer.shadowMap.enabled = true;
    this.renderer.shadowMap.type = THREE.BasicShadowMap;
    this.renderer.setPixelRatio(1);
    this.ppu = 22; // pixels do jogo por unidade de mundo
    this.pixelScaleOverride = 0;
    this.outlines = true;

    // câmera isométrica
    this.camera = new THREE.OrthographicCamera(-1, 1, 1, -1, 0.1, 120);
    this.yaw = Math.PI / 4;
    this.pitch = THREE.MathUtils.degToRad(33);
    this.camDist = 50;
    const dir = new THREE.Vector3(Math.sin(this.yaw) * Math.cos(this.pitch), Math.sin(this.pitch), Math.cos(this.yaw) * Math.cos(this.pitch));
    this.camDir = dir;
    this.camera.position.copy(dir).multiplyScalar(this.camDist);
    this.camera.lookAt(0, 0, 0);
    this.camera.updateMatrixWorld();
    this.camRight = new THREE.Vector3().setFromMatrixColumn(this.camera.matrixWorld, 0).normalize();
    this.camUp = new THREE.Vector3().setFromMatrixColumn(this.camera.matrixWorld, 1).normalize();
    this.camera.layers.enable(1);
    this.focus = new THREE.Vector3();
    this.shake = new THREE.Vector2();
    this.offset = new THREE.Vector2();

    this.quadScene = new THREE.Scene();
    this.quadCam = new THREE.OrthographicCamera(-1, 1, 1, -1, 0, 1);
    this.compMat = new THREE.ShaderMaterial({
      vertexShader: COMPOSITE_VS,
      fragmentShader: COMPOSITE_FS,
      uniforms: {
        tColor: { value: null }, tNormal: { value: null }, tDepth: { value: null },
        uLowRes: { value: new THREE.Vector2() }, uOut: { value: new THREE.Vector2() }, uScale: { value: 3 },
        uOffset: { value: new THREE.Vector2() }, uNear: { value: 0.1 }, uFar: { value: 120 }, uDepthK: { value: 120 },
        uHitFlash: { value: 0 }, uVignette: { value: 0.22 }, uFade: { value: 0 }, uFadeColor: { value: new THREE.Color(0.06, 0.05, 0.1) },
        uOutlines: { value: 1 }, tBloom: { value: null }, uInvViewProj: { value: new THREE.Matrix4() }, uTime: shared.uTime,
        uAO: { value: 0.32 }, uBloom: { value: 0.8 }, uFogColor: { value: new THREE.Color(0.7, 0.75, 0.85) }, uFogParams: { value: new THREE.Vector3(-0.2, -1.2, 0.0) },
        uHaze: { value: 0.012 }, uFocusDepth: { value: 50 },
        uExposure: { value: 1 }, uSat: { value: 1.08 }, uContrast: { value: 1.05 }, uLift: { value: new THREE.Color(0.02, 0.012, 0.04) }, uGain: { value: new THREE.Color(1, 0.985, 0.97) },
        uShadowTint: { value: new THREE.Color(0.96, 0.96, 1.06) }, uHighTint: { value: new THREE.Color(1.04, 1.0, 0.95) },
      },
      depthTest: false, depthWrite: false,
    });
    this.quad = new THREE.Mesh(new THREE.PlaneGeometry(2, 2), this.compMat);
    this.quadScene.add(this.quad);
    this.brightMat = new THREE.ShaderMaterial({ vertexShader: COMPOSITE_VS, fragmentShader: BRIGHT_FS, uniforms: { tColor: { value: null }, uTexel: { value: new THREE.Vector2() }, uThreshold: { value: 1.0 } }, depthTest: false, depthWrite: false });
    this.blurMat = new THREE.ShaderMaterial({ vertexShader: COMPOSITE_VS, fragmentShader: BLUR_FS, uniforms: { tSrc: { value: null }, uDir: { value: new THREE.Vector2() } }, depthTest: false, depthWrite: false });
    const r = this.renderer;
    this.hdrType = (r.extensions.has('EXT_color_buffer_float') || r.extensions.has('EXT_color_buffer_half_float')) ? THREE.HalfFloatType : THREE.UnsignedByteType;
    this.resize();
  }

  get pixelScale() { return this._scale; }

  resize() {
    const dpr = Math.min(window.devicePixelRatio || 1, 2);
    const W = Math.floor(window.innerWidth * dpr), H = Math.floor(window.innerHeight * dpr);
    this.renderer.setSize(W, H, false);
    this.renderer.domElement.style.width = window.innerWidth + 'px';
    this.renderer.domElement.style.height = window.innerHeight + 'px';
    const scale = this.pixelScaleOverride || Math.max(1, Math.round(H / 300));
    this._scale = scale;
    const lw = Math.ceil(W / scale) + 2, lh = Math.ceil(H / scale) + 2;
    this.lowW = lw; this.lowH = lh;
    for (const rt of [this.rtColor, this.rtNormal]) rt?.dispose();
    this.rtColor = new THREE.WebGLRenderTarget(lw, lh, { minFilter: THREE.NearestFilter, magFilter: THREE.NearestFilter, depthBuffer: true, type: this.hdrType });
    for (const rt of [this.rtBloomA, this.rtBloomB]) rt?.dispose();
    const bw = Math.max(2, Math.ceil(lw / 2)), bh = Math.max(2, Math.ceil(lh / 2));
    const bo = { minFilter: THREE.LinearFilter, magFilter: THREE.LinearFilter, depthBuffer: false, type: this.hdrType };
    this.rtBloomA = new THREE.WebGLRenderTarget(bw, bh, bo);
    this.rtBloomB = new THREE.WebGLRenderTarget(bw, bh, bo);
    this.bloomTexel = new THREE.Vector2(1 / bw, 1 / bh);
    const depthTex = new THREE.DepthTexture(lw, lh);
    depthTex.type = THREE.UnsignedIntType;
    this.rtNormal = new THREE.WebGLRenderTarget(lw, lh, { minFilter: THREE.NearestFilter, magFilter: THREE.NearestFilter, depthBuffer: true, depthTexture: depthTex });
    const viewH = lh / this.ppu, viewW = lw / this.ppu;
    Object.assign(this.camera, { left: -viewW / 2, right: viewW / 2, top: viewH / 2, bottom: -viewH / 2 });
    this.camera.updateProjectionMatrix();
    this.texel = 1 / this.ppu;
    const u = this.compMat.uniforms;
    u.tColor.value = this.rtColor.texture; u.tNormal.value = this.rtNormal.texture; u.tDepth.value = depthTex;
    u.uLowRes.value.set(lw, lh); u.uOut.value.set(W, H); u.uScale.value = scale;
    u.tBloom.value = this.rtBloomA.texture;
    u.uNear.value = this.camera.near; u.uFar.value = this.camera.far; u.uDepthK.value = this.camera.far - this.camera.near;
    this.W = W; this.H = H;
  }

  /** posiciona a câmera presa ao grid de pixels, olhando para `target` */
  updateCamera(target) {
    const p = target.clone().addScaledVector(this.camDir, this.camDist);
    const t = this.texel;
    const px = p.dot(this.camRight) + this.shake.x * t, py = p.dot(this.camUp) + this.shake.y * t;
    const sx = Math.round(px / t) * t, sy = Math.round(py / t) * t;
    p.addScaledVector(this.camRight, sx - px + this.shake.x * t).addScaledVector(this.camUp, sy - py + this.shake.y * t);
    this.camera.position.copy(p);
    this.camera.updateMatrixWorld();
    this.compMat.uniforms.uInvViewProj.value.multiplyMatrices(this.camera.projectionMatrix, this.camera.matrixWorldInverse).invert();
    // shake é inteiro (em pixels) e não entra no deslocamento suave
    this.offset.set((px - sx) / t, (py - sy) / t);
    this.focus.copy(target);
  }

  /** projeta ponto do mundo para coordenadas CSS da janela */
  project(v, out = { x: 0, y: 0 }) {
    const p = v.clone().project(this.camera);
    const gx = (p.x * 0.5 + 0.5) * this.lowW - this.offset.x;
    const gy = (p.y * 0.5 + 0.5) * this.lowH - this.offset.y;
    const sx = (gx - 0.5 * this.lowW) * this._scale + 0.5 * this.W;
    const sy = (gy - 0.5 * this.lowH) * this._scale + 0.5 * this.H;
    const dpr = this.W / window.innerWidth;
    out.x = sx / dpr; out.y = (this.H - sy) / dpr;
    return out;
  }

  render(scene) {
    const r = this.renderer;
    this.compMat.uniforms.uOffset.value.copy(this.offset);
    this.compMat.uniforms.uOutlines.value = this.outlines ? 1 : 0;
    // 1) cor
    this.camera.layers.enable(1);
    shared.uNormalPass.value = 0;
    r.setRenderTarget(this.rtColor);
    r.render(scene, this.camera);
    // 2) normais + profundidade (sem camada 1)
    const bg = scene.background;
    scene.background = null;
    this.camera.layers.disable(1);
    shared.uNormalPass.value = 1;
    const sm = r.shadowMap.autoUpdate;
    r.shadowMap.autoUpdate = false;
    r.setClearColor(0x8080ff, 0);
    r.setRenderTarget(this.rtNormal);
    r.clear();
    r.render(scene, this.camera);
    r.shadowMap.autoUpdate = sm;
    shared.uNormalPass.value = 0;
    this.camera.layers.enable(1);
    scene.background = bg;
    r.setClearColor(0x000000, 1);
    // 3) bloom: brilho -> borrão separável (2 iterações)
    if (this.compMat.uniforms.uBloom.value > 0) {
      this.quad.material = this.brightMat;
      this.brightMat.uniforms.tColor.value = this.rtColor.texture;
      this.brightMat.uniforms.uTexel.value.set(1 / this.lowW, 1 / this.lowH);
      r.setRenderTarget(this.rtBloomA); r.render(this.quadScene, this.quadCam);
      this.quad.material = this.blurMat;
      for (let it = 0; it < 2; it++) {
        const k = it + 1;
        this.blurMat.uniforms.tSrc.value = this.rtBloomA.texture; this.blurMat.uniforms.uDir.value.set(this.bloomTexel.x * k, 0);
        r.setRenderTarget(this.rtBloomB); r.render(this.quadScene, this.quadCam);
        this.blurMat.uniforms.tSrc.value = this.rtBloomB.texture; this.blurMat.uniforms.uDir.value.set(0, this.bloomTexel.y * k);
        r.setRenderTarget(this.rtBloomA); r.render(this.quadScene, this.quadCam);
      }
      this.quad.material = this.compMat;
    }
    // 4) composição
    r.setRenderTarget(null);
    r.render(this.quadScene, this.quadCam);
  }
}
