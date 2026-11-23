import * as THREE from 'three';
import { mulberry32 } from './noise.js';

// =============================================================================
// Atlas de sprites em pixel art, desenhado proceduralmente (determinístico).
// Células de 16x16. Os canais codificam:
//   RGB cinza = tom (0,55 sombra · 0,8 meio · 1,0 luz) → multiplicado pela cor do objeto
//   alfa 1,0 = folhagem tingida · alfa 0,8 = pétala (tingida pela cor da flor) · alfa 0,66 = cor crua do texel
// Linhas: 0 grama · 1 folhas · 2 agulhas de pinheiro · 3 juncos, samambaias, trevos
// =============================================================================

export const CELL = 16, COLS = 8, ROWS = 4;
const W = CELL * COLS, H = CELL * ROWS;

let atlas = null;
export function getAtlas() {
  if (atlas) return atlas;
  const cv = document.createElement('canvas');
  cv.width = W; cv.height = H;
  const ctx = cv.getContext('2d');
  const img = ctx.createImageData(W, H);
  const d = img.data;
  const put = (cx, cy, x, y, tone, a = 1, rgb = null) => {
    if (x < 0 || y < 0 || x >= CELL || y >= CELL) return;
    const px = cx * CELL + x, py = cy * CELL + y;
    const i = (py * W + px) * 4;
    const v = Math.round(tone * 255);
    d[i] = rgb ? rgb[0] : v; d[i + 1] = rgb ? rgb[1] : v; d[i + 2] = rgb ? rgb[2] : v; d[i + 3] = Math.round(a * 255);
  };
  const rng = mulberry32(4242);
  const R = (a, b) => a + rng() * (b - a);

  // ---------------------------------------------------------------- grama
  const blade = (cx, x0, h, lean, thick, back) => {
    for (let s = 0; s <= h; s++) {
      const t = s / h;
      const x = Math.round(x0 + lean * Math.pow(t, 1.6));
      const y = 15 - s;
      const tone = t < 0.3 ? 0.56 : t < 0.72 ? 0.8 : 1.0;
      put(cx, 0, x, y, back ? tone * 0.86 : tone);
      if (thick && t < 0.45) put(cx, 0, x + (lean > 0 ? -1 : 1), y, (back ? 0.5 : 0.62));
    }
  };
  const tuft = (cx, n, hMin, hMax, spread) => {
    const blades = [];
    for (let i = 0; i < n; i++) blades.push({ x: Math.round(8 + R(-spread, spread)), h: Math.round(R(hMin, hMax)), lean: R(-3.5, 3.5), back: i < n / 2 });
    blades.sort((a, b) => (a.back === b.back ? 0 : a.back ? -1 : 1));
    for (const b of blades) blade(cx, b.x, b.h, b.lean, b.h > 7, b.back);
    return blades;
  };
  tuft(0, 7, 6, 10, 3.5);
  tuft(1, 6, 10, 14, 3);
  tuft(2, 10, 4, 8, 6);
  tuft(3, 8, 7, 12, 4.5);
  // flores
  const flower = (cx, x, y, big) => {
    const pet = [[0, -1], [-1, 0], [1, 0], [0, 1]];
    for (const [dx, dy] of pet) put(cx, 0, x + dx, y + dy, dy > 0 ? 0.75 : 1, 0.8);
    if (big) for (const [dx, dy] of [[-1, -1], [1, -1], [-1, 1], [1, 1]]) put(cx, 0, x + dx, y + dy, 0.85, 0.8);
    put(cx, 0, x, y, 1, 0.66, [250, 214, 92]);
  };
  { const b = tuft(4, 6, 6, 11, 3.5); b.filter((x) => !x.back).slice(0, 2).forEach((bl, i) => flower(4, Math.round(bl.x + bl.lean), 15 - bl.h, i === 0)); }
  { tuft(5, 7, 4, 8, 4.5); for (let i = 0; i < 4; i++) put(5, 0, Math.round(R(3, 13)), Math.round(R(6, 11)), 1, 0.8); }
  { tuft(6, 5, 8, 13, 3); flower(6, 8, 3, true); }
  // trevo / folhinhas redondas
  {
    for (let i = 0; i < 6; i++) {
      const x = Math.round(R(3, 12)), y = Math.round(R(8, 13));
      for (const [dx, dy] of [[0, 0], [1, 0], [0, 1], [1, 1], [-1, 0], [0, -1]]) put(7, 0, x + dx, y + dy, dy < 0 || dx < 0 ? 1 : 0.78);
      put(7, 0, x, y + 2, 0.56); put(7, 0, x, y + 3, 0.56);
    }
  }

  // ---------------------------------------------------------------- folhas
  const leaf = (cx, cy, x, y, o) => {
    const shapes = [
      [[0, 0], [1, 0], [2, 0], [0, 1], [1, 1], [2, 1], [1, -1], [1, 2]],
      [[0, 0], [1, 0], [0, 1], [1, 1], [2, 1], [1, 2], [-1, 0], [0, -1]],
      [[0, 0], [1, 0], [2, 0], [3, 0], [1, 1], [2, 1], [1, -1], [2, -1]],
      [[0, 0], [0, 1], [1, 1], [1, 2], [0, -1], [1, 0], [-1, 1], [0, 2]],
    ];
    const s = shapes[o % 4];
    const minY = Math.min(...s.map((p) => p[1])), maxY = Math.max(...s.map((p) => p[1]));
    const minX = Math.min(...s.map((p) => p[0]));
    for (const [dx, dy] of s) {
      const tone = dy === minY || (dx === minX && dy <= 0) ? 1.0 : dy === maxY ? 0.58 : 0.8;
      put(cx, cy, x + dx, y + dy, tone);
    }
  };
  for (let v = 0; v < 8; v++) {
    const pts = [];
    const n = v < 4 ? 9 : 7;
    for (let i = 0; i < n; i++) { const a = R(0, Math.PI * 2), r = Math.sqrt(rng()) * (v < 4 ? 5.2 : 4.4); pts.push([Math.round(7 + Math.cos(a) * r), Math.round(7.5 + Math.sin(a) * r * 0.9), Math.floor(R(0, 4))]); }
    pts.sort((a, b) => a[1] - b[1]);
    for (const [x, y, o] of pts) leaf(v, 1, x, y, o);
    // furinhos de luz
    if (v % 2) for (let k = 0; k < 2; k++) put(v, 1, Math.round(R(5, 10)), Math.round(R(5, 10)), 0, 0);
  }

  // ---------------------------------------------------------------- agulhas
  for (let v = 0; v < 8; v++) {
    const rows = 4;
    for (let r = 0; r < rows; r++) {
      const y = 3 + r * 3;
      const half = 2 + r * 1.6 + R(-0.5, 0.5);
      for (let x = Math.round(8 - half); x <= Math.round(8 + half); x++) {
        const edge = Math.abs(x - 8) > half - 1.2;
        put(v, 2, x, y, r === 0 ? 1 : 0.82);
        put(v, 2, x, y + 1, edge ? 0.58 : 0.7);
        if ((x + r + v) % 3 === 0) put(v, 2, x, y + 2, 0.56);
      }
      put(v, 2, 8, y - 1, 1);
    }
  }

  // ---------------------------------------------------------------- juncos, samambaia
  for (let v = 0; v < 4; v++) {
    for (let i = 0; i < 5; i++) {
      const x0 = Math.round(R(4, 12)), h = Math.round(R(9, 15)), lean = R(-2, 2);
      for (let s = 0; s <= h; s++) { const t = s / h; put(v, 3, Math.round(x0 + lean * t * t), 15 - s, t < 0.4 ? 0.58 : t < 0.8 ? 0.8 : 1); }
      if (i < 2 && v < 2) {
        const tx = Math.round(x0 + lean), ty = 15 - h;
        for (let k = 0; k < 3; k++) { put(v, 3, tx, ty + k, 1, 0.66, k === 0 ? [150, 96, 62] : [118, 74, 48]); put(v, 3, tx + 1, ty + k, 1, 0.66, [96, 58, 40]); }
      }
    }
  }
  for (let v = 4; v < 8; v++) { // samambaia
    for (let f = 0; f < 4; f++) {
      const a = -Math.PI / 2 + (f - 1.5) * 0.5;
      for (let s = 0; s < 9; s++) {
        const x = Math.round(8 + Math.cos(a) * s), y = Math.round(15 + Math.sin(a) * s * 1.1);
        put(v, 3, x, y, 0.62);
        if (s > 1 && s % 2 === 0) { put(v, 3, x - 1, y - 1, 0.95); put(v, 3, x + 1, y - 1, 0.82); }
      }
    }
  }

  ctx.putImageData(img, 0, 0);
  const tex = new THREE.CanvasTexture(cv);
  tex.magFilter = tex.minFilter = THREE.NearestFilter;
  tex.generateMipmaps = false;
  tex.flipY = false;
  tex.colorSpace = THREE.NoColorSpace;
  atlas = tex;
  return tex;
}

/** uv (canto sup. esq. da célula) no atlas — flipY desligado: v cresce para baixo */
export const cellUV = (col, row) => [col / COLS, row / ROWS];
export const CELL_U = 1 / COLS, CELL_V = 1 / ROWS;

/** malha de um cartão 16x16 virado para a câmera, base no ponto (0,0,0) */
export function cardQuad(size, right, up, col, row, bottom = true) {
  const g = new THREE.BufferGeometry();
  const hw = size / 2;
  const y0 = bottom ? 0 : -size / 2;
  const P = (x, y) => [right.x * x + up.x * y, right.y * x + up.y * y, right.z * x + up.z * y];
  const pos = [...P(-hw, y0), ...P(hw, y0), ...P(hw, y0 + size), ...P(-hw, y0 + size)];
  const [u0, v0] = cellUV(col, row);
  const uv = [u0, v0 + CELL_V, u0 + CELL_U, v0 + CELL_V, u0 + CELL_U, v0, u0, v0];
  g.setAttribute('position', new THREE.Float32BufferAttribute(pos, 3));
  g.setAttribute('uv', new THREE.Float32BufferAttribute(uv, 2));
  g.setAttribute('normal', new THREE.Float32BufferAttribute([0, 1, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0], 3));
  g.setIndex([0, 1, 2, 0, 2, 3]);
  return g;
}
