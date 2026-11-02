#!/usr/bin/env python3
"""SOPRO — gera texturas procedurais do jogo (CC0, feitas aqui).

    python3 game/tools/gen_textures.py

game/assets/textures/chita.png      tecido de chita (flores grandes sobre vermelho), repete nas bordas
game/assets/textures/bandeirinhas.png  atlas 4x1 de bandeirinhas de festa junina (padrões)
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


def chita(size=1024, seed=3) -> Image.Image:
    rnd = random.Random(seed)
    img = Image.new("RGB", (size, size), (206, 32, 52))
    d = ImageDraw.Draw(img)
    # small background dots
    for _ in range(420):
        x, y = rnd.uniform(0, size), rnd.uniform(0, size)
        r = rnd.uniform(3, 6)
        col = rnd.choice([(255, 236, 190), (90, 170, 220), (255, 200, 60)])
        wrap_draw(lambda dx, dy: d.ellipse((x + dx - r, y + dy - r, x + dx + r, y + dy + r), fill=col), size)
    flowers = []
    for _ in range(9):
        for _try in range(60):
            x, y, R = rnd.uniform(0, size), rnd.uniform(0, size), rnd.uniform(70, 120)
            ok = all(min(abs(x - fx), size - abs(x - fx)) ** 2 + min(abs(y - fy), size - abs(y - fy)) ** 2 >
                     (R + fr + 20) ** 2 for fx, fy, fr in flowers)
            if ok:
                flowers.append((x, y, R))
                break
    palettes = [
        ((255, 214, 64), (255, 150, 30), (120, 40, 20)),
        ((255, 248, 236), (250, 180, 200), (200, 40, 80)),
        ((100, 190, 255), (40, 110, 210), (250, 230, 120)),
        ((255, 140, 170), (230, 60, 110), (255, 230, 120)),
    ]
    for (x, y, R) in flowers:
        petal, inner, center = rnd.choice(palettes)
        n = rnd.choice([5, 6, 7, 8])
        rot = rnd.uniform(0, math.tau)
        # leaves
        for k in range(3):
            a = rot + k * math.tau / 3 + 0.5
            lx, ly = x + math.cos(a) * R * 1.05, y + math.sin(a) * R * 1.05
            pts = []
            for s in range(24):
                t = s / 23 * math.tau
                px = math.cos(t) * R * 0.55
                py = math.sin(t) * R * 0.22
                pts.append((lx + px * math.cos(a) - py * math.sin(a), ly + px * math.sin(a) + py * math.cos(a)))
            wrap_draw(lambda dx, dy, pts=pts: d.polygon([(p[0] + dx, p[1] + dy) for p in pts], fill=(40, 150, 90),
                                                      outline=(20, 90, 60)), size)
        # petals (two layers)
        for layer, (rr, col) in enumerate(((R, petal), (R * 0.68, inner))):
            for k in range(n):
                a = rot + (k + 0.5 * layer) * math.tau / n
                cx, cy = x + math.cos(a) * rr * 0.55, y + math.sin(a) * rr * 0.55
                pr = rr * 0.48
                wrap_draw(lambda dx, dy, cx=cx, cy=cy, pr=pr, col=col: d.ellipse(
                    (cx + dx - pr, cy + dy - pr, cx + dx + pr, cy + dy + pr), fill=col, outline=(110, 20, 30), width=3), size)
        cr = R * 0.24
        wrap_draw(lambda dx, dy: d.ellipse((x + dx - cr, y + dy - cr, x + dx + cr, y + dy + cr), fill=center,
                                           outline=(90, 20, 20), width=3), size)
        for k in range(10):
            a = k * math.tau / 10
            sx, sy = x + math.cos(a) * cr * 0.55, y + math.sin(a) * cr * 0.55
            wrap_draw(lambda dx, dy, sx=sx, sy=sy: d.ellipse((sx + dx - 4, sy + dy - 4, sx + dx + 4, sy + dy + 4),
                                                             fill=(255, 250, 220)), size)
    return img.resize((512, 512), Image.LANCZOS)


def bandeirinhas() -> Image.Image:
    """4 flag patterns side by side (each 128x160): plain, dots, stripes, chita-ish."""
    W, H = 128, 160
    img = Image.new("RGBA", (W * 4, H), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    cols = [(240, 60, 80), (255, 200, 40), (40, 170, 230), (90, 200, 120)]
    for i in range(4):
        x0 = i * W
        d.rectangle((x0, 0, x0 + W - 1, H - 1), fill=cols[i] + (255,))
        if i == 1:
            for yy in range(10, H, 28):
                for xx in range(10, W, 28):
                    d.ellipse((x0 + xx, yy, x0 + xx + 10, yy + 10), fill=(255, 255, 255, 255))
        if i == 2:
            for yy in range(0, H, 24):
                d.rectangle((x0, yy, x0 + W - 1, yy + 10), fill=(255, 255, 255, 255))
        if i == 3:
            for yy in range(20, H, 50):
                for xx in range(20, W, 50):
                    d.ellipse((x0 + xx - 14, yy - 14, x0 + xx + 14, yy + 14), fill=(255, 230, 90, 255))
                    d.ellipse((x0 + xx - 5, yy - 5, x0 + xx + 5, yy + 5), fill=(220, 50, 70, 255))
    return img


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
    chita().save(OUT / "chita.png")
    bandeirinhas().save(OUT / "bandeirinhas.png")
    soft_dot().save(OUT / "soft_dot.png")
    streak().save(OUT / "streak.png")
    print("ok:", ", ".join(p.name for p in sorted(OUT.glob("*.png"))))


if __name__ == "__main__":
    main()
