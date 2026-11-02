"""SOPRO — props do mundo "Lençóis do Céu" (modelagem procedural no Blender).

    blender -b --factory-startup --python game/blender/build_props.py [-- --only tower]

Cada prop vira game/assets/props/<nome>.glb (raiz = vazio com o nome do prop;
partes animadas são filhos nomeados: petal_N, blades, tube_N, gpetal_N...).
Materiais (o jogo troca pelo nome): stone, wood, leaf, bronze, glow, petal, cloth, jelly.
A areia acumulada no topo das pedras é aplicada no shader (normal para cima).
"""
from __future__ import annotations

import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Matrix, Vector, noise

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from bhelpers import ASSETS, export_glb, log, material, reset_scene  # noqa: E402
from charkit import mix, smooth01  # noqa: E402
from propkit import PropBuilder, stone_color  # noqa: E402

OUT = ASSETS / "props"
TAU = math.tau
TERRA = (0.86, 0.50, 0.38)
SANDST = (0.96, 0.76, 0.60)
CREAM = (0.99, 0.89, 0.75)
DARKST = (0.62, 0.36, 0.34)
BRONZE = (0.88, 0.58, 0.26)
BRONZE_D = (0.55, 0.32, 0.16)
WOOD = (0.64, 0.44, 0.31)
TEAL = (0.10, 0.68, 0.64)


def mats() -> dict:
    return {
        "stone": material("stone", (0.9, 0.6, 0.5, 1)),
        "wood": material("wood", (0.6, 0.4, 0.3, 1)),
        "leaf": material("leaf", (0.4, 0.6, 0.4, 1)),
        "bronze": material("bronze", (0.85, 0.55, 0.25, 1), roughness=0.35),
        "glow": material("glow", (0.5, 1.0, 0.9, 1), emission=(0.5, 1.0, 0.9, 2.0)),
        "petal": material("petal", (1.0, 0.6, 0.75, 1)),
        "cloth": material("cloth", (0.9, 0.3, 0.3, 1)),
        "jelly": material("jelly", (0.8, 0.9, 1.0, 1)),
    }


def root(name: str) -> bpy.types.Object:
    e = bpy.data.objects.new(name, None)
    bpy.context.scene.collection.objects.link(e)
    return e


def attach(obj, parent, loc=(0, 0, 0), rot=(0, 0, 0)):
    obj.parent = parent
    obj.location = loc
    obj.rotation_euler = rot
    return obj


def export(name: str, objs) -> None:
    allo = []
    for o in objs:
        allo.append(o)
        allo.extend(o.children_recursive)
    export_glb(OUT / f"{name}.glb", allo)


# ============================================================================ stone
def arch(M):
    r = root("Arco")
    pb = PropBuilder("ArcoPedra")
    col = stone_color(TERRA, seed=1.0, bands=3.0)
    for x in (-2.9, 2.9):
        pb.box((x, 0, 2.6), (1.15, 1.2, 5.2), lambda u, p: col(0, 0, p), taper=0.9, wobble=0.07, seed=x, subdiv=3)
        pb.box((x, 0, 0.2), (1.6, 1.6, 0.4), lambda u, p: col(0, 0, p), wobble=0.05, seed=x + 1)
    n = 9
    for k in range(n):
        if k == 6:
            continue
        a0 = math.pi * k / n
        a1 = math.pi * (k + 1) / n
        am = (a0 + a1) * 0.5
        cx, cz = math.cos(am) * 2.9, 5.2 + math.sin(am) * 2.9
        blk = PropBuilder("b")
        pb.box((cx, 0, cz), (1.05, 1.15, 1.1), lambda u, p: col(0, 0, p), rot_z=0.0, wobble=0.05, seed=k * 3.1, subdiv=2)
        # rotate the last box's vertices around Y to follow the arc
        cnt = 26
        c = Vector((cx, 0, cz))
        R = Matrix.Rotation(-(am - math.pi * 0.5), 3, "Y")
        for i in range(len(pb.verts) - cnt, len(pb.verts)):
            pb.verts[i] = c + R @ (pb.verts[i] - c)
    # fallen block
    pb.box((1.2, 1.6, 0.45), (1.1, 1.0, 0.9), lambda u, p: col(0, 0, p), rot_z=0.6, wobble=0.08, seed=9.0)
    o = attach(pb.build(M), r)
    return [r]


def pillar(M):
    r = root("Coluna")
    pb = PropBuilder("ColunaPedra")
    col = stone_color(SANDST, seed=2.0, bands=4.0)
    prof = [(0.75, 0.0), (0.75, 0.35), (0.58, 0.45), (0.55, 1.5), (0.52, 2.6), (0.5, 3.1), (0.42, 3.25)]
    pb.lathe(prof, col, seg=14, wobble=0.06, seed=3.0)
    # broken top: a few jagged lumps
    pb.ellipsoid((0.1, 0.05, 3.25), (0.4, 0.35, 0.25), lambda u, p: col(0, 0, p), wobble=0.35, seed=4.0)
    # fallen drum
    drum = [(0.5, 0.0), (0.52, 0.5), (0.5, 1.0)]
    R = Matrix.Rotation(math.pi * 0.5, 3, "X") @ Matrix.Rotation(0.4, 3, "Z")
    pb.lathe(drum, col, seg=12, center=(1.6, -0.3, 0.5), xform=R, wobble=0.05, seed=5.0)
    attach(pb.build(M), r)
    return [r]


def rocks(M):
    out = []
    for k in range(3):
        r = root(f"Pedra{k}")
        pb = PropBuilder(f"PedraMalha{k}")
        col = stone_color(mix(TERRA, SANDST, k * 0.4), seed=k * 2.0, bands=2.5)
        pb.ellipsoid((0, 0, 0.5), (1.3 + 0.3 * k, 1.0 + 0.2 * k, 0.9 - 0.1 * k), lambda u, p: col(0, 0, p),
                     seg=14, rings=10, wobble=0.28, seed=k * 5.0)
        attach(pb.build(M), r)
        export(f"rock_{k}", [r])
    return []


def spire(M):
    r = root("Agulha")
    pb = PropBuilder("AgulhaPedra")
    col = stone_color(TERRA, seed=6.0, bands=2.2)
    prof = []
    for i in range(23):
        z = i * 0.8
        rad = 3.4 * (1.0 - (i / 22.0) ** 1.4) + 0.5
        if i % 4 == 3:
            rad += 0.45          # ledges to land on
        prof.append((rad, z))
    prof.append((0.0, 18.0))
    pb.lathe(prof, col, seg=16, wobble=0.12, seed=7.0)
    attach(pb.build(M), r)
    return [r]


# ============================================================================ tower + bell
def tower(M):
    r = root("Torre")
    pb = PropBuilder("TorreMalha")

    def bandcol(i, a, p):
        z = p.z
        n = 0.5 + 0.5 * noise.noise(Vector((p.x * 0.6, p.y * 0.6, z * 0.4)))
        if int(z / 1.6) % 2 == 0:
            c = mix(TERRA, CREAM, 0.15 * n)
        else:
            c = mix(CREAM, SANDST, 0.4 * n)
        if 15.6 < z < 16.8 or z < 1.2:
            c = mix(SANDST, CREAM, 0.6)
        return c

    prof = [(5.6, 0.0), (5.6, 0.5), (5.0, 0.6), (5.0, 1.1), (4.0, 1.2), (3.4, 1.4), (3.2, 5.0), (3.0, 10.0),
            (2.8, 14.0), (2.8, 15.6), (3.7, 15.8), (3.7, 16.6), (2.6, 16.8)]
    pb.lathe(prof, bandcol, seg=8, wobble=0.015, seed=1.0)
    # belfry pillars
    for k in range(4):
        a = TAU * (k + 0.5) / 4
        pb.box((math.cos(a) * 2.45, math.sin(a) * 2.45, 18.9), (0.75, 0.75, 4.2), lambda u, p: bandcol(0, 0, p),
               wobble=0.03, seed=k, subdiv=2)
    # dome roof + spire
    roof = [(3.2, 21.0), (3.25, 21.4), (2.9, 22.4), (2.2, 23.4), (1.2, 24.2), (0.35, 25.0), (0.25, 26.6), (0.0, 27.2)]
    pb.lathe(roof, lambda i, a, p: mix(TEAL, (0.2, 0.5, 0.6), i / 8.0) if i < 6 else BRONZE, seg=12)
    # festa-junina-ish ornaments: little bronze rings on the balcony
    tw = attach(pb.build(M), r)
    # seed sockets (filled by the game)
    for k in range(3):
        a = TAU * k / 3 + math.pi * 0.5
        s = PropBuilder(f"socket_{k}")
        s.lathe([(0.55, 0.0), (0.7, 0.25), (0.62, 0.5), (0.35, 0.45), (0.0, 0.42)],
                lambda i, aa, p: BRONZE if i < 3 else BRONZE_D, mat="bronze", seg=12)
        s.lathe([(0.3, 0.46), (0.3, 0.5)], lambda i, aa, p: (0.4, 1.0, 0.9), mat="glow", seg=12)
        o = s.build(M)
        attach(o, r, (math.cos(a) * 4.5, math.sin(a) * 4.5, 1.1))
    return [r]


def bell(M):
    r = root("Sino")
    pb = PropBuilder("SinoMalha")
    outer = [(0.0, 2.25), (0.55, 2.2), (0.9, 1.95), (1.05, 1.5), (1.15, 0.9), (1.35, 0.35), (1.6, 0.05), (1.64, 0.0)]
    inner = [(1.5, 0.0), (1.25, 0.32), (1.05, 0.9), (0.95, 1.5), (0.75, 1.95), (0.0, 2.05)]

    def bcol(i, a, p):
        z = p.z
        c = BRONZE
        if 0.25 < z < 0.4 or 1.6 < z < 1.7:
            c = mix(BRONZE, (1.0, 0.85, 0.5), 0.7)
        return mix(c, BRONZE_D, 0.25 * (0.5 + 0.5 * math.sin(a * 6)))

    pb.lathe(outer, bcol, mat="bronze", seg=28, cap_bottom=False, cap_top=True)
    pb.lathe(inner, lambda i, a, p: BRONZE_D, mat="bronze", seg=28, cap_bottom=False, cap_top=True)
    pb.ellipsoid((0, 0, 0.35), (0.28, 0.28, 0.3), lambda u, p: BRONZE_D, mat="bronze")
    pb.tube([(0, 0, 0.6), (0, 0, 2.0)], [0.07, 0.07], lambda t, a, p: BRONZE_D, mat="bronze", seg=8)
    pb.box((0, 0, 2.45), (0.5, 3.4, 0.35), lambda u, p: WOOD, mat="wood", subdiv=1)
    attach(pb.build(M), r, (0, 0, -2.3))
    return [r]


# ============================================================================ vegetation
def palm(M):
    out = []
    for k in range(2):
        rnd = random.Random(10 + k)
        r = root(f"Carnauba{k}")
        trunk = PropBuilder(f"Tronco{k}")
        h = 7.0 + 1.6 * k
        lean = Vector((0.5 + 0.3 * k, 0.2, 0))
        pts, radii = [], []
        for i in range(12):
            t = i / 11
            pts.append(Vector((0, 0, h * t)) + lean * (t * t) * 2.0)
            radii.append(0.32 - 0.1 * t + (0.15 if i == 0 else 0.0))

        def tcol(t, a, p):
            ring = 0.5 + 0.5 * math.sin(p.z * 9.0)
            c = mix((0.58, 0.50, 0.45), (0.72, 0.64, 0.56), ring * 0.6)
            return c + (min(1.0, (p.z / h) ** 2 * 0.35),)

        trunk.tube(pts, radii, tcol, mat="wood", seg=9)
        top = pts[-1]
        for j in range(15):
            az = TAU * j / 15 + rnd.uniform(-0.15, 0.15)
            el = rnd.uniform(-0.15, 0.55)
            d = Vector((math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el)))
            stalk_end = top + d * 1.3
            trunk.tube([top, top + d * 0.65, stalk_end], [0.05, 0.04, 0.03],
                       lambda t, a, p: (0.55, 0.6, 0.4, 0.4 + 0.4 * t), mat="wood", seg=5, cap=False)
            trunk.leaf_fan(stalk_end, d + Vector((0, 0, 0.15)), rnd.uniform(1.4, 1.8), 0.32,
                           (0.42, 0.60, 0.44), (0.66, 0.78, 0.52), leaflets=11, segs=5, droop=0.55)
        # a skirt of old dry fronds
        for j in range(5):
            az = TAU * j / 5 + 0.3
            d = Vector((math.cos(az), math.sin(az), -1.6)).normalized()
            trunk.leaf_fan(top - Vector((0, 0, 0.3)), d, 1.1, 0.28, (0.62, 0.52, 0.36), (0.78, 0.66, 0.45),
                           leaflets=7, segs=3, droop=0.1)
        attach(trunk.build(M), r)
        export(f"palm_{k}", [r])
    return []


def grass_tuft(M):
    """Small reed/grass tuft for lagoon shores (instanced by thousands)."""
    r = root("Capim")
    pb = PropBuilder("CapimMalha")
    rnd = random.Random(3)
    m = pb.mat("leaf")
    for k in range(7):
        a = TAU * k / 7 + rnd.uniform(-0.3, 0.3)
        lean = rnd.uniform(0.15, 0.45)
        h = rnd.uniform(0.35, 0.6)
        d = Vector((math.cos(a) * lean, math.sin(a) * lean, 1.0)).normalized()
        side = Vector((-math.sin(a), math.cos(a), 0)) * 0.03
        base = Vector((math.cos(a) * 0.04, math.sin(a) * 0.04, 0))
        prev = None
        for s in range(4):
            t = s / 3
            p = base + d * h * t + Vector((math.cos(a), math.sin(a), 0)) * 0.12 * t * t
            w = 1.0 - t
            col = mix((0.40, 0.58, 0.38), (0.80, 0.86, 0.55), t) + (t,)
            i0 = pb.v(p - side * w, col)
            i1 = pb.v(p + side * w, col)
            if prev:
                pb.f((prev[0], prev[1], i1, i0), m)
            prev = (i0, i1)
    attach(pb.build(M), r)
    return [r]


# ============================================================================ interactables
def pinwheel(M):
    r = root("CataVento")
    stick = PropBuilder("Haste")
    stick.tube([(0, 0, 0), (0, 0, 3.0)], [0.07, 0.06],
               lambda t, a, p: (1, 1, 1) if int(p.z * 3.0 + a / TAU) % 2 == 0 else (0.95, 0.3, 0.35), mat="wood", seg=10)
    attach(stick.build(M), r)
    bl = PropBuilder("blades")
    m = bl.mat("cloth")
    cols = [(0.98, 0.32, 0.4), (1.0, 0.8, 0.25), (0.15, 0.62, 0.95), (0.35, 0.82, 0.5)]
    for k in range(4):
        a = TAU * k / 4
        R = Matrix.Rotation(a, 3, "Y")
        c = cols[k]
        pts = [Vector((0, 0, 0)), Vector((0.95, 0, 0.05)), Vector((0.9, 0.18, 0.95)), Vector((0.1, 0.05, 0.1))]
        idx = [bl.v(R @ p, mix(c, (1, 1, 1), 0.15 * i)) for i, p in enumerate(pts)]
        bl.f((idx[0], idx[1], idx[2]), m)
        bl.f((idx[0], idx[2], idx[3]), m)
        bl.f((idx[2], idx[1], idx[0]), m)
        bl.f((idx[3], idx[2], idx[0]), m)
    bl.ellipsoid((0, 0.05, 0), (0.12, 0.08, 0.12), lambda u, p: (1.0, 0.85, 0.3), mat="cloth")
    attach(bl.build(M), r, (0, -0.12, 3.0))
    return [r]


def flower_cannon(M):
    r = root("FlorCanhao")
    base = PropBuilder("Base")
    for k in range(5):
        a = TAU * k / 5 + 0.3
        base.leaf_fan((0, 0, 0.05), (math.cos(a), math.sin(a), 0.12), 1.8, 0.9, (0.3, 0.62, 0.42), (0.5, 0.78, 0.5),
                      leaflets=3, segs=4, droop=0.15)
    stem = [(0, 0, 0), (0.05, 0, 0.6), (0.0, 0.05, 1.2), (0, 0, 1.55)]
    base.tube(stem, [0.24, 0.2, 0.2, 0.26], lambda t, a, p: (0.32, 0.62, 0.38, 0.0), mat="leaf", seg=10)
    base.lathe([(0.3, 1.5), (0.8, 1.7), (1.15, 2.1), (1.2, 2.3), (1.0, 2.25), (0.3, 1.9), (0.0, 1.85)],
               lambda i, a, p: mix((0.3, 0.64, 0.4), (1.0, 0.86, 0.35), smooth01((i - 3) / 3.0)), mat="leaf", seg=16)
    base.ellipsoid((0, 0, 1.95), (0.55, 0.55, 0.18), lambda u, p: (1.0, 0.9, 0.4), mat="glow", seg=12, rings=6)
    attach(base.build(M), r)
    for k in range(6):
        a = TAU * k / 6
        pt = PropBuilder(f"petal_{k}")
        m = pt.mat("petal")
        rows = []
        for i in range(7):
            t = i / 6
            w = 0.55 * math.sin(math.pi * min(1.0, 0.15 + t * 0.95))
            x = 1.9 * t
            z = 0.6 * math.sin(t * 1.4) - 0.2 * t * t
            row = []
            for j in range(5):
                s = j / 4 * 2 - 1
                cup = 0.18 * (1 - s * s)
                col = mix((0.98, 0.42, 0.62), (1.0, 0.92, 0.95), t * t) + (t,)
                row.append(pt.v((x, s * w, z + cup), col))
            rows.append(row)
        for i in range(6):
            for j in range(4):
                pt.f((rows[i][j], rows[i + 1][j], rows[i + 1][j + 1], rows[i][j + 1]), m)
                pt.f((rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j], rows[i][j]), m)
        o = pt.build(M)
        # closed pose: petals point up (rotate about local Y), pivot on the cup rim
        attach(o, r, (math.cos(a) * 1.05, math.sin(a) * 1.05, 2.2), (0, -math.radians(55), a))
    return [r]


def chime_post(M):
    r = root("PosteSinos")
    p = PropBuilder("Poste")
    p.tube([(0, 0, 0), (0, 0, 2.7)], [0.1, 0.08], lambda t, a, q: WOOD, mat="wood", seg=8)
    p.tube([(-0.75, 0, 2.5), (0.75, 0, 2.5)], [0.06, 0.06], lambda t, a, q: WOOD, mat="wood", seg=8)
    p.ellipsoid((0, 0, 2.78), (0.16, 0.16, 0.1), lambda u, q: (0.9, 0.3, 0.35), mat="cloth")
    attach(p.build(M), r)
    for k in range(5):
        x = -0.6 + 0.3 * k
        L = 0.55 + 0.1 * (2 - abs(k - 2)) + 0.05 * k
        t = PropBuilder(f"tube_{k}")
        t.tube([(0, 0, 0), (0, 0, -0.12)], [0.008, 0.008], lambda u, a, q: (0.3, 0.25, 0.2), mat="wood", seg=4, cap=False)
        t.lathe([(0.045, -0.12), (0.05, -0.14), (0.05, -0.12 - L), (0.04, -0.14 - L)],
                lambda i, a, q: mix(TEAL, (0.75, 0.95, 0.9), 0.3 + 0.2 * math.sin(a * 3)), mat="bronze", seg=10)
        attach(t.build(M), r, (x, 0, 2.44))
    return [r]


def gate_flower(M):
    r = root("PortaoFlor")
    b = PropBuilder("BaseFlor")
    col = stone_color(SANDST, seed=8.0, bands=3.0)
    b.lathe([(2.6, 0.0), (2.6, 0.35), (2.2, 0.5), (0.0, 0.5)], col, seg=20)
    attach(b.build(M), r)
    for k in range(5):
        a = TAU * k / 5
        pt = PropBuilder(f"gpetal_{k}")
        m = pt.mat("stone")
        rows = []
        for i in range(8):
            t = i / 7
            w = 1.25 * math.sin(math.pi * min(1.0, 0.12 + t * 0.92))
            x = -0.15 * math.sin(t * math.pi) * 2.0 + 0.25 * t
            z = 3.4 * t
            row = []
            for j in range(6):
                s = j / 5 * 2 - 1
                bulge = 0.35 * (1 - s * s) * math.sin(math.pi * t)
                q = Vector((x + bulge, s * w, z))
                row.append(pt.v(q, mix(col(0, 0, q + Vector((a, 0, 0))), (0.95, 0.75, 0.62), t * 0.5)))
            rows.append(row)
        for i in range(7):
            for j in range(5):
                pt.f((rows[i][j], rows[i + 1][j], rows[i + 1][j + 1], rows[i][j + 1]), m)
                pt.f((rows[i][j + 1], rows[i + 1][j + 1], rows[i + 1][j], rows[i][j]), m)
        o = pt.build(M)
        attach(o, r, (math.cos(a) * 1.55, math.sin(a) * 1.55, 0.45), (0, math.radians(-14), a + math.pi))
    return [r]


def plate(M):
    out = []
    for heavy in (False, True):
        nm = "plate_heavy" if heavy else "plate"
        r = root("PlacaPesada" if heavy else "Placa")
        rad = 1.35 if heavy else 1.0
        p = PropBuilder("PlacaPedra")
        col = stone_color(CREAM if not heavy else SANDST, seed=11.0)
        p.lathe([(rad + 0.15, 0.0), (rad + 0.1, 0.12), (rad, 0.2), (0.0, 0.2)], col, seg=24)
        p.lathe([(rad * 0.75, 0.205), (rad * 0.62, 0.205)],
                lambda i, a, q: (1.0, 0.75, 0.3) if heavy else (0.4, 1.0, 0.9), mat="glow", seg=24, cap_top=False, cap_bottom=False)
        attach(p.build(M), r)
        export(nm, [r])
    return []


def seed(M):
    r = root("Semente")
    s = PropBuilder("SementeMalha")
    s.lathe([(0.0, -0.55), (0.14, -0.45), (0.22, -0.25), (0.2, 0.0), (0.12, 0.2), (0.05, 0.3), (0.0, 0.32)],
            lambda i, a, q: mix((1.0, 0.75, 0.35), (1.0, 0.95, 0.7), i / 6.0), mat="glow", seg=14, wobble=0.04)
    s.tube([(0, 0, 0.3), (0, 0, 1.0)], [0.025, 0.02], lambda t, a, q: (1.0, 0.95, 0.8), mat="glow", seg=6)
    rnd = random.Random(5)
    for k in range(26):
        az = TAU * k / 26 + rnd.uniform(-0.1, 0.1)
        el = rnd.uniform(0.15, 1.2)
        d = Vector((math.cos(az) * math.cos(el), math.sin(az) * math.cos(el), math.sin(el)))
        a = Vector((0, 0, 1.0))
        b = a + d * 0.75
        s.tube([a, (a + b) * 0.5 + Vector((0, 0, 0.05)), b], [0.012, 0.01, 0.008], lambda t, aa, q: (1.0, 1.0, 0.95),
               mat="glow", seg=4, cap=False)
        s.ellipsoid(b, (0.06, 0.06, 0.06), lambda u, q: (1.0, 1.0, 1.0), mat="glow", seg=6, rings=4)
    attach(s.build(M), r)
    return [r]


def totem(M):
    r = root("Totem")
    t = PropBuilder("TotemPedra")
    col = stone_color(TERRA, seed=12.0, bands=4.0)
    t.lathe([(0.7, 0.0), (0.7, 0.25), (0.5, 0.35), (0.42, 1.8), (0.32, 2.2), (0.0, 2.5)], col, seg=6, wobble=0.04)
    for k in range(3):
        z = 0.7 + k * 0.45
        t.lathe([(0.445, z), (0.445, z + 0.12)], lambda i, a, q: (0.4, 1.0, 0.9), mat="glow", seg=6,
                cap_top=False, cap_bottom=False)
    attach(t.build(M), r)
    return [r]


def portal_ring(M):
    r = root("Portal")
    p = PropBuilder("PortalPedra")
    col = stone_color(SANDST, seed=13.0, bands=2.0)
    n = 14
    for k in range(n):
        a = TAU * k / n
        cx, cz = math.cos(a) * 1.9, 2.1 + math.sin(a) * 1.9
        before = len(p.verts)
        p.box((cx, 0, cz), (0.7, 0.75, 0.62), lambda u, q: col(0, 0, q), wobble=0.04, seed=k, subdiv=1)
        R = Matrix.Rotation(-a, 3, "Y")
        c = Vector((cx, 0, cz))
        for i in range(before, len(p.verts)):
            p.verts[i] = c + R @ (p.verts[i] - c)
    p.box((0, 0, 0.12), (4.6, 1.2, 0.24), lambda u, q: col(0, 0, q), wobble=0.03, subdiv=2)
    for k in range(6):
        a = TAU * k / 6 + 0.26
        p.ellipsoid((math.cos(a) * 1.9, -0.38, 2.1 + math.sin(a) * 1.9), (0.09, 0.03, 0.09),
                    lambda u, q: (0.6, 0.5, 1.0), mat="glow", seg=8, rings=5)
    attach(p.build(M), r)
    return [r]


def jelly_bell(M):
    r = root("AguaViva")
    j = PropBuilder("Sino")
    prof = [(0.0, 1.0), (0.45, 0.97), (0.8, 0.86), (1.05, 0.62), (1.18, 0.32), (1.2, 0.12), (1.12, 0.05),
            (0.95, 0.18), (0.6, 0.42), (0.0, 0.5)]
    j.lathe(prof, lambda i, a, q: mix((0.75, 0.9, 1.0), (1.0, 0.75, 0.95), smooth01(i / 6.0)) + (1.0 if i < 6 else 0.6,),
            mat="jelly", seg=28, cap_top=False, cap_bottom=False)
    # scalloped rim lumps
    for k in range(12):
        a = TAU * k / 12
        j.ellipsoid((math.cos(a) * 1.16, math.sin(a) * 1.16, 0.1), (0.16, 0.16, 0.09),
                    lambda u, q: (1.0, 0.8, 0.95), mat="jelly", seg=8, rings=5)
    attach(j.build(M), r)
    return [r]


PROPS = {
    "arch": arch, "pillar": pillar, "rocks": rocks, "spire": spire, "tower": tower, "bell": bell,
    "palm": palm, "grass": grass_tuft, "pinwheel": pinwheel, "flower_cannon": flower_cannon,
    "chime_post": chime_post, "gate_flower": gate_flower, "plate": plate, "seed": seed, "totem": totem,
    "portal": portal_ring, "jelly": jelly_bell,
}


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = argv[argv.index("--only") + 1] if "--only" in argv else None
    for name, fn in PROPS.items():
        if only and name != only:
            continue
        reset_scene()
        M = mats()
        objs = fn(M)
        if objs:
            export(name, objs)


if __name__ == "__main__":
    main()
