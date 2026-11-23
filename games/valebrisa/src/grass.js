import * as THREE from 'three';
import { toonMat } from './materials.js';
import { toWorld, TERRAIN_HEAD, riverV, WATER_Y } from './world.js';
import { mulberry32, vnoise } from './noise.js';
import { getAtlas, cardQuad, cellUV } from './texgen.js';

// =============================================================================
// Grama em sprites de pixel art (técnica "t3ssel8r"): cada tufo é um cartão 16x16 virado para
// a câmera em escala 1:1 com o pixel do jogo. A cor vem do terreno na raiz (a grama "é" o
// chão), a luz/sombra é a do chão (normal para cima), as rajadas de vento passam em ondas
// clareando as pontas e o tufo se dobra quando o herói passa. Flores, trevos, juncos e
// samambaias saem do mesmo atlas. Camada 1: sem contorno e sem projetar sombra.
// =============================================================================

export function buildGrass(world, scene, exclude, pr, zones = []) {
  const rng = mulberry32(77);
  const atlas = getAtlas();
  const size = 16 / pr.ppu;
  const geo = cardQuad(size, pr.camRight, pr.camUp, 0, 0);
  const mat = toonMat({
    key: 'grass2', wind: 0.24, normalUp: true, side: THREE.DoubleSide, uniforms: world.textures(), map: atlas, alphaTest: 0.5, outline: 0,
    vertHead: 'attribute vec2 aUvOff; varying vec3 vRoot;',
    vertUV: 'vMapUv += aUvOff;',
    vertBody: `vRoot = vbRoot.xyz;
      vec2 dp = vbRoot.xz - uPlayer.xz; float dl = length(dp);
      float push = (1.0 - smoothstep(0.15, 1.05, dl)) * max(position.y, 0.0);
      transformed.xz += (dp / max(dl, 0.001)) * push * 0.6;
      transformed.y -= push * 0.4;`,
    fragHead: TERRAIN_HEAD + '\nvarying vec3 vRoot;',
    albedoGLSL: `vec4 tx = sampledDiffuseColor;
      float dith = (vb_bayer(gl_FragCoord.xy) - 0.5) * 0.07;
      vec3 c;
      if (tx.a > 0.9) {
        vec3 g = grassAlbedo(vRoot, mapMask(vRoot), dith);
        c = g * tx.r * 1.16;
        float gust = vb_gust(vRoot.xz);
        if (tx.r > 0.9) c = mix(c, c * vec3(1.12, 1.14, 1.0) + 0.03, gust);
      } else if (tx.a > 0.74) c = vColor.rgb * (0.75 + tx.r * 0.3);
      else c = tx.rgb;
      diffuseColor = vec4(c, tx.a);`,
  });
  const CH = 10, chunks = new Map();
  const step = 0.3;
  const flowerCols = ['#f6f1e0', '#f4d35e', '#ef8fa8', '#9db7f0', '#f29e4c', '#e85d75', '#c9a3f0'].map((c) => new THREE.Color(c));
  const zoneAt = (u, v) => zones.find((z) => (u - z.c[0]) ** 2 + (v - z.c[1]) ** 2 < z.r * z.r);
  for (let v = -55; v < 55; v += step) {
    for (let u = -45; u < 45; u += step) {
      const uu = u + (rng() - 0.5) * step, vv = v + (rng() - 0.5) * step;
      const mk = world.maskAt(uu, vv);
      const edgeNoise = vnoise(uu * 2.1, vv * 2.1) * 0.25;
      if (mk.path > 0.22 + edgeNoise || mk.sand > 0.3 || mk.plaza > 0.2) continue;
      if (world.slopeAt(uu, vv) > 0.4) continue;
      const w = toWorld(uu, vv);
      const h = world.heightAt(w.x, w.z);
      if (h < WATER_Y + 0.12) continue;
      if (exclude && exclude(w.x, w.z)) continue;
      // tufos rareiam perto da trilha; manchas de gramado baixo mostram o chão
      if (mk.path > 0.1 && rng() < 0.5) continue;
      const dens = vnoise(uu * 0.16 + 4, vv * 0.16 - 2) * 0.7 + vnoise(uu * 0.5, vv * 0.5) * 0.3;
      if (dens < 0.42 && rng() < 0.75) continue;
      if (!world.walkableUV(uu, vv) && rng() < 0.45) continue;
      const key = Math.floor(uu / CH) + ',' + Math.floor(vv / CH);
      if (!chunks.has(key)) chunks.set(key, []);
      let col = 0, color = flowerCols[0];
      const r = rng();
      const z = zoneAt(uu, vv);
      if (z && r < 0.16) { col = rng() < 0.6 ? 4 : 6; color = flowerCols[z.colors[Math.floor(rng() * z.colors.length)]]; }
      else if (r < 0.03) { col = 5; color = flowerCols[0]; }
      else if (r < 0.08 && mk.dark < 0.4) col = 7;
      else col = mk.dark > 0.5 ? (rng() < 0.6 ? 1 : 3) : Math.floor(rng() * 4);
      chunks.get(key).push([w.x, h - 0.02, w.z, col, color]);
    }
  }
  let total = 0;
  const m4 = new THREE.Matrix4();
  for (const list of chunks.values()) {
    const g = geo.clone();
    const uvOff = new Float32Array(list.length * 2);
    list.forEach(([, , , col], i) => { const [u0, v0] = cellUV(col, 0); uvOff[i * 2] = u0; uvOff[i * 2 + 1] = v0; });
    g.setAttribute('aUvOff', new THREE.InstancedBufferAttribute(uvOff, 2));
    const im = new THREE.InstancedMesh(g, mat, list.length);
    list.forEach(([x, y, z, , c], i) => { m4.makeTranslation(x, y, z); im.setMatrixAt(i, m4); im.setColorAt(i, c); });
    im.computeBoundingSphere();
    im.layers.set(1);
    im.receiveShadow = true;
    scene.add(im);
    total += list.length;
  }
  buildReedsAndFerns(world, scene, exclude, pr);
  return total;
}

// juncos na beira d'água e samambaias no bosque
function buildReedsAndFerns(world, scene, exclude, pr) {
  const rng = mulberry32(91);
  const atlas = getAtlas();
  const size = 16 / pr.ppu;
  const geo = cardQuad(size, pr.camRight, pr.camUp, 0, 0);
  const mat = toonMat({
    key: 'reeds', wind: 0.3, normalUp: true, side: THREE.DoubleSide, map: atlas, alphaTest: 0.5, outline: 0,
    vertHead: 'attribute vec2 aUvOff;', vertUV: 'vMapUv += aUvOff;', vertBody: ' ',
    albedoGLSL: `vec4 tx = sampledDiffuseColor;
      diffuseColor = vec4(tx.a > 0.74 ? vColor.rgb * tx.r * 1.15 : tx.rgb, tx.a);`,
  });
  const items = [];
  // juncos: ao longo do rio e do lago
  for (let u = -30; u < 30; u += 0.35) {
    for (const side of [-1, 1]) {
      if (rng() < 0.35) continue;
      const vv = riverV(u) + side * (1.35 + rng() * 1.1);
      const w = toWorld(u + (rng() - 0.5) * 0.3, vv);
      const h = world.heightAt(w.x, w.z);
      if (h < WATER_Y - 0.15 || h > 0.35 || world.slopeAt(u, vv) > 0.5) continue;
      if (world.inBridge(u, vv)) continue;
      items.push([w.x, h - 0.03, w.z, Math.floor(rng() * 4), new THREE.Color(rng() < 0.5 ? '#6f9a4a' : '#7fa957')]);
    }
  }
  for (let i = 0; i < 160; i++) {
    const a = rng() * Math.PI * 2, r = 2.8 + rng() * 1.6;
    const u = -26.5 + Math.cos(a) * r * 1.2, v = 5.5 + Math.sin(a) * r * 0.9;
    const w = toWorld(u, v), h = world.heightAt(w.x, w.z);
    if (h < WATER_Y - 0.12 || h > 0.4) continue;
    items.push([w.x, h - 0.03, w.z, Math.floor(rng() * 4), new THREE.Color('#6f9a4a')]);
  }
  // samambaias: no bosque e nas bordas escuras
  for (let i = 0; i < 1600; i++) {
    const u = -36 + rng() * 72, v = -46 + rng() * 88;
    const mk = world.maskAt(u, v);
    if (mk.dark < 0.45 || mk.path > 0.2 || world.slopeAt(u, v) > 0.35) continue;
    const w = toWorld(u, v);
    if (exclude && exclude(w.x, w.z)) continue;
    items.push([w.x, world.heightAt(w.x, w.z) - 0.03, w.z, 4 + Math.floor(rng() * 4), new THREE.Color(rng() < 0.5 ? '#4f8a4f' : '#5f9a52')]);
  }
  const g = geo.clone();
  const uvOff = new Float32Array(items.length * 2);
  items.forEach(([, , , col], i) => { const [u0, v0] = cellUV(col, 3); uvOff[i * 2] = u0; uvOff[i * 2 + 1] = v0; });
  g.setAttribute('aUvOff', new THREE.InstancedBufferAttribute(uvOff, 2));
  const im = new THREE.InstancedMesh(g, mat, items.length);
  const m4 = new THREE.Matrix4();
  items.forEach(([x, y, z, , c], i) => { m4.makeTranslation(x, y, z); im.setMatrixAt(i, m4); im.setColorAt(i, c); });
  im.computeBoundingSphere();
  im.layers.set(1);
  im.receiveShadow = true;
  scene.add(im);
}

export function buildFlowers() { return 0; }
