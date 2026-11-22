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
uniform vec2 uLowRes;      // tamanho do alvo baixo (com borda)
uniform vec2 uOut;         // tamanho do canvas em px
uniform float uScale;      // px de tela por px do jogo
uniform vec2 uOffset;      // deslocamento subpixel (em px do jogo)
uniform float uNear, uFar;
uniform float uDepthK;     // profundidade -> unidades de mundo
uniform float uHitFlash;
uniform float uVignette;
uniform float uFade;
uniform vec3 uFadeColor;
uniform float uSat;
uniform vec3 uLift;
uniform vec3 uGain;
uniform float uOutlines;

float lin(vec2 uv) { return texture2D(tDepth, uv).r * uDepthK; }

float normalEdge(vec3 n, vec3 nn, float depthDiff) {
  vec3 bias = vec3(1.0, 1.0, 1.0);
  float normalDiff = dot(n - nn, bias);
  float ni = clamp(smoothstep(-0.01, 0.01, normalDiff), 0.0, 1.0);
  float di = clamp(sign(depthDiff * 0.25 + 0.0025), 0.0, 1.0);
  return (1.0 - dot(n, nn)) * di * ni;
}

void main() {
  // pixel do jogo correspondente a este pixel de tela
  vec2 fc = gl_FragCoord.xy;
  vec2 game = (fc - 0.5 * uOut) / uScale + 0.5 * uLowRes + uOffset;
  vec2 px = floor(game) + 0.5;
  vec2 texel = 1.0 / uLowRes;
  vec2 uv = px * texel;

  vec3 col = texture2D(tColor, uv).rgb;
  vec4 nc = texture2D(tNormal, uv);

  if (nc.a > 0.001 && uOutlines > 0.5) {
    vec3 n = normalize(nc.rgb * 2.0 - 1.0);
    float d = lin(uv);
    vec2 offs[4];
    offs[0] = vec2(0.0, texel.y); offs[1] = vec2(0.0, -texel.y); offs[2] = vec2(texel.x, 0.0); offs[3] = vec2(-texel.x, 0.0);
    float dEdge = 0.0;
    float nEdge = 0.0;
    for (int i = 0; i < 4; i++) {
      vec2 o = uv + offs[i];
      vec4 nn4 = texture2D(tNormal, o);
      float dn = nn4.a > 0.001 ? lin(o) : uFar * 2.0;
      dEdge += clamp((dn - d) - 0.45, 0.0, 1.0);
      if (nn4.a > 0.001) {
        vec3 nn = normalize(nn4.rgb * 2.0 - 1.0);
        nEdge += normalEdge(n, nn, dn - d);
      }
    }
    dEdge = dEdge > 0.0 ? 1.0 : 0.0;
    nEdge = smoothstep(0.18, 0.5, nEdge);
    float strength = nc.a;
    vec3 outline = col * vec3(0.32, 0.3, 0.42) * (1.0 - 0.0) ;
    if (dEdge > 0.0) col = mix(col, outline, strength);
    else col = mix(col, col * vec3(1.18, 1.15, 1.05) + vec3(0.05, 0.05, 0.03), nEdge * strength * 0.85);
  }

  // correção de cor (leve) — saturação, lift/gain
  float l = dot(col, vec3(0.3, 0.59, 0.11));
  col = mix(vec3(l), col, uSat);
  col = uLift + col * uGain;

  // vinheta em degraus (no grid de pixels do jogo)
  vec2 q = uv - 0.5;
  float v = dot(q * vec2(1.0, 1.25), q * vec2(1.0, 1.25));
  float vig = floor(smoothstep(0.12, 0.55, v) * 4.0) / 4.0;
  col *= 1.0 - vig * uVignette;

  col = mix(col, vec3(1.0, 0.95, 0.9), uHitFlash);
  col = mix(col, uFadeColor, uFade);
  gl_FragColor = vec4(col, 1.0);
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
        uSat: { value: 1.06 }, uLift: { value: new THREE.Color(0.02, 0.012, 0.04) }, uGain: { value: new THREE.Color(1.0, 0.985, 0.97) },
        uOutlines: { value: 1 },
      },
      depthTest: false, depthWrite: false,
    });
    this.quadScene.add(new THREE.Mesh(new THREE.PlaneGeometry(2, 2), this.compMat));
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
    this.rtColor = new THREE.WebGLRenderTarget(lw, lh, { minFilter: THREE.NearestFilter, magFilter: THREE.NearestFilter, depthBuffer: true });
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
    // 3) composição
    r.setRenderTarget(null);
    r.render(this.quadScene, this.quadCam);
  }
}
