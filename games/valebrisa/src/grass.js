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

// =============================================================================
// Estilo toon (desenho animado): tufos sólidos de folhas largas, cor do terreno na raiz,
// pontas mais claras, rajadas de vento, dobra ao passar; flores redondas de pétalas.
// =============================================================================
function toonTuft() {
  const pos = [], hts = [];
  const blades = [[0, 0, 0.42, 0.0, 0.07], [0.08, 0.05, 0.34, 1.3, 0.065], [-0.07, 0.06, 0.32, 2.5, 0.065], [0.04, -0.08, 0.3, 3.8, 0.06], [-0.05, -0.05, 0.36, 5.0, 0.06]];
  for (const [ox, oz, h, a, w] of blades) {
    const lx = Math.cos(a) * 0.12, lz = Math.sin(a) * 0.12;
    const px = -Math.sin(a) * w, pz = Math.cos(a) * w;
    const mx = ox + lx * 0.45, mz = oz + lz * 0.45;
    // lâmina em 2 segmentos (curva) — base, meio, ponta
    const v = [[ox - px, 0, oz - pz], [ox + px, 0, oz + pz], [mx + px * 0.7, h * 0.55, mz + pz * 0.7], [mx - px * 0.7, h * 0.55, mz - pz * 0.7], [ox + lx, h, oz + lz]];
    const tri = (a1, b1, c1) => { for (const i of [a1, b1, c1]) { pos.push(...v[i]); hts.push(v[i][1] / 0.42); } };
    tri(0, 1, 2); tri(0, 2, 3); tri(3, 2, 4);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(new Array(pos.length).fill(0).map((_, i) => (i % 3 === 1 ? 1 : 0)), 3));
  g.setAttribute('aTip', new THREE.Float32BufferAttribute(hts, 1));
  return g;
}
function flowerGeo() {
  const parts = [];
  const stem = new THREE.CylinderGeometry(0.012, 0.015, 0.32, 4).translate(0, 0.16, 0);
  const head = new THREE.CylinderGeometry(0.075, 0.06, 0.03, 6).translate(0, 0.33, 0);
  const ctr = new THREE.SphereGeometry(0.03, 6, 4).translate(0, 0.35, 0);
  for (const [g, t] of [[stem, 0], [head, 1], [ctr, 2]]) { const n = g.toNonIndexed(); n.setAttribute('aPart', new THREE.Float32BufferAttribute(new Array(n.attributes.position.count).fill(t), 1)); n.deleteAttribute('uv'); parts.push(n); }
  const out = new THREE.BufferGeometry();
  for (const k of ['position', 'normal', 'aPart']) {
    const arrs = parts.map((p) => p.attributes[k].array);
    const len = arrs.reduce((a, b) => a + b.length, 0), m = new Float32Array(len);
    let o = 0; for (const a of arrs) { m.set(a, o); o += a.length; }
    out.setAttribute(k, new THREE.BufferAttribute(m, k === 'aPart' ? 1 : 3));
  }
  return out;
}

export function buildToonGrass(world, scene, exclude, zones = []) {
  const rng = mulberry32(78);
  const geo = toonTuft();
  const mat = toonMat({
    key: 'toongrass', wind: 0.3, normalUp: true, side: THREE.DoubleSide, uniforms: world.textures(), outline: 0,
    vertHead: 'attribute float aTip; varying vec3 vRoot; varying float vTip;',
    vertBody: `vRoot = vbRoot.xyz; vTip = aTip;
      vec2 dp = vbRoot.xz - uPlayer.xz; float dl = length(dp);
      float push = (1.0 - smoothstep(0.15, 1.0, dl)) * max(position.y, 0.0);
      transformed.xz += (dp / max(dl, 0.001)) * push * 0.8;
      transformed.y -= push * 0.5;`,
    fragHead: TERRAIN_HEAD + '\nvarying vec3 vRoot; varying float vTip;',
    albedoGLSL: `vec3 g = grassAlbedo(vRoot, mapMask(vRoot), 0.0);
      float gust = vb_gust(vRoot.xz);
      g *= mix(0.72, 1.12, vTip);
      g = mix(g, g * vec3(1.12, 1.15, 1.0) + 0.04, gust * vTip);
      diffuseColor.rgb = g;`,
  });
  const fmat = toonMat({
    key: 'toonflower', wind: 0.35, normalUp: true, outline: 0,
    vertHead: 'attribute float aPart; varying float vPart;', vertBody: 'vPart = aPart;',
    fragHead: 'varying float vPart;',
    albedoGLSL: 'diffuseColor.rgb = vPart < 0.5 ? vec3(0.35, 0.6, 0.3) : (vPart < 1.5 ? vColor.rgb : vec3(1.0, 0.85, 0.3));',
  });
  const fgeo = flowerGeo();
  const flowerCols = ['#ffffff', '#ffd84a', '#ff8fb0', '#8fb8ff', '#ff9e4a', '#ff5d7a', '#c9a3f0'].map((c) => new THREE.Color(c));
  const zoneAt = (u, v) => zones.find((z) => (u - z.c[0]) ** 2 + (v - z.c[1]) ** 2 < z.r * z.r);
  const CH = 10, chunks = new Map(), flowers = [];
  const step = 0.46;
  for (let v = -55; v < 55; v += step) {
    for (let u = -45; u < 45; u += step) {
      const uu = u + (rng() - 0.5) * step, vv = v + (rng() - 0.5) * step;
      const mk = world.maskAt(uu, vv);
      if (mk.path > 0.2 || mk.sand > 0.3 || mk.plaza > 0.2) continue;
      if (world.slopeAt(uu, vv) > 0.4) continue;
      const dens = vnoise(uu * 0.16 + 4, vv * 0.16 - 2) * 0.7 + vnoise(uu * 0.5, vv * 0.5) * 0.3;
      if (dens < 0.45 && rng() < 0.8) continue;
      if (!world.walkableUV(uu, vv) && rng() < 0.5) continue;
      const w = toWorld(uu, vv);
      const h = world.heightAt(w.x, w.z);
      if (h < WATER_Y + 0.12) continue;
      if (exclude && exclude(w.x, w.z)) continue;
      const z = zoneAt(uu, vv);
      if (z && rng() < 0.22) { flowers.push([w.x, h, w.z, flowerCols[z.colors[Math.floor(rng() * z.colors.length)]]]); continue; }
      const key = Math.floor(uu / CH) + ',' + Math.floor(vv / CH);
      if (!chunks.has(key)) chunks.set(key, []);
      chunks.get(key).push([w.x, h - 0.02, w.z, rng() * 6.28, 0.8 + rng() * 0.5]);
    }
  }
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), up = new THREE.Vector3(0, 1, 0), sc = new THREE.Vector3(), p = new THREE.Vector3();
  let total = 0;
  for (const list of chunks.values()) {
    const im = new THREE.InstancedMesh(geo, mat, list.length);
    list.forEach(([x, y, z, a, s], i) => { q.setFromAxisAngle(up, a); sc.set(s, s, s); p.set(x, y, z); m4.compose(p, q, sc); im.setMatrixAt(i, m4); });
    im.computeBoundingSphere(); im.layers.set(1); im.receiveShadow = true;
    scene.add(im); total += list.length;
  }
  if (flowers.length) {
    const fm = new THREE.InstancedMesh(fgeo, fmat, flowers.length);
    flowers.forEach(([x, y, z, c], i) => { q.setFromAxisAngle(up, i); sc.setScalar(0.9 + (i % 5) * 0.08); p.set(x, y, z); m4.compose(p, q, sc); fm.setMatrixAt(i, m4); fm.setColorAt(i, c); });
    fm.computeBoundingSphere(); fm.layers.set(1); fm.receiveShadow = true;
    scene.add(fm);
  }
  return total;
}

// =============================================================================
// Grama estilizada de anime: muitas lâminas finas e uniformes formando um tapete macio,
// degradê da base (cor do chão, mais escura) até a ponta clara e quente, ondas largas de
// vento que clareiam o campo e o tapete se abre quando o herói passa. Sem ruído fino.
// =============================================================================
function bladeClump(n = 7, seed = 3) {
  const rng = mulberry32(seed);
  const pos = [], hts = [], idx = [];
  for (let b = 0; b < n; b++) {
    const a = rng() * Math.PI * 2, r = Math.sqrt(rng()) * 0.2;
    const ox = Math.cos(a) * r, oz = Math.sin(a) * r;
    const h = 0.42 + rng() * 0.2, w = 0.034 + rng() * 0.01;
    const yaw = rng() * Math.PI * 2, lean = 0.12 + rng() * 0.12;
    const px = Math.cos(yaw) * w, pz = Math.sin(yaw) * w;
    const lx = -Math.sin(yaw) * lean, lz = Math.cos(yaw) * lean;
    const P = (t, side) => { const ww = (1 - t) * side; return [ox + px * ww + lx * t * t, h * t, oz + pz * ww + lz * t * t]; };
    const base = pos.length / 3;
    for (const [t, sd] of [[0, -1], [0, 1], [0.5, 1], [0.5, -1], [1, 0]]) { pos.push(...P(t, sd)); hts.push(t); }
    idx.push(base, base + 1, base + 2, base, base + 2, base + 3, base + 3, base + 2, base + 4);
  }
  const g = new THREE.BufferGeometry();
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('normal', new THREE.Float32BufferAttribute(new Array(pos.length).fill(0).map((_, i) => (i % 3 === 1 ? 1 : 0)), 3));
  g.setAttribute('aTip', new THREE.Float32BufferAttribute(hts, 1));
  g.setIndex(idx);
  return g;
}

export function buildAnimeGrass(world, scene, exclude, zones = []) {
  const rng = mulberry32(81);
  const geo = bladeClump(7, 5);
  const mat = toonMat({
    key: 'animegrass', wind: 0.0, normalUp: true, side: THREE.DoubleSide, uniforms: world.textures(), outline: 0,
    vertHead: 'attribute float aTip; varying vec3 vRoot; varying float vTip; varying float vWave;',
    vertBody: `vRoot = vbRoot.xyz; vTip = aTip;
      // ondas de vento largas e suaves (o campo "respira")
      float wv = sin(dot(vbRoot.xz, uWindDir) * 0.35 - uTime * 1.8) * 0.5 + 0.5;
      wv = wv * wv;
      vWave = wv;
      float bend = aTip * aTip * (0.08 + wv * 0.22) + sin(uTime * 3.1 + vbRoot.x * 1.7 + vbRoot.z) * 0.02 * aTip;
      transformed.xz += uWindDir * bend;
      transformed.y -= bend * 0.35;
      vec2 dp = vbRoot.xz - uPlayer.xz; float dl = length(dp);
      float push = (1.0 - smoothstep(0.1, 1.0, dl)) * aTip;
      transformed.xz += (dp / max(dl, 0.001)) * push * 0.35;
      transformed.y -= push * 0.25;`,
    fragHead: TERRAIN_HEAD + '\nvarying vec3 vRoot; varying float vTip; varying float vWave;',
    albedoGLSL: `vec3 g = grassAlbedo(vRoot, mapMask(vRoot), 0.0);
      vec3 base = g * 0.78;
      vec3 tip = g * 1.22 + vec3(0.07, 0.06, -0.01);
      vec3 c = mix(base, tip, smoothstep(0.0, 1.0, vTip));
      c = mix(c, c * 1.14 + vec3(0.05, 0.05, 0.0), vWave * vTip * 0.8);
      diffuseColor.rgb = c;`,
  });
  const fmat = toonMat({
    key: 'animeflower', wind: 0.25, normalUp: true, outline: 0,
    vertHead: 'attribute float aPart; varying float vPart;', vertBody: 'vPart = aPart;',
    fragHead: 'varying float vPart;',
    albedoGLSL: 'diffuseColor.rgb = vPart < 0.5 ? vec3(0.35, 0.6, 0.3) : (vPart < 1.5 ? vColor.rgb : vec3(1.0, 0.85, 0.3));',
  });
  const flowerCols = ['#ffffff', '#ffd84a', '#ff8fb0', '#8fb8ff', '#ff9e4a', '#ff5d7a', '#c9a3f0'].map((c) => new THREE.Color(c));
  const zoneAt = (u, v) => zones.find((z) => (u - z.c[0]) ** 2 + (v - z.c[1]) ** 2 < z.r * z.r);
  const CH = 8, chunks = new Map(), flowers = [];
  const step = 0.3;
  for (let v = -55; v < 55; v += step) {
    for (let u = -45; u < 45; u += step) {
      const uu = u + (rng() - 0.5) * step, vv = v + (rng() - 0.5) * step;
      const mk = world.maskAt(uu, vv);
      if (mk.path > 0.3 || mk.sand > 0.35 || mk.plaza > 0.25) continue;
      if (world.slopeAt(uu, vv) > 0.45) continue;
      if (!world.walkableUV(uu, vv) && rng() < 0.35) continue;
      const w = toWorld(uu, vv);
      const h = world.heightAt(w.x, w.z);
      if (h < WATER_Y + 0.12) continue;
      if (exclude && exclude(w.x, w.z)) continue;
      // altura uniforme por região (manchas grandes) e encolhe perto da trilha
      const hk = (0.75 + vnoise(uu * 0.08, vv * 0.08) * 0.5) * (1 - Math.min(1, mk.path * 2.5) * 0.6);
      const z = zoneAt(uu, vv);
      if (z && rng() < 0.05) flowers.push([w.x, h, w.z, flowerCols[z.colors[Math.floor(rng() * z.colors.length)]]]);
      const key = Math.floor(uu / CH) + ',' + Math.floor(vv / CH);
      if (!chunks.has(key)) chunks.set(key, []);
      chunks.get(key).push([w.x, h - 0.03, w.z, rng() * 6.28, hk]);
    }
  }
  const m4 = new THREE.Matrix4(), q = new THREE.Quaternion(), up = new THREE.Vector3(0, 1, 0), sc = new THREE.Vector3(), p = new THREE.Vector3();
  let total = 0;
  for (const list of chunks.values()) {
    const im = new THREE.InstancedMesh(geo, mat, list.length);
    list.forEach(([x, y, z, a, hk], i) => { q.setFromAxisAngle(up, a); sc.set(1, hk, 1); p.set(x, y, z); m4.compose(p, q, sc); im.setMatrixAt(i, m4); });
    im.computeBoundingSphere(); im.layers.set(1); im.receiveShadow = true;
    scene.add(im); total += list.length;
  }
  if (flowers.length) {
    const fm = new THREE.InstancedMesh(flowerGeo(), fmat, flowers.length);
    flowers.forEach(([x, y, z, c], i) => { q.setFromAxisAngle(up, i); sc.setScalar(1.1); p.set(x, y + 0.12, z); m4.compose(p, q, sc); fm.setMatrixAt(i, m4); fm.setColorAt(i, c); });
    fm.computeBoundingSphere(); fm.layers.set(1); fm.receiveShadow = true;
    scene.add(fm);
  }
  return total;
}
