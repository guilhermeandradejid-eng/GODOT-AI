"""sdfchar — monta uma personagem completa a partir de peças SDF (sdfkit),
peças duras (primitivas do Blender) e olhos com UV para o shader de olho.

    rig = Rig([...BoneDef...])
    shapes = [Shape(...), ...]
    rig_obj, body = assemble("Nome", rig, shapes, extras=[eye_object(...), ...])
    bake_action(rig_obj, "idle", 2.0, idle_fn)          # charkit
    export(...)
"""
from __future__ import annotations

import math

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

import sdfkit
from bhelpers import export_glb, log, material, select_only
from charkit import Rig


def _mat(name: str) -> bpy.types.Material:
    m = bpy.data.materials.get(name)
    return m if m is not None else material(name, (0.8, 0.8, 0.8, 1.0))


def _assign_material(obj: bpy.types.Object, mat_name: str) -> None:
    obj.data.materials.clear()
    obj.data.materials.append(_mat(mat_name))


def union_field(shapes: list[sdfkit.Shape]):
    fields = [s.field for s in shapes]

    def f(P):
        d = fields[0](P)
        for g in fields[1:]:
            d = np.minimum(d, g(P))
        return d
    return f


def eye_object(name: str, center, radius: float, forward, bone: str, rig_bones: list[str],
               squash=(1.0, 1.0, 1.0), up=(0.0, 0.0, 1.0), segments: int = 20, rings: int = 14,
               material_name: str = "eye") -> bpy.types.Object:
    """Esfera de olho com UV frontal: u cresce para +X do mundo, v para +Z (o glTF inverte v,
    então no Godot UV.y cresce para baixo, como o shader de olho espera)."""
    bm = bmesh.new()
    bmesh.ops.create_uvsphere(bm, u_segments=segments, v_segments=rings, radius=1.0)
    f = Vector(forward).normalized()
    u = Vector(up)
    x = u.cross(f).normalized() if abs(u.dot(f)) < 0.98 else Vector((1, 0, 0))
    y = f.cross(x).normalized()
    # sphere pole (+Z of the primitive) -> forward
    basis = Matrix((x, y, f)).transposed()
    sq = Vector(squash)
    for v in bm.verts:
        p = Vector((v.co.x * sq.x, v.co.y * sq.y, v.co.z * sq.z)) * radius
        v.co = Vector(center) + basis @ p
    uv_layer = bm.loops.layers.uv.new("UVMap")
    for face in bm.faces:
        for lp in face.loops:
            d = (lp.vert.co - Vector(center)).normalized()
            lp[uv_layer].uv = (0.5 + d.x * 0.5 * 1.25, 0.5 + d.z * 0.5 * 1.25)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    for p in me.polygons:
        p.use_smooth = True
    sdfkit.rigid_object(obj, bone, rig_bones, color=(1, 1, 1))
    _assign_material(obj, material_name)
    return obj


def hard_object(name: str, build, bone: str, rig_bones: list[str], color, material_name: str,
                smooth: bool = False, bevel: float = 0.0) -> bpy.types.Object:
    """Peça dura: `build(bm)` preenche um bmesh (primitivas, extrusões...)."""
    bm = bmesh.new()
    build(bm)
    me = bpy.data.meshes.new(name)
    bm.to_mesh(me)
    bm.free()
    obj = bpy.data.objects.new(name, me)
    bpy.context.scene.collection.objects.link(obj)
    if bevel > 0.0:
        select_only([obj])
        mod = obj.modifiers.new("Bevel", "BEVEL")
        mod.width = bevel
        mod.segments = 2
        mod.limit_method = "ANGLE"
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for p in obj.data.polygons:
        p.use_smooth = smooth
    if not obj.data.uv_layers:
        obj.data.uv_layers.new(name="UVMap")
    sdfkit.rigid_object(obj, bone, rig_bones, color=color)
    _assign_material(obj, material_name)
    return obj


def assemble(name: str, rig: Rig, shapes: list[sdfkit.Shape], extras=(), ao: bool = True):
    rig_obj = rig.build(name)
    bones = [b for b in rig.order if rig.bones[b].deform]
    ao_field = union_field(shapes) if ao else None
    objs = []
    for sh in shapes:
        o = sdfkit.build_object(sh, bones, log=log, ao_field=ao_field)
        _assign_material(o, sh.material)
        objs.append(o)
    objs.extend(extras)
    select_only(objs)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    body = bpy.context.view_layer.objects.active
    body.name = name + "Mesh"
    body.data.name = name + "Mesh"
    # clean empty groups
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


def export(path, rig_obj, body) -> None:
    rig_obj.animation_data.action = bpy.data.actions.get("idle") if rig_obj.animation_data else None
    bpy.context.scene.frame_set(1)
    export_glb(path, [rig_obj, body], animations=True, skins=True)
