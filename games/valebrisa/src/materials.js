import * as THREE from 'three';

// =============================================================================
// Materiais "pixel-toon".
//
// Toda a cena usa MeshLambertMaterial com o shader remendado (onBeforeCompile):
//  - a luz é calculada em branco e depois quantizada em 3 faixas (sombra / base / luz);
//  - a faixa "base" é exatamente a cor do hex escolhido (gestão de cor desligada),
//    então a paleta é controlada à mão, como em pixel art;
//  - sombras são frias (azul/lilás) e luzes quentes: hue shifting, não só escurecer;
//  - a fronteira entre faixas tem dither Bayer 4x4 de 1-2 px;
//  - sombras de nuvens passam pelo chão;
//  - no "passe de normais" o mesmo material escreve a normal (view space) + força do contorno,
//    que o pós-processamento usa para desenhar contornos e brilhos de aresta.
// =============================================================================

export const shared = {
  uTime: { value: 0 },
  uNormalPass: { value: 0 },
  uAmb: { value: 0.5 },
  uCloud: { value: 1 },
  uShadeMul: { value: new THREE.Color(0.56, 0.6, 0.86) },
  uShadeAdd: { value: new THREE.Color(0.035, 0.02, 0.07) },
  uHiMul: { value: new THREE.Color(1.1, 1.07, 0.94) },
  uHiAdd: { value: new THREE.Color(0.05, 0.04, 0.0) },
  uWind: { value: 1 },
};

export const GLSL_COMMON = /* glsl */ `
uniform float uTime;
uniform float uNormalPass;
uniform float uAmb;
uniform float uCloud;
uniform vec3 uShadeMul, uShadeAdd, uHiMul, uHiAdd;
varying vec3 vWPos;
varying vec3 vWNormal;

float vb_hash(vec2 p) { p = fract(p * vec2(123.34, 456.21)); p += dot(p, p + 45.32); return fract(p.x * p.y); }
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
vec3 vb_toon(vec3 albedo, vec3 direct, vec3 indirect, float lightMul) {
  float cloud = vb_cloud(vWPos.xz) * uCloud;
  vec3 light = indirect + direct * lightMul;
  float l = dot(light, vec3(0.3, 0.59, 0.11));
  float d = (vb_bayer(gl_FragCoord.xy) - 0.5) * 0.05;
  float t1 = uAmb + 0.2 + d;
  float t2 = uAmb + 0.8 + d;
  vec3 shade = albedo * uShadeMul + uShadeAdd;
  vec3 hi = albedo * uHiMul + uHiAdd;
  vec3 c = l < t1 ? shade : (l < t2 ? albedo : hi);
  // cor da luz (tochas/magia esquentam a superfície)
  vec3 chroma = light / max(l, 0.001);
  float extra = max(l - (uAmb + 1.05), 0.0);
  c = c * mix(vec3(1.0), chroma, 0.5) + albedo * chroma * min(extra, 1.5) * 0.35;
  // sombra de nuvem: escurece e esfria sem trocar de faixa
  c = mix(c, c * vec3(0.86, 0.88, 0.97), cloud * lightMul);
  return c;
}
`;

const VERT_HEAD = /* glsl */ `
uniform float uTime;
uniform float uWind;
varying vec3 vWPos;
varying vec3 vWNormal;
`;

/**
 * Cria um material toon.
 * opts: color, vertexColors, wind (amplitude), outline (0..1, força do contorno),
 *       flash (uniform compartilhado {value} para piscar branco), emissive (0..1 = não recebe sombra),
 *       albedoGLSL (trecho que define `albedo` a partir de vWPos/vWNormal), uniforms extras,
 *       side, flatNormals, normalUp (normais apontando pra cima: grama),
 *       defines.
 */
export function toonMat(opts = {}) {
  const m = new THREE.MeshLambertMaterial({
    color: opts.color ?? 0xffffff,
    vertexColors: !!opts.vertexColors,
    side: opts.side ?? THREE.FrontSide,
    flatShading: !!opts.flat,
    transparent: !!opts.transparent,
    opacity: opts.opacity ?? 1,
  });
  const uOutline = { value: opts.outline ?? 0.75 };
  const uFlash = opts.flash || { value: 0 };
  const uFlashColor = opts.flashColor || { value: new THREE.Color(1, 1, 1) };
  const uLightMul = { value: opts.emissive ? 0 : 1 };
  const uEmis = { value: opts.emissive ?? 0 };
  m.userData.uOutline = uOutline;
  m.userData.uFlash = uFlash;
  m.onBeforeCompile = (sh) => {
    Object.assign(sh.uniforms, shared, opts.uniforms || {}, { uOutline, uFlash, uFlashColor, uLightMul, uEmis, uWind: opts.windU || { value: opts.wind || 0 } });
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
        float gust = 0.6 + 0.4 * sin(uTime * 0.6 + vbRoot.x * 0.05);
        transformed.x += sin(uTime * 1.9 + ph) * hh * gust;
        transformed.z += cos(uTime * 1.4 + ph * 1.3) * hh * 0.6 * gust;
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
    sh.vertexShader = vs;

    let fs = sh.fragmentShader;
    fs = fs.replace('#include <common>', '#include <common>\n' + GLSL_COMMON + `
      uniform float uOutline; uniform float uFlash; uniform vec3 uFlashColor; uniform float uLightMul; uniform float uEmis;
      ` + (opts.fragHead || ''));
    if (opts.albedoGLSL) fs = fs.replace('#include <color_fragment>', '#include <color_fragment>\n{\n' + opts.albedoGLSL + '\n}');
    fs = fs.replace('#include <lights_lambert_fragment>', `LambertMaterial material;
      material.diffuseColor = vec3(1.0);
      material.specularStrength = 1.0;`);
    fs = fs.replace('#include <opaque_fragment>', `
      vec3 vbCol = vb_toon(diffuseColor.rgb, reflectedLight.directDiffuse * PI, reflectedLight.indirectDiffuse * PI, uLightMul);
      vbCol = mix(vbCol, diffuseColor.rgb, uEmis);
      vbCol = mix(vbCol, uFlashColor, uFlash);
      gl_FragColor = vec4(vbCol, diffuseColor.a);`);
    fs = fs.replace('#include <dithering_fragment>', `#include <dithering_fragment>
      if (uNormalPass > 0.5) gl_FragColor = vec4(normalize(normal) * 0.5 + 0.5, uOutline);`);
    sh.fragmentShader = fs;
  };
  m.customProgramCacheKey = () => 'vb|' + (opts.key || '') + '|' + !!opts.albedoGLSL + '|' + !!opts.normalUp + '|' + (opts.vertBody ? opts.key : '');
  return m;
}

// Materiais não iluminados (efeitos, janelas acesas, olhos). Também respondem ao passe de normais.
export function unlitMat(color, opts = {}) {
  const m = new THREE.MeshBasicMaterial({ color, transparent: !!opts.transparent, opacity: opts.opacity ?? 1, side: opts.side ?? THREE.FrontSide, depthWrite: opts.depthWrite ?? true, blending: opts.additive ? THREE.AdditiveBlending : THREE.NormalBlending, vertexColors: !!opts.vertexColors });
  const uOutline = { value: opts.outline ?? 0.0 };
  m.onBeforeCompile = (sh) => {
    sh.uniforms.uNormalPass = shared.uNormalPass;
    sh.uniforms.uOutline = uOutline;
    sh.fragmentShader = sh.fragmentShader.replace('#include <common>', '#include <common>\nuniform float uNormalPass; uniform float uOutline;')
      .replace('#include <dithering_fragment>', '#include <dithering_fragment>\nif (uNormalPass > 0.5) gl_FragColor = vec4(0.5, 0.5, 1.0, uOutline);');
  };
  m.customProgramCacheKey = () => 'vbu';
  return m;
}

// cache simples para reaproveitar materiais de mesma cor
const cache = new Map();
export function mat(color, opts = {}) {
  const k = color + '|' + JSON.stringify(opts);
  if (!cache.has(k)) cache.set(k, toonMat({ color, ...opts }));
  return cache.get(k);
}
