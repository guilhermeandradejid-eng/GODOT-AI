"""propkit — modelagem procedural de props (sem esqueleto) para SOPRO.

PropBuilder junta primitivas (torno/lathe, tubos por caminho, elipsoides,
caixas arredondadas, leques de folhas) com cor por vértice em sRGB (→ linear)
e um material por parte. Cada prop vira um objeto (ou vários filhos nomeados,
para partes animadas no Godot: pétalas, pás, tubos de sino...).
"""
from __future__ import annotations

import math
import random

import bpy
from mathutils import Matrix, Vector, noise

from charkit import lin, mix, smooth01

TAU = math.tau


class PropBuilder:
    def __init__(self, name: str):
        self.name = name
        self.verts: list[Vector] = []
        self.faces: list[tuple] = []
        self.face_mat: list[int] = []
        self.colors: list[tuple] = []
        self.materials: list[str] = []

    def mat(self, name: str) -> int:
        if name not in self.materials:
            self.materials.append(name)
        return self.materials.index(name)

    def v(self, p, col) -> int:
        self.verts.append(Vector(p))
        self.colors.append(lin(col))
        return len(self.verts) - 1

    def f(self, idx, m: int) -> None:
        self.faces.append(tuple(idx))
        self.face_mat.append(m)

    # ------------------------------------------------------------ primitives
    def lathe(self, profile, color_fn, mat="stone", seg=24, center=(0, 0, 0), wobble=0.0, seed=0.0,
              cap_top=True, cap_bottom=True, xform=None):
        """profile: list of (radius, z). color_fn(i_profile, angle, p) -> rgb."""
        m = self.mat(mat)
        c = Vector(center)
        rows = []
        for i, (r, z) in enumerate(profile):
            row = []
            for j in range(seg):
                a = TAU * j / seg
                rr = r * (1.0 + wobble * noise.noise(Vector((math.cos(a) * 2, math.sin(a) * 2, z * 0.7 + seed))))
                p = Vector((math.cos(a) * rr, math.sin(a) * rr, z))
                if xform is not None:
                    p = xform @ p
                p += c
                row.append(self.v(p, color_fn(i, a, p)))
            rows.append(row)
        for i in range(len(rows) - 1):
            a, b = rows[i], rows[i + 1]
            for j in range(seg):
                self.f((a[j], a[(j + 1) % seg], b[(j + 1) % seg], b[j]), m)
        if cap_bottom and profile[0][0] > 1e-4:
            ci = self.v(c + (xform @ Vector((0, 0, profile[0][1])) if xform else Vector((0, 0, profile[0][1]))),
                        color_fn(0, 0.0, c))
            for j in range(seg):
                self.f((rows[0][(j + 1) % seg], rows[0][j], ci), m)
        if cap_top and profile[-1][0] > 1e-4:
            ci = self.v(c + (xform @ Vector((0, 0, profile[-1][1])) if xform else Vector((0, 0, profile[-1][1]))),
                        color_fn(len(profile) - 1, 0.0, c))
            for j in range(seg):
                self.f((rows[-1][j], rows[-1][(j + 1) % seg], ci), m)
        return rows

    def tube(self, pts, radii, color_fn, mat="wood", seg=8, cap=True):
        m = self.mat(mat)
        P = [Vector(p) for p in pts]
        rows = []
        prev = None
        for k, p in enumerate(P):
            tan = (P[min(k + 1, len(P) - 1)] - P[max(k - 1, 0)]).normalized()
            n = Vector((0, 0, 1)) if abs(tan.z) < 0.9 else Vector((1, 0, 0))
            if prev is not None:
                n = prev
            n = (n - tan * n.dot(tan)).normalized()
            prev = n
            b = tan.cross(n)
            row = []
            for j in range(seg):
                a = TAU * j / seg
                q = p + (n * math.cos(a) + b * math.sin(a)) * radii[k]
                row.append(self.v(q, color_fn(k / max(len(P) - 1, 1), a, q)))
            rows.append(row)
        for k in range(len(rows) - 1):
            a, b = rows[k], rows[k + 1]
            for j in range(seg):
                self.f((a[j], a[(j + 1) % seg], b[(j + 1) % seg], b[j]), m)
        if cap:
            for k, sgn in ((0, -1), (len(rows) - 1, 1)):
                tan = (P[min(k + 1, len(P) - 1)] - P[max(k - 1, 0)]).normalized()
                ci = self.v(P[k] + tan * sgn * radii[k] * 0.5, color_fn(k / max(len(P) - 1, 1), 0.0, P[k]))
                for j in range(seg):
                    if sgn < 0:
                        self.f((rows[k][(j + 1) % seg], rows[k][j], ci), m)
                    else:
                        self.f((rows[k][j], rows[k][(j + 1) % seg], ci), m)

    def ellipsoid(self, center, radii, color_fn, mat="stone", seg=14, rings=10, rot=(0, 0, 0), wobble=0.0, seed=0.0):
        m = self.mat(mat)
        R = Matrix.Rotation(math.radians(rot[2]), 3, "Z") @ Matrix.Rotation(math.radians(rot[1]), 3, "Y") \
            @ Matrix.Rotation(math.radians(rot[0]), 3, "X")
        c = Vector(center)
        grid = []
        for i in range(rings + 1):
            th = math.pi * i / rings
            row = []
            for j in range(seg):
                ph = TAU * j / seg
                u = Vector((math.sin(th) * math.cos(ph), math.sin(th) * math.sin(ph), math.cos(th)))
                k = 1.0 + wobble * noise.noise(u * 1.7 + Vector((seed, seed * 0.5, 0)))
                p = c + R @ Vector((u.x * radii[0] * k, u.y * radii[1] * k, u.z * radii[2] * k))
                if (i == 0 or i == rings) and j > 0:
                    row.append(row[0])
                else:
                    row.append(self.v(p, color_fn(u, p)))
            grid.append(row)
        for i in range(rings):
            for j in range(seg):
                a, b = grid[i][j], grid[i][(j + 1) % seg]
                cc, d = grid[i + 1][(j + 1) % seg], grid[i + 1][j]
                if i == 0:
                    self.f((a, d, cc), m)
                elif i == rings - 1:
                    self.f((a, d, b), m)
                else:
                    self.f((a, d, cc, b), m)

    def box(self, center, size, color_fn, mat="stone", rot_z=0.0, taper=1.0, wobble=0.0, seed=0.0, subdiv=2):
        """Box with optional taper (top scale) and noise; subdivided so it can wobble."""
        m = self.mat(mat)
        c = Vector(center)
        sx, sy, sz = size
        R = Matrix.Rotation(rot_z, 3, "Z")
        n = subdiv
        idx = {}

        def vid(i, j, k):
            key = (i, j, k)
            if key in idx:
                return idx[key]
            u, v, w = i / n * 2 - 1, j / n * 2 - 1, k / n * 2 - 1
            t = (w + 1) * 0.5
            sc = 1.0 + (taper - 1.0) * t
            p = Vector((u * sx * 0.5 * sc, v * sy * 0.5 * sc, w * sz * 0.5))
            if wobble > 0:
                p += Vector((noise.noise(p * 0.8 + Vector((seed, 0, 0))), noise.noise(p * 0.8 + Vector((0, seed, 3))),
                             noise.noise(p * 0.8 + Vector((7, 0, seed))) * 0.5)) * wobble
            p = c + R @ p
            idx[key] = self.v(p, color_fn(Vector((u, v, w)), p))
            return idx[key]

        for a in range(n):
            for b in range(n):
                # -z, +z
                self.f((vid(a, b, 0), vid(a, b + 1, 0), vid(a + 1, b + 1, 0), vid(a + 1, b, 0)), m)
                self.f((vid(a, b, n), vid(a + 1, b, n), vid(a + 1, b + 1, n), vid(a, b + 1, n)), m)
                # -y, +y
                self.f((vid(a, 0, b), vid(a + 1, 0, b), vid(a + 1, 0, b + 1), vid(a, 0, b + 1)), m)
                self.f((vid(a, n, b), vid(a, n, b + 1), vid(a + 1, n, b + 1), vid(a + 1, n, b)), m)
                # -x, +x
                self.f((vid(0, a, b), vid(0, a, b + 1), vid(0, a + 1, b + 1), vid(0, a + 1, b)), m)
                self.f((vid(n, a, b), vid(n, a + 1, b), vid(n, a + 1, b + 1), vid(n, a, b + 1)), m)

    def leaf_fan(self, base, direction, length, width, color_a, color_b, mat="leaf", segs=6, leaflets=9, droop=0.4):
        """Carnaúba-style palmate frond: leaflets radiating from a point, drooping at the tips.
        Alpha channel of the color = wind weight (0 at the base, 1 at the tips)."""
        m = self.mat(mat)
        d = Vector(direction).normalized()
        side = d.cross(Vector((0, 0, 1)))
        if side.length < 1e-3:
            side = Vector((1, 0, 0))
        side.normalize()
        up = side.cross(d).normalized()
        b = Vector(base)
        for k in range(leaflets):
            a = (k / (leaflets - 1) - 0.5) * 1.9
            ld = (d * math.cos(a) + side * math.sin(a)).normalized()
            prev = []
            for s in range(segs + 1):
                t = s / segs
                p = b + ld * length * t - up * droop * length * t * t
                w = width * math.sin(math.pi * min(1.0, t * 1.15 + 0.08)) * 0.5
                col = mix(color_a, color_b, t) + (t,)
                left = self.v(p + side.cross(ld).normalized() * 0.0 + (ld.cross(up)).normalized() * w, col)
                right = self.v(p - (ld.cross(up)).normalized() * w, col)
                mid = self.v(p + up * w * 0.25, col)
                cur = [left, mid, right]
                if prev:
                    self.f((prev[0], prev[1], cur[1], cur[0]), m)
                    self.f((prev[1], prev[2], cur[2], cur[1]), m)
                prev = cur

    # ------------------------------------------------------------ output
    def build(self, mats: dict, name: str | None = None) -> bpy.types.Object:
        nm = name or self.name
        mesh = bpy.data.meshes.new(nm)
        mesh.from_pydata([tuple(v) for v in self.verts], [], self.faces)
        mesh.validate(clean_customdata=False)
        mesh.update()
        obj = bpy.data.objects.new(nm, mesh)
        bpy.context.scene.collection.objects.link(obj)
        for mn in self.materials:
            mesh.materials.append(mats[mn])
        if self.face_mat:
            mesh.polygons.foreach_set("material_index", self.face_mat[:len(mesh.polygons)])
        mesh.polygons.foreach_set("use_smooth", [True] * len(mesh.polygons))
        if hasattr(mesh, "use_auto_smooth"):
            mesh.use_auto_smooth = True
            mesh.auto_smooth_angle = math.radians(48)
        attr = mesh.color_attributes.new(name="Col", type="FLOAT_COLOR", domain="POINT")
        flat = []
        for c in self.colors:
            flat.extend(c if len(c) == 4 else (*c, 1.0))
        attr.data.foreach_set("color", flat)
        mesh.color_attributes.active_color = attr
        try:
            mesh.color_attributes.render_color_index = mesh.color_attributes.find("Col")
        except Exception:
            pass
        return obj


def stone_color(base, top=(1.0, 0.93, 0.84), dark=(0.55, 0.32, 0.30), seed=0.0, bands=0.0):
    """Sandstone tint: sand on top-facing parts, darker at the bottom, optional strata."""
    def fn(_i, _a, p):
        n = 0.5 + 0.5 * noise.noise(Vector((p.x * 0.9, p.y * 0.9, p.z * 0.9 + seed)))
        col = mix(base, dark, 0.25 * (1 - n))
        if bands > 0:
            band = math.sin(p.z * bands + n * 2.0) * 0.5 + 0.5
            col = mix(col, mix(base, (1.0, 0.86, 0.7), 0.6), smooth01(band * 1.4 - 0.3) * 0.5)
        return col
    return fn
