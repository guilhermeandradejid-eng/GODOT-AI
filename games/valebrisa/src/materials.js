import * as THREE from 'three';
import { TOON } from './style.js';

// =============================================================================
// Materiais "pixel-toon" com iluminação própria.
//
// Toda a cena usa MeshLambertMaterial com o shader remendado (onBeforeCompile), mas a luz
// é calculada à mão:
//  - SOL/LUA: N·L × sombra (shadow map do three) × sombra de nuvem → 3 faixas com dither Bayer;
//    sombra = cor × céu (frio, de cima) / rebatida (quente, de baixo); luz = cor × cor do sol;
//    destaque = luz mais quente. As cores mudam com a hora do dia (lighting.js).
//  - LUZES PONTUAIS (até 12: lampiões, fogueira, magia, impactos): atenuação em degraus
//    (anéis de luz como em pixel art), coloridas, somadas por cima.
//  - RIM LIGHT nos personagens, padrões procedurais de textura (madeira, reboco, pedra,
//    telha, casca, rocha com musgo) e vento com rajadas.
//  - No "passe de normais" o mesmo material escreve normal (view space) + força do contorno.
// =============================================================================

export const MAXL = 12;
export const shared = {
  uTime: { value: 0 },
  uStyle: { value: TOON ? 1 : 0 },
  uNormalPass: { value: 0 },
  uCloud: { value: 1 },
  uSunColor: { value: new THREE.Color(0.9, 0.88, 0.82) },
  uSkyColor: { value: new THREE.Color(0.56, 0.6, 0.86) },
  uBounceColor: { value: new THREE.Color(0.62, 0.55, 0.62) },
  uHiColor: { value: new THREE.Color(1.1, 1.04, 0.9) },
  uRimColor: { value: new THREE.Color(0.9, 0.85, 1.0) },
  uEmisBoost: { value: 1.2 },
  uWindDir: { value: new THREE.Vector2(0.8, -0.6) },
  uPlayer: { value: new THREE.Vector3(9999, 0, 9999) },
  uPL: { value: Array.from({ length: MAXL }, () => new THREE.Vector4(0, -999, 0, 1)) },
  uPLC: { value: Array.from({ length: MAXL }, () => new THREE.Vector4(0, 0, 0, 0)) },
  uPLN: { value: 0 },
};

export const GLSL_COMMON = /* glsl */ `
uniform float uTime;
uniform float uStyle;
uniform float uNormalPass;
uniform float uCloud;
uniform vec3 uSunColor, uSkyColor, uBounceColor, uHiColor, uRimColor;
uniform float uEmisBoost;
uniform vec2 uWindDir;
uniform vec4 uPL[${MAXL}];
uniform vec4 uPLC[${MAXL}];
uniform int uPLN;
varying vec3 vWPos;
varying vec3 vWNormal;

float vb_hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vb_hash2(vec2 p) { return fract(sin(dot(p, vec2(12.9898, 78.233))) * 43758.5453); }
float vb_noise(vec2 p) {
  vec2 i = floor(p), f = fract(p);
  vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(vb_hash(i), vb_hash(i + vec2(1, 0)), u.x), mix(vb_hash(i + vec2(0, 1)), vb_hash(i + vec2(1, 1)), u.x), u.y);
}
float vb_fbm(vec2 p) { return vb_noise(p) * 0.55 + vb_noise(p * 2.03 + 7.1) * 0.3 + vb_noise(p * 4.1 + 3.7) * 0.15; }
float vb_bayer(vec2 fc) {
  ivec2 p = ivec2(mod(fc, 4.0));
  int i = p.x + p.y * 4;
  int m[16] = int[16](0, 8, 2, 10, 12, 4, 14, 6, 3, 11, 1, 9, 15, 7, 13, 5);
  return (float(m[i]) + 0.5) / 16.0;
}
float vb_cloud(vec2 xz) {
  float n = vb_fbm(xz * 0.045 + vec2(uTime * 0.018, uTime * 0.007));
  return smoothstep(0.6, 0.63, n);
}
float vb_gust(vec2 xz) {
  float w = sin(dot(xz, uWindDir) * 0.25 - uTime * 1.6 + vb_noise(xz * 0.06) * 5.0);
  return smoothstep(0.55, 1.0, w * 0.5 + 0.5);
}

/** luzes pontuais em degraus */
vec3 vb_points(vec3 albedo, vec3 wp, vec3 wn) {
  vec3 acc = vec3(0.0);
  float dth = vb_bayer(gl_FragCoord.xy);
  for (int i = 0; i < ${MAXL}; i++) {
    if (i >= uPLN) break;
    vec4 P = uPL[i]; vec4 C = uPLC[i];
    vec3 L = P.xyz - wp;
    float dist = length(L);
    float a = clamp(1.0 - dist / P.w, 0.0, 1.0);
    a *= a;
    float facing = clamp(dot(wn, L / max(dist, 0.001)) * 0.6 + 0.55, 0.0, 1.0);
    a = uStyle > 0.5 ? a * facing : floor(a * facing * 4.0 + 0.5 + (dth - 0.5) * 0.35) / 4.0;
    acc += C.rgb * C.a * a;
  }
  return albedo * acc;
}

/** sombreamento principal: sun = N·L×sombra (0..1) */
vec3 vb_toon(vec3 albedo, float sun, vec3 wn, vec3 nView, float rim, float cel) {
  float cloud = vb_cloud(vWPos.xz) * uCloud;
  sun *= 1.0 - cloud * 0.55;
  float d = (vb_bayer(gl_FragCoord.xy) - 0.5) * 0.1;
  vec3 amb = mix(uBounceColor, uSkyColor, clamp(wn.y * 0.5 + 0.5, 0.0, 1.0));
  vec3 shade = albedo * amb;
  vec3 lit = albedo * (uSunColor + amb * 0.22);
  vec3 hi = albedo * (uSunColor * uHiColor + amb * 0.22);
  float b = sun + d;
  vec3 c = b < 0.16 ? shade : (b < 0.66 ? lit : hi);
  // cel anime: 2 tons com corte seco (sem dither) e sombra um pouco mais saturada
  if (cel > 0.5 || uStyle > 0.5) {
    // toon de desenho animado: 2 tons com borda limpa (antialias no corte), sombra fria e saturada
    float e = uStyle > 0.5 ? smoothstep(0.17, 0.25, sun) : step(0.3, sun);
    vec3 sh = albedo * mix(amb, amb * vec3(0.9, 0.86, 1.1), 0.6);
    vec3 lt = albedo * (uSunColor + amb * 0.22);
    c = mix(sh, lt, e);
  }
  // contorno de luz (rim) em degrau
  float fr = 1.0 - clamp(nView.z, 0.0, 1.0);
  c += albedo * uRimColor * (uStyle > 0.5 ? smoothstep(0.6, 0.72, fr) * 0.35 : step(0.62, fr + d) * 0.45) * rim;
  c += vb_points(albedo, vWPos, wn);
  return c;
}

// --------------------------------------------------------------- padrões de textura
vec2 vb_faceUV(vec3 wp, vec3 wn) {
  vec3 an = abs(wn);
  return an.y > max(an.x, an.z) ? wp.xz : (an.x > an.z ? vec2(wp.z, wp.y) : vec2(wp.x, wp.y));
}
vec3 vb_pattern(float kind, vec3 c, vec3 wp, vec3 wn) {
  vec2 uv = vb_faceUV(wp, wn);
  vec3 an = abs(wn);
  bool top = an.y > max(an.x, an.z);
  if (kind < 1.5) { // madeira: tábuas + veios + nós
    float rows = 5.5;
    float r = floor(uv.y * rows);
    float f = fract(uv.y * rows);
    c *= 0.94 + vb_hash2(vec2(r, 3.1)) * 0.12;
    float grain = vb_noise(vec2(uv.x * 2.2 + r * 7.0, uv.y * 26.0));
    if (grain > 0.7) c *= 0.88;
    if (f < 0.13) c *= 0.72;
    else if (f > 0.87) c *= 1.08;
    if (vb_hash2(floor(vec2(uv.x * 3.0, r))) > 0.94 && abs(fract(uv.x * 3.0) - 0.5) < 0.12 && abs(f - 0.5) < 0.2) c *= 0.7;
  } else if (kind < 2.5) { // reboco: manchinhas e salpicos, sujeira embaixo
    float n = vb_fbm(uv * 1.6);
    c *= 0.95 + n * 0.08;
    float sp = vb_hash2(floor(uv * 16.0));
    if (sp > 0.93) c *= 0.9; else if (sp < 0.03) c *= 1.05;
    float h = fract(wp.y + 0.62);
    if (h < 0.22 && vb_noise(uv * 4.0) > 0.4) c *= 0.9;
  } else if (kind < 3.5) { // pedra: blocos com chanfro
    float rh = 0.3, bw = 0.5;
    float row = floor(uv.y / rh);
    vec2 q = vec2(uv.x / bw + mod(row, 2.0) * 0.5, uv.y / rh);
    vec2 id = floor(q), f = fract(q);
    c *= 0.9 + vb_hash2(id) * 0.18;
    if (f.y > 0.82 || f.x < 0.06) c *= 1.1;
    if (f.y < 0.16 || f.x > 0.93) c *= 0.7;
    if (top) { vec2 t = fract(wp.xz * 2.4); if (t.x < 0.08 || t.y < 0.08) c *= 0.75; }
  } else if (kind < 4.5) { // telhas: fileiras com escamas
    float along = abs(wn.x) > abs(wn.z) ? wp.z : wp.x;
    float h = wp.y * 5.0;
    float r = floor(h);
    float f = fract(h);
    float tile = floor(along * 4.0 + r * 0.5);
    c *= 0.93 + vb_hash2(vec2(tile, r)) * 0.13;
    float sc = abs(fract(along * 4.0 + r * 0.5) - 0.5);
    if (f < 0.16 + sc * 0.3) c *= 0.74;
    else if (f > 0.86) c *= 1.1;
  } else if (kind < 5.5) { // casca: sulcos verticais
    float a = (wp.x - wp.z) * 5.0;
    float g = vb_noise(vec2(a, wp.y * 1.3));
    if (g > 0.62) c *= 0.75; else if (g < 0.2) c *= 1.1;
    if (vb_hash2(floor(vec2(a, wp.y * 6.0))) > 0.95) c *= 0.8;
  } else if (kind < 6.5) { // rocha: rachaduras + musgo no topo
    float n = vb_noise(wp.xz * 3.0 + wp.y * 2.0);
    float cr = abs(vb_noise(uv * 2.5) - 0.5);
    if (cr < 0.035) c *= 0.68;
    c *= 0.93 + n * 0.12;
    if (wn.y > 0.5 && vb_noise(wp.xz * 2.2 + 3.0) > 0.42) c = mix(c, vec3(0.43, 0.62, 0.3), 0.85);
    if (vb_hash2(floor(uv * 10.0)) > 0.94) c *= 1.12;
  }
  return c;
}
`;

const VERT_HEAD = /* glsl */ `
uniform float uTime;
uniform float uWind;
uniform vec2 uWindDir;
uniform vec3 uPlayer;
varying vec3 vWPos;
varying vec3 vWNormal;
float vbv_hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
float vbv_noise(vec2 p) {
  vec2 i = floor(p), f = fract(p); vec2 u = f * f * (3.0 - 2.0 * f);
  return mix(mix(vbv_hash(i), vbv_hash(i + vec2(1, 0)), u.x), mix(vbv_hash(i + vec2(0, 1)), vbv_hash(i + vec2(1, 1)), u.x), u.y);
}
float vbv_gust(vec2 xz) {
  float w = sin(dot(xz, uWindDir) * 0.25 - uTime * 1.6 + vbv_noise(xz * 0.06) * 5.0);
  return smoothstep(0.55, 1.0, w * 0.5 + 0.5);
}
`;

/**
 * Cria um material toon.
 * opts: color, vertexColors, wind, outline (0..1), flash ({value}), emissive (0..1),
 *       albedoGLSL, fragHead, vertHead, vertBody, vertUV, uniforms, side, flat, normalUp, key,
 *       pattern (1 madeira · 2 reboco · 3 pedra · 4 telha · 5 casca · 6 rocha), rim, map, alphaTest
 */
export function toonMat(opts = {}) {
  const m = new THREE.MeshLambertMaterial({
    color: opts.color ?? 0xffffff,
    vertexColors: !!opts.vertexColors,
    side: opts.side ?? THREE.FrontSide,
    flatShading: !!opts.flat,
    transparent: !!opts.transparent,
    opacity: opts.opacity ?? 1,
    map: opts.map || null,
    alphaTest: opts.alphaTest ?? 0,
  });
  const uOutline = { value: opts.outline ?? 0.75 };
  const uFlash = opts.flash || { value: 0 };
  const uFlashColor = opts.flashColor || { value: new THREE.Color(1, 1, 1) };
  const uEmis = { value: opts.emissive ?? 0 };
  const uPattern = { value: opts.pattern ?? 0 };
  const uRim = { value: opts.rim ?? 0 };
  const uCel = { value: opts.cel ? 1 : 0 };
  m.userData.uOutline = uOutline;
  m.userData.uFlash = uFlash;
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, shared, opts.uniforms || {}, { uOutline, uFlash, uFlashColor, uEmis, uPattern, uRim, uCel, uWind: opts.windU || { value: opts.wind || 0 } });
    let vs = sh.vertexShader;
    vs = vs.replace('#include <common>', '#include <common>\n' + VERT_HEAD + (opts.vertHead || ''));
    vs = vs.replace('#include <begin_vertex>', `#include <begin_vertex>
      vec4 vbRoot = vec4(0.0, 0.0, 0.0, 1.0);
      #ifdef USE_INSTANCING
        vbRoot = instanceMatrix * vbRoot;
      #endif
      vbRoot = modelMatrix * vbRoot;
      if (uWind > 0.0) {
        float hh = max(position.y, 0.0) * uWind;
        float ph = vbRoot.x * 0.37 + vbRoot.z * 0.23;
        float gust = 0.5 + vbv_gust(vbRoot.xz) * 1.1;
        float sw = sin(uTime * 1.9 + ph) * 0.45 + 0.55;
        transformed.x += sw * hh * gust * uWindDir.x;
        transformed.z += sw * hh * gust * uWindDir.y;
        transformed.y -= hh * gust * 0.12;
      }
      ${opts.vertBody || ''}`);
    if (opts.normalUp) vs = vs.replace('#include <beginnormal_vertex>', 'vec3 objectNormal = vec3(0.0, 1.0, 0.0);\n#ifdef USE_TANGENT\nvec3 objectTangent = vec3(1.0,0.0,0.0);\n#endif');
    vs = vs.replace('#include <worldpos_vertex>', `#include <worldpos_vertex>
      {
        vec4 wp = vec4(transformed, 1.0);
        #ifdef USE_INSTANCING
          wp = instanceMatrix * wp;
        #endif
        vWPos = (modelMatrix * wp).xyz;
        vWNormal = normalize(mat3(modelMatrix) * objectNormal);
      }`);
    if (opts.vertUV) vs = vs.replace('#include <uv_vertex>', '#include <uv_vertex>\n' + opts.vertUV);
    sh.vertexShader = vs;

    let fs = sh.fragmentShader;
    fs = fs.replace('#include <common>', '#include <common>\n' + GLSL_COMMON + `
      uniform float uOutline; uniform float uFlash; uniform vec3 uFlashColor; uniform float uEmis; uniform float uPattern; uniform float uRim; uniform float uCel;
      ` + (opts.fragHead || ''));
    let albedo = '';
    if (opts.albedoGLSL) albedo += opts.albedoGLSL + '\n';
    albedo += 'if (uPattern > 0.5) diffuseColor.rgb = vb_pattern(uPattern, diffuseColor.rgb, vWPos, normalize(vWNormal));';
    fs = fs.replace('#include <color_fragment>', '#include <color_fragment>\n{\n' + albedo + '\n}');
    fs = fs.replace('#include <lights_lambert_fragment>', '');
    fs = fs.replace('#include <lights_fragment_begin>', `
      float vbSun = 0.0;
      #if NUM_DIR_LIGHTS > 0
      {
        float ndl = dot(normal, directionalLights[0].direction);
        float shd = 1.0;
        #if defined(USE_SHADOWMAP) && NUM_DIR_LIGHT_SHADOWS > 0
          DirectionalLightShadow dls = directionalLightShadows[0];
          shd = receiveShadow ? getShadow(directionalShadowMap[0], dls.shadowMapSize, dls.shadowIntensity, dls.shadowBias, dls.shadowRadius, vDirectionalShadowCoord[0]) : 1.0;
        #endif
        vbSun = clamp(ndl * 1.5, 0.0, 1.0) * shd;
      }
      #endif`);
    fs = fs.replace('#include <lights_fragment_maps>', '');
    fs = fs.replace('#include <lights_fragment_end>', '');
    fs = fs.replace('#include <aomap_fragment>', '');
    fs = fs.replace('#include <opaque_fragment>', `
      vec3 vbCol = vb_toon(diffuseColor.rgb, vbSun, normalize(vWNormal), normal, uRim, uCel);
      vbCol = mix(vbCol, diffuseColor.rgb * uEmisBoost, uEmis);
      vbCol = mix(vbCol, uFlashColor, uFlash);
      gl_FragColor = vec4(vbCol, diffuseColor.a);`);
    fs = fs.replace('#include <dithering_fragment>', `#include <dithering_fragment>
      if (uNormalPass > 0.5) gl_FragColor = vec4(normalize(normal) * 0.5 + 0.5, uOutline);`);
    sh.fragmentShader = fs;
  };
  m.customProgramCacheKey = () => 'vb2|' + (opts.key || '') + '|' + !!opts.albedoGLSL + '|' + !!opts.normalUp + '|' + (opts.vertBody || opts.vertUV ? opts.key : '');
  return m;
}

// Materiais não iluminados (janelas, lanternas, olhos, efeitos). `glow` multiplica pelo brilho
// da hora do dia (vira bloom à noite).
export function unlitMat(color, opts = {}) {
  const m = new THREE.MeshBasicMaterial({ color, transparent: !!opts.transparent, opacity: opts.opacity ?? 1, side: opts.side ?? THREE.FrontSide, depthWrite: opts.depthWrite ?? true, blending: opts.additive ? THREE.AdditiveBlending : THREE.NormalBlending, vertexColors: !!opts.vertexColors });
  const uOutline = { value: opts.outline ?? 0.0 };
  const uGlow = { value: opts.glow ?? 0 };
  m.onBeforeCompile = (sh) => {
    sh.uniforms.uNormalPass = shared.uNormalPass;
    sh.uniforms.uOutline = uOutline;
    sh.uniforms.uEmisBoost = shared.uEmisBoost;
    sh.uniforms.uGlow = uGlow;
    sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nuniform float uNormalPass; uniform float uOutline; uniform float uEmisBoost; uniform float uGlow;')
      .replace('#include <opaque_fragment>', '#include <opaque_fragment>\ngl_FragColor.rgb *= mix(1.0, uEmisBoost, uGlow);')
      .replace('#include <dithering_fragment>', '#include <dithering_fragment>\nif (uNormalPass > 0.5) gl_FragColor = vec4(0.5, 0.5, 1.0, uOutline);');
  };
  m.customProgramCacheKey = () => 'vbu2';
  return m;
}

// cores → padrão de textura (aplicado automaticamente pelo mat())
const PATTERNS = new Map();
export function setPattern(hexes, kind) { for (const h of hexes) PATTERNS.set(String(h).toLowerCase(), kind); }

const cache = new Map();
export function mat(color, opts = {}) {
  const pat = opts.pattern ?? PATTERNS.get(String(color).toLowerCase()) ?? 0;
  const k = color + '|' + JSON.stringify(opts) + '|' + pat;
  if (!cache.has(k)) cache.set(k, toonMat({ color, ...opts, pattern: pat }));
  return cache.get(k);
}
