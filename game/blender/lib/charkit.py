"""charkit — kit de modelagem/rig/animação procedural para os heróis de YLVAAR.

Tudo é construído por código (Blender 4.x, headless):
  * MeshBuilder: partes (elipsoides/superelipsoides, tubos ao longo de cadeias de
    ossos, tufos curvos, fitas, anéis) com cor por vértice (sRGB → linear),
    UV, material e pesos de skinning por parte.
  * Rig: armature a partir de uma tabela (cabeça, cauda, pai), com "roll" que
    deixa o eixo X local ≈ X do mundo — rotação +X = "inclinar para frente/baixo".
  * Animações: funções pose(t) → {osso: (rx, ry, rz, [loc])} amostradas a 30 fps.

Convenções (Blender): personagem olha para -Y, Z para cima, o lado ESQUERDO dele
fica em +X (sufixo _L). No Godot (glTF): olha para +Z.
"""
from __future__ import annotations

import math
from dataclasses import dataclass, field

import bpy
from mathutils import Euler, Matrix, Quaternion, Vector


def srgb_to_linear(c: float) -> float:
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def lin(col) -> tuple:
    return tuple(srgb_to_linear(x) for x in col[:3]) + ((col[3],) if len(col) > 3 else (1.0,))


def mix(a, b, t):
    return tuple(x + (y - x) * t for x, y in zip(a, b))


def smooth01(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


# ----------------------------------------------------------------------------- rig
@dataclass
class BoneDef:
    name: str
    head: tuple
    tail: tuple
    parent: str | None = None
    deform: bool = True


class Rig:
    def __init__(self, bones: list[BoneDef]):
        self.bones = {b.name: b for b in bones}
        self.order = [b.name for b in bones]

    def seg(self, name: str) -> tuple[Vector, Vector]:
        b = self.bones[name]
        return Vector(b.head), Vector(b.tail)

    def build(self, name: str) -> bpy.types.Object:
        arm = bpy.data.armatures.new(name + "_Rig")
        obj = bpy.data.objects.new(name, arm)
        bpy.context.scene.collection.objects.link(obj)
        bpy.context.view_layer.objects.active = obj
        obj.select_set(True)
        bpy.ops.object.mode_set(mode="EDIT")
        ebs = {}
        for bn in self.order:
            b = self.bones[bn]
            eb = arm.edit_bones.new(bn)
            eb.head = Vector(b.head)
            eb.tail = Vector(b.tail)
            d = (eb.tail - eb.head).normalized()
            z = Vector((1, 0, 0)).cross(d)
            if z.length < 1e-3:          # bone along X: keep Z pointing back
                z = Vector((0, 1, 0))
            eb.align_roll(z.normalized())
            eb.use_deform = b.deform
            ebs[bn] = eb
        for bn in self.order:
            b = self.bones[bn]
            if b.parent:
                ebs[bn].parent = ebs[b.parent]
                ebs[bn].use_connect = False
        bpy.ops.object.mode_set(mode="OBJECT")
        for pb in obj.pose.bones:
            pb.rotation_mode = "XYZ"
        return obj


def dist_point_segment(p: Vector, a: Vector, b: Vector) -> tuple[float, float]:
    ab = b - a
    L2 = ab.length_squared
    t = 0.0 if L2 < 1e-12 else max(0.0, min(1.0, (p - a).dot(ab) / L2))
    return (a + ab * t - p).length, t


# ----------------------------------------------------------------------------- mesh
class MeshBuilder:
    def __init__(self, rig: Rig):
        self.rig = rig
        self.verts: list[Vector] = []
        self.faces: list[tuple] = []
        self.face_mat: list[int] = []
        self.colors: list[tuple] = []
        self.uvs: list[tuple] = []          # per vertex (u, v)
        self.weights: list[dict] = []
        self.materials: list[str] = []

    def mat(self, name: str) -> int:
        if name not in self.materials:
            self.materials.append(name)
        return self.materials.index(name)

    def _add(self, p, col, w: dict, uv=(0.0, 0.0)) -> int:
        self.verts.append(Vector(p))
        self.colors.append(lin(col))
        self.uvs.append(uv)
        s = sum(w.values()) or 1.0
        self.weights.append({k: v / s for k, v in w.items() if v / s > 0.002})
        return len(self.verts) - 1

    def _face(self, f, m: int) -> None:
        self.faces.append(tuple(f))
        self.face_mat.append(m)

    # ---- weights helpers
    def w_dist(self, p: Vector, bones: list[str], power: float = 5.0) -> dict:
        out = {}
        best = 1e9
        ds = {}
        for bn in bones:
            a, b = self.rig.seg(bn)
            d, _ = dist_point_segment(p, a, b)
            ds[bn] = d
            best = min(best, d)
        for bn, d in ds.items():
            out[bn] = 1.0 / max(d, 0.004) ** power
        return out

    # ---- primitives
    def ellipsoid(self, center, radii, color, bones, mat="fur", rot=(0, 0, 0), seg=16, rings=12,
                  shape=None, color_fn=None, exponent=(2.0, 2.0), uv_mode=None, weight_fn=None):
        """(Super)ellipsoid. exponent > 2 gives boxy shapes (capybara head).
        shape(p_local) -> p_local deformed. color_fn(p_local_unit) -> color.
        bones: list (distance weights) or dict (fixed weights)."""
        m = self.mat(mat)
        c = Vector(center)
        R = Euler([math.radians(a) for a in rot], "XYZ").to_matrix()
        e1, e2 = exponent
        idx = []

        def spow(x, e):
            return math.copysign(abs(x) ** (2.0 / e), x)

        for i in range(rings + 1):
            th = math.pi * i / rings              # 0 top .. pi bottom
            row = []
            for j in range(seg):
                ph = 2 * math.pi * j / seg
                st, ct = math.sin(th), math.cos(th)
                u = Vector((spow(st, e1) * spow(math.cos(ph), e2),
                            spow(st, e1) * spow(math.sin(ph), e2),
                            spow(ct, e1)))
                pl = Vector((u.x * radii[0], u.y * radii[1], u.z * radii[2]))
                if shape:
                    pl = Vector(shape(pl))
                p = c + R @ pl
                col = color_fn(u) if color_fn else color
                if weight_fn:
                    w = weight_fn(p, u)
                elif isinstance(bones, dict):
                    w = dict(bones)
                else:
                    w = self.w_dist(p, bones)
                uv = (0.0, 0.0)
                if uv_mode == "front":           # eyes: front (-Y) at uv center; glTF flips V on export
                    uv = (0.5 + u.x * 0.5, 0.5 + u.z * 0.5)
                if i == 0 or i == rings:
                    if j == 0:
                        row.append(self._add(p, col, w, uv))
                    else:
                        row.append(row[0])
                else:
                    row.append(self._add(p, col, w, uv))
            idx.append(row)
        for i in range(rings):
            for j in range(seg):
                a, b = idx[i][j], idx[i][(j + 1) % seg]
                cc, d = idx[i + 1][(j + 1) % seg], idx[i + 1][j]
                if i == 0:
                    self._face((a, d, cc), m)
                elif i == rings - 1:
                    self._face((a, d, b), m)
                else:
                    self._face((a, d, cc, b), m)

    def tube(self, points, radii, color, chain, mat="fur", seg=10, per_bone=4, cap_start=True, cap_end=True,
             color_fn=None, flatten=1.0, up=(0, 0, 1)):
        """Tube through `points` (one per joint, len(chain)+1) with radius per point.
        Rings are weighted to the chain bones with smooth blends at the joints."""
        m = self.mat(mat)
        pts = [Vector(p) for p in points]
        n_seg = len(pts) - 1
        # Catmull-Rom samples
        samples = []
        for s in range(n_seg):
            p0 = pts[max(s - 1, 0)]
            p1, p2 = pts[s], pts[s + 1]
            p3 = pts[min(s + 2, n_seg)]
            for k in range(per_bone):
                t = k / per_bone
                t2, t3 = t * t, t * t * t
                p = 0.5 * ((2 * p1) + (-p0 + p2) * t + (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 + (-p0 + 3 * p1 - 3 * p2 + p3) * t3)
                r = radii[s] + (radii[s + 1] - radii[s]) * t
                samples.append((p, r, s, t))
        samples.append((pts[-1], radii[-1], n_seg - 1, 1.0))
        rings = []
        prev_n = None
        upv = Vector(up)
        total = len(samples)
        for k, (p, r, s, t) in enumerate(samples):
            if k < total - 1:
                tan = (samples[k + 1][0] - p).normalized()
            else:
                tan = (p - samples[k - 1][0]).normalized()
            if prev_n is None:
                n = upv - tan * upv.dot(tan)
                if n.length < 1e-3:
                    n = Vector((1, 0, 0)) - tan * tan.x
                n.normalize()
            else:
                n = (prev_n - tan * prev_n.dot(tan)).normalized()
            prev_n = n
            b = tan.cross(n)
            # weights: bone s, blended with neighbours near the joints
            w = {chain[s]: 1.0}
            if t < 0.35 and s > 0:
                f = 0.5 - t / 0.7
                w = {chain[s]: 1.0 - f, chain[s - 1]: f}
            elif t > 0.65 and s < n_seg - 1:
                f = (t - 0.65) / 0.7
                w = {chain[s]: 1.0 - f, chain[s + 1]: f}
            row = []
            frac = k / max(total - 1, 1)
            for j in range(seg):
                a = 2 * math.pi * j / seg
                off = n * math.cos(a) * r * flatten + b * math.sin(a) * r
                col = color_fn(frac, a) if color_fn else color
                row.append(self._add(p + off, col, w))
            rings.append((row, p, tan, w, frac))
        for i in range(len(rings) - 1):
            ra, rb = rings[i][0], rings[i + 1][0]
            for j in range(seg):
                self._face((ra[j], ra[(j + 1) % seg], rb[(j + 1) % seg], rb[j]), m)
        for which, ok in ((0, cap_start), (-1, cap_end)):
            if not ok:
                continue
            row, p, tan, w, frac = rings[which]
            r = samples[which][1]
            tip = p + tan * (r * 0.8 if which == -1 else -r * 0.8)
            col = color_fn(frac, 0.0) if color_fn else color
            ti = self._add(tip, col, w)
            for j in range(seg):
                if which == 0:
                    self._face((row[(j + 1) % seg], row[j], ti), m)
                else:
                    self._face((row[j], row[(j + 1) % seg], ti), m)

    def tuft(self, base, direction, length, width, color_base, color_tip, bones, mat="fur", bend=(0, 0, 0),
             sides=5, segs=3, flat=1.0):
        """Curved cone (hair clump / mane spike / tail tuft)."""
        m = self.mat(mat)
        d = Vector(direction).normalized()
        bendv = Vector(bend)
        side = d.cross(Vector((0, 0, 1)))
        if side.length < 1e-3:
            side = d.cross(Vector((0, 1, 0)))
        side.normalize()
        up = side.cross(d).normalized()
        w = dict(bones) if isinstance(bones, dict) else self.w_dist(Vector(base), bones)
        rows = []
        for s in range(segs + 1):
            t = s / segs
            c = Vector(base) + d * length * t + bendv * (t * t) * length
            r = width * (1.0 - t) ** 0.9
            col = mix(color_base, color_tip, t)
            if s == segs:
                rows.append([self._add(c, color_tip, w)])
                break
            row = []
            for j in range(sides):
                a = 2 * math.pi * j / sides
                row.append(self._add(c + side * math.cos(a) * r + up * math.sin(a) * r * flat, col, w))
            rows.append(row)
        for s in range(segs):
            ra, rb = rows[s], rows[s + 1]
            for j in range(sides):
                if len(rb) == 1:
                    self._face((ra[j], ra[(j + 1) % sides], rb[0]), m)
                else:
                    self._face((ra[j], ra[(j + 1) % sides], rb[(j + 1) % sides], rb[j]), m)
        # base cap
        cb = self._add(Vector(base) - d * width * 0.2, color_base, w)
        r0 = rows[0]
        for j in range(sides):
            self._face((r0[(j + 1) % sides], r0[j], cb), m)

    def ribbon(self, points, widths, normal_fn, color_fn, chain_weights, mat="cloth", thickness=0.006):
        """Thin double-sided strip along points. normal_fn(i) -> width direction.
        chain_weights(i) -> weights dict. color_fn(i, side) -> color. UV: u across, v along."""
        m = self.mat(mat)
        n = len(points)
        top, bot = [], []
        for i, p in enumerate(points):
            wdir = Vector(normal_fn(i)).normalized()
            p = Vector(p)
            if i < n - 1:
                tan = (Vector(points[i + 1]) - p).normalized()
            else:
                tan = (p - Vector(points[i - 1])).normalized()
            nrm = tan.cross(wdir).normalized() * thickness
            w = chain_weights(i)
            v = i / (n - 1)
            row_t, row_b = [], []
            for s in (-1, 1):
                q = p + wdir * widths[i] * 0.5 * s
                row_t.append(self._add(q + nrm, color_fn(i, s), w, ((s + 1) * 0.5, v)))
                row_b.append(self._add(q - nrm, color_fn(i, s), w, ((s + 1) * 0.5, v)))
            top.append(row_t)
            bot.append(row_b)
        for i in range(n - 1):
            a, b = top[i], top[i + 1]
            self._face((a[0], a[1], b[1], b[0]), m)
            a, b = bot[i], bot[i + 1]
            self._face((a[0], b[0], b[1], a[1]), m)
            # edges
            self._face((top[i][0], top[i + 1][0], bot[i + 1][0], bot[i][0]), m)
            self._face((top[i][1], bot[i][1], bot[i + 1][1], top[i + 1][1]), m)

    def ring(self, center, axis, radius, tube_r, color, bones, mat="cloth", seg=16, tseg=6, color_fn=None):
        """Torus (collars, wrist ribbons)."""
        m = self.mat(mat)
        ax = Vector(axis).normalized()
        u = ax.cross(Vector((0, 0, 1)))
        if u.length < 1e-3:
            u = ax.cross(Vector((1, 0, 0)))
        u.normalize()
        v = ax.cross(u).normalized()
        c = Vector(center)
        rows = []
        for i in range(seg):
            a = 2 * math.pi * i / seg
            dirv = u * math.cos(a) + v * math.sin(a)
            pc = c + dirv * radius
            col = color_fn(i / seg) if color_fn else color
            row = []
            for j in range(tseg):
                b = 2 * math.pi * j / tseg
                p = pc + dirv * math.cos(b) * tube_r + ax * math.sin(b) * tube_r
                w = dict(bones) if isinstance(bones, dict) else self.w_dist(p, bones)
                row.append(self._add(p, col, w))
            rows.append(row)
        for i in range(seg):
            ra, rb = rows[i], rows[(i + 1) % seg]
            for j in range(tseg):
                self._face((ra[j], rb[j], rb[(j + 1) % tseg], ra[(j + 1) % tseg]), m)

    # ---- object
    def build(self, name: str, rig_obj: bpy.types.Object, mats: dict) -> bpy.types.Object:
        mesh = bpy.data.meshes.new(name)
        mesh.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        mesh.validate(clean_customdata=False)
        mesh.update()
        obj = bpy.data.objects.new(name, mesh)
        bpy.context.scene.collection.objects.link(obj)
        for mn in self.materials:
            mesh.materials.append(mats[mn])
        mesh.polygons.foreach_set("material_index", self.face_mat[:len(mesh.polygons)])
        mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
        # colors
        attr = mesh.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
        flat = []
        for c in self.colors:
            flat.extend(c)
        attr.data.foreach_set("color", flat)
        mesh.color_attributes.active_color = attr
        try:
            mesh.color_attributes.render_color_index = mesh.color_attributes.find("Col")
        except Exception:
            pass
        # uvs (per loop)
        uvl = mesh.uv_layers.new(name="UVMap")
        loop_uv = []
        for lp in mesh.loops:
            loop_uv.extend(self.uvs[lp.vertex_index])
        uvl.data.foreach_set("uv", loop_uv)
        # skin
        groups = {}
        for bn in self.rig.order:
            if self.rig.bones[bn].deform:
                groups[bn] = obj.vertex_groups.new(name=bn)
        for vi, w in enumerate(self.weights):
            # keep the 4 strongest influences
            items = sorted(w.items(), key=lambda kv: -kv[1])[:4]
            s = sum(v for _, v in items) or 1.0
            for bn, v in items:
                if bn in groups:
                    groups[bn].add([vi], v / s, "REPLACE")
        mod = obj.modifiers.new("Armature", "ARMATURE")
        mod.object = rig_obj
        obj.parent = rig_obj
        return obj


# ----------------------------------------------------------------------------- animation
FPS = 30


def bake_action(rig_obj: bpy.types.Object, name: str, length_s: float, pose_fn, loop: bool = True) -> bpy.types.Action:
    """Samples pose_fn(t, phase) at 30 fps into a new action.
    pose_fn returns {bone: (rx, ry, rz)} in degrees or {bone: (rx, ry, rz, (lx, ly, lz))}."""
    if rig_obj.animation_data is None:
        rig_obj.animation_data_create()
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    rig_obj.animation_data.action = act
    frames = max(2, int(round(length_s * FPS)))
    pbs = rig_obj.pose.bones
    touched = set()
    for f in range(frames + 1):
        t = f / FPS
        ph = (f / frames) if frames else 0.0
        pose = pose_fn(t, ph)
        for pb in pbs:
            pb.rotation_euler = (0, 0, 0)
            pb.location = (0, 0, 0)
            pb.scale = (1, 1, 1)
        for bn, val in pose.items():
            pb = pbs.get(bn)
            if pb is None:
                continue
            rx, ry, rz = val[0], val[1], val[2]
            pb.rotation_euler = (math.radians(rx), math.radians(ry), math.radians(rz))
            if len(val) > 3 and val[3] is not None:
                pb.location = val[3]
            if len(val) > 4 and val[4] is not None:
                pb.scale = val[4]
            touched.add(bn)
        for pb in pbs:
            pb.keyframe_insert("rotation_euler", frame=f + 1, group=pb.name)
            pb.keyframe_insert("location", frame=f + 1, group=pb.name)
            pb.keyframe_insert("scale", frame=f + 1, group=pb.name)
    for fc in act.fcurves:
        for kp in fc.keyframe_points:
            kp.interpolation = "LINEAR"
    act.frame_range = (1, frames + 1)
    return act


def wave(ph: float, offset: float = 0.0) -> float:
    """sin over a 0..1 phase."""
    return math.sin((ph + offset) * math.tau)


def ease_out(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return 1 - (1 - t) ** 3


def ease_in_out(t: float) -> float:
    t = max(0.0, min(1.0, t))
    return t * t * (3 - 2 * t)


def keys(t: float, pts: list[tuple]) -> float:
    """Piecewise smooth interpolation between (time, value) keys."""
    if t <= pts[0][0]:
        return pts[0][1]
    for (t0, v0), (t1, v1) in zip(pts[:-1], pts[1:]):
        if t <= t1:
            u = (t - t0) / max(t1 - t0, 1e-6)
            return v0 + (v1 - v0) * ease_in_out(u)
    return pts[-1][1]


def mirror_pose(pose: dict) -> dict:
    """Builds _R entries mirrored from _L entries (rx, -ry, -rz, mirrored loc)."""
    out = dict(pose)
    for bn, v in pose.items():
        if bn.endswith("_L"):
            rn = bn[:-2] + "_R"
            if rn in pose:
                continue
            nv = [v[0], -v[1], -v[2]]
            if len(v) > 3:
                nv.append(None if v[3] is None else (-v[3][0], v[3][1], v[3][2]))
            if len(v) > 4:
                nv.append(v[4])
            out[rn] = tuple(nv)
    return out
