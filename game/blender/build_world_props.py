"""build_world_props.py — props do mundo de Ylvaar, modelados por SDF (sdfkit) e bmesh.

    blender -b --factory-startup --python game/blender/build_world_props.py [-- --only agulha,arco]

Saída: game/assets/props/<nome>.glb. Convenção: Blender Z-up; a FRENTE do prop é -Y
do Blender (= +Z do Godot, para onde a rotação "rot" da receita aponta). Origem no
chão, no centro da base. Materiais pelo nome (PropLib troca pelos shaders do jogo):
stone, bronze, glow, crystal, seam, jelly.

Cultura "Vael": arenito claro gasto pelo vento, inlays de latão e glifos ciano.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))

import bmesh  # noqa: E402
import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import sdfprop  # noqa: E402
from bhelpers import ASSETS, export_glb, log, material, reset_scene, select_only  # noqa: E402
from sdfkit import (Shape, box, capsule, cone, cylinder, ellipsoid, hexcol, plane, round_cone,  # noqa: E402
                    sphere, srgb_to_linear, torus, tube, blade)

OUT = ASSETS / "props"

STONE_L = hexcol("EED3B0")
STONE = hexcol("DDB28A")
STONE_D = hexcol("BE8D69")
STONE_DD = hexcol("9E6E55")
SAND = hexcol("EBBC92")
BRASS = hexcol("D4A33F")
BRASS_D = hexcol("9C7428")
GLYPH = hexcol("8FFFF2")
EMBER = hexcol("FFB85A")
CRY_A = hexcol("B9A6F0")
CRY_B = hexcol("7FE9E4")


# ----------------------------------------------------------------------------- helpers
def _mat(name: str):
    m = bpy.data.materials.get(name)
    return m if m is not None else material(name, (0.8, 0.8, 0.8, 1.0))


def strata(shape: Shape, z0: float, z1: float, step: float, cols=(STONE_L, STONE, STONE_D), soft=0.15):
    """Faixas horizontais de arenito (pintura)."""
    z = z0
    i = 0
    while z < z1:
        shape.paint(box((0, 0, z + step * 0.5), (500, 500, step * 0.5)), cols[i % len(cols)], soft=soft)
        z += step
        i += 1


def sand_drift(shape: Shape, c, radii, seed=5):
    """Monte de areia acumulada na base (mistura suave com a peça)."""
    shape.add(ellipsoid(c, radii).displace(min(radii) * 0.12, 1.0 / max(radii[0], 0.5), 2, seed), "root", SAND,
              k=min(radii) * 0.6)


def build_parts(parts: dict, ao=True):
    """parts = {nome_do_objeto: ([shapes], [extras], pivot_or_None)} -> objetos Blender."""
    objs = []
    for name, (shapes, extras, pivot) in parts.items():
        o = sdfprop.build_prop(name, shapes, extras, ao=ao) if shapes else None
        if o is None:
            select_only(list(extras))
            bpy.context.view_layer.objects.active = extras[0]
            if len(extras) > 1:
                bpy.ops.object.join()
            o = bpy.context.view_layer.objects.active
            o.name = name
        if pivot is not None:
            pv = Vector(pivot)
            o.data.transform(Matrix.Translation(-pv))
            o.location = pv
        objs.append(o)
    return objs


def export(name: str, objs) -> None:
    export_glb(OUT / f"{name}.glb", objs)


def bm_object(name: str, bm: bmesh.types.BMesh, mat: str, color, flat=True, gradient=None) -> bpy.types.Object:
    """Objeto de bmesh com cor por vértice (gradient(z)->(r,g,b) opcional) e material."""
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    for p in me.polygons:
        p.use_smooth = not flat
    attr = me.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
    cols = []
    zs = [v.co.z for v in me.vertices]
    zmin, zmax = (min(zs), max(zs)) if zs else (0, 1)
    for v in me.vertices:
        c = color if gradient is None else gradient((v.co.z - zmin) / max(zmax - zmin, 1e-6))
        cols.extend([srgb_to_linear(c[0]), srgb_to_linear(c[1]), srgb_to_linear(c[2]), c[3] if len(c) > 3 else 0.0])
    attr.data.foreach_set("color", cols)
    me.color_attributes.active_color = attr
    me.uv_layers.new(name="UVMap")
    me.materials.append(_mat(mat))
    return obj


def crystal_prism(bm, base, direction, length, radius, sides=6, tip=0.35, twist=0.0):
    """Prisma de cristal com ponta piramidal, ao longo de `direction`."""
    d = Vector(direction).normalized()
    up = Vector((0, 0, 1)) if abs(d.z) < 0.95 else Vector((1, 0, 0))
    x = d.cross(up).normalized()
    y = d.cross(x).normalized()
    b = Vector(base)
    ring0, ring1 = [], []
    body = length * (1.0 - tip)
    for i in range(sides):
        a = 2 * math.pi * i / sides + twist
        off = (x * math.cos(a) + y * math.sin(a)) * radius
        ring0.append(bm.verts.new(b + off * 0.92))
        ring1.append(bm.verts.new(b + d * body + off))
    apex = bm.verts.new(b + d * length)
    for i in range(sides):
        j = (i + 1) % sides
        bm.faces.new((ring0[i], ring0[j], ring1[j], ring1[i]))
        bm.faces.new((ring1[i], ring1[j], apex))
    bm.faces.new(list(reversed(ring0)))


def empty(name: str, loc) -> bpy.types.Object:
    e = bpy.data.objects.new(name, None)
    e.location = Vector(loc)
    bpy.context.scene.collection.objects.link(e)
    return e


# ============================================================================= landmarks
def agulha():
    """Agulha de Vael: lâmina-gnômon de relógio de sol (130 m), inclinada 35° para a
    frente (+Y do Blender = -Z do Godot; a receita gira para o sol), sobre um mostrador
    em degraus com 12 marcos de hora. Costura dourada ("seam") que acende por partes."""
    lean = math.radians(35.0)
    D = np.array([0.0, math.sin(lean), math.cos(lean)])
    N = np.cross(D, np.array([1.0, 0.0, 0.0]))          # blade normal (thickness direction)
    B = np.array([0.0, -3.0, 3.0])
    L = 132.0
    ts = [0.0, 0.12, 0.3, 0.5, 0.7, 0.86, 1.0]
    widths = [9.0, 8.0, 6.4, 4.6, 2.9, 1.5, 0.3]
    pts = [tuple(B + D * L * t) for t in ts]
    bl = Shape("Lamina", "stone", voxel=0.32, tris=1600, color_soft=0.6)
    bl.add(blade(pts, widths, flat=0.3, normal=tuple(N), k=3.0).displace(0.15, 0.06, 2, 7), "root", STONE_L, k=0)
    bl.add(cone((0, -1.0, 2.6), 9.5, 7.0, 3.0, rounding=0.4), "root", STONE, k=2.0)      # socket collar
    bl.paint(sphere(tuple(B + D * L), 26.0), hexcol("F4E2C4"), soft=10.0)
    for t in (0.33, 0.66):
        c = B + D * L * t
        bl.paint(plane(tuple(c), tuple(D)).clip(plane(tuple(c - D * 0.8), tuple(-D))), BRASS, soft=0.25)
    dial = Shape("Mostrador", "stone", voxel=0.18, tris=1500, color_soft=0.3)
    dial.add(cylinder((0, 0, 0.45), 23.0, 0.9, rounding=0.4), "root", STONE_D, k=0)
    dial.add(cylinder((0, 0, 1.55), 19.0, 0.65, rounding=0.3), "root", STONE, k=0)
    dial.add(cylinder((0, 0, 2.5), 14.5, 0.55, rounding=0.25), "root", STONE_L, k=0)
    for i in range(12):
        a = 2 * math.pi * i / 12
        c = (math.cos(a) * 21.0, math.sin(a) * 21.0, 1.9)
        dial.add(box(c, (0.55, 0.55, 1.1), (0, 0, math.degrees(a)), rounding=0.12), "root", STONE_L, k=0)
    dial.carve(torus((0, 0, 3.05), 11.5, 0.22), k=0.05, color=BRASS)
    # gold seam on the upper (back) face: alpha = progress 0..1 along the blade
    sm = Shape("Costura", "seam", voxel=0.12, tris=500)
    seam_pts = [tuple(B + D * L * t - N * (w * 0.30 + 0.15)) for t, w in zip(ts[:-1], widths[:-1])]
    sm.add(tube(seam_pts, [0.7, 0.62, 0.52, 0.42, 0.32, 0.22], k=0.4), "root", hexcol("FFD27A"), k=0)
    lam, mos, cos_ = build_parts({"Lamina": ([bl], [], None), "Mostrador": ([dial], [], None),
                                  "Costura": ([sm], [], None)})
    # seam progress in vertex alpha (0 at the base -> 1 at the tip)
    me = cos_.data
    attr = me.color_attributes.get("Col")
    col = np.empty(len(me.vertices) * 4, np.float32)
    attr.data.foreach_get("color", col)
    col = col.reshape(-1, 4)
    co = np.empty(len(me.vertices) * 3, np.float32)
    me.vertices.foreach_get("co", co)
    proj = (co.reshape(-1, 3) - B) @ D / (L * 0.86)
    col[:, 3] = np.clip(proj, 0.0, 1.0)
    attr.data.foreach_set("color", col.ravel())
    export("agulha", [lam, mos, cos_])


def portao_vael():
    """Portão de Vael (objetivo): três pilones em arco com bacias-encaixe onde as Pedras
    das Horas pousam (empties socket_0..2), sobre um patamar curvo."""
    st = Shape("Portao", "stone", voxel=0.06, tris=2200, color_soft=0.12)
    st.add(box((0, 0, 0.3), (6.5, 2.6, 0.3), rounding=0.12), "root", STONE_D, k=0)
    st.add(box((0, 0.3, 0.75), (5.6, 2.0, 0.2), rounding=0.1), "root", STONE, k=0)
    sockets = []
    for i, x in enumerate((-3.6, 0.0, 3.6)):
        y = 0.6 if x == 0 else 0.1
        h = 3.8 if x == 0 else 3.2
        st.add(box((x, y, 0.9 + h * 0.5), (0.55, 0.55, h * 0.5), (0, 0, 45), rounding=0.1).displace(0.03, 1.2, 2, i),
               "root", STONE_L, k=0)
        st.add(cone((x, y, 0.9 + h + 0.35), 0.75, 0.45, 0.35, rounding=0.05), "root", STONE, k=0.05)
        bowl = sphere((x, y, 0.9 + h + 1.05), 0.55)
        st.carve(bowl, k=0.08, color=STONE_D)
        st.add(torus((x, y, 0.9 + h + 0.72), 0.62, 0.09), "root", BRASS, k=0.03)
        sockets.append((x, y, 0.9 + h + 1.05))
        st.paint(box((x, y - 0.5, 0.9 + h * 0.55), (0.1, 0.12, h * 0.3)), GLYPH, soft=0.04)
    ar = Shape("Arco", "stone", voxel=0.07, tris=1600, color_soft=0.15)
    outer = box((0, 2.2, 6.2), (6.0, 0.9, 6.2), rounding=0.2)
    lan_o = cylinder((-4.2, 2.2, 7.0), 10.2, 1.0, (90, 0, 0)).clip(cylinder((4.2, 2.2, 7.0), 10.2, 1.0, (90, 0, 0)))
    shape_o = outer.clip(lan_o.union(box((0, 2.2, 3.5), (6.0, 1.0, 3.5)), 0), 0)
    lan_i = cylinder((-2.6, 2.2, 6.4), 6.6, 1.5, (90, 0, 0)).clip(cylinder((2.6, 2.2, 6.4), 6.6, 1.5, (90, 0, 0)))
    opening = lan_i.union(box((0, 2.2, 3.0), (4.0, 1.5, 3.2)), 0)
    ar.add(shape_o.cut(opening, 0.05).displace(0.05, 0.6, 3, 8), "root", STONE_L, k=0)
    ar.paint(box((0, 1.25, 12.0), (0.6, 0.12, 0.6), (0, 45, 0)), GLYPH, soft=0.05)
    strata(ar, 0, 14, 1.3, (STONE_L, STONE_L, STONE), soft=0.2)
    gl = Shape("Glifos", "glow", voxel=0.04, tris=500)
    for i, (x, y, z) in enumerate(sockets):
        gl.add(torus((x, y, z - 0.95), 0.42, 0.04), "root", GLYPH, k=0)
    objs = build_parts({"Portao": ([st], [], None), "Arco": ([ar], [], None), "Glifos": ([gl], [], None)})
    objs += [empty(f"socket_{i}", s) for i, s in enumerate(sockets)]
    export("portao_vael", objs)


def cabeca_colosso():
    """Cabeça de Tolvaren, o colosso adormecido: elmo arredondado gasto, viseira com olhos
    de brasa, coroa de 5 espinhos, mandíbula e uma alcova na frente (onde a Pedra repousa)."""
    st = Shape("Cabeca", "stone", voxel=0.14, tris=4200, color_soft=0.35)
    st.add(ellipsoid((0, 1.0, 6.5), (7.2, 7.6, 7.0)).displace(0.18, 0.18, 3, 2), "root", STONE, k=0)
    st.add(ellipsoid((0, -4.6, 6.2), (5.6, 3.4, 4.8)), "root", STONE_L, k=1.8)          # face plate
    st.add(box((0, -6.0, 8.8), (5.8, 1.6, 0.8), (-8, 0, 0), rounding=0.6), "root", STONE_D, k=0.8)   # brow
    st.add(box((0, -7.4, 6.2), (0.9, 0.9, 2.6), rounding=0.5), "root", STONE_L, k=0.6)  # nose guard
    for sx in (1, -1):
        st.carve(ellipsoid((2.7 * sx, -7.2, 7.3), (2.0, 1.6, 1.25)), k=0.4, color=hexcol("5A3A33"))
        st.add(ellipsoid((5.8 * sx, -2.0, 4.6), (1.6, 4.0, 3.6)), "root", STONE_D, k=1.0)   # cheek guards
    for i, a in enumerate((-32, 0, 32)):
        r = math.radians(a)
        base = (math.sin(r) * 3.2, 1.6, 12.6)
        tip = (math.sin(r) * 5.0, 2.6, 19.5 if a == 0 else 17.0)
        st.add(round_cone(base, tip, 1.5, 0.15), "root", STONE_L, k=0.8)
    # alcove at the front (open mouth), relic sits inside at ground level
    st.carve(box((0, -6.2, 1.6), (1.9, 3.2, 1.7), rounding=0.7), k=0.4, color=hexcol("6E4A3E"))
    st.clip(plane((0, 0, 0.0), (0, 0, -1)))
    sand_drift(st, (0, 0.5, -0.4), (11.0, 10.0, 2.6))
    strata(st, 0.0, 18.0, 1.6, (STONE_L, STONE, STONE, STONE_D), soft=0.6)
    st.detail(ellipsoid((0, -6.0, 6.5), (6, 3, 4)), 0.6)
    gl = Shape("Brasas", "glow", voxel=0.08, tris=300)
    for sx in (1, -1):
        gl.add(ellipsoid((2.7 * sx, -6.8, 7.3), (1.25, 0.6, 0.75)), "root", EMBER, k=0)
    objs = build_parts({"Cabeca": ([st], [], None), "Brasas": ([gl], [], None)})
    export("cabeca_colosso", objs)


def mao_colosso():
    """Mão aberta do colosso, palma para cima na areia (a placa pesada fica na palma, a 1,1 m)."""
    st = Shape("Mao", "stone", voxel=0.08, tris=2200, color_soft=0.2)
    st.add(box((0, 0.6, 0.55), (2.6, 2.4, 0.55), rounding=0.45), "root", STONE, k=0)
    st.add(box((0, 3.6, 0.9), (2.2, 1.4, 0.9), rounding=0.6), "root", STONE_D, k=0.6)     # wrist
    for i, x in enumerate((-1.8, -0.6, 0.6, 1.8)):
        ln = (2.6, 3.1, 3.0, 2.4)[i]
        a = (x, -1.6, 0.7)
        b = (x * 1.08, -1.6 - ln * 0.6, 1.0)
        c = (x * 1.12, -1.6 - ln, 2.0)
        st.add(round_cone(a, b, 0.55, 0.48), "root", STONE_L, k=0.25)
        st.add(round_cone(b, c, 0.48, 0.38), "root", STONE_L, k=0.15)
    st.add(round_cone((2.7, 0.8, 0.7), (3.9, -0.6, 1.4), 0.6, 0.45), "root", STONE_L, k=0.3)   # thumb
    st.clip(plane((0, 0, 0.0), (0, 0, -1)))
    sand_drift(st, (0.0, 3.0, -0.2), (4.0, 3.0, 0.9))
    objs = build_parts({"Mao": ([st], [], None)})
    export("mao_colosso", objs)


def _crystal_cluster(name, specs, seed=1):
    bm = bmesh.new()
    for base, direction, length, radius, twist in specs:
        crystal_prism(bm, base, direction, length, radius, twist=twist)
    grad = lambda t: (0.25 + 0.75 * t, 0.55 + 0.45 * t, 0.0, 0.0)   # R: height light, G: glow mask
    return bm_object(name, bm, "crystal", (1, 1, 1), flat=True, gradient=grad)


def cristal():
    o = _crystal_cluster("Cristal", [
        ((0, 0, -0.5), (0.05, 0.02, 1), 16.0, 1.6, 0.0),
        ((1.6, 0.6, -0.5), (0.35, 0.15, 1), 9.0, 1.0, 0.4),
        ((-1.4, 0.9, -0.5), (-0.4, 0.2, 1), 7.0, 0.85, 0.2),
        ((0.4, -1.5, -0.5), (0.1, -0.45, 1), 5.5, 0.7, 0.8),
    ])
    base = Shape("Base", "stone", voxel=0.08, tris=500)
    base.add(ellipsoid((0, 0, -0.2), (3.0, 2.6, 0.9)).displace(0.15, 0.6, 2, 3), "root", STONE_D, k=0)
    objs = build_parts({"Base": ([base], [], None)}) + [o]
    export("cristal", objs)


def cristal_b():
    o = _crystal_cluster("CristalB", [
        ((0, 0, -0.5), (-0.25, 0.1, 1), 10.0, 1.2, 0.3),
        ((1.2, -0.4, -0.5), (0.5, -0.2, 1), 6.0, 0.8, 0.1),
        ((-0.6, 1.2, -0.5), (-0.1, 0.55, 1), 5.0, 0.7, 0.6),
    ])
    export("cristal_b", [o])


def geodo():
    """Geodo meio enterrado: casca de pedra aberta na frente, cristais por dentro."""
    st = Shape("Casca", "stone", voxel=0.06, tris=1600, color_soft=0.15)
    shell = sphere((0, 0, 1.2), 4.6).displace(0.12, 0.45, 2, 4).shell(0.35)
    st.add(shell, "root", STONE_D, k=0)
    st.clip(plane((0, 0, 0.0), (0, 0, -1)))
    st.carve(box((0, -4.2, 2.0), (1.8, 2.0, 1.9), rounding=0.8), k=0.4, color=CRY_A)
    st.paint(sphere((0, 0, 1.2), 4.4), CRY_A, soft=0.2)
    sand_drift(st, (0, 0, -0.3), (6.2, 6.2, 1.3))
    specs = []
    rng = np.random.default_rng(3)
    for i in range(14):
        a = rng.uniform(0, 2 * math.pi)
        e = rng.uniform(0.2, 1.2)
        n = (math.cos(a) * math.cos(e), math.sin(a) * math.cos(e), math.sin(e))
        base = (n[0] * 4.0, n[1] * 4.0, 1.2 + n[2] * 4.0)
        specs.append((base, (-n[0], -n[1], -n[2]), rng.uniform(1.2, 2.4), rng.uniform(0.25, 0.45), rng.uniform(0, 1)))
    o = _crystal_cluster("CristaisDentro", specs)
    objs = build_parts({"Casca": ([st], [], None)}) + [o]
    export("geodo", objs)


# ============================================================================= ruins
def _column(sh, c, h, r, broken=None, seed=0):
    x, y = c
    col = cylinder((x, y, h * 0.5), r, h * 0.5, rounding=0.05)
    for i in range(8):
        a = 2 * math.pi * i / 8
        col = col.cut(cylinder((x + math.cos(a) * r * 1.02, y + math.sin(a) * r * 1.02, h * 0.5), r * 0.16, h * 0.5), 0.02)
    col = col.displace(0.04, 0.9, 2, seed)
    if broken is not None:
        col = col.clip(plane((x, y, broken), (0.25, 0.18, 1.0)))
    sh.add(col, "root", STONE_L, k=0)
    sh.add(cylinder((x, y, 0.25), r * 1.35, 0.25, rounding=0.06), "root", STONE, k=0)
    if broken is None:
        sh.add(box((x, y, h + 0.25), (r * 1.4, r * 1.4, 0.25), rounding=0.06), "root", STONE, k=0)


def colunata():
    st = Shape("Colunata", "stone", voxel=0.06, tris=3200, color_soft=0.1)
    st.add(cylinder((0, 0, 0.3), 8.6, 0.3, rounding=0.1).displace(0.05, 0.5, 2, 1), "root", STONE_D, k=0)
    heights = [7.0, 7.0, 3.2, 7.0, 5.0, 7.0]
    for i in range(6):
        a = 2 * math.pi * i / 6 + 0.3
        c = (math.cos(a) * 7.0, math.sin(a) * 7.0)
        _column(st, c, 7.0 if heights[i] >= 7 else heights[i] + 0.8, 0.6, None if heights[i] >= 7 else heights[i], seed=i)
    for i0, i1 in ((0, 1), (3, 5)):
        a0 = 2 * math.pi * i0 / 6 + 0.3
        a1 = 2 * math.pi * (i1 if i1 != 5 else 5) / 6 + 0.3
        p0 = np.array([math.cos(a0) * 7.0, math.sin(a0) * 7.0, 7.85])
        p1 = np.array([math.cos(a1) * 7.0, math.sin(a1) * 7.0, 7.85])
        st.add(capsule(tuple(p0), tuple(p1), 0.5).displace(0.04, 0.9, 2, 9), "root", STONE, k=0)
    st.add(box((2.0, -3.0, 0.9), (1.4, 0.8, 0.6), (8, 0, 30), rounding=0.15), "root", STONE, k=0)   # fallen drum
    gl = Shape("Glifos", "glow", voxel=0.04, tris=300)
    gl.add(torus((0, 0, 0.62), 5.0, 0.07), "root", GLYPH, k=0)
    export("colunata", build_parts({"Colunata": ([st], [], None), "Glifos": ([gl], [], None)}))


def arco():
    st = Shape("Arco", "stone", voxel=0.06, tris=2400, color_soft=0.15)
    outer = box((0, 0, 6.0), (4.6, 0.9, 6.0), rounding=0.2)
    lancet_o = cylinder((-3.2, 0, 7.0), 7.8, 1.0, (90, 0, 0)).clip(cylinder((3.2, 0, 7.0), 7.8, 1.0, (90, 0, 0)))
    shape_o = outer.clip(lancet_o.union(box((0, 0, 3.5), (4.6, 1.0, 3.5)), 0), 0)
    lancet_i = cylinder((-1.9, 0, 6.2), 4.9, 1.5, (90, 0, 0)).clip(cylinder((1.9, 0, 6.2), 4.9, 1.5, (90, 0, 0)))
    opening = lancet_i.union(box((0, 0, 3.0), (3.0, 1.5, 3.2)), 0)
    shape = shape_o.cut(opening, 0.05).displace(0.06, 0.6, 3, 4)
    shape = shape.clip(plane((3.4, 0, 9.5), (0.6, 0, 1)).union(plane((0, 0, 30), (0, 0, 1)), 0), 0.1)    # broken corner
    st.add(shape, "root", STONE_L, k=0)
    for sx in (1, -1):
        st.add(box((3.9 * sx, 0, 0.35), (1.0, 1.2, 0.35), rounding=0.1), "root", STONE, k=0)
    st.paint(box((0, -0.92, 9.4), (0.45, 0.1, 0.45), (0, 45, 0)), GLYPH, soft=0.05)
    strata(st, 0, 12, 1.2, (STONE_L, STONE_L, STONE), soft=0.2)
    sand_drift(st, (2.0, -0.6, -0.2), (3.5, 2.2, 0.9))
    export("arco", build_parts({"Arco": ([st], [], None)}))


def pilar():
    st = Shape("Pilar", "stone", voxel=0.05, tris=1200, color_soft=0.1)
    shaft = box((0, 0, 4.0), (0.75, 0.75, 4.0), rounding=0.18).displace(0.05, 0.9, 2, 2)
    shaft = shaft.clip(plane((0, 0, 7.6), (0.3, -0.2, 1)))
    st.add(shaft, "root", STONE_L, k=0)
    st.add(box((0, 0, 0.35), (1.15, 1.15, 0.35), rounding=0.12), "root", STONE, k=0)
    st.add(torus((0, 0, 5.2), 0.82, 0.1), "root", BRASS, k=0.02)
    for i in range(4):
        st.paint(box((0, -0.78, 2.0 + i * 1.1), (0.25, 0.08, 0.18), (0, 0, 0)), GLYPH, soft=0.04)
    sand_drift(st, (0.4, 0.3, -0.2), (2.2, 2.0, 0.7))
    export("pilar", build_parts({"Pilar": ([st], [], None)}))


def rocha(name="rocha", seed=1, radii=(2.2, 1.7, 1.5)):
    st = Shape("Rocha", "stone", voxel=0.06, tris=900, color_soft=0.25)
    st.add(ellipsoid((0, 0, radii[2] * 0.55), radii).displace(min(radii) * 0.22, 0.55, 3, seed), "root", STONE, k=0)
    st.add(ellipsoid((radii[0] * 0.5, radii[1] * 0.2, radii[2] * 0.3), tuple(r * 0.6 for r in radii)).displace(0.2, 0.7, 2, seed + 3),
           "root", STONE_D, k=0.4)
    st.clip(plane((0, 0, -0.2), (0, 0, -1)))
    strata(st, -0.2, radii[2] * 2.2, 0.45, (STONE_L, STONE, STONE_D, STONE), soft=0.12)
    export(name, build_parts({"Rocha": ([st], [], None)}))


# ============================================================================= interactable skins
def totem():
    """Pedra-Guia (checkpoint): três lajes inclinadas em tripé e um cristal flutuando (glow)."""
    st = Shape("Lajes", "stone", voxel=0.03, tris=900, color_soft=0.06)
    for i in range(3):
        a = 2 * math.pi * i / 3 + math.pi / 2
        base = (math.cos(a) * 1.1, math.sin(a) * 1.1, 1.3)
        rot = (math.degrees(math.sin(a)) * 0.0 - 14 * math.sin(a), 14 * math.cos(a), math.degrees(a) + 90)
        st.add(box(base, (0.42, 0.14, 1.35), rot, rounding=0.08).displace(0.02, 1.5, 2, i), "root", STONE_L, k=0)
    st.add(cylinder((0, 0, 0.12), 1.6, 0.12, rounding=0.05), "root", STONE_D, k=0)
    bm = bmesh.new()
    crystal_prism(bm, (0, 0, 2.05), (0, 0, 1), 0.7, 0.24, tip=0.45)
    crystal_prism(bm, (0, 0, 2.05), (0, 0, -1), 0.45, 0.24, tip=0.6)
    gem = bm_object("Cristal", bm, "glow", (0.65, 1.0, 0.95, 0.0))
    export("totem", build_parts({"Lajes": ([st], [], None)}) + [gem])


def plate(heavy=False):
    r = 1.45 if heavy else 1.05
    st = Shape("Placa", "stone", voxel=0.025, tris=700, color_soft=0.05)
    st.add(cylinder((0, 0, 0.12), r, 0.12, rounding=0.04), "root", STONE_D if heavy else STONE, k=0)
    if heavy:
        st.add(torus((0, 0, 0.2), r - 0.08, 0.07), "root", BRASS, k=0.01)
    gl = Shape("Glifo", "glow", voxel=0.02, tris=300)
    gl.add(torus((0, 0, 0.245), r * 0.55, 0.045), "root", GLYPH, k=0)
    gl.add(cylinder((0, 0, 0.24), 0.12 if not heavy else 0.2, 0.012), "root", GLYPH, k=0)
    export("plate_heavy" if heavy else "plate", build_parts({"Placa": ([st], [], None), "Glifo": ([gl], [], None)}))


def gate():
    """Portão de pedra: moldura ("Frame", com colisão) e porta deslizante ("door").
    A porta afunda no chão ao abrir. Glifo do grupo na porta."""
    fr = Shape("Frame", "stone", voxel=0.04, tris=1100, color_soft=0.06)
    fr.add(box((-2.0, 0, 2.3), (0.45, 0.6, 2.3), rounding=0.08).displace(0.02, 1.2, 2, 1), "root", STONE, k=0)
    fr.add(box((2.0, 0, 2.3), (0.45, 0.6, 2.3), rounding=0.08).displace(0.02, 1.2, 2, 2), "root", STONE, k=0)
    fr.add(box((0, 0, 4.85), (2.6, 0.7, 0.35), rounding=0.08), "root", STONE_D, k=0)
    fr.add(cone((0, 0, 5.5), 0.6, 0.15, 0.4), "root", BRASS, k=0)
    dr = Shape("door", "stone", voxel=0.035, tris=600, color_soft=0.06)
    dr.add(box((0, 0, 2.2), (1.56, 0.28, 2.2), rounding=0.06), "root", STONE_L, k=0)
    dr.carve(torus((0, -0.29, 2.6), 0.6, 0.06, (90, 0, 0)), k=0.01, color=GLYPH)
    dr.paint(torus((0, -0.29, 2.6), 0.6, 0.08, (90, 0, 0)), GLYPH, soft=0.02)
    export("gate", build_parts({"Frame": ([fr], [], None), "door": ([dr], [], None)}))


def urna():
    """Urna-canhão de bronze: base ("Base", com colisão) e tampa ("lid") que salta ao disparar."""
    b = Shape("Base", "bronze", voxel=0.03, tris=1300, color_soft=0.05)
    body = ellipsoid((0, 0, 1.2), (1.0, 1.0, 1.05))
    body = body.union(cylinder((0, 0, 2.15), 0.62, 0.3, rounding=0.05), 0.25)
    body = body.cut(cylinder((0, 0, 2.35), 0.48, 0.5), 0.05)
    b.add(body, "root", BRASS, k=0)
    b.add(cylinder((0, 0, 0.18), 0.85, 0.18, rounding=0.05), "root", STONE_D, k=0)
    for i in range(4):
        a = 2 * math.pi * i / 4
        b.add(torus((math.cos(a) * 0.98, math.sin(a) * 0.98, 1.45), 0.2, 0.05, (90, 0, math.degrees(a) + 90)), "root", BRASS_D, k=0)
    b.paint(torus((0, 0, 1.2), 1.0, 0.09), GLYPH, soft=0.03)
    lid = Shape("lid", "bronze", voxel=0.025, tris=400)
    lid.add(cylinder((0, 0, 2.5), 0.56, 0.08, rounding=0.03), "root", BRASS_D, k=0)
    lid.add(sphere((0, 0, 2.68), 0.14), "root", BRASS, k=0.05)
    export("urna", build_parts({"Base": ([b], [], None), "lid": ([lid], [], (0, 0, 2.5))}))


def tambor():
    """Tambor de bronze (trampolim): corpo de bronze + membrana (material 'jelly', que quica)."""
    b = Shape("Corpo", "bronze", voxel=0.025, tris=900, color_soft=0.05)
    b.add(cylinder((0, 0, 0.45), 1.3, 0.45, rounding=0.08), "root", BRASS, k=0)
    b.carve(cylinder((0, 0, 0.95), 1.12, 0.2), k=0.02)
    for i in range(10):
        a = 2 * math.pi * i / 10
        b.add(capsule((math.cos(a) * 1.31, math.sin(a) * 1.31, 0.15), (math.cos(a + 0.3) * 1.31, math.sin(a + 0.3) * 1.31, 0.8), 0.04), "root", BRASS_D, k=0)
    m = Shape("Membrana", "jelly", voxel=0.02, tris=500)
    m.add(cylinder((0, 0, 0.84), 1.14, 0.045, rounding=0.02), "root", hexcol("F2E3C8"), k=0)
    m.paint(torus((0, 0, 0.89), 0.7, 0.05), GLYPH, soft=0.03, emission=1.0)
    export("tambor", build_parts({"Corpo": ([b], [], None), "Membrana": ([m], [], None)}))


def fenda():
    """Fenda (rift): anel recortado de lascas de cristal ao redor do disco (o disco é do jogo)."""
    bm = bmesh.new()
    rng = np.random.default_rng(7)
    for i in range(11):
        a = 2 * math.pi * i / 11 + rng.uniform(-0.1, 0.1)
        r = 1.55 + rng.uniform(-0.1, 0.15)
        base = (math.cos(a) * r, 0.0, 1.9 + math.sin(a) * r)
        d = (math.cos(a), rng.uniform(-0.2, 0.2), math.sin(a))
        crystal_prism(bm, base, d, rng.uniform(0.5, 1.0), rng.uniform(0.12, 0.2), sides=5, tip=0.5, twist=rng.uniform(0, 1))
    o = bm_object("Lascas", bm, "crystal", (1, 1, 1), flat=True, gradient=lambda t: (0.6 + 0.4 * t, 1.0, 0.0, 0.0))
    st = Shape("Base", "stone", voxel=0.03, tris=400)
    st.add(cylinder((0, 0, 0.15), 1.0, 0.15, rounding=0.05), "root", STONE_D, k=0)
    export("portal", build_parts({"Base": ([st], [], None)}) + [o])


def pedra_hora():
    """Pedra das Horas (relíquia): gema octaédrica alongada, facetada (sem anéis cruzados)."""
    bm = bmesh.new()
    crystal_prism(bm, (0, 0, 0.55), (0, 0, 1), 0.55, 0.28, sides=6, tip=0.55)
    crystal_prism(bm, (0, 0, 0.55), (0, 0, -1), 0.45, 0.28, sides=6, tip=0.7)
    o = bm_object("Gema", bm, "glow", (1.0, 0.95, 0.85, 0.0))
    export("relic", [o])


PROPS = {
    "agulha": agulha, "portao_vael": portao_vael, "cabeca_colosso": cabeca_colosso, "mao_colosso": mao_colosso,
    "cristal": cristal, "cristal_b": cristal_b, "geodo": geodo, "colunata": colunata, "arco": arco, "pilar": pilar,
    "rocha": lambda: rocha("rocha", 1, (2.2, 1.7, 1.5)), "rocha_b": lambda: rocha("rocha_b", 4, (1.6, 2.4, 2.4)),
    "totem": totem, "plate": lambda: plate(False), "plate_heavy": lambda: plate(True), "gate": gate,
    "urna": urna, "tambor": tambor, "portal": fenda, "relic": pedra_hora,
}


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = argv[argv.index("--only") + 1].split(",") if "--only" in argv else list(PROPS)
    for name in only:
        reset_scene()
        log("prop", name)
        PROPS[name]()


if __name__ == "__main__":
    main()
