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
EYE_C_L = V3(0.054, -0.133, 0.784)     # feedback 2: smaller eyes (x0.65), a bit lower, ~1 eye-width apart
EYE_R = 0.030
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
        lid_c = c + R @ V3(0.0013 * sx, -0.036, 0.004)
        head.add(ellipsoid(lid_c, (0.030, 0.011, 0.018), R), "head", SKIN, k=0.018)
    for sx in (1.0, -1.0):          # ears
        ec = mx((0.150, 0.004, 0.778), sx)
        Re = sdfkit.euler(0, 0, 18 * sx)
        head.add(ellipsoid(ec, (0.019, 0.030, 0.039), Re), "head", SKIN, k=0.012)
        head.carve(ellipsoid(ec + mx((0.013, -0.004, 0.0), sx), (0.009, 0.018, 0.025), Re), k=0.006, color=EAR_IN)
    for sx in (1.0, -1.0):          # eye sockets: open only above the lower-lid line
        c, R = eye_basis(sx)
        sock = eye_ellipsoid(sx, grow=0.0030).clip(plane(tuple(c + V3(0, 0, -0.024)), (0, 0, -1)), 0.008)
        head.carve(sock, k=0.006)
    base = snapshot(head)
    nose_p = surf_hit(base, (0.0, -0.30, 0.748), (0, 1, 0))
    head.add(ellipsoid(nose_p + V3(0, 0.0010, 0.002), (0.0205, 0.0160, 0.0160), (-16, 0, 0)), "head", SKIN, k=0.007)
    head.detail(ellipsoid((0, -0.130, 0.750), (0.10, 0.06, 0.09)), 0.7)
    for sx in (1.0, -1.0):
        head.paint(ellipsoid(mx((0.094, -0.116, 0.734), sx), (0.032, 0.030, 0.021)), BLUSH, soft=0.016)
    head.paint(ellipsoid(nose_p + V3(0, -0.008, 0.002), (0.011, 0.008, 0.009)), BLUSH, soft=0.010)

    # ---- face lines: upper lid line (with a small outer flick) + open smile (flush plates)
    face = XShape("SaelFace", "skin", voxel=0.0015 * q, tris=340, color_soft=0.002, weight_sigma=0.02,
                  ao_strength=0.0)
    for sx in (1.0, -1.0):
        c, R = eye_basis(sx)
        ring = eye_ellipsoid(sx, grow=0.0050).clip(plane(tuple(c + V3(0, 0, 0.006)), (0, 0, -1)), 0.008)
        flick_a = c + R @ V3(0.025 * sx, 0.016, 0.000)
        flick_b = c + R @ V3(0.030 * sx, 0.018, -0.003)
        ring = ring.union(round_cone(flick_a, flick_b, 0.0032, 0.0015), 0.002)
        ring = tight(ring, c - 0.06, c + 0.06)
        face.add(plate(base, ring, lift=0.0020, sink=0.0034, k=0.0012), "head", LASH, k=0.0)
    mz, mw = 0.703, 0.0290

    def mouth_region(P):
        u = (P[:, 0] - 0.0010) / mw
        line = mz + 0.0050 * u * u + 0.0016 * u + 0.0030 * np.maximum(u - 0.60, 0.0) ** 2 * 6.0
        th = 0.0022 * (1.0 - 0.45 * np.clip(np.abs(u), 0.0, 1.0) ** 2)
        return np.maximum(np.maximum(np.abs(P[:, 2] - line) - th, (np.abs(u) - 1.0) * mw), P[:, 1] + 0.08)
    mouth = Prim(mouth_region, (-0.04, -0.25, 0.68), (0.04, -0.08, 0.74))
    face.add(plate(base, mouth, lift=0.0010, sink=0.0030, k=0.0008), "head", MOUTH, k=0.0)
    face.detail(everywhere(), 0.5)

    # ---- brows: thick, the inner end a little lower (determined, friendly)
    brows = XShape("SaelBrows", "hair", voxel=0.0016 * q, tris=200, color_soft=0.002, weight_sigma=0.02,
                   ao_strength=0.0)
    for sx in (1.0, -1.0):
        pts = surface_line(base, [(0.022 * sx, 0.832), (0.052 * sx, 0.846), (0.083 * sx, 0.843)], lift=0.0010)
        brows.add(stroke(pts, [0.0060, 0.0066, 0.0040], 0.003), "head", BROW, k=0.0)

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


# ============================================================================= sael helpers
# Os clipes abaixo são os da Saeli (build_saeli.py), portados quase sem mudança: o corpo usa o mesmo
# esqueleto. Só o que era dela mudou: leques -> braços (as mesmas poses de braço), orelhas-barbatana ->
# topete (tuft(), mesma chamada de ears()), cauda + prancha-folha -> pontas do cachecol (scarf_flow()) +
# prancha presa nas costas (vai para debaixo dos pés no surfe).
SCARF_BONES = {s: [f"scarf_{s}_{i + 1}" for i in range(N_SCARF)] for s in "LR"}
# pontas em repouso (medidas no rig): elevação do 1o e do último osso, rumo do 1o e do último osso
# (para trás = +Y, elevação + = para cima, rumo + = para a direita dele)
SCARF_REST = {"R": (-14.0, -67.0, 10.0, 21.0), "L": (-21.0, -71.0, -3.0, -17.0)}
# a prancha passa logo atrás do nó (borda direita dela): o 1o osso de cada ponta sai para trás e para a
# direita, acima da borda, antes de as pontas se abrirem por cima do deck
SCARF_ROOT_YAW = 36.0
SCARF_ROOT_ELEV = -6.0
CURL_AX = {sx: nrm(np.cross(mx(HAND_DIR, sx), V3(-sx, 0.0, 0.0))) for sx in (1.0, -1.0)}
HAND_Y0 = {sx: Vector(tuple(mx(HAND_DIR, sx))) for sx in (1.0, -1.0)}
GRIP_Y0 = Vector(tuple(GRIP_AXIS))


def tuft(P, lift=0.0, flare=0.0, tip=0.0, twist=0.0, diff=0.0):
    """Topete de trás (hair_B_1..2) no lugar das orelhas-barbatana da Saeli: mesma assinatura de ears(),
    amplitude menor (lift + = sobe, tip = segunda metade, diff = inclina para um lado)."""
    P.turn("hair_B_1", qw(x=0.45 * lift, z=-0.30 * diff + 0.10 * twist))
    t2 = 0.55 * tip + 0.15 * lift
    if t2:
        P.turn("hair_B_2", qw(x=t2))


def curl(P, s, deg):
    """Fecha a mitene: dobra os dedos (osso fingers_<s>) em volta do eixo do item (graus)."""
    if deg:
        P.turn(f"fingers_{s}", qa(CURL_AX[sxs(s)], deg))


def chest_q(P) -> Quaternion:
    return P.world("chest").to_quaternion() @ K.rrot["chest"].inverted()


def yaw_q(P) -> Quaternion:
    """Só o rumo do peito (giro em Z): o referencial do ar para o cachecol."""
    f = chest_q(P) @ Vector((0.0, -1.0, 0.0))
    if math.hypot(f.x, f.y) < 0.2:
        f = hips_q(P) @ Vector((0.0, -1.0, 0.0))
    return qw(z=math.degrees(math.atan2(f.x, -f.y)))


def back_dir(yaw_deg: float, elev_deg: float) -> Vector:
    y, e = math.radians(yaw_deg), math.radians(elev_deg)
    return Vector((-math.sin(y) * math.cos(e), math.cos(y) * math.cos(e), math.sin(e)))


def scarf_flow(P, ph=0.0, lift=None, bend=None, spread=0.0, drift=0.0, amp=0.0, waves=1.0, k=0.75,
               side_amp=0.0, twist=0.0, ref="yaw", lag=0.37, guard=True):
    """Pontas do cachecol por direções, osso a osso da raiz à ponta (P.aim): elevação do osso i =
    lift + bend * u (u = 0 na raiz .. 1 na ponta) + onda que corre da raiz para a ponta (amp graus,
    'waves' ondas por volta do clipe, k = atraso de fase por osso, amplitude crescendo para a ponta);
    rumo = o de repouso + spread (abre em V: + = cada ponta para o seu lado) + drift (+ = para a direita
    dele) + onda lateral (side_amp). lift/bend None = os de repouso. ref: 'yaw' (rumo do peito = o ar),
    'chest' (acompanha o tronco: cambalhotas) ou 'world'. guard: o 1o osso passa por cima da borda da
    prancha (rumo/elevação mínimos no referencial do peito)."""
    if ref == "yaw":
        Q = yaw_q(P)
    elif ref == "chest":
        Q = chest_q(P)
    else:
        Q = Quaternion()
    Qc = chest_q(P)
    for side, sgn, off in (("R", -1.0, 0.0), ("L", 1.0, lag)):
        e0, e1, y0, y1 = SCARF_REST[side]
        l0 = e0 if lift is None else lift + (e0 - SCARF_REST["R"][0]) * 0.5
        bd = (e1 - e0) if bend is None else bend
        for i, b in enumerate(SCARF_BONES[side]):
            u = i / (N_SCARF - 1)
            g = 0.30 + 0.70 * u
            w = TAU * (waves * ph + off) - k * i
            el = l0 + bd * u + amp * g * math.sin(w)
            yw = lerp(y0, y1, u) - sgn * spread * (0.6 + 0.4 * u) + drift + side_amp * g * math.sin(w + 1.3)
            d = Q @ back_dir(yw, el)
            if guard and i == 0:
                dc = Qc.inverted() @ d
                ce = math.degrees(math.asin(max(-1.0, min(1.0, dc.z))))
                cy = math.degrees(math.atan2(-dc.x, dc.y))
                d = Qc @ back_dir(max(cy, SCARF_ROOT_YAW), max(ce, SCARF_ROOT_ELEV))
            P.aim(b, d)
            if twist:
                ax = P.world(b).to_3x3().normalized() @ Vector((0, 1, 0))
                P.turn_world(b, qa(ax, twist * g * math.sin(w + 0.6)))


def foot_world(P, s, ankle, yaw=0.0, pitch=0.0, roll=0.0, pole=None):
    """Pé com o tornozelo num ponto do mundo e rumo 'yaw' no mundo (+ = ponta para a esquerda dele)."""
    sx = sxs(s)
    A0 = mx(ANKLE_L, sx)
    foot(P, s, ((ankle[0] - A0[0]) * sx, ankle[1] - A0[1], ankle[2] - A0[2]), pitch=pitch, yaw=sx * yaw,
         roll=roll, pivot="ankle", pole=pole)


def dvec(yaw=0.0, el=0.0) -> Vector:
    """Direção pelo rumo (0 = para a frente, + = para a esquerda dele) e elevação (graus)."""
    y, e = math.radians(yaw), math.radians(el)
    return Vector((math.sin(y) * math.cos(e), -math.cos(y) * math.cos(e), math.sin(e)))


def vspline(t, keys, periodic=False) -> Vector:
    return Vector(spline(t, [(a, tuple(v)) for a, v in keys], periodic))


def aim_grip(P, s, d, hint=None, share=0.5):
    """Gira a mão para o eixo do item (osso grip_<s>, +Y) apontar para d; os dedos seguem o antebraço
    (punho neutro) ou 'hint'; 'share' da torção da mão vai para o antebraço (sem pulso quebrado)."""
    sx = sxs(s)
    g0 = GRIP_Y0
    h0 = HAND_Y0[sx]
    h0 = (h0 - g0 * h0.dot(g0)).normalized()
    A = Matrix((g0, h0, g0.cross(h0))).transposed()
    d = Vector(tuple(d)).normalized()
    hv = Vector(tuple(hint)) if hint is not None else \
        P.world(f"forearm_{s}").to_3x3().normalized() @ Vector((0, 1, 0))
    h1 = hv - d * hv.dot(d)
    if h1.length < 1e-4:
        h1 = Vector((0.0, 0.0, -1.0)) - d * (-d.z)
    h1.normalize()
    Bm = Matrix((d, h1, d.cross(h1))).transposed()
    M3 = Bm @ A.transposed() @ K.rest[f"hand_{s}"].to_3x3().normalized()
    if share > 0.0:
        F = P.frame(f"hand_{s}").to_3x3().normalized()
        L = (F.inverted() @ M3).to_quaternion()
        if L.w < 0.0:
            L = -L
        ang = 2.0 * math.atan2(L.y, L.w)
        fa = P.world(f"forearm_{s}").to_3x3().normalized() @ Vector((0, 1, 0))
        P.turn_world(f"forearm_{s}", qa(fa, math.degrees(ang) * share))
    P.set_world_rot(f"hand_{s}", M3)


def grip_pos(P, s) -> Vector:
    """Posição atual do ponto de pega (cabeça do osso grip_<s>)."""
    return P.point(f"hand_{s}", grip_point(sxs(s)))


def hold(P, s, gp, pole, d, grip=100.0, hint=None, share=0.5, iters=3):
    """Mão segurando um item: o ponto de pega (grip_<s>) vai para gp, o eixo do item aponta para d e a
    mitene fecha em volta dele (IK do braço + orientação da mão, iterado)."""
    sx = sxs(s)
    gp = Vector(tuple(gp))
    wr = gp - Vector(tuple(grip_point(sx) - mx(WRIST_L, sx)))
    for _ in range(iters):
        reach(P, s, wr, pole)
        aim_grip(P, s, d, hint, share)
        wr = wr + (gp - grip_pos(P, s))
    curl(P, s, grip)


def stance(P, wide=1.0, sink=0.0, yl=10.0, yr=-2.0):
    """Base de luta: pé esquerdo à frente, direito atrás."""
    foot(P, "L", (0.010 + 0.014 * wide, -0.038 * wide, sink), yaw=yl)
    foot(P, "R", (0.010 + 0.014 * wide, 0.034 * wide, sink), yaw=yr)


def mouth_world(P) -> Vector:
    return P.point("head", h2w(V3(0.0015, -0.150, 0.707)))


# ============================================================================= clips
def done(P) -> dict:
    """Fim de todo clipe: a prancha nas costas sai 0,8° do repouso (encostada nas alças). Assim a trilha
    dela nunca é 'constante = repouso', que o importador do Godot descarta (remove_immutable_tracks): a
    pose da prancha do surfe não vaza para o clipe seguinte num AnimationPlayer simples."""
    if "board" not in P.rot and "board" not in P.loc:
        P.turn("board", qw(x=-0.8))
    return P.export()


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
    return done(P)


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
    # Saeli's fan flick -> the same little arm lift, the mittens open and close
    fo = spline(t, [(0, 0), (1.62, 0), (1.74, 0.46), (1.82, 0.36), (2.02, 0.38), (2.12, 0.0), (3.0, 0)])
    lift_arm = spline(t, [(0, 0), (1.55, 0), (1.74, 12), (2.02, 10), (2.25, 0), (3.0, 0)])
    for s in "LR":
        arm(P, s, swing=-4 + 1.5 * br, out=2 + lift_arm + 1.0 * br, twist=-6, flex=22 + 2 * br + lift_arm * 0.8,
            hand=(4, 0, -6))
        curl(P, s, 24 - 40 * fo)
    perk = spline(t, [(0, 0), (0.80, 10), (1.30, 8), (1.62, 2), (2.15, 4), (2.55, 0), (3.0, 0)], True)
    curious = spline(t, [(0, 0), (1.45, 0), (1.62, 14), (2.0, 12), (2.3, 0), (3.0, 0)])
    tuft(P, lift=perk + 2 * br, flare=8 + 3 * fo, tip=1.5 * cw(ph * 2, 0.15), diff=curious)
    # Saeli's two board taps -> a gust that lifts the scarf
    gust = spline(t, [(0, 0), (1.95, 0), (2.36, 1.0), (2.62, 0.75), (2.95, 0.0), (3.0, 0)])
    scarf_flow(P, ph, lift=-4 + 2 * br + 26 * gust, bend=-46 + 26 * gust, amp=4 + 7 * gust, waves=3, k=0.8,
               side_amp=4 + 4 * gust, twist=8)
    return done(P)


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
            # every pivot gets the same ground displacement y: the planted heel/ball never pops when the
            # pivot changes (Saeli's code offset the heel/ball by 4/10 cm here: the walk foot slid)
            foot(P, s, (0.004, y, 0.0), pitch=pitch, yaw=5, pivot=piv)
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
        curl(P, s, 26 if walk else 62)                                 # relaxed hands / running fists
    if walk:
        tuft(P, lift=2 + 3 * math.cos(TAU * 2 * (ph - 0.12)), flare=8, tip=2 * math.cos(TAU * 2 * (ph - 0.2)))
        scarf_flow(P, ph, lift=0 + 3 * math.cos(TAU * 2 * (ph - 0.1)), bend=-36, amp=7, waves=2, k=0.8,
                   side_amp=5, twist=10, drift=4 * wv(ph, -0.1))
    else:
        tuft(P, lift=-10 + 4 * math.cos(TAU * 2 * (ph - 0.15)), flare=10, tip=-6 + 3 * math.cos(TAU * 2 * (ph - 0.25)))
        scarf_flow(P, ph, lift=12 + 3 * math.cos(TAU * 2 * (ph - 0.12)), bend=-10, amp=11, waves=2, k=0.85,
                   side_amp=7, twist=14, spread=6, drift=3 * wv(ph, -0.1))
    return done(P)


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
    for s in "LR":
        arm(P, s, swing=sw, out=out, twist=-6, flex=fl, hand=(6, 0, -6))
        curl(P, s, spline(t, list(zip(T, [24, 40, 50, 10, 6, 12]))))
    tuft(P, lift=spline(t, list(zip(T, [0, -12, -16, 18, 14, 8]))), flare=spline(t, list(zip(T, [2, 0, 0, 6, 8, 6]))),
         tip=spline(t, list(zip(T, [0, -6, -8, 10, 6, 2]))))
    # the tail's whip -> the scarf: lifted by the crouch, dragged down by the take-off, floats at the top
    scarf_flow(P, t / 0.36, lift=spline(t, list(zip(T, [-4, 4, 8, -12, -8, 6]))),
               bend=spline(t, list(zip(T, [-44, -36, -30, -46, -36, -16]))), amp=6, waves=1.2, k=0.9, side_amp=4,
               spread=spline(t, list(zip(T, [0, 0, 2, 4, 8, 12]))), twist=8)
    return done(P)


def fall_pose(P, t, ph):
    body(P, pitch=-4 + 2 * wv(ph), pivot=(0, 0, 0.45), off=(0, 0, 0.02))
    spine(P, sp=(-2, 0, 0), ch=(-3 + 1.5 * wv(ph, 0.1), 0, 0), hd=(8 + 2 * wv(ph, 0.2), 0, 0))
    for s, o in (("L", 0.0), ("R", 0.5)):
        k = wv(ph, o)
        foot(P, s, (0.012, 0.012 + 0.025 * k, 0.07 + 0.025 * wv(ph, o + 0.25)), pitch=26 + 8 * k, yaw=6, rel=True)
    for s, o in (("L", 0.0), ("R", 0.25)):
        arm(P, s, swing=-22 + 6 * wv(ph, o), out=60 + 8 * wv(ph, o + 0.2), twist=-10, flex=32 + 6 * wv(ph, o + 0.3),
            hand=(8, 0, -8))
        curl(P, s, 12 + 6 * wv(ph * 2, o))
    tuft(P, lift=14 + 4 * wv(ph * 2), flare=6, tip=6 + 4 * wv(ph * 2, 0.15))
    # falling: the air comes from below and the scarf rises behind the head in a V
    scarf_flow(P, ph, lift=24 + 4 * wv(ph, -0.1), bend=40, spread=16, amp=9, waves=2, k=0.8, side_amp=7, twist=12)


def c_fall(t, ph):
    P = Pose(K)
    fall_pose(P, t, ph)
    return done(P)


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
    for s in "LR":
        arm(P, s, swing=sw, out=out, twist=-6, flex=fl, hand=(6, 0, -6))
        curl(P, s, spline(t, list(zip(T, [12, 30, 40, 30, 24, 24]))))
    tuft(P, lift=spline(t, list(zip(T, [14, -10, -18, -6, 4, 0]))), flare=2, tip=spline(t, list(zip(T, [6, -8, -10, 2, 2, 0]))))
    # the raised scarf (fall) drops onto the back and bounces
    scarf_flow(P, t / 0.30, lift=spline(t, list(zip(T, [24, 12, -2, -10, -6, -4]))),
               bend=spline(t, list(zip(T, [40, 6, -30, -50, -48, -46]))),
               spread=spline(t, list(zip(T, [16, 10, 4, 0, 0, 0]))), amp=5, waves=1.0, k=0.9, side_amp=3, twist=6)
    return done(P)


def c_double_jump(t, ph):
    P = Pose(K)
    # open (2 frames) -> arms beat down -> forward tuck flip -> open into fall
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
    for s in "LR":
        arm(P, s, swing=sw, out=out, twist=-8, flex=fl, hand=(8, 0, -8))
        curl(P, s, spline(t, list(zip(T, [10, 0, 20, 70, 70, 14]))))
    tuft(P, lift=spline(t, list(zip(T, [12, 20, 4, -24, -22, 12]))), flare=spline(t, list(zip(T, [6, 12, 4, -4, -4, 6]))),
         tip=spline(t, list(zip(T, [6, 10, -6, -12, -10, 6]))))
    # the scarf whips around the flip (chest frame: it lags behind the rotation and rises over the back)
    scarf_flow(P, t / 0.42, lift=spline(t, list(zip(T, [20, 18, 6, 34, 38, 24]))),
               bend=spline(t, list(zip(T, [36, 26, 10, 46, 40, 34]))),
               spread=spline(t, list(zip(T, [14, 24, 12, 18, 20, 16]))), amp=7, waves=1.5, k=0.9, side_amp=5,
               twist=10, ref="chest")
    return done(P)


def c_glide(t, ph):
    P = Pose(K)
    bank = 6.0 * wv(ph)
    body(P, pitch=26 + 1.5 * wv(ph, 0.25), roll=bank, yaw=-2.0 * wv(ph, 0.1), pivot=(0, 0, 0.45), off=(0, 0, 0.03))
    spine(P, sp=(2, -bank * 0.2, 0), ch=(-4, -bank * 0.3, 0), nk=(-6, 0, 0), hd=(-18, -bank * 0.4, bank * 0.3))
    for s in "LR":
        sx = sxs(s)
        dihedral = 6.0 + bank * sx * 0.6
        arm(P, s, swing=-8 + 1.5 * wv(ph, 0.3), out=49 + dihedral, twist=0, flex=6, hand=(0, 0, -4))
        curl(P, s, 6)
    for s, o_ in (("L", 0.0), ("R", 0.5)):
        foot(P, s, (0.006, 0.15, 0.11 + 0.008 * wv(ph, o_)), pitch=58, yaw=4, rel=True)
    tuft(P, lift=-18 + 2 * wv(ph * 2), flare=-4, tip=-8 + 3 * wv(ph * 3, 0.25))
    # the scarf is the sail: both tails spread wide behind like a kite, trembling in the wind
    # (Saeli's 6 Hz rib flutter -> the tips)
    scarf_flow(P, ph, lift=6 + 2 * wv(ph, -0.1), bend=-4, spread=44, drift=-bank * 1.2, amp=6, waves=7, k=0.9,
               side_amp=5, twist=12)
    return done(P)


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
    for s in "LR":
        arm(P, s, swing=-8, out=out, twist=-10, flex=spline(t, list(zip(T, [22, 18, 6, 6, 16, 22]))), hand=(4, 0, -6))
        curl(P, s, spline(t, list(zip(T, [24, 20, 8, 8, 18, 24]))))
    tuft(P, lift=spline(t, list(zip(T, [0, 4, 12, 12, 6, 0]))), flare=spline(t, list(zip(T, [2, 8, 22, 22, 10, 2]))))
    # centrifugal: the tails fly out flat and trail the turn (to his right: he spins to his left)
    fly = spline(t, list(zip(T, [0.0, 0.1, 1.0, 1.0, 0.45, 0.0])))
    scarf_flow(P, t / 0.40, lift=lerp(-6, 4, fly), bend=lerp(-44, -4, fly), spread=lerp(0, 22, fly),
               drift=48 * fly, amp=5, waves=2.0, k=0.9, side_amp=4, twist=8)
    return done(P)


SURF_YAW = -76.0                          # regular stance: left foot toward the nose (-Y), chest to -X


def c_surf(t, ph):
    """Surfe na prancha (snowboard): a prancha sai das costas para debaixo dos pés, nariz para a frente
    (-Y); base regular (pé esquerdo à frente), corpo de lado com os ombros abertos para a descida, joelhos
    dobrados, braços abertos para equilibrar, cabeça olhando a descida; carving e quique leves; o cachecol
    corre para trás no vento."""
    P = Pose(K)
    carve = wv(ph)                                     # one toe/heel carve per loop
    bob = 0.007 * wv(ph * 2, 0.15)
    body(P, pitch=14 + 2 * wv(ph * 2, 0.3), roll=-3.0 * carve, yaw=SURF_YAW, pivot=(0, 0.0, 0.30),
         off=(0.020 + 0.006 * carve, 0.0, -0.028 + bob))
    spine(P, sp=(3, 1.0 * carve, 9), ch=(4, 2.0 * carve, 14), nk=(-4, 0, 18), hd=(-6, 3.0 * carve, 22))
    # the board under the feet (deck up, nose forward, carving roll)
    bc = Vector((0.0, 0.0, BOARD_HALF_T + 0.002))
    P.place("board", board_world(bc, Vector((0.0, -1.0, 0.0)), Vector((0.05 * carve, 0.0, 1.0))))
    deck = bc.z + BOARD_HALF_T + 0.001
    for s, yb, fy in (("L", -0.115, -74.0), ("R", 0.115, -100.0)):
        fw = dvec(fy, 0.0)
        sole = Vector((0.0, yb, deck))
        ank = sole - fw * 0.034 + Vector((0.0, 0.0, 0.060))
        foot_world(P, s, ank, yaw=fy, pitch=-2.9 * carve,              # the feet follow the board's edge
                   pole=Vector((-1.0, 0.25 if s == "L" else -0.25, 0.05)))
    # arms out for balance: front (left) arm toward the nose, back (right) arm low toward the tail
    arm(P, "L", swing=-34 + 3 * wv(ph, 0.2), out=46 + 4 * carve, twist=-4, flex=26, hand=(4, 0, -8))
    arm(P, "R", swing=18 + 3 * wv(ph, 0.6), out=36 - 4 * carve, twist=-8, flex=30, hand=(4, 0, -8))
    for s in "LR":
        curl(P, s, 16)
    tuft(P, lift=-12 + 3 * wv(ph * 2), flare=4, tip=-6 + 3 * wv(ph * 3, 0.2))
    scarf_flow(P, ph, lift=16 + 3 * wv(ph, -0.1), bend=-6, spread=8, drift=-14, amp=10, waves=4, k=0.85,
               side_amp=7, twist=14, ref="world", guard=False)
    return done(P)


def c_ride(t, ph):
    """No cesto do Hulvar (chão do cesto = origem; amurada ~0,23-0,25 m, raio ~0,2 m): ajoelhado,
    cintura para cima, antebraços apoiados na amurada da frente, olha em volta (contra-balanço);
    o cachecol voa para trás por cima da amurada."""
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
        curl(P, s, 30)
    tuft(P, lift=6 + 6 * (abs(look) / 38.0), flare=4, tip=2 * wv(ph * 2), diff=look * 0.15)
    scarf_flow(P, ph, lift=6 + 2 * wv(ph, 0.2), bend=-30, drift=look * 0.06, amp=6, waves=3, k=0.8, side_amp=5,
               twist=10)
    return done(P)


def c_launch(t, ph):
    """Bola encolhida girando para a frente (1 volta por laço)."""
    P = Pose(K)
    body(P, pitch=360.0 * ph, pivot=(0, -0.01, 0.46), off=(0, 0, 0.02))
    spine(P, sp=(14, 0, 0), ch=(16, 0, 0), nk=(10, 0, 0), hd=(16, 0, 0))
    for s in "LR":
        foot(P, s, (0.030, -0.085, 0.235), pitch=55, yaw=8, rel=True)
    for s in "LR":
        arm(P, s, swing=-48, out=4, twist=-6, flex=104, ftwist=10, hand=(24, 0, 0))
        curl(P, s, 80)
    tuft(P, lift=-28, flare=-8, tip=-14)
    # the tails trail the roll, close over the back (chest frame)
    scarf_flow(P, ph, lift=30, bend=26, spread=10, amp=6, waves=2, k=0.8, side_amp=4, twist=10, ref="chest")
    return done(P)


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
    fist = spline(t, list(zip(T, [24, 40, 90, 90, 40, 10, 10, 40, 95, 95, 24])))
    for s in "LR":
        arm(P, s, swing=sw, out=out, twist=-8, flex=fl, hand=(6, 0, -8))
        curl(P, s, fist)
    tuft(P, lift=spline(t, list(zip(T, [0, -8, 22, 16, -6, 10, 10, 0, 24, 20, 0]))),
         flare=spline(t, list(zip(T, [2, 0, 12, 10, 2, 16, 16, 4, 14, 12, 2]))))
    wag = math.sin(TAU * t * 4.0) * spline(t, list(zip(T, [0, 0, 0, 0, 0, 0, 0, 0.6, 1.0, 1.0, 0])))
    spd = spline(t, list(zip(T, [0, 0, 0, 0, 0, 0.6, 1.0, 0.3, 0, 0, 0])))
    scarf_flow(P, t / 1.6, lift=spline(t, list(zip(T, [-4, 4, -10, 14, 20, 6, 4, -2, -8, 10, -4]))),
               bend=spline(t, list(zip(T, [-46, -36, -40, -4, 10, -20, -20, -36, -40, -10, -46]))),
               spread=spline(t, list(zip(T, [0, 0, 4, 14, 10, 18, 18, 6, 6, 14, 0]))),
               drift=14 * wag + 40 * spd, amp=6, waves=4.0, k=0.85, side_amp=5, twist=10)
    return done(P)


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
        curl(P, s, spline(t, list(zip(T, [24, 4, 30, 40, 30]))))
    tuft(P, lift=spline(t, list(zip(T, [0, 10, -20, -28, -24]))), flare=spline(t, list(zip(T, [2, 10, -4, -8, -6]))),
         tip=spline(t, list(zip(T, [0, 8, -10, -14, -12]))))
    # the hit throws the scarf forward-up over the shoulder line, then it falls back
    scarf_flow(P, t / 0.45, lift=spline(t, list(zip(T, [-4, 30, 16, -6, -6]))),
               bend=spline(t, list(zip(T, [-44, 30, 6, -36, -44]))),
               spread=spline(t, list(zip(T, [0, 20, 14, 4, 0]))), amp=5, waves=1.0, k=0.9, side_amp=4, twist=8)
    return done(P)


# ============================================================================= item clips
# O jogo prende os itens nos ossos de encaixe: grip_R / grip_L (centro da palma, +Y = eixo do item, para o
# lado do polegar), back_slot (bastão guardado nas costas), belt_L / belt_R (gancho e lanterna no quadril).
STAFF_TIP = 0.60          # do ponto de pega até a ponta do bastão (para os alvos dos golpes)


def c_attack_1(t, ph):
    """Bastão, golpe 1 (0,38 s): varrida da direita para a esquerda. 2 quadros de antecipação (bastão
    armado atrás do ombro direito, tronco girado), varrida rápida com o tronco (contato ~0,15 s), arrasto
    até a esquerda (smear) e volta à guarda."""
    P = Pose(K)
    T = [0.0, 0.067, 0.11, 0.15, 0.22, 0.30, 0.38]
    tw = spline(t, list(zip(T, [0, -26, -8, 16, 30, 14, 0])))              # + = torso to his left
    lunge = spline(t, list(zip(T, [0.0, -0.012, 0.012, 0.030, 0.034, 0.016, 0.0])))
    body(P, pitch=spline(t, list(zip(T, [3, 0, 5, 9, 10, 6, 3]))), yaw=tw * 0.35, pivot=(0, 0.01, 0.30),
         off=(0, -lunge, -0.014 - 0.5 * lunge))
    spine(P, sp=(0, 0, tw * 0.25), ch=(spline(t, list(zip(T, [2, -2, 4, 6, 6, 4, 2]))), 0, tw * 0.40),
          nk=(0, 0, -tw * 0.35), hd=(-2, 0, -tw * 0.40))
    stance(P)
    gp = vspline(t, list(zip(T, [(-0.13, -0.15, 0.38), (-0.17, 0.03, 0.51), (-0.15, -0.15, 0.45), (-0.03, -0.25, 0.41),
                                 (0.09, -0.17, 0.39), (-0.05, -0.20, 0.38), (-0.13, -0.15, 0.38)])))
    sy = spline(t, list(zip(T, [14, -150, -72, 24, 112, 62, 14])))
    se = spline(t, list(zip(T, [40, 26, 8, 0, -4, 18, 40])))
    pole = vspline(t, list(zip(T, [(-1, 0.4, -0.6), (-1, 0.6, 0.2), (-1, 0.1, -0.4), (-0.6, -0.4, -0.8),
                                   (0.2, -0.6, -0.8), (-0.8, 0.0, -0.7), (-1, 0.4, -0.6)])))
    hold(P, "R", gp, pole, dvec(sy, se))
    # free arm: counter-swing
    arm(P, "L", swing=spline(t, list(zip(T, [-10, -30, -20, 10, 26, 6, -10]))),
        out=spline(t, list(zip(T, [12, 24, 20, 30, 28, 16, 12]))), twist=-6,
        flex=spline(t, list(zip(T, [40, 60, 50, 36, 30, 36, 40]))), hand=(6, 0, -6))
    curl(P, "L", 60)
    tuft(P, lift=spline(t, list(zip(T, [0, 6, 0, -10, -8, -4, 0]))), diff=tw * 0.3)
    scarf_flow(P, t / 0.38, lift=spline(t, list(zip(T, [0, 4, 6, 10, 14, 8, 2]))), bend=-30,
               drift=spline(t, list(zip(T, [0, -10, 0, 20, 34, 16, 0]))), amp=6, waves=1.2, k=0.9, side_amp=4,
               twist=8)
    return done(P)


def c_attack_2(t, ph):
    """Bastão, golpe 2 (0,38 s): revés da esquerda para a direita (o braço cruza o peito na antecipação)."""
    P = Pose(K)
    T = [0.0, 0.067, 0.11, 0.15, 0.22, 0.30, 0.38]
    tw = spline(t, list(zip(T, [0, 28, 12, -14, -32, -14, 0])))
    lunge = spline(t, list(zip(T, [0.0, -0.010, 0.012, 0.030, 0.034, 0.016, 0.0])))
    body(P, pitch=spline(t, list(zip(T, [3, 1, 5, 9, 10, 6, 3]))), yaw=tw * 0.35, pivot=(0, 0.01, 0.30),
         off=(0, -lunge, -0.014 - 0.5 * lunge))
    spine(P, sp=(0, 0, tw * 0.25), ch=(spline(t, list(zip(T, [2, 0, 4, 6, 6, 4, 2]))), 0, tw * 0.40),
          nk=(0, 0, -tw * 0.35), hd=(-2, 0, -tw * 0.40))
    stance(P, yl=12, yr=-6)
    gp = vspline(t, list(zip(T, [(-0.13, -0.15, 0.38), (0.05, -0.08, 0.48), (0.02, -0.21, 0.45), (-0.10, -0.25, 0.41),
                                 (-0.20, -0.13, 0.39), (-0.17, -0.17, 0.38), (-0.13, -0.15, 0.38)])))
    sy = spline(t, list(zip(T, [14, 142, 70, -26, -114, -48, 14])))
    se = spline(t, list(zip(T, [40, 22, 6, 0, -4, 18, 40])))
    pole = vspline(t, list(zip(T, [(-1, 0.4, -0.6), (-0.4, -1.0, 0.4), (-0.6, -1.0, 0.0), (-1.0, -0.3, -0.4),
                                   (-1.0, 0.4, -0.5), (-1.0, 0.3, -0.6), (-1, 0.4, -0.6)])))
    hold(P, "R", gp, pole, dvec(sy, se))
    arm(P, "L", swing=spline(t, list(zip(T, [-10, 14, 6, -16, -28, -14, -10]))),
        out=spline(t, list(zip(T, [12, 30, 24, 22, 30, 18, 12]))), twist=-6,
        flex=spline(t, list(zip(T, [40, 40, 44, 50, 46, 42, 40]))), hand=(6, 0, -6))
    curl(P, "L", 60)
    tuft(P, lift=spline(t, list(zip(T, [0, 6, 0, -10, -8, -4, 0]))), diff=tw * 0.3)
    scarf_flow(P, t / 0.38, lift=spline(t, list(zip(T, [0, 4, 6, 10, 14, 8, 2]))), bend=-30,
               drift=spline(t, list(zip(T, [0, 14, 4, -12, -20, -8, 0]))), amp=6, waves=1.2, k=0.9, side_amp=4,
               twist=8)
    return done(P)


def c_attack_3(t, ph):
    """Bastão, golpe final (0,55 s): pancada por cima. Agacha (antecipação), sobe com o bastão erguido
    atrás da cabeça (as duas mãos), desce numa pancada no chão à frente (impacto ~0,24 s) e segura a pose
    mais forte do combo (agachado, base larga, cachecol para o alto) antes de voltar à guarda."""
    P = Pose(K)
    T = [0.0, 0.067, 0.14, 0.20, 0.24, 0.30, 0.42, 0.55]
    hz = spline(t, list(zip(T, [-0.014, -0.045, 0.030, 0.012, -0.098, -0.108, -0.090, -0.014])))
    pit = spline(t, list(zip(T, [3, 8, -12, 4, 24, 27, 22, 3])))
    body(P, pitch=pit, pivot=(0, 0.01, 0.30), off=(0, spline(t, list(zip(T, [0, 0.01, 0.01, -0.01, -0.03, -0.03, -0.025, 0]))), hz))
    spine(P, sp=(spline(t, list(zip(T, [0, 4, -8, 2, 10, 10, 8, 0]))), 0, 0),
          ch=(spline(t, list(zip(T, [2, 6, -10, 4, 12, 12, 10, 2]))), 0, 0),
          nk=(spline(t, list(zip(T, [0, 0, 4, 0, -10, -12, -10, 0]))), 0, 0),
          hd=(spline(t, list(zip(T, [-2, -4, 2, -2, -16, -18, -14, -2]))), 0, 0))
    up = spline(t, list(zip(T, [0, 0, 0.6, 0.2, 0, 0, 0, 0])))
    foot(P, "L", (0.024, -0.060, 0.0), yaw=12, pitch=10 * up, pivot="ball" if up > 0.05 else "ankle")
    foot(P, "R", (0.026, 0.055, 0.0), yaw=-6, pitch=14 * up, pivot="ball" if up > 0.05 else "ankle")
    gp = vspline(t, list(zip(T, [(-0.13, -0.15, 0.38), (-0.12, -0.10, 0.34), (-0.18, 0.03, 0.64), (-0.10, -0.17, 0.55),
                                 (-0.02, -0.27, 0.28), (-0.02, -0.27, 0.25), (-0.03, -0.25, 0.28), (-0.13, -0.15, 0.38)])))
    d = vspline(t, list(zip(T, [tuple(dvec(14, 40)), tuple(dvec(8, 52)), (-0.25, 0.45, 0.86), (-0.05, -0.35, 0.94),
                                tuple(dvec(0, -30)), tuple(dvec(0, -32)), tuple(dvec(0, -26)), tuple(dvec(14, 40))])))
    pole = vspline(t, list(zip(T, [(-1, 0.4, -0.6), (-1, 0.3, -0.6), (-1, 0.2, -0.2), (-1, -0.3, -0.3),
                                   (-1, 0.0, -0.6), (-1, 0.0, -0.6), (-1, 0.0, -0.6), (-1, 0.4, -0.6)])))
    hold(P, "R", gp, pole, d)
    # left hand joins the staff on the downswing (below the right hand along the staff) for the slam
    two = spline(t, list(zip(T, [0, 0, 0, 0.6, 1, 1, 1, 0])))
    dn = d.normalized()
    if two > 0.02:
        gl = grip_pos(P, "R") - dn * 0.095 + Vector((0.008, 0.0, 0.0))
        free = Vector((0.15, -0.06, 0.36))
        hold(P, "L", free.lerp(gl, two), Vector((1.0, 0.2, -0.6)), dn, grip=100.0 * two)
    else:
        arm(P, "L", swing=-14, out=16, twist=-6, flex=44, hand=(6, 0, -6))
        curl(P, "L", 60)
    tuft(P, lift=spline(t, list(zip(T, [0, -6, 14, 6, -20, -18, -12, 0]))),
         tip=spline(t, list(zip(T, [0, -4, 10, 4, -12, -10, -6, 0]))))
    # the scarf follows the hop and flies up at the impact
    scarf_flow(P, t / 0.55, lift=spline(t, list(zip(T, [0, 6, -14, -4, 30, 26, 10, 0]))),
               bend=spline(t, list(zip(T, [-36, -30, -46, -30, 30, 24, -10, -36]))),
               spread=spline(t, list(zip(T, [0, 4, 0, 6, 22, 24, 14, 0]))), amp=6, waves=1.5, k=0.9, side_amp=5,
               twist=10)
    return done(P)


def c_grapple_throw(t, ph):
    """Gancho (0,35 s): arma o braço direito atrás (2 quadros) e lança para a frente e para cima
    (solta ~0,12 s); termina apontando para onde o gancho foi (a corda sai da mão)."""
    P = Pose(K)
    T = [0.0, 0.067, 0.12, 0.17, 0.25, 0.35]
    tw = spline(t, list(zip(T, [0, -24, 8, 16, 10, 6])))
    body(P, pitch=spline(t, list(zip(T, [2, -4, 8, 10, 7, 5]))), yaw=tw * 0.35, pivot=(0, 0.01, 0.30),
         off=(0, spline(t, list(zip(T, [0, 0.012, -0.010, -0.020, -0.016, -0.012]))), -0.012))
    spine(P, sp=(0, 0, tw * 0.25), ch=(spline(t, list(zip(T, [0, -6, 6, 8, 5, 4]))), 0, tw * 0.4),
          nk=(0, 0, -tw * 0.35), hd=(spline(t, list(zip(T, [0, 2, -10, -14, -12, -10]))), 0, -tw * 0.40))
    stance(P)
    gp = vspline(t, list(zip(T, [(-0.13, -0.13, 0.37), (-0.17, 0.09, 0.50), (-0.17, -0.17, 0.62), (-0.17, -0.21, 0.64),
                                 (-0.17, -0.20, 0.63), (-0.17, -0.19, 0.62)])))
    d = vspline(t, list(zip(T, [tuple(dvec(0, 20)), tuple(dvec(170, -30)), tuple(dvec(0, 60)), tuple(dvec(0, 48)),
                                tuple(dvec(0, 42)), tuple(dvec(0, 40))])))
    pole = vspline(t, list(zip(T, [(-1, 0.4, -0.6), (-0.6, 0.2, 0.8), (-1, 0.0, -0.3), (-1, 0.2, -0.6),
                                   (-1, 0.2, -0.6), (-1, 0.2, -0.6)])))
    hold(P, "R", gp, pole, d, grip=spline(t, list(zip(T, [100, 100, 80, 30, 24, 24]))))
    arm(P, "L", swing=spline(t, list(zip(T, [-8, -40, -10, 14, 8, 4]))), out=spline(t, list(zip(T, [10, 20, 16, 14, 12, 12]))),
        twist=-6, flex=spline(t, list(zip(T, [36, 30, 50, 56, 50, 46]))), hand=(6, 0, -6))
    curl(P, "L", 50)
    tuft(P, lift=spline(t, list(zip(T, [0, 6, -8, -10, -8, -6]))))
    scarf_flow(P, t / 0.35, lift=spline(t, list(zip(T, [0, 2, 8, 12, 8, 4]))), bend=-30,
               drift=spline(t, list(zip(T, [0, -10, 10, 16, 10, 6]))), amp=6, waves=1.0, k=0.9, side_amp=4, twist=8)
    return done(P)


SWING_R = (-0.028, -0.150, 0.655)     # pega na corda (mãos na frente do queixo: com os braços curtos
SWING_L = (0.026, -0.150, 0.592)      # do chibi, acima da cabeça não alcança); a mão direita em cima


def c_swing(t, ph):
    """Pendurado na corda (laço 1,0 s): as duas mãos na corda (direita em cima), cabeça para trás olhando
    a corda, pernas juntas balançando (bombeando) e o corpo pendulando em volta das mãos; o cachecol
    arrasta do lado oposto ao balanço."""
    P = Pose(K)
    s1 = wv(ph)                         # + = legs forward
    s2 = wv(ph, 0.12)
    piv = (0.0, -0.15, 0.62)
    body(P, pitch=-6 - 7 * s2, roll=1.5 * wv(ph, 0.3), pivot=piv, off=(0, 0, 0.0))
    spine(P, sp=(-2 - 3 * s1, 0, 0), ch=(-2, 0, 0), nk=(-8, 0, 0), hd=(-16 + 2 * s2, 0, 0))
    for s, gp, pole in (("R", SWING_R, (-1.0, 0.2, -0.5)), ("L", SWING_L, (1.0, 0.2, -0.5))):
        hold(P, s, gp, pole, (0.0, 0.0, 1.0), grip=105.0)
    # legs together, knees a little bent, swinging from the hips
    swing_leg = 22.0 * s1
    for s in "LR":
        sx = sxs(s)
        P.turn(f"thigh_{s}", qw(x=-swing_leg - 8, z=sx * 3))
        P.turn(f"shin_{s}", qw(x=18 + 10 * clamp01(-s1)))
        P.turn(f"foot_{s}", qw(x=20 - 6 * s1))
    tuft(P, lift=-6 * s2, tip=-4 * s2)
    # the scarf trails opposite to the swing (forward swing -> it streams back and up)
    scarf_flow(P, ph, lift=4 + 18 * s2, bend=-30 + 22 * s2, spread=8, amp=6, waves=2, k=0.85, side_amp=5,
               twist=10)
    return done(P)


def c_pull(t, ph):
    """Puxão (0,5 s): as duas mãos na corda (que sai para a frente), um quadro de antecipação inclinado
    para a frente, depois puxa forte para trás: tronco para trás, o pé direito recua, mãos ao peito."""
    P = Pose(K)
    T = [0.0, 0.067, 0.16, 0.26, 0.38, 0.50]
    pit = spline(t, list(zip(T, [3, 9, -20, -24, -19, -15])))
    body(P, pitch=pit, pivot=(0, 0.01, 0.30), off=(0, spline(t, list(zip(T, [0.0, -0.012, 0.045, 0.055, 0.048, 0.040]))),
                                                  spline(t, list(zip(T, [-0.012, -0.020, -0.048, -0.058, -0.050, -0.044])))))
    spine(P, ch=(spline(t, list(zip(T, [2, 6, -8, -10, -8, -6]))), 0, 0),
          hd=(spline(t, list(zip(T, [0, 2, 10, 12, 10, 8]))), 0, 0))
    foot(P, "L", (0.018, -0.045, 0.0), yaw=8)
    ry = spline(t, list(zip(T, [0.030, 0.030, 0.110, 0.125, 0.125, 0.125])))
    rz = spline(t, list(zip(T, [0.0, 0.0, 0.035, 0.0, 0.0, 0.0])))
    foot(P, "R", (0.020, ry, rz), yaw=-4, pitch=spline(t, list(zip(T, [0, 0, 12, 0, 0, 0]))))
    rope = dvec(0, 10)
    gr = vspline(t, list(zip(T, [(-0.03, -0.23, 0.40), (-0.03, -0.27, 0.41), (-0.035, -0.13, 0.44), (-0.035, -0.10, 0.43),
                                 (-0.035, -0.12, 0.43), (-0.035, -0.14, 0.42)])))
    hold(P, "R", gr, (-1.0, 0.6, -0.4), rope, grip=105.0)
    hold(P, "L", gr - rope * 0.085 + Vector((0.035, 0.0, 0.0)), (1.0, 0.6, -0.4), rope, grip=105.0)
    tuft(P, lift=spline(t, list(zip(T, [0, -6, 14, 10, 6, 4]))))
    scarf_flow(P, t / 0.5, lift=spline(t, list(zip(T, [0, 4, -12, -10, -6, -4]))),
               bend=spline(t, list(zip(T, [-36, -30, -50, -46, -42, -40]))), amp=5, waves=1.0, k=0.9, side_amp=4,
               twist=8)
    return done(P)


LANTERN_BONES = ("upperarm_L", "forearm_L", "hand_L", "fingers_L")


def c_lantern_hold(t, ph):
    """Lanterna (laço 1,5 s, camada de corpo superior): SÓ o braço esquerdo é chaveado. A lanterna (em
    grip_L, eixo para cima) fica erguida à frente na altura do ombro, com um balanço suave."""
    P = Pose(K)
    sw = wv(ph)
    sw2 = wv(ph * 2, 0.2)
    gp = (0.112 + 0.006 * sw, -0.200 + 0.004 * sw2, 0.486 + 0.008 * sw2)
    hold(P, "L", gp, (1.0, 0.2, -0.9), dvec(-6 + 4 * sw, 80 + 3 * sw2), grip=100.0)
    out = P.export()
    return {b: v for b, v in out.items() if b in LANTERN_BONES}


def c_horn_blow(t, ph):
    """Búzio (0,7 s): leva o búzio à boca com a mão direita, enche o peito e sopra inclinando para trás
    (cabeça para cima); volta."""
    P = Pose(K)
    T = [0.0, 0.10, 0.18, 0.26, 0.50, 0.60, 0.70]
    pit = spline(t, list(zip(T, [2, 4, -2, -8, -10, -4, 2])))
    body(P, pitch=pit, pivot=(0, 0.01, 0.30), off=(0, spline(t, list(zip(T, [0, 0, 0.006, 0.014, 0.016, 0.008, 0]))),
                                                  -0.010))
    spine(P, sp=(spline(t, list(zip(T, [0, 0, -3, -6, -7, -3, 0]))), 0, 0),
          ch=(spline(t, list(zip(T, [0, -2, -6, -10, -11, -4, 0]))), 0, 0),
          nk=(spline(t, list(zip(T, [0, 0, -4, -6, -7, -3, 0]))), 0, 0),
          hd=(spline(t, list(zip(T, [0, 2, -6, -12, -14, -6, 0]))), 0, 0))
    stand_feet(P)
    to = spline(t, list(zip(T, [0, 0.55, 1.0, 1.0, 1.0, 0.45, 0])))
    Hq = P.world("head").to_quaternion() @ K.rrot["head"].inverted()
    dh = Hq @ dvec(-24, 26)
    at_mouth = mouth_world(P) + dh * 0.050 + Hq @ Vector((-0.004, 0.0, -0.006))
    rest_gp = Vector((-0.13, -0.10, 0.36))
    gp = rest_gp.lerp(at_mouth, to)
    d = dvec(-10, 20).lerp(dh, to)
    hold(P, "R", gp, (-1.0, 0.1, -0.5), d, grip=100.0)
    arm(P, "L", swing=-4, out=spline(t, list(zip(T, [2, 6, 12, 16, 16, 8, 2]))), twist=-6,
        flex=spline(t, list(zip(T, [22, 26, 34, 40, 40, 30, 22]))), hand=(6, 0, -6))
    curl(P, "L", spline(t, list(zip(T, [24, 30, 70, 80, 80, 40, 24]))))
    tuft(P, lift=spline(t, list(zip(T, [0, 2, 8, 14, 14, 6, 0]))))
    scarf_flow(P, t / 0.7, lift=spline(t, list(zip(T, [-4, 0, 6, 16, 22, 8, -4]))),
               bend=spline(t, list(zip(T, [-46, -40, -30, -16, -10, -30, -46]))),
               spread=spline(t, list(zip(T, [0, 0, 4, 10, 14, 6, 0]))), amp=7, waves=3.0, k=0.85, side_amp=5,
               twist=10)
    return done(P)


CLIPS = [
    ("rest", 0.067, c_rest, False),
    ("preview", 0.067, c_preview, False),
    # Saeli's 14 clips (same names and timing)
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
    # items
    ("attack_1", 0.38, c_attack_1, False),
    ("attack_2", 0.38, c_attack_2, False),
    ("attack_3", 0.55, c_attack_3, False),
    ("grapple_throw", 0.35, c_grapple_throw, False),
    ("swing", 1.0, c_swing, True),
    ("pull", 0.5, c_pull, False),
    ("lantern_hold", 1.5, c_lantern_hold, True),
    ("horn_blow", 0.7, c_horn_blow, False),
]
MODEL_CLIPS = ["rest", "preview"]
# clipes que só chaveiam parte do corpo (camadas): o .glb sai só com os canais destes ossos
PARTIAL_CLIPS = {"lantern_hold": LANTERN_BONES}


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


def strip_partial_channels(glb: Path) -> None:
    """Clipes de camada (PARTIAL_CLIPS, ex.: lantern_hold só no braço esquerdo): o exportador glTF amostra
    todos os ossos em toda ação; aqui o .glb fica só com os canais dos ossos que o clipe chaveia."""
    import json
    import struct
    data = glb.read_bytes()
    jlen = struct.unpack_from("<I", data, 12)[0]
    J = json.loads(data[20:20 + jlen])
    rest = data[20 + jlen:]
    nodes = J["nodes"]
    changed = []
    for a in J.get("animations", []):
        keep = PARTIAL_CLIPS.get(a.get("name"))
        if not keep:
            continue
        chans, samps = [], []
        for c in a["channels"]:
            if nodes[c["target"]["node"]].get("name") in keep:
                samps.append(a["samplers"][c["sampler"]])
                c = dict(c)
                c["sampler"] = len(samps) - 1
                chans.append(c)
        a["channels"], a["samplers"] = chans, samps
        changed.append(f"{a['name']} ({len(chans)} canais)")
    if not changed:
        return
    js = json.dumps(J, separators=(",", ":")).encode()
    js += b" " * ((4 - len(js) % 4) % 4)
    head = struct.pack("<III", 0x46546C67, 2, 20 + len(js) + len(rest)) + struct.pack("<II", len(js), 0x4E4F534A)
    glb.write_bytes(head + js + rest)
    log("clipes parciais:", ", ".join(changed))


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
    strip_partial_channels(OUT_GLB)
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
    strip_partial_channels(OUT_GLB)
    log(f"Sael: total {time.time() - t0:.1f}s")


if __name__ == "__main__":
    main()
