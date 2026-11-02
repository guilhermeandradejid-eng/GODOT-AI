#!/usr/bin/env python3
"""Gera texturas procedurais do jogo YLVAAR (CC0, feitas aqui).

    python3 game/tools/gen_textures.py

game/assets/textures/soft_dot.png   sprite redondo suave (partículas de luz)
game/assets/textures/streak.png     sprite alongado (rastros de vento, faíscas)
"""
from __future__ import annotations

import math
import random
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parents[2]
OUT = ROOT / "game" / "assets" / "textures"


def wrap_draw(draw_fn, size):
    """Calls draw_fn(dx, dy) for the 9 tile offsets so shapes wrap around."""
    for dx in (-size, 0, size):
        for dy in (-size, 0, size):
            draw_fn(dx, dy)


def soft_dot(n=128) -> Image.Image:
    img = Image.new("RGBA", (n, n))
    px = img.load()
    for y in range(n):
        for x in range(n):
            dx, dy = (x + 0.5) / n * 2 - 1, (y + 0.5) / n * 2 - 1
            r = math.sqrt(dx * dx + dy * dy)
            a = max(0.0, 1 - r) ** 2.2
            core = max(0.0, 1 - r * 3.0) ** 2
            v = min(1.0, a + core)
            px[x, y] = (255, 255, 255, int(v * 255))
    return img


def streak(w=256, h=32) -> Image.Image:
    img = Image.new("RGBA", (w, h))
    px = img.load()
    for y in range(h):
        for x in range(w):
            u = (x + 0.5) / w
            v = abs((y + 0.5) / h * 2 - 1)
            a = math.sin(math.pi * u) ** 1.5 * max(0.0, 1 - v) ** 2
            px[x, y] = (255, 255, 255, int(a * 255))
    return img


def main() -> None:
    OUT.mkdir(parents=True, exist_ok=True)
    soft_dot().save(OUT / "soft_dot.png")
    streak().save(OUT / "streak.png")
    print("ok:", ", ".join(p.name for p in sorted(OUT.glob("*.png"))))


if __name__ == "__main__":
    main()
