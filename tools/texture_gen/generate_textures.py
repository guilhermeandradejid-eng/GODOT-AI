#!/usr/bin/env python3
"""Generates the Vibe Suite texture pack.

* Terrain materials (tileable): <name>_albedo_height.webp (RGB albedo, A height)
  and <name>_normal_rough.webp (RGB OpenGL normal, A roughness).
  - grass_ground / rock: ambientCG Ground037 / Rock023 (CC0), taken from the
    Terrain3D demo (github.com/TokisanGames/Terrain3D).
  - sandstone: godot-demo-projects "material_testers" rock (MIT).
  - everything else is generated procedurally here (CC0).
* VFX sprites and noise textures for addons/vibe_vfx (procedural, CC0).

Usage:
    pip install numpy pillow
    python3 tools/texture_gen/generate_textures.py [--refs /path/to/refs]

--refs must contain clones of TokisanGames/Terrain3D and
godotengine/godot-demo-projects (sparse: 3d/material_testers).
"""
from __future__ import annotations

import argparse
import math
import os
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
TERRAIN_OUT = ROOT / "addons" / "vibe_terrain" / "textures"
VFX_OUT = ROOT / "addons" / "vibe_vfx" / "textures"


# --------------------------------------------------------------------------- noise

def _smooth(t):
    return t * t * (3.0 - 2.0 * t)


def value_noise(size: int, cells: int, rng: np.random.Generator) -> np.ndarray:
    """Tileable value noise in [0, 1] (size must be a multiple of cells)."""
    lattice = rng.random((cells, cells))
    coords = np.arange(size) * cells / size
    i0 = np.floor(coords).astype(int) % cells
    i1 = (i0 + 1) % cells
    t = _smooth(coords - np.floor(coords))
    # rows (y) and cols (x)
    a = lattice[i0][:, i0]
    b = lattice[i0][:, i1]
    c = lattice[i1][:, i0]
    d = lattice[i1][:, i1]
    tx = t[None, :]
    ty = t[:, None]
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


def fbm(size: int, base_cells: int, octaves: int, rng: np.random.Generator, gain: float = 0.5) -> np.ndarray:
    total = np.zeros((size, size))
    amp = 1.0
    norm = 0.0
    cells = base_cells
    for _ in range(octaves):
        if cells > size:
            break
        total += value_noise(size, cells, rng) * amp
        norm += amp
        amp *= gain
        cells *= 2
    return total / norm


def voronoi(size: int, cells: int, rng: np.random.Generator, jitter: float = 0.9):
    """Tileable Worley noise. Returns (F1, F2, cell_id) with distances in cell units."""
    pts = rng.random((cells, cells, 2)) * jitter + (1 - jitter) * 0.5
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float64)
    px = xs * cells / size
    py = ys * cells / size
    cx = np.floor(px).astype(int)
    cy = np.floor(py).astype(int)
    f1 = np.full((size, size), 9.0)
    f2 = np.full((size, size), 9.0)
    cid = np.zeros((size, size), dtype=np.int64)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            nx = cx + ox
            ny = cy + oy
            wx = nx % cells
            wy = ny % cells
            fx = nx + pts[wy, wx, 0]
            fy = ny + pts[wy, wx, 1]
            d = np.sqrt((fx - px) ** 2 + (fy - py) ** 2)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            cid = np.where(closer, wy * cells + wx, cid)
            f1 = np.where(closer, d, f1)
    return f1, f2, cid


def warp(img: np.ndarray, dx: np.ndarray, dy: np.ndarray) -> np.ndarray:
    """Samples img at (x + dx, y + dy) with wrap-around (bilinear)."""
    size = img.shape[0]
    ys, xs = np.mgrid[0:size, 0:size].astype(np.float64)
    x = (xs + dx) % size
    y = (ys + dy) % size
    x0 = np.floor(x).astype(int)
    y0 = np.floor(y).astype(int)
    x1 = (x0 + 1) % size
    y1 = (y0 + 1) % size
    tx = x - x0
    ty = y - y0
    a = img[y0, x0]
    b = img[y0, x1]
    c = img[y1, x0]
    d = img[y1, x1]
    return (a * (1 - tx) + b * tx) * (1 - ty) + (c * (1 - tx) + d * tx) * ty


def normalize01(a: np.ndarray) -> np.ndarray:
    lo, hi = float(a.min()), float(a.max())
    return (a - lo) / max(hi - lo, 1e-6)


def normal_from_height(h: np.ndarray, strength: float) -> np.ndarray:
    dx = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dy = (np.roll(h, -1, axis=0) - np.roll(h, 1, axis=0)) * 0.5
    nx = -dx * strength
    ny = dy * strength  # OpenGL convention (+Y up in texture space)
    nz = np.ones_like(h)
    length = np.sqrt(nx * nx + ny * ny + nz * nz)
    n = np.stack([nx / length, ny / length, nz / length], axis=-1)
    return n * 0.5 + 0.5


def gradient(t: np.ndarray, stops) -> np.ndarray:
    """Maps t in [0,1] through color stops [(pos, (r,g,b)), ...] (0..255 colors)."""
    t = np.clip(t, 0, 1)
    out = np.zeros(t.shape + (3,))
    for (p0, c0), (p1, c1) in zip(stops[:-1], stops[1:]):
        m = (t >= p0) & (t <= p1)
        k = ((t - p0) / max(p1 - p0, 1e-6))[..., None]
        out = np.where(m[..., None], np.array(c0) * (1 - k) + np.array(c1) * k, out)
    return out / 255.0


def save_pack(name: str, albedo: np.ndarray, height: np.ndarray, normal: np.ndarray, rough: np.ndarray, quality: int = 86):
    TERRAIN_OUT.mkdir(parents=True, exist_ok=True)
    ah = np.concatenate([np.clip(albedo, 0, 1), np.clip(height, 0, 1)[..., None]], axis=-1)
    nr = np.concatenate([np.clip(normal, 0, 1), np.clip(rough, 0, 1)[..., None]], axis=-1)
    Image.fromarray((ah * 255 + 0.5).astype(np.uint8), "RGBA").save(TERRAIN_OUT / f"{name}_albedo_height.webp", "WEBP", quality=quality, alpha_quality=95, method=6)
    Image.fromarray((nr * 255 + 0.5).astype(np.uint8), "RGBA").save(TERRAIN_OUT / f"{name}_normal_rough.webp", "WEBP", quality=quality + 4, alpha_quality=90, method=6)
    print("terrain", name, albedo.shape[0])


# --------------------------------------------------------------------------- terrain materials

def mat_sand(size, rng):
    base = fbm(size, 4, 5, rng)
    wx = (fbm(size, 4, 3, rng) - 0.5) * size * 0.08
    wy = (fbm(size, 4, 3, rng) - 0.5) * size * 0.08
    ys, xs = np.mgrid[0:size, 0:size] / size
    ripples = np.sin((xs * 14 + ys * 3) * 2 * math.pi)
    ripples = warp(ripples, wx, wy)
    ripples = np.where(ripples > 0, np.abs(ripples) ** 0.7, -(np.abs(ripples) ** 1.6))
    grain = value_noise(size, size // 2, rng)
    h = normalize01(ripples * 0.45 + base * 0.7 + grain * 0.12)
    tone = normalize01(base * 0.7 + h * 0.3)
    albedo = gradient(tone, [(0, (176, 142, 94)), (0.5, (212, 181, 128)), (1, (232, 209, 160))])
    albedo *= (0.93 + 0.1 * grain)[..., None]
    rough = 0.88 + grain * 0.1
    return albedo, h, normal_from_height(h, 6.0), rough


def mat_snow(size, rng):
    base = fbm(size, 4, 6, rng, 0.45)
    drift = warp(fbm(size, 2, 4, rng), (fbm(size, 4, 3, rng) - 0.5) * size * 0.2, 0)
    h = normalize01(base * 0.6 + drift * 0.6)
    sparkle = (rng.random((size, size)) > 0.9985).astype(float)
    shade = gradient(h, [(0, (196, 212, 232)), (0.5, (232, 240, 248)), (1, (252, 253, 255))])
    albedo = np.clip(shade + sparkle[..., None] * 0.08, 0, 1)
    rough = 0.55 - sparkle * 0.4 + (1 - h) * 0.1
    return albedo, h, normal_from_height(h, 3.0), rough


def mat_dirt(size, rng):
    base = fbm(size, 4, 6, rng)
    mid = fbm(size, 16, 4, rng)
    f1, f2, cid = voronoi(size, 64, rng)
    stones = np.clip(1.0 - f1 / 0.35, 0, 1) ** 0.7 * (rng.random(64 * 64)[cid] > 0.78)
    grain = value_noise(size, size // 2, rng)
    h = normalize01(base * 0.7 + mid * 0.35 + stones * 0.45 + grain * 0.08)
    tone = normalize01(base * 0.6 + mid * 0.5)
    albedo = gradient(tone, [(0, (62, 45, 31)), (0.45, (98, 73, 51)), (1, (132, 104, 76))])
    stone_col = (0.75 + 0.5 * rng.random(64 * 64))[cid]
    albedo = albedo * (1 - stones[..., None] * 0.7) + (np.array([0.47, 0.43, 0.39]) * stone_col[..., None]) * stones[..., None] * 0.7
    albedo *= (0.9 + 0.2 * grain)[..., None]
    rough = 0.88 + grain * 0.1 - stones * 0.15
    return albedo, h, normal_from_height(h, 5.0), rough


def mat_gravel(size, rng):
    f1, f2, cid = voronoi(size, 22, rng)
    edge = f2 - f1
    stone = np.clip(edge / 0.28, 0, 1) ** 0.5
    bump = np.clip(1.0 - f1 / 0.62, 0, 1) ** 0.7
    detail = fbm(size, 16, 4, rng)
    h = normalize01(stone * 0.6 + bump * 0.5 + detail * 0.15)
    cell_tone = rng.random(22 * 22)[cid]
    albedo = gradient(cell_tone, [(0, (86, 82, 78)), (0.4, (122, 114, 104)), (0.75, (150, 140, 126)), (1, (104, 92, 80))])
    albedo *= (0.85 + 0.25 * detail)[..., None]
    albedo *= (0.35 + 0.65 * stone)[..., None]
    rough = 0.75 + (1 - stone) * 0.2
    return albedo, h, normal_from_height(h, 7.0), rough


def mat_mud(size, rng):
    base = fbm(size, 4, 6, rng)
    puddles = np.clip((0.42 - base) * 8, 0, 1)
    detail = fbm(size, 16, 3, rng)
    h = normalize01(base * 0.9 + detail * 0.1)
    albedo = gradient(normalize01(base + detail * 0.2), [(0, (38, 29, 20)), (0.6, (62, 47, 33)), (1, (84, 66, 46))])
    albedo *= (1 - puddles * 0.35)[..., None]
    rough = 0.85 - puddles * 0.7
    return albedo, h, normal_from_height(h, 4.0), rough


def mat_ash(size, rng):
    base = fbm(size, 4, 6, rng)
    grain = value_noise(size, size // 2, rng)
    cinders = (rng.random((size, size)) > 0.995).astype(float)
    h = normalize01(base * 0.8 + grain * 0.2)
    albedo = gradient(normalize01(base * 0.8 + grain * 0.2), [(0, (26, 24, 23)), (0.6, (48, 45, 42)), (1, (70, 66, 62))])
    albedo = albedo + cinders[..., None] * 0.2
    rough = 0.95 - cinders * 0.3
    return albedo, h, normal_from_height(h, 5.0), rough


def mat_lava(size, rng):
    f1, f2, cid = voronoi(size, 10, rng)
    crack = np.clip((f2 - f1) / 0.22, 0, 1)
    detail = fbm(size, 8, 5, rng)
    wx = (fbm(size, 4, 3, rng) - 0.5) * size * 0.03
    crack = warp(crack, wx, wx.T)
    plate = crack ** 0.35
    h = normalize01(plate * 0.8 + detail * 0.25)  # low height = glowing cracks (shader)
    albedo = gradient(normalize01(detail + plate * 0.4), [(0, (18, 15, 14)), (0.6, (34, 29, 27)), (1, (58, 50, 46))])
    glow = (1 - plate) ** 2
    albedo = albedo * (1 - glow[..., None]) + np.array([1.0, 0.36, 0.05]) * glow[..., None]
    rough = 0.7 + plate * 0.25
    return albedo, h, normal_from_height(h, 6.0), rough


def mat_ice(size, rng):
    base = fbm(size, 2, 5, rng)
    f1, f2, _ = voronoi(size, 6, rng)
    cracks = np.clip(1.0 - (f2 - f1) / 0.025, 0, 1)
    f1b, f2b, _ = voronoi(size, 17, rng)
    fine = np.clip(1.0 - (f2b - f1b) / 0.02, 0, 1) * 0.6
    streak = fbm(size, 8, 4, rng)
    h = normalize01(base * 0.4 - cracks * 0.35 - fine * 0.2 + streak * 0.1)
    albedo = gradient(normalize01(base * 0.7 + streak * 0.3), [(0, (92, 150, 190)), (0.5, (150, 200, 228)), (1, (205, 232, 246))])
    albedo = albedo * (1 - fine[..., None] * 0.12) + cracks[..., None] * np.array([0.85, 0.95, 1.0]) * 0.35
    rough = 0.1 + cracks * 0.35 + fine * 0.15
    return albedo, h, normal_from_height(h, 3.0), rough


def mat_moss(size, rng):
    base = fbm(size, 4, 6, rng)
    fine = fbm(size, 32, 3, rng)
    f1, _, _ = voronoi(size, 20, rng)
    f1b, _, _ = voronoi(size, 55, rng)
    clumps = np.clip(1.0 - f1 / 0.9, 0, 1) * 0.6 + np.clip(1.0 - f1b / 0.8, 0, 1) * 0.4
    wx = (fbm(size, 8, 3, rng) - 0.5) * size * 0.03
    clumps = warp(clumps, wx, wx.T)
    h = normalize01(clumps * 0.55 + base * 0.45 + fine * 0.25)
    tone = normalize01(base * 0.5 + clumps * 0.4 + fine * 0.3)
    albedo = gradient(tone, [(0, (24, 36, 15)), (0.45, (52, 74, 27)), (0.8, (88, 108, 40)), (1, (120, 128, 58))])
    rough = 0.9 + fine * 0.08
    return albedo, h, normal_from_height(h, 4.5), rough


def mat_crystal(size, rng):
    f1, f2, cid = voronoi(size, 9, rng)
    ys, xs = np.mgrid[0:size, 0:size] / size
    ang = rng.random(81)[cid] * math.tau
    facet = normalize01(np.cos(ang) * xs * 9 + np.sin(ang) * ys * 9 + rng.random(81)[cid] * 3) % 1.0
    edge = np.clip((f2 - f1) / 0.06, 0, 1)
    h = normalize01(facet * 0.6 + edge * 0.6)
    hue = rng.random(81)[cid]
    albedo = gradient(hue, [(0, (40, 220, 240)), (0.5, (110, 120, 255)), (1, (200, 90, 255))])
    albedo *= (0.55 + 0.45 * facet)[..., None]
    albedo *= (0.4 + 0.6 * edge)[..., None]
    rough = 0.08 + (1 - edge) * 0.3
    return albedo, h, normal_from_height(h, 8.0), rough


def mat_regolith(size, rng):
    base = fbm(size, 4, 6, rng)
    grain = value_noise(size, size // 2, rng)
    f1, f2, cid = voronoi(size, 12, rng)
    r = rng.random(144)[cid] * 0.3 + 0.15
    rim = np.exp(-((f1 - r) / 0.05) ** 2) * (rng.random(144)[cid] > 0.5)
    bowl = np.clip(1 - f1 / np.maximum(r, 1e-3), 0, 1) ** 2 * (rng.random(144)[cid] > 0.5)
    h = normalize01(base * 0.6 + grain * 0.15 + rim * 0.35 - bowl * 0.35)
    albedo = gradient(normalize01(base * 0.7 + grain * 0.3), [(0, (86, 86, 86)), (0.5, (124, 123, 121)), (1, (160, 158, 155))])
    albedo += (rim * 0.08)[..., None]
    rough = 0.96
    return albedo, h, normal_from_height(h, 6.0), np.full((size, size), rough)


def repack_photo(name: str, refs: Path):
    src = refs / "Terrain3D" / "project" / "demo" / "assets" / "textures"
    mapping = {"grass_ground": "ground037", "rock": "rock023"}
    base = mapping[name]
    ah = Image.open(src / f"{base}_alb_ht.png").convert("RGBA")
    nr = Image.open(src / f"{base}_nrm_rgh.png").convert("RGBA")
    TERRAIN_OUT.mkdir(parents=True, exist_ok=True)
    ah.save(TERRAIN_OUT / f"{name}_albedo_height.webp", "WEBP", quality=84, alpha_quality=95, method=6)
    nr.save(TERRAIN_OUT / f"{name}_normal_rough.webp", "WEBP", quality=90, alpha_quality=90, method=6)
    print("terrain", name, ah.size, "(ambientCG CC0 via Terrain3D)")


def repack_sandstone(refs: Path):
    src = refs / "demo-projects" / "3d" / "material_testers" / "test_materials"
    alb = np.asarray(Image.open(src / "rock_albedo.jpg").convert("RGB")).astype(float) / 255.0
    depth = np.asarray(Image.open(src / "rock_depth.jpg").convert("L")).astype(float) / 255.0
    rough = np.asarray(Image.open(src / "rock_rough.jpg").convert("L")).astype(float) / 255.0
    height = 1.0 - depth  # depth maps are inverted heights
    save_pack("sandstone", alb, height, normal_from_height(height, 8.0), rough, quality=84)


# --------------------------------------------------------------------------- VFX sprites

def save_sprite(name: str, rgba: np.ndarray, quality: int = 90):
    VFX_OUT.mkdir(parents=True, exist_ok=True)
    img = Image.fromarray((np.clip(rgba, 0, 1) * 255 + 0.5).astype(np.uint8), "RGBA")
    img.save(VFX_OUT / f"{name}.webp", "WEBP", quality=quality, alpha_quality=100, method=6)
    print("vfx", name, rgba.shape[:2])


def radial(size):
    ys, xs = np.mgrid[0:size, 0:size].astype(float)
    c = (size - 1) / 2
    return np.sqrt((xs - c) ** 2 + (ys - c) ** 2) / c, xs / size, ys / size


def sprite_soft_circle(size=256):
    r, _, _ = radial(size)
    a = np.clip(1 - r, 0, 1) ** 2
    return np.dstack([np.ones_like(a)] * 3 + [a])


def sprite_smoke_atlas(rng, size=512):
    cell = size // 2
    out = np.zeros((size, size, 4))
    for i in range(4):
        ys, xs = np.mgrid[0:cell, 0:cell].astype(float) / cell
        density = np.zeros((cell, cell))
        # A few overlapping soft blobs -> billowy silhouette.
        for _ in range(7):
            cx, cy = rng.uniform(0.3, 0.7), rng.uniform(0.32, 0.68)
            rad = rng.uniform(0.16, 0.3)
            d = np.sqrt((xs - cx) ** 2 + (ys - cy) ** 2) / rad
            density = np.maximum(density, np.clip(1 - d, 0, 1) ** 0.8)
        n = fbm(cell, 4, 6, rng)
        wx = (fbm(cell, 4, 3, rng) - 0.5) * cell * 0.12
        density = warp(density, wx, wx.T)
        edge = np.clip(1 - np.sqrt((xs - 0.5) ** 2 + (ys - 0.5) ** 2) / 0.5, 0, 1)
        alpha = np.clip(density * (0.45 + 0.75 * n) * 1.3, 0, 1) * np.clip(edge * 3, 0, 1)
        light = np.clip(0.62 + (0.5 - ys) * 0.7 + (n - 0.5) * 0.45, 0, 1)
        tile = np.dstack([light] * 3 + [alpha])
        oy, ox = (i // 2) * cell, (i % 2) * cell
        out[oy:oy + cell, ox:ox + cell] = tile
    return out


def sprite_flame_atlas(rng, size=512):
    cell = size // 2
    out = np.zeros((size, size, 4))
    for i in range(4):
        ys, xs = np.mgrid[0:cell, 0:cell].astype(float) / cell
        x = (xs - 0.5) * 2
        y = 1 - ys  # 0 bottom, 1 top
        n = fbm(cell, 4, 5, rng)
        n2 = fbm(cell, 8, 4, rng)
        sway = (n - 0.5) * 0.45 * y
        width = 0.78 * np.clip(1 - y, 0, 1) ** 0.55 * (0.45 + 0.55 * np.clip(y * 4, 0, 1))
        d = np.abs(x + sway) / np.maximum(width, 1e-3)
        shape = np.clip(1 - d * d, 0, 1)
        breakup = np.clip(n2 * 1.3 - y * 0.55, 0, 1)
        alpha = np.clip(shape * (0.55 + breakup), 0, 1) ** 0.8 * np.clip(y / 0.12, 0, 1)
        core = np.clip(shape * (1 - y) * 1.4, 0, 1)
        intensity = np.clip(0.35 + core * 0.8, 0, 1)
        tile = np.dstack([intensity] * 3 + [alpha])
        oy, ox = (i // 2) * cell, (i % 2) * cell
        out[oy:oy + cell, ox:ox + cell] = tile
    return out


def sprite_spark(size=128):
    ys, xs = np.mgrid[0:size, 0:size].astype(float) / size
    x = (xs - 0.5) * 2
    y = (ys - 0.5) * 2
    a = np.clip(1 - np.abs(x) * 6, 0, 1) ** 1.5 * np.clip(1 - np.abs(y), 0, 1) ** 0.8
    a += np.clip(1 - np.sqrt(x * x * 16 + y * y * 1.5), 0, 1) ** 2
    return np.dstack([np.ones_like(a)] * 3 + [np.clip(a, 0, 1)])


def sprite_flare(size=256):
    r, xs, ys = radial(size)
    ang = np.arctan2(ys - 0.5, xs - 0.5)
    rays = (np.abs(np.cos(ang * 3)) ** 40) * np.clip(1 - r, 0, 1) ** 1.5
    glow = np.clip(1 - r, 0, 1) ** 3
    core = np.clip(1 - r * 5, 0, 1)
    a = np.clip(glow * 0.8 + rays * 0.7 + core, 0, 1)
    return np.dstack([np.ones_like(a)] * 3 + [a])


def sprite_sparkle(size=128):
    ys, xs = np.mgrid[0:size, 0:size].astype(float) / size
    x = np.abs((xs - 0.5) * 2)
    y = np.abs((ys - 0.5) * 2)
    star = np.clip(1 - (x * 7 + y), 0, 1) ** 2 + np.clip(1 - (y * 7 + x), 0, 1) ** 2
    glow = np.clip(1 - np.sqrt(x * x + y * y) * 1.6, 0, 1) ** 3
    a = np.clip(star + glow, 0, 1)
    return np.dstack([np.ones_like(a)] * 3 + [a])


def sprite_ring(size=256):
    r, _, _ = radial(size)
    a = np.exp(-((r - 0.8) / 0.08) ** 2) + 0.25 * np.exp(-((r - 0.72) / 0.15) ** 2)
    return np.dstack([np.ones_like(r)] * 3 + [np.clip(a, 0, 1)])


def sprite_drop(size=128):
    ys, xs = np.mgrid[0:size, 0:size].astype(float) / size
    x = (xs - 0.5) * 2
    a = np.clip(1 - np.abs(x) * 10, 0, 1) * np.clip(ys * 1.2, 0, 1) ** 1.5
    return np.dstack([np.ones_like(a)] * 3 + [np.clip(a, 0, 1) * 0.9])


def sprite_snowflake(size=128):
    r, xs, ys = radial(size)
    ang = np.arctan2(ys - 0.5, xs - 0.5)
    arms = (np.abs(np.cos(ang * 3)) ** 12) * np.clip(1 - r, 0, 1)
    a = np.clip(np.clip(1 - r * 1.6, 0, 1) ** 1.5 + arms * 0.6, 0, 1)
    return np.dstack([np.ones_like(a)] * 3 + [a])


def sprite_leaf_atlas(rng, size=256):
    cell = size // 2
    out = np.zeros((size, size, 4))
    for i in range(4):
        ys, xs = np.mgrid[0:cell, 0:cell].astype(float) / cell
        x = (xs - 0.5) * 2
        y = (ys - 0.5) * 2
        shape = 1 - (x * x / (0.36 * (1 - y * y * 0.9) + 1e-3) + y * y * 0.95)
        a = np.clip(shape * 8, 0, 1)
        vein = np.clip(1 - np.abs(x) * 30, 0, 1) * 0.35
        side = np.clip(1 - np.abs(np.abs(x) - (y + 1) * 0.25 % 0.3) * 20, 0, 1) * 0.12
        shade = 0.75 + 0.25 * (1 - np.abs(x)) + vein + side
        tile = np.dstack([shade] * 3 + [a])
        oy, ox = (i // 2) * cell, (i % 2) * cell
        out[oy:oy + cell, ox:ox + cell] = tile
    return out


def noise_textures(rng, size=256):
    n = fbm(size, 4, 6, rng)
    save_sprite("noise_fbm", np.dstack([n, n, n, np.ones_like(n)]), quality=95)
    f1, f2, _ = voronoi(size, 8, rng)
    v = normalize01(f1)
    save_sprite("noise_voronoi", np.dstack([v, v, v, np.ones_like(v)]), quality=95)


# --------------------------------------------------------------------------- main

def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--refs", default=os.environ.get("VIBE_REFS", "/home/user/refs"))
    parser.add_argument("--size", type=int, default=512, help="Procedural terrain texture size")
    args = parser.parse_args()
    refs = Path(args.refs)
    rng = np.random.default_rng(20260928)
    size = args.size
    if (refs / "Terrain3D").exists():
        repack_photo("grass_ground", refs)
        repack_photo("rock", refs)
    else:
        print("skipping photo textures (no Terrain3D clone in --refs)")
    if (refs / "demo-projects").exists():
        repack_sandstone(refs)
    for name, fn in [("sand", mat_sand), ("snow", mat_snow), ("dirt", mat_dirt), ("gravel", mat_gravel),
                     ("mud", mat_mud), ("ash", mat_ash), ("lava", mat_lava), ("ice", mat_ice),
                     ("moss", mat_moss), ("crystal", mat_crystal), ("regolith", mat_regolith)]:
        save_pack(name, *fn(size, rng))
    save_sprite("soft_circle", sprite_soft_circle())
    save_sprite("smoke_atlas", sprite_smoke_atlas(rng))
    save_sprite("flame_atlas", sprite_flame_atlas(rng))
    save_sprite("spark", sprite_spark())
    save_sprite("flare", sprite_flare())
    save_sprite("sparkle", sprite_sparkle())
    save_sprite("ring", sprite_ring())
    save_sprite("drop", sprite_drop())
    save_sprite("snowflake", sprite_snowflake())
    save_sprite("leaf_atlas", sprite_leaf_atlas(rng))
    noise_textures(rng)


if __name__ == "__main__":
    main()
