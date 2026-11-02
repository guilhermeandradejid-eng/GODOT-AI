"""SOPRO — modela, rigga e anima os heróis Juba (mico-leão-dourado) e Caju (capivara).

    blender -b --factory-startup --python game/blender/build_characters.py [-- --only juba]

Saída: game/assets/characters/<nome>.glb (malha com skin + animações) e
game/blender/<nome>.blend (fonte editável no Blender).
Materiais (o jogo troca por shaders próprios pelo nome):
    fur   – pelo/pele (cor por vértice)      eye  – olho (UV: íris/pupila no shader)
    cloth – cachecol, fitinhas (cor por vértice)   chita – manta de chita (textura)
"""
from __future__ import annotations

import math
import sys
from pathlib import Path

import bpy
from mathutils import Vector

sys.path.insert(0, str(Path(__file__).resolve().parent / "lib"))
from bhelpers import ASSETS, GAME, export_glb, log, material, reset_scene  # noqa: E402
from charkit import (BoneDef, MeshBuilder, Rig, bake_action, ease_in_out, ease_out, keys, mirror_pose,  # noqa: E402
                     mix, smooth01, wave)

OUT = ASSETS / "characters"
TAU = math.tau


def mats() -> dict:
    return {
        "fur": material("fur", (0.9, 0.6, 0.3, 1.0)),
        "eye": material("eye", (1.0, 1.0, 1.0, 1.0), roughness=0.1),
        "cloth": material("cloth", (0.1, 0.7, 0.6, 1.0)),
        "chita": material("chita", (0.85, 0.15, 0.2, 1.0)),
        "mane": material("mane", (1.0, 0.6, 0.2, 1.0)),
    }


# =============================================================================
# JUBA — mico-leão-dourado
# =============================================================================
J_GOLD = (1.0, 0.64, 0.18)
J_GOLD_LIGHT = (1.0, 0.80, 0.42)
J_MANE_BASE = (1.0, 0.50, 0.10)
J_MANE_TIP = (1.0, 0.86, 0.48)
J_DARK = (0.24, 0.14, 0.13)
J_MUZZLE = (0.33, 0.20, 0.18)
J_TEAL = (0.04, 0.66, 0.64)
J_TEAL_DARK = (0.02, 0.42, 0.48)
J_STRIPE = (1.0, 0.84, 0.30)
J_PINK = (1.0, 0.45, 0.56)


def juba_rig() -> Rig:
    B = BoneDef
    bones = [
        B("root", (0, 0, 0), (0, -0.15, 0), None, False),
        B("hips", (0, 0.0, 0.40), (0, 0.0, 0.50), "root"),
        B("spine", (0, 0.0, 0.50), (0, -0.005, 0.60), "hips"),
        B("chest", (0, -0.005, 0.60), (0, -0.01, 0.68), "spine"),
        B("neck", (0, -0.01, 0.68), (0, -0.02, 0.72), "chest"),
        B("head", (0, -0.02, 0.72), (0, -0.04, 0.98), "neck"),
        B("eye_L", (0.062, -0.17, 0.83), (0.062, -0.21, 0.83), "head"),
        B("eye_R", (-0.062, -0.17, 0.83), (-0.062, -0.21, 0.83), "head"),
    ]
    for s, x in (("L", 1), ("R", -1)):
        bones += [
            B(f"thigh_{s}", (0.075 * x, 0.0, 0.42), (0.085 * x, -0.02, 0.24), "hips"),
            B(f"shin_{s}", (0.085 * x, -0.02, 0.24), (0.085 * x, 0.01, 0.07), f"thigh_{s}"),
            B(f"foot_{s}", (0.085 * x, 0.01, 0.07), (0.085 * x, -0.085, 0.02), f"shin_{s}"),
            B(f"upperarm_{s}", (0.10 * x, 0.0, 0.64), (0.19 * x, -0.01, 0.53), "chest"),
            B(f"forearm_{s}", (0.19 * x, -0.01, 0.53), (0.26 * x, -0.03, 0.42), f"upperarm_{s}"),
            B(f"hand_{s}", (0.26 * x, -0.03, 0.42), (0.29 * x, -0.05, 0.35), f"forearm_{s}"),
        ]
    tail = [(0, 0.08, 0.42), (0, 0.19, 0.37), (0, 0.31, 0.37), (0, 0.41, 0.43), (0, 0.49, 0.53),
            (0, 0.54, 0.65), (0, 0.55, 0.77), (0, 0.52, 0.88)]
    for i in range(len(tail) - 1):
        bones.append(B(f"tail_{i + 1}", tail[i], tail[i + 1], "hips" if i == 0 else f"tail_{i}"))
    scarf = [(0, 0.075, 0.665), (0, 0.15, 0.625), (0, 0.22, 0.575), (0, 0.28, 0.515), (0, 0.33, 0.45), (0, 0.37, 0.385)]
    for i in range(len(scarf) - 1):
        bones.append(B(f"scarf_{i + 1}", scarf[i], scarf[i + 1], "chest" if i == 0 else f"scarf_{i}"))
    rig = Rig(bones)
    rig.tail_pts = tail
    rig.scarf_pts = scarf
    return rig


def juba_mesh(rig: Rig) -> MeshBuilder:
    mb = MeshBuilder(rig)
    head_c = Vector((0, -0.03, 0.82))
    # head + dark face + muzzle
    mb.ellipsoid(head_c, (0.155, 0.142, 0.148), J_GOLD, {"head": 1.0}, seg=20, rings=14,
                 color_fn=lambda u: mix(J_GOLD, J_GOLD_LIGHT, max(0.0, -u.z) * 0.6))
    mb.ellipsoid((0, -0.112, 0.80), (0.104, 0.07, 0.108), J_DARK, {"head": 1.0}, seg=18, rings=12,
                 shape=lambda p: (p[0] * (1.0 - 0.18 * max(0.0, -p[2]) / 0.108), p[1], p[2]))
    mb.ellipsoid((0, -0.168, 0.762), (0.056, 0.042, 0.042), J_MUZZLE, {"head": 1.0}, seg=14, rings=10)
    mb.ellipsoid((0, -0.205, 0.775), (0.016, 0.008, 0.01), J_DARK, {"head": 1.0}, seg=8, rings=6)   # nose
    # brows: little dark ridges give expression
    for x in (1, -1):
        mb.tuft((0.035 * x, -0.17, 0.878), (0.6 * x, -0.25, 0.1), 0.05, 0.012, J_DARK, J_DARK, {"head": 1.0},
                sides=4, segs=2, flat=0.5)
    # eyes (UV-mapped, iris/pupil drawn by the eye shader)
    for s, x in (("L", 1), ("R", -1)):
        mb.ellipsoid((0.064 * x, -0.17, 0.832), (0.043, 0.026, 0.051), (1, 1, 1), {f"eye_{s}": 1.0, "head": 0.0},
                     mat="eye", seg=18, rings=14, uv_mode="front", rot=(0, 0, -12 * x))
    # mane: rings of curved tufts framing the face + back crest
    import random
    rnd = random.Random(4)

    def ring(n, polar, length, width, back_bias, up_boost=0.0, jitter=0.15):
        for k in range(n):
            a = TAU * (k + rnd.random() * 0.3) / n
            pol = math.radians(polar + rnd.uniform(-8, 8))
            # direction from head centre: around the face axis (-Y)
            radial = Vector((math.cos(a), 0, math.sin(a)))
            dirv = (Vector((0, -1, 0)) * math.cos(pol) + radial * math.sin(pol)).normalized()
            base = head_c + Vector((dirv.x * 0.15, dirv.y * 0.14, dirv.z * 0.145))
            up = max(0.0, math.sin(a))
            ln = length * (1.0 + up_boost * up) * rnd.uniform(1 - jitter, 1 + jitter)
            if math.sin(a) < -0.6:      # shorter under the chin
                ln *= 0.55
            out = (dirv + Vector((0, back_bias, 0))).normalized()
            bend = Vector((0, 0.35, 0.15 * up - 0.1))
            mb.tuft(base, out, ln, width * rnd.uniform(0.85, 1.15), J_MANE_BASE, J_MANE_TIP,
                    {"head": 1.0}, mat="mane", bend=bend, sides=6, segs=3, flat=0.7)

    # soft mane volume behind the face (front flattened so the face peeks out)
    mb.ellipsoid(head_c + Vector((0, 0.035, 0.012)), (0.205, 0.16, 0.205), J_MANE_BASE, {"head": 1.0}, mat="mane",
                 seg=20, rings=14, shape=lambda p: (p[0], p[1] * (0.35 if p[1] < 0 else 1.0), p[2]),
                 color_fn=lambda u: mix(J_MANE_BASE, J_MANE_TIP, smooth01(0.5 + 0.5 * u.z) * 0.5))
    ring(16, 70, 0.07, 0.055, 0.3, 0.35)
    ring(20, 98, 0.095, 0.062, 0.55, 0.45)
    ring(18, 128, 0.1, 0.064, 0.9, 0.25)
    ring(12, 158, 0.085, 0.06, 1.1, 0.0)
    # torso
    mb.ellipsoid((0, 0.0, 0.55), (0.122, 0.108, 0.152), J_GOLD, ["hips", "spine", "chest"], seg=18, rings=14,
                 color_fn=lambda u: mix(J_GOLD, J_GOLD_LIGHT, smooth01(-u.y * 1.4)),
                 shape=lambda p: (p[0] * (1.0 + 0.12 * max(0.0, -p[2]) / 0.148), p[1] - 0.012 * max(0.0, -p[2]) / 0.148, p[2]))
    # chest fluff (mane continues on the chest)
    for k in range(0):
        a = -0.6 + 1.2 * k / 6
        base = Vector((0.06 * a, -0.085, 0.63 - abs(a) * 0.02))
        mb.tuft(base, (a * 0.4, -0.6, -0.8), 0.07, 0.035, J_MANE_BASE, J_MANE_TIP, {"chest": 0.7, "neck": 0.3},
                mat="mane", bend=(0, 0.1, 0), sides=5, segs=2, flat=0.7)
    # arms / legs
    for s, x in (("L", 1), ("R", -1)):
        mb.tube([(0.09 * x, 0.0, 0.635), (0.19 * x, -0.01, 0.53), (0.26 * x, -0.03, 0.42)], [0.037, 0.031, 0.027],
                J_GOLD, [f"upperarm_{s}", f"forearm_{s}"], seg=10, per_bone=4, cap_start=False,
                color_fn=lambda f, a: mix(J_GOLD, J_DARK, smooth01((f - 0.55) * 2.2)))
        mb.ellipsoid((0.272 * x, -0.042, 0.385), (0.036, 0.028, 0.044), J_DARK, {f"hand_{s}": 1.0}, seg=12, rings=10)
        for k, (fx, fz) in enumerate(((0.012, 0.0), (0.0, -0.012), (-0.012, 0.0))):
            mb.ellipsoid((0.272 * x + fx * x, -0.06 + k * 0.002, 0.345 + fz), (0.012, 0.012, 0.022), J_DARK,
                         {f"hand_{s}": 1.0}, seg=8, rings=6)
        mb.tube([(0.075 * x, 0.0, 0.44), (0.085 * x, -0.02, 0.24), (0.085 * x, 0.01, 0.07)], [0.058, 0.043, 0.032],
                J_GOLD, [f"thigh_{s}", f"shin_{s}"], seg=10, per_bone=4, cap_start=False,
                color_fn=lambda f, a: mix(J_GOLD, J_DARK, smooth01((f - 0.6) * 2.5)))
        mb.ellipsoid((0.085 * x, -0.035, 0.035), (0.04, 0.078, 0.032), J_DARK, {f"foot_{s}": 1.0}, seg=12, rings=10)
        # bonfim wrist ribbons
        cols = [(0.95, 0.15, 0.2), (1.0, 0.85, 0.2), (0.15, 0.45, 0.95)]
        for k, c in enumerate(cols):
            p = Vector((0.252 * x, -0.027, 0.432)) + Vector((0.06 * x, -0.02, -0.09)).normalized() * (k * 0.012 - 0.012)
            mb.ring(p, (0.06 * x, -0.02, -0.09), 0.03, 0.0055, c, {f"forearm_{s}": 1.0}, mat="cloth", seg=12, tseg=4)
    # tail (long, curling up) + fluffy tip
    tp = rig.tail_pts
    mb.tube(tp, [0.034, 0.032, 0.03, 0.028, 0.027, 0.026, 0.026, 0.03], J_GOLD,
            [f"tail_{i + 1}" for i in range(len(tp) - 1)], seg=9, per_bone=3,
            color_fn=lambda f, a: mix(J_GOLD, J_MANE_BASE, smooth01((f - 0.7) * 3.0)))
    tip = Vector(tp[-1])
    mb.ellipsoid(tip + Vector((0, -0.005, 0.015)), (0.045, 0.045, 0.06), J_MANE_BASE, {"tail_7": 1.0}, mat="mane",
                 seg=12, rings=9, color_fn=lambda u: mix(J_MANE_BASE, J_MANE_TIP, smooth01(0.5 + 0.5 * u.z)))
    for k in range(5):
        a = TAU * k / 5
        mb.tuft(tip + Vector((math.cos(a) * 0.02, math.sin(a) * 0.02, 0.03)),
                (math.cos(a) * 0.35, -0.15 + math.sin(a) * 0.35, 1.0), 0.06, 0.03,
                J_MANE_BASE, J_MANE_TIP, {"tail_7": 1.0}, mat="mane", sides=5, segs=2, flat=0.7)
    # scarf: collar + trailing ribbon (teal with golden stripes and pink fringe)
    mb.ring((0, -0.005, 0.665), (0, 0.05, 1), 0.085, 0.03, J_TEAL, {"chest": 0.6, "neck": 0.4}, mat="cloth",
            seg=18, tseg=7, color_fn=lambda f: J_TEAL if (f * 9) % 1.0 > 0.18 else J_STRIPE)
    sp = rig.scarf_pts
    pts = []
    for i in range(len(sp) - 1):
        a, b = Vector(sp[i]), Vector(sp[i + 1])
        for k in range(3):
            pts.append(a.lerp(b, k / 3))
    pts.append(Vector(sp[-1]))
    n = len(pts)

    def scarf_w(i):
        seg = min(int(i / 3), len(sp) - 2)
        t = (i % 3) / 3
        w = {f"scarf_{seg + 1}": 1.0 - 0.5 * t}
        if seg + 2 <= len(sp) - 1:
            w[f"scarf_{seg + 2}"] = 0.5 * t
        return w

    def scarf_col(i, side):
        v = i / (n - 1)
        if v > 0.9:
            return J_PINK
        if 0.62 < v < 0.7 or 0.76 < v < 0.8:
            return J_STRIPE
        return mix(J_TEAL, J_TEAL_DARK, v * 0.4)

    mb.ribbon(pts, [0.075 + 0.04 * (i / (n - 1)) for i in range(n)], lambda i: (1, 0, 0), scarf_col, scarf_w,
              mat="cloth", thickness=0.006)
    return mb


def juba_anims(rig_obj) -> None:
    arm_rest = 0.0

    def base():
        return {}

    # ------------------------------------------------------------------ idle
    def idle(t, ph):
        b = wave(ph)
        look = keys(ph, [(0, 0), (0.18, 0), (0.3, 18), (0.55, 18), (0.68, -14), (0.88, -14), (1.0, 0)])
        tilt = keys(ph, [(0, 0), (0.32, 6), (0.55, 6), (0.7, -5), (0.9, -5), (1.0, 0)])
        p = {
            "hips": (0, 0, 2 * wave(ph, 0.25), (0, 0.004 * b, 0)),
            "spine": (2 + 1.5 * b, 0, -1.5 * wave(ph, 0.25)),
            "chest": (1 + 1.5 * b, look * 0.15, 0, None, (1 + 0.012 * b, 1, 1 + 0.012 * b)),
            "neck": (-2, look * 0.3, 0),
            "head": (-3 - 1.5 * b, look * 0.55, tilt),
            "upperarm_L": (4 + 3 * b, 0, -6), "forearm_L": (-22 - 4 * b, 0, 0), "hand_L": (-10, 0, 0),
            "thigh_L": (-4, 0, -3), "shin_L": (6, 0, 0), "foot_L": (-2, 0, 0),
        }
        p = mirror_pose(p)
        p["upperarm_R"] = (4 - 3 * b, 0, 6)
        for i in range(7):
            p[f"tail_{i + 1}"] = (2 + 4 * wave(ph, -i * 0.08), 0, 10 * wave(ph, 0.1 - i * 0.1))
        for i in range(5):
            p[f"scarf_{i + 1}"] = (3 * wave(ph, -i * 0.1), 0, 4 * wave(ph, 0.2 - i * 0.12))
        return p

    # ------------------------------------------------------------------ locomotion
    def locomotion(ph, run: bool):
        A = 52 if run else 26
        K = 95 if run else 45
        AA = 58 if run else 24
        s = math.sin(TAU * ph)
        c2 = math.cos(2 * TAU * ph)
        lean = 14 if run else 3
        bob = (0.035 if run else 0.012) * -c2
        p = {
            "hips": (lean * 0.4, 7 * s, 3 * math.sin(TAU * (ph + 0.25)), (0, bob, 0)),
            "spine": (lean * 0.5, -5 * s, 0),
            "chest": (lean * 0.4 + (3 if run else 1) * c2, -7 * s, 0),
            "neck": (-lean * 0.4, 3 * s, 0),
            "head": (-lean * 0.7 - (4 if run else 1.5) * c2, 4 * s, 0),
        }
        for side, off in (("L", 0.0), ("R", 0.5)):
            q = ph + off
            sw = math.sin(TAU * q)
            swing_bend = max(0.0, math.cos(TAU * q)) ** 1.4
            thigh = -A * sw - (8 if run else 2)
            shin = 6 + K * swing_bend
            foot = -0.55 * (thigh + shin) + (25 if run else 12) * max(0.0, -math.cos(TAU * (q + 0.12)))
            sgn = 1 if side == "L" else -1
            p[f"thigh_{side}"] = (thigh, 0, 0)
            p[f"shin_{side}"] = (shin, 0, 0)
            p[f"foot_{side}"] = (foot, 0, 0)
            arm = AA * sw
            p[f"upperarm_{side}"] = (arm + (10 if run else 0), 0, -sgn * (10 if run else 4))
            p[f"forearm_{side}"] = (-(70 if run else 20) - 25 * max(0.0, -sw), 0, 0)
            p[f"hand_{side}"] = (-10, 0, 0)
        for i in range(7):
            p[f"tail_{i + 1}"] = ((-6 if run else 2) + (10 if run else 5) * math.sin(TAU * (2 * ph - i * 0.1)), 0,
                                  (6 if run else 8) * math.sin(TAU * (ph - i * 0.09)))
        for i in range(5):
            p[f"scarf_{i + 1}"] = ((-18 if run else -4) + 6 * math.sin(TAU * (2 * ph - i * 0.15)), 0,
                                   5 * math.sin(TAU * (ph - i * 0.1)))
        return p

    # ------------------------------------------------------------------ air
    def jump(t, ph):
        k = ease_out(ph)
        p = {
            "hips": (keys(ph, [(0, -6), (1, 4)]), 0, 0, (0, 0.03 * (1 - k), 0)),
            "spine": (keys(ph, [(0, -8), (1, 6)]), 0, 0),
            "chest": (keys(ph, [(0, -6), (1, 4)]), 0, 0),
            "head": (keys(ph, [(0, -12), (1, 2)]), 0, 0),
            "thigh_L": (keys(ph, [(0, 18), (0.5, -45), (1, -70)]), 0, -4),
            "shin_L": (keys(ph, [(0, 8), (0.5, 80), (1, 105)]), 0, 0),
            "foot_L": (keys(ph, [(0, 30), (1, -20)]), 0, 0),
            "upperarm_L": (keys(ph, [(0, -150), (1, -105)]), 0, keys(ph, [(0, -40), (1, -70)])),
            "forearm_L": (keys(ph, [(0, -5), (1, -30)]), 0, 0),
        }
        p = mirror_pose(p)
        p["thigh_R"] = (keys(ph, [(0, 25), (0.5, -20), (1, -40)]), 0, 4)
        p["shin_R"] = (keys(ph, [(0, 5), (0.5, 60), (1, 80)]), 0, 0)
        for i in range(7):
            p[f"tail_{i + 1}"] = (keys(ph, [(0, -14), (1, 8)]), 0, 0)
        for i in range(5):
            p[f"scarf_{i + 1}"] = (keys(ph, [(0, 25), (1, -10)]), 0, 0)
        return p

    def fall(t, ph):
        s = wave(ph)
        p = {
            "hips": (4, 0, 2 * s),
            "spine": (2, 0, 0), "chest": (-4, 0, 0), "head": (14, 0, 4 * wave(ph, 0.2)),
            "upperarm_L": (-60 + 10 * s, 0, -55 - 10 * wave(ph, 0.3)),
            "forearm_L": (-55 + 12 * wave(ph, 0.25), 0, 0), "hand_L": (-15, 0, 0),
            "thigh_L": (-30 + 16 * s, 0, -6), "shin_L": (50 + 15 * wave(ph, 0.3), 0, 0), "foot_L": (10, 0, 0),
        }
        p = mirror_pose(p)
        p["upperarm_R"] = (-60 - 10 * s, 0, 55 + 10 * wave(ph, 0.3))
        p["thigh_R"] = (-30 - 16 * s, 0, 6)
        p["shin_R"] = (50 - 15 * wave(ph, 0.3), 0, 0)
        for i in range(7):
            p[f"tail_{i + 1}"] = (-10 + 8 * wave(ph, -i * 0.1), 0, 6 * wave(ph, 0.3 - i * 0.1))
        for i in range(5):
            p[f"scarf_{i + 1}"] = (-25 + 6 * wave(ph, -i * 0.15), 0, 5 * wave(ph, 0.2 - i * 0.1))
        return p

    def land(t, ph):
        sq = keys(ph, [(0, 1), (0.2, 1.0), (1, 0)])
        p = {
            "hips": (10 * sq, 0, 0, (0, -0.075 * sq, 0)),
            "spine": (14 * sq, 0, 0), "chest": (6 * sq, 0, 0), "head": (-16 * sq, 0, 0),
            "thigh_L": (-45 * sq, 0, -6 * sq), "shin_L": (85 * sq, 0, 0), "foot_L": (-35 * sq, 0, 0),
            "upperarm_L": (-35 * sq, 0, -30 * sq), "forearm_L": (-30 * sq - 15, 0, 0),
        }
        p = mirror_pose(p)
        for i in range(7):
            p[f"tail_{i + 1}"] = (12 * sq * (1 - i / 10), 0, 0)
        for i in range(5):
            p[f"scarf_{i + 1}"] = (18 * sq, 0, 0)
        return p

    def double_jump(t, ph):
        flip = 360 * ease_in_out(ph)
        tuck = math.sin(math.pi * min(1.0, ph * 1.15))
        p = {
            "hips": (flip, 0, 0, (0, 0.12 * tuck, 0)),
            "spine": (20 * tuck, 0, 0), "chest": (15 * tuck, 0, 0), "head": (20 * tuck, 0, 0),
            "thigh_L": (-110 * tuck, 0, -8), "shin_L": (130 * tuck, 0, 0), "foot_L": (20 * tuck, 0, 0),
            "upperarm_L": (-40 * tuck, 0, -20), "forearm_L": (-110 * tuck, 0, 0),
        }
        p = mirror_pose(p)
        for i in range(7):
            p[f"tail_{i + 1}"] = (-16 * tuck, 0, 0)
        for i in range(5):
            p[f"scarf_{i + 1}"] = (-30 * tuck, 0, 0)
        return p

    def glide(t, ph):
        s = wave(ph)
        p = {
            "hips": (-8, 0, 4 * s), "spine": (-4, 0, -2 * s), "chest": (-6, 0, 0),
            "neck": (4, 0, 0), "head": (16, 3 * wave(ph, 0.25), 0),
            "upperarm_L": (-160, 0, -38), "forearm_L": (-18, 0, 0), "hand_L": (-20, 0, 0),
            "thigh_L": (-12 + 14 * s, 0, -4), "shin_L": (25 + 12 * wave(ph, 0.2), 0, 0), "foot_L": (25, 0, 0),
        }
        p = mirror_pose(p)
        p["thigh_R"] = (-12 - 14 * s, 0, 4)
        p["shin_R"] = (25 - 12 * wave(ph, 0.2), 0, 0)
        for i in range(7):
            p[f"tail_{i + 1}"] = (-18 + 10 * wave(ph, -i * 0.12), 0, 10 * wave(ph, 0.25 - i * 0.12))
        for i in range(5):
            p[f"scarf_{i + 1}"] = (-40 + 10 * wave(ph, -i * 0.18), 0, 10 * wave(ph, -i * 0.15))
        return p

    def spin(t, ph):
        k = ease_out(min(1.0, ph * 1.1))
        ext = math.sin(math.pi * ph)
        p = {
            "hips": (6, 360 * k, 0, (0, 0.03 * ext, 0)),
            "spine": (6, 0, 0), "head": (-6, -30 * ext, 0),
            "upperarm_L": (-30, 0, -70 * ext), "forearm_L": (-10, 0, 0),
            "thigh_L": (-20 * ext, 0, -10 * ext), "shin_L": (40 * ext, 0, 0),
        }
        p = mirror_pose(p)
        for i in range(7):
            p[f"tail_{i + 1}"] = (-12 * ext, 0, -14 * ext)
        return p

    def ride(t, ph):
        s = wave(ph)
        b = wave(ph * 2)
        p = {
            "hips": (-6, 0, 2 * s, (0, -0.02 + 0.01 * b, 0)),
            "spine": (6 + 3 * b, 4 * s, 0), "chest": (4, 4 * s, 0), "head": (-8, 10 * wave(ph, 0.25), 5 * s),
            "thigh_L": (-78, 0, -38), "shin_L": (82, 0, 0), "foot_L": (20, 0, 0),
            "upperarm_L": (-120 + 30 * b, 0, -30 - 10 * b), "forearm_L": (-40, 0, 0),
        }
        p = mirror_pose(p)
        p["upperarm_R"] = (-30, 0, 18)
        p["forearm_R"] = (-60, 0, 0)
        for i in range(7):
            p[f"tail_{i + 1}"] = (-4 + 6 * wave(ph, -i * 0.1), 0, 12 * wave(ph, -i * 0.1))
        return p

    def celebrate(t, ph):
        hop = max(0.0, math.sin(TAU * ph * 2)) if ph < 0.5 else 0.0
        arms = keys(ph, [(0, -40), (0.12, -170), (0.6, -170), (0.75, -120), (0.9, -170), (1.0, -160)])
        p = {
            "hips": (-4, 0, 0, (0, 0.09 * hop, 0)),
            "spine": (-6, 0, 0), "chest": (-8, 0, 0), "head": (-14, 0, 6 * wave(ph * 2)),
            "upperarm_L": (arms, 0, -22), "forearm_L": (-20 - 25 * hop, 0, 0),
            "thigh_L": (-20 * hop, 0, -6), "shin_L": (40 * hop, 0, 0),
        }
        p = mirror_pose(p)
        for i in range(7):
            p[f"tail_{i + 1}"] = (-8, 0, 20 * wave(ph * 3, -i * 0.12))
        return p

    def hurt(t, ph):
        k = keys(ph, [(0, 0), (0.25, 1), (1, 0)])
        p = {
            "hips": (-14 * k, 0, 0, (0, 0, -0.04 * k)), "spine": (-18 * k, 0, 0), "head": (-20 * k, 0, 10 * k),
            "upperarm_L": (-50 * k, 0, -50 * k), "forearm_L": (-40 * k, 0, 0),
            "thigh_L": (-25 * k, 0, 0), "shin_L": (35 * k, 0, 0),
        }
        return mirror_pose(p)

    def swim(t, ph):
        s = wave(ph)
        p = {
            "hips": (35, 0, 4 * s), "spine": (15, 0, 0), "chest": (5, 0, 0), "neck": (-20, 0, 0), "head": (-30, 0, 0),
            "upperarm_L": (-70 + 50 * s, 0, -15), "forearm_L": (-50 - 20 * wave(ph, 0.25), 0, 0),
            "thigh_L": (10 + 30 * wave(ph, 0.5), 0, -6), "shin_L": (30 + 20 * wave(ph, 0.75), 0, 0), "foot_L": (40, 0, 0),
        }
        p = mirror_pose(p)
        p["upperarm_R"] = (-70 - 50 * s, 0, 15)
        p["thigh_R"] = (10 - 30 * wave(ph, 0.5), 0, 6)
        for i in range(7):
            p[f"tail_{i + 1}"] = (-20, 0, 15 * wave(ph, -i * 0.12))
        return p

    bake_action(rig_obj, "idle", 3.0, idle)
    bake_action(rig_obj, "walk", 0.8, lambda t, ph: locomotion(ph, False))
    bake_action(rig_obj, "run", 0.5, lambda t, ph: locomotion(ph, True))
    bake_action(rig_obj, "jump", 0.36, jump, loop=False)
    bake_action(rig_obj, "fall", 0.8, fall)
    bake_action(rig_obj, "land", 0.32, land, loop=False)
    bake_action(rig_obj, "double_jump", 0.45, double_jump, loop=False)
    bake_action(rig_obj, "glide", 1.2, glide)
    bake_action(rig_obj, "spin", 0.4, spin, loop=False)
    bake_action(rig_obj, "ride", 2.0, ride)
    bake_action(rig_obj, "celebrate", 1.6, celebrate, loop=False)
    bake_action(rig_obj, "hurt", 0.45, hurt, loop=False)
    bake_action(rig_obj, "swim", 1.0, swim)


# =============================================================================
# CAJU — capivara
# =============================================================================
C_FUR = (0.74, 0.50, 0.31)
C_FUR_DARK = (0.56, 0.35, 0.22)
C_BELLY = (0.84, 0.64, 0.45)
C_NOSE = (0.23, 0.14, 0.11)
C_EAR = (0.40, 0.24, 0.17)
CAJU_RED = (1.0, 0.25, 0.12)
CAJU_ORANGE = (1.0, 0.55, 0.12)
CAJU_YELLOW = (1.0, 0.86, 0.25)
NUT = (0.62, 0.58, 0.40)


def caju_rig() -> Rig:
    B = BoneDef
    bones = [
        B("root", (0, 0, 0), (0, -0.15, 0), None, False),
        B("hips", (0, 0.24, 0.43), (0, 0.0, 0.45), "root"),
        B("spine", (0, 0.0, 0.45), (0, -0.2, 0.47), "hips"),
        B("chest", (0, -0.2, 0.47), (0, -0.32, 0.50), "spine"),
        B("neck", (0, -0.32, 0.50), (0, -0.42, 0.56), "chest"),
        B("head", (0, -0.42, 0.56), (0, -0.74, 0.53), "neck"),
        B("jaw", (0, -0.53, 0.47), (0, -0.70, 0.45), "head"),
        B("eye_L", (0.12, -0.61, 0.645), (0.135, -0.65, 0.645), "head"),
        B("eye_R", (-0.12, -0.61, 0.645), (-0.135, -0.65, 0.645), "head"),
        B("fruit", (0, -0.47, 0.69), (0, -0.47, 0.80), "head"),
        B("belly", (0, 0.04, 0.30), (0, -0.12, 0.27), "spine"),
    ]
    for s, x in (("L", 1), ("R", -1)):
        bones += [
            B(f"ear_{s}", (0.085 * x, -0.42, 0.68), (0.105 * x, -0.40, 0.75), "head"),
            B(f"upperarm_{s}", (0.15 * x, -0.24, 0.36), (0.15 * x, -0.25, 0.20), "chest"),
            B(f"forearm_{s}", (0.15 * x, -0.25, 0.20), (0.15 * x, -0.25, 0.06), f"upperarm_{s}"),
            B(f"hand_{s}", (0.15 * x, -0.25, 0.06), (0.15 * x, -0.32, 0.015), f"forearm_{s}"),
            B(f"thigh_{s}", (0.16 * x, 0.26, 0.38), (0.17 * x, 0.22, 0.21), "hips"),
            B(f"shin_{s}", (0.17 * x, 0.22, 0.21), (0.16 * x, 0.27, 0.07), f"thigh_{s}"),
            B(f"foot_{s}", (0.16 * x, 0.27, 0.07), (0.16 * x, 0.19, 0.015), f"shin_{s}"),
        ]
    return Rig(bones)


def caju_mesh(rig: Rig) -> MeshBuilder:
    mb = MeshBuilder(rig)

    def body_shape(p):
        x, y, z = p
        rear = max(0.0, y) / 0.42
        k = 1.0 + 0.1 * rear
        z2 = z * k
        if z < 0:
            z2 = z * 0.86                      # flatter belly
        return (x * (1.0 + 0.08 * rear), y, z2)

    mb.ellipsoid((0, 0.03, 0.44), (0.27, 0.43, 0.255), C_FUR, ["hips", "spine", "chest", "belly"], seg=24, rings=16,
                 shape=body_shape, color_fn=lambda u: mix(mix(C_FUR, C_FUR_DARK, max(0.0, u.z) * 0.35), C_BELLY,
                                                         smooth01(-u.z * 1.6 - 0.3)))
    # neck fill
    mb.ellipsoid((0, -0.36, 0.52), (0.16, 0.13, 0.15), C_FUR, ["chest", "neck"], seg=16, rings=10)
    # head: boxy superellipsoid, darker towards the snout
    mb.ellipsoid((0, -0.56, 0.565), (0.148, 0.215, 0.14), C_FUR, {"head": 1.0}, seg=20, rings=14, rot=(-6, 0, 0),
                 exponent=(2.6, 2.4), shape=lambda p: (p[0] * (1.0 - 0.12 * max(0.0, -p[1]) / 0.215), p[1], p[2]),
                 color_fn=lambda u: mix(C_FUR, C_FUR_DARK, smooth01(-u.y * 1.2 - 0.2)))
    mb.ellipsoid((0, -0.765, 0.565), (0.10, 0.035, 0.072), C_NOSE, {"head": 1.0}, seg=16, rings=10, exponent=(2.4, 2.4))
    for x in (1, -1):
        mb.ellipsoid((0.042 * x, -0.792, 0.592), (0.018, 0.008, 0.012), (0.08, 0.05, 0.05), {"head": 1.0}, seg=8, rings=6)
    mb.ellipsoid((0, -0.64, 0.465), (0.095, 0.12, 0.05), C_BELLY, {"jaw": 1.0}, seg=14, rings=8)
    mb.ellipsoid((0, -0.755, 0.495), (0.05, 0.02, 0.012), C_NOSE, {"jaw": 0.6, "head": 0.4}, seg=10, rings=6)
    # eyes + heavy lids (calm look)
    for s, x in (("L", 1), ("R", -1)):
        mb.ellipsoid((0.122 * x, -0.632, 0.645), (0.042, 0.03, 0.04), (1, 1, 1), {f"eye_{s}": 1.0}, mat="eye",
                     seg=16, rings=12, uv_mode="front", rot=(0, 0, -32 * x))
        mb.ellipsoid((0.12 * x, -0.618, 0.676), (0.05, 0.036, 0.016), C_FUR_DARK, {"head": 1.0}, seg=12, rings=8,
                     rot=(12, 0, -32 * x))
        # ears
        mb.ellipsoid((0.098 * x, -0.405, 0.715), (0.036, 0.018, 0.045), C_EAR, {f"ear_{s}": 1.0}, seg=12, rings=8,
                     rot=(10, 0, -20 * x), color_fn=lambda u, x=x: mix(C_EAR, (0.85, 0.55, 0.5), max(0.0, -u.y) * 0.6))
        # legs
        mb.tube([(0.15 * x, -0.23, 0.40), (0.15 * x, -0.25, 0.20), (0.15 * x, -0.25, 0.06)], [0.085, 0.06, 0.05],
                C_FUR, [f"upperarm_{s}", f"forearm_{s}"], seg=10, per_bone=4, cap_start=False,
                color_fn=lambda f, a: mix(C_FUR, C_FUR_DARK, smooth01(f * 1.4)))
        mb.ellipsoid((0.15 * x, -0.29, 0.032), (0.058, 0.07, 0.034), C_NOSE, {f"hand_{s}": 1.0}, seg=12, rings=8)
        mb.tube([(0.16 * x, 0.25, 0.42), (0.17 * x, 0.22, 0.21), (0.16 * x, 0.27, 0.07)], [0.12, 0.075, 0.052],
                C_FUR, [f"thigh_{s}", f"shin_{s}"], seg=10, per_bone=4, cap_start=False,
                color_fn=lambda f, a: mix(C_FUR, C_FUR_DARK, smooth01(f * 1.4)))
        mb.ellipsoid((0.16 * x, 0.22, 0.032), (0.06, 0.085, 0.034), C_NOSE, {f"foot_{s}": 1.0}, seg=12, rings=8)
        for k in range(3):
            mb.ellipsoid((0.16 * x + (k - 1) * 0.03, 0.15, 0.025), (0.016, 0.02, 0.016), C_NOSE, {f"foot_{s}": 1.0},
                         seg=8, rings=6)
            mb.ellipsoid((0.15 * x + (k - 1) * 0.028, -0.355, 0.025), (0.016, 0.02, 0.016), C_NOSE, {f"hand_{s}": 1.0},
                         seg=8, rings=6)
    # scruffy fur tufts on the back and cheeks
    import random
    rnd = random.Random(9)
    for k in range(16):
        y = 0.36 - k * 0.05
        x = rnd.uniform(-0.08, 0.08)
        z = 0.44 + 0.25 * math.sqrt(max(0.0, 1 - (y - 0.03) ** 2 / 0.43 ** 2)) - 0.01
        bones = ["hips", "spine", "chest"]
        mb.tuft((x, y, z), (x * 2, 0.6, 0.6), 0.06, 0.03, C_FUR, C_FUR_DARK, bones, sides=4, segs=2)

    # chita blanket on the back (UV 0..1, fringe around)
    rows, cols = 7, 9
    grid = []
    for i in range(rows + 1):
        v = i / rows
        y = 0.24 - v * 0.42
        row = []
        for j in range(cols + 1):
            u = j / cols * 2 - 1
            ang = u * 1.18
            ry = 0.27 * math.sqrt(max(0.0, 1 - ((y - 0.03) / 0.45) ** 2))
            rz = 0.255 * math.sqrt(max(0.0, 1 - ((y - 0.03) / 0.45) ** 2))
            p = Vector((math.sin(ang) * (ry + 0.018), y, 0.44 + math.cos(ang) * (rz + 0.018)))
            row.append((p, (j / cols, v)))
        grid.append(row)
    m = mb.mat("chita")
    idx = []
    for i, row in enumerate(grid):
        r = []
        for p, uv in row:
            r.append(mb._add(p, (1, 1, 1), mb.w_dist(p, ["hips", "spine", "chest"]), uv))
        idx.append(r)
    for i in range(rows):
        for j in range(cols):
            mb._face((idx[i][j], idx[i + 1][j], idx[i + 1][j + 1], idx[i][j + 1]), m)
            mb._face((idx[i][j], idx[i][j + 1], idx[i + 1][j + 1], idx[i + 1][j]), m)
    for i in (0, rows):
        for j in range(0, cols + 1, 1):
            p = grid[i][j][0]
            mb.tuft(p, (0, 0.3 if i == 0 else -0.3, -1), 0.022, 0.008, (1.0, 0.85, 0.3), (1.0, 0.7, 0.3),
                    ["hips", "spine", "chest"], mat="cloth", sides=3, segs=1)
    # the caju on the head: pear-shaped fruit + kidney nut on top
    # caju "apple": wide rounded pear, yellow on one cheek, red on the other
    mb.ellipsoid((0, -0.47, 0.79), (0.085, 0.08, 0.095), CAJU_ORANGE, {"fruit": 1.0}, seg=18, rings=14,
                 shape=lambda p: (p[0] * (1.0 + 0.12 * p[2] / 0.095), p[1] * (1.0 + 0.12 * p[2] / 0.095), p[2]),
                 color_fn=lambda u: mix(mix(CAJU_RED, CAJU_ORANGE, smooth01(u.x * 0.8 + 0.5)), CAJU_YELLOW,
                                        smooth01(u.x * 1.2 + u.z * 0.6 - 0.1)))
    # the nut: kidney-shaped bean on top
    mb.tube([(-0.035, -0.47, 0.875), (-0.01, -0.47, 0.905), (0.025, -0.47, 0.91), (0.045, -0.47, 0.885)],
            [0.022, 0.03, 0.03, 0.022], NUT, ["fruit", "fruit", "fruit"], seg=10, per_bone=3,
            color_fn=lambda f, a: mix(NUT, (0.5, 0.46, 0.32), f))
    # tiny leaf
    mb.tuft((0.0, -0.47, 0.88), (-0.6, -0.3, 0.5), 0.06, 0.02, (0.35, 0.65, 0.3), (0.55, 0.8, 0.35), {"fruit": 1.0},
            sides=4, segs=2, flat=0.3)
    return mb


def caju_anims(rig_obj) -> None:
    def legs(p, ph, A, K, phases, lift=1.0):
        for leg, off in phases.items():
            q = ph + off
            sw = math.sin(TAU * q)
            bend = max(0.0, math.cos(TAU * q)) ** 1.3
            side = leg[-1]
            if leg.startswith("f"):
                p[f"upperarm_{side}"] = (-A * sw, 0, 0)
                p[f"forearm_{side}"] = (K * 0.4 * bend * lift, 0, 0)
                p[f"hand_{side}"] = (-K * 0.6 * bend * lift - 0.3 * (-A * sw), 0, 0)
            else:
                p[f"thigh_{side}"] = (-A * sw, 0, 0)
                p[f"shin_{side}"] = (K * 0.5 * bend * lift, 0, 0)
                p[f"foot_{side}"] = (-K * 0.5 * bend * lift + 0.4 * A * sw, 0, 0)

    def idle(t, ph):
        b = wave(ph)
        chew = max(0.0, math.sin(TAU * ph * 6)) if 0.1 < ph < 0.55 else 0.0
        flick = keys(ph, [(0, 0), (0.62, 0), (0.65, -35), (0.7, 0), (0.74, -25), (0.78, 0), (1.0, 0)])
        look = keys(ph, [(0, 0), (0.2, 0), (0.35, 12), (0.6, 12), (0.75, -8), (0.9, -8), (1.0, 0)])
        p = {
            "hips": (0, 0, 0, (0, 0, -0.004 * b)),
            "spine": (0, 0, 0, None, (1 + 0.015 * b, 1, 1 + 0.015 * b)),
            "chest": (-1 * b, 0, 0),
            "neck": (-3, 0, look * 0.3),
            "head": (2 + 1.5 * b, 0, look * 0.6),
            "jaw": (6 * chew, 0, 2 * chew),
            "ear_L": (flick, 0, 0), "ear_R": (flick * 0.4, 0, 0),
        }
        return p

    def walk(t, ph):
        p = {"hips": (0, 3 * wave(ph), 2 * wave(ph, 0.25), (0, 0, -0.012 * math.cos(2 * TAU * ph))),
             "spine": (0, -2 * wave(ph), 0), "chest": (0, -2 * wave(ph), 0),
             "neck": (2 * math.cos(2 * TAU * ph), 0, 0), "head": (-2 * math.cos(2 * TAU * ph), 0, 3 * wave(ph)),
             "jaw": (0, 0, 0), "ear_L": (6 * wave(ph * 2), 0, 0), "ear_R": (6 * wave(ph * 2, 0.3), 0, 0)}
        legs(p, ph, 22, 55, {"rL": 0.0, "fL": 0.25, "rR": 0.5, "fR": 0.75})
        return p

    def run(t, ph):
        flex = math.sin(TAU * ph)
        p = {"hips": (-6 * flex, 0, 0, (0, 0, -0.05 * max(0.0, math.sin(TAU * (ph + 0.1))))),
             "spine": (8 * flex, 0, 0), "chest": (6 * flex, 0, 0),
             "neck": (-6 * flex, 0, 0), "head": (-6 * flex + 4, 0, 0),
             "jaw": (4 + 4 * flex, 0, 0),
             "ear_L": (-25 + 15 * flex, 0, 0), "ear_R": (-25 + 15 * flex, 0, 0)}
        legs(p, ph, 45, 95, {"rL": 0.0, "rR": 0.06, "fL": 0.5, "fR": 0.56})
        return p

    def jump(t, ph):
        k = ease_out(ph)
        p = {"hips": (keys(ph, [(0, 10), (1, -4)]), 0, 0), "spine": (keys(ph, [(0, -6), (1, 4)]), 0, 0),
             "head": (keys(ph, [(0, -14), (1, 4)]), 0, 0), "ear_L": (-40 * (1 - k), 0, 0), "ear_R": (-40 * (1 - k), 0, 0),
             "thigh_L": (keys(ph, [(0, 50), (1, -25)]), 0, 0), "shin_L": (keys(ph, [(0, -10), (1, 60)]), 0, 0),
             "upperarm_L": (keys(ph, [(0, -55), (1, -35)]), 0, 0), "forearm_L": (keys(ph, [(0, 10), (1, 70)]), 0, 0),
             "hand_L": (keys(ph, [(0, 10), (1, -50)]), 0, 0)}
        return mirror_pose(p)

    def fall(t, ph):
        s = wave(ph)
        p = {"hips": (3, 0, 2 * s), "head": (-10, 0, 3 * wave(ph, 0.25)),
             "ear_L": (-50 + 10 * s, 0, 0), "ear_R": (-50 - 10 * s, 0, 0), "jaw": (8, 0, 0),
             "thigh_L": (-10 + 12 * s, 0, -25), "shin_L": (30, 0, 0),
             "upperarm_L": (-30 - 12 * s, 0, -30), "forearm_L": (30, 0, 0)}
        p = mirror_pose(p)
        p["thigh_R"] = (-10 - 12 * s, 0, 25)
        p["upperarm_R"] = (-30 + 12 * s, 0, 30)
        return p

    def land(t, ph):
        sq = keys(ph, [(0, 1), (0.2, 1), (1, 0)])
        p = {"hips": (0, 0, 0, (0, 0, 0.09 * sq)), "spine": (0, 0, 0, None, (1 + 0.12 * sq, 1, 1 - 0.1 * sq)),
             "head": (10 * sq, 0, 0), "ear_L": (25 * sq, 0, 0), "ear_R": (25 * sq, 0, 0),
             "thigh_L": (-30 * sq, 0, -12 * sq), "shin_L": (55 * sq, 0, 0), "foot_L": (-25 * sq, 0, 0),
             "upperarm_L": (-20 * sq, 0, -14 * sq), "forearm_L": (35 * sq, 0, 0), "hand_L": (-15 * sq, 0, 0)}
        return mirror_pose(p)

    def flop(t, ph):
        up = keys(ph, [(0, 0), (0.35, 1), (0.6, 1), (0.75, 0.2), (1.0, 0.2)])
        sp = keys(ph, [(0, 0.3), (0.45, 1), (1, 1)])
        p = {"hips": (0, 0, 0, (0, 0, 0.06 * (1 - up))), "spine": (0, 0, 0, None, (1 + 0.1 * sp, 1, 1 - 0.08 * sp)),
             "head": (-14 * up, 0, 0), "jaw": (12 * up, 0, 0),
             "ear_L": (-60 * up, 0, 0), "ear_R": (-60 * up, 0, 0), "belly": (0, 0, 0, (0, 0, 0.02 * sp)),
             "thigh_L": (-20, 0, -65 * sp), "shin_L": (20, 0, 0), "foot_L": (10, 0, 0),
             "upperarm_L": (-25, 0, -65 * sp), "forearm_L": (-10, 0, 0)}
        return mirror_pose(p)

    def swim(t, ph):
        p = {"hips": (-10, 0, 3 * wave(ph)), "neck": (-8, 0, 0), "head": (-6, 0, 4 * wave(ph, 0.3)),
             "ear_L": (-10, 0, 0), "ear_R": (-10, 0, 0)}
        legs(p, ph, 30, 70, {"rL": 0.0, "fR": 0.0, "rR": 0.5, "fL": 0.5})
        return p

    def sit(t, ph):
        b = wave(ph)
        p = {"hips": (-28, 0, 0, (0, -0.06, 0.1)), "spine": (-6 + 1.5 * b, 0, 0), "chest": (-4, 0, 0),
             "neck": (12, 0, 0), "head": (16 + 2 * b, 0, 4 * wave(ph, 0.2)),
             "jaw": (5 * max(0.0, math.sin(TAU * ph * 4)), 0, 0),
             "thigh_L": (-75, 0, -12), "shin_L": (130, 0, 0), "foot_L": (-50, 0, 0),
             "upperarm_L": (18, 0, -4), "forearm_L": (0, 0, 0), "hand_L": (-12, 0, 0),
             "ear_L": (keys(ph, [(0, 0), (0.5, 0), (0.55, -30), (0.6, 0), (1, 0)]), 0, 0)}
        return mirror_pose(p)

    def hurt(t, ph):
        k = keys(ph, [(0, 0), (0.25, 1), (1, 0)])
        p = {"hips": (8 * k, 0, 0, (0, -0.05 * k, 0)), "head": (-24 * k, 0, 8 * k), "jaw": (18 * k, 0, 0),
             "ear_L": (-50 * k, 0, 0), "ear_R": (-50 * k, 0, 0),
             "upperarm_L": (-20 * k, 0, -20 * k), "thigh_L": (10 * k, 0, -15 * k)}
        return mirror_pose(p)

    bake_action(rig_obj, "idle", 3.0, idle)
    bake_action(rig_obj, "walk", 1.0, walk)
    bake_action(rig_obj, "run", 0.55, run)
    bake_action(rig_obj, "jump", 0.36, jump, loop=False)
    bake_action(rig_obj, "fall", 0.8, fall)
    bake_action(rig_obj, "land", 0.4, land, loop=False)
    bake_action(rig_obj, "flop", 0.7, flop, loop=False)
    bake_action(rig_obj, "swim", 1.0, swim)
    bake_action(rig_obj, "sit", 3.0, sit)
    bake_action(rig_obj, "hurt", 0.45, hurt, loop=False)


# =============================================================================
def build(name: str, rig_fn, mesh_fn, anim_fn) -> None:
    reset_scene()
    m = mats()
    rig = rig_fn()
    rig_obj = rig.build(name.capitalize())
    mb = mesh_fn(rig)
    body = mb.build(name.capitalize() + "Mesh", rig_obj, m)
    log(name, "verts", len(body.data.vertices), "tris", sum(len(p.vertices) - 2 for p in body.data.polygons),
        "bones", len(rig.order))
    anim_fn(rig_obj)
    rig_obj.animation_data.action = bpy.data.actions.get("idle")
    bpy.context.scene.frame_set(1)
    blend_path = GAME / "blender" / f"{name}.blend"
    bpy.ops.wm.save_as_mainfile(filepath=str(blend_path), compress=True)
    export_glb(OUT / f"{name}.glb", [rig_obj, body], animations=True, skins=True)


def main() -> None:
    argv = sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else []
    only = argv[argv.index("--only") + 1] if "--only" in argv else None
    if only in (None, "juba"):
        build("juba", juba_rig, juba_mesh, juba_anims)
    if only in (None, "caju"):
        build("caju", caju_rig, caju_mesh, caju_anims)


if __name__ == "__main__":
    main()
