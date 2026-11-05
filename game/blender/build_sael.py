"""YLVAAR — SAEL, o menino do cachecol vermelho (herói ágil, ~1,0 m). Design: game/design/herois.md
(pedido do usuário: um menino de jaqueta marrom, cabelo castanho e cachecol vermelho esvoaçante;
"Vela e Casco": o cachecol é a vela, o Hulvar é o casco).

    blender -b --factory-startup --python game/blender/build_sael.py [-- --fast] [--model-only]
                                                                      [--out X.glb] [--blend X.blend]

Saída: game/assets/characters/sael.glb (armature + malha única com skin + animações)
e game/blender/sael.blend (fonte editável). Com --out, o .blend só sai se --blend for dado.
--model-only: só o modelo em repouso + uma pose estática "preview" (pontas do cachecol ao vento),
sem as animações do jogo (iteração rápida da modelagem). --fast: voxels maiores (rascunho).

Modelagem por campos de distância (lib/sdfkit.py). Cada Shape vira uma peça com um material;
as bordas de cor importantes são ARESTAS geométricas (placas finas que acompanham a superfície):
    SaelHead       skin   crânio, bochechas, queixo, nariz-botão, orelhas, pálpebras inferiores
    SaelFace       skin   linha das pálpebras superiores e sorriso (traços escuros em relevo)
    SaelBrows      hair   sobrancelhas grossas
    SaelHair       hair   capa + mechas grossas varridas pelo vento, franja, redemoinho
    SaelTuft       hair   topete de trás (ossos hair_B_1..2, balança com molas)
    SaelSkin       skin   pescoço e mãos (luva-mitene com polegar)
    SaelJacket     cloth  jaqueta curta de aviador (tronco, mangas)
    SaelPanels     cloth  placas escuras: ombros, barra, carcela; correia diagonal da prancha
    SaelShearling  cloth  gola e punhos de lã de carneiro (creme)
    SaelShirt      cloth  barra da camisa creme sob a jaqueta
    SaelLegs       cloth  calça índigo, botas marrom-escuras com sola caramelo
    SaelScarf      scarf  cachecol enrolado no pescoço (2 voltas) + nó atrás à direita
    SaelTail_L/R   scarf  pontas longas do cachecol: FITAS EXPLÍCITAS (anéis regulares) com peso
                          linear entre ossos vizinhos (scarf_L/R_1..7) -> dobram lisas, sem vincos
    SaelBoard      cloth  prancha de areia (madeira clara, pontas levantadas)
    SaelBoardMarks cloth  glifo índigo (anel + 3 pontos) e 2 alças (bindings) no deck
    SaelRim        metal  aro de latão da prancha
    SaelBrass      metal  botões, fivela da correia, broche do glifo no nó do cachecol
    Eye_L/R        eye    olhos (UV frontal para o shader de olho)
A prancha fica presa nas costas (osso board, filho de chest) e vai para baixo dos pés no surfe.
Animações: FK em eixos do mundo + IK de 2 ossos (pés plantados), CCD, splines Catmull-Rom, 30 fps.
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
import sdfkit  # noqa: E402
from bhelpers import log, material, reset_scene, select_only  # noqa: E402
from charkit import BoneDef, Rig, bake_action  # noqa: E402
from sdfkit import (Prim, Shape, blade, box, capsule, cylinder, ellipsoid, hexcol,  # noqa: E402
                    look_basis, plane, round_cone, smax, smin, smoothstep, sphere, srgb_to_linear, torus)

ROOT = Path(__file__).resolve().parents[2]
OUT_GLB = ROOT / "game" / "assets" / "characters" / "sael.glb"
OUT_BLEND = ROOT / "game" / "blender" / "sael.blend"

ARGS = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
FAST = "--fast" in ARGS
MODEL_ONLY = "--model-only" in ARGS
NOANIM = "--noanim" in ARGS
if "--out" in ARGS:
    OUT_GLB = Path(ARGS[ARGS.index("--out") + 1])
    OUT_BLEND = None
if "--blend" in ARGS:
    OUT_BLEND = Path(ARGS[ARGS.index("--blend") + 1])

# ----------------------------------------------------------------------------- palette
SKIN = hexcol("E6AC82")        # pele morena-clara quente
SKIN_LID = hexcol("D99A72")    # pele da pálpebra/sombra
SKIN_HAND = hexcol("DD9E74")   # mãos (um tom abaixo: não estouram no sol ao lado dos punhos creme)
BLUSH = hexcol("EE9478")       # rubor
EAR_IN = hexcol("D88A70")      # concha da orelha
HAIR = hexcol("4C3020")        # chocolate
HAIR_HI = hexcol("7A4E32")     # reflexo
HAIR_DK = hexcol("35211A")     # raiz / nuca
BROW = hexcol("3A2416")
LASH = hexcol("2A1810")        # linha da pálpebra superior
MOUTH = hexcol("5E2220")
JACKET = hexcol("7A4A2A")
JACKET_DK = hexcol("4E2E1A")
STRAP = hexcol("3A2418")
SHEARLING = hexcol("F2E3C6")
SHEAR_SH = hexcol("DCC8A4")    # lã na sombra (miolo dos tufos)
SHIRT = hexcol("EFE0C0")
TROUSERS = hexcol("2B3A87")
TROUSERS_DK = hexcol("223070")
BOOT = hexcol("3A2418")
BOOT_CUFF = hexcol("4E2E1A")
SOLE = hexcol("C8935A")
SCARF = hexcol("D6322B")
SCARF_SH = hexcol("9E1F1F")
BRASS = hexcol("D4A33F")
BRASS_D = hexcol("9A6A22")
WOOD = hexcol("E6C38F")
WOOD_DK = hexcol("C99A5E")
INDIGO = hexcol("2B3A87")

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
# Corpo = esqueleto da Saeli (mesmos nomes, hierarquia e comprimentos): os clipes dela valem para ele.
HIPS_H = V3(0, 0.010, 0.290)
SPINE_H = V3(0, 0.000, 0.370)
CHEST_H = V3(0, -0.004, 0.450)
NECK_H = V3(0, -0.010, 0.530)
HEAD_H = V3(0, -0.016, 0.575)
HEAD_TIP = V3(0, -0.025, 0.900)
SHOULDER_L = V3(0.092, 0.0, 0.508)
ELBOW_L = V3(0.168, -0.006, 0.420)
WRIST_L = V3(0.224, -0.020, 0.338)
HAND_TIP_L = V3(0.248, -0.040, 0.280)
HIP_L = V3(0.062, 0.006, 0.300)
KNEE_L = V3(0.070, -0.012, 0.165)
ANKLE_L = V3(0.070, 0.010, 0.060)
TOE_L = V3(0.070, -0.085, 0.020)

# A cabeça é modelada num "espaço de projeto" próprio (abaixo) e posta sobre o osso head por uma
# semelhança: P_mundo = HEAD_H + (P_proj - HEAD_BASE_D) * HS.
HEAD_BASE_D = V3(0, -0.010, 0.660)
HS = 1.03


def h2w(p) -> np.ndarray:
    return HEAD_H + (V3(p) - HEAD_BASE_D) * HS


# --- cabeça (ESPAÇO DE PROJETO; h2w() leva ao mundo)
HEAD_C = V3(0, -0.012, 0.822)          # crânio
HEAD_R = V3(0.158, 0.150, 0.152)
JAW_C = V3(0, -0.040, 0.742)
JAW_R = V3(0.126, 0.110, 0.084)
EYE_C_L = V3(0.066, -0.124, 0.790)
EYE_R = 0.046
EYE_SQ = (0.88, 1.16, 0.80)
EYE_FWD_L = V3(0.16, -1.0, 0.02)

# cachecol: nó atrás à direita do pescoço; 2 pontas longas (R = a de fora, mais longa)
KNOT_C = V3(-0.048, 0.062, 0.552)
N_SCARF = 7
TAIL_SPEC = {
    "R": dict(ctrl=[(-0.054, 0.068, 0.550), (-0.072, 0.215, 0.566), (-0.112, 0.335, 0.390), (-0.145, 0.420, 0.160)],
              length=0.70, width=0.100),
    "L": dict(ctrl=[(-0.042, 0.070, 0.542), (-0.040, 0.200, 0.548), (-0.026, 0.300, 0.370), (-0.005, 0.360, 0.170)],
              length=0.60, width=0.092),
}
SCARF_HALF_T = 0.0052

# prancha de areia nas costas (diagonal: ponta de cima atrás do ombro esquerdo dele)
BOARD_C = V3(0.0, 0.150, 0.448)
BOARD_ANG = 28.0
BOARD_LEN = 0.500
BOARD_HW = 0.090
BOARD_HALF_T = 0.0085


def board_frame():
    a = math.radians(BOARD_ANG)
    e1 = V3(math.sin(a), 0.0, math.cos(a))      # comprido (para o "nariz", em cima)
    e2 = V3(math.cos(a), 0.0, -math.sin(a))     # largura
    n = np.cross(e1, e2)                        # deck (para fora das costas, +Y)
    return BOARD_C.copy(), e1, e2, n


def bezier(ctrl, n: int = 400) -> np.ndarray:
    p0, p1, p2, p3 = (V3(c) for c in ctrl)
    t = np.linspace(0.0, 1.0, n)[:, None]
    return (1 - t) ** 3 * p0 + 3 * (1 - t) ** 2 * t * p1 + 3 * (1 - t) * t * t * p2 + t ** 3 * p3


def arclen(poly: np.ndarray) -> np.ndarray:
    return np.r_[0.0, np.cumsum(np.linalg.norm(np.diff(poly, axis=0), axis=1))]


def tail_curve(side: str):
    """Linha central da ponta do cachecol (polilinha densa) com o comprimento pedido."""
    spec = TAIL_SPEC[side]
    ctrl = [V3(c) for c in spec["ctrl"]]
    poly = bezier(ctrl)
    L0 = arclen(poly)[-1]
    k = spec["length"] / L0
    ctrl = [ctrl[0]] + [ctrl[0] + (c - ctrl[0]) * k for c in ctrl[1:]]
    poly = bezier(ctrl, 600)
    return poly, arclen(poly)


def at_s(poly, s_all, s):
    return np.stack([np.interp(s, s_all, poly[:, i]) for i in range(3)], axis=-1)


def tail_bones(side: str):
    """Cabeças/caudas dos ossos scarf_<side>_1..N (comprimentos iguais ao longo da fita)."""
    poly, s_all = tail_curve(side)
    L = s_all[-1]
    s0 = 0.030                                   # a cadeia começa onde a fita sai do nó
    ks = np.linspace(s0, L, N_SCARF + 1)
    return [at_s(poly, s_all, k) for k in ks], ks


def make_rig() -> Rig:
    B = BoneDef
    t = lambda p: tuple(float(x) for x in p)  # noqa: E731
    bones = [
        B("hips", t(HIPS_H), t(SPINE_H)),
        B("spine", t(SPINE_H), t(CHEST_H), "hips"),
        B("chest", t(CHEST_H), t(NECK_H), "spine"),
        B("neck", t(NECK_H), t(HEAD_H), "chest"),
        B("head", t(HEAD_H), t(HEAD_TIP), "neck"),
    ]
    for s, sx in (("L", 1.0), ("R", -1.0)):
        ec = h2w(mx(EYE_C_L, sx))
        bones += [
            B(f"eye_{s}", t(ec), t(ec + V3(0.004 * sx, -0.040, 0.0)), "head"),
            B(f"upperarm_{s}", t(mx(SHOULDER_L, sx)), t(mx(ELBOW_L, sx)), "chest"),
            B(f"forearm_{s}", t(mx(ELBOW_L, sx)), t(mx(WRIST_L, sx)), f"upperarm_{s}"),
            B(f"hand_{s}", t(mx(WRIST_L, sx)), t(mx(HAND_TIP_L, sx)), f"forearm_{s}"),
            # mitten fingers (one bone): curls around the item axis in the item clips
            B(f"fingers_{s}", t(mx(WRIST_L + HAND_DIR * 0.044, sx)), t(mx(WRIST_L + HAND_DIR * 0.086, sx)),
              f"hand_{s}"),
            B(f"thigh_{s}", t(mx(HIP_L, sx)), t(mx(KNEE_L, sx)), "hips"),
            B(f"shin_{s}", t(mx(KNEE_L, sx)), t(mx(ANKLE_L, sx)), f"thigh_{s}"),
            B(f"foot_{s}", t(mx(ANKLE_L, sx)), t(mx(TOE_L, sx)), f"shin_{s}"),
        ]
    hb = [h2w(p) for p in tuft_points()]
    bones += [
        B("hair_B_1", t(hb[0]), t(hb[1]), "head"),
        B("hair_B_2", t(hb[1]), t(hb[2]), "hair_B_1"),
    ]
    for side in ("L", "R"):
        pts, _ = tail_bones(side)
        for i in range(N_SCARF):
            par = "chest" if i == 0 else f"scarf_{side}_{i}"
            bones.append(B(f"scarf_{side}_{i + 1}", t(pts[i]), t(pts[i + 1]), par))
    o, e1, e2, n = board_frame()
    bones.append(B("board", t(o - e1 * 0.20), t(o + e1 * 0.20), "chest"))
    # attachment points for the items (NOT deforming; the game parents the item meshes to them)
    for s, sx in (("L", 1.0), ("R", -1.0)):
        gp = grip_point(sx)
        bones.append(B(f"grip_{s}", t(gp), t(gp + GRIP_AXIS * 0.07), f"hand_{s}", False))
    bs = V3(0.0, 0.112, 0.448)
    bones.append(B("back_slot", t(bs), t(bs + e1 * 0.10), "chest", False))
    for s, sx in (("L", 1.0), ("R", -1.0)):
        bl = mx(BELT_L, sx)
        bones.append(B(f"belt_{s}", t(bl), t(bl + V3(0, 0, -0.06)), "hips", False))
    return Rig(bones)


HAND_DIR = nrm(HAND_TIP_L - WRIST_L)
GRIP_AXIS = nrm(np.cross(V3(-1.0, 0.0, 0.0), HAND_DIR))     # thumb side: forward and a little up
BELT_L = V3(0.101, 0.006, 0.322)


def grip_point(sx: float) -> np.ndarray:
    """Centro da palma (por onde passa o eixo de um item segurado)."""
    return mx(WRIST_L + HAND_DIR * 0.034 + V3(-0.004, -0.004, 0.0), sx)


# ============================================================================= fast shapes
class FShape(Shape):
    """Shape com campo avaliado por células (cada célula só avalia as primitivas cuja caixa
    a alcança) e pesos ajustáveis: overrides por região ou função própria."""
    CELL = 0.03

    def __init__(self, *a, ao_group: str = "body", ao_strength: float = 0.45, **kw):
        super().__init__(*a, **kw)
        self.weight_overrides: list = []     # (prim, bone, soft)
        self.weight_fn = None
        self.ao_group = ao_group
        self.ao_strength = ao_strength

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
        adds = [i for i, e in enumerate(ext) if e[0] == "add"]
        for b0, b1 in zip(bnd, bnd_end):
            ids = pts[b0:b1]
            g = g_sorted[b0]
            act = active[first[g]]
            if not act[adds].any():
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


class XShape(FShape):
    """FShape modelada no espaço de projeto da cabeça e posta no mundo por h2w() (semelhança):
    campo, cores, emissão, pesos e detalhe são avaliados no espaço de projeto."""

    @staticmethod
    def _q(P):
        return HEAD_BASE_D + (P - HEAD_H) / HS

    def field(self, P):
        return super().field(self._q(P)) * HS

    def colors_at(self, V):
        return super().colors_at(self._q(V))

    def emission_at(self, V):
        return super().emission_at(self._q(V))

    def weights_at(self, V, max_influences: int = 4):
        return super().weights_at(self._q(V), max_influences)

    def detail_at(self, V):
        return super().detail_at(self._q(V))

    def bounds(self):
        lo, hi = super().bounds()
        return h2w(lo), h2w(hi)


# ============================================================================= custom prims
def everywhere() -> Prim:
    return Prim(lambda P: np.full(len(P), -1.0), (-1e3,) * 3, (1e3,) * 3)


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
            corners.append(o + px * e1 + py * e2 + hz * (half_t + 0.04) * n)
    corners = np.array(corners)
    return Prim(f, corners.min(axis=0) - 0.01, corners.max(axis=0) + 0.01)


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


def snapshot(shape: FShape):
    """Campo das peças já adicionadas (base para placas)."""
    t = FShape("tmp", shape.material, voxel=shape.voxel)
    t.items = list(shape.items)
    return t.field


def surface_line(field, pts_xz, y0: float = -0.30, lift: float = 0.0006):
    """Pontos da superfície vistos de frente (raio +Y) para cada (x, z)."""
    out = []
    for x, z in pts_xz:
        p = surf_hit(field, (x, y0, z), (0, 1, 0))
        out.append(p + field_n(field, p) * lift)
    return out


def stroke(pts, radii, k: float = 0.0015) -> Prim:
    pr = None
    for i in range(len(pts) - 1):
        seg = round_cone(pts[i], pts[i + 1], radii[i], radii[i + 1])
        pr = seg if pr is None else pr.union(seg, k)
    return pr


# ============================================================================= head
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


def hp(u, v, w, r=1.0) -> np.ndarray:
    """Ponto na direção (u, v, w) do espaço normalizado do crânio (esfera unitária = superfície);
    r = fator radial (1 = superfície do crânio, > 1 = para fora)."""
    d = nrm(V3(u, v, w))
    return HEAD_C + r * d * HEAD_R


def build_head(q: float):
    head = XShape("SaelHead", "skin", voxel=0.0030 * q, tris=1420, color_soft=0.003, weight_sigma=0.02,
                  ao_strength=0.40)
    head.add(ellipsoid(HEAD_C, HEAD_R), "head", SKIN, k=0.0)
    head.add(ellipsoid(JAW_C, JAW_R), "head", SKIN, k=0.05)
    head.add_mirrored(ellipsoid((0.084, -0.088, 0.738), (0.066, 0.058, 0.054)), "head", SKIN, k=0.045)   # cheeks
    head.add(ellipsoid((0.0, -0.104, 0.690), (0.046, 0.036, 0.032)), "head", SKIN, k=0.035)              # chin
    for sx in (1.0, -1.0):          # lower lids: the cheeks push up under the eyes
        c, R = eye_basis(sx)
        lid_c = c + R @ V3(0.002 * sx, -0.054, 0.006)
        head.add(ellipsoid(lid_c, (0.044, 0.016, 0.026), R), "head", SKIN, k=0.026)
    for sx in (1.0, -1.0):          # ears
        ec = mx((0.150, 0.004, 0.778), sx)
        Re = sdfkit.euler(0, 0, 18 * sx)
        head.add(ellipsoid(ec, (0.019, 0.030, 0.039), Re), "head", SKIN, k=0.012)
        head.carve(ellipsoid(ec + mx((0.013, -0.004, 0.0), sx), (0.009, 0.018, 0.025), Re), k=0.006, color=EAR_IN)
    for sx in (1.0, -1.0):          # eye sockets: open only above the lower-lid line
        c, R = eye_basis(sx)
        sock = eye_ellipsoid(sx, grow=0.0034).clip(plane(tuple(c + V3(0, 0, -0.036)), (0, 0, -1)), 0.012)
        head.carve(sock, k=0.006)
    base = snapshot(head)
    nose_p = surf_hit(base, (0.0, -0.30, 0.748), (0, 1, 0))
    head.add(ellipsoid(nose_p + V3(0, 0.0050, 0.002), (0.0175, 0.0128, 0.0138), (-16, 0, 0)), "head", SKIN, k=0.007)
    head.detail(ellipsoid((0, -0.130, 0.750), (0.10, 0.06, 0.09)), 0.7)
    for sx in (1.0, -1.0):
        head.paint(ellipsoid(mx((0.094, -0.116, 0.734), sx), (0.032, 0.030, 0.021)), BLUSH, soft=0.016)
    head.paint(ellipsoid(nose_p + V3(0, -0.008, 0.002), (0.011, 0.008, 0.009)), BLUSH, soft=0.010)

    # ---- face lines: upper lid line (with a small outer flick) + open smile (flush plates)
    face = XShape("SaelFace", "skin", voxel=0.0015 * q, tris=340, color_soft=0.002, weight_sigma=0.02,
                  ao_strength=0.0)
    for sx in (1.0, -1.0):
        c, R = eye_basis(sx)
        ring = eye_ellipsoid(sx, grow=0.0066).clip(plane(tuple(c + V3(0, 0, 0.008)), (0, 0, -1)), 0.012)
        flick_a = c + R @ V3(0.038 * sx, 0.024, 0.000)
        flick_b = c + R @ V3(0.045 * sx, 0.027, -0.004)
        ring = ring.union(round_cone(flick_a, flick_b, 0.0045, 0.0020), 0.003)
        ring = tight(ring, c - 0.09, c + 0.09)
        face.add(plate(base, ring, lift=0.0020, sink=0.0034, k=0.0012), "head", LASH, k=0.0)
    mz, mw, mh = 0.707, 0.0300, 0.0175

    def mouth_region(P):
        x = (P[:, 0] - 0.0015) / mw
        z = P[:, 2]
        top = mz + 0.0075 * x * x + 0.0012 * x
        ell = np.hypot(x, (z - top) / mh) - 1.0
        return np.maximum(np.maximum(ell * 0.014, z - top), P[:, 1] + 0.08)
    mouth = Prim(mouth_region, (-0.04, -0.25, 0.68), (0.04, -0.08, 0.74))
    face.add(plate(base, mouth, lift=0.0011, sink=0.0034, k=0.0010), "head", MOUTH, k=0.0)
    face.paint(ellipsoid((0.004, -0.16, mz - 0.0125), (0.015, 0.05, 0.0062)), hexcol("C65A55"), soft=0.003)
    face.detail(everywhere(), 0.5)

    # ---- brows: thick, the inner end a little lower (determined, friendly)
    brows = XShape("SaelBrows", "hair", voxel=0.0016 * q, tris=200, color_soft=0.002, weight_sigma=0.02,
                   ao_strength=0.0)
    for sx in (1.0, -1.0):
        pts = surface_line(base, [(0.028 * sx, 0.858), (0.062 * sx, 0.871), (0.098 * sx, 0.867)], lift=0.0012)
        brows.add(stroke(pts, [0.0084, 0.0092, 0.0058], 0.003), "head", BROW, k=0.0)

    face.cull_by = [head]
    face.cull_margin = 0.0005
    brows.cull_by = [head]
    brows.cull_margin = 0.0005
    head.cull_by = [face, brows]
    head.cull_margin = 0.0009
    return head, face, brows, base


# ============================================================================= hair
def hairline_prim() -> Prim:
    """Recorte da capa de cabelo: só existe acima de uma linha (elevação por azimute) que desce
    da testa (alta) para as têmporas e a nuca (baixa)."""
    A0, A1, A2 = 0.085, 0.50, 0.035

    def f(P):
        d = (P - HEAD_C) / HEAD_R
        r = np.linalg.norm(d, axis=1) + 1e-9
        el = np.arcsin(np.clip(d[:, 2] / r, -1.0, 1.0))
        az = np.arctan2(d[:, 0], -d[:, 1])
        h = A0 + A1 * np.cos(az) + A2 * np.cos(2.0 * az)
        return (h - el) * 0.155
    return Prim(f, (-1e3,) * 3, (1e3,) * 3)


def lock(path, radii, flat: float = 0.5, k: float = 0.004) -> Prim:
    """Mecha: lâmina afunilada pela polilinha (pontos hp(u, v, w, r)), achatada na direção
    radial do crânio (deita sobre a cabeça); cada segmento tem a sua normal."""
    pts = [hp(*q) for q in path]
    pr = None
    for i in range(len(pts) - 1):
        mid = 0.5 * (pts[i] + pts[i + 1])
        n = nrm(mid - HEAD_C)
        seg = blade([pts[i], pts[i + 1]], [radii[i], radii[i + 1]], flat=flat, normal=tuple(n))
        pr = seg if pr is None else pr.union(seg, k)
    return pr


# (u, v, w, r) paths: u = his left, v = back, w = up (normalized skull space); r = radial factor
# (the cap sits at ~1.09). Wind from the front: the locks start at the hairline, flow over the top
# and flick out at the back; the fringe falls over the forehead and sweeps to his right.
HAIR_LOCKS = [
    # top, swept back (tips fan out behind the head)
    ([(0.06, -0.72, 0.68, 1.10), (0.04, -0.20, 0.98, 1.20), (0.03, 0.42, 0.92, 1.21), (0.02, 0.86, 0.62, 1.30),
      (0.00, 1.00, 0.62, 1.62)], [0.044, 0.052, 0.050, 0.034, 0.004]),
    ([(0.40, -0.66, 0.62, 1.10), (0.42, -0.10, 0.92, 1.19), (0.38, 0.48, 0.80, 1.19), (0.40, 0.88, 0.40, 1.28),
      (0.48, 1.00, 0.36, 1.56)], [0.040, 0.048, 0.046, 0.030, 0.004]),
    ([(-0.34, -0.68, 0.62, 1.10), (-0.38, -0.06, 0.93, 1.19), (-0.36, 0.52, 0.78, 1.19), (-0.40, 0.88, 0.36, 1.27),
      (-0.50, 1.00, 0.28, 1.52)], [0.040, 0.048, 0.046, 0.030, 0.004]),
    ([(0.74, -0.42, 0.56, 1.09), (0.76, 0.12, 0.68, 1.15), (0.70, 0.62, 0.38, 1.16), (0.76, 0.80, 0.04, 1.42)],
     [0.034, 0.040, 0.030, 0.004]),
    ([(-0.74, -0.42, 0.56, 1.09), (-0.78, 0.14, 0.64, 1.15), (-0.70, 0.64, 0.34, 1.16), (-0.78, 0.80, -0.02, 1.40)],
     [0.034, 0.040, 0.030, 0.004]),
    # sides over the ears, sweeping back (tips behind the ears)
    ([(0.92, -0.30, 0.24, 1.07), (0.98, 0.18, 0.16, 1.10), (0.86, 0.58, -0.02, 1.13), (0.72, 0.80, -0.22, 1.32)],
     [0.030, 0.034, 0.026, 0.004]),
    ([(-0.92, -0.30, 0.24, 1.07), (-0.98, 0.18, 0.16, 1.10), (-0.86, 0.58, -0.02, 1.13), (-0.72, 0.80, -0.22, 1.32)],
     [0.030, 0.034, 0.026, 0.004]),
    # nape (points down and a little out)
    ([(0.00, 0.93, 0.14, 1.10), (0.00, 0.97, -0.22, 1.12), (0.02, 0.92, -0.50, 1.24)], [0.036, 0.028, 0.004]),
    ([(0.40, 0.86, 0.06, 1.10), (0.42, 0.88, -0.22, 1.12), (0.50, 0.80, -0.44, 1.22)], [0.032, 0.026, 0.004]),
    ([(-0.40, 0.86, 0.06, 1.10), (-0.42, 0.88, -0.25, 1.12), (-0.50, 0.80, -0.48, 1.22)], [0.032, 0.026, 0.004]),
    # sideburns in front of the ears
    ([(0.92, -0.33, 0.10, 1.07), (0.95, -0.31, -0.22, 1.06), (0.92, -0.28, -0.44, 1.07)], [0.020, 0.015, 0.003]),
    ([(-0.92, -0.33, 0.10, 1.07), (-0.95, -0.31, -0.22, 1.06), (-0.92, -0.28, -0.44, 1.07)], [0.020, 0.015, 0.003]),
    # fringe: a big lock that sweeps over the forehead to his right, a second one, a small left one
    ([(0.24, -0.62, 0.76, 1.12), (0.12, -0.88, 0.58, 1.21), (-0.16, -0.92, 0.50, 1.19), (-0.46, -0.80, 0.44, 1.13)],
     [0.040, 0.036, 0.024, 0.004]),
    ([(-0.06, -0.68, 0.74, 1.12), (-0.12, -0.90, 0.56, 1.18), (-0.22, -0.92, 0.42, 1.13)], [0.032, 0.024, 0.004]),
    ([(0.46, -0.64, 0.66, 1.11), (0.54, -0.78, 0.52, 1.15), (0.64, -0.70, 0.40, 1.11)], [0.028, 0.020, 0.004]),
    # cowlick on top (curls back)
    ([(0.06, -0.34, 0.95, 1.18), (0.10, -0.26, 1.00, 1.34), (0.18, -0.06, 1.00, 1.46), (0.26, 0.16, 0.96, 1.44)],
     [0.018, 0.014, 0.009, 0.004]),
]
TUFT_PATH = [(0.00, 0.50, 0.86, 1.12), (0.02, 0.84, 0.70, 1.34), (0.04, 0.98, 0.66, 1.70)]
TUFT_SIDE = [(0.34, 0.98, 0.56, 1.58), (-0.30, 0.98, 0.50, 1.56)]


def tuft_points():
    return [hp(*q) for q in TUFT_PATH]


def build_hair(q: float, head_base):
    hair = XShape("SaelHair", "hair", voxel=0.0030 * q, tris=1450, color_soft=0.004, weight_sigma=0.02,
                  ao_strength=0.45)
    hair.add(ellipsoid(HEAD_C, HEAD_R + 0.013), "head", HAIR, k=0.0)
    hair.add(ellipsoid(HEAD_C + V3(0, 0.016, 0.040), (0.148, 0.152, 0.136)), "head", HAIR, k=0.03)
    hair.clip(hairline_prim(), k=0.010)
    for path, radii in HAIR_LOCKS:
        hair.add(lock(path, radii, flat=0.46), "head", HAIR, k=0.007)
    # soft light on the top-front, darker roots at the nape
    hair.paint(ellipsoid(HEAD_C + V3(0.0, -0.07, 0.14), (0.12, 0.10, 0.06)), HAIR_HI, soft=0.05)
    hair.paint(plane(tuple(HEAD_C + V3(0, 0, -0.03)), (0, 0, 1)), HAIR_DK, soft=0.05)
    hair.cull_by = []
    hair.cull_margin = 0.002

    tuft = XShape("SaelTuft", "hair", voxel=0.0026 * q, tris=260, color_soft=0.004, weight_sigma=0.03,
                  ao_strength=0.25)
    tp = tuft_points()
    nb = tuple(nrm(tp[1] - HEAD_C))
    tuft.add(blade([tp[0], tp[1], tp[2]], [0.040, 0.030, 0.004], flat=0.46, normal=nb), "hair_B_2", HAIR, k=0.0)
    for tip in TUFT_SIDE:
        pt = hp(*tip)
        mid = 0.5 * (tp[0] + pt) + nrm(pt - HEAD_C) * 0.012
        tuft.add(blade([tp[0], mid, pt], [0.032, 0.024, 0.004], flat=0.46, normal=nb), "hair_B_2", HAIR, k=0.010)
    tuft.paint(sphere(tp[2], 0.08), HAIR_HI, soft=0.04)
    L1 = np.linalg.norm(tp[1] - tp[0])
    a = tp[0]
    ax = nrm(tp[1] - tp[0])

    def tuft_w(V):
        out = []
        for p in V:
            s = float((p - a) @ ax) / L1          # 0 at the root .. 1 at the joint
            if s < 0.15:
                out.append({"head": 1.0})
                continue
            w1 = smooth01((s - 0.15) / 0.45)
            w2 = smooth01((s - 0.70) / 0.60)
            d = {"head": 1.0 - w1}
            d["hair_B_1"] = w1 * (1.0 - w2)
            d["hair_B_2"] = w1 * w2
            tot = sum(d.values())
            out.append({b: x / tot for b, x in d.items() if x / tot > 0.004})
        return out
    tuft.weight_fn = tuft_w
    tuft.cull_by = [hair]
    tuft.cull_margin = 0.0015
    return hair, tuft


def smooth01(x: float) -> float:
    x = 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)
    return x * x * (3.0 - 2.0 * x)


# ============================================================================= body
def arm_axes(sx):
    S, E, W = mx(SHOULDER_L, sx), mx(ELBOW_L, sx), mx(WRIST_L, sx)
    return S, E, W


STRAP_A = V3(0.072, 0.0, 0.540)        # correia diagonal: ombro esquerdo -> quadril direito
STRAP_B = V3(-0.098, 0.0, 0.326)


def build_body(q: float):
    # ---- jacket (torso + sleeves)
    jk = FShape("SaelJacket", "cloth", voxel=0.0038 * q, tris=1650, color_soft=0.0035, weight_sigma=0.022,
                ao_strength=0.45)
    jk.add(ellipsoid((0, 0.004, 0.384), (0.097, 0.083, 0.062)), "spine", JACKET, k=0.0)
    jk.add(ellipsoid((0, 0.000, 0.450), (0.104, 0.087, 0.086)), "chest", JACKET, k=0.05)
    jk.add(ellipsoid((0.080, 0.003, 0.488), (0.045, 0.049, 0.040)), "chest", JACKET, k=0.04)
    jk.add(ellipsoid((-0.080, 0.003, 0.488), (0.045, 0.049, 0.040)), "chest", JACKET, k=0.04)
    jk.add(ellipsoid((0, 0.006, 0.338), (0.103, 0.088, 0.030)), "hips", JACKET, k=0.03)          # hem flare
    jk.clip(plane((0, 0, 0.322), (0, 0, -1)), k=0.004)
    for sx, s_ in ((1.0, "L"), (-1.0, "R")):
        S, E, W = arm_axes(sx)
        jk.add(round_cone(S, E, 0.040, 0.0355), f"upperarm_{s_}", JACKET, k=0.030)
        end = W + (E - W) * 0.13
        jk.add(round_cone(E, end, 0.0355, 0.0335), f"forearm_{s_}", JACKET, k=0.012)
    jbase = snapshot(jk)

    # ---- dark panels (shoulder yoke, hem band, placket) + the board's diagonal strap
    panels = FShape("SaelPanels", "cloth", voxel=0.0024 * q, tris=560, color_soft=0.003, weight_sigma=0.03,
                    ao_strength=0.40)
    yoke = tight(plane((0, 0, 0.486), (0, 0, -1)), (-0.19, -0.13, 0.46), (0.19, 0.13, 0.58))
    panels.add(plate(jbase, yoke, 0.0018, 0.0040, 0.0016), "chest", JACKET_DK, k=0.0)
    hem = tight(plane((0, 0, 0.346), (0, 0, 1)), (-0.13, -0.11, 0.31), (0.13, 0.11, 0.36))
    panels.add(plate(jbase, hem, 0.0018, 0.0040, 0.0016), "hips", JACKET_DK, k=0.0)
    plk = box((-0.011, -0.10, 0.405), (0.0080, 0.06, 0.078))
    panels.add(plate(jbase, plk, 0.0018, 0.0040, 0.0016), "chest", JACKET_DK, k=0.0)
    s_dir = nrm(STRAP_B - STRAP_A)
    s_n = nrm(np.cross(s_dir, V3(0, 1, 0)))

    def strap_region(P):
        return np.abs((P - STRAP_A) @ s_n) - 0.0145
    strap = Prim(strap_region, (-0.15, -0.13, 0.30), (0.15, 0.13, 0.58))
    panels.add(plate(jbase, strap, 0.0040, 0.0030, 0.0016), "chest", STRAP, k=0.0)
    panels.weight_fn = jk.weights_at

    # ---- shearling collar + cuffs
    sh = FShape("SaelShearling", "cloth", voxel=0.0024 * q, tris=620, color_soft=0.004, weight_sigma=0.02,
                ao_strength=0.35)
    col_c = V3(0, 0.006, 0.524)
    col_R = sdfkit.euler(15, 0, 0)
    sh.add(torus(col_c, 0.068, 0.0195, col_R), "chest", SHEARLING, k=0.0)
    for i in range(16):
        a_ = 2 * math.pi * (i + 0.5) / 16
        p_ = col_c + col_R @ V3(0.083 * math.sin(a_), -0.083 * math.cos(a_), -0.004)
        sh.add(sphere(p_, 0.0125), "chest", SHEARLING, k=0.010)
    for sx, s_ in ((1.0, "L"), (-1.0, "R")):
        S, E, W = arm_axes(sx)
        cc = W + (E - W) * 0.13
        ax = nrm(W - E)
        sh.add(torus(cc, 0.0310, 0.0110, look_basis(ax)), f"forearm_{s_}", SHEARLING, k=0.0)
    sh.paint(Prim(lambda P: np.abs(np.linalg.norm((P - col_c)[:, :2], axis=1) - 0.068) - 0.0055,
                  (-0.2, -0.2, 0.45), (0.2, 0.2, 0.62)), SHEAR_SH, soft=0.01)

    # ---- shirt hem under the jacket
    shirt = FShape("SaelShirt", "cloth", voxel=0.0028 * q, tris=150, color_soft=0.004, weight_sigma=0.03,
                   ao_strength=0.45)
    shirt.add(ellipsoid((0, 0.008, 0.321), (0.095, 0.082, 0.018)), "hips", SHIRT, k=0.0)

    # ---- trousers + boots
    legs = FShape("SaelLegs", "cloth", voxel=0.0034 * q, tris=1200, color_soft=0.003, weight_sigma=0.022,
                  ao_strength=0.45)
    legs.add(ellipsoid((0, 0.010, 0.290), (0.092, 0.080, 0.060)), "hips", TROUSERS, k=0.0)
    for sx, s_ in ((1.0, "L"), (-1.0, "R")):
        H, Kn, A = mx(HIP_L, sx), mx(KNEE_L, sx), mx(ANKLE_L, sx)
        legs.add(round_cone(H, Kn, 0.047, 0.039), f"thigh_{s_}", TROUSERS, k=0.042)
        legs.add(round_cone(Kn, Kn + (A - Kn) * 0.45, 0.039, 0.036), f"shin_{s_}", TROUSERS, k=0.010)
        b0 = Kn + (A - Kn) * 0.30
        legs.add(round_cone(b0, A, 0.0410, 0.0370), f"shin_{s_}", BOOT, k=0.006)
        legs.add(torus(Kn + (A - Kn) * 0.32, 0.0410, 0.0070, look_basis(A - Kn)), f"shin_{s_}", BOOT_CUFF, k=0.002)
        legs.add(ellipsoid(mx((0.071, -0.024, 0.034), sx), (0.047, 0.082, 0.036)), f"foot_{s_}", BOOT, k=0.024)
        legs.add(ellipsoid(mx((0.071, -0.080, 0.031), sx), (0.042, 0.035, 0.031)), f"foot_{s_}", BOOT, k=0.016)
    legs.clip(plane((0, 0, 0.0), (0, 0, -1)), k=0.0)
    legs.paint(plane((0, 0, 0.012), (0, 0, 1)), SOLE, soft=0.002)
    for sx in (1.0, -1.0):
        legs.paint(ellipsoid(mx((0.070, -0.042, 0.170), sx), (0.038, 0.028, 0.028)), TROUSERS_DK, soft=0.02)

    # ---- skin: neck + hands (mitten with a thumb)
    skin = FShape("SaelSkin", "skin", voxel=0.0026 * q, tris=620, color_soft=0.003, weight_sigma=0.02,
                  ao_strength=0.40)
    skin.add(capsule((0, -0.008, 0.515), (0, -0.014, 0.610), 0.040), "neck", SKIN, k=0.0)
    for sx, s_ in ((1.0, "L"), (-1.0, "R")):
        S, E, W = arm_axes(sx)
        fa = nrm(W - E)
        hd = mx(HAND_DIR, sx)
        skin.add(round_cone(W - fa * 0.012, W + hd * 0.010, 0.021, 0.023), f"hand_{s_}", SKIN_HAND, k=0.0)
        Rh = look_basis(hd, up=(0, -1, 0))
        palm = W + hd * 0.030
        skin.add(ellipsoid(palm, (0.029, 0.023, 0.030), Rh), f"hand_{s_}", SKIN_HAND, k=0.012)
        fing = W + hd * 0.057 + V3(0, -0.004, 0)
        skin.add(ellipsoid(fing, (0.027, 0.020, 0.024), Rh), f"fingers_{s_}", SKIN_HAND, k=0.012)
        for fx in (-0.013, 0.0, 0.013):
            fp = fing + Rh @ V3(fx * sx, 0.0, 0.018)
            skin.add(sphere(fp, 0.0100), f"fingers_{s_}", SKIN_HAND, k=0.006)
        th0 = W + hd * 0.020 + V3(-0.006 * sx, -0.022, 0.0)
        th1 = th0 + V3(0.003 * sx, -0.014, -0.020)
        skin.add(round_cone(th0, th1, 0.0110, 0.0094), f"hand_{s_}", SKIN_HAND, k=0.008)
        skin.detail(sphere(fing, 0.04), 0.4)

    jk.cull_by = [panels, sh, skin]
    jk.cull_margin = 0.0009
    panels.cull_by = [sh]
    panels.cull_margin = 0.0008
    sh.cull_by = [jk]
    sh.cull_margin = 0.003
    shirt.cull_by = [jk, legs]
    shirt.cull_margin = 0.0008
    legs.cull_by = [jk, shirt]
    legs.cull_margin = 0.0012
    skin.cull_by = [jk, sh]
    skin.cull_margin = 0.0012
    return [jk, panels, sh, shirt, legs, skin], jk


# ============================================================================= scarf wrap
def build_scarf(q: float):
    sc = FShape("SaelScarf", "scarf", voxel=0.0025 * q, tris=540, color_soft=0.004, weight_sigma=0.02,
                ao_strength=0.40)
    sc.add(torus((0, -0.006, 0.553), 0.046, 0.0235, sdfkit.euler(10, 0, 0)), "chest", SCARF, k=0.0)
    sc.add(torus((0, -0.010, 0.577), 0.043, 0.0200, sdfkit.euler(-5, 0, 0)), "neck", SCARF, k=0.008)
    sc.add(ellipsoid(KNOT_C, (0.028, 0.024, 0.030), sdfkit.euler(0, 0, -40)), "chest", SCARF, k=0.010)
    sc.add(ellipsoid(KNOT_C + V3(-0.010, 0.014, -0.015), (0.022, 0.019, 0.023), sdfkit.euler(0, 0, -40)),
           "chest", SCARF, k=0.010)
    # fold shadow between the two turns
    sc.paint(Prim(lambda P: np.abs(P[:, 2] - 0.566) - 0.0026, (-0.2, -0.2, 0.5), (0.2, 0.2, 0.65)), SCARF_SH,
             soft=0.004)
    sc.paint(ellipsoid(KNOT_C + V3(-0.006, 0.010, -0.004), (0.012, 0.010, 0.012)), SCARF_SH, soft=0.01)
    return sc


# ============================================================================= board
def board_warp(x, y):
    """Pontas levantadas para o lado do deck (afastam-se das costas)."""
    return 3.2 * np.maximum(np.abs(x) - (BOARD_LEN * 0.5 - 0.095), 0.0) ** 2


def board_sdf2d(x, y):
    L = BOARD_LEN * 0.5
    a = sd_capsule2(x, y, (-L + BOARD_HW, 0.0), (L - BOARD_HW, 0.0), BOARD_HW, BOARD_HW)
    # slight sidecut: the middle is narrower
    side = np.abs(y) - (BOARD_HW - 0.006 * np.exp(-(x / 0.12) ** 2))
    return np.maximum(a, side)


def board_prim(grow: float = 0.0) -> Prim:
    o, e1, e2, n = board_frame()
    L = BOARD_LEN * 0.5 + 0.02
    bb = [(-L, 0.12), (L, 0.12), (L, -0.12), (-L, -0.12)]
    return extrude2d(o, e1, e2, lambda x, y: board_sdf2d(x, y) - grow, BOARD_HALF_T + grow, 0.0065 + grow, bb,
                     board_warp)


def board_point(x, y, h=0.0) -> np.ndarray:
    o, e1, e2, n = board_frame()
    z = float(board_warp(np.array([x]), np.array([y]))[0])
    return o + x * e1 + y * e2 + (z + h) * n


def glyph_sdf2d(x, y, scale: float = 1.0):
    """Glifo da dupla: anel + 3 pontos (ponta do triângulo para o 'nariz' da prancha)."""
    r = 0.050 * scale
    ring = np.abs(np.hypot(x, y) - r) - 0.0062 * scale
    d = ring
    for ang in (0.0, 120.0, 240.0):
        a = math.radians(ang)
        cx, cy = 0.026 * scale * math.cos(a), 0.026 * scale * math.sin(a)
        d = np.minimum(d, np.hypot(x - cx, y - cy) - 0.0092 * scale)
    return d


def build_board(q: float):
    o, e1, e2, n = board_frame()
    bd = FShape("SaelBoard", "cloth", voxel=0.0026 * q, tris=360, color_soft=0.003, weight_sigma=0.03,
                ao_group="board", ao_strength=0.30)
    bd.add(board_prim(), "board", WOOD, k=0.0)

    def base_side(P):
        return ((P - o) @ n) + 0.002                # negative on the base (toward his back)
    bd.paint(Prim(base_side, (-1e3,) * 3, (1e3,) * 3), WOOD_DK, soft=0.004)
    bbase = snapshot(bd)

    def caps_region(P):
        qv = P - o
        return (BOARD_LEN * 0.5 - 0.060) - np.abs(qv @ e1)       # negative near both ends

    marks = FShape("SaelBoardMarks", "cloth", voxel=0.0021 * q, tris=400, color_soft=0.003, weight_sigma=0.03,
                   ao_group="board", ao_strength=0.30)

    def glyph_region(P):
        qv = P - o
        x, y, z = qv @ e1, qv @ e2, qv @ n
        return np.maximum(glyph_sdf2d(x, y), -z)
    gr = Prim(glyph_region, o - 0.09, o + 0.09)
    marks.add(plate(bbase, gr, 0.0015, 0.0030, 0.0012), "board", INDIGO, k=0.0)
    # deck stripes along the nose/tail (indigo)
    for sgn in (1.0, -1.0):
        def stripe_region(P, sgn=sgn):
            qv = P - o
            x, y, z = qv @ e1, qv @ e2, qv @ n
            return np.maximum(np.maximum(np.abs(y) - 0.0075, np.abs(sgn * x - 0.205) - 0.034), -z)
        bp = board_prim(0.01)
        marks.add(plate(bbase, Prim(stripe_region, bp.lo, bp.hi), 0.0015, 0.0030, 0.0012), "board", INDIGO,
                  k=0.0)
    # two foot straps (bindings) across the deck
    for xb in (-0.115, 0.115):
        h = BOARD_HALF_T
        p0 = board_point(xb, -0.072, h - 0.002)
        pm = board_point(xb, 0.0, h + 0.013)
        p1 = board_point(xb, 0.072, h - 0.002)
        marks.add(blade([p0, pm, p1], [0.0115, 0.0125, 0.0115], flat=0.42, normal=tuple(e1)), "board", STRAP,
                  k=0.0)
    marks.add(plate(bbase, Prim(caps_region, board_prim(0.01).lo, board_prim(0.01).hi), 0.0012, 0.0030, 0.0012),
              "board", INDIGO, k=0.0)
    marks.cull_by = [bd]
    marks.cull_margin = 0.0005

    rim = FShape("SaelRim", "metal", voxel=0.0027 * q, tris=280, color_soft=0.003, weight_sigma=0.03,
                 ao_group="board", ao_strength=0.15)
    L = BOARD_LEN * 0.5 + 0.02
    bb = [(-L, 0.12), (L, 0.12), (L, -0.12), (-L, -0.12)]
    rim.add(extrude2d(o, e1, e2, lambda x, y: np.abs(board_sdf2d(x, y) + 0.0040) - 0.0042, BOARD_HALF_T + 0.0013,
                      0.0030, bb, board_warp), "board", BRASS, k=0.0)
    bd.cull_by = [marks, rim]
    bd.cull_margin = 0.0006
    return [bd, marks, rim]


def build_brass(q: float, jk_field, scarf_field):
    """Botões da carcela, fivela da correia e o broche do glifo no nó do cachecol."""
    br = FShape("SaelBrass", "metal", voxel=0.0016 * q, tris=320, color_soft=0.002, weight_sigma=0.02,
                ao_strength=0.15)
    for z in (0.468, 0.356):
        p = surf_hit(jk_field, (-0.011, -0.30, z), (0, 1, 0))
        nn = field_n(jk_field, p)
        br.add(cylinder(p + nn * 0.0030, 0.0080, 0.0026, look_basis(nn), rounding=0.0020),
               "chest" if z > 0.42 else "spine", BRASS, k=0.0)
    # strap buckle where the strap crosses the placket
    zc = 0.418
    tpar = (zc - STRAP_A[2]) / (STRAP_B[2] - STRAP_A[2])
    xc = STRAP_A[0] + (STRAP_B[0] - STRAP_A[0]) * tpar
    p = surf_hit(jk_field, (xc, -0.30, zc), (0, 1, 0))
    nn = field_n(jk_field, p)
    sd = nrm(STRAP_B - STRAP_A)
    Rb = np.stack([nrm(np.cross(nn, sd)), sd, nn], axis=1)
    frame = box(p + nn * 0.0058, (0.0165, 0.0128, 0.0025), Rb, rounding=0.0021)
    hole = box(p + nn * 0.0058, (0.0098, 0.0064, 0.02), Rb)
    br.add(frame.cut(hole, 0.0), "spine", BRASS, k=0.0)
    br.add(capsule(p + nn * 0.0070 - Rb[:, 0] * 0.011, p + nn * 0.0070 + Rb[:, 0] * 0.011, 0.0020), "spine",
           BRASS_D, k=0.0)
    # scarf pin with the duo glyph (ring + 3 dots), on the knot
    dv = V3(-0.12, 0.10, 0.012)
    kp = surf_hit(scarf_field, KNOT_C + dv, -nrm(dv), t1=0.3)
    kn = field_n(scarf_field, kp)
    Rk = look_basis(kn, up=(0, 0, 1))
    br.add(torus(kp + kn * 0.0018, 0.0120, 0.0025, Rk), "chest", BRASS, k=0.0)
    for ang in (90.0, 210.0, 330.0):
        a_ = math.radians(ang)
        dp = Rk @ V3(0.0060 * math.cos(a_), 0.0060 * math.sin(a_), 0.0)
        br.add(sphere(kp + kn * 0.0016 + dp, 0.0029), "chest", BRASS, k=0.0)
    br.detail(everywhere(), 0.6)
    return br


# ============================================================================= scarf tails (explicit ribbons)
def ribbon_data(side: str):
    """Fita explícita da ponta do cachecol: anéis regulares ao longo da linha central (perfil em
    'estádio' levemente abaulado), cor por anel (2 listras escuras perto da ponta, com anéis
    duplos = borda nítida), pesos lineares entre ossos vizinhos (dobra suave), raiz presa no peito."""
    poly, s_all = tail_curve(side)
    L = s_all[-1]
    spec = TAIL_SPEC[side]
    width = spec["width"]
    _, ks = tail_bones(side)
    # ring stations: regular + duplicated rings at the stripe borders
    stripes = [(L - 0.118, L - 0.100), (L - 0.078, L - 0.060)]
    st = list(np.linspace(0.0, L, 26))
    for a_, b_ in stripes:
        for e in (a_, b_):
            st += [e - 0.0016, e + 0.0016]
    st = np.array(sorted(set(round(float(x), 5) for x in st)))
    st = st[(st >= 0.0) & (st <= L)]
    C = at_s(poly, s_all, st)
    # tangents and parallel-transported width direction (starts along +X)
    T = np.gradient(C, axis=0)
    T /= np.linalg.norm(T, axis=1)[:, None]
    Wd = np.zeros_like(C)
    w = V3(1.0, 0.0, 0.0)
    for i in range(len(C)):
        w = w - (w @ T[i]) * T[i]
        w = nrm(w)
        Wd[i] = w
    N = np.cross(T, Wd)
    # half width: gathered at the knot, full, slight taper at the end
    def hw(s):
        g = smooth01(s / 0.14)
        e = smooth01((L - s) / 0.05)
        return 0.5 * width * (0.50 + 0.50 * g) * (0.86 + 0.14 * e)
    prof = [(1.0, 0.0), (0.62, 1.0), (0.0, 1.0), (-0.62, 1.0), (-1.0, 0.0), (-0.62, -1.0), (0.0, -1.0), (0.62, -1.0)]
    K = len(prof)
    verts, cols, uvs, wts = [], [], [], []
    for i, s in enumerate(st):
        a = hw(s)
        bth = SCARF_HALF_T * (0.75 + 0.25 * smooth01(s / 0.10))
        billow = 0.0045 * smooth01(s / 0.12)
        in_stripe = any(lo_ <= s <= hi_ for lo_, hi_ in stripes)
        col = SCARF_SH if in_stripe else SCARF
        if s < 0.05:                                  # tucked into the knot: a little darker
            col = tuple(np.array(SCARF_SH) + (np.array(SCARF) - np.array(SCARF_SH)) * smooth01(s / 0.05))
        for (pu, pv) in prof:
            u = pu * a
            v = pv * bth + billow * (1.0 - pu * pu)
            verts.append(C[i] + Wd[i] * u + N[i] * v)
            cols.append(col)
            uvs.append((0.5 + 0.5 * pu, s / L))
        # weights: hat functions between bone centres; root blends from the chest
        cen = 0.5 * (ks[:-1] + ks[1:])
        if s <= cen[0]:
            d = {f"scarf_{side}_1": 1.0}
        elif s >= cen[-1]:
            d = {f"scarf_{side}_{N_SCARF}": 1.0}
        else:
            j = int(np.searchsorted(cen, s) - 1)
            f = (s - cen[j]) / (cen[j + 1] - cen[j])
            d = {f"scarf_{side}_{j + 1}": 1.0 - f, f"scarf_{side}_{j + 2}": f}
        root = 1.0 - smooth01((s - 0.010) / 0.045)
        if root > 0.0:
            d = {b: x * (1.0 - root) for b, x in d.items()}
            d["chest"] = d.get("chest", 0.0) + root
        tot = sum(d.values())
        dw = {b: x / tot for b, x in d.items() if x / tot > 0.003}
        wts.extend(dict(dw) for _ in prof)
    faces = []
    nr = len(st)
    for i in range(nr - 1):
        for j in range(K):
            a0 = i * K + j
            a1 = i * K + (j + 1) % K
            b1 = (i + 1) * K + (j + 1) % K
            b0 = (i + 1) * K + j
            faces.append((a0, a1, b1, b0))
    # caps: root (normal -T) and tip (normal +T), as triangle fans
    for i, sgn in ((0, -1.0), (nr - 1, 1.0)):
        cidx = len(verts)
        verts.append(C[i] + N[i] * (0.0045 * (smooth01(st[i] / 0.12))))
        cols.append(cols[i * K])
        uvs.append((0.5, st[i] / L))
        for j in range(K):
            a0 = i * K + j
            a1 = i * K + (j + 1) % K
            faces.append((a0, a1, cidx) if sgn > 0 else (a1, a0, cidx))
        wts.append(dict(wts[i * K]))
    return np.array(verts), faces, np.array(cols), np.array(uvs), wts


def ribbon_object(name: str, side: str, rig_bones: list[str]):
    V, F, C, UV, W = ribbon_data(side)
    me = bpy.data.meshes.new(name)
    me.from_pydata([tuple(v) for v in V], [], [tuple(f) for f in F])
    me.validate(clean_customdata=False)
    me.update()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    lin = np.vectorize(srgb_to_linear)(np.clip(C, 0, 1))
    rgba = np.concatenate([lin, np.ones((len(V), 1))], axis=1).astype(np.float32)
    attr = me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
    attr.data.foreach_set("color", rgba.ravel())
    me.color_attributes.active_color = attr
    try:
        me.color_attributes.render_color_index = me.color_attributes.find("Col")
    except Exception:
        pass
    uvl = me.uv_layers.new(name="UVMap")
    li = np.empty(len(me.loops), np.int32)
    me.loops.foreach_get("vertex_index", li)
    uvl.data.foreach_set("uv", UV[li].astype(np.float32).ravel())
    groups = {b: obj.vertex_groups.new(name=b) for b in rig_bones}
    for vi, w in enumerate(W):
        for b, x in w.items():
            groups[b].add([vi], float(x), "REPLACE")
    for p in me.polygons:
        p.use_smooth = True
    sdfchar._assign_material(obj, "scarf")
    tris = sum(len(p.vertices) - 2 for p in me.polygons)
    log(f"  {name}: ribbon {len(V)} verts, {tris} tris")
    return obj


# ============================================================================= assembly
def build_shapes():
    q = 1.45 if FAST else 1.0
    head, face, brows, head_base = build_head(q)
    hair, tuft = build_hair(q, head_base)
    head.cull_by += [hair]
    body_parts, jk = build_body(q)
    scarf = build_scarf(q)
    board_parts = build_board(q)
    brass = build_brass(q, snapshot(jk), scarf.field)
    skin = body_parts[-1]
    skin.cull_by = list(skin.cull_by) + [scarf]
    scarf.cull_by = []
    return [head, face, brows, hair, tuft] + body_parts + [scarf] + board_parts + [brass]


def build_eyes(bones):
    eyes = []
    for sx, s in ((1.0, "L"), (-1.0, "R")):
        eyes.append(sdfchar.eye_object(f"Eye_{s}", tuple(h2w(mx(EYE_C_L, sx))), EYE_R * HS, tuple(mx(EYE_FWD_L, sx)),
                                       f"eye_{s}", bones, squash=EYE_SQ, segments=16, rings=10))
    return eyes


def union_field(shapes):
    fields = [s.field for s in shapes]

    def f(P):
        d = fields[0](P)
        for g in fields[1:]:
            d = np.minimum(d, g(P))
        return d
    return f


def assemble(name, rig, shapes, extras):
    """sdfchar.assemble com AO por grupo (o corpo não recebe sombra da prancha, que sai das
    costas no surfe) e força de AO por peça."""
    rig_obj = rig.build(name)
    bones = [b for b in rig.order if rig.bones[b].deform]
    groups = {}
    for sh in shapes:
        groups.setdefault(sh.ao_group, []).append(sh)
    ao_fields = {g: union_field(lst) for g, lst in groups.items()}
    objs = []
    for sh in shapes:
        t = time.time()
        o = sdfkit.build_object(sh, bones, log=log, ao_field=ao_fields[sh.ao_group] if sh.ao_strength > 0 else None,
                                ao_strength=sh.ao_strength)
        sdfchar._assign_material(o, sh.material)
        if o.data.validate(verbose=False, clean_customdata=False):
            log(f"    {sh.name}: malha corrigida por validate()")
        objs.append(o)
        log(f"    {sh.name}: {time.time() - t:.1f}s")
    objs.extend(extras)
    for side in ("L", "R"):
        ro = ribbon_object(f"SaelTail_{side}", side, bones)
        if ro.data.validate(verbose=False, clean_customdata=False):
            log(f"    SaelTail_{side}: malha corrigida por validate()")
        objs.append(ro)
    select_only(objs)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = name + "Mesh"
    body.data.name = name + "Mesh"
    used = set()
    for v in body.data.vertices:
        for g in v.groups:
            if g.weight > 0.0:
                used.add(g.group)
    for vg in list(body.vertex_groups):
        if vg.index not in used and vg.name not in bones:
            body.vertex_groups.remove(vg)
    mod = body.modifiers.new("Armature", "ARMATURE")
    mod.object = rig_obj
    body.parent = rig_obj
    tris = sum(len(p.vertices) - 2 for p in body.data.polygons)
    log(f"{name}: {len(body.data.vertices)} verts, {tris} tris, {len(body.data.materials)} materials, {len(bones)} bones")
    return rig_obj, body


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

    def place(self, b, M_world: Matrix):
        """Põe o osso exatamente na matriz de mundo M_world (rotação + posição da cabeça)."""
        F = self.frame(b)
        L = F.inverted() @ M_world
        self.rot[b] = L.to_quaternion()
        self.loc[b] = L.translation.copy()
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


def body(P, pitch=0.0, yaw=0.0, roll=0.0, pivot=(0.0, 0.0, 0.45), off=(0.0, 0.0, 0.0)):
    """Corpo inteiro (osso hips): pitch + = para a frente, roll + = tomba para a esquerda dele,
    yaw + = vira para a esquerda dele; em volta de 'pivot', deslocado por 'off' (mundo)."""
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


def scarf(P, side, lift=0.0, curl=(), sway=0.0, twist=()):
    """Ponta do cachecol: lift + = levanta a raiz (a fita sobe para trás); curl[i] / twist[i]
    por osso (graus, em volta da largura da fita / do próprio eixo); sway + = para a direita dele."""
    for i in range(N_SCARF):
        b = f"scarf_{side}_{i + 1}"
        c = (lift if i == 0 else 0.0) + (curl[i] if i < len(curl) else 0.0)
        q = qw(x=c, z=sway if i == 0 else 0.0)
        tw = twist[i] if i < len(twist) else 0.0
        if tw:
            ax = K.tail[b] - K.head[b]
            q = q @ qa(ax, tw)
        P.turn(b, q)


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


def board_world(center: Vector, fwd: Vector, up: Vector) -> Matrix:
    """Matriz de mundo do osso board para a prancha ficar com o centro em 'center', o nariz para
    'fwd' e o deck para 'up' (surfe: debaixo dos pés)."""
    o, e1, e2, n = board_frame()
    S = Matrix((Vector(tuple(e1)), Vector(tuple(n)), Vector(tuple(np.cross(e1, n))))).transposed()
    Yb = fwd.normalized()
    upp = (up - Yb * up.dot(Yb)).normalized()
    T = Matrix((Yb, upp, Yb.cross(upp))).transposed()
    R = (T @ S.transposed()) @ K.rest["board"].to_3x3().normalized()
    head_rest = K.head["board"] - Vector(tuple(o))
    M = R.to_4x4()
    M.translation = center + (T @ S.transposed()) @ head_rest
    return M


# ============================================================================= clips
def c_rest(t, ph):
    return {}


def c_preview(t, ph):
    """Pose estática da prévia: em pé, braços relaxados, cabeça levemente inclinada, as duas pontas
    do cachecol levantadas para trás pelo vento (onda suave), topete erguido."""
    P = Pose(K)
    body(P, pitch=0.5, roll=-1.5, yaw=-4, pivot=(0, 0.01, 0.30), off=(-0.004, 0.0, -0.004))
    spine(P, sp=(0, 1.0, 2), ch=(0.6, 1.0, 3), nk=(0, 0, 2), hd=(-3.0, -5.0, 6.0))
    foot(P, "L", (0.026, -0.022, 0.0), yaw=14)
    foot(P, "R", (0.012, 0.018, 0.0), yaw=4)
    # left fist on the hip (elbow out), right arm relaxed a little forward
    reach(P, "L", (0.150, 0.004, 0.338), (1.0, 0.55, 0.15))
    P.turn_world("hand_L", qw(y=-24, z=-10))
    arm(P, "R", swing=-7, out=-14, twist=-10, flex=20, hand=(6, 0, -6))
    scarf(P, "R", lift=50, curl=(0, 12, 10, -6, -16, -8, 8), sway=16, twist=(0, 10, 18, 24, 18, 8, -4))
    scarf(P, "L", lift=46, curl=(0, 6, 14, 10, -8, -16, -8), sway=-30, twist=(0, -8, -14, -18, -12, -4, 6))
    P.turn("hair_B_1", qw(x=-6))
    P.turn("hair_B_2", qw(x=-8))
    return P.export()


CLIPS = [
    ("rest", 0.067, c_rest, False),
    ("preview", 0.067, c_preview, False),
]
MODEL_CLIPS = ["rest", "preview"]


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
MATERIALS = (("skin", (0.82, 0.47, 0.26, 1)), ("hair", (0.10, 0.04, 0.02, 1)), ("cloth", (0.19, 0.07, 0.02, 1)),
             ("scarf", (0.67, 0.03, 0.02, 1)), ("metal", (0.66, 0.37, 0.05, 1)), ("eye", (1, 1, 1, 1)))


def reanim(blend_path: str):
    """Itera só nas animações: abre um .blend já modelado, refaz as ações e exporta."""
    t0 = time.time()
    bpy.ops.wm.open_mainfile(filepath=blend_path)
    rig_obj = bpy.data.objects["Sael"]
    body_obj = bpy.data.objects["SaelMesh"]
    for act in list(bpy.data.actions):
        bpy.data.actions.remove(act)
    only = ARGS[ARGS.index("--anims") + 1].split(",") if "--anims" in ARGS else None
    bake_all(rig_obj, Kin(rig_obj), only)
    sdfchar.export(OUT_GLB, rig_obj, body_obj)
    log(f"Sael: reanim {time.time() - t0:.1f}s")


def main():
    if "--reanim" in ARGS:
        reanim(ARGS[ARGS.index("--reanim") + 1])
        return
    t0 = time.time()
    reset_scene()
    for name, col in MATERIALS:
        material(name, col)
    rig = make_rig()
    shapes = build_shapes()
    deform = [b for b in rig.order if rig.bones[b].deform]
    eyes = build_eyes(deform)
    rig_obj, body_obj = assemble("Sael", rig, shapes, eyes)
    log(f"Sael: modelo pronto em {time.time() - t0:.1f}s")
    kin = Kin(rig_obj)
    only = None
    if "--anims" in ARGS:
        only = ARGS[ARGS.index("--anims") + 1].split(",")
    if MODEL_ONLY or NOANIM:
        only = MODEL_CLIPS
    bake_all(rig_obj, kin, only)
    log(f"Sael: animações prontas em {time.time() - t0:.1f}s")
    if OUT_BLEND is not None:
        OUT_BLEND.parent.mkdir(parents=True, exist_ok=True)
        bpy.context.preferences.filepaths.save_version = 0
        bpy.ops.wm.save_as_mainfile(filepath=str(OUT_BLEND), compress=True)
    sdfchar.export(OUT_GLB, rig_obj, body_obj)
    log(f"Sael: total {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()
