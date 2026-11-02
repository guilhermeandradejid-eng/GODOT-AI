"""sdfprop — props e cenários modelados por SDF (sdfkit) e exportados em GLB.

    stone = Shape("Pedra", "stone", voxel=0.03, tris=1500)
    stone.add(box(...), "root", hexcol("d9a27a"), k=0.2)
    export_prop("monolito", [stone], extras=[...])     # -> game/assets/props/monolito.glb

Materiais pelo nome (PropLib troca pelos shaders do jogo): stone, wood, bronze,
cloth, leaf, glow, petal. A cor vai por vértice (com AO do campo); o alfa do
vértice é o "quanto balança no vento" no shader de props (1 = parado aqui:
emissão de pintura não é usada em props; use uma peça "glow").
"""
from __future__ import annotations

from pathlib import Path

import bpy
import numpy as np

import sdfkit
from bhelpers import ASSETS, export_glb, log, material, select_only


def _mat(name: str):
    m = bpy.data.materials.get(name)
    return m if m is not None else material(name, (0.8, 0.8, 0.8, 1.0))


def build_prop(name: str, shapes: list, extras=(), ao: bool = True, sway=None):
    """Malha única do prop (uma superfície por material). sway(V)->0..1 opcional
    grava o balanço no vento no alfa do vértice (folhas, panos)."""
    fields = [s.field for s in shapes]

    def union(P):
        d = fields[0](P)
        for f in fields[1:]:
            d = np.minimum(d, f(P))
        return d
    objs = []
    for sh in shapes:
        o = sdfkit.build_object(sh, [], log=log, ao_field=union if ao else None, ao_strength=0.65)
        o.data.materials.clear()
        o.data.materials.append(_mat(sh.material))
        me = o.data
        attr = me.color_attributes.get("Col")
        n = len(me.vertices)
        col = np.empty(n * 4, np.float32)
        attr.data.foreach_get("color", col)
        col = col.reshape(-1, 4)
        if sway is not None:
            co = np.empty(n * 3, np.float32)
            me.vertices.foreach_get("co", co)
            col[:, 3] = np.clip(sway(co.reshape(-1, 3).astype(np.float64)), 0.0, 1.0)
        else:
            col[:, 3] = 0.0 if sh.material != "glow" else col[:, 3]
        attr.data.foreach_set("color", col.ravel())
        objs.append(o)
    objs.extend(extras)
    select_only(objs)
    bpy.context.view_layer.objects.active = objs[0]
    if len(objs) > 1:
        bpy.ops.object.join()
    obj = bpy.context.view_layer.objects.active
    obj.name = name
    obj.data.name = name
    tris = sum(len(p.vertices) - 2 for p in obj.data.polygons)
    log(f"prop {name}: {len(obj.data.vertices)} verts, {tris} tris")
    return obj


def export_prop(name: str, shapes: list, extras=(), out_dir: Path | None = None, **kw) -> Path:
    obj = build_prop(name, shapes, extras, **kw)
    path = (out_dir or (ASSETS / "props")) / f"{name}.glb"
    export_glb(path, [obj])
    return path
