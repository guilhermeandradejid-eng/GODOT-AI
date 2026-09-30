#!/usr/bin/env python3
"""Generates the tileable sky and water textures (committed PNGs).

    python3 tools/gen_sky_water_textures.py

  addons/vibe_vfx/textures/cloud_noise.png   RGBA 512², every channel tiles:
      R = billowy Perlin-Worley (cumulus shapes)
      G = Worley fbm (detail that erodes cloud edges)
      B = streaky fbm stretched along x (cirrus)
      A = soft low-frequency fbm (coverage variation / weather)
  addons/vibe_terrain/textures/water_normal.png  RGBA 512²: tangent-space
      normal (OpenGL convention) of an ocean height field + the height in A
      (used for foam and crest color).

Spectral synthesis (FFT) and wrapped cellular noise, so everything tiles.
Only numpy + Pillow are needed.
"""
from __future__ import annotations

from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parent.parent
N = 512
rng = np.random.default_rng(1234)


def freqs(n: int) -> tuple[np.ndarray, np.ndarray]:
    f = np.fft.fftfreq(n) * n
    return np.meshgrid(f, f)


def spectral_noise(n: int, beta: float, stretch: tuple[float, float] = (1.0, 1.0), lo: float = 1.0, hi: float = 1e9) -> np.ndarray:
    """Tileable noise with a 1/f^beta power spectrum (band-limited to lo..hi)."""
    kx, ky = freqs(n)
    k = np.sqrt((kx * stretch[0]) ** 2 + (ky * stretch[1]) ** 2)
    amp = np.where((k >= lo) & (k <= hi), 1.0 / np.maximum(k, 1e-6) ** (beta / 2.0), 0.0)
    phase = rng.uniform(0, 2 * np.pi, (n, n))
    spec = amp * np.exp(1j * phase)
    out = np.real(np.fft.ifft2(spec))
    out -= out.min()
    return out / max(out.max(), 1e-9)


def worley(n: int, cells: int, seed: int) -> np.ndarray:
    """Tileable cellular noise: distance to the nearest feature point (0..1)."""
    r = np.random.default_rng(seed)
    pts = (np.stack(np.meshgrid(np.arange(cells), np.arange(cells), indexing="ij"), -1) + r.uniform(0, 1, (cells, cells, 2))) / cells
    ys, xs = np.mgrid[0:n, 0:n] / n
    best = np.full((n, n), 10.0)
    cell_of = lambda v: np.floor(v * cells).astype(int)  # noqa: E731
    cx, cy = cell_of(xs), cell_of(ys)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            ix = (cx + dx) % cells
            iy = (cy + dy) % cells
            p = pts[ix, iy]
            ddx = xs - p[..., 0]
            ddy = ys - p[..., 1]
            ddx -= np.round(ddx)
            ddy -= np.round(ddy)
            best = np.minimum(best, np.sqrt(ddx * ddx + ddy * ddy))
    best *= cells
    return np.clip(best / 1.1, 0.0, 1.0)


def remap(v, a, b, c, d):
    return c + (v - a) * (d - c) / (b - a)


def norm01(v: np.ndarray) -> np.ndarray:
    v = v - v.min()
    return v / max(v.max(), 1e-9)


def cloud_noise() -> None:
    perlin = spectral_noise(N, 3.2, lo=2.0)
    w = 1.0 - (0.625 * worley(N, 4, 1) + 0.25 * worley(N, 8, 2) + 0.125 * worley(N, 16, 3))
    pw = norm01(np.clip(remap(perlin, 0.0, 1.0, w, 1.0), 0, 1))
    pw = norm01(pw * 0.85 + perlin * 0.15)
    detail = norm01(1.0 - (0.5 * worley(N, 12, 4) + 0.3 * worley(N, 24, 5) + 0.2 * worley(N, 48, 6)))
    cirrus = spectral_noise(N, 2.6, stretch=(1.8, 0.22), lo=1.0)
    weather = spectral_noise(N, 4.0, lo=1.0, hi=10.0)
    img = np.stack([pw, detail, cirrus, weather], -1)
    img = (np.clip(img, 0, 1) * 255.0 + 0.5).astype(np.uint8)
    out = ROOT / "addons" / "vibe_vfx" / "textures" / "cloud_noise.png"
    Image.fromarray(img, "RGBA").save(out, optimize=True)
    print("wrote", out.relative_to(ROOT))


def water_normal() -> None:
    kx, ky = freqs(N)
    k = np.sqrt(kx * kx + ky * ky)
    wind = np.array([1.0, 0.35])
    wind /= np.linalg.norm(wind)
    kn = np.where(k > 0, k, 1.0)
    cos_w = (kx * wind[0] + ky * wind[1]) / kn
    # Phillips-like spectrum: peak at mid frequencies, aligned with the wind
    # (a bit of counter-direction energy keeps it lively), tiny waves damped.
    peak = 9.0
    ph = np.exp(-1.0 / (kn / peak) ** 2) / kn ** 4.0 * (0.2 + np.abs(cos_w) ** 2.0) * np.exp(-(kn / 70.0) ** 2)
    ph[0, 0] = 0.0
    amp = np.sqrt(ph)
    spec = amp * (rng.normal(size=(N, N)) + 1j * rng.normal(size=(N, N)))
    h = np.real(np.fft.ifft2(spec))
    dx = np.real(np.fft.ifft2(1j * kx * 2 * np.pi / N * spec))
    dy = np.real(np.fft.ifft2(1j * ky * 2 * np.pi / N * spec))
    s = 1.0 / max(np.abs(dx).max(), np.abs(dy).max()) * 1.4
    nx, ny = -dx * s, -dy * s
    nz = np.ones_like(nx)
    ln = np.sqrt(nx * nx + ny * ny + nz * nz)
    nx, ny, nz = nx / ln, ny / ln, nz / ln
    # Image rows go down (+v) while the OpenGL normal-map green points up.
    img = np.stack([nx * 0.5 + 0.5, -ny * 0.5 + 0.5, nz * 0.5 + 0.5, norm01(h)], -1)
    img = (np.clip(img, 0, 1) * 255.0 + 0.5).astype(np.uint8)
    out = ROOT / "addons" / "vibe_terrain" / "textures" / "water_normal.png"
    Image.fromarray(img, "RGBA").save(out, optimize=True)
    print("wrote", out.relative_to(ROOT))


if __name__ == "__main__":
    cloud_noise()
    water_normal()
