"""SOPRO — HULVAR, o navio-guardião (herói forte, 1,40 m). Design: game/design/herois.md.

    blender -b --factory-startup --python game/blender/build_hulvar.py [-- --fast] [--noanim]

Saída: game/assets/characters/hulvar.glb (malha única com skin + animações) e
game/blender/hulvar.blend (fonte editável).

Modelagem por campos de distância (lib/sdfkit.py): cada peça é um Shape com um material
(stone = esmalte do casco/placas, metal = latão, glow = lanterna/escotilhas/glifo/runa,
glyph = só o ponto de cima do Glifo de Rumo, eye = olhos de escotilha). Peças que
precisam de bordas nítidas (amurada, aros, quilha...) ficam em Shapes próprios.
As animações usam FK/IK próprios (pés plantados, punhos na areia, cesto nivelado).

Convenção: Blender Z-up, personagem olhando para -Y, lado esquerdo em +X.
"""
from __future__ import annotations

import math
import sys
import time
from pathlib import Path

import numpy as np

LIB = Path(__file__).resolve().parent / "lib"
if str(LIB) not in sys.path:
    sys.path.insert(0, str(LIB))

import sdfkit as K  # noqa: E402
from sdfkit import (Shape, blade, box, capsule, cone, cylinder, ellipsoid, hexcol, look_basis,  # noqa: E402
                    plane, round_cone, sphere, torus, tube)

ROOT = Path(__file__).resolve().parents[2]
OUT_GLB = ROOT / "game" / "assets" / "characters" / "hulvar.glb"
OUT_BLEND = ROOT / "game" / "blender" / "hulvar.blend"

# ----------------------------------------------------------------------------- palette
# Value plan: a LIGHT sea-glass hull with DARK indigo fittings (visor, stem/keel, jaw, plates, limbs),
# ivory only on the porthole "oculi", the deck and the nest. In the game light the old teal-blue glaze
# rendered as cobalt at the same value as the indigo plates; this keeps a >2.5:1 hull:plate ratio.
HULL_LO = hexcol("3F7FA8")      # esmalte vidro-do-mar (baixo)
HULL_HI = hexcol("6FAAC6")      # esmalte vidro-do-mar (alto)
KEEL = hexcol("2B3A87")         # Night Indigo — roda de proa (stem) + quilha
INDIGO = hexcol("343C96")       # Indigo Glaze — viseira, mandíbula, placas, antebraços, punhos, canelas
INDIGO_HI = hexcol("4650B0")    # brilho de cima do esmalte índigo
LIMB = hexcol("3A4699")         # braço e coxa: índigo um degrau mais claro (lê a articulação)
IVORY = hexcol("F5ECD7")        # Shell Ivory — óculos dos olhos, convés, cesto, solas
IVORY_SH = hexcol("E3D5B8")
BRASS = hexcol("D4A33F")
BRASS_HI = hexcol("F2CF72")
GLASS = hexcol("4FE3D6")        # Glass Cyan
GLOW = hexcol("8FFFF2")         # brilho
MOON = hexcol("CFD6E6")         # Moonstone — âncora
MOON_SH = hexcol("9AA6C4")
MOUTH = hexcol("141A3F")
SOCKET = hexcol("1C2458")

# ----------------------------------------------------------------------------- hull geometry (a boat on legs)
# Side: sheer deck rising to a raked stem, forefoot curving into the keel, raked transom.
# Front: V bow with a crisp stem ridge, flat-ish flanks, deadrise bottom narrowing to the keel.
# Plan: pointed bow, straight flanks, square stern.
BODY_C, BODY_R, BODY_N = (0.0, -0.10, 0.92), (0.43, 0.75, 0.60), 4.0
STEM_P = (0.0, -0.548, 0.900)      # a point of the stem (apex of the bow V)
BOW_ENTRY = 52.0                   # half-angle of the bow in plan view (deg)
BOW_RAKE = 0.30                    # stem rake dy/dz: the bow leans forward at the top
KEEL_Z = 0.370                     # bottom of the deadrise V
DEADRISE = 22.0                    # bottom V in the front view (deg)
STERN_Y = 0.460
STERN_N = (0.0, 1.0, -0.18)        # raked transom
DECK_Z0, DECK_Y0, DECK_A, DECK_B = 1.185, 0.03, 0.34, 0.10   # deck: z0 + A (y - y0)^2 + B x^2 -> sheer
STEM_PROUD, STEM_HW = 0.026, 0.0225                        # cutwater ridge: 2.6 cm proud, 4.5 cm wide
VISOR_OFF = 0.022                  # visor stands 2.2 cm off the bow (no brim)
NEST_C = (0.0, 0.220, 1.190)       # nest floor centre (Saeli's feet); 7 cm aft of the deck centre
SHOULDER = (0.360, -0.030, 1.010)
ELBOW = (0.490, -0.060, 0.700)
WRIST = (0.535, -0.125, 0.350)
FIST_C = (0.537, -0.163, 0.190)                   # fist box centre (bottom at z ~0.06: gorilla-long arms)
PORT_YS = (-0.010, 0.100, 0.210, 0.320)           # row of side portholes
PORT_Z = 0.860
PORT_R = 0.034


def _bow_normal(sx):
    a = math.radians(BOW_ENTRY)
    n = np.array([math.cos(a) * sx, -math.sin(a), -BOW_RAKE * math.sin(a)])
    return n / np.linalg.norm(n)


BOW_NL, BOW_NR = tuple(_bow_normal(1.0)), tuple(_bow_normal(-1.0))


def bow_face_y(x, z):
    """y of the bow V plane at (x, z) (sharp, without the stem rounding)."""
    n = _bow_normal(1.0)
    return STEM_P[1] + (n[0] * abs(x) + n[2] * (z - STEM_P[2])) / -n[1]


EYE_R = 0.088
EYE_X, EYE_Z = 0.150, 1.050
EYE_FWD = np.array([0.30, -1.0, -0.05])
EYE_C = np.array([EYE_X, bow_face_y(EYE_X, EYE_Z) + 0.046, EYE_Z])   # left eye centre (+X), 4.6 cm in the bow
RIM_MAJOR = 0.098


def deck_z(x, y):
    u = y - DECK_Y0
    return DECK_Z0 + DECK_A * u * u + DECK_B * x * x


def deck_prim():
    """Half-space above the deck surface (negative above): carving it leaves a sheered deck."""
    def f(P):
        u = P[:, 1] - DECK_Y0
        zd = DECK_Z0 + DECK_A * u * u + DECK_B * P[:, 0] ** 2
        g = np.sqrt(1.0 + (2.0 * DECK_A * u) ** 2 + (2.0 * DECK_B * P[:, 0]) ** 2)
        return (zd - P[:, 2]) / g
    return K.Prim(f, (-1e3,) * 3, (1e3,) * 3)


def superellipsoid(c, r, n=2.6):
    """Rounded-box-like blob: (|x/a|^n + |y/b|^n + |z/c|^n)^(1/n) = 1 (approximate distance)."""
    c = np.asarray(c, float)
    r = np.asarray(r, float)
    rmin = float(r.min())

    if n == 4.0:                      # fast path: powers by squaring
        def f(P):
            q = (P - c) / r
            q = q * q
            k = np.sqrt(np.sqrt((q * q).sum(axis=1)))
            return (k - 1.0) * rmin
    else:
        def f(P):
            q = np.abs((P - c) / r)
            k = np.power(np.power(q, n).sum(axis=1), 1.0 / n)
            return (k - 1.0) * rmin
    return K.Prim(f, c - r, c + r)


def memo(prim):
    """Cache the last evaluation: region copies of the hull share one body evaluation."""
    cache = {"key": None, "val": None}
    fn = prim.fn

    def f(P):
        n = len(P)
        key = (id(P), n, P[0].tobytes() if n else b"", P[n // 2].tobytes() if n else b"", P[-1].tobytes() if n else b"")
        if cache["key"] != key:
            cache["val"] = fn(P)
            cache["key"] = key
        return cache["val"]
    return K.Prim(f, prim.lo, prim.hi)


def bounded(prim, lo, hi):
    return K.Prim(prim.fn, lo, hi)


def slab(axis, lo, hi, k=0.0):
    """lo < P[axis] < hi as an SDF."""
    n = [0.0, 0.0, 0.0]
    n[axis] = 1.0
    p_hi = [0.0, 0.0, 0.0]
    p_hi[axis] = hi
    p_lo = [0.0, 0.0, 0.0]
    p_lo[axis] = lo
    return plane(tuple(p_hi), tuple(n)).clip(plane(tuple(p_lo), tuple(-a for a in n)), k)


def capsule_chain(points, r):
    """Constant-radius tube through a polyline (cheaper than sdfkit.tube)."""
    A = np.array([np.asarray(p, float) for p in points[:-1]])
    B = np.array([np.asarray(p, float) for p in points[1:]])
    BA = B - A
    L2 = np.maximum((BA * BA).sum(axis=1), 1e-12)

    def f(P):
        d = np.full(len(P), 1e9)
        for i in range(len(A)):
            pa = P - A[i]
            t = np.clip(pa @ BA[i] / L2[i], 0.0, 1.0)
            q = pa - np.outer(t, BA[i])
            d = np.minimum(d, np.einsum("ij,ij->i", q, q))
        return np.sqrt(d) - r
    allp = np.array([np.asarray(p, float) for p in points])
    return K.Prim(f, allp.min(axis=0) - r, allp.max(axis=0) + r)


def boat_body():
    """The hull: a rounded box cut into a boat (V bow with a crisp stem, deadrise bottom,
    rounded forefoot, keel rising aft, raked transom). The deck is carved later (sheer)."""
    b = superellipsoid(BODY_C, BODY_R, BODY_N)
    bow = plane(STEM_P, BOW_NL).clip(plane(STEM_P, BOW_NR), 0.030)          # V bow, crisp stem
    b = b.clip(bow, 0.085)                                                  # rounded bow shoulders
    sb, cb = math.sin(math.radians(DEADRISE)), math.cos(math.radians(DEADRISE))
    vee = plane((0, 0, KEEL_Z), (sb, 0, -cb)).clip(plane((0, 0, KEEL_Z), (-sb, 0, -cb)), 0.05)
    b = b.clip(vee, 0.10)                                                   # deadrise, round bilge
    b = b.clip(plane((0, -0.36, 0.56), (0, -0.62, -0.78)), 0.14)            # forefoot
    b = b.clip(plane((0, 0.30, 0.40), (0, 0.50, -0.866)), 0.10)             # the keel rises aft (run)
    b = b.clip(plane((0, STERN_Y, 0.90), STERN_N), 0.06)                    # transom
    return bounded(b, (-0.44, -0.76, 0.34), (0.44, 0.56, 1.44))


HEAD_Y, HEAD_Z, CHEST_Z, HIPS_Z = -0.24, 0.90, 0.98, 0.70


_BODY = None


def hull_core_parts():
    """Exclusive region-clipped copies of the boat (their union == boat): each region
    gets its own bone, so skin weights blend only near the region borders."""
    global _BODY
    if _BODY is None:
        _BODY = memo(boat_body())
    body = _BODY
    in_head = plane((0, HEAD_Y, 0), (0, 1, 0)).clip(plane((0, 0, HEAD_Z), (0, 0, -1)))
    not_head = plane((0, HEAD_Y, 0), (0, -1, 0)).union(plane((0, 0, HEAD_Z), (0, 0, 1)))
    out = {
        "head": body.clip(in_head),
        "chest": body.clip(plane((0, 0, CHEST_Z), (0, 0, -1))).clip(plane((0, HEAD_Y, 0), (0, -1, 0))),
        "spine": body.clip(plane((0, 0, CHEST_Z), (0, 0, 1))).clip(plane((0, 0, HIPS_Z), (0, 0, -1))).clip(not_head),
        "hips": body.clip(plane((0, 0, HIPS_Z), (0, 0, 1))),
    }
    return body, out


def hull_core():
    """Hull without the deck carve (used for bands, plates and placement)."""
    return hull_core_parts()[0]


def stem_band(proud=STEM_PROUD, hw=STEM_HW):
    """Cutwater ridge: the hull offset outward, kept in a thin slab around the centre line."""
    return hull_core().offset(proud).clip(slab(0, -hw, hw, 0.0), 0.010)


def eye_frame(sx):
    c = EYE_C * np.array([sx, 1, 1])
    f = EYE_FWD * np.array([sx, 1, 1])
    f = f / np.linalg.norm(f)
    side = np.cross(np.array([0, 0, 1.0]), f)
    side /= np.linalg.norm(side)
    if side[0] * sx < 0:
        side = -side                  # points outward
    up = np.cross(f, side)
    if up[2] < 0:
        up = -up
    return c, f, side, up


def rim_axis(sx):
    """Porthole rim axis: halfway between the eye's gaze and the bow face normal (sits flatter)."""
    f = eye_frame(sx)[1]
    n = np.array(BOW_NL if sx > 0 else BOW_NR)
    a = f * 0.55 + n * 0.45
    return a / np.linalg.norm(a)


def visor_prim():
    """Prow visor: the bow's top band under the gunwale, arcing over both porthole eyes
    (gull wing), only VISOR_OFF proud of the bow (no cap brim) and split by the stem."""
    core = hull_core()
    v = core.offset(VISOR_OFF)
    v = v.clip(plane((0, -0.25, 0), (0, 1, 0)), 0.045)                      # bow only, tapers away aft
    nl = np.array([0.0, 0.30, -1.0])
    v = v.clip(plane((0, -0.50, 1.150), tuple(nl / np.linalg.norm(nl))), 0.040)   # lower edge rises aft
    v = v.cut(deck_prim().offset(0.010), 0.006)                             # top: under the rail
    cuts = None
    for sx in (1, -1):
        c, f, side, up = eye_frame(sx)
        rc = c + f * 0.052
        cs = cylinder(tuple(rc + up * 0.006), RIM_MAJOR + 0.044, 0.40, look_basis(rim_axis(sx)))
        cuts = cs if cuts is None else cuts.union(cs, 0.05)
    v = v.cut(cuts, 0.040)                                                   # gull wing over the eyes
    v = v.cut(slab(0, -0.016, 0.016), 0.006)                                 # the stem runs through
    return bounded(v, (-0.47, -0.76, 1.08), (0.47, -0.20, 1.40))


def jaw_prim():
    """Underbite jaw: a bumper band around the lower bow, 2 cm proud, rounded chin."""
    core = hull_core()
    j = core.offset(0.020)
    j = j.clip(plane((0, 0, 0.902), (0, 0, 1)), 0.010)                       # top edge = mouth line
    nb = np.array([0.0, 0.30, -1.0])
    j = j.clip(plane((0, -0.50, 0.772), tuple(nb / np.linalg.norm(nb))), 0.035)   # chin, rising aft
    j = j.clip(plane((0, -0.335, 0), (0, 1, 0)), 0.05)                       # wraps the front only
    ridge = core.offset(0.032).clip(slab(0, -STEM_HW, STEM_HW, 0.0), 0.008)  # stem continues over the jaw
    ridge = ridge.clip(plane((0, 0, 0.900), (0, 0, 1)), 0.008).clip(plane((0, 0, 0.770), (0, 0, -1)), 0.02)
    j = j.union(ridge, 0.006)
    return bounded(j, (-0.34, -0.66, 0.70), (0.34, -0.25, 0.93))


def surface_point(field, origin, direction, r0=0.0, r1=1.2, iters=40):
    """First point where field crosses 0 marching from origin (inside) along direction."""
    o = np.asarray(origin, float)
    d = np.asarray(direction, float)
    d = d / np.linalg.norm(d)
    a, b = r0, r1
    n = 120
    prev = a
    for i in range(1, n + 1):
        t = r0 + (r1 - r0) * i / n
        if field(np.array([o + d * t]))[0] > 0.0:
            a, b = prev, t
            break
        prev = t
    for _ in range(iters):
        m = 0.5 * (a + b)
        if field(np.array([o + d * m]))[0] > 0.0:
            b = m
        else:
            a = m
    return o + d * 0.5 * (a + b)


def field_normal(field, p, eps=0.002):
    p = np.asarray(p, float)
    g = np.array([field(np.array([p + e]))[0] - field(np.array([p - e]))[0]
                  for e in (np.array([eps, 0, 0]), np.array([0, eps, 0]), np.array([0, 0, eps]))])
    return g / (np.linalg.norm(g) + 1e-12)


def rail_prim(r=0.019, inset=0.007, lift=0.003):
    """Gunwale rail: a round tube riding the deck edge, measured from the hull field at the rail
    height (narrow band: points far above/below the rail only get a vertical bound)."""
    cf = hull_core().fn

    def f(P):
        zr = deck_z(P[:, 0], P[:, 1]) + lift
        dz = P[:, 2] - zr
        out = np.abs(dz) - r
        near = np.nonzero(np.abs(dz) < r + 0.03)[0]
        if len(near):
            Q = P[near].copy()
            Q[:, 2] = zr[near]
            dh = cf(Q) + inset
            out[near] = np.sqrt(dh * dh + dz[near] ** 2) - r
        return out
    return K.Prim(f, (-0.47, -0.78, 1.14), (0.47, 0.58, 1.43))


def gunwale_loop(n=64):
    """Points along the deck edge (hull side meets the deck surface), closed loop; i=0 at the bow."""
    core = hull_core()
    pts = []
    for i in range(n):
        th = 2 * math.pi * i / n
        dx, dy = math.sin(th), -math.cos(th)
        a, b = 0.05, 0.85
        for _ in range(40):
            m = 0.5 * (a + b)
            x, y = dx * m, 0.0 + dy * m
            z = deck_z(x, y)
            if core(np.array([[x, y, z]]))[0] > 0.0:
                b = m
            else:
                a = m
        x, y = dx * a, 0.0 + dy * a
        pts.append(np.array([x, y, deck_z(x, y)]))
    return pts


# ----------------------------------------------------------------------------- shapes
def S(name, mat, voxel, tris, q, **kw):
    return Shape(name, mat, voxel=voxel * q, tris=tris, **kw)


def lens_xz(cx, half_w, z_top, z_bottom):
    """Shield outline in XZ (vesica of two Y-axis cylinders) clipped flat on top: an infinite prism along Y."""
    a = 0.20
    R = half_w + a
    zc = z_bottom + math.sqrt(R * R - a * a)
    ca = cylinder((cx + a, 0.0, zc), R, 3.0, (90, 0, 0))
    cb = cylinder((cx - a, 0.0, zc), R, 3.0, (90, 0, 0))
    return ca.clip(cb).clip(plane((0, 0, z_top), (0, 0, 1)))


def build_shapes(q: float = 1.0):
    """All SDF pieces. q scales the voxel size (q > 1 = faster, coarser)."""
    shapes = []
    info = {}
    body, parts = hull_core_parts()
    core = body
    deck = deck_prim()
    eyes = {sx: eye_frame(sx) for sx in (1, -1)}
    rim_c = {sx: eyes[sx][0] + eyes[sx][1] * 0.052 for sx in (1, -1)}

    # ---------------------------------------------------------------- hull (stone)
    hull = S("HulvarHull", "stone", 0.0066, 2800, q, color_soft=0.006, weight_sigma=0.05)
    hull.add(parts["chest"], "chest", HULL_HI, k=0.0)
    hull.add(parts["spine"], "spine", HULL_LO, k=0.0)
    hull.add(parts["hips"], "hips", HULL_LO, k=0.0)
    hull.add(parts["head"], "head", HULL_HI, k=0.0)
    # cutwater: stem ridge down the bow (head) -> under the jaw -> keel band to the groin
    band = stem_band()
    stem = bounded(band.clip(plane((0, 0, 0.905), (0, 0, -1)), 0.0).clip(plane((0, -0.30, 0), (0, 1, 0)), 0.0),
                   (-0.03, -0.76, 0.88), (0.03, -0.28, 1.42))
    keel = band.clip(plane((0, 0, 0.785), (0, 0, 1)), 0.0).clip(plane((0, 0.20, 0), (0, 1, 0)), 0.05)
    keel_hi = bounded(keel.clip(plane((0, 0, HIPS_Z), (0, 0, -1)), 0.0), (-0.03, -0.62, 0.66), (0.03, -0.20, 0.80))
    keel_lo = bounded(keel.clip(plane((0, 0, HIPS_Z), (0, 0, 1)), 0.0), (-0.03, -0.45, 0.31), (0.03, 0.24, 0.74))
    hull.add(stem, "head", KEEL, k=0.004)
    hull.add(keel_hi, "spine", KEEL, k=0.004)
    hull.add(keel_lo, "hips", KEEL, k=0.004)
    # side portholes (glow lens sits inside)
    port_c = []
    for sx in (1, -1):
        for py in PORT_YS:
            p = surface_point(core, (0.0, py, PORT_Z), (sx, 0, 0))
            n = field_normal(core, p)
            port_c.append((p, n, sx))
            hull.carve(sphere(tuple(p + n * 0.008), PORT_R + 0.004), 0.005, SOCKET)
    info["ports"] = port_c
    # mouth: a dark 1.5 cm slit between the face and the jaw (the throat glow sits at its back)
    slit = core.offset(-0.012).shell(0.034).clip(slab(2, 0.904, 0.920, 0.004), 0.0)
    slit = bounded(slit.clip(slab(0, -0.235, 0.235, 0.01), 0.0).clip(plane((0, -0.33, 0), (0, 1, 0)), 0.0),
                   (-0.25, -0.62, 0.89), (0.25, -0.30, 0.93))
    hull.carve(slit, 0.003, MOUTH)
    hull.carve(deck, 0.025)
    # stem head: the stem rises a hand above the bow tip (prow fin, brass cap)
    tip_y = bow_face_y(0.0, 1.36)
    stem_head = round_cone((0, tip_y + 0.045, 1.30), (0, tip_y - 0.018, 1.392), 0.024, 0.017)
    hull.add(stem_head, "head", KEEL, k=0.012)
    info["stem_tip"] = np.array([0.0, tip_y - 0.020, 1.397])
    # livery
    hull.paint(plane((0, 0, 0.86), (0, 0, 1)), HULL_LO, soft=0.30)              # vertical glaze gradient
    hull.paint(deck.offset(0.008).cut(deck.offset(-0.014)), IVORY, soft=0.006)   # ivory deck (a thin layer)
    hull.paint(stem_head.offset(0.002), KEEL, soft=0.004)
    jaw_bed = core.offset(0.03).clip(slab(2, 0.78, 0.905), 0.0).clip(plane((0, -0.36, 0), (0, 1, 0)), 0.0)
    hull.paint(jaw_bed, MOUTH, soft=0.008)                                       # mouth inside, seen when the jaw drops
    for sx in (1, -1):                                                           # eye sockets
        c = eyes[sx][0]
        hull.carve(sphere(tuple(c), EYE_R + 0.006), 0.010, SOCKET)
        hull.paint(sphere(tuple(c), EYE_R + 0.010), SOCKET, soft=0.004)
    hull.detail(ellipsoid((0, -0.54, 1.10), (0.34, 0.20, 0.32)), 0.55)
    shapes.append(hull)
    info["hull"] = hull

    # ---------------------------------------------------------------- ivory oculi (stone): raised inlays round the eyes
    face = S("HulvarFace", "stone", 0.0030, 300, q, color_soft=0.004, weight_sigma=0.02)
    outline = None
    for sx in (1, -1):
        n = np.array(BOW_NL if sx > 0 else BOW_NR)
        e = ellipsoid(tuple(rim_c[sx] + np.array([0.014 * sx, 0.0, -0.008])), (0.192, 0.172, 0.22), look_basis(n))
        outline = e if outline is None else outline.union(e, 0.06)
    outline = outline.union(box((0, -0.50, 0.975), (0.25, 0.25, 0.06), rounding=0.05), 0.06)   # cheeks to the mouth
    fp = core.offset(0.0075).clip(outline, 0.004)
    fp = fp.clip(plane((0, 0, 0.925), (0, 0, -1)), 0.004)                        # above the mouth
    for sx in (1, -1):
        fp = fp.cut(sphere(tuple(eyes[sx][0]), EYE_R + 0.010), 0.004)
    fp = bounded(fp, (-0.33, -0.65, 0.90), (0.33, -0.30, 1.23))
    face.add(fp, "head", IVORY, k=0.0)
    face.paint(sphere((0, 0, 0), 5.0), IVORY, soft=0.01, emission=0.12)         # stays ivory when backlit
    face.paint(plane((0, 0, 0.98), (0, 0, 1)), IVORY_SH, soft=0.05)
    shapes.append(face)

    # ---------------------------------------------------------------- prow visor (stone, rigid on brow)
    brow = S("HulvarBrow", "stone", 0.0040, 300, q, color_soft=0.004, weight_sigma=0.02)
    brow.add(visor_prim(), "brow", INDIGO, k=0.0)
    brow.paint(plane((0, 0, 1.235), (0, 0, -1)), INDIGO_HI, soft=0.03)
    shapes.append(brow)

    # ---------------------------------------------------------------- jaw (stone, rigid on jaw)
    jaw = S("HulvarJaw", "stone", 0.0040, 260, q, color_soft=0.004, weight_sigma=0.02)
    jaw.add(jaw_prim(), "jaw", INDIGO, k=0.0)
    jaw.paint(plane((0, 0, 0.880), (0, 0, -1)), INDIGO_HI, soft=0.02)
    jaw.paint(slab(0, -STEM_HW - 0.002, STEM_HW + 0.002).cut(core.offset(0.0205)), KEEL, soft=0.004)
    shapes.append(jaw)

    # ---------------------------------------------------------------- arms (stone): DK forearms, pinched elbow
    for sx, side in ((1, "L"), (-1, "R")):
        arm = S(f"HulvarArm_{side}", "stone", 0.0056, 590, q, color_soft=0.006, weight_sigma=0.035)
        X = lambda p: (p[0] * sx, p[1], p[2])  # noqa: E731
        sh_, el_, wr_ = np.array(SHOULDER), np.array(ELBOW), np.array(WRIST)
        arm.add(round_cone(X(sh_), X(el_), 0.104, 0.074), f"upperarm_{side}", LIMB, k=0.0)
        arm.add(round_cone(X(el_), X(wr_), 0.078, 0.126), f"forearm_{side}", INDIGO, k=0.028)
        fc = np.array(FIST_C)
        arm.add(box(X(fc), (0.140, 0.130, 0.128), rounding=0.072), f"hand_{side}", INDIGO, k=0.03)
        for x in (-0.074, -0.014, 0.046):
            arm.add(sphere(X(fc + np.array([x, -0.104, -0.050])), 0.042), f"hand_{side}", INDIGO, k=0.022)
        arm.add(capsule(X(fc + np.array([-0.122, -0.055, 0.057])), X(fc + np.array([-0.110, -0.108, -0.007])), 0.040), f"hand_{side}", INDIGO, k=0.02)
        shapes.append(arm)

    # ---------------------------------------------------------------- legs (stone)
    legs = S("HulvarLegs", "stone", 0.0058, 480, q, color_soft=0.006, weight_sigma=0.03)
    legs.add_mirrored(round_cone((0.190, 0.100, 0.560), (0.210, 0.070, 0.300), 0.124, 0.104), "thigh_L", LIMB, k=0.0)
    legs.add_mirrored(round_cone((0.210, 0.070, 0.300), (0.210, 0.080, 0.130), 0.104, 0.114), "shin_L", INDIGO, k=0.03)
    legs.add_mirrored(cylinder((0.210, 0.035, 0.068), 0.146, 0.068, rounding=0.045), "foot_L", INDIGO, k=0.035)
    legs.clip(plane((0, 0, 0.0), (0, 0, -1)), 0.0)
    legs.paint(plane((0, 0, 0.026), (0, 0, 1)), IVORY, soft=0.006)
    shapes.append(legs)

    # ---------------------------------------------------------------- plates: shoulder plates + transom shield (stone)
    plates = S("HulvarPlates", "stone", 0.0042, 250, q, color_soft=0.006, weight_sigma=0.03)
    for sx, side in ((1, "L"), (-1, "R")):
        sp = surface_point(core, (0.20 * sx, -0.02, 1.10), (sx, 0, 0.55))
        pl = core.offset(0.026).clip(sphere(tuple(sp), 0.165), 0.02).clip(plane((0, 0, 0.93), (0, 0, -1)), 0.02)
        pl = pl.cut(deck.offset(0.012), 0.003)                                   # hard top under the rail
        plates.add(pl.offset(-0.008), "chest", INDIGO, k=0.0)
        plates.add(pl, f"upperarm_{side}", INDIGO, k=0.0)                       # ~57% follows the arm
    plates.paint(plane((0, 0, 1.12), (0, 0, -1)), INDIGO_HI, soft=0.05)
    shapes.append(plates)
    stern_plate = S("HulvarStern", "stone", 0.0042, 210, q, color_soft=0.006, weight_sigma=0.03)
    sh = lens_xz(0.0, 0.300, 1.170, 0.600)
    sp_n = np.array(STERN_N) / np.linalg.norm(STERN_N)
    stern = core.offset(0.016).clip(sh, 0.012).clip(plane((0, STERN_Y - 0.03, 0.90), tuple(-sp_n)), 0.006)
    stern = bounded(stern, (-0.34, 0.36, 0.55), (0.34, 0.56, 1.22))
    stern_plate.add(stern, "chest", INDIGO, k=0.0)
    stern_plate.paint(plane((0, 0, 1.12), (0, 0, -1)), INDIGO_HI, soft=0.06)
    shapes.append(stern_plate)
    stern_c = surface_point(stern, (0, STERN_Y - 0.005, 0.94), (0, 1, 0))
    info["stern_c"] = stern_c

    # ---------------------------------------------------------------- crow's nest (stone, rigid on nest): ivory staves
    nx, ny, nz = NEST_C
    nest = S("HulvarNest", "stone", 0.0040, 360, q, color_soft=0.004, weight_sigma=0.02)
    nest.add(cone((nx, ny, 1.235), 0.170, 0.206, 0.092, rounding=0.018), "nest", IVORY, k=0.0)
    nest.carve(cone((nx, ny, nz + 0.110), 0.140, 0.176, 0.110), 0.010, SOCKET)
    slits = []
    for a_deg in (180.0, 128.0, -128.0):                                         # lantern slits (back and sides)
        a = math.radians(a_deg)
        d = np.array([math.sin(a), -math.cos(a), 0.0])
        c = np.array([nx, ny, 1.289]) + d * 0.19
        rot = look_basis(d)
        nest.carve(box(tuple(c), (0.011, 0.029, 0.06), rot, rounding=0.009), 0.004, SOCKET)
        slits.append((c, d))
    info["slits"] = slits
    nest.paint(cone((nx, ny, nz + 0.110), 0.150, 0.186, 0.116), SOCKET, soft=0.008)
    for i in range(12):                                                          # stave seams
        a = math.radians(15 + 30 * i)
        d = np.array([math.sin(a), -math.cos(a), 0.0])
        nest.paint(box(tuple(np.array([nx, ny, 1.27]) + d * 0.20), (0.0035, 0.10, 0.05), look_basis(d)), IVORY_SH, soft=0.003)
    nest.paint(plane((0, 0, 1.215), (0, 0, 1)), IVORY_SH, soft=0.03)
    shapes.append(nest)
    lip_z = 1.235 + 0.092

    # ---------------------------------------------------------------- anchor (stone)
    anc = S("HulvarAnchor", "stone", 0.0038, 290, q, color_soft=0.006, weight_sigma=0.02)
    anc.add(capsule((0, 0.690, 0.430), (0, 0.712, 0.245), 0.030), "anchor", MOON, k=0.0)
    arc = torus((0, 0.712, 0.372), 0.166, 0.034, (90, 0, 0)).clip(plane((0, 0, 0.345), (0, 0, 1)), 0.02)
    anc.add(arc, "anchor", MOON, k=0.03)
    for sx in (1, -1):
        fl = blade([(0.148 * sx, 0.712, 0.318), (0.190 * sx, 0.712, 0.372), (0.214 * sx, 0.712, 0.425)],
                   [0.040, 0.034, 0.010], flat=0.45, normal=(0, 1, 0))
        anc.add(fl, "anchor", MOON, k=0.025)
    anc.add(sphere((0, 0.712, 0.215), 0.042), "anchor", MOON, k=0.03)
    anc.paint(plane((0, 0, 0.27), (0, 0, 1)), MOON_SH, soft=0.07)
    shapes.append(anc)

    # ---------------------------------------------------------------- brass (metal)
    rail = S("HulvarGunwale", "metal", 0.0036, 320, q, color_soft=0.004, weight_sigma=0.05)
    rp = rail_prim()
    rail.add(bounded(rp.clip(plane((0, HEAD_Y + 0.04, 0), (0, 1, 0)), 0.0), (-0.47, -0.78, 1.16), (0.47, HEAD_Y + 0.05, 1.43)),
             "head", BRASS, k=0.0)
    rail.add(bounded(rp.clip(plane((0, HEAD_Y - 0.04, 0), (0, -1, 0)), 0.0), (-0.47, HEAD_Y - 0.05, 1.14), (0.47, 0.58, 1.31)),
             "chest", BRASS, k=0.0)
    rail.paint(plane((0, 0, 1.30), (0, 0, -1)), BRASS_HI, soft=0.03)
    shapes.append(rail)

    face_brass = S("HulvarEyeRims", "metal", 0.0030, 240, q, color_soft=0.004, weight_sigma=0.02)
    for sx in (1, -1):
        face_brass.add(torus(tuple(rim_c[sx]), RIM_MAJOR, 0.019, look_basis(rim_axis(sx))), "head", BRASS, k=0.0)
    face_brass.paint(plane((0, 0, 1.09), (0, 0, -1)), BRASS_HI, soft=0.03)
    shapes.append(face_brass)

    cap = S("HulvarStemCap", "metal", 0.0028, 40, q, color_soft=0.004, weight_sigma=0.02)
    cap.add(sphere(tuple(info["stem_tip"]), 0.022), "head", BRASS_HI, k=0.0)
    shapes.append(cap)

    tusks = S("HulvarTusks", "metal", 0.0028, 80, q, color_soft=0.004, weight_sigma=0.02)
    for sx in (1, -1):
        x0 = 0.232 * sx
        b0 = np.array([x0, bow_face_y(x0, 0.885) - 0.026, 0.870])
        rot = (0.0, -12.0 * sx, 0.0)                                             # tilted 12 deg outward
        up = K.euler(*rot) @ np.array([0, 0, 1.0])
        tusks.add(cylinder(tuple(b0 + up * 0.026), 0.0155, 0.026, rot, rounding=0.007), "jaw", BRASS, k=0.0)
        tusks.add(cylinder(tuple(b0 + up * 0.052), 0.0205, 0.007, rot, rounding=0.0055), "jaw", BRASS_HI, k=0.010)
    shapes.append(tusks)

    side_brass = S("HulvarPortRims", "metal", 0.0024, 340, q, color_soft=0.004, weight_sigma=0.02)
    for p, n, sx in port_c:
        side_brass.add(torus(tuple(p + n * 0.004), PORT_R + 0.004, 0.0115, look_basis(n)), "spine", BRASS, k=0.0)
    shapes.append(side_brass)

    for sx, side in ((1, "L"), (-1, "R")):
        ab = S(f"HulvarCuff_{side}", "metal", 0.0032, 85, q, color_soft=0.004, weight_sigma=0.02)
        el = np.array(ELBOW) * np.array([sx, 1, 1])
        wr = np.array(WRIST) * np.array([sx, 1, 1])
        fd = (wr - el) / np.linalg.norm(wr - el)
        ab.add(torus(tuple(wr - fd * 0.014), 0.128, 0.021, look_basis(fd)), f"forearm_{side}", BRASS, k=0.0)
        shapes.append(ab)

    nb = S("HulvarNestRail", "metal", 0.0034, 330, q, color_soft=0.004, weight_sigma=0.02)
    nb.add(torus((nx, ny, lip_z), 0.200, 0.019), "nest", BRASS, k=0.0)
    nb.add(torus((nx, ny, 1.247), 0.198, 0.013), "nest", BRASS, k=0.0)               # low hoop
    top_z = lip_z + 0.057
    nb.add(torus((nx, ny, top_z), 0.206, 0.021), "nest", BRASS, k=0.0)              # heavier top rail
    for i in range(6):
        a = math.radians(30 + 60 * i)
        px, py = nx + math.sin(a) * 0.203, ny - math.cos(a) * 0.203
        nb.add(capsule((px, py, lip_z), (px, py, top_z), 0.012), "nest", BRASS, k=0.008)
    nb.paint(plane((0, 0, top_z + 0.008), (0, 0, -1)), BRASS_HI, soft=0.01)
    shapes.append(nb)

    ch = S("HulvarChain", "metal", 0.0032, 210, q, color_soft=0.004, weight_sigma=0.012)
    hawse = surface_point(core, (0, 0.30, 0.680), (0, 1, 0))
    ch.add(torus(tuple(hawse + np.array([0, 0.008, 0])), 0.040, 0.014, look_basis((0, 1, 0))), "hips", BRASS, k=0.0)
    links = [((0, 0.440, 0.650), (0, 0.894, -0.447), "chain_1", 0),
             ((0, 0.555, 0.575), (0, 0.776, -0.631), "chain_2", 1),
             ((0, 0.650, 0.475), (0, 0.588, -0.809), "chain_3", 0)]
    for p, d, b, alt in links:
        d = np.asarray(d) / np.linalg.norm(d)
        side_v = np.array([1.0, 0, 0]) if alt == 0 else np.cross(d, np.array([1.0, 0, 0]))
        c = np.asarray(p)
        loop_pts = [c + d * math.cos(2 * math.pi * i / 12) * 0.058 + side_v * math.sin(2 * math.pi * i / 12) * 0.033
                    for i in range(13)]
        ch.add(tube(loop_pts, 0.0135), b, BRASS, k=0.0)
    ch.add(torus((0, 0.690, 0.448), 0.032, 0.012, look_basis((1, 0, 0))), "anchor", BRASS, k=0.0)
    ch.add(torus((0, 0.712, 0.262), 0.034, 0.011), "anchor", BRASS, k=0.0)
    shapes.append(ch)

    # ---------------------------------------------------------------- glow pieces
    ports = S("HulvarPortGlow", "glow", 0.0026, 110, q, color_soft=0.004, weight_sigma=0.02)
    for p, n, sx in port_c:
        ports.add(ellipsoid(tuple(p - n * 0.006), (PORT_R * 0.92, PORT_R * 0.92, 0.012), look_basis(n)), "spine", GLOW, k=0.0)
    ports.paint(sphere((0, 0, 0), 5.0), GLOW, soft=0.01, emission=1.0)
    shapes.append(ports)

    glyph = S("HulvarGlyph", "glow", 0.0024, 230, q, color_soft=0.004, weight_sigma=0.02)
    gc = stern_c
    gn = field_normal(stern, gc)
    glyph.add(torus(tuple(gc - gn * 0.001), 0.098, 0.011, look_basis(gn)), "chest", GLOW, k=0.0)
    for dx, dz in ((0.044, -0.026), (-0.044, -0.026)):
        p = surface_point(stern, (dx, STERN_Y - 0.005, gc[2] + dz), (0, 1, 0))
        glyph.add(sphere(tuple(p), 0.017), "chest", GLOW, k=0.0)
    glyph.paint(sphere((0, 0, 0), 5.0), GLOW, soft=0.01, emission=1.0)
    shapes.append(glyph)

    gtop = S("HulvarGlyphTop", "glyph", 0.0028, 40, q, color_soft=0.004, weight_sigma=0.02)
    p = surface_point(stern, (0.0, STERN_Y - 0.005, gc[2] + 0.051), (0, 1, 0))
    gtop.add(sphere(tuple(p), 0.019), "chest", GLOW, k=0.0)
    gtop.paint(sphere((0, 0, 0), 5.0), GLOW, soft=0.01, emission=1.0)
    shapes.append(gtop)

    nglow = S("HulvarNestGlow", "glow", 0.0034, 80, q, color_soft=0.004, weight_sigma=0.02)
    nglow.add(cylinder((nx, ny, nz + 0.003), 0.134, 0.010, rounding=0.006), "nest", GLOW, k=0.0)
    for c, d in slits:                                                           # lantern light in the slits
        nglow.add(box(tuple(c - d * 0.012), (0.0085, 0.026, 0.006), look_basis(d), rounding=0.004), "nest", GLOW, k=0.0)
    nglow.paint(sphere((0, 0, 0), 5.0), GLOW, soft=0.01, emission=1.0)
    shapes.append(nglow)

    rune = S("HulvarRune", "glow", 0.0030, 64, q, color_soft=0.003, weight_sigma=0.02)
    for sy in (1, -1):
        y = 0.712 + sy * 0.036
        rune.add(torus((0, y, 0.215), 0.022, 0.0055, look_basis((0, 1, 0))), "anchor", GLOW, k=0.0)
        rune.add(sphere((0, y, 0.215), 0.008), "anchor", GLOW, k=0.0)
    rune.paint(sphere((0, 0, 0), 5.0), GLOW, soft=0.01, emission=1.0)
    shapes.append(rune)

    throat = S("HulvarThroat", "glow", 0.0030, 50, q, color_soft=0.004, weight_sigma=0.02)
    tl = core.offset(-0.038).shell(0.006).clip(slab(2, 0.906, 0.918, 0.0), 0.0)
    tl = bounded(tl.clip(slab(0, -0.19, 0.19, 0.01), 0.0).clip(plane((0, -0.36, 0), (0, 1, 0)), 0.0),
                 (-0.21, -0.60, 0.90), (0.21, -0.33, 0.925))
    throat.add(tl, "head", GLASS, k=0.0)
    throat.paint(sphere((0, 0, 0), 5.0), GLASS, soft=0.01, emission=0.6)
    shapes.append(throat)

    # probe points (rest space) + bone, used by the animation ground solver / validation
    probe = []
    n = 160
    ga = math.pi * (3.0 - math.sqrt(5.0))
    core_k = core.offset(0.015)
    for i in range(n):
        zc = 1.0 - 2.0 * (i + 0.5) / n
        rr = math.sqrt(max(0.0, 1.0 - zc * zc))
        d = np.array([math.cos(ga * i) * rr, math.sin(ga * i) * rr, zc])
        pnt = surface_point(core_k, (0.0, -0.06, 0.82), d)
        x, y, z = pnt
        if z > deck_z(x, y) + 0.01:
            pnt = np.array([x, y, deck_z(x, y)])
            z = pnt[2]
        if y < HEAD_Y and z > HEAD_Z:
            bn = "head"
        elif z > CHEST_Z:
            bn = "chest"
        elif z < HIPS_Z:
            bn = "hips"
        else:
            bn = "spine"
        probe.append((pnt, bn))
    for sx, side in ((1, "L"), (-1, "R")):
        fc = np.array(FIST_C) * np.array([sx, 1, 1])
        for dx in (-0.12, 0.12):
            for dy in (-0.11, 0.11):
                probe.append((fc + np.array([dx, dy, -0.122]), f"hand_{side}"))
        for a in range(8):
            aa = 2 * math.pi * a / 8
            probe.append((np.array([0.21 * sx + 0.14 * math.cos(aa), 0.035 + 0.14 * math.sin(aa), 0.0]), f"foot_{side}"))
    for x in (-0.20, 0.0, 0.20):
        probe.append((np.array([x, bow_face_y(x, 0.78) - 0.02, 0.775]), "jaw"))
    for x in (-0.20, -0.10, 0.0, 0.10, 0.20):
        probe.append((np.array([x, 0.712, 0.215 - 0.04 * (1 - abs(x) / 0.2)]), "anchor"))
    probe.append((np.array([0.0, 0.712, 0.170]), "anchor"))
    for x in (0.0, 0.22, -0.22):
        probe.append((np.array([x, bow_face_y(x, 1.20) - VISOR_OFF, 1.20]), "brow"))
    probe.append((info["stem_tip"], "head"))
    for sx in (1, -1):
        probe.append((np.array([0.15 * sx, bow_face_y(0.15, 1.05), 1.05]), "head"))
        probe.append((np.array([0.15 * sx, bow_face_y(0.15, 0.94), 0.94]), "head"))
    info["probe"] = probe
    hull.cull_by = [stern_plate, face]            # both rigid on bones that also drive those hull regions
    hull.cull_margin = 0.004
    for shp, margin in ((face, 0.010), (stern_plate, 0.012), (brow, 0.028), (jaw, 0.045), (plates, 0.035),
                        (face_brass, 0.010), (side_brass, 0.008), (rail, 0.020)):
        shp.cull_by = [hull]
        shp.cull_margin = margin
    glyph.cull_by = [stern_plate]
    gtop.cull_by = [stern_plate]
    tusks.cull_by = [jaw]
    tusks.cull_margin = 0.006
    info["eyes"] = [(eyes[1][0], "L"), (eyes[-1][0], "R")]
    return shapes, info


# ----------------------------------------------------------------------------- rig
def bone_table():
    t = [
        ("root", (0, 0, 0), (0, -0.20, 0), None, False),
        ("hips", (0, 0.080, 0.520), (0, 0.050, 0.700), "root", True),
        ("spine", (0, 0.050, 0.700), (0, 0.000, 0.920), "hips", True),
        ("chest", (0, 0.000, 0.920), (0, -0.040, 1.150), "spine", True),
        ("head", (0, -0.100, 0.980), (0, -0.400, 1.020), "chest", True),
        ("brow", (0, -0.470, 1.215), (0, -0.620, 1.255), "head", True),
        ("jaw", (0, -0.240, 0.930), (0, -0.440, 0.880), "head", True),
        ("eye_L", tuple(EYE_C), tuple(EYE_C + EYE_FWD / np.linalg.norm(EYE_FWD) * 0.07), "head", True),
        ("eye_R", tuple(EYE_C * [-1, 1, 1]), tuple(EYE_C * [-1, 1, 1] + EYE_FWD * [-1, 1, 1] / np.linalg.norm(EYE_FWD) * 0.07), "head", True),
        ("nest", NEST_C, (NEST_C[0], NEST_C[1], NEST_C[2] + 0.22), "chest", True),
    ]
    for s, x in (("L", 1), ("R", -1)):
        t += [
            (f"upperarm_{s}", (SHOULDER[0] * x, SHOULDER[1], SHOULDER[2]), (ELBOW[0] * x, ELBOW[1], ELBOW[2]), "chest", True),
            (f"forearm_{s}", (ELBOW[0] * x, ELBOW[1], ELBOW[2]), (WRIST[0] * x, WRIST[1], WRIST[2]), f"upperarm_{s}", True),
            (f"hand_{s}", (WRIST[0] * x, WRIST[1], WRIST[2]), (FIST_C[0] * x, FIST_C[1] - 0.012, FIST_C[2] - 0.050), f"forearm_{s}", True),
            (f"thigh_{s}", (0.190 * x, 0.100, 0.560), (0.210 * x, 0.070, 0.300), "hips", True),
            (f"shin_{s}", (0.210 * x, 0.070, 0.300), (0.210 * x, 0.080, 0.120), f"thigh_{s}", True),
            (f"foot_{s}", (0.210 * x, 0.080, 0.120), (0.210 * x, -0.120, 0.040), f"shin_{s}", True),
        ]
    t += [
        ("chain_1", (0, 0.380, 0.680), (0, 0.500, 0.620), "hips", True),
        ("chain_2", (0, 0.500, 0.620), (0, 0.610, 0.530), "chain_1", True),
        ("chain_3", (0, 0.610, 0.530), (0, 0.690, 0.420), "chain_2", True),
        ("anchor", (0, 0.690, 0.420), (0, 0.715, 0.210), "chain_3", True),
    ]
    return t


def make_rig():
    from charkit import BoneDef, Rig
    return Rig([BoneDef(n, tuple(map(float, h)), tuple(map(float, tl)), p, d) for n, h, tl, p, d in bone_table()])


# ----------------------------------------------------------------------------- assembly
AO_STRENGTH = {"stone": 0.15, "metal": 0.15, "glow": 0.0, "glyph": 0.0}
MOVING = ("HulvarArm", "HulvarCuff", "HulvarLegs", "HulvarAnchor", "HulvarChain", "HulvarRune")


def assemble(name, rig, shapes, extras, log):
    """sdfchar.assemble with per-material AO strength, a wider AO reach and per-group occluders:
    limbs and the anchor only occlude themselves (no baked dark patches on the hull where an arm
    happens to hang in the rest pose), the hull group occludes itself."""
    import functools
    import bpy
    import sdfchar
    from bhelpers import select_only
    rig_obj = rig.build(name)
    bones = [b for b in rig.order if rig.bones[b].deform]
    body_group = [sh for sh in shapes if not sh.name.startswith(MOVING)]
    body_field = sdfchar.union_field(body_group)
    orig_ao = K.sdf_ao
    K.sdf_ao = functools.partial(orig_ao, reach=0.20, steps=6, strength=2.2)
    objs = []
    try:
        for sh in shapes:
            t = time.time()
            ao_field = sh.field if sh.name.startswith(MOVING) else body_field
            o = K.build_object(sh, bones, log=log, ao_field=ao_field, ao_strength=AO_STRENGTH.get(sh.material, 0.4))
            sdfchar._assign_material(o, sh.material)
            objs.append(o)
            log(f"    {sh.name}: {time.time() - t:.1f}s")
    finally:
        K.sdf_ao = orig_ao
    objs.extend(extras)
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


# ----------------------------------------------------------------------------- animation
# Pose functions return {bone: (rx, ry, rz[, loc[, scale]])} (degrees, bone-local), sampled at 30 fps
# by charkit.bake_action. A small FK/IK layer (mathutils) keeps feet and fists planted, the nest
# level and the chain hanging in world space.
FPS = 30
CLIPS = {}            # name -> (length_s, fn, loop)
BROW_K = 0.45         # visor tilt scale (the clips' brow angles were tuned for a small brow)


def clip(name, length, loop=False):
    def deco(fn):
        CLIPS[name] = (length, fn, loop)
        return fn
    return deco


def clamp01(x):
    return 0.0 if x < 0.0 else (1.0 if x > 1.0 else x)


def sstep(x):
    x = clamp01(x)
    return x * x * (3.0 - 2.0 * x)


def lerp(a, b, t):
    return a + (b - a) * t


def win(t, t0, t1):
    """0 before t0, 1 after t1, smooth in between."""
    return sstep((t - t0) / max(t1 - t0, 1e-6))


def bump(t, t0, t1, t2):
    """0 -> 1 (t0..t1) -> 0 (t1..t2), smooth."""
    if t <= t1:
        return win(t, t0, t1)
    return 1.0 - win(t, t1, t2)


def spline(t, pts, loop_len=None):
    """Catmull-Rom through (time, value) keys; with loop_len the keys wrap (seamless loop)."""
    n = len(pts)
    if loop_len is not None:
        t = t % loop_len
        ext = [(pts[-2][0] - loop_len, pts[-2][1])] + list(pts) + [(pts[1][0] + loop_len, pts[1][1])]
    else:
        if t <= pts[0][0]:
            return pts[0][1]
        if t >= pts[-1][0]:
            return pts[-1][1]
        ext = [pts[0]] + list(pts) + [pts[-1]]
    for i in range(1, len(ext) - 2):
        t0, v0 = ext[i]
        t1, v1 = ext[i + 1]
        if t0 <= t <= t1:
            tm, vm = ext[i - 1]
            tp, vp = ext[i + 2]
            h = max(t1 - t0, 1e-6)
            u = (t - t0) / h
            m0 = (v1 - vm) / max(t1 - tm, 1e-6) * h
            m1 = (vp - v0) / max(tp - t0, 1e-6) * h
            u2, u3 = u * u, u * u * u
            return (2 * u3 - 3 * u2 + 1) * v0 + (u3 - 2 * u2 + u) * m0 + (-2 * u3 + 3 * u2) * v1 + (u3 - u2) * m1
    return pts[-1][1]


def wv(ph, cycles=1.0, off=0.0):
    return math.sin(2 * math.pi * (ph * cycles + off))


class Pose:
    """Per-bone local rotation (quaternion), location and scale."""

    def __init__(self):
        from mathutils import Quaternion, Vector
        self.Q, self.V = Quaternion, Vector
        self.r, self.l, self.s = {}, {}, {}

    def rot(self, bone, rx=0.0, ry=0.0, rz=0.0):
        from mathutils import Euler
        if bone == "brow":            # the visor is one big rigid piece: keep its tilt small
            rx, ry, rz = rx * BROW_K, ry * BROW_K, rz * BROW_K
        q = Euler((math.radians(rx), math.radians(ry), math.radians(rz)), "XYZ").to_quaternion()
        self.r[bone] = self.r.get(bone, self.Q()) @ q
        return self

    def loc(self, bone, x=0.0, y=0.0, z=0.0):
        self.l[bone] = self.l.get(bone, self.V()) + self.V((x, y, z))
        return self

    def scl(self, bone, x=1.0, y=1.0, z=1.0):
        o = self.s.get(bone, self.V((1, 1, 1)))
        self.s[bone] = self.V((o.x * x, o.y * y, o.z * z))
        return self

    def basis(self, bone):
        from mathutils import Matrix
        m = Matrix.Translation(self.l.get(bone, self.V())) @ self.r.get(bone, self.Q()).to_matrix().to_4x4()
        sc = self.s.get(bone)
        if sc is not None:
            m = m @ Matrix.Diagonal((sc.x, sc.y, sc.z, 1.0))
        return m

    def out(self):
        res = {}
        for b in set(self.r) | set(self.l) | set(self.s):
            e = self.r.get(b, self.Q()).to_euler("XYZ")
            res[b] = (math.degrees(e.x), math.degrees(e.y), math.degrees(e.z),
                      tuple(self.l.get(b, self.V())), tuple(self.s.get(b, self.V((1, 1, 1)))))
        return res


class Skel:
    """Rest data of the armature + FK, two-bone IK, aiming and world orientation."""

    def __init__(self, rig_obj):
        bones = rig_obj.data.bones
        self.parent = {b.name: (b.parent.name if b.parent else None) for b in bones}
        self.rest = {b.name: b.matrix_local.copy() for b in bones}
        self.length = {b.name: b.length for b in bones}
        self.rel = {}
        for b in bones:
            p = self.parent[b.name]
            self.rel[b.name] = (self.rest[p].inverted() @ self.rest[b.name]) if p else self.rest[b.name].copy()
        self.order = []
        seen = set()

        def visit(n):
            if n in seen:
                return
            if self.parent[n]:
                visit(self.parent[n])
            seen.add(n)
            self.order.append(n)
        for b in bones:
            visit(b.name)

    def fk(self, P):
        M = {}
        for n in self.order:
            p = self.parent[n]
            base = (M[p] @ self.rel[n]) if p else self.rel[n]
            M[n] = base @ P.basis(n)
        return M

    def frame0(self, P, bone, M=None):
        if M is None:
            M = self.fk(P)
        p = self.parent[bone]
        return (M[p] @ self.rel[bone]) if p else self.rel[bone].copy()

    def head(self, P, bone, M=None):
        return self.frame0(P, bone, M).translation

    def aim(self, P, bone, direction, M=None, twist=0.0):
        from mathutils import Quaternion, Vector
        F = self.frame0(P, bone, M)
        R = F.to_3x3().normalized()
        y0 = R @ Vector((0, 1, 0))
        qw = y0.rotation_difference(Vector(direction).normalized())
        q = (R.inverted() @ qw.to_matrix() @ R).to_quaternion()
        if twist:
            q = q @ Quaternion((0, 1, 0), math.radians(twist))
        P.r[bone] = q

    def orient(self, P, bone, Rw, M=None):
        F = self.frame0(P, bone, M)
        R = F.to_3x3().normalized()
        P.r[bone] = (R.inverted() @ Rw).to_quaternion()

    def rest_rot(self, bone):
        return self.rest[bone].to_3x3().normalized()

    def ik2(self, P, upper, lower, target, pole):
        from mathutils import Vector
        M = self.fk(P)
        H = self.frame0(P, upper, M).translation
        L1, L2 = self.length[upper], self.length[lower]
        T = Vector(target)
        d = T - H
        dist = min(max(d.length, abs(L1 - L2) + 1e-4), (L1 + L2) * 0.9993)
        u = d.normalized()
        pl = Vector(pole)
        pv = pl - u * pl.dot(u)
        if pv.length < 1e-6:
            pv = Vector((0, -1, 0)) - u * (-u.y)
        pv.normalize()
        ca = (L1 * L1 + dist * dist - L2 * L2) / (2 * L1 * dist)
        a = math.acos(max(-1.0, min(1.0, ca)))
        K = H + (u * math.cos(a) + pv * math.sin(a)) * L1
        self.aim(P, upper, K - H, M)
        M = self.fk(P)
        E = H + u * dist
        self.aim(P, lower, E - K, M)
        return K, E


def rotx(deg):
    from mathutils import Matrix
    return Matrix.Rotation(math.radians(deg), 3, "X")


def roty(deg):
    from mathutils import Matrix
    return Matrix.Rotation(math.radians(deg), 3, "Y")


def rotz(deg):
    from mathutils import Matrix
    return Matrix.Rotation(math.radians(deg), 3, "Z")


SK = None             # Skel, set in bake_all
ANKLE = (0.210, 0.080, 0.120)
FIST_HALF = 0.128
FIST_DROP = WRIST[2] - (FIST_C[2] - FIST_HALF) - 0.004   # wrist height when the fist rests flat on the sand


def body(P, drop=0.0, pitch=0.0, roll=0.0, yaw=0.0, fwd=0.0, side=0.0, spine=(0, 0, 0), chest=(0, 0, 0)):
    """Hips placement in world metres (drop down, fwd towards -Y, side towards +X) and
    torso bends in degrees (pitch>0 leans forward, roll>0 tilts the top towards -X, yaw>0 turns left)."""
    from mathutils import Vector
    w = Vector((side, -fwd, -drop))
    loc = SK.rest_rot("hips").inverted() @ w
    P.loc("hips", loc.x, loc.y, loc.z)
    P.rot("hips", pitch, yaw, roll)
    P.rot("spine", *spine)
    P.rot("chest", *chest)


def lift_body(P, dz):
    """Raise (dz>0) / lower the whole body in world Z (adds to the hips location)."""
    from mathutils import Vector
    loc = SK.rest_rot("hips").inverted() @ Vector((0.0, 0.0, dz))
    P.loc("hips", loc.x, loc.y, loc.z)


PROBE = []            # (rest point Vector, bone)
INFO = {}


def lowest(P, bones=None):
    M = SK.fk(P)
    z = 1e9
    for p, b in PROBE:
        if bones is not None and b not in bones:
            continue
        q = M[b] @ SK.rest[b].inverted() @ p
        z = min(z, q.z)
    return z


HULL_BONES = ("hips", "spine", "chest", "head", "jaw", "brow")


def blend(Pa, Pb, w):
    from mathutils import Quaternion, Vector
    P = Pose()
    for b in set(Pa.r) | set(Pb.r):
        P.r[b] = Pa.r.get(b, Quaternion()).slerp(Pb.r.get(b, Quaternion()), w)
    for b in set(Pa.l) | set(Pb.l):
        P.l[b] = Pa.l.get(b, Vector()).lerp(Pb.l.get(b, Vector()), w)
    for b in set(Pa.s) | set(Pb.s):
        P.s[b] = Pa.s.get(b, Vector((1, 1, 1))).lerp(Pb.s.get(b, Vector((1, 1, 1))), w)
    return P


def leg(P, side, target, pitch=0.0, yaw=0.0, pole_out=0.28):
    from mathutils import Vector
    sx = 1 if side == "L" else -1
    SK.ik2(P, f"thigh_{side}", f"shin_{side}", Vector(target), Vector((pole_out * sx, -1.0, 0.0)))
    SK.orient(P, f"foot_{side}", rotz(yaw) @ rotx(pitch) @ SK.rest_rot(f"foot_{side}"))


def arm_ik(P, side, wrist, hand_pitch=0.0, hand_roll=0.0, hand_yaw=0.0, pole=(0.55, 0.85, 0.0), world_hand=True):
    """IK the arm to a wrist target. world_hand: fist keeps its rest orientation in the world
    (rotated by pitch/roll/yaw) - planted fists; otherwise the fist follows the forearm."""
    from mathutils import Vector
    sx = 1 if side == "L" else -1
    SK.ik2(P, f"upperarm_{side}", f"forearm_{side}", Vector(wrist), Vector((pole[0] * sx, pole[1], pole[2])))
    if world_hand:
        SK.orient(P, f"hand_{side}", rotz(hand_yaw * sx) @ roty(hand_roll * sx) @ rotx(hand_pitch) @ SK.rest_rot(f"hand_{side}"))
    else:
        P.r.pop(f"hand_{side}", None)
        P.rot(f"hand_{side}", hand_pitch, hand_roll * sx, hand_yaw * sx)


def arm_world(P, side, upper_dir, fore_dir, hand=(0.0, 0.0, 0.0)):
    """Aim the arm by world directions (given for the left arm, mirrored in X for the right)."""
    from mathutils import Vector
    sx = 1 if side == "L" else -1
    SK.aim(P, f"upperarm_{side}", Vector((upper_dir[0] * sx, upper_dir[1], upper_dir[2])))
    SK.aim(P, f"forearm_{side}", Vector((fore_dir[0] * sx, fore_dir[1], fore_dir[2])))
    P.r.pop(f"hand_{side}", None)
    P.rot(f"hand_{side}", hand[0], hand[1] * sx, hand[2] * sx)


def mixv(a, b, t):
    return tuple(lerp(a[i], b[i], t) for i in range(3))


def toe_lift(pitch):
    """Ankle raise that keeps the toe tip on the ground when the foot pitches toes-down (heel up)."""
    a = math.radians(max(0.0, pitch))
    return 0.12 * (1.0 - math.cos(a)) + 0.16 * math.sin(a)


def arm_fk(P, side, swing=0.0, out=0.0, twist=0.0, elbow=0.0, wrist=(0, 0, 0)):
    """swing>0 = forward; out>0 = away from the body; elbow>0 = bend (forearm forward/up)."""
    sx = 1 if side == "L" else -1
    P.rot(f"upperarm_{side}", -swing, twist * sx, -out * sx)
    P.rot(f"forearm_{side}", -elbow, 0.0, 0.0)
    P.rot(f"hand_{side}", wrist[0], wrist[1] * sx, wrist[2] * sx)


def level_nest(P, amount=1.0, tilt=(0.0, 0.0), back=0.0, up=0.0):
    """Blend the nest towards world-upright; tilt = extra (pitch, roll) in degrees."""
    from mathutils import Quaternion
    M = SK.fk(P)
    F = SK.frame0(P, "nest", M)
    R = F.to_3x3().normalized()
    up_rot = (R.inverted() @ (rotx(tilt[0]) @ roty(tilt[1]) @ SK.rest_rot("nest"))).to_quaternion()
    q = Quaternion().slerp(up_rot, amount)
    P.r["nest"] = q
    if back or up:
        P.loc("nest", 0.0, up, -back)        # nest local: y = up, z = forward


def chain(P, dirs, M=None):
    """dirs: world directions for chain_1, chain_2, chain_3, anchor (each re-aimed after its parent)."""
    for b, d in zip(("chain_1", "chain_2", "chain_3", "anchor"), dirs):
        SK.aim(P, b, d)


def hang(swing_x=0.0, swing_side=0.0, lag=(1.0, 1.25, 1.5, 1.7), base=(0.62, 0.42, 0.22, 0.04)):
    """World directions of a chain hanging back-and-down; swing_x>0 lifts it backwards (deg),
    swing_side swings it sideways (deg). Each link exaggerates the swing (follow-through)."""
    from mathutils import Vector
    out = []
    for k, b in zip(lag, base):
        d = Vector((0.0, b, -math.sqrt(max(0.0, 1.0 - b * b))))
        d = rotz(swing_side * k) @ rotx(swing_x * k) @ d
        out.append(d)
    return out


def eyes(P, yaw=0.0, pitch=0.0, squash=1.0):
    """Gaze: yaw>0 looks to the character's left, pitch>0 looks up."""
    for side in ("L", "R"):
        P.rot(f"eye_{side}", -pitch, 0.0, -yaw)
        if squash != 1.0:
            P.scl(f"eye_{side}", 1.0, 1.0, squash)


def breathe(P, b, amount=0.015):
    """Hull breath: spine bone scale (children counter-scaled)."""
    sx, sy = 1.0 + amount * b, 1.0 + amount * 0.6 * b
    P.scl("spine", sx, sy, sx)
    P.scl("chest", 1.0 / sx, 1.0 / sy, 1.0 / sx)


def squash(P, k):
    """Hull squash/stretch on the spine (k<1 = squashed): volume-ish preserving, children counter-scaled."""
    w = 1.0 / math.sqrt(max(k, 0.3))
    P.scl("spine", w, k, w)
    P.scl("chest", 1.0 / w, 1.0 / k, 1.0 / w)


def gait(ph, c0, c1, front, back, lift):
    """Foot/fist path for one limb: planted from c0 to c1 (moves front->back at constant speed),
    swings back->front elsewhere with a lift arc. Returns (y, z_lift, planted)."""
    span = (c1 - c0) % 1.0 or 1.0
    u = (ph - c0) % 1.0
    if u <= span:
        return lerp(front, back, u / span), 0.0, True
    w = (u - span) / (1.0 - span)
    # Hermite with ground-speed tangents at both ends: no hitch at lift-off / touch-down
    v = (back - front) / span * (1.0 - span)
    h00, h10, h01, h11 = 2 * w ** 3 - 3 * w ** 2 + 1, w ** 3 - 2 * w ** 2 + w, -2 * w ** 3 + 3 * w ** 2, w ** 3 - w ** 2
    y = h00 * back + h10 * v * 0.35 + h01 * front + h11 * v * 0.35
    return y, lift * math.sin(math.pi * w) ** 0.8, False



# ----------------------------------------------------------------------------- clips
FOOT_X = 0.225


def idle_pose(ph, glance=True):
    P = Pose()
    b = wv(ph, 2)                                            # two slow breaths per loop
    body(P, drop=0.095 - 0.006 * b, pitch=4.0 + 0.6 * b, roll=0.9 * wv(ph, 1, 0.1), yaw=1.5 * wv(ph, 1, 0.3),
         spine=(1.0, 0.0, 0.0), chest=(1.0 - 1.0 * b, 0.0, 0.0))
    breathe(P, b)
    g = bump(ph, 0.30, 0.40, 0.56) if glance else 0.0         # glances up at the nest
    sideways = spline(ph, [(0.0, 0.0), (0.12, 7.0), (0.24, 0.0), (0.62, -6.0), (0.78, -1.0), (1.0, 0.0)], 1.0) if glance else 0.0
    P.rot("head", -2.0 - 8.0 * g + 1.0 * b, 0.6 * sideways, 0.0)
    eyes(P, yaw=1.6 * sideways, pitch=-4.0 + 22.0 * g)
    ch = bump(ph, 0.66, 0.70, 0.84) if glance else 0.0      # rumbling chuckle
    P.rot("jaw", 1.5 + ch * (4.0 + 3.0 * math.sin(ph * 2 * math.pi * 14.0)), 0.0, 0.0)
    P.rot("brow", 1.5 - 7.0 * g + 2.0 * ch, 0.0, 0.0)
    leg(P, "L", (FOOT_X, 0.08, ANKLE[2]))
    leg(P, "R", (-FOOT_X, 0.08, ANKLE[2]))
    tap = bump(ph, 0.84, 0.88, 0.94) if glance else 0.0     # left knuckles drum once
    arm_ik(P, "L", (0.535, -0.175, FIST_DROP + 0.05 * tap), hand_pitch=-6.0 * tap)
    arm_ik(P, "R", (-0.535, -0.175, FIST_DROP))
    level_nest(P, 1.0, tilt=(1.2 * wv(ph, 2, -0.12), 0.0))
    chain(P, hang(swing_x=3.0 + 2.0 * wv(ph, 1, -0.1), swing_side=6.0 * wv(ph, 1, -0.2)))
    return P


@clip("idle", 3.5, loop=True)
def c_idle(t, ph):
    return idle_pose(ph)


@clip("walk", 1.1, loop=True)
def c_walk(t, ph):
    P = Pose()
    S, Y0, c, lift = 0.185, 0.07, 0.56, 0.075
    bob = 0.5 - 0.5 * math.cos(4 * math.pi * (ph - 0.05))   # 0 at contacts, 1 at passing
    body(P, drop=0.050 - 0.026 * bob, pitch=3.5 + 1.5 * bob, roll=-4.0 * wv(ph, 1, -0.03), yaw=-5.0 * math.cos(2 * math.pi * ph),
         side=0.028 * wv(ph, 1, -0.03), spine=(0.5, 2.0 * math.cos(2 * math.pi * ph), 1.2 * wv(ph, 1, -0.10)),
         chest=(1.0, 2.5 * math.cos(2 * math.pi * (ph - 0.05)), 1.0 * wv(ph, 1, -0.16)))
    for side, sx, c0 in (("L", 1, 0.0), ("R", -1, 0.5)):
        y, z, planted = gait(ph, c0, (c0 + c) % 1.0, Y0 - S, Y0 + S, lift)
        pitch = 0.0 if planted else -14.0 * (z / lift)
        leg(P, side, (FOOT_X * sx, y, ANKLE[2] + z), pitch=pitch)
    for side, sx, off in (("L", 1, 0.5), ("R", -1, 0.0)):
        sw = 24.0 * math.cos(2 * math.pi * (ph - off - 0.07))
        arm_fk(P, side, swing=sw, out=9.0, twist=-4.0, elbow=20.0 + 12.0 * max(0.0, sw) / 24.0,
               wrist=(-8.0 - 8.0 * max(0.0, -sw) / 24.0, 0.0, 0.0))
    P.rot("head", -2.0 + 2.0 * bob, 1.5 * math.cos(2 * math.pi * ph), 1.5 * wv(ph, 1, -0.05))
    P.rot("jaw", 2.0 + 2.5 * (1.0 - bob), 0.0, 0.0)
    eyes(P, pitch=-2.0)
    level_nest(P, 0.85, tilt=(2.0 * math.cos(4 * math.pi * (ph - 0.15)), 0.0))
    chain(P, hang(swing_x=6.0 + 4.0 * math.cos(4 * math.pi * (ph - 0.12)), swing_side=9.0 * wv(ph, 1, -0.22)))
    return P


@clip("run", 0.62, loop=True)
def c_run(t, ph):
    """Knuckle-gallop, 4 beats: R fist, L fist, R foot, L foot (2-frame plants)."""
    P = Pose()
    hi = 0.5 + 0.5 * math.cos(4 * math.pi * (ph - 0.36))   # 1 in the two flights, 0 after the plants
    body(P, drop=0.095 - 0.060 * hi, pitch=21.0 + 5.0 * wv(ph, 1, -0.02), roll=3.0 * wv(ph, 1, 0.1),
         yaw=4.0 * wv(ph, 1, 0.05), spine=(3.5, 0.0, 0.0), chest=(3.5 + 2.0 * wv(ph, 1, -0.1), 0.0, 0.0))
    squash(P, 1.0 + 0.035 * (hi - 0.5))
    # fists: plant ahead of the shoulders, sweep back 0.40 m while planted
    for side, sx, c0 in (("R", -1, 0.00), ("L", 1, 0.11)):
        y, z, planted = gait(ph, c0, c0 + 0.13, -0.66, -0.26, 0.20)
        hp = 0.0 if planted else -35.0 * math.sin(math.pi * min(1.0, z / 0.2))
        arm_ik(P, side, (0.47 * sx, y, FIST_DROP + 0.004 + z), hand_pitch=hp, pole=(0.45, 0.9, 0.2))
    for side, sx, c0 in (("R", -1, 0.50), ("L", 1, 0.61)):
        y, z, planted = gait(ph, c0, c0 + 0.13, -0.10, 0.28, 0.17)
        leg(P, side, (0.215 * sx, y, ANKLE[2] + z), pitch=(0.0 if planted else -25.0 * z / 0.17))
    P.rot("head", -17.0 + 3.0 * wv(ph, 2, 0.1), 0.0, 0.0)
    P.rot("jaw", 6.0 + 4.0 * hi, 0.0, 0.0)
    P.rot("brow", 4.0, 0.0, 0.0)
    eyes(P, pitch=4.0)
    nod = sum(bump((ph - c0) % 1.0, 0.0, 0.035, 0.12) for c0 in (0.0, 0.11))   # nods on each fist plant
    level_nest(P, 1.0, tilt=(3.0 * wv(ph, 2, -0.18) + 4.0 * nod, 0.0), up=-0.012 * nod)   # counter-rotated
    chain(P, hang(swing_x=38.0 + 10.0 * wv(ph, 2, -0.2), swing_side=6.0 * wv(ph, 1, -0.25), lag=(1.0, 1.15, 1.3, 1.4)))
    return P


def air_pose(t, k=1.0):
    """Shared airborne pose (jump end / fall start)."""
    P = Pose()
    body(P, drop=-0.02, pitch=-4.0 + 2.0 * math.sin(t * 7.0), roll=2.0 * math.sin(t * 5.0), spine=(-2.0, 0, 0), chest=(-3.0, 0, 0))
    leg(P, "L", (FOOT_X + 0.02, 0.02, 0.30 + 0.03 * math.sin(t * 9.0)), pitch=12.0)
    leg(P, "R", (-FOOT_X - 0.02, 0.06, 0.27 - 0.03 * math.sin(t * 9.0)), pitch=8.0)
    for side, sx in (("L", 1), ("R", -1)):
        f = 0.08 * math.sin(t * 8.0 + sx)
        arm_world(P, side, (0.80, -0.22, 0.52 + f), (0.50, -0.34, 0.78 + f), hand=(-15.0, 0.0, 0.0))
    P.rot("head", -6.0, 0.0, 0.0)
    P.rot("jaw", 7.0, 0.0, 0.0)
    P.rot("brow", -5.0, 0.0, 0.0)
    eyes(P, pitch=-12.0)
    level_nest(P, 0.8, tilt=(-4.0 + 3.0 * math.sin(t * 6.0), 0.0))
    return P


@clip("jump", 0.45)
def c_jump(t, ph):
    sq = bump(t, 0.0, 0.055, 0.13)              # 2-frame squat, push-off
    air = win(t, 0.07, 0.24)
    P0 = Pose()
    body(P0, drop=0.095 + 0.07 * sq, pitch=4.0 + 8.0 * sq, spine=(1, 0, 0), chest=(1, 0, 0))
    squash(P0, 1.0 - 0.07 * sq + 0.08 * bump(t, 0.06, 0.12, 0.22))
    leg(P0, "L", (FOOT_X, 0.08, ANKLE[2]))
    leg(P0, "R", (-FOOT_X, 0.08, ANKLE[2]))
    for side, sx in (("L", 1), ("R", -1)):
        arm_ik(P0, side, (0.535 * sx, -0.175 + 0.04 * sq, FIST_DROP))
    P0.rot("head", -2.0, 0, 0)
    P0.rot("jaw", 2.0 + 6.0 * sq, 0, 0)
    eyes(P0, pitch=6.0 * sq)
    level_nest(P0, 1.0, back=0.0, up=-0.025 * sq)
    P1 = air_pose(t)
    P = blend(P0, P1, air)
    # stretch on the push-off
    st = bump(t, 0.06, 0.12, 0.25)
    squash(P, 1.0 + 0.06 * st)
    chain(P, hang(swing_x=lerp(4.0, -18.0, air) + 10.0 * bump(t, 0.05, 0.15, 0.4), swing_side=0.0))
    return P


@clip("fall", 0.8, loop=True)
def c_fall(t, ph):
    P = Pose()
    body(P, drop=-0.02, pitch=-5.0 + 2.0 * wv(ph, 1), roll=2.5 * wv(ph, 1, 0.25), spine=(-2.0, 0, 0), chest=(-3.0 + 1.0 * wv(ph, 1, 0.1), 0, 0))
    leg(P, "L", (FOOT_X + 0.02, 0.03 + 0.03 * wv(ph, 1), 0.24 + 0.03 * wv(ph, 1, 0.2)), pitch=14.0)
    leg(P, "R", (-FOOT_X - 0.02, 0.03 - 0.03 * wv(ph, 1), 0.24 - 0.03 * wv(ph, 1, 0.2)), pitch=10.0)
    for side, sx, off in (("L", 1, 0.0), ("R", -1, 0.12)):
        flap = wv(ph, 2, off)
        arm_world(P, side, (0.80, -0.20, 0.52 + 0.12 * flap), (0.50, -0.30, 0.80 + 0.14 * wv(ph, 2, off - 0.08)),
                  hand=(-15.0 + 10.0 * flap, 0.0, 0.0))
    P.rot("head", -8.0 + 2.0 * wv(ph, 1, 0.3), 0.0, 1.5 * wv(ph, 1))
    P.rot("jaw", 9.0 + 3.0 * wv(ph, 2), 0.0, 0.0)
    P.rot("brow", -6.0, 0.0, 0.0)
    eyes(P, pitch=-16.0)
    level_nest(P, 0.75, tilt=(-5.0 + 3.0 * wv(ph, 2, -0.15), 2.0 * wv(ph, 1)))
    chain(P, hang(swing_x=62.0 + 10.0 * wv(ph, 1, -0.2), swing_side=8.0 * wv(ph, 1, -0.35), lag=(1.0, 1.2, 1.35, 1.45)))
    return P


@clip("land", 0.45)
def c_land(t, ph):
    hit = bump(t, 0.0, 0.035, 0.20)
    reb = bump(t, 0.10, 0.17, 0.32)
    P = Pose()
    body(P, drop=0.095 + 0.10 * hit - 0.035 * reb, pitch=4.0 + 11.0 * hit - 3.0 * reb, spine=(1.0 + 3.0 * hit, 0, 0),
         chest=(1.0 + 4.0 * hit, 0, 0))
    squash(P, 1.0 - 0.09 * hit + 0.04 * reb)
    leg(P, "L", (FOOT_X + 0.02 * hit, 0.08, ANKLE[2]))
    leg(P, "R", (-FOOT_X - 0.02 * hit, 0.08, ANKLE[2]))
    for side, sx in (("L", 1), ("R", -1)):
        arm_ik(P, side, (0.56 * sx, -0.19 - 0.06 * hit, FIST_DROP + 0.024 * reb))
    P.rot("head", -2.0 + 8.0 * hit - 4.0 * reb, 0, 0)
    P.rot("jaw", 1.5 + 13.0 * bump(t, 0.02, 0.07, 0.22), 0, 0)
    P.rot("brow", 1.5 + 5.0 * hit, 0, 0)
    eyes(P, pitch=-4.0, squash=1.0 - 0.45 * bump(t, 0.0, 0.04, 0.14))
    level_nest(P, 1.0, tilt=(6.0 * bump(t, 0.03, 0.09, 0.2) - 4.0 * bump(t, 0.12, 0.2, 0.34), 0.0), up=-0.05 * bump(t, 0.02, 0.08, 0.22))
    chain(P, hang(swing_x=3.0 - 25.0 * bump(t, 0.04, 0.12, 0.24) + 10.0 * bump(t, 0.2, 0.28, 0.42), swing_side=0.0))
    # settle exactly into idle
    return blend(P, idle_pose(0.0), win(t, 0.30, 0.45))


@clip("slam", 0.60)
def c_slam(t, ph):
    """Belly-flop (Barrigada): hang + wind-up, dive, belly hits with fists forward; the anchor slams last."""
    P = Pose()
    wind = bump(t, 0.0, 0.07, 0.16)
    dive = win(t, 0.10, 0.27)
    hit = win(t, 0.27, 0.31)
    pitch = lerp(-14.0 * wind, 62.0, dive)
    body(P, drop=0.0, pitch=pitch, spine=(-6.0 * wind + 4.0 * dive, 0, 0), chest=(-6.0 * wind + 3.0 * dive, 0, 0))
    squash(P, 1.0 + 0.05 * dive * (1.0 - hit) - 0.12 * hit + 0.05 * bump(t, 0.31, 0.38, 0.50))
    P.rot("head", -10.0 * wind - 30.0 * dive + 5.0 * hit, 0, 0)
    P.rot("jaw", 6.0 + 10.0 * wind + 12.0 * hit, 0, 0)
    P.rot("brow", 6.0 - 4.0 * hit, 0, 0)
    eyes(P, pitch=lerp(10.0, 18.0, dive), squash=1.0 - 0.6 * bump(t, 0.28, 0.31, 0.42))
    z0 = lowest(P, HULL_BONES)
    target = lerp(0.42, 0.0, win(t, 0.12, 0.29))
    lift_body(P, target - z0 - 0.010 * hit)
    M = SK.fk(P)
    for side, sx in (("L", 1), ("R", -1)):
        hip = SK.head(P, f"thigh_{side}", M)
        tuck = (FOOT_X * sx, hip.y - 0.10, hip.z - 0.26)
        back = (0.25 * sx, hip.y + 0.40, max(0.13, hip.z - 0.06))
        tgt = [lerp(tuck[i], back[i], dive) for i in range(3)]
        leg(P, side, tgt, pitch=lerp(15.0, 75.0, dive))
    for side, sx in (("L", 1), ("R", -1)):
        up_u, up_f = (0.32, 0.22, 0.92), (0.16, 0.12, 0.98)
        fw_u, fw_f = (0.16, -0.97, 0.10), (0.10, -0.99, -0.02)
        if t < 0.27:
            k = win(t, 0.10, 0.25)
            arm_world(P, side, mixv(up_u, fw_u, k), mixv(up_f, fw_f, k), hand=(-10.0, 0.0, 0.0))
        else:
            M = SK.fk(P)
            sh = SK.head(P, f"upperarm_{side}", M)
            k = win(t, 0.27, 0.31)
            tgt = (sh.x + 0.08 * sx, sh.y - 0.52, lerp(sh.z + 0.02, 0.268, k))
            arm_ik(P, side, tgt, hand_pitch=-10.0, pole=(0.7, 0.3, 0.8), world_hand=False)
    level_nest(P, 0.5, tilt=(-12.0 * bump(t, 0.30, 0.36, 0.5), 0.0))
    lift = 80.0 * dive - 80.0 * win(t, 0.33, 0.45) + 6.0 * bump(t, 0.45, 0.50, 0.58)
    chain(P, hang(swing_x=-10.0 * wind + lift, swing_side=0.0, base=(0.90, 0.85, 0.80, 0.70), lag=(1.0, 1.1, 1.2, 1.25)))
    return P


@clip("ram", 0.50)
def c_ram(t, ph):
    """Aríete de Proa: 2-frame anticipation, prow-down lunge, arms swept back, recover."""
    ant = bump(t, 0.0, 0.05, 0.09)
    go = win(t, 0.05, 0.12) * (1.0 - win(t, 0.32, 0.48))
    shake = math.sin(t * 2 * math.pi * 18.0) * go * (1.0 - win(t, 0.25, 0.32))
    P = Pose()
    imp = bump(t, 0.10, 0.135, 0.20)                           # impact accent: 2-frame squash along the bow
    body(P, drop=0.09 + 0.04 * go, pitch=4.0 - 8.0 * ant + 24.0 * go + 1.2 * shake, fwd=0.05 * go + 0.03 * imp,
         spine=(1.0 + 4.0 * go, 0, 0), chest=(1.0 + 4.0 * go, 0, 0))
    squash(P, 1.0 + 0.05 * go)
    P.scl("spine", 1.0 + 0.05 * imp, 1.0 + 0.04 * imp, 1.0 - 0.11 * imp)
    P.scl("chest", 1.0 / (1.0 + 0.05 * imp), 1.0 / (1.0 + 0.04 * imp), 1.0 / (1.0 - 0.11 * imp))
    leg(P, "L", (FOOT_X, lerp(0.08, -0.16, go), ANKLE[2]))
    leg(P, "R", (-FOOT_X, lerp(0.08, 0.34, go), ANKLE[2] + toe_lift(28.0 * go)), pitch=28.0 * go)
    for side, sx in (("L", 1), ("R", -1)):
        sw = lerp(-8.0 * ant, -62.0, go)
        arm_fk(P, side, swing=sw, out=lerp(8.0, 22.0, go), twist=-10.0 * go, elbow=lerp(12.0, 4.0, go), wrist=(18.0 * go, 0.0, 0.0))
    idle = idle_pose(0.0)
    P.rot("head", -2.0 + 16.0 * go - 6.0 * ant, 0, 0)
    P.rot("jaw", 1.5 - 1.5 * go, 0, 0)
    P.rot("brow", 1.5 + 9.0 * go, 0, 0)
    eyes(P, pitch=8.0 * go, squash=1.0 - 0.18 * go)
    level_nest(P, 0.7, tilt=(-14.0 * go, 0.0))
    chain(P, hang(swing_x=3.0 + 45.0 * win(t, 0.08, 0.2) * (1.0 - win(t, 0.30, 0.5)) - 12.0 * bump(t, 0.38, 0.44, 0.5), swing_side=0.0))
    # arms ease back to the idle IK pose at the end
    return blend(P, idle, win(t, 0.40, 0.50))


def brace_pose(t):
    """Canhão do Ninho: wide low stance leaning back, fists planted far forward and wide, jaw
    clenched, anchor dug into the sand behind; the shot (recoil + nest kick) at t = 0.25 s."""
    P = Pose()
    fire = 0.25
    rec = bump(t, fire, fire + 0.025, fire + 0.22)
    kick = bump(t, fire, fire + 0.03, fire + 0.12)
    wob = math.sin((t - fire) * 2 * math.pi * 5.0) * math.exp(-max(0.0, t - fire) * 7.0) * (1.0 if t > fire else 0.0)
    charge = win(t, 0.06, 0.22) * (1.0 - win(t, fire, fire + 0.02))
    jit = math.sin(t * 2 * math.pi * 24.0) * charge
    body(P, drop=0.185 + 0.008 * jit + 0.035 * rec, pitch=-5.0 + 1.5 * charge - 7.0 * rec + 2.5 * wob, side=0.004 * jit,
         spine=(-1.5 - 2.0 * rec, 0, 0), chest=(-1.5 - 4.0 * rec, 0, 0))
    squash(P, 1.0 - 0.03 * charge - 0.08 * kick + 0.04 * wob)
    leg(P, "L", (0.420, 0.03, ANKLE[2]), yaw=-16.0, pole_out=0.45)
    leg(P, "R", (-0.420, 0.11, ANKLE[2]), yaw=16.0, pole_out=0.45)
    arm_ik(P, "L", (0.665, -0.330, FIST_DROP), hand_yaw=16.0, pole=(0.7, 0.75, 0.1))
    arm_ik(P, "R", (-0.665, -0.330, FIST_DROP), hand_yaw=16.0, pole=(0.7, 0.75, 0.1))
    P.rot("head", 3.0 + 1.5 * charge - 10.0 * rec + 3.0 * wob, 0, 0)
    P.rot("jaw", -1.5 + 1.5 * jit + 22.0 * rec, 0, 0)            # clenched until the shot, then a roar
    P.rot("brow", 9.0 + 3.0 * charge - 14.0 * rec, 0, 0)
    eyes(P, pitch=8.0, squash=1.0 - 0.28 * charge - 0.5 * kick)
    level_nest(P, 1.0, tilt=(13.0 + 2.0 * charge - 32.0 * rec + 8.0 * wob, 0.0), back=0.09 * rec, up=-0.03 * rec)
    P.scl("nest", 1.0 + 0.10 * kick, 1.0 - 0.12 * kick + 0.05 * wob, 1.0 + 0.10 * kick)
    # anchor: the chain runs back taut and the flukes bite the sand behind
    chain(P, hang(swing_x=34.0 + 4.0 * rec, swing_side=0.0, base=(0.80, 0.70, 0.55, -0.35), lag=(1.0, 1.0, 1.0, 1.0)))
    return P


@clip("brace", 0.70, loop=True)
def c_brace(t, ph):
    return brace_pose(t)


@clip("surf", 1.0, loop=True)
def c_surf(t, ph):
    """Trenó de Quilha: the hull planes on its keel like a boat - prow lifted 14 deg, the aft keel is
    the contact line, legs folded inside, fists trailing behind at the sides as rudders, nest level."""
    P = Pose()
    bob = 0.006 * wv(ph, 4) + 0.004 * wv(ph, 7, 0.3)
    body(P, drop=0.0, pitch=-11.0 + 1.5 * wv(ph, 2, 0.1), roll=3.0 * wv(ph, 1), spine=(-1.5, 0, 0),
         chest=(-1.5, 0, -1.0 * wv(ph, 1, -0.1)))
    z0 = lowest(P, HULL_BONES)
    lift_body(P, -z0 - 0.012 + bob)
    M = SK.fk(P)
    for side, sx in (("L", 1), ("R", -1)):
        hip = SK.head(P, f"thigh_{side}", M)
        leg(P, side, (0.20 * sx, hip.y - 0.06, hip.z + 0.05), pitch=70.0)
    for side, sx, off in (("L", 1, 0.0), ("R", -1, 0.5)):
        dip = 0.5 + 0.5 * wv(ph, 1, off)
        arm_ik(P, side, (0.66 * sx, 0.26 + 0.05 * dip, FIST_DROP - 0.004 + 0.03 * dip), hand_pitch=18.0, hand_yaw=-20.0,
               pole=(0.6, 0.3, 1.0))
    P.rot("head", 2.0 + 1.0 * wv(ph, 2), 0, 1.5 * wv(ph, 1))
    P.rot("jaw", 3.0, 0, 0)
    P.rot("brow", 2.0, 0, 0)
    eyes(P, pitch=4.0, yaw=4.0 * wv(ph, 1, 0.2))
    level_nest(P, 1.0, tilt=(1.5 * wv(ph, 2, -0.2), 2.0 * wv(ph, 1, -0.15)))
    chain(P, hang(swing_x=70.0, swing_side=7.0 * wv(ph, 1, -0.3), base=(0.85, 0.8, 0.75, 0.7), lag=(1.0, 1.05, 1.1, 1.12)))
    return P


@clip("celebrate", 2.0)
def c_celebrate(t, ph):
    P = Pose()
    drum = 1.0 - win(t, 0.84, 1.00)
    up = win(t, 0.90, 1.10) * (1.0 - win(t, 1.55, 1.85))
    hop = bump(t, 1.02, 1.12, 1.26)
    beats = [0.14, 0.30, 0.46, 0.62, 0.76]
    bounce = sum(bump(t, b - 0.05, b, b + 0.09) for b in beats) * drum
    body(P, drop=0.05 + 0.015 * bounce - 0.03 * hop - 0.02 * up, pitch=lerp(5.0, -7.0, up) + 2.0 * bounce,
         spine=(1.0, 0, 0), chest=(lerp(1.0, -5.0, up) - 2.0 * bounce, 0, 0))
    squash(P, 1.0 - 0.03 * bounce + 0.05 * hop)
    leg(P, "L", (FOOT_X, 0.08, ANKLE[2]))
    leg(P, "R", (-FOOT_X, 0.08, ANKLE[2]))
    for side, sx, beat_ids in (("L", 1, (0, 2, 4)), ("R", -1, (1, 3, 4))):
        hitk = sum(bump(t, beats[i] - 0.08, beats[i], beats[i] + 0.06) for i in beat_ids)
        Pd = Pose()
        Pd.r, Pd.l, Pd.s = dict(P.r), dict(P.l), dict(P.s)
        # belly drum: fists swing in from the sides and thump the hull below the jaw
        arm_ik(Pd, side, (lerp(0.52, 0.36, hitk) * sx, lerp(-0.52, -0.60, hitk), lerp(0.70, 0.64, hitk)),
               hand_pitch=-15.0, hand_yaw=-25.0 * hitk, pole=(1.0, 0.6, -0.2), world_hand=False)
        Pu = Pose()
        Pu.r, Pu.l, Pu.s = dict(P.r), dict(P.l), dict(P.s)
        wig = 0.06 * math.sin(t * 14.0 + sx)
        arm_world(Pu, side, (0.46, -0.06, 0.88 + wig), (0.24, -0.10, 0.96), hand=(-20.0, 0.0, 0.0))
        from mathutils import Quaternion
        for bn in (f"upperarm_{side}", f"forearm_{side}", f"hand_{side}"):
            P.r[bn] = Pd.r.get(bn, Quaternion()).slerp(Pu.r.get(bn, Quaternion()), up)
    P.rot("head", lerp(-10.0, -18.0, up) + 3.0 * bounce, 0, 0)
    P.rot("jaw", 10.0 + 8.0 * up + 5.0 * math.sin(t * 25.0) * drum, 0, 0)
    P.rot("brow", -8.0, 0, 0)
    eyes(P, pitch=8.0 + 10.0 * up, squash=0.75)
    level_nest(P, 1.0, tilt=(3.0 * math.sin(t * 13.0) * drum - 6.0 * hop, 0.0), up=0.02 * hop)
    wag = math.sin(t * 2 * math.pi * 3.2) * (1.0 - win(t, 1.6, 1.95))
    chain(P, hang(swing_x=28.0 * (1.0 - win(t, 1.6, 1.95)) + 3.0, swing_side=24.0 * wag, lag=(1.0, 1.35, 1.7, 2.0)))
    return blend(P, idle_pose(0.0), win(t, 1.70, 2.0))


@clip("hurt", 0.5)
def c_hurt(t, ph):
    hit = bump(t, 0.0, 0.05, 0.30)
    over = bump(t, 0.18, 0.30, 0.48)
    P = Pose()
    body(P, drop=0.095 + 0.02 * hit, pitch=4.0 - 18.0 * hit + 5.0 * over, roll=-4.0 * hit, spine=(1.0 - 5.0 * hit, 0, 0),
         chest=(1.0 - 6.0 * hit, 0, 2.0 * hit))
    squash(P, 1.0 + 0.04 * hit - 0.03 * over)
    leg(P, "L", (FOOT_X, 0.08, ANKLE[2]))
    leg(P, "R", (-FOOT_X, 0.08 + 0.04 * hit, ANKLE[2]))
    idle = idle_pose(0.0)
    for side, sx in (("L", 1), ("R", -1)):
        Pa = Pose()
        Pa.r, Pa.l, Pa.s = dict(P.r), dict(P.l), dict(P.s)
        arm_world(Pa, side, (0.72, -0.42, 0.55), (0.40, -0.55, 0.73), hand=(-30.0, 0.0, 0.0))
        Pi = Pose()
        Pi.r, Pi.l, Pi.s = dict(P.r), dict(P.l), dict(P.s)
        arm_ik(Pi, side, (0.535 * sx, -0.175, FIST_DROP))
        from mathutils import Quaternion
        for bn in (f"upperarm_{side}", f"forearm_{side}", f"hand_{side}"):
            P.r[bn] = Pi.r.get(bn, Quaternion()).slerp(Pa.r.get(bn, Quaternion()), hit)
    P.rot("head", -2.0 - 14.0 * hit + 6.0 * over, 0, 4.0 * hit)
    P.rot("jaw", 1.5 + 16.0 * bump(t, 0.0, 0.06, 0.3), 0, 0)
    P.rot("brow", -9.0 * hit + 3.0 * over, 0, 0)
    eyes(P, pitch=4.0 * hit, squash=1.0 - 0.85 * bump(t, 0.0, 0.03, 0.22))
    level_nest(P, 0.6, tilt=(10.0 * bump(t, 0.03, 0.10, 0.3) - 6.0 * over, 0.0))
    chain(P, hang(swing_x=3.0 + 26.0 * bump(t, 0.03, 0.12, 0.34) - 4.0 * over, swing_side=6.0 * hit))
    w = win(t, 0.22, 0.48)
    return blend(P, idle, w)


def bake_all(rig_obj):
    from charkit import bake_action
    global SK
    SK = Skel(rig_obj)
    from mathutils import Vector
    PROBE[:] = [(Vector(tuple(map(float, p))), b) for p, b in INFO.get("probe", [])]
    for name, (length, fn, loop) in CLIPS.items():
        act = bake_action(rig_obj, name, length, lambda t, ph, fn=fn: fn(t, ph).out(), loop)
        # charkit keys frames 1..n+1 and the glTF exporter samples from frame 0, which duplicates the
        # first pose (a one-frame stall at every loop wrap). Shift the keys to 0..n: the clip is then
        # exactly `length` long and, for loops, its last key equals its first.
        n = int(round(length * FPS))
        for fc in act.fcurves:
            for kp in fc.keyframe_points:
                kp.co.x -= 1.0
                kp.handle_left.x -= 1.0
                kp.handle_right.x -= 1.0
        act.frame_range = (0, n)


def check_clips(rig_obj, body, log, every=2):
    """Evaluate the deformed mesh per frame: lowest point overall / per limb (feet, fists, anchor)."""
    import bpy
    me = body.data
    groups = {vg.index: vg.name for vg in body.vertex_groups}
    n = len(me.vertices)
    dom = np.empty(n, dtype=object)
    for v in me.vertices:
        best, bw = None, 0.0
        for g in v.groups:
            if g.weight > bw:
                best, bw = groups.get(g.group), g.weight
        dom[v.index] = best
    limbs = {k: np.array([d == k for d in dom]) for k in ("foot_L", "foot_R", "hand_L", "hand_R", "anchor", "nest")}
    hullm = np.array([d in ("hips", "spine", "chest", "head", "jaw", "brow") for d in dom])
    deps = bpy.context.evaluated_depsgraph_get()
    for act in bpy.data.actions:
        rig_obj.animation_data.action = act
        f0, f1 = int(act.frame_range[0]), int(act.frame_range[1])
        rows = []
        for f in range(f0, f1 + 1, every):
            bpy.context.scene.frame_set(f)
            ev = body.evaluated_get(deps)
            m = ev.to_mesh()
            co = np.empty(len(m.vertices) * 3, np.float32)
            m.vertices.foreach_get("co", co)
            ev.to_mesh_clear()
            co = co.reshape(-1, 3)
            r = [f - f0, co[:, 2].min(), co[hullm, 2].min()]
            for k in ("foot_L", "foot_R", "hand_L", "hand_R", "anchor"):
                c = co[limbs[k]]
                i = int(np.argmin(c[:, 2]))
                r += [c[i, 2], c[i, 1]]
            rows.append(r)
        A = np.array(rows)
        log(f"CHECK {act.name:10s} frames {f1 - f0:3d}  min z {A[:, 1].min():+.3f}  hull {A[:, 2].min():+.3f}  "
            f"footL {A[:, 3].min():+.3f}..{A[:, 3].max():+.3f}  footR {A[:, 5].min():+.3f}..{A[:, 5].max():+.3f}  "
            f"fistL {A[:, 7].min():+.3f}..{A[:, 7].max():+.3f}  fistR {A[:, 9].min():+.3f}..{A[:, 9].max():+.3f}  "
            f"anchor {A[:, 11].min():+.3f}..{A[:, 11].max():+.3f}")
        if act.name in ("walk", "run"):
            for r in rows[::1]:
                log("   f%2d  footL z%+.3f y%+.3f  footR z%+.3f y%+.3f  fistL z%+.3f y%+.3f  fistR z%+.3f y%+.3f" % (
                    r[0], r[3], r[4], r[5], r[6], r[7], r[8], r[9], r[10]))


# ----------------------------------------------------------------------------- main
def main(argv):
    import bpy
    from bhelpers import log, material, reset_scene
    import sdfchar

    fast = "--fast" in argv
    noanim = "--noanim" in argv
    out = OUT_GLB
    if "--out" in argv:
        out = Path(argv[argv.index("--out") + 1])
    q = 1.6 if fast else 1.0
    t0 = time.time()
    reset_scene()
    for name, col in (("stone", (0.24, 0.47, 0.63, 1)), ("metal", (0.83, 0.64, 0.25, 1)),
                      ("glow", (0.56, 1.0, 0.95, 1)), ("glyph", (0.56, 1.0, 0.95, 1)), ("eye", (1, 1, 1, 1))):
        material(name, col)
    rig = make_rig()
    shapes, info = build_shapes(q)
    INFO.update(info)
    bones = [b for b in rig.order if rig.bones[b].deform]
    extras = []
    for c, side in info["eyes"]:
        sx = 1 if side == "L" else -1
        f = EYE_FWD * np.array([sx, 1, 1])
        extras.append(sdfchar.eye_object(f"Eye_{side}", tuple(c), EYE_R, tuple(f), f"eye_{side}", bones,
                                         squash=(1.0, 1.0, 0.82), segments=14, rings=9))

    def crystal(bm):
        import bmesh
        from mathutils import Matrix
        bmesh.ops.create_icosphere(bm, subdivisions=1, radius=1.0)
        bmesh.ops.transform(bm, matrix=Matrix.Diagonal((0.048, 0.048, 0.062, 1.0)), verts=bm.verts)
        bmesh.ops.translate(bm, vec=(NEST_C[0], NEST_C[1] - 0.05, 1.215), verts=bm.verts)
    extras.append(sdfchar.hard_object("HulvarCrystal", crystal, "nest", bones, (0.62, 1.0, 0.96, 0.0), "glow"))
    rig_obj, body = assemble("Hulvar", rig, shapes, extras, log)
    log(f"mesh built in {time.time() - t0:.1f}s")
    if not noanim:
        bake_all(rig_obj)
    else:
        from charkit import bake_action
        bake_action(rig_obj, "idle", 1.0, lambda t, ph: {})
    if "--check" in argv:
        check_clips(rig_obj, body, log)
    OUT_BLEND.parent.mkdir(parents=True, exist_ok=True)
    if out == OUT_GLB:
        bpy.context.preferences.filepaths.save_version = 0      # no hulvar.blend1 backups
        bpy.ops.wm.save_as_mainfile(filepath=str(OUT_BLEND), compress=True)
    sdfchar.export(out, rig_obj, body)
    log(f"total {time.time() - t0:.1f}s")


if __name__ == "__main__":
    _argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    try:
        import bpy  # noqa: F401
        main(_argv)
    except ImportError:
        print("run inside Blender: blender -b --factory-startup --python game/blender/build_hulvar.py")
