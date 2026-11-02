"""Shared helpers for the SOPRO Blender build scripts (Blender 4.x, run headless).

Coordinates: the level recipe (game/world/lencois.json) uses Godot axes
(x east, y up, z south). Blender is Z-up: Godot (x, y, z) == Blender (x, -z, y).
The glTF exporter (export_yup=True) converts back, so meshes built here in
Blender space land in Godot exactly where the recipe says.
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[3]          # repo root (GODOT-AI/)
GAME = ROOT / "game"
ASSETS = GAME / "assets"


def log(*args) -> None:
    print("[sopro]", *args, flush=True)
    sys.stdout.flush()


def reset_scene() -> None:
    """Empty scene, metric units, 30 fps."""
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "METRIC"
    scene.render.fps = 30
    scene.frame_start = 1


def g2b(x: float, y: float, z: float) -> Vector:
    """Godot position -> Blender position."""
    return Vector((x, -z, y))


def smoothstep(e0: float, e1: float, x: float) -> float:
    if e0 == e1:
        return 0.0 if x < e0 else 1.0
    t = max(0.0, min(1.0, (x - e0) / (e1 - e0)))
    return t * t * (3.0 - 2.0 * t)


def lerp(a, b, t):
    return a + (b - a) * t


def clamp(x, a=0.0, b=1.0):
    return a if x < a else (b if x > b else x)


def mesh_object(name: str, verts, faces, collection=None) -> bpy.types.Object:
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata([tuple(v) for v in verts], [], [tuple(f) for f in faces])
    mesh.validate(clean_customdata=False)
    mesh.update()
    obj = bpy.data.objects.new(name, mesh)
    (collection or bpy.context.scene.collection).objects.link(obj)
    return obj


def set_smooth(obj: bpy.types.Object, auto_angle_deg: float | None = None) -> None:
    mesh = obj.data
    mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
    if auto_angle_deg is not None and hasattr(mesh, "use_auto_smooth"):
        mesh.use_auto_smooth = True
        mesh.auto_smooth_angle = math.radians(auto_angle_deg)
    mesh.update()


def set_point_colors(obj: bpy.types.Object, colors, name: str = "Col") -> None:
    """colors: list of (r, g, b, a) per vertex (linear floats). Becomes glTF COLOR_0."""
    mesh = obj.data
    attr = mesh.color_attributes.get(name) or mesh.color_attributes.new(name=name, type="FLOAT_COLOR", domain="POINT")
    flat = [0.0] * (len(colors) * 4)
    for i, c in enumerate(colors):
        flat[i * 4:i * 4 + 4] = (c[0], c[1], c[2], c[3] if len(c) > 3 else 1.0)
    attr.data.foreach_set("color", flat)
    idx = mesh.color_attributes.find(name)
    mesh.color_attributes.active_color = attr
    try:
        mesh.color_attributes.render_color_index = idx
    except Exception:  # read-only in some versions; active is then used
        pass


def material(name: str, color=(0.8, 0.8, 0.8, 1.0), emission=None, roughness=0.8) -> bpy.types.Material:
    """Simple Principled material. Godot replaces most of them by game shaders,
    but names/colors still travel in the glTF (useful as material IDs)."""
    mat = bpy.data.materials.get(name)
    if mat is None:
        mat = bpy.data.materials.new(name)
        mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    if bsdf is not None:
        bsdf.inputs["Base Color"].default_value = color
        bsdf.inputs["Roughness"].default_value = roughness
        if emission is not None:
            key = "Emission Color" if "Emission Color" in bsdf.inputs else "Emission"
            bsdf.inputs[key].default_value = (*emission[:3], 1.0)
            if "Emission Strength" in bsdf.inputs:
                bsdf.inputs["Emission Strength"].default_value = emission[3] if len(emission) > 3 else 1.0
    mat.diffuse_color = color
    return mat


def select_only(objs) -> None:
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    if objs:
        bpy.context.view_layer.objects.active = objs[0]


def export_glb(path: Path, objs, animations: bool = False, skins: bool = False) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    select_only(objs)
    kw = dict(
        filepath=str(path),
        export_format="GLB",
        use_selection=True,
        export_apply=True,
        export_yup=True,
        export_colors=True,
        export_normals=True,
        export_texcoords=True,
        export_tangents=False,
        export_materials="EXPORT",
        export_cameras=False,
        export_lights=False,
        export_skins=skins,
        export_morph=False,
        export_animations=animations,
    )
    if animations:
        kw.update(
            export_animation_mode="ACTIONS",
            export_force_sampling=True,
            export_frame_step=1,
            export_def_bones=False,
            export_optimize_animation_size=False,
            export_anim_single_armature=True,
            export_reset_pose_bones=True,
        )
    bpy.ops.export_scene.gltf(**kw)
    log("exported", path.relative_to(ROOT), f"{path.stat().st_size // 1024} KB")


def hemisphere_dirs(n: int):
    """Cosine-weighted hemisphere directions around +Z (Fibonacci spiral)."""
    dirs = []
    golden = math.pi * (3.0 - math.sqrt(5.0))
    for i in range(n):
        u = (i + 0.5) / n
        r = math.sqrt(u)
        th = golden * i
        dirs.append(Vector((r * math.cos(th), r * math.sin(th), math.sqrt(max(0.0, 1.0 - u)))))
    return dirs


def bake_vertex_ao(obj: bpy.types.Object, rays: int = 12, max_dist: float = 10.0, strength: float = 0.95,
                   extra_bvhs=()) -> list[float]:
    """Per-vertex ambient occlusion by ray casting against the object (+ optional extra BVH trees)."""
    from mathutils.bvhtree import BVHTree
    mesh = obj.data
    mesh.update()
    mw = obj.matrix_world
    verts = [mw @ v.co for v in mesh.vertices]
    faces = [tuple(p.vertices) for p in mesh.polygons]
    bvh = BVHTree.FromPolygons(verts, faces)
    trees = [bvh, *extra_bvhs]
    nm = mw.to_3x3().inverted().transposed()
    base_dirs = hemisphere_dirs(rays)
    out = []
    for v, mv in zip(verts, mesh.vertices):
        n = (nm @ mv.normal).normalized()
        # tangent frame
        t = Vector((0, 0, 1)).cross(n)
        if t.length < 1e-4:
            t = Vector((1, 0, 0)).cross(n)
        t.normalize()
        b = n.cross(t)
        origin = v + n * 0.06
        occ = 0.0
        for d in base_dirs:
            dw = (t * d.x + b * d.y + n * d.z).normalized()
            best = None
            for tree in trees:
                hit = tree.ray_cast(origin, dw, max_dist)
                if hit[0] is not None and (best is None or hit[3] < best):
                    best = hit[3]
            if best is not None:
                occ += 1.0 - (best / max_dist) ** 0.5 * 0.6
        out.append(clamp(1.0 - strength * occ / rays))
    return out
