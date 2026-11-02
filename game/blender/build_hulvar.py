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
HULL_LO = hexcol("2C5E86")      # esmalte azul-petróleo (baixo)
HULL_HI = hexcol("3C78A0")      # esmalte azul-petróleo (alto)
KEEL = hexcol("2B3A87")         # Night Indigo — quilha
INDIGO = hexcol("343C96")       # Indigo Glaze — placas, mandíbula, punhos, viseira
INDIGO_SH = hexcol("2A3180")
IVORY = hexcol("F5ECD7")        # Shell Ivory — máscara, convés, solas
IVORY_SH = hexcol("E6D9BC")
BRASS = hexcol("D4A33F")
BRASS_HI = hexcol("F2CF72")
BRASS_SH = hexcol("A9792A")
GLASS = hexcol("4FE3D6")        # Glass Cyan
GLOW = hexcol("8FFFF2")         # brilho
MOON = hexcol("CFD6E6")         # Moonstone — âncora
MOON_SH = hexcol("9AA6C4")
MOUTH = hexcol("141A3F")
SOCKET = hexcol("1C2458")

# ----------------------------------------------------------------------------- hull geometry
EYE_C = np.array([0.150, -0.352, 1.032])          # left eye centre (+X)
EYE_R = 0.088
EYE_FWD = np.array([0.30, -1.0, 0.02])            # rims roughly follow the V bow face
RIM_MAJOR = 0.098
DECK = dict(c=(0.0, 0.06, 2.69), r=(2.6, 1.915, 1.50))   # big ellipsoid carved from the top -> deck with sheer
BOW_P = (0.0, -0.505, 1.00)                       # stem point for the bow V planes
_bn = np.array([0.60, -0.78, -0.17])              # -z component: the stem rakes forward at the top
BOW_NL = tuple(_bn / np.linalg.norm(_bn))
BOW_NR = (-BOW_NL[0], BOW_NL[1], BOW_NL[2])
STERN_Y = 0.455
STERN_N = (0.0, 1.0, -0.16)
NEST_C = (0.0, 0.150, 1.190)                      # nest floor centre (Saeli's feet)
SHOULDER = (0.360, -0.020, 1.040)
ELBOW = (0.485, -0.052, 0.735)
WRIST = (0.530, -0.118, 0.425)
FIST_C = (0.532, -0.156, 0.265)                   # fist box centre (bottom at z ~0.14)
PORT_YS = (0.110, 0.225, 0.340)                   # row of side portholes
PORT_Z = 0.885
PORT_R = 0.030


def deck_prim():
    return ellipsoid(DECK["c"], DECK["r"])


def deck_z(x, y):
    """Deck surface height (bottom of the carving ellipsoid) at (x, y)."""
    c, r = DECK["c"], DECK["r"]
    u = 1.0 - (x / r[0]) ** 2 - ((y - c[1]) / r[1]) ** 2
    return c[2] - r[2] * math.sqrt(max(u, 1e-9))


def superellipsoid(c, r, n=2.6):
    """Rounded-box-like blob: (|x/a|^n + |y/b|^n + |z/c|^n)^(1/n) = 1 (approximate distance)."""
    c = np.asarray(c, float)
    r = np.asarray(r, float)
    rmin = float(r.min())

    def f(P):
        q = np.abs((P - c) / r)
        k = np.power(np.power(q, n).sum(axis=1), 1.0 / n)
        return (k - 1.0) * rmin
    return K.Prim(f, c - r, c + r)


HULL_STYLE = "super"


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
    """The hull as a boat: long chubby blob, U section tapering to the keel, raked V bow,
    raked forefoot and a flat transom."""
    if HULL_STYLE == "box":
        b = box((0, -0.025, 0.835), (0.428, 0.500, 0.435), rounding=0.28)
    else:
        b = superellipsoid((0, -0.025, 0.840), (0.440, 0.525, 0.445), 2.7)
    b = b.clip(cylinder((0, 0, 1.08), 0.690, 2.0, (90, 0, 0)), 0.08)           # U section
    b = b.clip(plane(BOW_P, BOW_NL), 0.07).clip(plane(BOW_P, BOW_NR), 0.07)      # V bow
    b = b.clip(plane((0, -0.40, 0.57), (0, -0.60, -0.80)), 0.12)                # forefoot
    b = b.clip(plane((0, STERN_Y, 0.90), STERN_N), 0.05)                        # transom
    return b


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
    """Hull without deck carve (used for rails, bands and placement)."""
    return hull_core_parts()[0]


def visor_prim():
    """Prow visor: the top band of the bow rising from the gunwale line, overhanging the
    eyes, with a gull-wing lower edge (arcs over both eyes)."""
    v = hull_core().offset(0.032)
    # prow tip: the visor runs forward into a pointed, raked prow over the face
    tip = ellipsoid((0, -0.470, 1.192), (0.200, 0.190, 0.068), (-10, 0, 0))
    tp = (0.0, -0.648, 1.20)
    tn = np.array([0.56, -0.80, -0.20])
    tn /= np.linalg.norm(tn)
    tip = tip.clip(plane(tp, tuple(tn)), 0.03).clip(plane(tp, (-tn[0], tn[1], tn[2])), 0.03)
    v = v.union(tip, 0.06)
    v = v.clip(plane((0, -0.16, 0), (0, 1, 0)), 0.03)
    v = v.clip(plane((0, 0, 1.105), (0, 0, -1)), 0.018)
    sw = np.array([0.0, 0.42, -1.0])
    v = v.clip(plane((0, -0.32, 1.125), tuple(sw / np.linalg.norm(sw))), 0.02)   # tapers as it sweeps back
    for sx in (1, -1):                                                              # no "sideburns" by the rims
        ns = np.array([0.55 * sx, 0.0, -1.0])
        v = v.clip(plane((0.22 * sx, 0, 1.108), tuple(ns / np.linalg.norm(ns))), 0.02)
    v = v.cut(deck_prim().offset(-0.003), 0.010)
    cuts = None
    for sx in (1, -1):
        c, f, side, up = eye_frame(sx)
        cs = cylinder(tuple(c + up * 0.004), RIM_MAJOR + 0.040, 0.40, look_basis(f))
        cuts = cs if cuts is None else cuts.union(cs, 0.05)
    v = v.cut(cuts, 0.018)
    return K.Prim(v.fn, (-0.48, -0.70, 1.05), (0.48, -0.10, 1.32))


def outline_core():
    """Hull + visor: the outline the gunwale rail follows."""
    return hull_core().union(visor_prim(), 0.0)


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


def gunwale_loop(n=60):
    """Points along the deck edge (hull side meets the deck surface), closed loop; i=0 at the bow."""
    core = outline_core()
    pts = []
    for i in range(n):
        th = 2 * math.pi * i / n
        dx, dy = math.sin(th), -math.cos(th)
        a, b = 0.05, 0.80
        for _ in range(40):
            m = 0.5 * (a + b)
            x, y = dx * m, 0.02 + dy * m
            z = deck_z(x, y)
            if core(np.array([[x, y, z]]))[0] > 0.0:
                b = m
            else:
                a = m
        x, y = dx * a, 0.02 + dy * a
        pts.append(np.array([x, y, deck_z(x, y)]))
    return pts


# ----------------------------------------------------------------------------- shapes
def S(name, mat, voxel, tris, q, **kw):
    return Shape(name, mat, voxel=voxel * q, tris=tris, **kw)


def lens_xz(cx, half_w, z_top, z_bottom):
    """Shield outline in XZ (vesica of two Y-axis cylinders) clipped flat on top: an infinite prism along Y."""
    # two circles of radius R centred at x=+-a, height zc: half-width at zc = R - a, bottom tip at zc - sqrt(R^2 - a^2)
    a = 0.20
    R = half_w + a
    zc = z_bottom + math.sqrt(R * R - a * a)
    ca = cylinder((cx + a, 0.0, zc), R, 3.0, (90, 0, 0))
    cb = cylinder((cx - a, 0.0, zc), R, 3.0, (90, 0, 0))
    return ca.clip(cb).clip(plane((0, 0, z_top), (0, 0, 1)))


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
    hull = S("HulvarHull", "stone", 0.0062, 2330, q, color_soft=0.006, weight_sigma=0.05)
    hull.add(parts["chest"], "chest", HULL_HI, k=0.0)
    hull.add(parts["spine"], "spine", HULL_LO, k=0.0)
    hull.add(parts["hips"], "hips", HULL_LO, k=0.0)
    hull.add(parts["head"], "head", HULL_HI, k=0.0)
    hull.carve(deck, 0.025)
    # keel band: raised stripe from under the chin to the groin
    keel = core.offset(0.017).clip(plane((0.040, 0, 0), (1, 0, 0)), 0.012).clip(plane((-0.040, 0, 0), (-1, 0, 0)), 0.012)
    keel = keel.clip(plane((0, 0, 0.835), (0, 0, 1)), 0.03).clip(plane((0, 0.17, 0), (0, 1, 0)), 0.04)
    keel = bounded(keel, (-0.06, -0.60, 0.33), (0.06, 0.20, 0.86))
    hull.add(keel, "spine", KEEL, k=0.004)
    # side portholes (glow lens sits inside)
    port_c = []
    for sx in (1, -1):
        for py in PORT_YS:
            p = surface_point(core, (0.0, py, PORT_Z), (sx, 0, 0))
            n = field_normal(core, p)
            port_c.append((p, n, sx))
            hull.carve(sphere(tuple(p + n * 0.008), PORT_R + 0.004), 0.005, SOCKET)
    info["ports"] = port_c
    # mouth: dark slot between the face plate and the jaw
    hull.carve(box((0, -0.470, 0.912), (0.170, 0.10, 0.015), rounding=0.013), 0.006, MOUTH)
    # livery
    hull.paint(plane((0, 0, 0.84), (0, 0, 1)), HULL_LO, soft=0.24)              # vertical glaze gradient
    hull.paint(deck.offset(0.008), IVORY, soft=0.006)                            # ivory deck
    # eye sockets (after the face plate so they stay dark)
    for sx in (1, -1):
        c = eyes[sx][0]
        hull.carve(sphere(tuple(c), EYE_R + 0.006), 0.010, SOCKET)
        hull.paint(sphere(tuple(c), EYE_R + 0.010), SOCKET, soft=0.004)
    hull.detail(ellipsoid((0, -0.42, 1.02), (0.32, 0.15, 0.18)), 0.6)
    shapes.append(hull)
    info["hull"] = hull

    # ---------------------------------------------------------------- ivory face plate (stone): a raised inlay, crisp edge
    face = S("HulvarFace", "stone", 0.0032, 300, q, color_soft=0.004, weight_sigma=0.02)
    outline = ellipsoid(tuple(rim_c[1]), (0.152, 0.2, 0.142)).union(ellipsoid(tuple(rim_c[-1]), (0.152, 0.2, 0.142)), 0.06)
    outline = outline.union(ellipsoid((0, -0.46, 0.992), (0.13, 0.2, 0.078)), 0.05)
    smile = cylinder((0, -0.40, 1.40), 0.478, 0.6, (90, 0, 0))           # bottom edge curves up at the corners
    outline = outline.clip(smile, 0.02).clip(plane((0, -0.25, 0), (0, 1, 0)), 0.0)
    fp = core.offset(0.0075).clip(outline, 0.004)
    for sx in (1, -1):
        fp = fp.cut(sphere(tuple(eyes[sx][0]), EYE_R + 0.010), 0.004)
    fp = bounded(fp, (-0.36, -0.62, 0.86), (0.36, -0.20, 1.22))
    face.add(fp, "head", IVORY, k=0.0)
    face.paint(plane((0, 0, 0.95), (0, 0, 1)), IVORY_SH, soft=0.05)
    shapes.append(face)

    # ---------------------------------------------------------------- prow visor + bowsprit fin (stone, rigid on brow)
    brow = S("HulvarBrow", "stone", 0.0038, 380, q, color_soft=0.004, weight_sigma=0.02)
    brow.add(visor_prim(), "brow", INDIGO, k=0.0)
    fin = blade([(0, -0.540, 1.236), (0, -0.600, 1.268), (0, -0.650, 1.300), (0, -0.676, 1.318)],
                [0.040, 0.032, 0.022, 0.012], flat=0.60, normal=(1, 0, 0))
    brow.add(fin, "brow", INDIGO, k=0.030)
    brow.paint(plane((0, 0, 1.19), (0, 0, -1)), hexcol("4650B0"), soft=0.03)
    brow.paint(deck.offset(0.010).clip(plane((0, -0.62, 0), (0, -1, 0))), IVORY, soft=0.006)   # its top is deck
    brow.paint(sphere((0, -0.676, 1.318), 0.026), BRASS, soft=0.008)
    shapes.append(brow)

    # ---------------------------------------------------------------- jaw (stone, rigid on jaw)
    jaw = S("HulvarJaw", "stone", 0.0045, 240, q, color_soft=0.004, weight_sigma=0.02)
    j = ellipsoid((0, -0.352, 0.848), (0.226, 0.140, 0.098), (8, 0, 0))
    jp = (0.0, -0.530, 0.86)
    j = j.clip(plane(jp, (0.55, -0.835, 0.0)), 0.07).clip(plane(jp, (-0.55, -0.835, 0.0)), 0.07)
    j = j.clip(plane((0, 0, 0.904), (0, 0, 1)), 0.016)
    jaw.add(j, "jaw", INDIGO, k=0.0)
    jaw.paint(plane((0, 0, 0.885), (0, 0, -1)), hexcol("4650B0"), soft=0.02)
    shapes.append(jaw)

    # ---------------------------------------------------------------- arms (stone)
    for sx, side in ((1, "L"), (-1, "R")):
        arm = S(f"HulvarArm_{side}", "stone", 0.0058, 620, q, color_soft=0.006, weight_sigma=0.035)
        X = lambda p: (p[0] * sx, p[1], p[2])  # noqa: E731
        sh_, el_, wr_ = SHOULDER, ELBOW, WRIST
        arm.add(round_cone(X(sh_), X(el_), 0.110, 0.088), f"upperarm_{side}", HULL_HI, k=0.0)
        arm.add(round_cone(X(el_), X(wr_), 0.088, 0.118), f"forearm_{side}", INDIGO, k=0.03)
        fc = np.array(FIST_C)
        arm.add(box(X(fc), (0.136, 0.126, 0.126), rounding=0.088), f"hand_{side}", INDIGO, k=0.03)
        for x in (-0.074, -0.014, 0.046):
            arm.add(sphere(X(fc + np.array([x, -0.100, -0.053])), 0.045), f"hand_{side}", INDIGO, k=0.028)
        arm.add(capsule(X(fc + np.array([-0.120, -0.055, 0.057])), X(fc + np.array([-0.108, -0.108, -0.007])), 0.040), f"hand_{side}", INDIGO, k=0.02)
        shapes.append(arm)

    # ---------------------------------------------------------------- legs (stone)
    legs = S("HulvarLegs", "stone", 0.0058, 520, q, color_soft=0.006, weight_sigma=0.03)
    legs.add_mirrored(round_cone((0.190, 0.100, 0.560), (0.210, 0.070, 0.300), 0.126, 0.110), "thigh_L", HULL_LO, k=0.0)
    legs.add_mirrored(round_cone((0.210, 0.070, 0.300), (0.210, 0.080, 0.130), 0.110, 0.112), "shin_L", INDIGO, k=0.03)
    legs.add_mirrored(cylinder((0.210, 0.035, 0.068), 0.146, 0.068, rounding=0.045), "foot_L", INDIGO, k=0.035)
    legs.clip(plane((0, 0, 0.0), (0, 0, -1)), 0.0)
    legs.paint(plane((0, 0, 0.026), (0, 0, 1)), IVORY, soft=0.006)
    shapes.append(legs)

    # ---------------------------------------------------------------- plates: shoulder plates + transom shield (stone)
    plates = S("HulvarPlates", "stone", 0.0045, 260, q, color_soft=0.006, weight_sigma=0.03)
    for sx, side in ((1, "L"), (-1, "R")):
        sp = surface_point(core, (0.20 * sx, -0.02, 1.10), (sx, 0, 0.55))
        pl = core.offset(0.026).clip(sphere(tuple(sp), 0.165), 0.02).clip(plane((0, 0, 0.93), (0, 0, -1)), 0.02)
        pl = pl.cut(deck.offset(0.012), 0.01)
        plates.add(pl, "chest", INDIGO, k=0.0)
        plates.add(pl.offset(-0.012), f"upperarm_{side}", INDIGO, k=0.0)
    plates.paint(plane((0, 0, 1.12), (0, 0, -1)), hexcol("4650B0"), soft=0.05)
    shapes.append(plates)
    stern_plate = S("HulvarStern", "stone", 0.0042, 220, q, color_soft=0.006, weight_sigma=0.03)
    sh = lens_xz(0.0, 0.300, 1.150, 0.600)
    sp_n = np.array(STERN_N) / np.linalg.norm(STERN_N)
    stern = core.offset(0.016).clip(sh, 0.012).clip(plane((0, STERN_Y - 0.03, 0.90), tuple(-sp_n)), 0.006)
    stern = bounded(stern, (-0.34, 0.36, 0.55), (0.34, 0.54, 1.20))
    stern_plate.add(stern, "chest", INDIGO, k=0.0)
    stern_plate.paint(plane((0, 0, 1.10), (0, 0, -1)), hexcol("4650B0"), soft=0.06)
    shapes.append(stern_plate)
    stern_c = surface_point(stern, (0, STERN_Y - 0.005, 0.925), (0, 1, 0))
    info["stern_c"] = stern_c

    # ---------------------------------------------------------------- nest tub (stone, rigid on nest)
    nx, ny, nz = NEST_C
    nest = S("HulvarNest", "stone", 0.0042, 360, q, color_soft=0.005, weight_sigma=0.02)
    nest.add(cone((nx, ny, 1.235), 0.168, 0.214, 0.092, rounding=0.022), "nest", HULL_HI, k=0.0)
    nest.carve(cone((nx, ny, nz + 0.110), 0.136, 0.180, 0.110), 0.012, SOCKET)
    nest.paint(cone((nx, ny, nz + 0.110), 0.146, 0.190, 0.116), SOCKET, soft=0.008)
    nest.paint(plane((0, 0, 1.20), (0, 0, 1)), HULL_LO, soft=0.04)
    shapes.append(nest)
    lip_z = 1.235 + 0.092

    # ---------------------------------------------------------------- anchor (stone)
    anc = S("HulvarAnchor", "stone", 0.0038, 320, q, color_soft=0.006, weight_sigma=0.02)
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
    rail = S("HulvarGunwale", "metal", 0.0036, 360, q, color_soft=0.004, weight_sigma=0.05)
    loop = gunwale_loop(64)
    oc = outline_core()
    pts = []
    for p in loop:
        n = field_normal(oc, p)
        nh = np.array([n[0], n[1], 0.0])
        nh /= np.linalg.norm(nh) + 1e-9
        pts.append(p - nh * 0.007 + np.array([0, 0, 0.003]))
    m = len(pts)
    rail.add(capsule_chain([pts[i % m] for i in range(-6, 7)], 0.019), "brow", BRASS, k=0.0)
    rail.add(capsule_chain([pts[i] for i in range(6, 33)], 0.019), "chest", BRASS, k=0.0)
    rail.add(capsule_chain([pts[i % m] for i in range(32, 59)], 0.019), "chest", BRASS, k=0.0)
    shapes.append(rail)
    info["rail"] = pts

    face_brass = S("HulvarEyeRims", "metal", 0.0032, 320, q, color_soft=0.004, weight_sigma=0.02)
    for sx in (1, -1):
        c, f, side, up = eyes[sx]
        face_brass.add(torus(tuple(rim_c[sx]), RIM_MAJOR, 0.022, look_basis(f)), "head", BRASS, k=0.0)
    face_brass.paint(plane((0, 0, 1.08), (0, 0, -1)), BRASS_HI, soft=0.03)
    shapes.append(face_brass)

    tusks = S("HulvarTusks", "metal", 0.0030, 120, q, color_soft=0.004, weight_sigma=0.02)
    for sx in (1, -1):
        b0 = np.array([0.116 * sx, -0.448, 0.896])
        tusks.add(cylinder(tuple(b0 + np.array([0, 0, 0.032])), 0.022, 0.032, rounding=0.010), "jaw", BRASS, k=0.0)
        tusks.add(cylinder(tuple(b0 + np.array([0, 0, 0.068])), 0.030, 0.010, rounding=0.008), "jaw", BRASS_HI, k=0.012)
    shapes.append(tusks)

    side_brass = S("HulvarPortRims", "metal", 0.0024, 400, q, color_soft=0.004, weight_sigma=0.02)
    for p, n, sx in port_c:
        side_brass.add(torus(tuple(p + n * 0.004), PORT_R + 0.004, 0.0105, look_basis(n)), "spine", BRASS, k=0.0)
    shapes.append(side_brass)

    for sx, side in ((1, "L"), (-1, "R")):
        ab = S(f"HulvarCuff_{side}", "metal", 0.0032, 110, q, color_soft=0.004, weight_sigma=0.02)
        el = np.array(ELBOW) * np.array([sx, 1, 1])
        wr = np.array(WRIST) * np.array([sx, 1, 1])
        fd = (wr - el) / np.linalg.norm(wr - el)
        ab.add(torus(tuple(wr - fd * 0.016), 0.120, 0.022, look_basis(fd)), f"forearm_{side}", BRASS, k=0.0)
        shapes.append(ab)

    nb = S("HulvarNestRail", "metal", 0.0032, 330, q, color_soft=0.004, weight_sigma=0.02)
    nb.add(torus((nx, ny, lip_z), 0.200, 0.020), "nest", BRASS, k=0.0)
    top_z = lip_z + 0.057
    nb.add(torus((nx, ny, top_z), 0.206, 0.016), "nest", BRASS, k=0.0)
    for i in range(6):
        a = math.radians(30 + 60 * i)
        px, py = nx + math.sin(a) * 0.203, ny - math.cos(a) * 0.203
        nb.add(capsule((px, py, lip_z), (px, py, top_z), 0.012), "nest", BRASS, k=0.008)
    nb.paint(plane((0, 0, top_z + 0.006), (0, 0, -1)), BRASS_HI, soft=0.01)
    shapes.append(nb)

    ch = S("HulvarChain", "metal", 0.0032, 240, q, color_soft=0.004, weight_sigma=0.012)
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
    ports = S("HulvarPortGlow", "glow", 0.0028, 100, q, color_soft=0.004, weight_sigma=0.02)
    for p, n, sx in port_c:
        ports.add(ellipsoid(tuple(p - n * 0.006), (PORT_R * 0.92, PORT_R * 0.92, 0.012), look_basis(n)), "spine", GLOW, k=0.0)
    ports.paint(sphere((0, 0, 0), 5.0), GLOW, soft=0.01, emission=1.0)
    shapes.append(ports)

    glyph = S("HulvarGlyph", "glow", 0.0024, 280, q, color_soft=0.004, weight_sigma=0.02)
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

    nglow = S("HulvarNestGlow", "glow", 0.0034, 50, q, color_soft=0.004, weight_sigma=0.02)
    nglow.add(cylinder((nx, ny, nz + 0.003), 0.132, 0.010, rounding=0.006), "nest", GLOW, k=0.0)
    nglow.paint(sphere((0, 0, 0), 5.0), GLOW, soft=0.01, emission=1.0)
    shapes.append(nglow)

    rune = S("HulvarRune", "glow", 0.0030, 70, q, color_soft=0.003, weight_sigma=0.02)
    for sy in (1, -1):
        y = 0.712 + sy * 0.036
        rune.add(torus((0, y, 0.215), 0.022, 0.0055, look_basis((0, 1, 0))), "anchor", GLOW, k=0.0)
        rune.add(sphere((0, y, 0.215), 0.008), "anchor", GLOW, k=0.0)
    rune.paint(sphere((0, 0, 0), 5.0), GLOW, soft=0.01, emission=1.0)
    shapes.append(rune)

    throat = S("HulvarThroat", "glow", 0.0040, 40, q, color_soft=0.004, weight_sigma=0.02)
    throat.add(ellipsoid((0, -0.395, 0.905), (0.11, 0.03, 0.030)), "head", GLASS, k=0.0)
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
        pnt = surface_point(core_k, (0.0, -0.02, 0.82), d)
        x, y, z = pnt
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
    for x in (-0.16, 0.0, 0.16):
        probe.append((np.array([x, -0.45, 0.775]), "jaw"))
    for x in (-0.20, -0.10, 0.0, 0.10, 0.20):
        probe.append((np.array([x, 0.712, 0.215 - 0.04 * (1 - abs(x) / 0.2)]), "anchor"))
    probe.append((np.array([0.0, 0.712, 0.170]), "anchor"))
    for pnt in ((0.0, -0.676, 1.318), (0.0, -0.64, 1.20), (0.22, -0.52, 1.16), (-0.22, -0.52, 1.16), (0.0, -0.58, 1.13)):
        probe.append((np.array(pnt), "brow"))
    for sx in (1, -1):
        probe.append((np.array([0.15 * sx, -0.47, 1.03]), "head"))
        probe.append((np.array([0.15 * sx, -0.46, 0.93]), "head"))
    info["probe"] = probe
    hull.cull_by = [stern_plate, face]            # both rigid on bones that also drive those hull regions
    hull.cull_margin = 0.004
    for shp, margin in ((face, 0.010), (stern_plate, 0.012), (brow, 0.030), (jaw, 0.050), (plates, 0.035),
                        (face_brass, 0.010), (side_brass, 0.008), (rail, 0.020)):
        shp.cull_by = [hull]
        shp.cull_margin = margin
    glyph.cull_by = [stern_plate]
    gtop.cull_by = [stern_plate]
    tusks.cull_by = [jaw]
    tusks.cull_margin = 0.008
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
        ("brow", (0, -0.300, 1.185), (0, -0.440, 1.195), "head", True),
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
AO_STRENGTH = {"stone": 0.28, "metal": 0.18, "glow": 0.0, "glyph": 0.0}


def assemble(name, rig, shapes, extras, log):
    """sdfchar.assemble with per-material AO strength and per-piece timing."""
    import bpy
    import sdfchar
    from bhelpers import select_only
    rig_obj = rig.build(name)
    bones = [b for b in rig.order if rig.bones[b].deform]
    ao_field = sdfchar.union_field(shapes)
    objs = []
    for sh in shapes:
        t = time.time()
        o = K.build_object(sh, bones, log=log, ao_field=ao_field, ao_strength=AO_STRENGTH.get(sh.material, 0.4))
        sdfchar._assign_material(o, sh.material)
        objs.append(o)
        log(f"    {sh.name}: {time.time() - t:.1f}s")
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
FIST_DROP = WRIST[2] - (FIST_C[2] - 0.126) - 0.004   # wrist height when the fist rests flat on the sand


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
    body(P, drop=0.072 - 0.006 * b, pitch=15.5 + 0.8 * b, roll=0.9 * wv(ph, 1, 0.1), yaw=1.5 * wv(ph, 1, 0.3),
         spine=(3.0, 0.0, 0.0), chest=(3.5 - 1.2 * b, 0.0, 0.0))
    breathe(P, b)
    g = bump(ph, 0.30, 0.40, 0.56) if glance else 0.0         # glances up at the nest
    sideways = spline(ph, [(0.0, 0.0), (0.12, 7.0), (0.24, 0.0), (0.62, -6.0), (0.78, -1.0), (1.0, 0.0)], 1.0) if glance else 0.0
    P.rot("head", -11.0 - 9.0 * g + 1.0 * b, 0.6 * sideways, 0.0)
    eyes(P, yaw=1.6 * sideways, pitch=-4.0 + 22.0 * g)
    ch = bump(ph, 0.66, 0.70, 0.84) if glance else 0.0      # rumbling chuckle
    P.rot("jaw", 1.5 + ch * (4.0 + 3.0 * math.sin(ph * 2 * math.pi * 14.0)), 0.0, 0.0)
    P.rot("brow", 1.5 - 7.0 * g + 2.0 * ch, 0.0, 0.0)
    leg(P, "L", (FOOT_X, 0.08, ANKLE[2]))
    leg(P, "R", (-FOOT_X, 0.08, ANKLE[2]))
    tap = bump(ph, 0.84, 0.88, 0.94) if glance else 0.0     # left knuckles drum once
    arm_ik(P, "L", (0.530, -0.275, FIST_DROP - 0.010 + 0.05 * tap), hand_pitch=-6.0 * tap)
    arm_ik(P, "R", (-0.530, -0.275, FIST_DROP - 0.010))
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
    body(P, drop=0.050 - 0.026 * bob, pitch=8.0 + 1.5 * bob, roll=-4.0 * wv(ph, 1, -0.03), yaw=-5.0 * math.cos(2 * math.pi * ph),
         side=0.028 * wv(ph, 1, -0.03), spine=(1.0, 2.0 * math.cos(2 * math.pi * ph), 1.2 * wv(ph, 1, -0.10)),
         chest=(1.5, 2.5 * math.cos(2 * math.pi * (ph - 0.05)), 1.0 * wv(ph, 1, -0.16)))
    for side, sx, c0 in (("L", 1, 0.0), ("R", -1, 0.5)):
        y, z, planted = gait(ph, c0, (c0 + c) % 1.0, Y0 - S, Y0 + S, lift)
        pitch = 0.0 if planted else -14.0 * (z / lift)
        leg(P, side, (FOOT_X * sx, y, ANKLE[2] + z), pitch=pitch)
    for side, sx, off in (("L", 1, 0.5), ("R", -1, 0.0)):
        sw = 24.0 * math.cos(2 * math.pi * (ph - off - 0.07))
        arm_fk(P, side, swing=sw, out=7.0, twist=-4.0, elbow=10.0 + 9.0 * max(0.0, sw) / 24.0,
               wrist=(-6.0 - 8.0 * max(0.0, -sw) / 24.0, 0.0, 0.0))
    P.rot("head", -6.0 + 2.0 * bob, 1.5 * math.cos(2 * math.pi * ph), 1.5 * wv(ph, 1, -0.05))
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
    level_nest(P, 1.0, tilt=(3.0 * wv(ph, 2, -0.18), 0.0))   # counter-rotated: stays upright
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
    body(P0, drop=0.06 + 0.07 * sq, pitch=12.0 + 6.0 * sq, spine=(3, 0, 0), chest=(3, 0, 0))
    squash(P0, 1.0 - 0.07 * sq + 0.08 * bump(t, 0.06, 0.12, 0.22))
    leg(P0, "L", (FOOT_X, 0.08, ANKLE[2]))
    leg(P0, "R", (-FOOT_X, 0.08, ANKLE[2]))
    for side, sx in (("L", 1), ("R", -1)):
        arm_ik(P0, side, (0.53 * sx, -0.26 + 0.06 * sq, FIST_DROP + 0.01))
    P0.rot("head", -10.0, 0, 0)
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
    body(P, drop=0.062 + 0.10 * hit - 0.035 * reb, pitch=15.5 + 9.0 * hit - 3.0 * reb, spine=(3.0 + 3.0 * hit, 0, 0),
         chest=(3.5 + 4.0 * hit, 0, 0))
    squash(P, 1.0 - 0.09 * hit + 0.04 * reb)
    leg(P, "L", (FOOT_X + 0.02 * hit, 0.08, ANKLE[2]))
    leg(P, "R", (-FOOT_X - 0.02 * hit, 0.08, ANKLE[2]))
    for side, sx in (("L", 1), ("R", -1)):
        arm_ik(P, side, (0.56 * sx, -0.28 - 0.04 * hit, FIST_DROP + 0.024 * reb))
    P.rot("head", -11.0 + 8.0 * hit - 4.0 * reb, 0, 0)
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
    body(P, drop=0.06 + 0.04 * go, pitch=15.5 - 10.0 * ant + 18.0 * go + 1.2 * shake, fwd=0.05 * go, spine=(3.0 + 4.0 * go, 0, 0),
         chest=(3.5 + 4.0 * go, 0, 0))
    squash(P, 1.0 + 0.05 * go)
    leg(P, "L", (FOOT_X, lerp(0.08, -0.16, go), ANKLE[2]))
    leg(P, "R", (-FOOT_X, lerp(0.08, 0.34, go), ANKLE[2] + toe_lift(28.0 * go)), pitch=28.0 * go)
    for side, sx in (("L", 1), ("R", -1)):
        sw = lerp(-8.0 * ant, -62.0, go)
        arm_fk(P, side, swing=sw, out=lerp(8.0, 22.0, go), twist=-10.0 * go, elbow=lerp(12.0, 4.0, go), wrist=(18.0 * go, 0.0, 0.0))
    idle = idle_pose(0.0)
    P.rot("head", -11.0 + 26.0 * go + 6.0 * ant * -1.0, 0, 0)
    P.rot("jaw", 1.5 - 1.5 * go, 0, 0)
    P.rot("brow", 1.5 + 9.0 * go, 0, 0)
    eyes(P, pitch=8.0 * go, squash=1.0 - 0.18 * go)
    level_nest(P, 0.7, tilt=(-14.0 * go, 0.0))
    chain(P, hang(swing_x=3.0 + 45.0 * win(t, 0.08, 0.2) * (1.0 - win(t, 0.30, 0.5)) - 12.0 * bump(t, 0.38, 0.44, 0.5), swing_side=0.0))
    # arms ease back to the idle IK pose at the end
    return blend(P, idle, win(t, 0.40, 0.50))


def brace_pose(t):
    P = Pose()
    fire = 0.25
    rec = bump(t, fire, fire + 0.025, fire + 0.22)
    kick = bump(t, fire, fire + 0.03, fire + 0.12)
    wob = math.sin((t - fire) * 2 * math.pi * 5.0) * math.exp(-max(0.0, t - fire) * 7.0) * (1.0 if t > fire else 0.0)
    charge = win(t, 0.06, 0.22) * (1.0 - win(t, fire, fire + 0.02))
    jit = math.sin(t * 2 * math.pi * 24.0) * charge
    body(P, drop=0.115 + 0.01 * jit + 0.03 * rec, pitch=6.0 + 3.0 * charge - 11.0 * rec + 2.5 * wob, side=0.004 * jit,
         spine=(2.0 - 3.0 * rec, 0, 0), chest=(2.0 - 5.0 * rec, 0, 0))
    squash(P, 1.0 - 0.03 * charge - 0.08 * kick + 0.04 * wob)
    leg(P, "L", (0.31, 0.02, ANKLE[2]), yaw=-8.0)
    leg(P, "R", (-0.31, 0.14, ANKLE[2]), yaw=8.0)
    arm_ik(P, "L", (0.60, -0.21, FIST_DROP), hand_yaw=10.0)
    arm_ik(P, "R", (-0.60, -0.21, FIST_DROP), hand_yaw=10.0)
    P.rot("head", -6.0 - 12.0 * rec + 3.0 * wob, 0, 0)
    P.rot("jaw", 1.0 - 1.0 * charge + 22.0 * rec, 0, 0)
    P.rot("brow", 6.0 + 3.0 * charge - 12.0 * rec, 0, 0)
    eyes(P, pitch=10.0, squash=1.0 - 0.25 * charge - 0.5 * kick)
    level_nest(P, 1.0, tilt=(13.0 + 2.0 * charge - 32.0 * rec + 8.0 * wob, 0.0), back=0.09 * rec, up=-0.03 * rec)
    P.scl("nest", 1.0 + 0.10 * kick, 1.0 - 0.12 * kick + 0.05 * wob, 1.0 + 0.10 * kick)
    chain(P, hang(swing_x=-1.0 + 8.0 * rec, swing_side=0.0, base=(0.60, 0.44, 0.28, 0.14)))
    return P


@clip("brace", 0.70, loop=True)
def c_brace(t, ph):
    return brace_pose(t)


@clip("surf", 1.0, loop=True)
def c_surf(t, ph):
    """Trenó de Quilha: hull on the sand like a boat, legs folded inside, fists as rudders."""
    P = Pose()
    bob = 0.006 * wv(ph, 4) + 0.004 * wv(ph, 7, 0.3)
    body(P, drop=0.0, pitch=-5.0 + 1.5 * wv(ph, 2, 0.1), roll=3.0 * wv(ph, 1), spine=(0, 0, 0), chest=(1.0, 0, -1.0 * wv(ph, 1, -0.1)))
    z0 = lowest(P, HULL_BONES)
    lift_body(P, -z0 - 0.010 + bob)
    M = SK.fk(P)
    for side, sx in (("L", 1), ("R", -1)):
        hip = SK.head(P, f"thigh_{side}", M)
        leg(P, side, (0.20 * sx, hip.y - 0.10, hip.z + 0.07), pitch=80.0)
    for side, sx, off in (("L", 1, 0.0), ("R", -1, 0.5)):
        dip = 0.5 + 0.5 * wv(ph, 1, off)
        arm_ik(P, side, (0.78 * sx, 0.12 + 0.05 * dip, FIST_DROP + 0.002 + 0.025 * dip), hand_pitch=0.0, hand_yaw=-25.0,
               pole=(0.3, 1.0, 0.6))
    P.rot("head", -5.0 + 1.0 * wv(ph, 2), 0, 1.5 * wv(ph, 1))
    P.rot("jaw", 3.0, 0, 0)
    P.rot("brow", 3.0, 0, 0)
    eyes(P, pitch=-2.0, yaw=4.0 * wv(ph, 1, 0.2))
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
    body(P, drop=0.06 + 0.02 * hit, pitch=15.5 - 24.0 * hit + 5.0 * over, roll=-4.0 * hit, spine=(3.0 - 6.0 * hit, 0, 0),
         chest=(3.5 - 7.0 * hit, 0, 2.0 * hit))
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
        arm_fk(Pi, side, swing=0.0, out=6.0, elbow=6.0)
        from mathutils import Quaternion
        for bn in (f"upperarm_{side}", f"forearm_{side}", f"hand_{side}"):
            P.r[bn] = Pi.r.get(bn, Quaternion()).slerp(Pa.r.get(bn, Quaternion()), hit)
    P.rot("head", -11.0 - 14.0 * hit + 6.0 * over, 0, 4.0 * hit)
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
        bmesh.ops.translate(bm, vec=(0.0, 0.10, 1.215), verts=bm.verts)
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
