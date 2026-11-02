"""SOPRO — gera as ilhas flutuantes dos 'Lençóis do Céu' a partir da receita.

    blender -b --factory-startup --python game/blender/build_world.py [-- --only IlhaSino]

Cada ilha = tampa de dunas (anéis concêntricos com densidade uniforme, dunas
barcanas assimétricas, lagoas escavadas, platôs para estruturas) + borda
arredondada + "raiz" de arenito pendurada (cone com caneluras e saliências).
Cores por vértice (COLOR_0, lidas pelos shaders do jogo):
    R = oclusão ambiente (raycast)   G = areia molhada / fundo de lagoa
    B = rocha (0 = topo de areia, 1 = penhasco/raiz)   A = máscara de grama
Saída: game/assets/world/<Ilha>.glb e far_islands.glb (ilhas distantes, 1 malha).
"""
from __future__ import annotations

import json
import math
import random
import sys
from pathlib import Path

import bpy
from mathutils import Vector, noise

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from bhelpers import (ASSETS, GAME, bake_vertex_ao, clamp, export_glb, log, material,  # noqa: E402
                      mesh_object, reset_scene, set_point_colors, set_smooth, smoothstep)

RECIPE = GAME / "world" / "lencois.json"
OUT = ASSETS / "world"
TAU = math.tau


def n3(x, y, z) -> float:
    return noise.noise(Vector((x, y, z)))


class Island:
    def __init__(self, d: dict, water: float, far: bool = False):
        self.d = d
        self.name = d.get("name", "Far")
        self.R = float(d["radius"])
        self.seed = float(d.get("seed", 1)) * 1.731
        self.base = float(d.get("base", 1.5))
        self.amp = float(d.get("dune_amp", 3.0))
        self.freq = float(d.get("dune_freq", 0.06))
        w = math.radians(float(d.get("wind_deg", 30)))
        self.wind = (math.cos(w), math.sin(w))
        self.depth = float(d.get("depth", 50))
        self.spacing = float(d.get("spacing", 1.1))
        self.lagoons = d.get("lagoons", [])
        self.flats = d.get("flats", [])
        self.water = water
        self.far = far

    # ---------------------------------------------------------------- shape
    def outline(self, th: float) -> float:
        """Noisy island radius for angle th (closed curve: noise sampled on a circle)."""
        c, s = math.cos(th), math.sin(th)
        k = 1.0 + 0.13 * n3(c * 1.3, s * 1.3, self.seed) + 0.06 * n3(c * 3.1, s * 3.1, self.seed + 4.0)
        return self.R * k

    def lagoon_radius(self, lg: dict, dx: float, dz: float) -> float:
        a = math.atan2(dz, dx)
        return lg["r"] * (1.0 + 0.2 * n3(math.cos(a) * 1.7, math.sin(a) * 1.7, self.seed + lg["r"]))

    def dunes(self, x: float, z: float) -> float:
        wx, wz = self.wind
        sd = self.seed
        warp = n3(x * 0.018, z * 0.018, sd) * 10.0 + n3(x * 0.05, z * 0.05, sd + 3.0) * 3.0
        along = x * wx + z * wz
        across = -x * wz + z * wx
        # crescent (barchan) bending of the crest lines
        bend = 0.010 * across * across * (0.6 + 0.4 * n3(across * 0.02, 0.0, sd + 5.0))
        ph = (along + warp - bend) * self.freq
        fr = ph - math.floor(ph)
        crest = 0.74
        if fr < crest:
            prof = (fr / crest) ** 1.6                       # long windward slope
        else:
            prof = ((1.0 - fr) / (1.0 - crest)) ** 0.85      # steep slip face
        prof = prof * prof * (3.0 - 2.0 * prof) * 0.35 + prof * 0.65
        amp_mod = 0.5 + 0.5 * (0.5 + 0.5 * n3(x * 0.013, z * 0.013, sd + 7.0))
        breakup = 0.55 + 0.45 * (0.5 + 0.5 * n3(across * 0.035, ph * 0.3, sd + 11.0))
        h = self.amp * prof * amp_mod * breakup
        h += 0.45 * n3(x * 0.07, z * 0.07, sd + 13.0) + 0.15 * n3(x * 0.2, z * 0.2, sd + 17.0)
        return h

    def top(self, x: float, z: float, t: float):
        """Top height (Godot y, island-local) + masks (wet, grass_hint)."""
        h = self.base + self.dunes(x, z)
        wet = 0.0
        grass = 0.0
        for lg in self.lagoons:
            cx, cz = lg["at"]
            dx, dz = x - cx, z - cz
            dist = math.hypot(dx, dz)
            r = self.lagoon_radius(lg, dx, dz)
            # dunes calm down around lagoons
            calm = smoothstep(r * 2.6, r * 1.15, dist)
            h = h + (self.base + 0.25 - h) * calm * 0.75
            # bowl
            inside = smoothstep(r * 1.18, r * 0.62, dist)
            bowl = 1.0 - min(1.0, (dist / max(r, 0.1)) ** 2)
            bottom = self.water - lg["depth"] * (0.35 + 0.65 * bowl)
            h = h + (bottom - h) * inside
            wet = max(wet, smoothstep(r * 1.45, r * 0.95, dist))
            band = smoothstep(r * 0.98, r * 1.25, dist) * smoothstep(r * 2.3, r * 1.4, dist)
            grass = max(grass, band)
        for fl in self.flats:
            cx, cz = fl["at"]
            dist = math.hypot(x - cx, z - cz)
            f = smoothstep(fl["r"] * 1.7, fl["r"] * 0.95, dist)
            h = h + (fl["h"] - h) * f
            grass *= 1.0 - f
        # rounded lip towards the rim
        rim_h = self.base * 0.55
        e = smoothstep(0.84, 1.0, t)
        h = h + (rim_h - h) * e * e
        grass *= 1.0 - smoothstep(0.8, 0.93, t)
        return h, wet, grass

    # ---------------------------------------------------------------- mesh
    def build(self, offset=Vector((0, 0, 0))):
        sp = self.spacing
        M = max(4, int(round(self.R / sp)))
        verts: list[Vector] = []
        rock: list[float] = []
        wetl: list[float] = []
        grassl: list[float] = []
        faces: list[tuple] = []
        rings: list[tuple[list[int], list[float]]] = []

        def add(v: Vector, r=0.0, w=0.0, g=0.0) -> int:
            verts.append(v + offset)
            rock.append(r)
            wetl.append(w)
            grassl.append(g)
            return len(verts) - 1

        # center vertex (Blender XY; Godot local x = bx, z = -by)
        h0, w0, g0 = self.top(0.0, 0.0, 0.0)
        rings.append(([add(Vector((0, 0, h0)), 0, w0, g0)], [0.0]))
        rim_ang: list[float] = []
        for i in range(1, M + 1):
            t = i / M
            n = max(8, int(round(TAU * t * self.R / sp)))
            off = 0.5 * (i % 2)
            idx, angs = [], []
            for j in range(n):
                th = (j + off) / n * TAU
                r = t * self.outline(th)
                bx, by = r * math.cos(th), r * math.sin(th)
                h, w, g = self.top(bx, -by, t)
                idx.append(add(Vector((bx, by, h)), 0.0, w, g))
                angs.append(th)
            rings.append((idx, angs))
            if i == M:
                rim_ang = angs
        rim_h = self.base * 0.55
        # underside rings: lip, cliff and the hanging sandstone root
        n_rim = len(rim_ang)
        K = 24 if not self.far else 12
        lip = [(1.012, -0.35), (1.008, -0.9)]
        for k, (scale, dz) in enumerate(lip):
            idx, angs = [], []
            for th in rim_ang:
                r = self.outline(th) * scale
                idx.append(add(Vector((r * math.cos(th), r * math.sin(th), rim_h + dz)), 1.0))
                angs.append(th)
            rings.append((idx, angs))
        z0 = rim_h - 0.9
        for k in range(1, K + 1):
            u = k / K
            if k == K:
                tip = Vector((n3(self.seed, 1, 2) * self.R * 0.08, n3(self.seed, 3, 4) * self.R * 0.08,
                              z0 - self.depth))
                rings.append(([add(tip, 1.0)], [0.0]))
                break
            n = max(8, int(round(n_rim * (0.35 + 0.65 * (1.0 - u)) * (0.6 if not self.far else 0.5))))
            rf = (1.0 - u ** 1.1) ** 0.55
            z = z0 - self.depth * u ** 1.25
            idx, angs = [], []
            for j in range(n):
                th = (j + 0.5 * (k % 2)) / n * TAU
                c, s = math.cos(th), math.sin(th)
                amp = 0.08 + 0.3 * u
                lobes = n3(c * 1.5, s * 1.5, self.seed + u * 1.8)
                flutes = n3(c * 7.0, s * 7.0, z * 0.06 + self.seed)
                ledge = 0.0
                if u < 0.55:
                    fz = (z / 3.1) - math.floor(z / 3.1)
                    ledge = 0.05 * smoothstep(0.75, 1.0, fz) * (1.0 - u / 0.55)
                r = self.outline(th) * rf * (1.0 + amp * (0.65 * lobes + 0.35 * flutes) + ledge)
                idx.append(add(Vector((r * c, r * s, z)), 1.0))
                angs.append(th)
            rings.append((idx, angs))

        for a, b in zip(rings[:-1], rings[1:]):
            zip_rings(a, b, faces)

        obj = mesh_object(self.name, verts, faces)
        # outward normals (closed surface)
        import bmesh
        bm = bmesh.new()
        bm.from_mesh(obj.data)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(obj.data)
        bm.free()
        set_smooth(obj, 62.0 if not self.far else 70.0)
        # crisp edge between sand cap and cliff
        rim_set = set(rings[M][0])
        lip_set = set(rings[M + 1][0])
        for e in obj.data.edges:
            a, b = e.vertices
            if (a in rim_set and b in lip_set) or (a in lip_set and b in rim_set):
                e.use_edge_sharp = True
        obj.data.update()
        return obj, rock, wetl, grassl


def zip_rings(a, b, faces) -> None:
    """Triangulates between two closed, angle-sorted loops (any vertex counts)."""
    ai, aa = a
    bi, ba = b
    na, nb = len(ai), len(bi)
    if na == 1:
        for j in range(nb):
            faces.append((ai[0], bi[j], bi[(j + 1) % nb]))
        return
    if nb == 1:
        for i in range(na):
            faces.append((ai[i], ai[(i + 1) % na], bi[0]))
        return
    i = j = 0
    while i < na or j < nb:
        a0, b0 = ai[i % na], bi[j % nb]
        ang_a = aa[(i + 1) % na] + (TAU if i + 1 >= na else 0.0)
        ang_b = ba[(j + 1) % nb] + (TAU if j + 1 >= nb else 0.0)
        if j >= nb or (i < na and ang_a <= ang_b):
            faces.append((a0, ai[(i + 1) % na], b0))
            i += 1
        else:
            faces.append((a0, bi[(j + 1) % nb], b0))
            j += 1


def finish_colors(obj, isl: Island, rock, wet, grass, ao) -> None:
    mesh = obj.data
    cols = []
    for k, v in enumerate(mesh.vertices):
        nz = v.normal.z
        h = v.co.z
        g = grass[k]
        if rock[k] < 0.5:
            # patches + only gentle slopes above the water
            patch = 0.5 + 0.5 * n3(v.co.x * 0.11, v.co.y * 0.11, isl.seed + 31.0)
            g = clamp(g * smoothstep(0.25, 0.75, patch) * smoothstep(0.8, 0.93, nz)
                      * smoothstep(isl.water + 0.25, isl.water + 0.7, h))
            w = clamp(max(wet[k] * smoothstep(isl.water + 1.4, isl.water + 0.15, h),
                          smoothstep(isl.water + 0.05, isl.water - 0.3, h)))
        else:
            g = 0.0
            w = 0.0
        cols.append((ao[k], w, rock[k], g))
    set_point_colors(obj, cols)


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = argv[argv.index("--only") + 1] if "--only" in argv else None
    recipe = json.loads(RECIPE.read_text())
    water = float(recipe.get("water_level", 0.6))
    reset_scene()
    sand = material("island", (0.95, 0.9, 0.85, 1.0))
    for d in recipe["islands"]:
        if only and d["name"] != only:
            continue
        isl = Island(d, water)
        obj, rock, wet, grass = isl.build()
        obj.data.materials.append(sand)
        ao = bake_vertex_ao(obj, rays=12, max_dist=9.0)
        finish_colors(obj, isl, rock, wet, grass, ao)
        log(d["name"], "verts", len(obj.data.vertices), "tris", sum(len(p.vertices) - 2 for p in obj.data.polygons))
        export_glb(OUT / f"{d['name']}.glb", [obj])
    if only and only != "far":
        return
    # distant islands: one merged low-poly mesh in world space
    parts = []
    rnd = random.Random(7)
    for k, d in enumerate(recipe.get("far_islands", [])):
        x, y, z = d["at"]
        dd = {"name": f"Far{k}", "radius": d["radius"], "seed": d["seed"], "base": 1.5,
              "dune_amp": 3.0 + rnd.random() * 4.0, "dune_freq": 0.03, "wind_deg": rnd.random() * 180,
              "depth": d["radius"] * 1.4, "spacing": max(3.0, d["radius"] / 14.0), "lagoons": [], "flats": []}
        isl = Island(dd, water, far=True)
        obj, rock, wet, grass = isl.build(offset=Vector((x, -z, y)))
        cols = [(0.85 + 0.15 * (1.0 - r), 0.0, r, 0.0) for r in rock]
        set_point_colors(obj, cols)
        parts.append(obj)
    if parts:
        bpy.ops.object.select_all(action="DESELECT")
        for p in parts:
            p.select_set(True)
        bpy.context.view_layer.objects.active = parts[0]
        bpy.ops.object.join()
        far = bpy.context.view_layer.objects.active
        far.name = "FarIslands"
        far.data.materials.clear()
        far.data.materials.append(sand)
        log("far islands verts", len(far.data.vertices))
        export_glb(OUT / "far_islands.glb", [far])


if __name__ == "__main__":
    main()
