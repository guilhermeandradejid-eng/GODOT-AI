#!/usr/bin/env python3
"""Generates the foliage textures of the vibe_scatter plugin (committed PNGs).

All textures are grayscale shading + alpha; the shaders tint them with the
preset/palette colors, so one texture serves green, autumn and alien trees.

    python3 tools/gen_vegetation_textures.py

Drawn with supersampling (4x) and downsampled for clean, anti-aliased edges.
Only Pillow + numpy are needed. Output: addons/vibe_scatter/textures/*.png
"""
from __future__ import annotations

import math
import random
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

OUT = Path(__file__).resolve().parent.parent / "addons" / "vibe_scatter" / "textures"
SS = 4  # supersampling


def canvas(w: int, h: int) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    img = Image.new("RGBA", (w * SS, h * SS), (0, 0, 0, 0))
    return img, ImageDraw.Draw(img)


def finish(img: Image.Image, w: int, h: int, name: str, dilate: int = 0) -> None:
    small = img.resize((w, h), Image.LANCZOS)
    arr = np.array(small).astype(np.float32)
    a = arr[..., 3:4] / 255.0
    # Bleed colors into transparent texels so mipmaps do not get dark halos.
    rgb = arr[..., :3]
    mask = (a[..., 0] > 0.02).astype(np.float32)
    if mask.sum() > 0:
        fill = rgb.copy()
        m = mask.copy()
        for _ in range(12):
            acc = np.zeros_like(fill)
            cnt = np.zeros_like(m)
            for dy in (-1, 0, 1):
                for dx in (-1, 0, 1):
                    acc += np.roll(np.roll(fill * m[..., None], dy, 0), dx, 1)
                    cnt += np.roll(np.roll(m, dy, 0), dx, 1)
            grown = cnt > 0
            newfill = np.where(grown[..., None], acc / np.maximum(cnt[..., None], 1), fill)
            fill = np.where(m[..., None] > 0, fill, newfill)
            m = np.maximum(m, grown.astype(np.float32))
        rgb = fill
    out = np.concatenate([rgb, a * 255.0], axis=-1).clip(0, 255).astype(np.uint8)
    im = Image.fromarray(out, "RGBA")
    if dilate:
        alpha = im.split()[3].filter(ImageFilter.MaxFilter(dilate))
        im.putalpha(alpha)
    OUT.mkdir(parents=True, exist_ok=True)
    im.save(OUT / name, optimize=True)
    print("wrote", OUT / name, im.size)


def leaf_polygon(cx: float, cy: float, length: float, width: float, ang: float, tip: float = 0.85, steps: int = 18) -> list:
    """Tapered leaf outline starting at (cx, cy) along angle ang."""
    pts_l, pts_r = [], []
    ca, sa = math.cos(ang), math.sin(ang)
    for i in range(steps + 1):
        t = i / steps
        half = width * 0.5 * (math.sin(math.pi * t) ** tip) * (1.0 - 0.25 * t)
        x = t * length
        for side, pts in ((1, pts_l), (-1, pts_r)):
            px = cx + x * ca - side * half * sa
            py = cy + x * sa + side * half * ca
            pts.append((px, py))
    return pts_l + pts_r[::-1]


def shade(v: float) -> tuple[int, int, int, int]:
    g = int(max(0, min(255, v * 255)))
    return (g, g, g, 255)


def broadleaf(size: int = 512, seed: int = 3) -> None:
    rnd = random.Random(seed)
    img, d = canvas(size, size)
    S = size * SS
    cx, cy = S * 0.5, S * 0.55
    leaves = []
    # Twigs radiating from the cluster center, leaves along and at the tips.
    for k in range(13):
        ang = rnd.uniform(0, math.tau)
        length = S * rnd.uniform(0.2, 0.4)
        ex, ey = cx + math.cos(ang) * length, cy + math.sin(ang) * length
        d.line([(cx, cy), (ex, ey)], fill=shade(0.28), width=int(S * 0.006))
        for j in range(6):
            t = 0.3 + 0.7 * j / 5
            px, py = cx + (ex - cx) * t, cy + (ey - cy) * t
            a = ang + rnd.choice((-1, 1)) * rnd.uniform(0.4, 0.9)
            leaves.append((rnd.random(), px, py, S * rnd.uniform(0.11, 0.17), a))
        leaves.append((rnd.random(), ex, ey, S * rnd.uniform(0.12, 0.17), ang + rnd.uniform(-0.3, 0.3)))
    leaves.sort()
    for depth, px, py, ln, a in leaves:
        tone = 0.45 + 0.5 * depth + rnd.uniform(-0.06, 0.06)
        d.polygon(leaf_polygon(px, py, ln, ln * 0.52, a), fill=shade(tone))
        # Midrib and a lighter half for a bit of relief.
        ex, ey = px + math.cos(a) * ln * 0.9, py + math.sin(a) * ln * 0.9
        d.line([(px, py), (ex, ey)], fill=shade(tone * 0.72), width=max(1, int(S * 0.003)))
    finish(img, size, size, "leaves_broad.png")


def stylized_clump(size: int = 512, seed: int = 7) -> None:
    """Soft, painterly leaf clump (stylized / toon canopies)."""
    rnd = random.Random(seed)
    S = size * SS
    img, d = canvas(size, size)
    lobes = []
    for i in range(26):
        ang = rnd.uniform(0, math.tau)
        r = S * 0.3 * math.sqrt(rnd.random())
        x, y = S * 0.5 + math.cos(ang) * r, S * 0.52 + math.sin(ang) * r * 0.85
        rad = S * rnd.uniform(0.07, 0.13)
        lobes.append((y, x, rad))
    lobes.sort()
    for y, x, rad in lobes:
        # Darker toward the bottom of the clump, lighter on top.
        tone = 0.95 - 0.45 * (y / S)
        d.ellipse([x - rad, y - rad, x + rad, y + rad], fill=shade(tone * 0.8))
        d.ellipse([x - rad * 0.8, y - rad * 0.95, x + rad * 0.7, y + rad * 0.45], fill=shade(min(1.0, tone * 0.98)))
    # Small scalloped leaves along the edge give the painted silhouette.
    for i in range(70):
        ang = rnd.uniform(0, math.tau)
        r = S * rnd.uniform(0.33, 0.4)
        x, y = S * 0.5 + math.cos(ang) * r, S * 0.52 + math.sin(ang) * r * 0.85
        ln = S * rnd.uniform(0.04, 0.07)
        d.polygon(leaf_polygon(x - math.cos(ang) * ln * 0.5, y - math.sin(ang) * ln * 0.5, ln, ln * 0.7, ang), fill=shade(0.62 - 0.3 * (y / S)))
    finish(img, size, size, "leaves_clump.png")


def needles(w: int = 512, h: int = 256, seed: int = 11) -> None:
    rnd = random.Random(seed)
    img, d = canvas(w, h)
    W, H = w * SS, h * SS
    y0 = H * 0.5
    d.line([(0, y0), (W * 0.97, y0)], fill=shade(0.3), width=int(H * 0.035))
    # Side twigs.
    twigs = [(0.0, y0, W * 0.97, y0)]
    for i in range(7):
        x = W * (0.12 + 0.12 * i)
        side = 1 if i % 2 else -1
        ln = W * rnd.uniform(0.18, 0.28) * (1.0 - 0.5 * i / 7)
        ex, ey = x + ln * 0.8, y0 + side * ln * 0.55
        d.line([(x, y0), (ex, ey)], fill=shade(0.3), width=int(H * 0.018))
        twigs.append((x, y0, ex, ey))
    for (x0, y1, x2, y2) in twigs:
        length = math.hypot(x2 - x0, y2 - y1)
        ang = math.atan2(y2 - y1, x2 - x0)
        n = int(length / (W * 0.006))
        for k in range(n):
            t = k / max(n - 1, 1)
            px, py = x0 + (x2 - x0) * t, y1 + (y2 - y1) * t
            for side in (-1, 1):
                a = ang + side * rnd.uniform(0.6, 1.1) + 0.25
                ln = H * rnd.uniform(0.14, 0.22) * (1.0 - 0.35 * t)
                tone = rnd.uniform(0.5, 0.95)
                d.line([(px, py), (px + math.cos(a) * ln, py + math.sin(a) * ln)], fill=shade(tone), width=max(2, int(H * 0.012)))
    finish(img, w, h, "needles.png")


def frond(w: int = 1024, h: int = 256, seed: int = 5, fern: bool = False) -> None:
    rnd = random.Random(seed)
    img, d = canvas(w, h)
    W, H = w * SS, h * SS
    y0 = H * 0.5
    d.line([(0, y0), (W * 0.98, y0)], fill=shade(0.45), width=int(H * 0.03))
    n = 50 if not fern else 18
    for i in range(n):
        t = (i + 0.5) / n
        x = W * (0.04 + 0.92 * t)
        env = math.sin(math.pi * min(1.0, t * 1.1)) ** 0.7 if not fern else (1.0 - t) ** 0.6
        for side in (-1, 1):
            ln = H * 0.47 * env * rnd.uniform(0.85, 1.0)
            if ln < H * 0.03:
                continue
            # Leaflets point toward the tip of the frond.
            ang = side * rnd.uniform(0.75, 1.05)
            tone = rnd.uniform(0.6, 0.95)
            if fern:
                # Pinnae: a tapered leaflet with lobed edges.
                d.polygon(leaf_polygon(x, y0, ln, ln * 0.34, ang, tip=0.7), fill=shade(tone))
                for k in range(6):
                    tt = 0.15 + 0.8 * k / 6
                    px = x + math.cos(ang) * ln * tt
                    py = y0 + math.sin(ang) * ln * tt
                    r = ln * 0.1 * (1.0 - tt * 0.55)
                    for sgn in (-1, 1):
                        ox, oy = -math.sin(ang) * r * 0.9 * sgn, math.cos(ang) * r * 0.9 * sgn
                        d.ellipse([px + ox - r, py + oy - r, px + ox + r, py + oy + r], fill=shade(tone * 0.95))
            else:
                d.polygon(leaf_polygon(x, y0, ln, H * 0.04, ang, tip=0.5), fill=shade(tone))
    finish(img, w, h, "fern.png" if fern else "frond.png")


def bark_noise(size: int = 256, seed: int = 2) -> None:
    """Tileable bark relief (vertical fibers): grayscale height."""
    rng = np.random.default_rng(seed)
    x = np.linspace(0, 1, size, endpoint=False)
    y = np.linspace(0, 1, size, endpoint=False)
    X, Y = np.meshgrid(x, y)
    h = np.zeros((size, size))
    for octave in range(5):
        fx = 3 * 2 ** octave
        fy = 1 * 2 ** octave
        phase = rng.uniform(0, math.tau, 4)
        h += (np.sin(math.tau * (X * fx + 0.3 * np.sin(math.tau * Y * fy + phase[0])) + phase[1]) *
              np.cos(math.tau * Y * fy * 0.5 + phase[2])) / (1.3 ** octave)
    h = (h - h.min()) / (h.max() - h.min())
    h = np.abs(h - 0.5) * 2.0  # ridges = fissures
    img = Image.fromarray((h * 255).astype(np.uint8), "L").convert("RGBA")
    OUT.mkdir(parents=True, exist_ok=True)
    img.save(OUT / "bark.png", optimize=True)
    print("wrote", OUT / "bark.png")


if __name__ == "__main__":
    broadleaf()
    stylized_clump()
    needles()
    frond()
    frond(768, 256, seed=9, fern=True)
    bark_noise()
