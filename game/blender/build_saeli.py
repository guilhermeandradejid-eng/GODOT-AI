"""SOPRO — SAELI, a sprite-vela (heroína ágil, 0,93 m). Design: game/design/herois.md.

    blender -b --factory-startup --python game/blender/build_saeli.py [-- --fast] [--noanim] [--out X.glb]

Saída: game/assets/characters/saeli.glb (armature + malha única com skin + animações)
e game/blender/saeli.blend (fonte editável).

Modelagem por campos de distância (lib/sdfkit.py). Cada Shape vira uma peça com um material;
as bordas de cor importantes são ARESTAS geométricas (placas finas que acompanham a superfície),
então ficam nítidas mesmo com ~9k triângulos:
    SaeliHead      skin  crânio, testa, bochechas de feijão, focinho, pálpebras inferiores, bases das orelhas
    SaeliFace      skin  placa marfim da máscara-coração (+ linha dos cílios) e 2 chevrons na nuca
    SaeliFeatures  skin  nariz-botão, sobrancelhas índigo e sorriso (traço escuro em relevo)
    SaeliGems      glow  sardas: 3 contas luminosas por bochecha no triângulo do Glifo de Rumo
    SaeliBody      skin  pescoço, tronco em gota, braços, mãos-luva, pernas, botas com punho, cauda
                         com 2 anéis índigo e prancha-folha (verso/borda marfim, quilha)
    SaeliMarks     skin  placa marfim da barriga e 3 chevrons dorsais índigo (Λ)
    SaeliDeck      skin  deck índigo da prancha
    SaeliVeins     glow  nervuras luminosas da prancha
    SaeliRibs      skin  10 costelas dos leques (marfim)
    SaeliMetal     metal punhos de latão, cubos dos leques (núcleo brilhante), contas das costelas
    SaeliFins      glow  membranas das orelhas-barbatana (borda recortada, ponta luminosa)
    SaeliFinRays   skin  3 raios marfim por orelha
    SaeliFans      glow  membranas dos leques em SDF (4 painéis por braço, prega em tenda, borda
                         recortada); peso angular linear entre costelas vizinhas -> o leque dobra
    Eye_L/R        eye   olhos (UV frontal para o shader de olho)
Rest pose: braços ~49° abaixo da horizontal com os leques ABERTOS. Fechar = girar as costelas em
volta da normal do leque; fechadas, as costelas também encolhem (escala no próprio eixo) e o leque
vira uma lâmina curta no dorso do antebraço. Animações: FK em eixos do mundo + IK de 2 ossos
(pés plantados, mãos na amurada/na prancha), CCD na cauda (surfe), giros em volta do centro de
massa, chaves por spline Catmull-Rom, 30 fps.
Iteração rápida só das animações: -- --reanim modelo.blend --out X.glb [--anims run,idle]

Convenção: Blender Z-up, personagem olhando para -Y, lado esquerdo em +X.
"""
from __future__ import annotations

import math
import sys
import time
from pathlib import Path

import bpy
import numpy as np
from mathutils import Euler, Matrix, Quaternion, Vector

LIB = Path(__file__).resolve().parent / "lib"
if str(LIB) not in sys.path:
    sys.path.insert(0, str(LIB))

import sdfchar  # noqa: E402
from bhelpers import log, reset_scene  # noqa: E402
from charkit import BoneDef, Rig, bake_action  # noqa: E402
from sdfkit import (Prim, Shape, capsule, cylinder, ellipsoid, hexcol, look_basis,  # noqa: E402
                    plane, round_cone, smax, smin, smoothstep, sphere, torus)

ROOT = Path(__file__).resolve().parents[2]
OUT_GLB = ROOT / "game" / "assets" / "characters" / "saeli.glb"
OUT_BLEND = ROOT / "game" / "blender" / "saeli.blend"

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
FAST = "--fast" in ARGS
NOANIM = "--noanim" in ARGS
if "--out" in ARGS:
    OUT_GLB = Path(ARGS[ARGS.index("--out") + 1])
    OUT_BLEND = Path(ARGS[ARGS.index("--blend") + 1]) if "--blend" in ARGS else None

# ----------------------------------------------------------------------------- palette
LAGOON = hexcol("17808E")      # pele
ABYSS = hexcol("0E5563")       # coroa / sombra / antebraço externo
IVORY = hexcol("F5ECD7")       # máscara-coração, barriga, palmas, solas, verso da prancha
INDIGO = hexcol("2B3A87")      # nariz, sobrancelhas, chevrons, botas, pontas, topo da prancha
GLASS = hexcol("4FE3D6")       # membranas
DEEPCYAN = hexcol("1FB5B0")    # membranas perto do cubo
PALEAQUA = hexcol("BDF7F0")    # bordas das membranas, ponta das orelhas
GLOW = hexcol("8FFFF2")        # sardas, núcleos dos cubos
BONE = hexcol("FFF6E6")        # costelas e raios das orelhas
BRASS = hexcol("D4A33F")
BRASS_D = hexcol("9A6A22")
STRIPE = hexcol("5EF2E6")      # nervura luminosa da prancha
MOUTH = hexcol("5A2340")
LASH = hexcol("123F55")        # contorno superior do olho
FIN_LO = hexcol("12707C")      # membranas perto do cubo / raiz das orelhas
FIN_MID = hexcol("178F98")     # membranas (corpo)
FIN_HI = hexcol("2BB9B6")      # membranas (perto da borda)
EDGE = hexcol("6FEDE3")        # borda luminosa
CROWN = hexcol("11707F")       # coroa (escurecimento sutil)

BIG = 1.0e3


def V3(*a) -> np.ndarray:
    if len(a) == 1:
        return np.asarray(a[0], dtype=np.float64)
    return np.asarray(a, dtype=np.float64)


def nrm(v) -> np.ndarray:
    v = np.asarray(v, dtype=np.float64)
    return v / (np.linalg.norm(v) + 1e-12)


def mx(p, sx: float) -> np.ndarray:
    """Espelha um ponto do lado esquerdo (+X) para o lado sx (+1 / -1)."""
    p = V3(p).copy()
    p[0] *= sx
    return p


# ============================================================================= rig
HIPS_H = V3(0, 0.010, 0.290)
SHOULDER_L = V3(0.092, 0.0, 0.508)
ELBOW_L = V3(0.168, -0.006, 0.420)
WRIST_L = V3(0.224, -0.020, 0.338)
HAND_TIP_L = V3(0.248, -0.040, 0.280)
HUB_L = V3(0.231, -0.010, 0.340)
HIP_L = V3(0.062, 0.006, 0.300)
KNEE_L = V3(0.070, -0.012, 0.165)
ANKLE_L = V3(0.070, 0.010, 0.060)
TOE_L = V3(0.070, -0.085, 0.020)
HEAD_C = V3(0, -0.025, 0.735)
HEAD_R = (0.190, 0.162, 0.166)
EYE_C_L = V3(0.075, -0.146, 0.737)
EYE_R = 0.052
EYE_SQ = (0.92, 1.12, 0.85)
EYE_FWD_L = V3(0.22, -1.0, 0.02)
FIN_ROOT_L = V3(0.128, 0.005, 0.818)
FIN_MID_L = V3(0.190, 0.095, 0.875)
FIN_TIP_L = V3(0.238, 0.212, 0.928)
TAIL_PTS = [V3(0, 0.080, 0.330), V3(0, 0.170, 0.310), V3(0, 0.255, 0.322), V3(0, 0.330, 0.352)]
BOARD_TAIL = V3(0, 0.647, 0.443)

FAN_OPEN = [14.0, 49.0, 84.0, 119.0, 154.0]     # ângulos das costelas (aberto), a partir de u
FAN_CLOSED = [14.0, 15.0, 16.0, 17.0, 18.0]     # fechado: escalonado 1° (sem z-fighting)
FAN_LEN = 0.21
FAN_FOLD = 0.50                                  # comprimento relativo das costelas fechadas


def fan_basis(sx: float):
    """(hub, u, v, n) do leque do lado sx. u: punho->cotovelo; v: ~+Y (para trás); n = u x v.
    Girar +phi em volta de n leva u em direção a v (abre o leque)."""
    E = mx(ELBOW_L, sx)
    W = mx(WRIST_L, sx)
    u = nrm(E - W)
    Y = V3(0, 1, 0)
    v = nrm(Y - (Y @ u) * u)
    n = np.cross(u, v)
    return mx(HUB_L, sx), u, v, n


def rib_dir(sx: float, theta: float) -> np.ndarray:
    hub, u, v, n = fan_basis(sx)
    t = math.radians(theta)
    return math.cos(t) * u + math.sin(t) * v


def make_rig() -> Rig:
    B = BoneDef
    t = lambda p: tuple(float(x) for x in p)  # noqa: E731
    bones = [
        B("hips", t(HIPS_H), (0, 0.0, 0.370)),
        B("spine", (0, 0.0, 0.370), (0, -0.004, 0.450), "hips"),
        B("chest", (0, -0.004, 0.450), (0, -0.010, 0.530), "spine"),
        B("neck", (0, -0.010, 0.530), (0, -0.016, 0.575), "chest"),
        B("head", (0, -0.016, 0.575), (0, -0.025, 0.900), "neck"),
    ]
    for s, sx in (("L", 1.0), ("R", -1.0)):
        ec = mx(EYE_C_L, sx)
        bones += [
            B(f"eye_{s}", t(ec), t(ec + V3(0.004 * sx, -0.040, 0.0)), "head"),
            B(f"earfin_{s}_1", t(mx(FIN_ROOT_L, sx)), t(mx(FIN_MID_L, sx)), "head"),
            B(f"earfin_{s}_2", t(mx(FIN_MID_L, sx)), t(mx(FIN_TIP_L, sx)), f"earfin_{s}_1"),
            B(f"upperarm_{s}", t(mx(SHOULDER_L, sx)), t(mx(ELBOW_L, sx)), "chest"),
            B(f"forearm_{s}", t(mx(ELBOW_L, sx)), t(mx(WRIST_L, sx)), f"upperarm_{s}"),
            B(f"hand_{s}", t(mx(WRIST_L, sx)), t(mx(HAND_TIP_L, sx)), f"forearm_{s}"),
        ]
        hub = mx(HUB_L, sx)
        for k in range(5):
            bones.append(B(f"fan_{s}_{k + 1}", t(hub), t(hub + FAN_LEN * rib_dir(sx, FAN_OPEN[k])), f"forearm_{s}"))
        bones += [
            B(f"thigh_{s}", t(mx(HIP_L, sx)), t(mx(KNEE_L, sx)), "hips"),
            B(f"shin_{s}", t(mx(KNEE_L, sx)), t(mx(ANKLE_L, sx)), f"thigh_{s}"),
            B(f"foot_{s}", t(mx(ANKLE_L, sx)), t(mx(TOE_L, sx)), f"shin_{s}"),
        ]
    bones += [
        B("tail_1", t(TAIL_PTS[0]), t(TAIL_PTS[1]), "hips"),
        B("tail_2", t(TAIL_PTS[1]), t(TAIL_PTS[2]), "tail_1"),
        B("tail_3", t(TAIL_PTS[2]), t(TAIL_PTS[3]), "tail_2"),
        B("board", t(TAIL_PTS[3]), t(BOARD_TAIL), "tail_3"),
    ]
    return Rig(bones)


# ============================================================================= fast shapes
class FShape(Shape):
    """Shape com campo avaliado por células (cada célula só avalia as primitivas cuja caixa
    a alcança) e pesos ajustáveis: overrides por região ou função própria."""
    CELL = 0.03

    def __init__(self, *a, **kw):
        super().__init__(*a, **kw)
        self.weight_overrides: list = []     # (prim, bone, soft)
        self.weight_fn = None

    def _ext(self):
        pad = max(0.02, 6.0 * self.voxel)
        out = []
        for kind, prim, k, _b, _c in self.items:
            if kind == "clip" or not np.all(np.abs(prim.lo) < 900):
                out.append((kind, prim, k, None, None))
            else:
                m = k + pad
                out.append((kind, prim, k, prim.lo - m, prim.hi + m))
        return out

    @staticmethod
    def _eval(P, ext, active=None):
        d = None
        for i, (kind, prim, k, _lo, _hi) in enumerate(ext):
            if active is not None and not active[i]:
                continue
            if d is None:
                if kind == "add":
                    d = prim(P)
                else:
                    d = np.full(len(P), BIG)
                continue
            di = prim(P)
            if kind == "add":
                d = smin(d, di, k)
            elif kind == "carve":
                d = smax(d, -di, k)
            else:
                d = smax(d, di, k)
        return d if d is not None else np.full(len(P), BIG)

    def field(self, P):
        ext = self._ext()
        n = len(P)
        if n < 30000:
            return self._eval(P, ext)
        cull = [i for i, e in enumerate(ext) if e[3] is not None]
        C = self.CELL
        lo = P.min(axis=0)
        ijk = np.floor((P - lo) / C).astype(np.int64)
        dims = ijk.max(axis=0) + 1
        lin = (ijk[:, 0] * dims[1] + ijk[:, 1]) * dims[2] + ijk[:, 2]
        order = np.argsort(lin, kind="stable")
        ls = lin[order]
        starts = np.flatnonzero(np.r_[True, ls[1:] != ls[:-1]])
        counts = np.diff(np.r_[starts, n])
        cells = ls[starts]
        ci = np.stack([cells // (dims[1] * dims[2]), (cells // dims[2]) % dims[1], cells % dims[2]], axis=1)
        clo = lo + ci * C
        chi = clo + C
        active = np.ones((len(cells), len(ext)), bool)
        if cull:
            plo = np.array([ext[i][3] for i in cull])
            phi = np.array([ext[i][4] for i in cull])
            ov = np.all((phi[None] >= clo[:, None]) & (plo[None] <= chi[:, None]), axis=2)
            active[:, cull] = ov
        keys = np.packbits(active, axis=1)
        _, first, inv = np.unique(keys, axis=0, return_index=True, return_inverse=True)
        inv = inv.ravel()
        cell_of_sorted = np.repeat(np.arange(len(cells)), counts)
        grp_sorted = inv[cell_of_sorted]
        o2 = np.argsort(grp_sorted, kind="stable")
        pts = order[o2]
        g_sorted = grp_sorted[o2]
        bnd = np.flatnonzero(np.r_[True, g_sorted[1:] != g_sorted[:-1]])
        bnd_end = np.r_[bnd[1:], n]
        out = np.empty(n)
        for b0, b1 in zip(bnd, bnd_end):
            ids = pts[b0:b1]
            g = g_sorted[b0]
            act = active[first[g]]
            if not act[[i for i, e in enumerate(ext) if e[0] == "add"]].any():
                out[ids] = BIG
            else:
                out[ids] = self._eval(P[ids], ext, act)
        return out

    def weights_at(self, V, max_influences: int = 4):
        if self.weight_fn is not None:
            return self.weight_fn(V)
        W = super().weights_at(V, max_influences)
        for prim, bone, soft in self.weight_overrides:
            a = smoothstep(soft * 0.5, -soft * 0.5, prim(V))
            for i in np.flatnonzero(a > 1e-3):
                ai = float(a[i])
                d = {b: w * (1.0 - ai) for b, w in W[i].items()}
                d[bone] = d.get(bone, 0.0) + ai
                W[i] = {b: w for b, w in d.items() if w > 0.004}
        return W


# ============================================================================= custom prims
def prim_fn(fn, lo, hi) -> Prim:
    return Prim(fn, lo, hi)


def everywhere() -> Prim:
    return Prim(lambda P: np.full(len(P), -1.0), (-1e3,) * 3, (1e3,) * 3)


def outside_sphere(c, r, side: float = 0.0) -> Prim:
    """Negativo FORA da esfera (pintura radial: 'tudo a partir do raio r'); com side=+1/-1
    vale só para aquele lado (x > 0 / x < 0), para não pintar a peça espelhada."""
    c = V3(c)
    if side == 0.0:
        return Prim(lambda P: r - np.linalg.norm(P - c, axis=1), (-1e3,) * 3, (1e3,) * 3)
    return Prim(lambda P: np.maximum(r - np.linalg.norm(P - c, axis=1), -side * P[:, 0]), (-1e3,) * 3, (1e3,) * 3)


def sd_polygon(x, y, verts) -> np.ndarray:
    """Distância assinada a um polígono 2D (Quilez), vetorizada."""
    vs = [np.asarray(v, dtype=np.float64) for v in verts]
    d = (x - vs[0][0]) ** 2 + (y - vs[0][1]) ** 2
    s = np.ones_like(x)
    nv = len(vs)
    j = nv - 1
    for i in range(nv):
        e = vs[j] - vs[i]
        wx = x - vs[i][0]
        wy = y - vs[i][1]
        t = np.clip((wx * e[0] + wy * e[1]) / (e @ e), 0.0, 1.0)
        bx = wx - e[0] * t
        by = wy - e[1] * t
        d = np.minimum(d, bx * bx + by * by)
        c1 = y >= vs[i][1]
        c2 = y < vs[j][1]
        c3 = e[0] * wy > e[1] * wx
        allc = c1 & c2 & c3
        nonec = (~c1) & (~c2) & (~c3)
        s = np.where(allc | nonec, -s, s)
        j = i
    return s * np.sqrt(d)


def sd_capsule2(x, y, a, b, ra, rb) -> np.ndarray:
    """Cápsula 2D com raios diferentes (cone arredondado no plano)."""
    rc = round_cone((a[0], a[1], 0.0), (b[0], b[1], 0.0), ra, rb)
    return rc(np.stack([x, y, np.zeros_like(x)], axis=1))


def extrude2d(origin, e1, e2, sdf2d, half_t: float, rounding: float, pts2d, warp=None) -> Prim:
    """Forma 2D (no plano e1,e2 por origin) extrudada em n = e1 x e2, com bordas arredondadas."""
    o = V3(origin)
    e1 = nrm(e1)
    e2 = nrm(e2 - (e2 @ e1) * e1)
    n = np.cross(e1, e2)
    rr = min(rounding, half_t * 0.999)

    def f(P):
        q = P - o
        x = q @ e1
        y = q @ e2
        z = q @ n
        if warp is not None:
            z = z - warp(x, y)
        d2 = sdf2d(x, y) + rr
        dz = np.abs(z) - half_t + rr
        return (np.minimum(np.maximum(d2, dz), 0.0)
                + np.sqrt(np.maximum(d2, 0.0) ** 2 + np.maximum(dz, 0.0) ** 2) - rr)
    pts = np.array(pts2d, dtype=np.float64)
    corners = []
    for px, py in pts:
        for hz in (-1.0, 1.0):
            corners.append(o + px * e1 + py * e2 + hz * (half_t + 0.02) * n)
    corners = np.array(corners)
    return Prim(f, corners.min(axis=0) - 0.01, corners.max(axis=0) + 0.01)


def heart_prim(lobe_c, lobe_r, tip_c, tip_r, y_cut, k=0.008) -> Prim:
    """Máscara-coração projetada ao longo de Y (só a metade da frente)."""
    lc = (lobe_c[0], 0.0, lobe_c[1])
    tc = (tip_c[0], 0.0, tip_c[1])
    rc = round_cone(lc, tc, lobe_r, tip_r)
    lob = sphere(lc, lobe_r)

    def f(P):
        Q = np.stack([np.abs(P[:, 0]), np.zeros(len(P)), P[:, 2]], axis=1)
        d2 = smin(lob(Q), rc(Q), k)
        return np.maximum(d2, P[:, 1] - y_cut)
    return Prim(f, (-0.3, -0.4, 0.4), (0.3, y_cut, 1.0))


def plate(base, region: Prim, lift: float = 0.0018, sink: float = 0.0016, k: float = 0.0018) -> Prim:
    """Placa fina que acompanha a superfície de 'base' (de -sink a +lift) dentro de 'region':
    a borda da cor vira uma aresta geométrica (nítida mesmo com poucos triângulos)."""
    def f(P):
        d = base(P)
        shell = np.maximum(d - lift, -d - sink)
        return smax(shell, region(P), k)
    return Prim(f, region.lo, region.hi)


def tight(prim: Prim, lo, hi) -> Prim:
    return Prim(prim.fn, lo, hi)


def surf_hit(field, origin, direction, t1: float = 0.5, steps: int = 400) -> np.ndarray:
    """Primeiro ponto da superfície ao longo de um raio (marcha + bisseção)."""
    o = V3(origin)
    d = nrm(direction)
    ts = np.linspace(0.0, t1, steps)
    f = field(o[None, :] + ts[:, None] * d[None, :])
    idx = np.flatnonzero((f[:-1] > 0.0) & (f[1:] <= 0.0))
    if len(idx) == 0:
        raise RuntimeError(f"surf_hit: sem superfície a partir de {origin} {direction}")
    a, b = ts[idx[0]], ts[idx[0] + 1]
    for _ in range(40):
        m = 0.5 * (a + b)
        if field((o + m * d)[None, :])[0] > 0.0:
            a = m
        else:
            b = m
    return o + 0.5 * (a + b) * d


def field_n(field, p, eps: float = 0.0015) -> np.ndarray:
    p = V3(p)
    g = np.zeros(3)
    for i in range(3):
        e = np.zeros(3)
        e[i] = eps
        g[i] = field((p + e)[None])[0] - field((p - e)[None])[0]
    return nrm(g)


# ============================================================================= pieces
def eye_basis(sx: float) -> tuple[np.ndarray, np.ndarray]:
    """(centro, matriz local->mundo com colunas x, y, f) do olho, como sdfchar.eye_object."""
    c = mx(EYE_C_L, sx)
    f = nrm(mx(EYE_FWD_L, sx))
    up = V3(0, 0, 1)
    x = nrm(np.cross(up, f))
    y = nrm(np.cross(f, x))
    return c, np.stack([x, y, f], axis=1)


def eye_ellipsoid(sx: float, grow: float = 0.0) -> Prim:
    c, R = eye_basis(sx)
    radii = tuple(EYE_R * s + grow for s in EYE_SQ)
    return ellipsoid(c, radii, R)


def fin_frame():
    """Referencial da orelha-barbatana esquerda: origem na raiz, a = eixo (raiz->ponta),
    b = largura (positivo = borda de ataque, de cima), n = normal da face (para cima/fora)."""
    o = FIN_ROOT_L + V3(-0.008, 0.000, -0.008)
    a = nrm(FIN_TIP_L - FIN_ROOT_L)
    nz = V3(0.62, 0.0, 0.78)
    n = nrm(nz - (nz @ a) * a)
    b = np.cross(n, a)
    return o, a, b, n


FIN_LEN = 0.325


def fin_outline():
    """Polígono (s ao longo, w de través) + raios + recortes da borda de fuga."""
    L = FIN_LEN
    poly = [(-0.016, 0.044), (0.09, 0.058), (0.195, 0.047), (0.284, 0.022), (L, 0.002),
            (0.254, -0.045), (0.172, -0.067), (0.083, -0.074), (-0.016, -0.062)]
    rays = [((0.0, 0.007), (L - 0.010, 0.003)),
            ((0.0, -0.011), (0.250, -0.040)),
            ((0.0, -0.024), (0.169, -0.063))]
    tips = [(L, 0.002), (0.254, -0.045), (0.172, -0.067), (0.056, -0.076)]
    scallops = []
    for (ax, ay), (bx, by) in zip(tips[:-1], tips[1:]):
        mxp, myp = 0.5 * (ax + bx), 0.5 * (ay + by)
        ex, ey = bx - ax, by - ay
        c = 0.5 * math.hypot(ex, ey)
        nx, ny = ey / (2 * c), -ex / (2 * c)
        if ny > 0:
            nx, ny = -nx, -ny
        sag = 0.012
        R = (c * c + sag * sag) / (2 * sag)
        scallops.append(((mxp + nx * (R - sag), myp + ny * (R - sag)), R))
    return poly, rays, scallops


def fin_warp(x, y):
    """Leve concha: a borda de fuga curva para baixo e a ponta para cima."""
    return 0.12 * y * y * (x / FIN_LEN) + 0.05 * np.maximum(x - 0.15, 0.0) ** 2 - 0.10 * np.minimum(y, 0.0) ** 2


def fin_prims():
    """(origem, eixo, membrana, [raios]) da orelha esquerda."""
    o, a, b, n = fin_frame()
    poly, rays, scallops = fin_outline()

    def sdf2d(x, y):
        d = sd_polygon(x, y, poly) - 0.004
        for (cx, cy), R in scallops:
            d = np.maximum(d, R - np.hypot(x - cx, y - cy))
        return d

    bb = [(-0.03, 0.09), (FIN_LEN + 0.02, 0.09), (FIN_LEN + 0.02, -0.10), (-0.03, -0.10)]
    mem = extrude2d(o, a, b, sdf2d, 0.0042, 0.0040, bb, fin_warp)

    def pt(s_, w_):
        z = float(fin_warp(np.array([s_]), np.array([w_]))[0])
        return o + s_ * a + w_ * b + z * n
    ray_prims = []
    for (p0, p1), r0 in zip(rays, (0.0072, 0.0068, 0.0064)):
        pts = [pt(p0[0] + (p1[0] - p0[0]) * t, p0[1] + (p1[1] - p0[1]) * t) for t in (0.0, 0.3, 0.6, 0.85, 1.0)]
        rad = [r0, r0 * 0.92, r0 * 0.84, 0.0052, 0.0046]
        rp = None
        for i in range(len(pts) - 1):
            seg = round_cone(pts[i], pts[i + 1], rad[i], rad[i + 1])
            rp = seg if rp is None else rp.union(seg, 0.003)
        ray_prims.append(rp)
    return o, a, mem, ray_prims


def leaf_frame():
    o = TAIL_PTS[3].copy()
    e1 = nrm(BOARD_TAIL - TAIL_PTS[3])
    e2 = V3(-1.0, 0.0, 0.0)
    n = np.cross(e1, nrm(e2 - (e2 @ e1) * e1))
    return o, e1, e2, n


BOARD_LEN = 0.330


def leaf_warp(x, y):
    """Nariz levemente levantado e borda em concha (prancha)."""
    return 0.30 * np.maximum(x - 0.22, 0.0) ** 2 + 0.30 * y * y


LEAF_CAPS = [((-0.004, 0.0), (0.048, 0.0), 0.022, 0.055), ((0.048, 0.0), (0.138, 0.0), 0.055, 0.090),
             ((0.138, 0.0), (0.232, 0.0), 0.090, 0.068), ((0.232, 0.0), (BOARD_LEN - 0.006, 0.0), 0.068, 0.006)]


def leaf_sdf2d(x, y):
    d = None
    for a_, b_, ra, rb in LEAF_CAPS:
        di = sd_capsule2(x, y, a_, b_, ra, rb)
        d = di if d is None else smin(d, di, 0.05)
    return d


LEAF_HALF_T = 0.0125


def leaf_prim(grow: float = 0.0) -> Prim:
    o, e1, e2, n = leaf_frame()
    L = BOARD_LEN
    bb = [(-0.04, 0.11), (L + 0.02, 0.11), (L + 0.02, -0.11), (-0.04, -0.11)]
    return extrude2d(o, e1, e2, lambda x, y: leaf_sdf2d(x, y) - grow, LEAF_HALF_T + grow, 0.0108 + grow, bb, leaf_warp)


def leaf_top_region(inset: float) -> Prim:
    """Região 'de cima' da prancha, recuada da borda (para o deck índigo)."""
    o, e1, e2, n = leaf_frame()

    def f(P):
        q = P - o
        x = q @ e1
        y = q @ e2
        z = q @ n - leaf_warp(x, y)
        return np.maximum(leaf_sdf2d(x, y) + inset, -z)
    lp = leaf_prim(0.01)
    return Prim(f, lp.lo, lp.hi)


def leaf_point(s_, w_, h=0.0) -> np.ndarray:
    o, e1, e2, n = leaf_frame()
    z = float(leaf_warp(np.array([s_]), np.array([w_]))[0])
    return o + s_ * e1 + w_ * e2 + (z + h) * n


def fan_panel(sx: float, k: int, half_t: float = 0.0046, R: float = FAN_LEN + 0.003, depth: float = 0.020,
              pleat: float = 0.0042) -> Prim:
    """Painel de membrana entre as costelas k e k+1 (0-based) do lado sx: disco fino recortado
    pelos 2 planos das costelas, borda recortada (círculo) e prega (tenda ao longo do ângulo)."""
    hub, u, v, n = fan_basis(sx)
    th0 = math.radians(FAN_OPEN[k])
    th1 = math.radians(FAN_OPEN[k + 1])
    mid = 0.5 * (th0 + th1)
    ha = 0.5 * (th1 - th0)
    c0 = R * math.cos(ha) - R + depth
    Rs = (c0 * c0 + (R * math.sin(ha)) ** 2) / (2 * c0)
    D = R - depth + Rs
    scx, scy = D * math.cos(mid), D * math.sin(mid)
    sgn = 1.0 if k % 2 == 0 else -1.0
    s0, c0_, s1, c1_ = math.sin(th0), math.cos(th0), math.sin(th1), math.cos(th1)

    def f(P):
        q = P - hub
        a_ = q @ u
        b_ = q @ v
        h = q @ n
        r = np.sqrt(a_ * a_ + b_ * b_)
        th = np.arctan2(b_, a_)
        t = np.clip((th - th0) / (th1 - th0), 0.0, 1.0)
        tent = 1.0 - np.abs(2.0 * t - 1.0)
        h = h - sgn * pleat * np.clip(r / R, 0.0, 1.0) * tent
        d_disc = r - R
        d_w0 = a_ * s0 - b_ * c0_
        d_w1 = -a_ * s1 + b_ * c1_
        d_sc = Rs - np.hypot(a_ - scx, b_ - scy)
        d2 = np.maximum(np.maximum(d_disc, np.maximum(d_w0, d_w1)), d_sc)
        rr = half_t * 0.95
        d2r = d2 + rr
        dz = np.abs(h) - half_t + rr
        return (np.minimum(np.maximum(d2r, dz), 0.0)
                + np.sqrt(np.maximum(d2r, 0.0) ** 2 + np.maximum(dz, 0.0) ** 2) - rr)
    pts = [hub]
    for th in np.linspace(th0, th1, 7):
        pts.append(hub + R * (math.cos(th) * u + math.sin(th) * v))
    pts = np.array(pts)
    return Prim(f, pts.min(axis=0) - 0.02, pts.max(axis=0) + 0.02)


def fan_weight_fn(V):
    """Peso angular linear entre as costelas vizinhas (o painel dobra suavemente)."""
    out = []
    bases = {1.0: fan_basis(1.0), -1.0: fan_basis(-1.0)}
    for p in V:
        sx = 1.0 if p[0] >= 0.0 else -1.0
        side = "L" if sx > 0 else "R"
        hub, u, v, n = bases[sx]
        q = p - hub
        th = math.degrees(math.atan2(q @ v, q @ u))
        if th <= FAN_OPEN[0]:
            out.append({f"fan_{side}_1": 1.0})
            continue
        if th >= FAN_OPEN[-1]:
            out.append({f"fan_{side}_5": 1.0})
            continue
        for k in range(4):
            if FAN_OPEN[k] <= th <= FAN_OPEN[k + 1]:
                s_ = (th - FAN_OPEN[k]) / (FAN_OPEN[k + 1] - FAN_OPEN[k])
                d = {}
                if s_ < 0.999:
                    d[f"fan_{side}_{k + 1}"] = 1.0 - s_
                if s_ > 0.001:
                    d[f"fan_{side}_{k + 2}"] = s_
                tot = sum(d.values())
                out.append({b_: w / tot for b_, w in d.items()})
                break
    return out


# ============================================================================= shapes
def snapshot(shape: FShape):
    """Campo das peças já adicionadas (base para placas)."""
    t = FShape("tmp", shape.material, voxel=shape.voxel)
    t.items = list(shape.items)
    return t.field


def build_head(q: float):
    """Crânio, bochechas de feijão, focinho, nariz, sorriso esculpido, sobrancelhas, pálpebras
    inferiores, bases das orelhas (tudo rígido no osso head) + a placa marfim da máscara-coração
    e as sardas (contas luminosas)."""
    head = FShape("SaeliHead", "skin", voxel=0.0031 * q, tris=1440, color_soft=0.003, weight_sigma=0.02)
    head.add(ellipsoid(HEAD_C, HEAD_R), "head", LAGOON, k=0.0)
    head.add(ellipsoid(HEAD_C + V3(0, -0.016, 0.036), (0.180, 0.144, 0.114)), "head", LAGOON, k=0.045)
    head.add_mirrored(ellipsoid((0.094, -0.088, 0.682), (0.085, 0.066, 0.060)), "head", LAGOON, k=0.05)
    head.add(ellipsoid((0.0, -0.156, 0.674), (0.047, 0.034, 0.035)), "head", LAGOON, k=0.03)
    for sx in (1.0, -1.0):          # lower lids: the cheeks push up under the eyes
        c, R = eye_basis(sx)
        lid_c = c + R @ V3(0.004 * sx, -0.060, 0.008)
        head.add(ellipsoid(lid_c, (0.050, 0.020, 0.030), R), "head", LAGOON, k=0.03)
    fo, fa, _fb, fn = fin_frame()
    for sx in (1.0, -1.0):          # ear-fin bases
        c = mx(fo + 0.022 * fa - 0.006 * fn, sx)
        Rb = look_basis(mx(fa, sx), up=tuple(mx(fn, sx)))
        head.add(ellipsoid(c, (0.026, 0.017, 0.044), Rb), "head", LAGOON, k=0.028)
    for sx in (1.0, -1.0):          # eye sockets: open only above the lower-lid line
        c, R = eye_basis(sx)
        sock = eye_ellipsoid(sx, grow=0.0036).clip(plane(tuple(c + V3(0, 0, -0.042)), (0, 0, -1)), 0.012)
        head.carve(sock, k=0.006)
    base = snapshot(head)            # head volume without the small features
    # nose (indigo button on top of the muzzle) and brows (short ridges, inner end lower)
    nose_p = surf_hit(base, (0.0, -0.30, 0.692), (0, 1, 0))
    nose = ellipsoid(nose_p + V3(0, 0.0030, 0.002), (0.0195, 0.0125, 0.0135), (-12, 0, 0))
    brows = []
    for sx in (1.0, -1.0):
        pa = surf_hit(base, (0.040 * sx, -0.30, 0.812), (0, 1, 0))
        pm = surf_hit(base, (0.070 * sx, -0.30, 0.824), (0, 1, 0))
        pb = surf_hit(base, (0.100 * sx, -0.30, 0.823), (0, 1, 0))
        na, nm, nb_ = field_n(base, pa), field_n(base, pm), field_n(base, pb)
        brows.append(round_cone(pa + na * 0.0005, pm + nm * 0.0005, 0.0068, 0.0064).union(
            round_cone(pm + nm * 0.0005, pb - nb_ * 0.0005, 0.0064, 0.0046), 0.004))
    # smile: a crisp dark line on the plate (wider in the middle), little upturned corners
    smile = []
    for i in range(11):
        t = (i / 10.0) * 2.0 - 1.0
        p = surf_hit(base, (0.030 * t, -0.30, 0.652 + 0.0105 * t * t + 0.0025 * t ** 4), (0, 1, 0))
        smile.append(p + field_n(base, p) * 0.0006)
    sm = None
    for i in range(len(smile) - 1):
        w0 = 1 - abs((i / 10.0) * 2 - 1)
        w1 = 1 - abs(((i + 1) / 10.0) * 2 - 1)
        seg = round_cone(smile[i], smile[i + 1], 0.0026 + 0.0012 * w0, 0.0026 + 0.0012 * w1)
        sm = seg if sm is None else sm.union(seg, 0.0015)
    for sx, idx in ((1.0, -1), (-1.0, 0)):
        tip = smile[idx] + V3(0.0055 * sx, 0.0, 0.0060)
        sm = sm.union(round_cone(smile[idx], tip, 0.0026, 0.0024), 0.0015)
    head.detail(ellipsoid((0, -0.150, 0.700), (0.07, 0.06, 0.07)), 0.8)
    head.paint(plane(tuple(HEAD_C + V3(0, 0.035, 0.030)), (0, -0.55, -0.835)), CROWN, soft=0.15)   # countershading

    # ---- ivory heart plate (inset face mask)
    face = FShape("SaeliFace", "skin", voxel=0.0022 * q, tris=940, color_soft=0.0025, weight_sigma=0.02)
    lob_c, lob_r, tip_c, tip_r = (0.064, 0.757), 0.076, (0.0, 0.626), 0.011
    heart = heart_prim(lobe_c=lob_c, lobe_r=lob_r, tip_c=tip_c, tip_r=tip_r, y_cut=-0.060, k=0.006)
    heart = tight(heart, (-0.16, -0.25, tip_c[1] - tip_r - 0.012), (0.16, -0.055, lob_c[1] + lob_r + 0.012))
    face.add(plate(base, heart, lift=0.0019, sink=0.0040, k=0.0016), "head", IVORY, k=0.0)
    for sx in (1.0, -1.0):          # dense ring around the eye openings
        face.detail(Prim(lambda P, e=eye_ellipsoid(sx, grow=0.0036): np.abs(e(P)) - 0.004,
                         eye_ellipsoid(sx).lo - 0.02, eye_ellipsoid(sx).hi + 0.02), 0.9)
    for sx in (1.0, -1.0):          # upper lash line on the plate
        c, R = eye_basis(sx)
        lash = eye_ellipsoid(sx, grow=0.0064).clip(plane(tuple(c + V3(0, 0, 0.010)), (0, 0, -1)), 0.014)
        face.paint(lash, LASH, soft=0.0022)
    feat = FShape("SaeliFeatures", "skin", voxel=0.0015 * q, tris=320, color_soft=0.002, weight_sigma=0.02)
    feat.add(nose, "head", INDIGO, k=0.0)
    for brow in brows:
        feat.add(brow, "head", INDIGO, k=0.0)
    feat.add(sm, "head", MOUTH, k=0.0)
    # dorsal chevrons continue up the back of the head (follow-camera read)
    for zc, hl, th in ((0.672, 0.046, 0.0105), (0.752, 0.040, 0.0095)):
        reg = None
        for sx in (1.0, -1.0):
            bx = prim_box((0.030 * sx, 0.14, zc), (hl, 0.10, th), (0, 36 * sx, 0))
            reg = bx if reg is None else reg.union(bx, 0.0)
        reg = tight(reg, (-0.09, 0.02, zc - 0.07), (0.09, 0.25, zc + 0.07))
        face.add(plate(base, reg, lift=0.0019, sink=0.0040, k=0.0016), "head", INDIGO, k=0.0)
    face.cull_by = [head]
    face.cull_margin = 0.0005

    # ---- freckles: glowing beads in a triangle (apex up) = the Glifo de Rumo
    gems = FShape("SaeliGems", "glow", voxel=0.0016 * q, tris=200, color_soft=0.003, weight_sigma=0.02)
    for sx in (1.0, -1.0):
        for (fx, fz) in ((0.132, 0.684), (0.118, 0.659), (0.146, 0.659)):
            p = surf_hit(base, (fx * sx, -0.30, fz), (0, 1, 0))
            nrmv = field_n(base, p)
            gems.add(ellipsoid(p - nrmv * 0.0006, (0.0094, 0.0094, 0.0046), look_basis(nrmv)), "head", GLASS, k=0.0)
            gems.paint(sphere(p, 0.016), GLASS, soft=0.002, emission=1.0)

    gems.cull_by = [head]
    gems.cull_margin = 0.0005
    feat.cull_by = [face, head]
    feat.cull_margin = 0.0005
    head.cull_by = [face, gems, feat]
    head.cull_margin = 0.0009
    face.cull_by = [head, feat]
    return head, face, gems, feat


def torso_parts():
    return [
        (capsule((0, -0.006, 0.495), (0, -0.016, 0.610), 0.056), "neck", 0.0),
        (ellipsoid((0, 0.012, 0.330), (0.115, 0.102, 0.075)), "hips", 0.05),
        (ellipsoid((0, 0.002, 0.398), (0.127, 0.113, 0.090)), "spine", 0.06),
        (ellipsoid((0, -0.006, 0.474), (0.095, 0.086, 0.070)), "chest", 0.06),
    ]


def tail_point(u: float) -> np.ndarray:
    """Ponto ao longo da cauda (u = 0..3, um por segmento)."""
    i = min(int(u), 2)
    t = u - i
    return TAIL_PTS[i] + (TAIL_PTS[i + 1] - TAIL_PTS[i]) * t


TAIL_R = [0.044, 0.034, 0.027, 0.021]


def build_body(q: float):
    body = FShape("SaeliBody", "skin", voxel=0.0040 * q, tris=2450, color_soft=0.0035, weight_sigma=0.022)
    for prim, bone, k in torso_parts():
        body.add(prim, bone, LAGOON, k=k)
    torso = snapshot(body)
    # arms + mitten hands (finger nubs indigo-tipped)
    for sx in (1.0, -1.0):
        s = "L" if sx > 0 else "R"
        body.add(round_cone(mx(SHOULDER_L, sx), mx(ELBOW_L, sx), 0.039, 0.033), f"upperarm_{s}", LAGOON, k=0.03)
        body.add(round_cone(mx(ELBOW_L, sx), mx(WRIST_L, sx), 0.033, 0.030), f"forearm_{s}", LAGOON, k=0.010)
        hand_c = mx((0.239, -0.034, 0.300), sx)
        body.add(ellipsoid(hand_c, (0.040, 0.034, 0.045), (0, 0, -8 * sx)), f"hand_{s}", LAGOON, k=0.016)
        for fx, fz in ((0.221, 0.266), (0.239, 0.258), (0.257, 0.266)):
            body.add(ellipsoid(mx((fx, -0.050, fz), sx), (0.0135, 0.0135, 0.021), (12, 0, 0)), f"hand_{s}", LAGOON, k=0.006)
    # legs: teal thighs, indigo boots (shin starts below the knee -> crisp crease) with a cuff
    for sx in (1.0, -1.0):
        s = "L" if sx > 0 else "R"
        K, A = mx(KNEE_L, sx), mx(ANKLE_L, sx)
        body.add(round_cone(mx(HIP_L, sx), K, 0.052, 0.042), f"thigh_{s}", LAGOON, k=0.045)
        b0 = K + (A - K) * 0.22
        body.add(round_cone(b0, A, 0.0405, 0.034), f"shin_{s}", INDIGO, k=0.008)
        cuff_c = K + (A - K) * 0.26
        body.add(torus(cuff_c, 0.0405, 0.0062, look_basis(A - K)), f"shin_{s}", INDIGO, k=0.003)
        body.add(ellipsoid(mx((0.072, -0.030, 0.026), sx), (0.052, 0.092, 0.038)), f"foot_{s}", INDIGO, k=0.026)
        for tx in (0.050, 0.072, 0.094):
            body.add(ellipsoid(mx((tx, -0.114, 0.022), sx), (0.0175, 0.022, 0.0185)), f"foot_{s}", INDIGO, k=0.008)
    # tail (two indigo bands) + leaf board
    for i in range(3):
        body.add(round_cone(TAIL_PTS[i], TAIL_PTS[i + 1], TAIL_R[i], TAIL_R[i + 1]), f"tail_{i + 1}", LAGOON,
                 k=0.04 if i == 0 else 0.012)
    for u_, bone in ((1.15, "tail_2"), (2.1, "tail_3")):
        c = tail_point(u_)
        i = min(int(u_), 2)
        rr = TAIL_R[i] + (TAIL_R[i + 1] - TAIL_R[i]) * (u_ - i)
        axis = TAIL_PTS[i + 1] - TAIL_PTS[i]
        body.add(torus(c, rr, 0.0058, look_basis(axis)), bone, INDIGO, k=0.002)
    body.add(leaf_prim(), "board", IVORY, k=0.026)
    keel = round_cone(leaf_point(0.03, 0.0, -0.011), leaf_point(0.28, 0.0, -0.0095), 0.0068, 0.0045)
    body.add(keel, "board", IVORY, k=0.006)
    body.clip(plane((0, 0, 0.0), (0, 0, -1)), k=0.0)       # flat soles
    # soft paints
    for sx in (1.0, -1.0):
        body.paint(ellipsoid(mx((0.210, 0.012, 0.372), sx), (0.028, 0.028, 0.058), (0, -34 * sx, 0)), ABYSS, soft=0.02)
        body.paint(ellipsoid(mx((0.220, -0.040, 0.288), sx), (0.020, 0.034, 0.038), (0, 0, -8 * sx)), IVORY, soft=0.008)
        for fx, fz in ((0.221, 0.266), (0.239, 0.258), (0.257, 0.266)):
            body.paint(sphere(mx((fx, -0.054, fz - 0.012), sx), 0.0140), INDIGO, soft=0.005)
    body.paint(plane((0, 0, 0.0025), (0, 0, 1)), IVORY, soft=0.002)                           # soles
    for sx in (1.0, -1.0):
        body.detail(sphere(mx((0.238, -0.040, 0.290), sx), 0.05), 0.35)

    # ---- raised marks: ivory belly plate, indigo dorsal chevrons, indigo board deck
    marks = FShape("SaeliMarks", "skin", voxel=0.0026 * q, tris=340, color_soft=0.003, weight_sigma=0.03)
    belly = ellipsoid((0, -0.088, 0.402), (0.074, 0.070, 0.104))
    marks.add(plate(torso, tight(belly, (-0.09, -0.2, 0.28), (0.09, -0.02, 0.52)), 0.0017, 0.0045, 0.0016),
              "spine", IVORY, k=0.0)
    for z, bone in ((0.372, "hips"), (0.420, "spine"), (0.468, "chest")):
        reg = None
        for sx in (1.0, -1.0):
            bx = prim_box((0.025 * sx, 0.105, z), (0.037, 0.050, 0.0088), (0, 35 * sx, 0))
            reg = bx if reg is None else reg.union(bx, 0.0)
        reg = tight(reg, (-0.075, 0.02, z - 0.06), (0.075, 0.2, z + 0.06))
        marks.add(plate(torso, reg, 0.0017, 0.0045, 0.0016), bone, INDIGO, k=0.0)
    deck = FShape("SaeliDeck", "skin", voxel=0.0028 * q, tris=200, color_soft=0.003, weight_sigma=0.03)
    deck.add(plate(leaf_prim(), leaf_top_region(0.0065), 0.0016, 0.0050, 0.0016), "board", INDIGO, k=0.0)
    for sh in (marks, deck):
        sh.cull_by = [body]
        sh.cull_margin = 0.0005
    body.cull_by = [marks, deck]
    body.cull_margin = 0.0009
    return body, marks, deck


def board_veins():
    """Nervuras luminosas da prancha (sobre o deck)."""
    h = LEAF_HALF_T + 0.0016
    out = []
    pts = [leaf_point(s_, 0.0, h) for s_ in np.linspace(0.02, 0.285, 6)]
    rr = np.linspace(0.0046, 0.0040, 6)
    mid = None
    for i in range(5):
        seg = round_cone(pts[i], pts[i + 1], rr[i], rr[i + 1])
        mid = seg if mid is None else mid.union(seg, 0.002)
    out.append(mid)
    for s0, w1 in ((0.075, 0.050), (0.137, 0.061), (0.199, 0.049)):
        for sg in (1.0, -1.0):
            p0 = leaf_point(s0, 0.0, h)
            pm = leaf_point(s0 + 0.028, sg * w1 * 0.55, h)
            p1 = leaf_point(s0 + 0.050, sg * w1, h)
            out.append(round_cone(p0, pm, 0.0041, 0.0040).union(round_cone(pm, p1, 0.0040, 0.0040), 0.002))
    return out


def build_shapes():
    q = 1.45 if FAST else 1.0
    head, face, gems, feat = build_head(q)
    body, marks, deck = build_body(q)
    veins = FShape("SaeliVeins", "glow", voxel=0.0026 * q, tris=200, color_soft=0.003, weight_sigma=0.03)
    for vein in board_veins():
        veins.add(vein, "board", STRIPE, k=0.0)
    veins.paint(everywhere(), STRIPE, soft=0.01, emission=0.8)
    veins.cull_by = [deck]
    veins.cull_margin = 0.0005
    shapes = [head, face, gems, feat, body, marks, deck, veins]

    # ------------------------------------------------------------------ fan ribs (skin, ivory)
    ribs = FShape("SaeliRibs", "skin", voxel=0.0026 * q, tris=420, color_soft=0.003, weight_sigma=0.010)
    for sx in (1.0, -1.0):
        s = "L" if sx > 0 else "R"
        hub, u, v, n = fan_basis(sx)
        for k in range(5):
            d = rib_dir(sx, FAN_OPEN[k])
            ribs.add(round_cone(hub + d * 0.010, hub + d * (FAN_LEN - 0.002), 0.0098, 0.0052), f"fan_{s}_{k + 1}", BONE, k=0.0)
    shapes.append(ribs)

    # ------------------------------------------------------------------ metal
    metal = FShape("SaeliMetal", "metal", voxel=0.0026 * q, tris=440, color_soft=0.003, weight_sigma=0.010)
    for sx in (1.0, -1.0):
        s = "L" if sx > 0 else "R"
        hub, u, v, n = fan_basis(sx)
        Rn = look_basis(n)
        metal.add(cylinder(hub, 0.0255, 0.0108, Rn, rounding=0.0055), f"forearm_{s}", BRASS, k=0.0)
        cuff_c = mx(WRIST_L, sx) + (mx(ELBOW_L, sx) - mx(WRIST_L, sx)) * 0.22
        metal.add(torus(cuff_c, 0.0290, 0.0064, look_basis(u)), f"forearm_{s}", BRASS, k=0.0)
        for side in (1.0, -1.0):
            metal.carve(torus(hub + n * side * 0.0108, 0.0172, 0.0026, Rn), k=0.0015, color=BRASS_D)
            metal.paint(sphere(hub + n * side * 0.0108, 0.0095), GLOW, soft=0.003, emission=0.9)
        for k in range(5):
            d = rib_dir(sx, FAN_OPEN[k])
            metal.add(sphere(hub + d * (FAN_LEN + 0.001), 0.0098), f"fan_{s}_{k + 1}", BRASS, k=0.0)
    shapes.append(metal)

    # ------------------------------------------------------------------ ear fins (glow)
    fins = FShape("SaeliFins", "glow", voxel=0.0024 * q, tris=560, color_soft=0.004, weight_sigma=0.03)
    frays = FShape("SaeliFinRays", "skin", voxel=0.0022 * q, tris=300, color_soft=0.003, weight_sigma=0.03)
    o, a, mem, rays = fin_prims()
    split = o + a * 0.135
    for sx in (1.0, -1.0):
        s = "L" if sx > 0 else "R"
        h1 = mem.clip(plane(tuple(split), tuple(a)))
        h2 = mem.clip(plane(tuple(split), tuple(-a)))
        p1, p2 = (h1, h2) if sx > 0 else (h1.mirrored(), h2.mirrored())
        fins.add(p1, f"earfin_{s}_1", LAGOON, k=0.0)
        fins.add(p2, f"earfin_{s}_2", LAGOON, k=0.0)
        for rp in rays:
            r1 = rp.clip(plane(tuple(split), tuple(a)))
            r2 = rp.clip(plane(tuple(split), tuple(-a)))
            if sx < 0:
                r1, r2 = r1.mirrored(), r2.mirrored()
            frays.add(r1, f"earfin_{s}_1", BONE, k=0.0)
            frays.add(r2, f"earfin_{s}_2", BONE, k=0.0)
    for sx in (1.0, -1.0):
        root = mx(o, sx)
        fins.paint(outside_sphere(root, 0.050, sx), FIN_LO, soft=0.06, emission=0.03)
        fins.paint(outside_sphere(root, 0.150, sx), FIN_MID, soft=0.08, emission=0.08)
        fins.paint(outside_sphere(root, 0.230, sx), FIN_HI, soft=0.05, emission=0.18)
        fins.paint(outside_sphere(root, 0.280, sx), EDGE, soft=0.02, emission=0.45)
    fins.cull_by = [frays]
    fins.cull_margin = 0.0008
    shapes += [fins, frays]

    # ------------------------------------------------------------------ fan membranes (glow)
    fans = FShape("SaeliFans", "glow", voxel=0.0026 * q, tris=860, color_soft=0.004, weight_sigma=0.02)
    for sx in (1.0, -1.0):
        s = "L" if sx > 0 else "R"
        for k in range(4):
            fans.add(fan_panel(sx, k), f"fan_{s}_{k + 1}", DEEPCYAN, k=0.0)
    for sx in (1.0, -1.0):
        hub = mx(HUB_L, sx)
        fans.paint(everywhere(), FIN_LO, soft=0.01, emission=0.05)
        fans.paint(outside_sphere(hub, 0.110, sx), FIN_MID, soft=0.09, emission=0.10)
        fans.paint(outside_sphere(hub, 0.175, sx), FIN_HI, soft=0.05, emission=0.16)
        fans.paint(outside_sphere(hub, FAN_LEN - 0.010, sx), EDGE, soft=0.012, emission=0.45)
    fans.weight_fn = fan_weight_fn
    shapes.append(fans)
    return shapes


def prim_box(c, half, rot):
    from sdfkit import box
    return box(c, half, rot)


def build_eyes(bones):
    eyes = []
    for sx, s in ((1.0, "L"), (-1.0, "R")):
        eyes.append(sdfchar.eye_object(f"Eye_{s}", tuple(mx(EYE_C_L, sx)), EYE_R, tuple(mx(EYE_FWD_L, sx)),
                                       f"eye_{s}", bones, squash=EYE_SQ, segments=16, rings=12))
    return eyes


# ============================================================================= kinematics
class Kin:
    """Dados de repouso da armature para FK/IK."""

    def __init__(self, rig_obj):
        bones = rig_obj.data.bones
        self.names = [b.name for b in bones]
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in bones}
        self.rest = {b.name: b.matrix_local.copy() for b in bones}
        self.rrot = {n: m.to_quaternion() for n, m in self.rest.items()}
        self.head = {b.name: b.head_local.copy() for b in bones}
        self.tail = {b.name: b.tail_local.copy() for b in bones}
        self.length = {b.name: (b.tail_local - b.head_local).length for b in bones}
        self.rel = {}
        for b in bones:
            p = self.parent[b.name]
            self.rel[b.name] = self.rest[p].inverted() @ self.rest[b.name] if p else self.rest[b.name].copy()


def qw(x: float = 0.0, y: float = 0.0, z: float = 0.0) -> Quaternion:
    """Rotação em eixos do MUNDO (graus), ordem X, depois Y, depois Z."""
    return Euler((math.radians(x), math.radians(y), math.radians(z)), "XYZ").to_quaternion()


def qa(axis, deg: float) -> Quaternion:
    return Quaternion(Vector(tuple(float(c) for c in axis)).normalized(), math.radians(deg))


class Pose:
    def __init__(self, kin: Kin):
        self.k = kin
        self.rot: dict = {}
        self.loc: dict = {}
        self.scl: dict = {}
        self._W: dict = {}

    def _dirty(self):
        self._W = {}

    def basis(self, b) -> Matrix:
        T = Matrix.Translation(self.loc.get(b, Vector((0, 0, 0))))
        R = self.rot.get(b, Quaternion()).to_matrix().to_4x4()
        s = self.scl.get(b, Vector((1, 1, 1)))
        S = Matrix.Diagonal((s[0], s[1], s[2], 1.0))
        return T @ R @ S

    def world(self, b) -> Matrix:
        if b in self._W:
            return self._W[b]
        p = self.k.parent[b]
        W = (self.world(p) @ self.k.rel[b] if p else self.k.rest[b]) @ self.basis(b)
        self._W[b] = W
        return W

    def frame(self, b) -> Matrix:
        """Matriz do osso com base identidade (o 'referencial do pai' para este osso)."""
        p = self.k.parent[b]
        return self.world(p) @ self.k.rel[b] if p else self.k.rest[b].copy()

    def head(self, b) -> Vector:
        return self.world(b).translation.copy()

    def point(self, b, p_rest) -> Vector:
        """Posição atual de um ponto de repouso preso ao osso b."""
        return self.world(b) @ (self.k.rest[b].inverted() @ Vector(tuple(p_rest)))

    # ---- rotations ---------------------------------------------------------
    def turn(self, b, q: Quaternion):
        """Gira o osso por q em eixos do mundo de REPOUSO (acompanha o pai)."""
        r = self.k.rrot[b]
        ql = r.inverted() @ q @ r
        self.rot[b] = ql @ self.rot.get(b, Quaternion())
        self._dirty()

    def turn_world(self, b, q: Quaternion):
        """Gira o osso por q em eixos do mundo ATUAL (depois do movimento do pai)."""
        F = self.world(b).to_quaternion()
        Fp = self.frame(b).to_quaternion()
        target = q @ F
        self.rot[b] = Fp.inverted() @ target
        self._dirty()

    def set_world_rot(self, b, M3: Matrix):
        F = self.frame(b).to_3x3().normalized()
        self.rot[b] = (F.inverted() @ M3).to_quaternion()
        self._dirty()

    def aim(self, b, target_dir: Vector, twist_ref: Vector | None = None):
        """Aponta o eixo Y do osso para target_dir (giro mínimo a partir da pose atual)."""
        Wq = self.world(b).to_quaternion()
        cur = Wq @ Vector((0, 1, 0))
        dq = cur.rotation_difference(Vector(target_dir).normalized())
        self.turn_world(b, dq)

    def move(self, b, v_world):
        """Translada o osso (vetor no mundo de repouso)."""
        r = self.k.rrot[b]
        lv = r.inverted() @ Vector(tuple(v_world))
        self.loc[b] = self.loc.get(b, Vector((0, 0, 0))) + lv
        self._dirty()

    def scale(self, b, s):
        self.scl[b] = Vector(tuple(s))
        self._dirty()

    def root(self, q: Quaternion, pivot=(0.0, 0.0, 0.5), offset=(0.0, 0.0, 0.0)):
        """Gira o corpo inteiro (hips) por q em volta de 'pivot' e o desloca por 'offset' (mundo)."""
        H = self.k.head["hips"]
        C = Vector(tuple(pivot))
        t = Vector(tuple(offset)) + (C - H) - q @ (C - H)
        r = self.k.rrot["hips"]
        self.rot["hips"] = r.inverted() @ q @ r
        self.loc["hips"] = r.inverted() @ t
        self._dirty()

    # ---- IK --------------------------------------------------------------------
    def two_bone(self, b1, b2, target: Vector, pole: Vector, hinge_sign: float = 1.0):
        """IK de 2 ossos: b1 (coxa/braço) e b2 (canela/antebraço) até 'target' com joelho/cotovelo
        para o lado de 'pole'. Eixo X local = dobradiça."""
        A = self.head(b1)
        L1, L2 = self.k.length[b1], self.k.length[b2]
        d = Vector(target) - A
        dist = max(min(d.length, (L1 + L2) * 0.99995), abs(L1 - L2) + 1e-4)
        dn = d.normalized()
        a = (L1 * L1 - L2 * L2 + dist * dist) / (2 * dist)
        h = math.sqrt(max(L1 * L1 - a * a, 0.0))
        pole = Vector(pole)
        perp = pole - dn * pole.dot(dn)
        if perp.length < 1e-6:
            perp = Vector((0, -1, 0)) - dn * (-dn.y)
        perp.normalize()
        knee = A + dn * a + perp * h
        tgt = A + dn * dist
        hinge = perp.cross(dn).normalized() * hinge_sign
        ref = self.frame(b1).to_3x3().normalized() @ Vector((1, 0, 0))
        if hinge.dot(ref) < 0.0:
            hinge = -hinge
        for b, p0, p1 in ((b1, A, knee), (b2, knee, tgt)):
            Y = (p1 - p0).normalized()
            X = (hinge - Y * hinge.dot(Y)).normalized()
            Z = X.cross(Y)
            self.set_world_rot(b, Matrix((X, Y, Z)).transposed())
        return knee

    def export(self) -> dict:
        out = {}
        for b in set(self.rot) | set(self.loc) | set(self.scl):
            e = self.rot.get(b, Quaternion()).to_euler("XYZ")
            lv = self.loc.get(b)
            sv = self.scl.get(b)
            out[b] = (math.degrees(e.x), math.degrees(e.y), math.degrees(e.z),
                      tuple(lv) if lv is not None else None, tuple(sv) if sv is not None else None)
        return out


# ============================================================================= animation helpers
TAU = math.tau
K: Kin = None          # set in bake_all


def clamp01(x: float) -> float:
    return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)


def smooth(x: float) -> float:
    x = clamp01(x)
    return x * x * (3.0 - 2.0 * x)


def lerp(a, b, t):
    return a + (b - a) * t


def wv(ph: float, off: float = 0.0) -> float:
    return math.sin(TAU * (ph + off))


def cw(ph: float, off: float = 0.0) -> float:
    return math.cos(TAU * (ph + off))


def ease_out(x: float, p: float = 3.0) -> float:
    return 1.0 - (1.0 - clamp01(x)) ** p


def ease_in(x: float, p: float = 2.0) -> float:
    return clamp01(x) ** p


def spline(t: float, pts, periodic: bool = False, tension: float = 1.0):
    """Catmull-Rom (Hermite) pelas chaves [(t, valor), ...]; valor float ou tupla.
    periodic: a 1a e a última chave são o mesmo instante do laço (tangentes atravessam a emenda);
    caso contrário as pontas têm tangente zero (ease)."""
    ts = [float(q[0]) for q in pts]
    vs = [np.atleast_1d(np.asarray(q[1], dtype=np.float64)) for q in pts]
    n = len(ts)
    if periodic:
        T = ts[-1] - ts[0]
        t = ts[0] + (t - ts[0]) % T
    if t <= ts[0]:
        v = vs[0]
    elif t >= ts[-1]:
        v = vs[-1]
    else:
        i = 0
        while i < n - 2 and ts[i + 1] <= t:
            i += 1

        def tan(j):
            if 0 < j < n - 1:
                return (vs[j + 1] - vs[j - 1]) / (ts[j + 1] - ts[j - 1])
            if periodic:
                return (vs[1] - vs[-2]) / ((ts[1] - ts[0]) + (ts[-1] - ts[-2]))
            return vs[j] * 0.0
        h = ts[i + 1] - ts[i]
        u = (t - ts[i]) / h
        h00 = 2 * u ** 3 - 3 * u ** 2 + 1
        h10 = u ** 3 - 2 * u ** 2 + u
        h01 = -2 * u ** 3 + 3 * u ** 2
        h11 = u ** 3 - u ** 2
        v = h00 * vs[i] + h10 * h * tan(i) * tension + h01 * vs[i + 1] + h11 * h * tan(i + 1) * tension
    return float(v[0]) if v.size == 1 else tuple(float(x) for x in v)


def sxs(s: str) -> float:
    return 1.0 if s == "L" else -1.0


ARM_AX = {sx: nrm(mx(ELBOW_L, sx) - mx(SHOULDER_L, sx)) for sx in (1.0, -1.0)}
FORE_AX = {sx: nrm(mx(WRIST_L, sx) - mx(ELBOW_L, sx)) for sx in (1.0, -1.0)}
ELB_H = {sx: nrm(np.cross(FORE_AX[sx], V3(0, -1, 0))) for sx in (1.0, -1.0)}
FAN_N = {sx: fan_basis(sx)[3] for sx in (1.0, -1.0)}


def body(P, pitch=0.0, yaw=0.0, roll=0.0, pivot=(0.0, 0.0, 0.45), off=(0.0, 0.0, 0.0)):
    """Corpo inteiro (osso hips): pitch + = para a frente, roll + = tomba para a esquerda dela,
    yaw + = vira para a esquerda dela; em volta de 'pivot', deslocado por 'off' (mundo)."""
    P.root(qw(z=yaw) @ qw(y=roll) @ qw(x=pitch), pivot, off)


def spine(P, sp=(0, 0, 0), ch=(0, 0, 0), nk=(0, 0, 0), hd=(0, 0, 0)):
    """(pitch para a frente, inclina para a esquerda, vira para a esquerda) por osso."""
    for b, (x, y, z) in (("spine", sp), ("chest", ch), ("neck", nk), ("head", hd)):
        if x or y or z:
            P.turn(b, qw(x=x, y=y, z=z))


def arm(P, s, swing=0.0, out=0.0, twist=0.0, flex=0.0, ftwist=0.0, hand=(0.0, 0.0, 0.0)):
    """swing - = braço para a frente; out + = abre para o lado; flex + = dobra o cotovelo;
    twist/ftwist giram braço/antebraço no próprio eixo (simétricos entre os lados)."""
    sx = sxs(s)
    P.turn(f"upperarm_{s}", qw(x=swing) @ qw(y=-sx * out) @ qa(ARM_AX[sx], sx * twist))
    P.turn(f"forearm_{s}", qa(ELB_H[sx], flex) @ qa(FORE_AX[sx], sx * ftwist))
    hx, hy, hz = hand
    if hx or hy or hz:
        P.turn(f"hand_{s}", qw(x=hx, y=-sx * hy, z=sx * hz))


def fan(P, s, open01: float, flutter: float = 0.0, wobble: float = 0.0):
    """Abre o leque (0 fechado .. 1 aberto, >1 = overshoot). flutter/wobble: tremor da costela 5
    no plano / fora do plano (graus)."""
    sx = sxs(s)
    n = FAN_N[sx]
    # folded fans retract along the forearm (ribs telescope), so the closed blade never
    # sticks out past the elbow; they reach full length by ~55% open
    length = lerp(FAN_FOLD, 1.0, smooth(max(open01, 0.0) / 0.55))
    for k in range(5):
        tgt = FAN_CLOSED[k] + (FAN_OPEN[k] - FAN_CLOSED[k]) * open01
        d = tgt - FAN_OPEN[k]
        if length < 0.999:
            P.scale(f"fan_{s}_{k + 1}", (1.0, length, 1.0))
        q = qa(n, d) if abs(d) > 1e-6 else Quaternion()
        if k >= 3 and (flutter or wobble):
            amt = 1.0 if k == 4 else 0.45
            th = tgt
            dk = rib_dir(sx, th)
            e = np.cross(n, dk)
            q = qa(n, flutter * amt) @ qa(e, wobble * amt) @ q
        if q != Quaternion():
            P.turn(f"fan_{s}_{k + 1}", q)


def fan_level(P, s, normal=(0.0, 0.0, 1.0), amount: float = 1.0):
    """Gira o antebraço no próprio eixo para o plano do leque ficar com a normal 'normal'
    (a membrana é igual dos dois lados: escolhe o menor giro)."""
    sx = sxs(s)
    b = f"forearm_{s}"
    W = P.world(b).to_3x3().normalized()
    R0 = K.rest[b].to_3x3().normalized()
    n_w = W @ (R0.transposed() @ Vector(tuple(FAN_N[sx])))
    a = W @ Vector((0, 1, 0))
    tgt = Vector(tuple(normal)).normalized()
    n_p = n_w - a * n_w.dot(a)
    t_p = tgt - a * tgt.dot(a)
    if n_p.length < 1e-6 or t_p.length < 1e-6:
        return
    n_p.normalize()
    t_p.normalize()
    if n_p.dot(t_p) < 0.0:
        t_p = -t_p
    ang = math.atan2(a.dot(n_p.cross(t_p)), n_p.dot(t_p))
    P.turn_world(b, qa(a, math.degrees(ang) * amount))


def ear(P, s, lift=0.0, flare=0.0, tip=0.0, twist=0.0):
    """lift + = levanta (orelha em pé), flare + = abre para fora, tip = segunda metade."""
    sx = sxs(s)
    P.turn(f"earfin_{s}_1", qw(x=lift, y=-sx * twist, z=-sx * flare))
    if tip:
        P.turn(f"earfin_{s}_2", qw(x=tip))


def ears(P, lift=0.0, flare=0.0, tip=0.0, twist=0.0, diff=0.0):
    ear(P, "L", lift + diff, flare, tip, twist)
    ear(P, "R", lift - diff, flare, tip, twist)


def tail(P, lift=(0.0, 0.0, 0.0), sway=(0.0, 0.0, 0.0), board=(0.0, 0.0, 0.0), roll=(0.0, 0.0, 0.0)):
    """lift + = sobe, sway + = para a direita dela (eixo Z), board = (x, y, z) da prancha."""
    for i in range(3):
        q = qw(x=lift[i], z=sway[i])
        if roll[i]:
            ax = nrm(TAIL_PTS[i + 1] - TAIL_PTS[i])
            q = q @ qa(ax, roll[i])
        P.turn(f"tail_{i + 1}", q)
    bx, by, bz = board
    if bx or by or bz:
        P.turn("board", qw(x=bx, y=by, z=bz))


def hips_q(P) -> Quaternion:
    return P.world("hips").to_quaternion() @ K.rrot["hips"].inverted()


FOOT_HEEL_Y = 0.050
FOOT_BALL_Y = -0.088


def foot(P, s, pos=(0.0, 0.0, 0.0), pitch=0.0, yaw=0.0, roll=0.0, pivot="ankle", knee_out=0.20,
         rel=False, pole=None):
    """Planta/posiciona o pé: pos = deslocamento (x para fora, y, z) do ponto-pivô em relação ao repouso
    (no mundo, ou no referencial do quadril se rel=True). pitch + = ponta para baixo (calcanhar sobe)."""
    sx = sxs(s)
    A0 = Vector(tuple(mx(ANKLE_L, sx)))
    if pivot == "ball":
        C0 = Vector((A0.x, FOOT_BALL_Y, 0.0))
    elif pivot == "heel":
        C0 = Vector((A0.x, FOOT_HEEL_Y, 0.0))
    else:
        C0 = A0.copy()
    Qf = qw(z=sx * yaw) @ qw(y=-sx * roll) @ qw(x=pitch)
    off = Vector((sx * pos[0], pos[1], pos[2]))
    Hq = hips_q(P)
    if rel:
        Cw = P.point("hips", tuple(C0 + off))
        Qf = Hq @ Qf
        A = Cw + Qf @ (A0 - C0)
    else:
        Cw = C0 + off
        A = Cw + Qf @ (A0 - C0)
    if pole is None:
        pole = Hq @ Vector((knee_out * sx, -1.0, 0.0))
    P.two_bone(f"thigh_{s}", f"shin_{s}", A, pole)
    M3 = (Qf.to_matrix() @ K.rest[f"foot_{s}"].to_3x3().normalized())
    P.set_world_rot(f"foot_{s}", M3)


def reach(P, s, target, pole):
    """IK do braço até 'target' (punho), cotovelo para o lado de 'pole'."""
    P.two_bone(f"upperarm_{s}", f"forearm_{s}", Vector(tuple(target)), Vector(tuple(pole)))


def stand_feet(P, spread=0.004, yaw=6.0, sink=0.0):
    for s in "LR":
        foot(P, s, (spread, 0.0, sink), yaw=yaw)


def ccd(P, chain, target: Vector, iters: int = 24):
    """IK por descida de coordenadas cíclica: leva a ponta da cadeia até 'target' (mundo)."""
    end = chain[-1]
    L = K.length[end]
    for _ in range(iters):
        for b in reversed(chain):
            tip = P.world(end) @ Vector((0, L, 0))
            h = P.head(b)
            v1 = tip - h
            v2 = target - h
            if v1.length < 1e-6 or v2.length < 1e-6:
                continue
            dq = v1.rotation_difference(v2)
            P.turn_world(b, dq)
        if ((P.world(end) @ Vector((0, L, 0))) - target).length < 0.002:
            break


def board_world(fwd: Vector, up: Vector) -> Matrix:
    """Orientação (eixos no mundo) do osso board para que a prancha aponte 'fwd' com o deck para 'up'."""
    o, e1, e2, n = leaf_frame()
    Yr = Vector(tuple(e1))
    nr = Vector(tuple(n))
    S = Matrix((Yr, nr, Yr.cross(nr))).transposed()
    Yb = fwd.normalized()
    upp = (up - Yb * up.dot(Yb)).normalized()
    T = Matrix((Yb, upp, Yb.cross(upp))).transposed()
    return (T @ S.transposed()) @ K.rest["board"].to_3x3().normalized()


# ============================================================================= clips
def c_idle(t, ph):
    P = Pose(K)
    br = cw(ph * 2.0)                       # 2 breaths per loop
    look = spline(t, [(0, 0), (0.45, 0), (0.80, 26), (1.30, 24), (1.62, -20), (2.15, -18), (2.55, 0), (3.0, 0)], True)
    nod = spline(t, [(0, 0), (0.80, -6), (1.30, -4), (1.62, 3), (2.15, 2), (2.55, 0), (3.0, 0)], True)
    tilt = spline(t, [(0, 0), (0.45, 0), (0.80, 6), (1.30, 8), (1.62, -4), (2.15, -6), (2.55, 0), (3.0, 0)], True)
    shift = spline(t, [(0, 0), (0.8, 0.006), (1.6, -0.005), (2.4, 0.0), (3.0, 0)], True)
    body(P, pitch=1.5 + 0.5 * br, roll=-shift * 120, off=(shift, 0.0, -0.010 + 0.003 * br))
    spine(P, sp=(0.6 * br, 0, look * 0.10), ch=(0.8 * br, -tilt * 0.15, look * 0.15),
          nk=(0, tilt * 0.3, look * 0.25), hd=(nod - 1.0 * br, tilt * 0.7, look * 0.5))
    stand_feet(P)
    # fan fidget: flick open (overshoot) and snap shut
    fo = spline(t, [(0, 0), (1.62, 0), (1.74, 0.46), (1.82, 0.36), (2.02, 0.38), (2.12, 0.0), (3.0, 0)])
    lift_arm = spline(t, [(0, 0), (1.55, 0), (1.74, 12), (2.02, 10), (2.25, 0), (3.0, 0)])
    for s in "LR":
        sx = sxs(s)
        arm(P, s, swing=-4 + 1.5 * br, out=2 + lift_arm + 1.0 * br, twist=-6, flex=22 + 2 * br + lift_arm * 0.8,
            hand=(4, 0, -6))
        fan(P, s, fo, flutter=2.0 * fo * wv(t * 8))
    perk = spline(t, [(0, 0), (0.80, 10), (1.30, 8), (1.62, 2), (2.15, 4), (2.55, 0), (3.0, 0)], True)
    curious = spline(t, [(0, 0), (1.45, 0), (1.62, 14), (2.0, 12), (2.3, 0), (3.0, 0)])
    ears(P, lift=perk + 2 * br, flare=8 + 3 * fo, tip=1.5 * cw(ph * 2, 0.15), diff=curious)
    # two board taps on the sand
    tap = spline(t, [(0, 0), (2.25, 0), (2.36, 1.0), (2.46, 0.25), (2.58, 1.0), (2.72, 0.0), (3.0, 0)])
    tail(P, lift=(-12 + 3 * br - 28 * tap, 2, 4 + 6 * tap), sway=(3 * wv(ph), 4 * wv(ph, -0.1), 4 * wv(ph, -0.2)),
         board=(-4 - 22 * tap, 0, 0))
    return P.export()


def loco(t, ph, walk: bool):
    """Ciclo de locomoção no lugar (pés plantados deslizando para trás no apoio)."""
    P = Pose(K)
    if walk:
        duty, stride, lift, bob, base, lean = 0.62, 0.20, 0.050, 0.011, 0.020, 5.0
        arm_amp, flex0, flex_amp, yaw_amp = 24.0, 22.0, 12.0, 7.0
    else:
        duty, stride, lift, bob, base, lean = 0.36, 0.44, 0.115, 0.0175, 0.030, 16.0
        arm_amp, flex0, flex_amp, yaw_amp = 46.0, 82.0, 14.0, 11.0
    mid_l = duty * 0.5
    z = -base + bob * math.cos(TAU * 2.0 * (ph - mid_l))
    if not walk:
        z = -base - bob * math.cos(TAU * 2.0 * (ph - mid_l))       # lowest at mid-stance (compression)
    sway = (0.012 if walk else 0.006) * math.cos(TAU * (ph - mid_l))
    pyaw = -yaw_amp * math.cos(TAU * ph)                            # left hip forward at left heel strike
    proll = (3.0 if walk else 2.0) * math.cos(TAU * (ph - mid_l))
    body(P, pitch=lean, yaw=pyaw, roll=-proll, pivot=(0, 0.01, 0.30), off=(sway, 0.0, z))
    if not walk:
        sq = 1.0 - 0.035 * math.cos(TAU * 2.0 * (ph - mid_l))
        P.scale("spine", (1.0 / math.sqrt(sq), sq, 1.0 / math.sqrt(sq)))
    spine(P, sp=(0.0, 0, -pyaw * 0.5), ch=(1.0 if walk else 2.0, proll * 0.5, -pyaw * 0.6),
          nk=(0, 0, 0), hd=(-lean * 0.7 + (1.5 if walk else 3.0) * math.cos(TAU * 2 * (ph - mid_l - 0.06)), -proll * 0.4, pyaw * 0.3))
    for s, off in (("L", 0.0), ("R", 0.5)):
        p = (ph + off) % 1.0
        if p < duty:                                                   # stance
            u = p / duty
            y = -stride * 0.5 + stride * u
            if walk:
                pitch = spline(u, [(0, -14), (0.18, 0), (0.70, 0), (1.0, 26)])
                piv = "heel" if u < 0.18 else ("ball" if u > 0.70 else "ankle")
            else:
                pitch = spline(u, [(0, 4), (0.3, 0), (0.62, 2), (1.0, 38)])
                piv = "ball"
            if piv == "ankle":
                foot(P, s, (0.004, y, 0.0), pitch=pitch, yaw=5, pivot="ankle")
            elif piv == "heel":
                foot(P, s, (0.004, y + (FOOT_HEEL_Y - 0.010), 0.0), pitch=pitch, yaw=5, pivot="heel")
            else:
                foot(P, s, (0.004, y + (FOOT_BALL_Y - 0.010), 0.0), pitch=pitch, yaw=5, pivot="ball")
        else:                                                          # swing
            u = (p - duty) / (1.0 - duty)
            if walk:
                y = spline(u, [(0, stride * 0.5 - 0.02), (0.5, 0.0), (1.0, -stride * 0.5)])
                zz = lift * math.sin(math.pi * u) ** 0.9
                pitch = spline(u, [(0, 26), (0.35, 12), (0.8, -6), (1.0, -14)])
                foot(P, s, (0.004, y, zz), pitch=pitch, yaw=5, pivot="ankle")
            else:
                y = spline(u, [(0, stride * 0.5), (0.25, stride * 0.40), (0.55, 0.0), (0.85, -stride * 0.5 + 0.02),
                               (1.0, -stride * 0.5)])
                zz = spline(u, [(0, 0.0), (0.25, lift * 1.05), (0.55, lift * 0.95), (0.85, 0.035), (1.0, 0.0)])
                pitch = spline(u, [(0, 38), (0.25, 62), (0.55, 30), (0.85, 4), (1.0, 4)])
                foot(P, s, (0.004, y, zz), pitch=pitch, yaw=4, pivot="ankle")
    lag = 0.03 if walk else 0.02
    for s, off in (("L", 0.0), ("R", 0.5)):
        sw = arm_amp * math.cos(TAU * (ph + off - lag))               # + = back when same-side leg is forward
        fwd = clamp01(-sw / arm_amp)
        arm(P, s, swing=sw - (6 if walk else 10), out=(6 if walk else 10) + (2 if walk else 6) * fwd,
            twist=-8, flex=flex0 + flex_amp * fwd, ftwist=0 if walk else -12, hand=(6, 0, -6))
        fan(P, s, 0.0)
    if walk:
        ears(P, lift=2 + 3 * math.cos(TAU * 2 * (ph - 0.12)), flare=8, tip=2 * math.cos(TAU * 2 * (ph - 0.2)))
        tail(P, lift=(-14 + 3 * math.cos(TAU * 2 * (ph - 0.1)), 0, 2),
             sway=(8 * wv(ph, -0.08), 7 * wv(ph, -0.18), 6 * wv(ph, -0.28)),
             board=(-8 + 3 * math.cos(TAU * 2 * (ph - 0.3)), 0, 4 * wv(ph, -0.35)))
    else:
        ears(P, lift=-10 + 4 * math.cos(TAU * 2 * (ph - 0.15)), flare=10, tip=-6 + 3 * math.cos(TAU * 2 * (ph - 0.25)))
        tail(P, lift=(-12 + 5 * math.cos(TAU * 2 * (ph - 0.12)), -2 + 4 * math.cos(TAU * 2 * (ph - 0.22)), -2),
             sway=(4 * wv(ph, -0.06), 4 * wv(ph, -0.16), 4 * wv(ph, -0.26)),
             board=(-12 + 6 * math.cos(TAU * 2 * (ph - 0.32)), 0, 3 * wv(ph, -0.3)))
    return P.export()


def c_walk(t, ph):
    return loco(t, ph, True)


def c_run(t, ph):
    return loco(t, ph, False)


def c_jump(t, ph):
    P = Pose(K)
    T = [0.0, 0.033, 0.067, 0.13, 0.20, 0.36]
    hz = spline(t, list(zip(T, [-0.006, -0.032, -0.040, 0.012, 0.030, 0.035])))
    pit = spline(t, list(zip(T, [2, 9, 11, 2, -4, 2])))
    body(P, pitch=pit, pivot=(0, 0.01, 0.30), off=(0, 0, hz))
    sq = spline(t, list(zip(T, [1.0, 0.94, 0.92, 1.09, 1.05, 1.0])))
    P.scale("spine", (1.0 / math.sqrt(sq), sq, 1.0 / math.sqrt(sq)))
    spine(P, sp=(spline(t, list(zip(T, [0, 6, 8, -4, -3, 2]))), 0, 0), ch=(spline(t, list(zip(T, [0, 4, 6, -5, -2, 2]))), 0, 0),
          hd=(spline(t, list(zip(T, [0, -4, -6, -10, -6, 0]))), 0, 0))
    # feet: on the ground until frame 3, then tuck
    fz = spline(t, list(zip(T, [0.0, 0.0, 0.0, 0.0, 0.04, 0.10])))
    fy = spline(t, list(zip(T, [0.0, 0.0, 0.0, 0.01, 0.03, 0.0])))
    fp = spline(t, list(zip(T, [0, 0, 0, 30, 34, 18])))
    for s in "LR":
        foot(P, s, (0.006, fy, fz), pitch=fp, yaw=5, pivot="ball" if t > 0.08 else "ankle")
    sw = spline(t, list(zip(T, [-6, 22, 34, -70, -110, -60])))
    out = spline(t, list(zip(T, [4, 8, 10, 30, 42, 46])))
    fl = spline(t, list(zip(T, [22, 30, 34, 20, 26, 34])))
    fo = spline(t, list(zip(T, [0, 0, 0, 0.0, 0.12, 0.22])))
    for s in "LR":
        arm(P, s, swing=sw, out=out, twist=-6, flex=fl, hand=(6, 0, -6))
        fan(P, s, fo)
    ears(P, lift=spline(t, list(zip(T, [0, -12, -16, 18, 14, 8]))), flare=spline(t, list(zip(T, [2, 0, 0, 6, 8, 6]))),
         tip=spline(t, list(zip(T, [0, -6, -8, 10, 6, 2]))))
    tail(P, lift=(spline(t, list(zip(T, [-4, -14, -26, -10, 10, 14]))), spline(t, list(zip(T, [4, -6, -12, 6, 10, 8]))), 6),
         board=(spline(t, list(zip(T, [4, -10, -22, 8, 14, 8]))), 0, 0))
    return P.export()


def fall_pose(P, t, ph, fo=0.30):
    body(P, pitch=-4 + 2 * wv(ph), pivot=(0, 0, 0.45), off=(0, 0, 0.02))
    spine(P, sp=(-2, 0, 0), ch=(-3 + 1.5 * wv(ph, 0.1), 0, 0), hd=(8 + 2 * wv(ph, 0.2), 0, 0))
    for s, o in (("L", 0.0), ("R", 0.5)):
        k = wv(ph, o)
        foot(P, s, (0.012, 0.012 + 0.025 * k, 0.07 + 0.025 * wv(ph, o + 0.25)), pitch=26 + 8 * k, yaw=6, rel=True)
    for s, o in (("L", 0.0), ("R", 0.25)):
        arm(P, s, swing=-22 + 6 * wv(ph, o), out=60 + 8 * wv(ph, o + 0.2), twist=-10, flex=32 + 6 * wv(ph, o + 0.3),
            hand=(8, 0, -8))
        fan_level(P, s, (0, 0.3, 1), amount=0.4)
        fan(P, s, fo + 0.03 * wv(ph * 2, o), flutter=2.0 * wv(ph * 4, o))
    ears(P, lift=14 + 4 * wv(ph * 2), flare=6, tip=6 + 4 * wv(ph * 2, 0.15))
    tail(P, lift=(18 + 4 * wv(ph, -0.1), 8 + 4 * wv(ph, -0.2), 6 + 3 * wv(ph, -0.3)),
         sway=(4 * wv(ph, 0.1), 4 * wv(ph, 0.0), 3 * wv(ph, -0.1)), board=(10 + 6 * wv(ph, -0.35), 0, 0))


def c_fall(t, ph):
    P = Pose(K)
    fall_pose(P, t, ph)
    return P.export()


def c_land(t, ph):
    P = Pose(K)
    T = [0.0, 0.033, 0.067, 0.12, 0.20, 0.30]
    hz = spline(t, list(zip(T, [0.0, -0.050, -0.062, -0.028, 0.004, -0.010])))
    pit = spline(t, list(zip(T, [-2, 10, 13, 6, 0, 1.5])))
    body(P, pitch=pit, pivot=(0, 0.01, 0.30), off=(0, 0, hz))
    sq = spline(t, list(zip(T, [1.0, 0.91, 0.90, 0.97, 1.02, 1.0])))
    P.scale("spine", (1.0 / math.sqrt(sq), sq, 1.0 / math.sqrt(sq)))
    spine(P, sp=(0, 0, 0), ch=(spline(t, list(zip(T, [-2, 6, 8, 3, 0, 0.8]))), 0, 0),
          hd=(spline(t, list(zip(T, [6, -2, -6, -2, 1, -1]))), 0, 0))
    for s in "LR":
        foot(P, s, (0.010, 0.0, 0.0), yaw=6)
    sw = spline(t, list(zip(T, [-20, -12, -2, -4, -5, -4])))
    out = spline(t, list(zip(T, [60, 34, 18, 8, 3, 2])))
    fl = spline(t, list(zip(T, [32, 40, 36, 26, 22, 22])))
    fo = spline(t, list(zip(T, [0.30, 0.10, 0.0, 0.0, 0.0, 0.0])))
    for s in "LR":
        arm(P, s, swing=sw, out=out, twist=-6, flex=fl, hand=(6, 0, -6))
        fan(P, s, fo)
    ears(P, lift=spline(t, list(zip(T, [14, -10, -18, -6, 4, 0]))), flare=2, tip=spline(t, list(zip(T, [6, -8, -10, 2, 2, 0]))))
    tail(P, lift=(spline(t, list(zip(T, [18, -8, -16, -10, -4, -6]))), spline(t, list(zip(T, [8, 0, -6, 2, 4, 4]))), 6),
         board=(spline(t, list(zip(T, [10, -8, -14, 0, 6, 4]))), 0, 0))
    return P.export()


def c_double_jump(t, ph):
    P = Pose(K)
    # open (2 frames) -> clap down -> forward tuck flip -> open into fall
    flip = 360.0 * smooth((t - 0.15) / 0.24) if t > 0.15 else 0.0
    T = [0.0, 0.067, 0.15, 0.22, 0.32, 0.42]
    tuck = spline(t, list(zip(T, [0.0, 0.0, 0.25, 1.0, 1.0, 0.2])))
    body(P, pitch=flip + spline(t, list(zip(T, [0, -8, 4, 10, 6, 0]))), pivot=(0, -0.01, 0.47),
         off=(0, 0, spline(t, list(zip(T, [0.0, 0.01, 0.03, 0.06, 0.05, 0.02])))))
    sq = spline(t, list(zip(T, [1.0, 1.04, 1.06, 0.96, 0.97, 1.0])))
    P.scale("spine", (1.0 / math.sqrt(sq), sq, 1.0 / math.sqrt(sq)))
    spine(P, sp=(10 * tuck, 0, 0), ch=(12 * tuck - 4 * (1 - tuck), 0, 0), hd=(14 * tuck, 0, 0))
    for s in "LR":
        foot(P, s, (0.02 * tuck + 0.006, lerp(0.01, -0.13, tuck), lerp(0.03, 0.20, tuck)),
             pitch=lerp(26, 40, tuck), yaw=6, rel=True)
    sw = spline(t, list(zip(T, [-40, -60, -10, -55, -55, -24])))
    out = spline(t, list(zip(T, [70, 118, 30, 18, 20, 66])))
    fl = spline(t, list(zip(T, [30, 14, 18, 86, 86, 32])))
    fo = spline(t, list(zip(T, [0.3, 1.08, 0.96, 0.15, 0.12, 0.30])))
    lv = spline(t, list(zip(T, [0.4, 0.8, 0.8, 0.0, 0.0, 0.4])))
    for s in "LR":
        arm(P, s, swing=sw, out=out, twist=-8, flex=fl, hand=(8, 0, -8))
        fan_level(P, s, (0, 0.3, 1), amount=lv)
        fan(P, s, fo)
    ears(P, lift=spline(t, list(zip(T, [12, 20, 4, -24, -22, 12]))), flare=spline(t, list(zip(T, [6, 12, 4, -4, -4, 6]))),
         tip=spline(t, list(zip(T, [6, 10, -6, -12, -10, 6]))))
    tail(P, lift=(spline(t, list(zip(T, [16, 10, -10, -40, -36, 16]))), spline(t, list(zip(T, [8, 6, -10, -30, -28, 8]))),
                  spline(t, list(zip(T, [6, 4, -6, -20, -18, 6])))),
         board=(spline(t, list(zip(T, [10, 6, -10, -22, -20, 10]))), 0, 0))
    return P.export()


def c_glide(t, ph):
    P = Pose(K)
    bank = 6.0 * wv(ph)
    body(P, pitch=26 + 1.5 * wv(ph, 0.25), roll=bank, yaw=-2.0 * wv(ph, 0.1), pivot=(0, 0, 0.45), off=(0, 0, 0.03))
    spine(P, sp=(2, -bank * 0.2, 0), ch=(-4, -bank * 0.3, 0), nk=(-6, 0, 0), hd=(-18, -bank * 0.4, bank * 0.3))
    for s in "LR":
        sx = sxs(s)
        dihedral = 6.0 + bank * sx * 0.6
        arm(P, s, swing=-8 + 1.5 * wv(ph, 0.3), out=49 + dihedral, twist=0, flex=6, hand=(0, 0, -4))
        fan_level(P, s, (0.0, 0.20, 1.0))
        fan(P, s, 1.0 + 0.02 * wv(ph, 0.2), flutter=3.0 * wv(ph * 7), wobble=4.5 * wv(ph * 7, 0.25))
    for s, o_ in (("L", 0.0), ("R", 0.5)):
        foot(P, s, (0.006, 0.15, 0.11 + 0.008 * wv(ph, o_)), pitch=58, yaw=4, rel=True)
    ears(P, lift=-18 + 2 * wv(ph * 2), flare=-4, tip=-8 + 3 * wv(ph * 3, 0.2))
    tail(P, lift=(-24, 0 + wv(ph, -0.1), -2), sway=(-bank * 0.6, -bank * 0.8, -bank), board=(-14, -bank * 1.2, 0))
    return P.export()


def c_spin(t, ph):
    P = Pose(K)
    a = -14.0 * smooth(t / 0.033) if t < 0.033 else 720.0 * ease_out((t - 0.033) / 0.31, 2.4) - 14.0 * (1.0 - smooth((t - 0.033) / 0.06))
    T = [0.0, 0.033, 0.10, 0.25, 0.34, 0.40]
    hop = spline(t, list(zip(T, [0.0, -0.012, 0.035, 0.040, 0.008, 0.0])))
    body(P, yaw=a, pitch=spline(t, list(zip(T, [2, 6, 2, 2, 4, 2]))), pivot=(0, 0, 0.0), off=(0, 0, hop))
    spine(P, ch=(0, 0, 0), hd=(-4, 0, -spline(t, list(zip(T, [0, 0, 10, 10, 4, 0])))))
    tk = spline(t, list(zip(T, [0.0, 0.2, 1.0, 1.0, 0.3, 0.0])))
    for s in "LR":
        foot(P, s, (0.004 + 0.006 * tk, 0.01 * tk, 0.05 * tk), pitch=20 * tk, yaw=6, rel=True)
    out = spline(t, list(zip(T, [2, 22, 50, 52, 24, 2])))
    fo = spline(t, list(zip(T, [0.0, 0.3, 1.06, 1.0, 0.25, 0.0])))
    for s in "LR":
        arm(P, s, swing=-8, out=out, twist=-10, flex=spline(t, list(zip(T, [22, 18, 6, 6, 16, 22]))), hand=(4, 0, -6))
        fan_level(P, s, (0, 0, 1), amount=smooth(fo))
        fan(P, s, fo)
    ears(P, lift=spline(t, list(zip(T, [0, 4, 12, 12, 6, 0]))), flare=spline(t, list(zip(T, [2, 8, 22, 22, 10, 2]))))
    tail(P, lift=(spline(t, list(zip(T, [-12, -10, -6, -6, -10, -12]))), 2, 2),
         sway=(spline(t, list(zip(T, [0, -6, -14, -14, -6, 0]))), -10 * tk, -8 * tk), board=(6 * tk, 0, 0))
    return P.export()


def c_surf(t, ph):
    """'Cometa': deitada de barriga na prancha-folha (que se desenrola: x1,4), peito erguido, cabeça
    à frente, orelhas para trás, braços à frente em V com os leques entreabertos, pernas esticadas
    para trás (solas para cima); a cauda curva por baixo (tail_1..3) até o talo da prancha."""
    P = Pose(K)
    bob = 0.005 * wv(ph * 2)
    roll = 3.0 * wv(ph)
    body(P, pitch=76 + 1.5 * wv(ph * 2, 0.1), roll=roll, pivot=(0, 0.002, 0.398),
         off=(0, 0.020, -0.228 + bob))
    spine(P, sp=(-4, 0, 0), ch=(-8 + 1.0 * wv(ph * 2, 0.2), -roll * 0.3, 0), nk=(-22, 0, 0),
          hd=(-30 + 2.0 * wv(ph * 2, 0.3), -roll * 0.5, 2.5 * wv(ph, 0.2)))
    belly = P.point("spine", (0.0, 0.002, 0.398))
    tail(P, lift=(-40, -55, -50), sway=(0, 0, 0))
    ccd(P, ["tail_1", "tail_2", "tail_3"], Vector((0.0, belly.y + 0.205, 0.040)))
    P.set_world_rot("board", board_world(Vector((0, -1.0, 0.02)), Vector((roll * 0.004, 0, 1))))
    P.scale("board", (1.75, 1.42, 1.30))
    # legs streaming back, soles up, little flutter kick
    for s, o_ in (("L", 0.0), ("R", 0.5)):
        k = wv(ph * 2, o_)
        foot(P, s, (0.030, 0.395, 0.050 + 0.018 * k), pitch=150 + 6 * k, yaw=-4,
             pole=Vector((0.25 * sxs(s), 0.0, -1.0)))
    # arms forward-out (superman V), fans a little open
    for s in "LR":
        sx = sxs(s)
        reach(P, s, (0.200 * sx, -0.300 + 0.008 * wv(ph, 0.3 * sx), 0.115 + 0.006 * wv(ph * 2, 0.2)),
              (sx * 0.9, 0.2, 1.0))
        fan_level(P, s, (0, 0, 1), amount=0.8)
        P.turn_world(f"hand_{s}", qw(x=-10))
        fan(P, s, 0.24 + 0.04 * wv(ph * 2, 0.1), flutter=2.5 * wv(ph * 4), wobble=3.0 * wv(ph * 4, 0.25))
    ears(P, lift=-28 + 3 * wv(ph * 2, 0.1), flare=-4, tip=-12 + 4 * wv(ph * 3, 0.25))
    return P.export()


def c_ride(t, ph):
    """No cesto do Hulvar (chão do cesto = origem; amurada ~0,23-0,25 m, raio ~0,2 m): ajoelhada,
    cintura para cima, antebraços apoiados na amurada da frente, olha em volta (contra-balanço);
    a cauda sobe e a prancha fica de pé atrás dela como uma vela (deck virado para trás)."""
    P = Pose(K)
    look = spline(t, [(0, 0), (0.3, 0), (0.65, 38), (1.05, 36), (1.35, -34), (1.75, -32), (2.0, 0)], True)
    bob = 0.005 * wv(ph * 2, 0.3)
    body(P, pitch=26, roll=-look * 0.04, yaw=look * 0.08, pivot=(0, 0.01, 0.30), off=(0, 0.045, -0.118 + bob))
    spine(P, sp=(-2, 0, look * 0.08), ch=(-4, 0, look * 0.12), nk=(-8, 0, look * 0.2),
          hd=(-14 + 2 * wv(ph * 2), look * 0.06, look * 0.45))
    for s in "LR":
        foot(P, s, (0.012, 0.070, 0.035), pitch=120, yaw=-8, pivot="ankle", pole=Vector((0.15 * sxs(s), -1.0, 0.2)))
    for s in "LR":
        sx = sxs(s)
        lean = 0.006 * wv(ph * 2, 0.3 + 0.1 * sx)
        reach(P, s, (0.085 * sx, -0.212, 0.262 + lean), (sx * 0.9, 0.35, -0.6))
        P.turn_world(f"hand_{s}", qw(x=62, z=-sx * 18))
        fan(P, s, 0.0)
    ears(P, lift=6 + 6 * (abs(look) / 38.0), flare=4, tip=2 * wv(ph * 2), diff=look * 0.15)
    tail(P, lift=(70, 12, 8 + 2 * wv(ph * 2, 0.2)), sway=(look * 0.05, look * 0.06, look * 0.06),
         board=(4 + 2 * wv(ph * 2, 0.4), 0, 0), roll=(55, 55, 55))
    return P.export()


def c_launch(t, ph):
    """Bola encolhida girando para a frente (1 volta por laço)."""
    P = Pose(K)
    body(P, pitch=360.0 * ph, pivot=(0, -0.01, 0.46), off=(0, 0, 0.02))
    spine(P, sp=(14, 0, 0), ch=(16, 0, 0), nk=(10, 0, 0), hd=(16, 0, 0))
    for s in "LR":
        foot(P, s, (0.030, -0.085, 0.235), pitch=55, yaw=8, rel=True)
    for s in "LR":
        arm(P, s, swing=-48, out=4, twist=-6, flex=104, ftwist=10, hand=(24, 0, 0))
        fan(P, s, 0.0)
    ears(P, lift=-28, flare=-8, tip=-14)
    tail(P, lift=(-62, -58, -50), board=(-48, 0, 0))
    return P.export()


def c_celebrate(t, ph):
    P = Pose(K)
    T = [0.0, 0.067, 0.24, 0.42, 0.52, 0.62, 0.95, 1.05, 1.15, 1.30, 1.60]
    hz = spline(t, list(zip(T, [0.0, -0.035, 0.105, 0.03, -0.040, 0.0, 0.0, -0.012, 0.0, 0.0, -0.008])))
    spin = 360.0 * smooth((t - 0.58) / 0.36) if t > 0.58 else 0.0
    arch = spline(t, list(zip(T, [0, 8, -10, -6, 10, 2, 0, -2, -10, -8, 1.5])))
    body(P, pitch=arch, yaw=spin, pivot=(0, 0, 0.0), off=(0, 0, hz))
    sq = spline(t, list(zip(T, [1.0, 0.93, 1.07, 1.02, 0.92, 1.0, 1.0, 0.97, 1.03, 1.0, 1.0])))
    P.scale("spine", (1.0 / math.sqrt(sq), sq, 1.0 / math.sqrt(sq)))
    spine(P, ch=(spline(t, list(zip(T, [0, 4, -6, -4, 4, 0, 0, 0, -6, -4, 0.8]))), 0, 0),
          hd=(spline(t, list(zip(T, [0, 0, -12, -8, 2, -4, -4, -2, -14, -10, -1]))), 0, 0))
    air = spline(t, list(zip(T, [0.0, 0.0, 1.0, 0.4, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0])))
    for s in "LR":
        foot(P, s, (0.008, 0.0, 0.0), yaw=6) if air < 0.02 else foot(P, s, (0.010, -0.02 * air, 0.06 * air),
                                                                      pitch=30 * air, yaw=6, rel=True)
    sw = spline(t, list(zip(T, [-4, 20, -150, -120, -20, -10, -10, -12, -160, -150, -4])))
    out = spline(t, list(zip(T, [2, 12, 40, 50, 30, 74, 74, 30, 40, 44, 2])))
    fl = spline(t, list(zip(T, [22, 30, 10, 14, 30, 8, 8, 26, 6, 8, 22])))
    fo = spline(t, list(zip(T, [0.0, 0.0, 1.08, 0.95, 0.2, 1.0, 1.0, 0.0, 1.1, 1.0, 0.0])))
    lv = spline(t, list(zip(T, [0, 0, 0.3, 0.3, 0, 1.0, 1.0, 0, 0.2, 0.2, 0])))
    for s in "LR":
        arm(P, s, swing=sw, out=out, twist=-8, flex=fl, hand=(6, 0, -8))
        if lv > 0.01:
            fan_level(P, s, (0, 0, 1), amount=lv)
        fan(P, s, fo, flutter=2.0 * fo * wv(t * 9))
    ears(P, lift=spline(t, list(zip(T, [0, -8, 22, 16, -6, 10, 10, 0, 24, 20, 0]))),
         flare=spline(t, list(zip(T, [2, 0, 12, 10, 2, 16, 16, 4, 14, 12, 2]))))
    wag = math.sin(TAU * t * 4.0) * spline(t, list(zip(T, [0, 0, 0, 0, 0, 0, 0, 0.6, 1.0, 1.0, 0])))
    tail(P, lift=(spline(t, list(zip(T, [-6, -16, 16, 10, -10, 8, 8, -4, 20, 18, -6]))), 6, 8),
         sway=(18 * wag, 16 * wag, 12 * wag), board=(spline(t, list(zip(T, [4, -10, 14, 8, -6, 6, 6, 0, 16, 14, 4]))), 0, 0))
    return P.export()


def c_hurt(t, ph):
    P = Pose(K)
    T = [0.0, 0.05, 0.12, 0.25, 0.45]
    body(P, pitch=spline(t, list(zip(T, [0, -18, -14, -6, -2]))), pivot=(0, 0.01, 0.30),
         off=(0, spline(t, list(zip(T, [0.0, 0.03, 0.05, 0.04, 0.03]))), spline(t, list(zip(T, [0.0, 0.01, -0.02, -0.03, -0.015])))))
    spine(P, ch=(spline(t, list(zip(T, [0, -8, -4, 2, 2]))), 0, 0),
          hd=(spline(t, list(zip(T, [0, -18, -6, 6, 4]))), spline(t, list(zip(T, [0, 6, 8, 4, 2]))), 0))
    for s in "LR":
        foot(P, s, (0.010, 0.0, 0.0), yaw=6)
    sw = spline(t, list(zip(T, [-4, -40, -30, -12, -8])))
    out = spline(t, list(zip(T, [2, 56, 40, 14, 6])))
    fl = spline(t, list(zip(T, [22, 60, 70, 46, 34])))
    for s in "LR":
        arm(P, s, swing=sw, out=out, twist=-6, flex=fl, hand=(10, 0, -8))
        fan(P, s, 0.0)
    ears(P, lift=spline(t, list(zip(T, [0, 10, -20, -28, -24]))), flare=spline(t, list(zip(T, [2, 10, -4, -8, -6]))),
         tip=spline(t, list(zip(T, [0, 8, -10, -14, -12]))))
    tail(P, lift=(spline(t, list(zip(T, [-6, 14, -10, -24, -20]))), spline(t, list(zip(T, [4, 10, -6, -12, -10]))), 6),
         board=(spline(t, list(zip(T, [4, 16, -6, -14, -10]))), 0, 0))
    return P.export()


CLIPS = [
    ("idle", 3.0, c_idle, True),
    ("walk", 0.8, c_walk, True),
    ("run", 0.48, c_run, True),
    ("jump", 0.36, c_jump, False),
    ("fall", 0.8, c_fall, True),
    ("land", 0.30, c_land, False),
    ("double_jump", 0.42, c_double_jump, False),
    ("glide", 1.2, c_glide, True),
    ("spin", 0.40, c_spin, False),
    ("surf", 1.0, c_surf, True),
    ("ride", 2.0, c_ride, True),
    ("launch", 0.5, c_launch, True),
    ("celebrate", 1.6, c_celebrate, False),
    ("hurt", 0.45, c_hurt, False),
]


def bake_all(rig_obj, kin, only=None):
    global K
    K = kin
    for name, length, fn, loop in CLIPS:
        if only and name not in only:
            continue
        act = bake_action(rig_obj, name, length, fn, loop=loop)
        start_at_zero(act)


def start_at_zero(act):
    """charkit.bake_action chaveia a partir do quadro 1, mas o exportador glTF amostra a partir do 0:
    o 1o quadro sairia duplicado (trava de 1 quadro em cada volta do laço e atraso de 1 quadro nas
    ações). Desloca as chaves para começarem no quadro 0."""
    last = 0.0
    for fc in act.fcurves:
        for kp in fc.keyframe_points:
            kp.co.x -= 1.0
            kp.handle_left.x -= 1.0
            kp.handle_right.x -= 1.0
            last = max(last, kp.co.x)
        fc.update()
    act.frame_range = (0.0, last)


# ============================================================================= main
def reanim(blend_path: str):
    """Itera só nas animações: abre um .blend já modelado, refaz as ações e exporta."""
    t0 = time.time()
    bpy.ops.wm.open_mainfile(filepath=blend_path)
    rig_obj = bpy.data.objects["Saeli"]
    body_obj = bpy.data.objects["SaeliMesh"]
    for act in list(bpy.data.actions):
        bpy.data.actions.remove(act)
    only = ARGS[ARGS.index("--anims") + 1].split(",") if "--anims" in ARGS else None
    bake_all(rig_obj, Kin(rig_obj), only)
    sdfchar.export(OUT_GLB, rig_obj, body_obj)
    log(f"Saeli: reanim {time.time() - t0:.1f}s")


def main():
    if "--reanim" in ARGS:
        reanim(ARGS[ARGS.index("--reanim") + 1])
        return
    t0 = time.time()
    reset_scene()
    rig = make_rig()
    shapes = build_shapes()
    deform = [b for b in rig.order if rig.bones[b].deform]
    eyes = build_eyes(deform)
    rig_obj, body_obj = sdfchar.assemble("Saeli", rig, shapes, extras=eyes)
    log(f"Saeli: modelo pronto em {time.time() - t0:.1f}s")
    kin = Kin(rig_obj)
    only = None
    if "--anims" in ARGS:
        only = ARGS[ARGS.index("--anims") + 1].split(",")
    if NOANIM:
        only = ["idle"]
    bake_all(rig_obj, kin, only)
    log(f"Saeli: animações prontas em {time.time() - t0:.1f}s")
    if OUT_BLEND is not None:
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(OUT_BLEND), compress=True)
    sdfchar.export(OUT_GLB, rig_obj, body_obj)
    log(f"Saeli: total {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()
