// Colisão simples: círculos (pessoas/itens) contra AABBs (móveis e paredes).
import { BOUNDS } from './level.js';

export function pushOutCircle(pos, r, colliders, opts = {}) {
  const { minTop = 0.05, y = null } = opts;
  let hit = null;
  for (const b of colliders) {
    if (b.top < minTop) continue;
    if (y != null && y > b.top - 0.02) continue; // está acima (ex.: item sobre a mesa)
    const cx = Math.max(b.minX, Math.min(b.maxX, pos.x));
    const cz = Math.max(b.minZ, Math.min(b.maxZ, pos.z));
    let dx = pos.x - cx, dz = pos.z - cz;
    const d2 = dx * dx + dz * dz;
    if (d2 < r * r) {
      if (d2 > 1e-8) {
        const d = Math.sqrt(d2);
        pos.x = cx + (dx / d) * r; pos.z = cz + (dz / d) * r;
        hit = { nx: dx / d, nz: dz / d };
      } else {
        // centro dentro da caixa: empurra pelo lado mais próximo
        const l = pos.x - b.minX, rr = b.maxX - pos.x, t = pos.z - b.minZ, bb = b.maxZ - pos.z;
        const m = Math.min(l, rr, t, bb);
        if (m === l) { pos.x = b.minX - r; hit = { nx: -1, nz: 0 }; }
        else if (m === rr) { pos.x = b.maxX + r; hit = { nx: 1, nz: 0 }; }
        else if (m === t) { pos.z = b.minZ - r; hit = { nx: 0, nz: -1 }; }
        else { pos.z = b.maxZ + r; hit = { nx: 0, nz: 1 }; }
      }
    }
  }
  pos.x = Math.max(BOUNDS.minX + r, Math.min(BOUNDS.maxX - r, pos.x));
  pos.z = Math.max(BOUNDS.minZ + r, Math.min(BOUNDS.maxZ - r, pos.z));
  return hit;
}

export function groundAt(x, z, y, colliders) {
  let g = 0;
  for (const b of colliders) {
    if (x >= b.minX && x <= b.maxX && z >= b.minZ && z <= b.maxZ && b.top <= y + 0.06 && b.top > g) g = b.top;
  }
  return g;
}
