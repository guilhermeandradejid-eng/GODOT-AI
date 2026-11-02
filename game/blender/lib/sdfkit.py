"""sdfkit — modelagem de personagens por campos de distância (SDF).

Formas orgânicas com acabamento de "brinquedo premium": partes primitivas
(elipsoides, cones arredondados, caixas, toros, tubos) somadas com união SUAVE
(smin), cascas de tecido (|d| - espessura) recortadas por planos e "pinturas"
(volumes que só colorem). A malha sai por Surface Nets + projeção na
superfície, é decimada no Blender (QEM) preservando contornos de cor e regiões
de detalhe, e recebe cor por vértice e pesos de skin calculados das próprias
partes (cada parte pertence a um osso -> pesos suaves nas junções).

A parte numérica (numpy) roda dentro ou fora do Blender; as funções que criam
objetos importam bpy sob demanda.

Convenção: Blender Z-up, personagem olhando para -Y, lado esquerdo em +X.
"""
from __future__ import annotations

import math

import numpy as np


# ----------------------------------------------------------------------------- utils
def _v(a) -> np.ndarray:
    return np.asarray(a, dtype=np.float64)


def euler(rx: float = 0.0, ry: float = 0.0, rz: float = 0.0) -> np.ndarray:
    """Matriz local->mundo para Euler XYZ em graus (ordem do Blender)."""
    x, y, z = (math.radians(a) for a in (rx, ry, rz))
    cx, sx, cy, sy, cz, sz = math.cos(x), math.sin(x), math.cos(y), math.sin(y), math.cos(z), math.sin(z)
    rot_x = np.array([[1, 0, 0], [0, cx, -sx], [0, sx, cx]])
    rot_y = np.array([[cy, 0, sy], [0, 1, 0], [-sy, 0, cy]])
    rot_z = np.array([[cz, -sz, 0], [sz, cz, 0], [0, 0, 1]])
    return rot_z @ rot_y @ rot_x


def look_basis(direction, up=(0.0, 0.0, 1.0)) -> np.ndarray:
    """Matriz cujo eixo local Z aponta para `direction`."""
    z = _v(direction)
    z = z / (np.linalg.norm(z) + 1e-12)
    u = _v(up)
    if abs(float(np.dot(u, z))) > 0.98:
        u = np.array([0.0, 1.0, 0.0]) if abs(z[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
    x = np.cross(u, z)
    x /= np.linalg.norm(x) + 1e-12
    y = np.cross(z, x)
    return np.stack([x, y, z], axis=1)


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def hexcol(h: str) -> tuple:
    h = h.lstrip("#")
    return tuple(int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4))


def smin(a: np.ndarray, b: np.ndarray, k: float) -> np.ndarray:
    """União suave polinomial (Quilez)."""
    if k <= 0.0:
        return np.minimum(a, b)
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.minimum(a, b) - h * h * k * 0.25


def smax(a: np.ndarray, b: np.ndarray, k: float) -> np.ndarray:
    return -smin(-a, -b, k)


def smoothstep(e0: float, e1: float, x: np.ndarray) -> np.ndarray:
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3.0 - 2.0 * t)


# ----------------------------------------------------------------------------- primitives
class Prim:
    """Uma SDF com caixa envolvente (lo, hi). Chamável com P (N, 3) -> (N,)."""
    __slots__ = ("fn", "lo", "hi")

    def __init__(self, fn, lo, hi):
        self.fn = fn
        self.lo = _v(lo)
        self.hi = _v(hi)

    def __call__(self, P: np.ndarray) -> np.ndarray:
        return self.fn(P)

    def mirrored(self) -> "Prim":
        """Espelha em X (lado esquerdo <-> direito)."""
        fn = self.fn

        def f(P):
            Q = P.copy()
            Q[:, 0] = -Q[:, 0]
            return fn(Q)
        return Prim(f, (-self.hi[0], self.lo[1], self.lo[2]), (-self.lo[0], self.hi[1], self.hi[2]))

    def offset(self, r: float) -> "Prim":
        fn = self.fn
        return Prim(lambda P: fn(P) - r, self.lo - max(r, 0), self.hi + max(r, 0))

    def shell(self, t: float) -> "Prim":
        """Casca de espessura 2t em volta da superfície (tecido)."""
        fn = self.fn
        return Prim(lambda P: np.abs(fn(P)) - t, self.lo - t, self.hi + t)

    def union(self, o: "Prim", k: float = 0.0) -> "Prim":
        a, b = self.fn, o.fn
        return Prim(lambda P: smin(a(P), b(P), k), np.minimum(self.lo, o.lo), np.maximum(self.hi, o.hi))

    def cut(self, o: "Prim", k: float = 0.0) -> "Prim":
        """self menos o."""
        a, b = self.fn, o.fn
        return Prim(lambda P: smax(a(P), -b(P), k), self.lo, self.hi)

    def clip(self, o: "Prim", k: float = 0.0) -> "Prim":
        """Interseção."""
        a, b = self.fn, o.fn
        return Prim(lambda P: smax(a(P), b(P), k), np.maximum(self.lo, o.lo), np.minimum(self.hi, o.hi))

    def warp(self, fn_warp) -> "Prim":
        """Deforma o espaço: d(P) = sdf(fn_warp(P)). Use com moderação (não-Lipschitz)."""
        fn = self.fn
        return Prim(lambda P: fn(fn_warp(P)), self.lo, self.hi)


def _local(P, c, R):
    return (P - c) @ R


def _rot_bbox(c, half, R):
    ext = np.abs(R) @ _v(half)
    return c - ext, c + ext


def sphere(c, r: float) -> Prim:
    c = _v(c)
    return Prim(lambda P: np.linalg.norm(P - c, axis=1) - r, c - r, c + r)


def ellipsoid(c, radii, rot=(0.0, 0.0, 0.0)) -> Prim:
    """Elipsoide (aproximação de Quilez, ótima perto da superfície)."""
    c = _v(c)
    r = _v(radii)
    R = euler(*rot) if len(rot) == 3 and not isinstance(rot, np.ndarray) else _v(rot)

    def f(P):
        q = _local(P, c, R)
        k0 = np.linalg.norm(q / r, axis=1)
        k1 = np.linalg.norm(q / (r * r), axis=1)
        return k0 * (k0 - 1.0) / np.maximum(k1, 1e-9)
    lo, hi = _rot_bbox(c, r, R)
    return Prim(f, lo, hi)


def round_cone(a, b, ra: float, rb: float) -> Prim:
    """Cone arredondado de a (raio ra) até b (raio rb) — exato (Quilez)."""
    a = _v(a)
    b = _v(b)
    ba = b - a
    l2 = float(np.dot(ba, ba))
    rr = ra - rb
    a2 = l2 - rr * rr
    il2 = 1.0 / max(l2, 1e-12)

    def f(P):
        pa = P - a
        y = pa @ ba
        z = y - l2
        w = pa * l2 - np.outer(y, ba)
        x2 = np.einsum("ij,ij->i", w, w)
        y2 = y * y * l2
        z2 = z * z * l2
        k = math.copysign(1.0, rr) * rr * rr * x2
        d_tip = np.sqrt(x2 + z2) * il2 - rb
        d_base = np.sqrt(x2 + y2) * il2 - ra
        d_side = (np.sqrt(np.maximum(x2 * a2 * il2, 0.0)) + y * rr) * il2 - ra
        return np.where(np.sign(z) * a2 * z2 > k, d_tip, np.where(np.sign(y) * a2 * y2 < k, d_base, d_side))
    r = max(ra, rb)
    return Prim(f, np.minimum(a, b) - r, np.maximum(a, b) + r)


def capsule(a, b, r: float) -> Prim:
    return round_cone(a, b, r, r)


def box(c, half, rot=(0.0, 0.0, 0.0), rounding: float = 0.0) -> Prim:
    c = _v(c)
    h = _v(half)
    R = euler(*rot) if len(rot) == 3 and not isinstance(rot, np.ndarray) else _v(rot)

    def f(P):
        q = np.abs(_local(P, c, R)) - h + rounding
        return np.linalg.norm(np.maximum(q, 0.0), axis=1) + np.minimum(q.max(axis=1), 0.0) - rounding
    lo, hi = _rot_bbox(c, h, R)
    return Prim(f, lo, hi)


def cylinder(c, radius: float, half_h: float, rot=(0.0, 0.0, 0.0), rounding: float = 0.0) -> Prim:
    """Cilindro ao longo do Z local."""
    c = _v(c)
    R = euler(*rot) if len(rot) == 3 and not isinstance(rot, np.ndarray) else _v(rot)

    def f(P):
        q = _local(P, c, R)
        d0 = np.linalg.norm(q[:, :2], axis=1) - radius + rounding
        d1 = np.abs(q[:, 2]) - half_h + rounding
        return np.minimum(np.maximum(d0, d1), 0.0) + np.sqrt(np.maximum(d0, 0) ** 2 + np.maximum(d1, 0) ** 2) - rounding
    lo, hi = _rot_bbox(c, (radius, radius, half_h), R)
    return Prim(f, lo, hi)


def cone(c, r_base: float, r_top: float, half_h: float, rot=(0.0, 0.0, 0.0), rounding: float = 0.0) -> Prim:
    """Tronco de cone ao longo do Z local (base em -half_h)."""
    c = _v(c)
    R = euler(*rot) if len(rot) == 3 and not isinstance(rot, np.ndarray) else _v(rot)
    h = half_h - rounding
    r1 = r_base - rounding
    r2 = r_top - rounding

    def f(P):
        q3 = _local(P, c, R)
        qx = np.linalg.norm(q3[:, :2], axis=1)
        qy = q3[:, 2]
        k1x, k1y = r2, h
        k2x, k2y = r2 - r1, 2.0 * h
        cax = qx - np.minimum(qx, np.where(qy < 0.0, r1, r2))
        cay = np.abs(qy) - h
        t = np.clip(((k1x - qx) * k2x + (k1y - qy) * k2y) / (k2x * k2x + k2y * k2y), 0.0, 1.0)
        cbx = qx - k1x + k2x * t
        cby = qy - k1y + k2y * t
        s = np.where((cbx < 0.0) & (cay < 0.0), -1.0, 1.0)
        return s * np.sqrt(np.minimum(cax * cax + cay * cay, cbx * cbx + cby * cby)) - rounding
    r = max(r_base, r_top)
    lo, hi = _rot_bbox(c, (r, r, half_h), R)
    return Prim(f, lo, hi)


def torus(c, major: float, minor: float, rot=(0.0, 0.0, 0.0)) -> Prim:
    """Toro em volta do Z local."""
    c = _v(c)
    R = euler(*rot) if len(rot) == 3 and not isinstance(rot, np.ndarray) else _v(rot)

    def f(P):
        q = _local(P, c, R)
        qx = np.linalg.norm(q[:, :2], axis=1) - major
        return np.sqrt(qx * qx + q[:, 2] ** 2) - minor
    lo, hi = _rot_bbox(c, (major + minor, major + minor, minor), R)
    return Prim(f, lo, hi)


def plane(point, normal) -> Prim:
    """Semi-espaço: negativo do lado oposto à normal."""
    p0 = _v(point)
    n = _v(normal)
    n = n / np.linalg.norm(n)
    return Prim(lambda P: (P - p0) @ n, (-1e3,) * 3, (1e3,) * 3)


def tube(points, radii, k: float = 0.0) -> Prim:
    """Tubo por uma polilinha (cones arredondados encadeados)."""
    pts = [_v(p) for p in points]
    rs = list(radii) if hasattr(radii, "__len__") else [radii] * len(pts)
    segs = [round_cone(pts[i], pts[i + 1], rs[i], rs[i + 1]) for i in range(len(pts) - 1)]

    def f(P):
        d = segs[0](P)
        for s in segs[1:]:
            d = smin(d, s(P), k)
        return d
    lo = np.min([s.lo for s in segs], axis=0)
    hi = np.max([s.hi for s in segs], axis=0)
    return Prim(f, lo, hi)


def bezier_points(p0, p1, p2, p3=None, n: int = 8) -> list:
    """Amostra uma Bézier quadrática (p0, p1, p2) ou cúbica (p0..p3)."""
    p0, p1, p2 = _v(p0), _v(p1), _v(p2)
    out = []
    for i in range(n + 1):
        t = i / n
        if p3 is None:
            out.append((1 - t) ** 2 * p0 + 2 * (1 - t) * t * p1 + t * t * p2)
        else:
            q3 = _v(p3)
            out.append((1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * p1 + 3 * (1 - t) * t * t * p2 + t ** 3 * q3)
    return out


def ribbon(points, widths, thickness: float, up=(0.0, 0.0, 1.0)) -> Prim:
    """Fita achatada por uma polilinha: caixas arredondadas por segmento.
    `up` define o lado "largo" (largura no plano perpendicular a `up`)."""
    pts = [_v(p) for p in points]
    ws = list(widths) if hasattr(widths, "__len__") else [widths] * len(pts)
    parts = []
    for i in range(len(pts) - 1):
        a, b = pts[i], pts[i + 1]
        d = b - a
        L = float(np.linalg.norm(d))
        if L < 1e-6:
            continue
        z = d / L
        u = _v(up)
        x = np.cross(z, u)
        if np.linalg.norm(x) < 1e-6:
            x = np.cross(z, np.array([1.0, 0.0, 0.0]))
        x /= np.linalg.norm(x)
        y = np.cross(z, x)
        R = np.stack([x, y, z], axis=1)
        w = 0.5 * (ws[i] + ws[i + 1])
        parts.append(box((a + b) * 0.5, (w * 0.5, thickness, L * 0.5 + thickness), R, rounding=thickness * 0.95))

    def f(P):
        d = parts[0](P)
        for s in parts[1:]:
            d = np.minimum(d, s(P))
        return d
    lo = np.min([s.lo for s in parts], axis=0)
    hi = np.max([s.hi for s in parts], axis=0)
    return Prim(f, lo, hi)


# ----------------------------------------------------------------------------- shapes
class Shape:
    """Uma peça da personagem (vira uma superfície com um material).

    add(prim, bone, color, k)   soma suave (k = raio da mescla)
    carve(prim, k, color)       subtrai (cavidades: boca, olhos fundos...)
    clip(prim, k)               interseção (recortes por plano...)
    paint(prim, color, soft)    só colore (manchas, listras, pintura facial)
    detail(prim, w)             região onde a decimação preserva mais triângulos
    """

    def __init__(self, name: str, material: str, voxel: float = 0.005, tris: int = 4000,
                 color_soft: float = 0.006, weight_sigma: float = 0.03):
        self.name = name
        self.material = material
        self.voxel = voxel
        self.tris = tris
        self.color_soft = color_soft
        self.weight_sigma = weight_sigma
        self.items: list[tuple] = []          # (kind, prim, k, bone, color)
        self.paints: list[tuple] = []         # (prim, color, soft, emission)
        self.details: list[tuple] = []        # (prim, w)
        self.cull_by: list["Shape"] = []      # peças que cobrem esta (faces escondidas somem)
        self.cull_margin = 0.012
        self.emission_soft = 0.004

    # building ---------------------------------------------------------------
    def add(self, prim: Prim, bone: str, color, k: float = 0.02) -> "Shape":
        self.items.append(("add", prim, k, bone, tuple(color)))
        return self

    def add_mirrored(self, prim: Prim, bone_l: str, color, k: float = 0.02) -> "Shape":
        """Adiciona a parte (lado esquerdo, +X) e a espelhada (direito)."""
        self.add(prim, bone_l, color, k)
        bone_r = bone_l[:-2] + "_R" if bone_l.endswith("_L") else bone_l
        self.add(prim.mirrored(), bone_r, color, k)
        return self

    def carve(self, prim: Prim, k: float = 0.0, color=None) -> "Shape":
        self.items.append(("carve", prim, k, None, None if color is None else tuple(color)))
        return self

    def clip(self, prim: Prim, k: float = 0.0) -> "Shape":
        self.items.append(("clip", prim, k, None, None))
        return self

    def paint(self, prim: Prim, color, soft: float = 0.006, emission: float = 0.0) -> "Shape":
        self.paints.append((prim, tuple(color), soft, emission))
        return self

    def detail(self, prim: Prim, w: float = 1.0) -> "Shape":
        self.details.append((prim, w))
        return self

    # evaluation ---------------------------------------------------------------
    def field(self, P: np.ndarray) -> np.ndarray:
        d = None
        for kind, prim, k, _bone, _col in self.items:
            di = prim(P)
            if d is None:
                d = di if kind == "add" else np.full(len(P), 1e3)
                continue
            if kind == "add":
                d = smin(d, di, k)
            elif kind == "carve":
                d = smax(d, -di, k)
            else:
                d = smax(d, di, k)
        return d

    def bounds(self) -> tuple[np.ndarray, np.ndarray]:
        adds = [it for it in self.items if it[0] == "add"]
        lo = np.min([it[1].lo - it[2] for it in adds], axis=0)
        hi = np.max([it[1].hi + it[2] for it in adds], axis=0)
        for kind, prim, k, _b, _c in self.items:
            if kind == "clip" and np.all(np.abs(prim.lo) < 900):
                lo = np.maximum(lo, prim.lo)
                hi = np.minimum(hi, prim.hi)
        m = 3.0 * self.voxel
        return lo - m, hi + m

    def _add_items(self):
        return [it for it in self.items if it[0] == "add"]

    def colors_at(self, V: np.ndarray) -> np.ndarray:
        adds = self._add_items()
        D = np.stack([it[1](V) for it in adds])
        dmin = D.min(axis=0)
        W = np.exp(-(D - dmin) / self.color_soft)
        cols = np.array([it[4] for it in adds])
        C = (W[:, :, None] * cols[:, None, :]).sum(axis=0) / W.sum(axis=0)[:, None]
        for kind, prim, k, _b, col in self.items:
            if kind == "carve" and col is not None:
                a = smoothstep(self.color_soft * 1.5, 0.0, prim(V))
                C = C * (1 - a[:, None]) + np.array(col)[None, :] * a[:, None]
        for prim, col, soft, _em in self.paints:
            a = smoothstep(soft * 0.5, -soft * 0.5, prim(V))
            C = C * (1 - a[:, None]) + np.array(col)[None, :] * a[:, None]
        return C

    def emission_at(self, V: np.ndarray) -> np.ndarray:
        E = np.zeros(len(V))
        for prim, _col, soft, em in self.paints:
            if em > 0.0:
                a = smoothstep(soft * 0.5, -soft * 0.5, prim(V))
                E = np.maximum(E, a * em)
        return E

    def weights_at(self, V: np.ndarray, max_influences: int = 4) -> list[dict]:
        adds = self._add_items()
        D = np.stack([it[1](V) for it in adds])
        dmin = D.min(axis=0)
        W = np.exp(-(D - dmin) / self.weight_sigma)
        bones = sorted({it[3] for it in adds})
        bi = {b: i for i, b in enumerate(bones)}
        B = np.zeros((len(bones), len(V)))
        for j, it in enumerate(adds):
            B[bi[it[3]]] += W[j]
        out = []
        order = np.argsort(-B, axis=0)[:max_influences]
        for v in range(len(V)):
            ids = order[:, v]
            ws = B[ids, v]
            s = ws.sum()
            d = {}
            for i, w in zip(ids, ws):
                if w / s > 0.01:
                    d[bones[i]] = w / s
            s2 = sum(d.values())
            out.append({k: w / s2 for k, w in d.items()})
        return out

    def detail_at(self, V: np.ndarray) -> np.ndarray:
        out = np.zeros(len(V))
        for prim, w in self.details:
            out = np.maximum(out, smoothstep(0.01, -0.01, prim(V)) * w)
        return out


# ----------------------------------------------------------------------------- meshing
_CORNERS = np.array([(0, 0, 0), (1, 0, 0), (0, 1, 0), (1, 1, 0), (0, 0, 1), (1, 0, 1), (0, 1, 1), (1, 1, 1)])
_EDGES = [(0, 1), (2, 3), (4, 5), (6, 7), (0, 2), (1, 3), (4, 6), (5, 7), (0, 4), (1, 5), (2, 6), (3, 7)]


def sample_grid(field, lo, hi, voxel: float, slab_points: int = 1_500_000):
    lo = _v(lo)
    n = (np.ceil((_v(hi) - lo) / voxel).astype(int) + 1)
    nx, ny, nz = (int(a) for a in n)
    xs = lo[0] + np.arange(nx) * voxel
    ys = lo[1] + np.arange(ny) * voxel
    zs = lo[2] + np.arange(nz) * voxel
    D = np.empty((nx, ny, nz), np.float32)
    Y, Z = np.meshgrid(ys, zs, indexing="ij")
    per = max(1, slab_points // (ny * nz))
    for i0 in range(0, nx, per):
        i1 = min(nx, i0 + per)
        P = np.empty((i1 - i0, ny, nz, 3))
        P[..., 0] = xs[i0:i1, None, None]
        P[..., 1] = Y[None]
        P[..., 2] = Z[None]
        D[i0:i1] = field(P.reshape(-1, 3)).reshape(i1 - i0, ny, nz)
    return D, lo


def surface_nets(D: np.ndarray, lo: np.ndarray, voxel: float):
    """Malha de quads (Surface Nets) da isosuperfície 0 de D (negativo = dentro)."""
    nx, ny, nz = D.shape
    S = D < 0.0
    cs = [S[a:nx - 1 + a, b:ny - 1 + b, c:nz - 1 + c] for a, b, c in _CORNERS]
    any_in = cs[0].copy()
    all_in = cs[0].copy()
    for c in cs[1:]:
        any_in |= c
        all_in &= c
    active = any_in & ~all_in
    idx = np.argwhere(active)
    M = len(idx)
    if M == 0:
        return np.zeros((0, 3)), np.zeros((0, 4), np.int64)
    dc = [D[idx[:, 0] + a, idx[:, 1] + b, idx[:, 2] + c].astype(np.float64) for a, b, c in _CORNERS]
    acc = np.zeros((M, 3))
    cnt = np.zeros(M)
    for e0, e1 in _EDGES:
        d0 = dc[e0]
        d1 = dc[e1]
        m = (d0 < 0.0) != (d1 < 0.0)
        t = d0[m] / (d0[m] - d1[m])
        p0 = _CORNERS[e0].astype(np.float64)
        p1 = _CORNERS[e1].astype(np.float64)
        acc[m] += p0[None, :] + t[:, None] * (p1 - p0)[None, :]
        cnt[m] += 1.0
    V = lo[None, :] + (idx + acc / cnt[:, None]) * voxel
    lin = (idx[:, 0] * (ny - 1) + idx[:, 1]) * (nz - 1) + idx[:, 2]

    def vid(i, j, k):
        q = (i * (ny - 1) + j) * (nz - 1) + k
        return np.searchsorted(lin, q)

    quads = []
    # x edges
    e = np.argwhere(S[:-1, 1:-1, 1:-1] != S[1:, 1:-1, 1:-1])
    if len(e):
        i, j, k = e[:, 0], e[:, 1] + 1, e[:, 2] + 1
        q = np.stack([vid(i, j - 1, k - 1), vid(i, j, k - 1), vid(i, j, k), vid(i, j - 1, k)], axis=1)
        flip = ~S[i, j, k]
        q[flip] = q[flip][:, ::-1]
        quads.append(q)
    # y edges
    e = np.argwhere(S[1:-1, :-1, 1:-1] != S[1:-1, 1:, 1:-1])
    if len(e):
        i, j, k = e[:, 0] + 1, e[:, 1], e[:, 2] + 1
        q = np.stack([vid(i - 1, j, k - 1), vid(i - 1, j, k), vid(i, j, k), vid(i, j, k - 1)], axis=1)
        flip = ~S[i, j, k]
        q[flip] = q[flip][:, ::-1]
        quads.append(q)
    # z edges
    e = np.argwhere(S[1:-1, 1:-1, :-1] != S[1:-1, 1:-1, 1:])
    if len(e):
        i, j, k = e[:, 0] + 1, e[:, 1] + 1, e[:, 2]
        q = np.stack([vid(i - 1, j - 1, k), vid(i, j - 1, k), vid(i, j, k), vid(i - 1, j, k)], axis=1)
        flip = ~S[i, j, k]
        q[flip] = q[flip][:, ::-1]
        quads.append(q)
    F = np.concatenate(quads) if quads else np.zeros((0, 4), np.int64)
    return V, F


def project(field, V: np.ndarray, voxel: float, iters: int = 3) -> np.ndarray:
    """Empurra os vértices para a superfície exata (passos de Newton limitados)."""
    eps = voxel * 0.35
    ex = np.array([eps, 0, 0])
    ey = np.array([0, eps, 0])
    ez = np.array([0, 0, eps])
    for _ in range(iters):
        d = field(V)
        g = np.stack([field(V + ex) - field(V - ex), field(V + ey) - field(V - ey),
                      field(V + ez) - field(V - ez)], axis=1) / (2 * eps)
        gl2 = np.einsum("ij,ij->i", g, g)
        step = (d / np.maximum(gl2, 1e-9))[:, None] * g
        sl = np.linalg.norm(step, axis=1)
        lim = np.minimum(1.0, voxel * 0.75 / np.maximum(sl, 1e-12))
        V = V - step * lim[:, None]
    return V


def mesh_shape(shape: Shape, log=print):
    lo, hi = shape.bounds()
    D, lo = sample_grid(shape.field, lo, hi, shape.voxel)
    V, F = surface_nets(D, lo, shape.voxel)
    V = project(shape.field, V, shape.voxel)
    if shape.cull_by:
        inside = np.zeros(len(V), bool)
        for other in shape.cull_by:
            inside |= other.field(V) < -shape.cull_margin
        keep = ~inside[F].all(axis=1)
        F = F[keep]
        used = np.unique(F)
        remap = -np.ones(len(V), np.int64)
        remap[used] = np.arange(len(used))
        V = V[used]
        F = remap[F]
    log(f"  {shape.name}: grid {D.shape}, {len(V)} verts, {len(F)} quads")
    return V, F


def field_normals(field, V: np.ndarray, eps: float = 0.002) -> np.ndarray:
    ex = np.array([eps, 0, 0])
    ey = np.array([0, eps, 0])
    ez = np.array([0, 0, eps])
    g = np.stack([field(V + ex) - field(V - ex), field(V + ey) - field(V - ey), field(V + ez) - field(V - ez)], axis=1)
    return g / np.maximum(np.linalg.norm(g, axis=1), 1e-12)[:, None]


def sdf_ao(field, V: np.ndarray, N: np.ndarray, reach: float = 0.12, steps: int = 5, strength: float = 3.0) -> np.ndarray:
    """Oclusão ambiente pelo próprio campo (Quilez): 1 = aberto, 0 = fechado."""
    occ = np.zeros(len(V))
    sca = 1.0
    for i in range(steps):
        h = 0.01 + reach * i / max(steps - 1, 1)
        d = field(V + N * h)
        occ += (h - d) * sca
        sca *= 0.9
    return np.clip(1.0 - strength * occ, 0.0, 1.0)


# ----------------------------------------------------------------------------- blender
def build_object(shape: Shape, rig_bones: list[str], log=print, decimate: bool = True,
                 ao_field=None, ao_strength: float = 0.55):
    """Cria o objeto Blender da peça: malha decimada + cor/emissão por vértice + pesos."""
    import bpy

    V, F = mesh_shape(shape, log)
    me = bpy.data.meshes.new(shape.name)
    me.vertices.add(len(V))
    me.vertices.foreach_set("co", V.astype(np.float32).ravel())
    me.loops.add(F.size)
    me.loops.foreach_set("vertex_index", F.astype(np.int32).ravel())
    me.polygons.add(len(F))
    me.polygons.foreach_set("loop_start", (np.arange(len(F)) * 4).astype(np.int32))
    me.update(calc_edges=True)
    me.validate(clean_customdata=False)
    obj = bpy.data.objects.new(shape.name, me)
    bpy.context.scene.collection.objects.link(obj)
    if decimate:
        # preserve color borders + explicit detail regions
        C = shape.colors_at(V)
        keep = _color_border(C, F) * 0.6
        keep = np.maximum(keep, shape.detail_at(V))
        vg = obj.vertex_groups.new(name="_detail")
        for lvl in np.linspace(0.05, 1.0, 20):
            ids = np.nonzero((keep > lvl - 0.05) & (keep <= lvl + 1e-9))[0]
            if len(ids):
                vg.add(ids.tolist(), float(lvl), "REPLACE")
        tris_now = 2 * len(F)
        ratio = min(1.0, shape.tris / max(tris_now, 1))
        bpy.context.view_layer.objects.active = obj
        mod = obj.modifiers.new("Decimate", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = ratio
        mod.use_collapse_triangulate = True
        mod.vertex_group = "_detail"
        mod.invert_vertex_group = True
        mod.vertex_group_factor = 1.0
        bpy.ops.object.modifier_apply(modifier=mod.name)
        obj.vertex_groups.remove(obj.vertex_groups["_detail"])
    me = obj.data
    n = len(me.vertices)
    co = np.empty(n * 3, np.float32)
    me.vertices.foreach_get("co", co)
    Vd = co.reshape(-1, 3).astype(np.float64)
    # colors (sRGB -> linear) + emission in alpha
    C = shape.colors_at(Vd)
    E = shape.emission_at(Vd)
    if ao_field is not None and ao_strength > 0.0:
        N = field_normals(shape.field, Vd)
        ao = sdf_ao(ao_field, Vd + N * 0.002, N)
        C = C * (1.0 - ao_strength * (1.0 - ao) * (1.0 - E))[:, None]
    lin = np.vectorize(srgb_to_linear)(np.clip(C, 0, 1))
    rgba = np.concatenate([lin, (1.0 - E)[:, None]], axis=1).astype(np.float32)
    attr = me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
    attr.data.foreach_set("color", rgba.ravel())
    me.color_attributes.active_color = attr
    try:
        me.color_attributes.render_color_index = me.color_attributes.find("Col")
    except Exception:
        pass
    # uv: simple planar (front) projection — the toon shaders use vertex colors
    uvl = me.uv_layers.new(name="UVMap")
    li = np.empty(len(me.loops), np.int32)
    me.loops.foreach_get("vertex_index", li)
    uv = np.stack([Vd[li, 0] * 0.5 + 0.5, Vd[li, 2] * 0.5], axis=1).astype(np.float32)
    uvl.data.foreach_set("uv", uv.ravel())
    # skin weights
    W = shape.weights_at(Vd)
    groups = {b: obj.vertex_groups.new(name=b) for b in rig_bones}
    by_bone: dict = {}
    for vi, w in enumerate(W):
        for b, x in w.items():
            by_bone.setdefault(b, {}).setdefault(round(x, 3), []).append(vi)
    for b, buckets in by_bone.items():
        g = groups.get(b)
        if g is None:
            continue
        for x, ids in buckets.items():
            g.add(ids, x, "REPLACE")
    for p in me.polygons:
        p.use_smooth = True
    log(f"  {shape.name}: final {len(me.vertices)} verts, {sum(len(p.vertices) - 2 for p in me.polygons)} tris")
    return obj


def _color_border(C: np.ndarray, F: np.ndarray) -> np.ndarray:
    """0..1: quanto a cor muda em volta de cada vértice (para preservar contornos)."""
    diff = np.zeros(len(C))
    for a, b in ((0, 1), (1, 2), (2, 3), (3, 0)):
        dc = np.abs(C[F[:, a]] - C[F[:, b]]).sum(axis=1)
        np.maximum.at(diff, F[:, a], dc)
        np.maximum.at(diff, F[:, b], dc)
    return np.clip(diff * 6.0, 0.0, 1.0)


def rigid_object(obj, bone: str, rig_bones: list[str], color=None):
    """Prende um objeto (peça dura feita com primitivas do Blender) a um único osso."""
    for b in rig_bones:
        if b not in obj.vertex_groups:
            obj.vertex_groups.new(name=b)
    obj.vertex_groups[bone].add(list(range(len(obj.data.vertices))), 1.0, "REPLACE")
    if color is not None:
        me = obj.data
        lin = [srgb_to_linear(c) for c in color[:3]] + [1.0 if len(color) < 4 else color[3]]
        attr = me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
        attr.data.foreach_set("color", lin * len(me.vertices))
        me.color_attributes.active_color = attr
    return obj
