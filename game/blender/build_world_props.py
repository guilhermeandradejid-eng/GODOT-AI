"""build_world_props.py — props do mundo de Ylvaar, modelados por SDF (sdfkit) e bmesh.

    blender -b --factory-startup --python game/blender/build_world_props.py [-- --only agulha,arco]
        [--out /tmp/prev_props --lift]      (prévias: outra pasta, itens apoiados no chão)

Saída: game/assets/props/<nome>.glb. Convenção: Blender Z-up; a FRENTE do prop é -Y
do Blender (= +Z do Godot, para onde a rotação "rot" da receita aponta). Origem no
chão, no centro da base (itens de mão: origem na empunhadura, ver item_*). Materiais
pelo nome (PropLib troca pelos shaders do jogo): stone, wood, bronze, cloth, nacre, glow,
crystal, seam, jelly.

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
from sdfkit import project as sdfkit_project  # noqa: E402
from sdfkit import (Shape, box, look_basis, ribbon, capsule, cone, cylinder, ellipsoid, hexcol, plane, round_cone,  # noqa: E402
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


def despike(obj, shapes) -> int:
    """A decimação (collapse) às vezes joga um vértice longe da superfície em peças
    finas (garras, hastes). Devolve esses vértices para a média dos vizinhos e depois
    para a superfície exata do SDF. Só vale para objetos feitos só de `shapes`."""
    me = obj.data
    n = len(me.vertices)
    co = np.empty(n * 3, np.float64)
    me.vertices.foreach_get("co", co)
    V = co.reshape(-1, 3)

    def field(P):
        return np.min([sh.field(P) for sh in shapes], axis=0)
    tol = 2.5 * max(sh.voxel for sh in shapes)
    bad = np.abs(field(V)) > tol
    if not bad.any():
        return 0
    ev = np.empty(len(me.edges) * 2, np.int64)
    me.edges.foreach_get("vertices", ev)
    ev = ev.reshape(-1, 2)
    for _ in range(4):
        acc = np.zeros((n, 3))
        cnt = np.zeros(n)
        good = ~bad
        for a, b in ((0, 1), (1, 0)):
            m = good[ev[:, b]]
            np.add.at(acc, ev[m, a], V[ev[m, b]])
            np.add.at(cnt, ev[m, a], 1)
        fix = bad & (cnt > 0)
        V[fix] = acc[fix] / cnt[fix][:, None]
        V[fix] = sdfkit_project(field, V[fix], min(sh.voxel for sh in shapes), 8)
        bad = np.abs(field(V)) > tol
        if not bad.any():
            break
    me.vertices.foreach_set("co", V.astype(np.float32).ravel())
    me.update()
    return int(fix.sum())


def build_parts(parts: dict, ao=True):
    """parts = {nome_do_objeto: ([shapes], [extras], pivot_or_None)} -> objetos Blender."""
    objs = []
    for name, (shapes, extras, pivot) in parts.items():
        o = sdfprop.build_prop(name, shapes, extras, ao=ao) if shapes else None
        if o is not None and not extras:
            k = despike(o, shapes)
            if k:
                log(f"  {name}: {k} vértices fora da superfície corrigidos")
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


LIFT = False      # --lift (só para prévias): apoia o prop no chão (itens de mão têm origem na empunhadura)


def export(name: str, objs) -> None:
    if LIFT:
        zmin = min(min(v.co.z for v in o.data.vertices) for o in objs if o.type == "MESH")
        recenter(objs, (0, 0, zmin))
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


# ============================================================================= itens e travas (itens.md 8.4)
# Itens de mão (item_*): origem na EMPUNHADURA (onde a mão/osso segura), eixo longo em
# +Z do Blender (= +Y do Godot), frente em -Y. Peças separadas por nome para o jogo
# poder esconder/acender partes (ex.: "Rolo" do arpéu, "Vidro" da lanterna).
ROPE = hexcol("A3543C")
ROPE_D = hexcol("7A3A2A")
WOOD_L = hexcol("DCA862")
WOOD = hexcol("C38C4E")
WOOD_D = hexcol("8A5E34")
LEATHER = hexcol("6B4330")
INDIGO = hexcol("2B3A87")
INDIGO_D = hexcol("1E2A66")
AMBER = hexcol("FFB45A")
AMBER_HOT = hexcol("FFE7B0")
CYAN = hexcol("4FE3D6")
NACRE = hexcol("F9D6C4")
NACRE_L = hexcol("FFEFE4")
NACRE_D = hexcol("E39C8E")
BRONZE = hexcol("B9813F")
SAILCLOTH = hexcol("F3E6CC")


def recenter(objs, pivot) -> None:
    """Move a geometria (e os empties) para a origem ficar em `pivot` (empunhadura)."""
    m = Matrix.Translation(-Vector(pivot))
    for o in objs:
        if o.type == "MESH":
            o.data.transform(m)
        else:
            o.location = o.location - Vector(pivot)


def helix(c, radius, z0, z1, turns, n_per_turn=18, phase=0.0):
    """Pontos de uma hélice em volta do Z (rolo de corda)."""
    n = max(2, int(turns * n_per_turn))
    pts = []
    for i in range(n + 1):
        t = i / n
        a = phase + 2 * math.pi * turns * t
        pts.append((c[0] + math.cos(a) * radius, c[1] + math.sin(a) * radius, z0 + (z1 - z0) * t))
    return pts


def item_arpeu():
    """Arpéu de Rumo (0,30 m): haste de latão com três garras curvas (pontas voltadas
    para a corda) e um rolo de corda de vela com 4 voltas em volta da haste.
    Empunhadura = centro do rolo (origem). Peças: "Garras" (latão), "Rolo" (corda),
    "Conta" (glow ciano); "hook_point" = coroa (ponta que prende)."""
    br = Shape("Garras", "bronze", voxel=0.002, tris=2600, color_soft=0.003)
    br.add(round_cone((0, 0, -0.045), (0, 0, 0.2), 0.0105, 0.0125), "root", BRASS, k=0)
    br.add(torus((0, 0, -0.06), 0.015, 0.005, (90, 0, 0)), "root", BRASS_D, k=0.002)         # olhal da corda
    br.add(sphere((0, 0, 0.212), 0.02), "root", BRASS, k=0.006)                               # coroa
    br.add(cylinder((0, 0, 0.178), 0.0155, 0.0055, rounding=0.002), "root", BRASS_D, k=0.002) # anéis da haste
    br.add(cylinder((0, 0, 0.05), 0.0135, 0.004, rounding=0.0015), "root", BRASS_D, k=0.002)
    for i in range(3):
        a = 2 * math.pi * i / 3 + math.pi / 2
        ca, sa = math.cos(a), math.sin(a)
        prof = [(0.0, 0.212), (0.04, 0.232), (0.074, 0.218), (0.093, 0.186), (0.094, 0.152), (0.082, 0.124)]
        pts = [(ca * r, sa * r, z) for r, z in prof]
        br.add(blade(pts, [0.0125, 0.0118, 0.0108, 0.0094, 0.0072, 0.0026], flat=0.7, normal=(-sa, ca, 0), k=0.004),
               "root", BRASS, k=0.005)
        br.add(round_cone((ca * 0.086, sa * 0.086, 0.13), (ca * 0.074, sa * 0.074, 0.139), 0.005, 0.0015),
               "root", BRASS, k=0.002)                                                        # farpa
        br.paint(sphere((ca * 0.083, sa * 0.083, 0.13), 0.02), hexcol("F6DD8E"), soft=0.012)   # pontas gastas, claras
    br.paint(cylinder((0, 0, 0.12), 0.02, 0.035), hexcol("B8892F"), soft=0.004)
    br.detail(sphere((0, 0, 0.19), 0.1), 0.8)
    rope = Shape("Rolo", "cloth", voxel=0.002, tris=2000, color_soft=0.003)
    pts = helix((0, 0), 0.027, -0.038, 0.036, 4.0, 22)
    rope.add(tube(pts, 0.0108, k=0.002), "root", ROPE, k=0)
    rope.add(tube([pts[0], (0.03, -0.005, -0.055), (0.012, -0.012, -0.064), (0.0, 0.0, -0.06)], 0.008, k=0.003),
             "root", ROPE, k=0.003)                                                           # ponta amarrada no olhal
    for k in range(5):                                                                        # fios trançados (listras)
        rope.paint(tube(helix((0, 0), 0.027, -0.038 + k * 0.004, 0.036 + k * 0.004, 4.0, 22), 0.0045), ROPE_D, soft=0.002)
    gl = Shape("Conta", "glow", voxel=0.0015, tris=200)
    gl.add(sphere((0, 0, 0.236), 0.0085), "root", CYAN, k=0)
    objs = build_parts({"Garras": ([br], [], None), "Rolo": ([rope], [], None), "Conta": ([gl], [], None)})
    objs.append(empty("hook_point", (0, 0, 0.235)))
    export("item_arpeu", objs)


def item_bastao():
    """Bastão de Quilha (0,95 m): haste de madeira clara que se achata como uma quilha
    na parte de golpe, veios longitudinais, ponteira de latão, empunhadura de couro e 3
    anéis entalhados logo acima dela. Empunhadura = origem; ponta em +Z ("tip").
    Peças: "Haste" (madeira), "Ponteira" (latão), "Veio" (filete ciano, glow)."""
    wd = Shape("Haste", "wood", voxel=0.0028, tris=2600, color_soft=0.004)
    wd.add(round_cone((0, 0, -0.135), (0, 0, 0.3), 0.0215, 0.0235), "root", WOOD, k=0)
    keel = blade([(0, 0, 0.25), (0, 0, 0.4), (0, 0, 0.56), (0, 0, 0.7), (0, 0, 0.765)],
                 [0.024, 0.035, 0.041, 0.035, 0.026], flat=0.6, normal=(1, 0, 0), k=0.01)
    wd.add(keel, "root", WOOD_L, k=0.025)
    for z in (0.088, 0.116, 0.144):                                                           # 3 anéis entalhados
        wd.carve(torus((0, 0, z), 0.0235, 0.0038), k=0.0015, color=WOOD_D)
    wd.add(round_cone((0, 0, -0.072), (0, 0, 0.066), 0.0243, 0.0243), "root", LEATHER, k=0.002)   # couro
    for i in range(7):                                                                        # tiras do couro
        z = -0.064 + i * 0.0195
        wd.paint(torus((0, 0, z), 0.0246, 0.0024, (8, 0, 0)), hexcol("4E2F22"), soft=0.002)
    for i in range(12):                                                                       # veios da quilha
        a = 2 * math.pi * i / 12 + 0.2
        rr = 0.024 if i % 3 else 0.03
        wd.paint(box((math.cos(a) * rr, math.sin(a) * rr, 0.42), (0.0022, 0.0022, 0.33), (0, 0, math.degrees(a))),
                 WOOD_D if i % 2 else hexcol("B48A57"), soft=0.004)
    wd.detail(box((0, 0, 0.1), (0.035, 0.035, 0.08)), 0.8)
    br = Shape("Ponteira", "bronze", voxel=0.0026, tris=900, color_soft=0.003)
    br.add(cone((0, 0, 0.782), 0.03, 0.022, 0.026, rounding=0.003), "root", BRASS, k=0)
    br.add(sphere((0, 0, 0.82), 0.025), "root", BRASS, k=0.008)
    br.add(torus((0, 0, 0.758), 0.029, 0.0045), "root", BRASS_D, k=0.002)
    br.add(cylinder((0, 0, 0.262), 0.026, 0.008, rounding=0.003), "root", BRASS_D, k=0)         # colar da quilha
    br.add(cylinder((0, 0, -0.142), 0.0235, 0.009, rounding=0.003), "root", BRASS_D, k=0)       # tampa do cabo
    gl = Shape("Veio", "glow", voxel=0.0016, tris=400)
    for sx in (1, -1):                                                                        # quilha "afinada": filete ciano
        gl.add(blade([(sx * 0.0205, 0, 0.36), (sx * 0.0247, 0, 0.5), (sx * 0.0257, 0, 0.6), (sx * 0.0222, 0, 0.7)],
                     [0.003, 0.0042, 0.0042, 0.0026], flat=0.35, normal=(1, 0, 0)), "root", CYAN, k=0)
    objs = build_parts({"Haste": ([wd], [], None), "Ponteira": ([br], [], None), "Veio": ([gl], [], None)})
    objs.append(empty("tip", (0, 0, 0.84)))
    export("item_bastao", objs)


def item_lanterna():
    """Lanterna de Brasa (0,22 m): gaiola de latão de 4 hastes, vidro âmbar (glow, com o
    núcleo quente mais claro no centro) e alça de arco. Origem = topo da alça (pendura
    em belt_L/grip_L); o corpo fica abaixo (-Z). Peças: "Gaiola" (latão), "Vidro" (glow)."""
    H = 0.22
    cg = Shape("Gaiola", "bronze", voxel=0.0018, tris=1800, color_soft=0.003)
    cg.add(cylinder((0, 0, 0.009), 0.05, 0.009, rounding=0.003), "root", BRASS_D, k=0)          # base
    cg.add(cylinder((0, 0, -0.001), 0.04, 0.004, rounding=0.0015), "root", BRASS_D, k=0.002)    # pé
    cg.add(torus((0, 0, 0.02), 0.047, 0.004), "root", BRASS, k=0.002)
    cg.add(cylinder((0, 0, 0.128), 0.047, 0.006, rounding=0.002), "root", BRASS, k=0)           # aro do teto
    cg.add(cone((0, 0, 0.148), 0.046, 0.016, 0.016, rounding=0.003), "root", BRASS_D, k=0.003)  # telhado
    cg.add(sphere((0, 0, 0.168), 0.011), "root", BRASS, k=0.004)                                # pináculo
    for i in range(4):                                                                         # 4 hastes da gaiola
        a = 2 * math.pi * i / 4 + math.pi / 4
        c, s = math.cos(a), math.sin(a)
        cg.add(tube([(c * 0.048, s * 0.048, 0.018), (c * 0.054, s * 0.054, 0.07), (c * 0.048, s * 0.048, 0.126)],
                    [0.0042, 0.0046, 0.0042], k=0.002), "root", BRASS, k=0.002)
    # alça de arco: meia-volta de toro no plano XZ, presa nos lados do pináculo
    arc = torus((0, 0, 0.17), 0.042, 0.0038, (90, 0, 0)).clip(plane((0, 0, 0.168), (0, 0, -1)))
    cg.add(arc, "root", BRASS, k=0.002)
    for sx in (1, -1):
        cg.add(sphere((sx * 0.042, 0, 0.168), 0.0062), "root", BRASS_D, k=0.002)
    cg.detail(sphere((0, 0, 0.17), 0.05), 0.6)
    gl = Shape("Vidro", "glow", voxel=0.0018, tris=700, color_soft=0.01)
    gl.add(cylinder((0, 0, 0.073), 0.041, 0.05, rounding=0.016), "root", AMBER, k=0)
    gl.paint(ellipsoid((0, 0, 0.07), (0.034, 0.034, 0.044)), AMBER_HOT, soft=0.03)              # núcleo quente
    objs = build_parts({"Gaiola": ([cg], [], None), "Vidro": ([gl], [], None)})
    objs.append(empty("light", (0, 0, 0.075)))
    recenter(objs, (0, 0, 0.212))
    export("item_lanterna", objs)


def item_concha():
    """Concha dos Ventos (0,24 m): espiral cônica de nácar rosado com 3 voltas (raio do
    tubo cresce em progressão geométrica), espinhos no ombro, boca aberta em sino com
    lábio claro e bocal de latão no ápice (+Z). Origem = meio do corpo."""
    sh = Shape("Concha", "nacre", voxel=0.0018, tris=3000, color_soft=0.004)
    turns, r0, r1 = 3.0, 0.0045, 0.03
    kk = math.log(r1 / r0) / (2 * math.pi * turns)
    pts, rads, outs = [], [], []
    n = 60
    for i in range(n + 1):
        th = 2 * math.pi * turns * i / n
        r = r0 * math.exp(kk * th)
        R = 0.95 * r
        z = 0.112 - (r - r0) / (math.pi * kk) * 1.1
        pts.append(np.array([math.cos(th) * R, -math.sin(th) * R, z]))     # gira para a boca abrir na frente (-Y)
        rads.append(r)
        outs.append(np.array([math.cos(th), -math.sin(th), 0.0]))
    sh.add(tube([tuple(p) for p in pts], rads, k=0.004), "root", NACRE, k=0)
    # boca em sino: continua a última volta pela tangente, abrindo e descendo
    end = pts[-1]
    d = pts[-1] - pts[-3]
    d = d / np.linalg.norm(d) + np.array([0, 0, -0.35])
    d = d / np.linalg.norm(d)
    bell = [end, end + d * 0.022, end + d * 0.04, end + d * 0.052]
    br_r = [r1, r1 * 1.15, r1 * 1.5, r1 * 1.9]
    sh.add(tube([tuple(p) for p in bell], br_r, k=0.004), "root", NACRE, k=0.004)
    sh.carve(tube([tuple(p) for p in [end - d * 0.01, end + d * 0.026, end + d * 0.045, end + d * 0.08]],
                  [r1 * 0.55, r1 * 1.0, r1 * 1.38, r1 * 1.9]), k=0.003, color=hexcol("FFB8AE"))
    lip = end + d * 0.05
    sh.add(torus(tuple(lip), r1 * 1.82, 0.0042, look_basis(tuple(d))), "root", NACRE_L, k=0.003)   # lábio claro
    # canal (sifão) descendo do corpo
    sh.add(round_cone(tuple(end + np.array([0.012, 0.0, -0.01])), tuple(end + np.array([0.01, -0.006, -0.06])), 0.016, 0.006),
           "root", NACRE, k=0.012)
    # espinhos no ombro de cada volta
    for i in range(14, n - 2, 6):
        t = i / n
        p, r, o = pts[i], rads[i], outs[i]
        base = p + o * r * 0.6 + np.array([0, 0, r * 0.6])
        tip = base + o * (0.004 + 0.014 * t) + np.array([0, 0, 0.006 + 0.008 * t])
        sh.add(round_cone(tuple(base), tuple(tip), r * 0.38, 0.0015), "root", NACRE_L, k=0.003)
    # faixas espirais coral e linha da sutura
    stripe = [tuple(p + o * r * 0.98) for p, r, o in zip(pts, rads, outs)]
    sh.paint(tube(stripe[6:], [r * 0.2 for r in rads[6:]]), NACRE_D, soft=0.004)
    suture = [tuple(p + o * r * 0.55 + np.array([0, 0, r * 0.85])) for p, r, o in zip(pts, rads, outs)]
    sh.paint(tube(suture[4:], [r * 0.12 for r in rads[4:]]), hexcol("C98A86"), soft=0.003)
    sh.detail(sphere(tuple(end + d * 0.03), 0.06), 0.8)
    br = Shape("Bocal", "bronze", voxel=0.0016, tris=700, color_soft=0.003)
    br.add(cylinder((0, 0, 0.122), 0.0068, 0.012, rounding=0.002), "root", BRASS, k=0)
    br.add(cone((0, 0, 0.14), 0.0075, 0.0115, 0.006, rounding=0.002), "root", BRASS, k=0.002)
    br.add(torus((0, 0, 0.111), 0.0075, 0.0026), "root", BRASS_D, k=0.002)
    br.carve(cylinder((0, 0, 0.146), 0.0055, 0.006), k=0.001, color=hexcol("4A3418"))
    objs = build_parts({"Concha": ([sh], [], None), "Bocal": ([br], [], None)})
    objs.append(empty("mouth", (0, 0, 0.146)))
    export("item_concha", objs)


def relicario():
    """Relicário de Ferramenta (0,9 m): pedestal de arenito em degraus, glifos ciano,
    pano índigo caído na frente e atrás e aro de latão no topo (o item flutua a 1,0 m)."""
    st = Shape("Pedestal", "stone", voxel=0.01, tris=2400, color_soft=0.03)
    st.add(box((0, 0, 0.07), (0.4, 0.4, 0.07), rounding=0.03).displace(0.006, 6.0, 2, 3), "root", STONE_D, k=0)
    st.add(box((0, 0, 0.18), (0.31, 0.31, 0.05), rounding=0.025), "root", STONE, k=0)
    st.add(box((0, 0, 0.49), (0.17, 0.17, 0.3), rounding=0.03).displace(0.005, 5.0, 2, 4), "root", STONE_L, k=0.02)
    st.add(cone((0, 0, 0.79), 0.2, 0.32, 0.05, rounding=0.02), "root", STONE, k=0.02)
    st.add(cylinder((0, 0, 0.855), 0.33, 0.025, rounding=0.012), "root", STONE_L, k=0.01)
    st.carve(sphere((0, 0, 1.12), 0.26), k=0.02, color=STONE_D)                                # concavidade do topo
    strata(st, 0.0, 0.9, 0.09, (STONE_L, STONE, STONE_L), soft=0.03)
    for sy in (1, -1):                                                                          # glifos nas faces frente/trás
        st.paint(box((0, sy * 0.17, 0.52), (0.018, 0.03, 0.13)), GLYPH, soft=0.01)
        st.paint(box((0, sy * 0.17, 0.36), (0.06, 0.03, 0.01)), GLYPH, soft=0.01)
        st.detail(box((0, sy * 0.17, 0.48), (0.08, 0.04, 0.2)), 0.9)
    sand_drift(st, (0.12, 0.08, -0.04), (0.55, 0.48, 0.1))
    br = Shape("Aro", "bronze", voxel=0.008, tris=500)
    br.add(torus((0, 0, 0.88), 0.315, 0.017), "root", BRASS, k=0)
    for i in range(4):
        a = 2 * math.pi * i / 4 + math.pi / 4
        br.add(sphere((math.cos(a) * 0.315, math.sin(a) * 0.315, 0.885), 0.026), "root", BRASS_D, k=0.004)
    cl = Shape("Pano", "cloth", voxel=0.006, tris=1400, color_soft=0.01)
    cl.add(box((0, 0, 0.9), (0.13, 0.338, 0.009), rounding=0.008).displace(0.002, 20.0, 2, 7), "root", INDIGO, k=0)
    for sy in (1, -1):                                                                          # abas frente/trás
        pts = [(0, sy * 0.338, 0.905), (0, sy * 0.35, 0.8), (0, sy * 0.342, 0.7), (0, sy * 0.33, 0.6)]
        cl.add(ribbon(pts, [0.26, 0.25, 0.2, 0.05], 0.007, up=(0, 1, 0)).displace(0.003, 22.0, 2, 5 if sy > 0 else 6),
               "root", INDIGO, k=0.01)
        cl.paint(box((0, sy * 0.345, 0.715), (0.2, 0.03, 0.012)), BRASS, soft=0.008)              # barra bordada
        cl.add(sphere((0, sy * 0.33, 0.585), 0.018), "root", BRASS, k=0.004)                       # pingente
    cl.paint(box((0, 0, 0.91), (0.09, 0.2, 0.02)), INDIGO_D, soft=0.04)
    cl.detail(box((0, 0, 0.75), (0.2, 0.4, 0.2)), 0.5)
    objs = build_parts({"Pedestal": ([st], [], None), "Aro": ([br], [], None), "Pano": ([cl], [], None)})
    objs.append(empty("item", (0, 0, 1.0)))
    export("relicario", objs)


def argola():
    """Argola (1,1 m de Ø): aro de latão vertical (plano XZ do Blender) com cintas, uma
    presilha no topo e 3 contas de vidro ciano (peça "Contas", glow 0,25 -> 1,0) das
    quais pendem 3 bandeirolas de pano de vela. Origem = centro do aro (ponto do arpéu)."""
    R = 0.5
    br = Shape("Aro", "bronze", voxel=0.006, tris=1600, color_soft=0.008)
    br.add(torus((0, 0, 0), R, 0.042, (90, 0, 0)), "root", BRASS, k=0)
    for a in (20, 160, 60, 120):                                                                # cintas
        r = math.radians(a)
        br.add(torus((math.cos(r) * R, 0, math.sin(r) * R), 0.05, 0.012, (0, -a, 0)), "root", BRASS_D, k=0.004)
    br.add(cylinder((0, 0, R + 0.06), 0.035, 0.05, rounding=0.012), "root", BRASS_D, k=0.01)      # presilha
    br.add(torus((0, 0, R + 0.14), 0.04, 0.012, (90, 0, 0)), "root", BRASS, k=0.004)
    br.paint(torus((0, 0, 0), R, 0.05, (90, 0, 0)).clip(plane((0, 0, -0.1), (0, 0, 1))), hexcol("E8BC55"), soft=0.08)
    gl = Shape("Contas", "glow", voxel=0.004, tris=600)
    cl = Shape("Bandeirolas", "cloth", voxel=0.005, tris=1300, color_soft=0.01)
    for i, a in enumerate((-90, -135, -45)):
        r = math.radians(a)
        p = np.array([math.cos(r) * R, 0, math.sin(r) * R])
        gl.add(ellipsoid(tuple(p), (0.062, 0.062, 0.062)), "root", CYAN, k=0)
        ln = 0.5 if a == -90 else 0.38
        top = p + np.array([0, 0, -0.05])
        sway = 0.04 * (1 if i % 2 else -1)
        pts = [tuple(top), tuple(top + np.array([sway * 0.3, 0.01, -ln * 0.35])),
               tuple(top + np.array([sway, 0.0, -ln * 0.7])), tuple(top + np.array([sway * 1.4, -0.01, -ln]))]
        cl.add(blade(pts, [0.06, 0.08, 0.068, 0.014], flat=0.1, normal=(0, 1, 0), k=0.01)
               .displace(0.004, 14.0, 2, 10 + i), "root", SAILCLOTH, k=0)
        cl.paint(box(tuple(top + np.array([0, 0, -ln * 0.55])), (0.2, 0.2, 0.025)), ROPE, soft=0.012)   # faixa
    objs = build_parts({"Aro": ([br], [], None), "Contas": ([gl], [], None), "Bandeirolas": ([cl], [], None)})
    export("argola", objs)


def aro_puxar():
    """Aro de puxar (0,6 m): placa índigo vertical (frente -Y) com rebites e glifo, um
    olhal e 2 elos de corrente segurando um aro grosso de latão. Origem = centro do
    verso da placa (encosta no objeto); "grab" = centro do aro."""
    pl = Shape("Placa", "stone", voxel=0.005, tris=2400, color_soft=0.01)
    pl.add(box((0, -0.03, 0.0), (0.21, 0.03, 0.21), rounding=0.02), "root", INDIGO, k=0)
    pl.add(box((0, -0.064, 0.0), (0.17, 0.006, 0.17), rounding=0.006), "root", INDIGO_D, k=0.004)
    pl.paint(torus((0, -0.07, -0.02), 0.13, 0.009, (90, 0, 0)), GLYPH, soft=0.008)               # glifo em volta do aro
    pl.detail(torus((0, -0.07, -0.02), 0.13, 0.03, (90, 0, 0)), 1.0)
    br = Shape("Aro", "bronze", voxel=0.0045, tris=1500, color_soft=0.006)
    frame = box((0, -0.035, 0.0), (0.226, 0.032, 0.226), rounding=0.012).cut(box((0, -0.07, 0.0), (0.19, 0.05, 0.19)), 0.004)
    br.add(frame, "root", BRASS_D, k=0)                                                         # moldura
    for sx in (1, -1):
        for sz in (1, -1):
            br.add(sphere((sx * 0.172, -0.064, sz * 0.172), 0.016), "root", BRASS, k=0.003)        # rebites
    br.add(torus((0, -0.07, 0.1), 0.03, 0.011, (90, 0, 90)), "root", BRASS_D, k=0.004)           # olhal (plano YZ)
    br.add(cylinder((0, -0.066, 0.1), 0.034, 0.006, (90, 0, 0), rounding=0.004), "root", BRASS_D, k=0.004)
    br.add(torus((0, -0.098, 0.05), 0.034, 0.009, (90, 0, 0)), "root", BRASS_D, k=0)             # elo 1 (XZ)
    br.add(torus((0, -0.098, -0.004), 0.034, 0.009, (90, 0, 90)), "root", BRASS_D, k=0)          # elo 2 (YZ)
    br.add(torus((0, -0.098, -0.165), 0.12, 0.024, (90, 0, 0)), "root", BRASS, k=0)              # aro grosso
    br.paint(torus((0, -0.098, -0.165), 0.12, 0.03, (90, 0, 0)).clip(plane((0, 0, -0.2), (0, 0, 1))), hexcol("EBC25E"),
             soft=0.03)                                                                          # gasto da mão
    objs = build_parts({"Placa": ([pl], [], None), "Aro": ([br], [], None)})
    objs.append(empty("grab", (0, -0.098, -0.165)))
    export("aro_puxar", objs)


def _tripod(sh, h, foot_r, col=BRONZE, thick=0.035):
    """Tripé de bronze: 3 pernas levemente arqueadas, pés de latão, cinta a 38% da
    altura (encostada nas pernas) e cabeça com anel e pináculo."""
    top = np.array([0.0, 0.0, h - 0.06])
    top_r = 0.07
    ring_z = h * 0.38

    def leg_r(z):
        return foot_r + (top_r - foot_r) * (z - 0.03) / (top[2] - 0.03)
    for i in range(3):
        a = 2 * math.pi * i / 3 + math.pi / 2
        o = np.array([math.cos(a), math.sin(a), 0.0])
        pts = []
        for t in np.linspace(0.0, 1.0, 6):
            z = 0.03 + (top[2] - 0.03) * t
            pts.append(tuple(o * (leg_r(z) + 0.05 * math.sin(math.pi * t)) + np.array([0, 0, z])))
        sh.add(tube(pts, list(np.linspace(thick * 1.1, thick * 0.8, 6)), k=0.01), "root", col, k=0.015)
        foot = o * foot_r + np.array([0, 0, 0.03])
        sh.add(round_cone(tuple(foot), tuple(foot + o * 0.06 + np.array([0, 0, -0.01])), thick * 1.45, thick * 1.05),
               "root", BRASS_D, k=0.01)
        knot = o * (leg_r(ring_z) + 0.05 * math.sin(math.pi * (ring_z - 0.03) / (top[2] - 0.03))) + np.array([0, 0, ring_z])
        sh.add(sphere(tuple(knot), thick * 1.35), "root", BRASS, k=0.01)
    rr = leg_r(ring_z) + 0.05 * math.sin(math.pi * (ring_z - 0.03) / (top[2] - 0.03))
    sh.add(torus((0, 0, ring_z), rr, thick * 0.45), "root", BRASS_D, k=0.008)
    sh.add(cylinder((0, 0, h), 0.09, 0.05, rounding=0.02), "root", BRASS, k=0.03)
    sh.add(torus((0, 0, h - 0.05), 0.11, 0.018), "root", BRASS_D, k=0.01)
    sh.add(cone((0, 0, h + 0.08), 0.05, 0.012, 0.04, rounding=0.008), "root", BRASS, k=0.01)


def sino_cristal():
    """Sino de Cristal (1,6 m): prisma lilás facetado (material de cristal de Kesrin)
    pendurado no ápice de um tripé de bronze. Origem no chão. Peça "Cristal"."""
    br = Shape("Tripe", "bronze", voxel=0.008, tris=1800, color_soft=0.01)
    _tripod(br, 1.62, 0.6)
    br.add(cylinder((0, 0, 1.49), 0.016, 0.07), "root", BRASS_D, k=0.01)                        # haste
    br.add(cone((0, 0, 1.395), 0.11, 0.05, 0.035, rounding=0.008), "root", BRASS, k=0.01)       # garra do cristal
    br.paint(torus((0, 0, 1.57), 0.091, 0.012), GLYPH, soft=0.01)
    bm = bmesh.new()
    crystal_prism(bm, (0, 0, 1.13), (0, 0, 1), 0.27, 0.15, sides=6, tip=0.25, twist=0.26)
    crystal_prism(bm, (0, 0, 1.13), (0, 0, -1), 0.66, 0.15, sides=6, tip=0.5, twist=0.26)
    crystal_prism(bm, (0.05, 0.04, 1.0), (0.4, 0.2, -1), 0.32, 0.06, sides=5, tip=0.5, twist=0.4)
    crystal_prism(bm, (-0.05, 0.02, 1.08), (-0.45, -0.15, -1), 0.26, 0.05, sides=5, tip=0.5, twist=0.1)
    gem = bm_object("Cristal", bm, "crystal", (1, 1, 1), flat=True,
                    gradient=lambda t: (0.2 + 0.8 * t, 0.45 + 0.55 * (1 - t), 0.0, 0.0))
    objs = build_parts({"Tripe": ([br], [], None)}) + [gem]
    export("sino_cristal", objs)


def cristal_eco():
    """Cristal-Eco (sino maior e mais escuro): prisma largo de lilás profundo num tripé
    mais robusto, com veios ciano (peça "Veios", glow) que racham quando ressoa."""
    br = Shape("Tripe", "bronze", voxel=0.01, tris=2000, color_soft=0.012)
    _tripod(br, 1.95, 0.78, col=BRASS_D, thick=0.048)
    br.add(cylinder((0, 0, 1.8), 0.02, 0.08), "root", BRASS_D, k=0.01)
    br.add(cone((0, 0, 1.69), 0.17, 0.07, 0.045, rounding=0.01), "root", BRASS_D, k=0.01)
    bm = bmesh.new()
    L_dn, L_up, r = 0.95, 0.3, 0.24
    zc = 1.36
    crystal_prism(bm, (0, 0, zc), (0, 0, 1), L_up, r, sides=6, tip=0.3, twist=0.0)
    crystal_prism(bm, (0, 0, zc), (0, 0, -1), L_dn, r, sides=6, tip=0.45, twist=0.0)
    crystal_prism(bm, (0.08, 0.05, 1.2), (0.45, 0.25, -1), 0.42, 0.08, sides=5, tip=0.5, twist=0.4)
    crystal_prism(bm, (-0.08, -0.02, 1.28), (-0.5, -0.1, -1), 0.36, 0.07, sides=5, tip=0.5, twist=0.1)
    crystal_prism(bm, (0.0, -0.09, 1.1), (0.05, -0.5, -1), 0.3, 0.06, sides=5, tip=0.5, twist=0.7)
    gem = bm_object("Cristal", bm, "crystal", (1, 1, 1), flat=True,
                    gradient=lambda t: (0.02 + 0.33 * t, 0.85, 0.0, 0.0))
    # veios: zigue-zagues sobre as faces do prisma (um pouco para fora da face)
    gl = Shape("Veios", "glow", voxel=0.004, tris=1400)
    body = L_dn * (1 - 0.45)
    rng = np.random.default_rng(11)
    for f in range(6):
        a = 2 * math.pi * (f + 0.5) / 6
        nx, ny = math.cos(a), math.sin(a)
        tx, ty = -ny, nx
        dist = r * math.cos(math.pi / 6) * 0.985 + 0.004
        pts = []
        steps = 6
        for s in range(steps + 1):
            z = zc + L_up * 0.5 - (L_up * 0.5 + body * 0.95) * s / steps
            w = rng.uniform(-0.6, 0.6) * r * 0.45
            rr = dist * (0.92 + 0.08 * (1 - abs(z - zc) / 0.6)) if z < zc else dist
            pts.append((nx * rr + tx * w, ny * rr + ty * w, z))
        gl.add(tube(pts, [0.006] + [0.0085] * (steps - 1) + [0.004], k=0.004), "root", CYAN, k=0.004)
    objs = build_parts({"Tripe": ([br], [], None), "Veios": ([gl], [], None)}) + [gem]
    export("cristal_eco", objs)


def cabeco(name="cabeco", H=3.0):
    """Cabeço do Cabo de Vidro: coluna de bronze canelada sobre base de arenito, com aro
    de latão no topo (plano XZ: o cabo passa por ele ao longo de Y). "cable" = centro do
    aro, a H m do chão (2,2 / 3,0 m)."""
    st = Shape("Base", "stone", voxel=0.012, tris=700, color_soft=0.02)
    st.add(box((0, 0, 0.12), (0.34, 0.34, 0.12), rounding=0.03).displace(0.008, 4.0, 2, 2), "root", STONE_D, k=0)
    st.add(cone((0, 0, 0.3), 0.3, 0.2, 0.08, rounding=0.02), "root", STONE, k=0.02)
    sand_drift(st, (0.08, 0.05, -0.05), (0.55, 0.5, 0.12))
    br = Shape("Coluna", "bronze", voxel=0.01, tris=1800, color_soft=0.012)
    col = cylinder((0, 0, (H - 0.1) * 0.5 + 0.2), 0.11, (H - 0.1) * 0.5 - 0.1, rounding=0.02)
    for i in range(8):
        a = 2 * math.pi * i / 8
        col = col.cut(cylinder((math.cos(a) * 0.118, math.sin(a) * 0.118, H * 0.5), 0.022, H * 0.4), 0.008)
    br.add(col, "root", BRONZE, k=0)
    br.add(cylinder((0, 0, 0.42), 0.15, 0.05, rounding=0.015), "root", BRASS_D, k=0.01)
    for z in (H * 0.45, H - 0.34):
        br.add(torus((0, 0, z), 0.12, 0.018), "root", BRASS_D, k=0.008)
    br.add(cone((0, 0, H - 0.2), 0.12, 0.07, 0.06, rounding=0.015), "root", BRASS_D, k=0.01)
    br.add(torus((0, 0, H), 0.17, 0.034, (90, 0, 0)), "root", BRASS, k=0.02)                      # aro do cabo
    br.add(sphere((0, 0, H + 0.2), 0.04), "root", BRASS, k=0.02)
    br.paint(box((0, -0.12, H * 0.62), (0.03, 0.03, 0.18)), GLYPH, soft=0.02)
    objs = build_parts({"Base": ([st], [], None), "Coluna": ([br], [], None)})
    objs.append(empty("cable", (0, 0, H)))
    export(name, objs)


def braseiro():
    """Braseiro (Olho de Brasa): tigela rasa de bronze com uma gema-tigela de vidro âmbar
    (peça "Gema", glow; o jogo a acende de 0 a 2,0). Serve no chão e no fundo do olho
    da cabeça do colosso. Origem no fundo da tigela; Ø 0,9 m."""
    br = Shape("Tigela", "bronze", voxel=0.006, tris=1300, color_soft=0.01)
    bowl = ellipsoid((0, 0, 0.3), (0.45, 0.45, 0.28)).shell(0.03).clip(plane((0, 0, 0.3), (0, 0, 1)))
    br.add(bowl, "root", BRASS_D, k=0)
    br.add(torus((0, 0, 0.3), 0.45, 0.03), "root", BRASS, k=0.01)
    br.add(cone((0, 0, 0.04), 0.2, 0.14, 0.04, rounding=0.01), "root", BRASS_D, k=0.03)
    for i in range(6):
        a = 2 * math.pi * i / 6
        br.add(sphere((math.cos(a) * 0.45, math.sin(a) * 0.45, 0.31), 0.04), "root", BRASS, k=0.01)
    br.paint(torus((0, 0, 0.17), 0.39, 0.012), GLYPH, soft=0.012)
    bm = bmesh.new()
    crystal_prism(bm, (0, 0, 0.06), (0, 0, 1), 0.38, 0.31, sides=8, tip=0.42, twist=0.2)
    deep = hexcol("C8641E")        # âmbar fundo: com energia 2,0 ainda lê laranja, não branco
    gem = bm_object("Gema", bm, "glow", (AMBER[0], AMBER[1], AMBER[2], 0.0), flat=True,
                    gradient=lambda t: tuple(deep[k] * (1 - t) + AMBER[k] * t for k in range(3)) + (0.0,))
    objs = build_parts({"Tigela": ([br], [], None)}) + [gem]
    objs.append(empty("flame", (0, 0, 0.35)))
    export("braseiro", objs)


PROPS = {
    "agulha": agulha, "portao_vael": portao_vael, "cabeca_colosso": cabeca_colosso, "mao_colosso": mao_colosso,
    "cristal": cristal, "cristal_b": cristal_b, "geodo": geodo, "colunata": colunata, "arco": arco, "pilar": pilar,
    "rocha": lambda: rocha("rocha", 1, (2.2, 1.7, 1.5)), "rocha_b": lambda: rocha("rocha_b", 4, (1.6, 2.4, 2.4)),
    "totem": totem, "plate": lambda: plate(False), "plate_heavy": lambda: plate(True), "gate": gate,
    "urna": urna, "tambor": tambor, "portal": fenda, "relic": pedra_hora,
    "item_arpeu": item_arpeu, "item_bastao": item_bastao, "item_lanterna": item_lanterna, "item_concha": item_concha,
    "relicario": relicario, "argola": argola, "aro_puxar": aro_puxar, "sino_cristal": sino_cristal,
    "cristal_eco": cristal_eco, "cabeco": cabeco, "cabeco_baixo": lambda: cabeco("cabeco_baixo", 2.2),
    "braseiro": braseiro,
}


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = argv[argv.index("--only") + 1].split(",") if "--only" in argv else list(PROPS)
    global OUT, LIFT
    if "--out" in argv:
        OUT = Path(argv[argv.index("--out") + 1])
    LIFT = "--lift" in argv
    for name in only:
        reset_scene()
        log("prop", name)
        PROPS[name]()


if __name__ == "__main__":
    main()
