import * as THREE from 'three';

// Direção de arte: sombreamento "toon" em degraus + contorno preto (inverted hull).

function makeGradient(steps) {
  const data = new Uint8Array(steps.length * 4);
  steps.forEach((v, i) => { data.set([v, v, v, 255], i * 4); });
  const t = new THREE.DataTexture(data, steps.length, 1, THREE.RGBAFormat);
  t.minFilter = t.magFilter = THREE.NearestFilter;
  t.generateMipmaps = false;
  t.needsUpdate = true;
  return t;
}
// 3 tons: sombra, meio-tom, luz
export const GRADIENT = makeGradient([115, 190, 255]);

const TOON_KEYS = new Set(['color', 'map', 'emissive', 'emissiveMap', 'emissiveIntensity', 'transparent', 'opacity', 'side', 'alphaTest', 'depthWrite', 'vertexColors', 'fog', 'aoMap', 'normalMap', 'toneMapped']);

export function toonMat(params = {}) {
  const p = { gradientMap: GRADIENT };
  for (const [k, v] of Object.entries(params)) if (TOON_KEYS.has(k)) p[k] = v;
  return new THREE.MeshToonMaterial(p);
}

// ------------------------------------------------------------------ contorno
const outlineMats = new Map();
export function outlineMat(thickness = 0.022, color = 0x1d2540) {
  const key = thickness + '|' + color;
  if (!outlineMats.has(key)) {
    outlineMats.set(key, new THREE.ShaderMaterial({
      uniforms: { thickness: { value: thickness }, color: { value: new THREE.Color(color) } },
      vertexShader: `uniform float thickness;
        void main() {
          // empurra ao longo da normal no espaço do objeto, compensando a escala do objeto
          vec3 n = normalize(normal);
          float s = length(modelMatrix[0].xyz);
          vec3 p = position + n * (thickness / max(s, 0.0001));
          gl_Position = projectionMatrix * modelViewMatrix * vec4(p, 1.0);
        }`,
      fragmentShader: 'uniform vec3 color; void main() { gl_FragColor = vec4(color, 1.0); }',
      side: THREE.BackSide,
    }));
  }
  return outlineMats.get(key);
}

/** adiciona contorno a todas as malhas de `obj` (ignora as marcadas com userData.noOutline) */
export function addOutline(obj, thickness = 0.022, color = 0x1d2540) {
  const list = [];
  obj.traverse((o) => { if (o.isMesh && !o.userData.isOutline && !o.userData.noOutline && !(o.material?.transparent)) list.push(o); });
  for (const o of list) {
    const m = new THREE.Mesh(o.geometry, outlineMat(thickness, color));
    m.userData.isOutline = true;
    m.castShadow = false; m.receiveShadow = false;
    m.raycast = () => {};
    o.add(m);
    // acompanha visibilidade do original (o filho já herda)
  }
  return obj;
}
