#!/usr/bin/env python3
"""Gera o terreno contínuo do mundo (um só mapa de alturas) a partir da receita JSON.

    python3 game/tools/gen_terrain.py [game/world/world.json] [--preview]

Saída (ao lado da receita, em game/world/<nome>_terrain/):
    height.bin   float32 little-endian, resolution x resolution (linha = z), em metros
    normals.png  RGB8: normal do relevo (x, y, z em 0..1) para cristas nítidas em todo LOD
    masks.png    RGBA8: R = rocha, G = areia compactada (trilhas/pisos), B = areia vítrea
                 (brilho extra), A = exposição ao vento (ondulações/fitas de areia)
    meta.json    {"resolution", "cell_size", "size", "height_min", "height_max"}
    preview.png  (com --preview) relevo sombreado para conferir o layout

Receita: seção "terrain" com "size", "cell_size", "seed", "base", "dunes" (campos de dunas)
e "features" (plateau, canyon, basin, ramp, ridge, flatten, mound, border). Coordenadas
em metros do Godot (x leste, z sul), mapa centrado em 0,0.
"""
from __future__ import annotations

import json
import math
import sys
from pathlib import Path

import numpy as np
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]


# ----------------------------------------------------------------------------- noise
def _hash2(ix: np.ndarray, iz: np.ndarray, seed: int) -> np.ndarray:
    h = (ix.astype(np.int64) * 374761393 + iz.astype(np.int64) * 668265263 + seed * 2246822519) & 0xFFFFFFFF
    h = (h ^ (h >> 13)) * 1274126177 & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFF).astype(np.float64) / 65535.0


def gradient_noise(x: np.ndarray, z: np.ndarray, seed: int) -> np.ndarray:
    """2D gradient (Perlin-like) noise in [-1, 1], vectorized."""
    x0 = np.floor(x)
    z0 = np.floor(z)
    fx = x - x0
    fz = z - z0
    ix = x0.astype(np.int64)
    iz = z0.astype(np.int64)

    def grad(ixo, izo, dx, dz):
        a = _hash2(ix + ixo, iz + izo, seed) * math.tau
        return np.cos(a) * dx + np.sin(a) * dz

    n00 = grad(0, 0, fx, fz)
    n10 = grad(1, 0, fx - 1, fz)
    n01 = grad(0, 1, fx, fz - 1)
    n11 = grad(1, 1, fx - 1, fz - 1)
    ux = fx * fx * fx * (fx * (fx * 6 - 15) + 10)
    uz = fz * fz * fz * (fz * (fz * 6 - 15) + 10)
    return (n00 * (1 - ux) + n10 * ux) * (1 - uz) + (n01 * (1 - ux) + n11 * ux) * uz


def fbm(x, z, seed, octaves=4, lac=2.0, gain=0.5):
    total = np.zeros_like(x)
    amp = 1.0
    freq = 1.0
    norm = 0.0
    for o in range(octaves):
        total += gradient_noise(x * freq, z * freq, seed + o * 101) * amp
        norm += amp
        amp *= gain
        freq *= lac
    return total / norm


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# ----------------------------------------------------------------------------- shapes
def smax(a, b, k):
    """Máximo suave (sem vincos onde as superfícies se encontram)."""
    h = np.maximum(k - np.abs(a - b), 0.0) / k
    return np.maximum(a, b) + h * h * k * 0.25


def dune_field(X, Z, f: dict, seed: int) -> np.ndarray:
    """Organic dunes: ridged noise stretched across the wind (crest lines run
    perpendicular to it), domain-warped so crests bend and branch, then made
    asymmetric (long windward slope, steep slip face) by sampling the ridge
    upwind. Secondary small dunes ride on top."""
    wl = float(f.get("wavelength", 140.0))
    amp = float(f.get("amplitude", 16.0))
    w = math.radians(float(f.get("wind_deg", 30.0)))
    wx, wz = math.cos(w), math.sin(w)
    stretch = float(f.get("stretch", 2.4))
    warp_amt = float(f.get("warp", 0.9))
    sharp = float(f.get("sharpness", 2.2))
    s = seed + int(f.get("seed", 0)) * 13
    along = (X * wx + Z * wz) / wl
    across = (-X * wz + Z * wx) / (wl * stretch)
    wu = fbm(along * 0.45, across * 0.45, s + 1, 3) * warp_amt
    wv = fbm(along * 0.45 + 17.3, across * 0.45 - 4.1, s + 2, 3) * warp_amt
    skew = float(f.get("skew", 0.16))

    def ridge(u, v):
        n = gradient_noise(u, v, s) * 0.75 + gradient_noise(u * 2.03 + 5.1, v * 2.03, s + 3) * 0.25
        return (1.0 - np.abs(n)) ** sharp

    u = along + wu
    v = across + wv
    r0 = ridge(u, v)
    r_up = ridge(u - skew, v)                 # upwind sample: windward rises slowly
    h = np.maximum(r0, r_up * 0.92)
    h = np.clip((h - 0.35) / 0.65, 0.0, 1.0)
    h = h * h * (3 - 2 * h)
    patch = 0.5 + 0.5 * smoothstep(-0.5, 0.6, fbm(X / (wl * 4.0), Z / (wl * 4.0), s + 7, 3))
    out = amp * h * patch
    sw = float(f.get("small_wavelength", wl * 0.18))
    sa = float(f.get("small_amplitude", amp * 0.07))
    if sa > 0:
        su = (X * wx + Z * wz) / sw
        sv = (-X * wz + Z * wx) / (sw * 2.0)
        sn = (1.0 - np.abs(gradient_noise(su + wu * 3.0, sv, s + 9))) ** 2.0
        out += sa * sn * smoothstep(-0.3, 0.7, fbm(X / (sw * 7), Z / (sw * 7), s + 17, 2))
    return out


def radial(X, Z, at, r, inner=0.0):
    d = np.hypot(X - at[0], Z - at[1])
    return d, smoothstep(r, r * inner if inner else 0.0, d) if inner else None


def polyline_dist(X, Z, pts):
    """Distance to a polyline + parameter (0..1 along the total length)."""
    P = np.asarray(pts, dtype=np.float64)
    best = np.full(X.shape, 1e12)
    tpar = np.zeros(X.shape)
    seglen = np.hypot(np.diff(P[:, 0]), np.diff(P[:, 1]))
    total = max(seglen.sum(), 1e-6)
    acc = 0.0
    for i in range(len(P) - 1):
        ax, az = P[i]
        bx, bz = P[i + 1]
        dx, dz = bx - ax, bz - az
        L2 = max(dx * dx + dz * dz, 1e-9)
        t = np.clip(((X - ax) * dx + (Z - az) * dz) / L2, 0.0, 1.0)
        px = ax + dx * t
        pz = az + dz * t
        d = np.hypot(X - px, Z - pz)
        m = d < best
        best = np.where(m, d, best)
        tpar = np.where(m, (acc + t * seglen[i]) / total, tpar)
        acc += seglen[i]
    return best, tpar


def build(recipe: dict):
    T = recipe["terrain"]
    size = float(T.get("size", 1024))
    cell = float(T.get("cell_size", 1.0))
    res = int(round(size / cell)) + 1
    seed = int(T.get("seed", 7))
    half = size * 0.5
    xs = np.linspace(-half, half, res)
    X, Z = np.meshgrid(xs, xs)            # rows = z
    base = T.get("base", {})
    H = np.full(X.shape, float(base.get("height", 0.0)))
    H += fbm(X / float(base.get("scale", 420.0)), Z / float(base.get("scale", 420.0)), seed, 4) * float(base.get("amplitude", 10.0))
    rock = np.zeros(X.shape)
    packed = np.zeros(X.shape)
    glass = np.zeros(X.shape)
    calm = np.zeros(X.shape)             # 1 = no dunes (features flatten the dunes)

    feats = T.get("features", [])
    # dunes, attenuated where features want calm ground
    for f in feats:
        t = f["type"]
        if t in ("plateau", "basin", "flatten", "canyon", "mound"):
            if t == "canyon":
                d, _ = polyline_dist(X, Z, f["points"])
                calm = np.maximum(calm, smoothstep(f["width"] * 1.6, f["width"] * 0.5, d))
            else:
                d = np.hypot(X - f["at"][0], Z - f["at"][1])
                calm = np.maximum(calm, smoothstep(f["radius"] * float(f.get("calm", 1.5)), f["radius"] * 0.8, d))
    D = np.zeros(X.shape)
    for df in T.get("dunes", []):
        dh = dune_field(X, Z, df, seed)
        if "at" in df:
            d = np.hypot(X - df["at"][0], Z - df["at"][1])
            dh *= smoothstep(df["radius"], df["radius"] * float(df.get("falloff", 0.6)), d)
        D += dh
    H += D * (1.0 - calm)
    windy = smoothstep(0.0, 1.0, D / max(1e-3, np.percentile(D, 95)))

    for f in feats:
        t = f["type"]
        if t == "plateau":
            # flat top, steep noisy cliffs (sandstone), sand piled at the foot
            d = np.hypot(X - f["at"][0], Z - f["at"][1])
            ang = np.arctan2(Z - f["at"][1], X - f["at"][0])
            r = f["radius"] * (1.0 + 0.12 * gradient_noise(np.cos(ang) * 2.2 + 50, np.sin(ang) * 2.2, seed + 5)
                               + 0.05 * gradient_noise(np.cos(ang) * 6 + 9, np.sin(ang) * 6, seed + 6))
            cliff = float(f.get("cliff", 6.0))
            top = smoothstep(r + cliff, r - cliff * 0.2, d)
            target = float(f["height"])
            H = H * (1 - top) + target * top + top * fbm(X / 30, Z / 30, seed + 9, 2) * 0.6
            rim = smoothstep(cliff * 1.2, 0.0, np.abs(d - r)) * (1 - smoothstep(0.98, 1.0, top))
            rock = np.maximum(rock, rim)
            foot = smoothstep(r + cliff * 4.0, r + cliff, d) * (1 - top)
            H += foot * float(f.get("talus", 4.0)) * smoothstep(0.0, 1.0, foot)
        elif t == "canyon":
            d, tp = polyline_dist(X, Z, f["points"])
            w = float(f["width"])
            depth = float(f["depth"])
            floor_y = None
            if "floor" in f:
                fl = f["floor"]
                floor_y = fl[0] + (fl[1] - fl[0]) * tp
            wobble = 1.0 + 0.15 * gradient_noise(X / 40, Z / 40, seed + 21)
            k = smoothstep(w * 0.5 * wobble + float(f.get("wall", 6.0)), w * 0.5 * wobble, d)
            carved = (floor_y if floor_y is not None else H - depth)
            H = H * (1 - k) + np.minimum(H, carved + (1 - k) * depth) * k
            walls = smoothstep(float(f.get("wall", 6.0)) * 1.4, 0.0, np.abs(d - w * 0.5 * wobble))
            rock = np.maximum(rock, walls * smoothstep(depth * 0.2, depth * 0.6, H - carved))
            packed = np.maximum(packed, k * 0.5)
        elif t == "basin":
            d = np.hypot(X - f["at"][0], Z - f["at"][1])
            r = f["radius"]
            bowl = smoothstep(r, r * 0.25, d)
            target = float(f["floor"])
            H = H * (1 - bowl) + target * bowl
            packed = np.maximum(packed, smoothstep(r * 0.8, r * 0.3, d) * float(f.get("packed", 0.6)))
        elif t == "flatten":
            d = np.hypot(X - f["at"][0], Z - f["at"][1])
            k = smoothstep(f["radius"] * float(f.get("blend", 1.6)), f["radius"], d)
            H = H * (1 - k) + float(f["height"]) * k
            packed = np.maximum(packed, k * float(f.get("packed", 0.0)))
        elif t == "mound":
            d = np.hypot(X - f["at"][0], Z - f["at"][1])
            H += float(f["height"]) * smoothstep(f["radius"], 0.0, d) ** float(f.get("power", 1.4))
        elif t in ("ramp", "ridge"):
            # long sand slope for surfing (ramp) or a dune ridge line
            d, tp = polyline_dist(X, Z, f["points"])
            w = float(f["width"])
            prof = smoothstep(w, 0.0, d)
            if t == "ramp":
                # raised sand road; continuous: max over each segment's own profile
                h0, h1 = f["heights"]
                side = math.tan(math.radians(float(f.get("side_deg", 27.0))))
                P = np.asarray(f["points"], dtype=np.float64)
                seglen = np.hypot(np.diff(P[:, 0]), np.diff(P[:, 1]))
                total = max(seglen.sum(), 1e-6)
                road = np.full(X.shape, -1e9)
                acc = 0.0
                for i in range(len(P) - 1):
                    ax, az = P[i]; bx, bz = P[i + 1]
                    ddx, ddz = bx - ax, bz - az
                    L2 = max(ddx * ddx + ddz * ddz, 1e-9)
                    tu = ((X - ax) * ddx + (Z - az) * ddz) / L2          # unclamped
                    tt = np.clip(tu, 0.0, 1.0)
                    di = np.hypot(X - (ax + ddx * tt), Z - (az + ddz * tt))
                    # height keeps the segment's own grade past its ends (no flat caps at joints)
                    tpi = np.clip((acc + tu * seglen[i]) / total, 0.0, 1.0)
                    tpc = np.clip((acc + tt * seglen[i]) / total, 1e-6, 1.0)
                    cv = float(f.get("curve", 1.0))
                    slope_t = cv * tpc ** (cv - 1.0) if cv != 1.0 else 1.0
                    hl = h0 + (h1 - h0) * (tpc ** cv + slope_t * (tpi - tpc))
                    road = np.maximum(road, hl - np.maximum(0.0, di - w * 0.5) * side)
                    acc += seglen[i]
                # dune-like flanks: noisy side slopes and width, smooth lane in the middle
                fn = float(f.get("flank_noise", 3.5))
                if fn > 0.0:
                    fl = smoothstep(w * 0.35, w * 0.5 + 14.0, d)
                    road = road + fn * fbm(X / 34.0, Z / 34.0, seed + 41, 3) * fl \
                        - np.maximum(0.0, d - w * 0.5) * side * 0.35 * fbm(X / 70.0, Z / 70.0, seed + 43, 2)
                H = smax(H, road, float(f.get("soft", 4.0)))
            else:
                H += float(f["height"]) * prof ** 1.3
            calm = np.maximum(calm, prof * 0.5)
        elif t == "glass":
            d = np.hypot(X - f["at"][0], Z - f["at"][1])
            glass = np.maximum(glass, smoothstep(f["radius"], f["radius"] * 0.4, d))
        elif t == "path":
            d, _ = polyline_dist(X, Z, f["points"])
            packed = np.maximum(packed, smoothstep(float(f.get("width", 4.0)), 0.0, d) * float(f.get("strength", 0.6)))
    # map border: tall dune walls that blend into the endless horizon dunes of the shader
    border = T.get("border", {})
    if border:
        e = np.maximum(np.abs(X), np.abs(Z))
        k = smoothstep(half - float(border.get("width", 90.0)), half - 4.0, e)
        H += k * float(border.get("height", 30.0)) * (0.7 + 0.3 * fbm(X / 120, Z / 120, seed + 31, 3))
    # slope-based rock on the steepest slopes (sand can't hold more than ~38°)
    gz, gx = np.gradient(H, cell)
    slope = np.degrees(np.arctan(np.hypot(gx, gz)))
    rock = np.maximum(rock, smoothstep(40.0, 52.0, slope))
    masks = np.stack([rock, packed, glass, windy * (1 - rock)], axis=-1)
    return H.astype(np.float32), np.clip(masks * 255.0, 0, 255).astype(np.uint8), res, cell, size


def _import_settings(path: Path) -> None:
    """Texturas do terreno: sem compressão com perdas (normais/máscaras), com mipmaps
    e sem a conversão automática para VRAM quando o Godot detecta uso em 3D."""
    want = {"compress/mode": "0", "mipmaps/generate": "true", "detect_3d/compress_to": "0"}
    if path.exists():
        lines = path.read_text().splitlines()
        seen = set()
        for i, ln in enumerate(lines):
            k = ln.split("=", 1)[0]
            if k in want:
                lines[i] = f"{k}={want[k]}"
                seen.add(k)
        if "[params]" in lines:
            at = lines.index("[params]") + 1
            for k, v in want.items():
                if k not in seen:
                    lines.insert(at, f"{k}={v}")
        path.write_text("\n".join(lines) + "\n")
    else:
        path.write_text('[remap]\n\nimporter="texture"\ntype="CompressedTexture2D"\n\n[params]\n\n'
                        + "".join(f"{k}={v}\n" for k, v in want.items()))


def main() -> int:
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    recipe_path = Path(args[0]) if args else ROOT / "game" / "world" / "world.json"
    recipe = json.loads(recipe_path.read_text())
    H, M, res, cell, size = build(recipe)
    out = recipe_path.parent / (recipe_path.stem + "_terrain")
    out.mkdir(parents=True, exist_ok=True)
    (out / "height.bin").write_bytes(H.astype("<f4").tobytes())
    Image.fromarray(M, "RGBA").save(out / "masks.png", optimize=True)
    # macro normals (x, z in RG, y in B) for crisp crests at every LOD
    gz, gx = np.gradient(H.astype(np.float64), cell)
    n = np.stack([-gx, np.ones_like(gx), -gz], -1)
    n /= np.linalg.norm(n, axis=-1, keepdims=True)
    nrm = np.clip((n * 0.5 + 0.5) * 255.0 + 0.5, 0, 255).astype(np.uint8)
    Image.fromarray(nrm, "RGB").save(out / "normals.png", optimize=True)
    for tex in ("masks.png", "normals.png"):
        _import_settings(out / (tex + ".import"))
    meta = {"resolution": res, "cell_size": cell, "size": size,
            "height_min": float(H.min()), "height_max": float(H.max())}
    (out / "meta.json").write_text(json.dumps(meta, indent=1))
    if "--preview" in sys.argv:
        gz, gx = np.gradient(H, cell)
        n = np.stack([-gx, np.ones_like(H) * 1.0, -gz], -1)
        n /= np.linalg.norm(n, axis=-1, keepdims=True)
        light = np.array([-0.5, 0.6, -0.6])
        light /= np.linalg.norm(light)
        shade = np.clip(n @ light, 0, 1)
        hn = (H - H.min()) / max(1e-6, H.max() - H.min())
        rgb = np.stack([0.55 + 0.45 * shade, 0.45 + 0.4 * shade, 0.35 + 0.3 * shade], -1) * (0.75 + 0.25 * hn[..., None])
        rgb = rgb * (1 - M[..., 0:1] / 255 * 0.4) + (M[..., 0:1] / 255) * np.array([0.25, 0.12, 0.1]) * 0.4
        Image.fromarray(np.clip(rgb * 255, 0, 255).astype(np.uint8)).resize((min(res, 1024),) * 2).save(out / "preview.png")
    print(f"terrain: {res}x{res} cell={cell} size={size} h=[{H.min():.1f}, {H.max():.1f}] -> {out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
