#!/usr/bin/env python3
"""Builds the demo worlds from recipes/*.json and renders their screenshots.

    python3 tools/build_demos.py                 # every demo
    python3 tools/build_demos.py vulcao vale_cel # only these
    python3 tools/build_demos.py --shots-only    # re-render without rebuilding

Each demo is made exactly like a user (or Claude Code) would make it from the
terminal: `world.build` with the recipe, then `screenshot`. Outputs:
  demos/<name>.tscn (+ demos/<name>_data/)   the playable scene
  docs/img/<name>_<shot>.webp                screenshots for the README
  demos/thumbs/<name>.webp                   thumbnail used by the demo hub
  demos/demos.json                           manifest read by demos/demo_hub.tscn
Needs Godot 4.3+ (GODOT_BIN) and a display or xvfb-run for the screenshots.
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from vibe_client import VibeClient, VibeError  # noqa: E402

ORDER = ["ilha_tropical", "montanhas_nevadas", "deserto_canion", "vulcao", "campo_noturno",
         "vale_cel", "arquipelago_lowpoly", "planeta_alien", "vfx_showcase"]

# Extra screenshots per demo (besides "hero" and "aerial").
SHOTS: dict[str, list[dict]] = {
    "ilha_tropical": [{"shot": "fogueira", "target": "Fogueira"}],
    "deserto_canion": [{"shot": "fogueira", "target": "Fogueira"}],
    "vulcao": [{"shot": "pluma", "target": "Pluma"}],
    "campo_noturno": [{"shot": "portal", "target": "Portal"}, {"shot": "fogueira", "target": "Fogueira"}],
    "vale_cel": [{"shot": "chao", "view": "ground"}],
    "planeta_alien": [{"shot": "portal", "target": "Portal"}],
    "vfx_showcase": [{"shot": "fogueira", "target": "FX_campfire"}, {"shot": "portal", "target": "FX_portal"},
                     {"shot": "campo_de_forca", "target": "FX_force_field"}, {"shot": "aura", "target": "FX_magic_aura"},
                     {"shot": "cachoeira", "target": "FX_waterfall"}],
}
MAIN_VIEW = {"vfx_showcase": "camera"}
SIZE = (1280, 720)


def log(*a) -> None:
    print("[demos]", *a, flush=True)


def build(name: str, recipe: dict) -> None:
    client = VibeClient(ROOT, scene=recipe["scene"], mode="headless", timeout=1800)
    t = time.time()
    r = client.run([{"cmd": "world.build", "args": {"path": f"res://recipes/{name}.json"}}])
    res = (r.get("results") or [{}])[0]
    steps = res.get("result", {}).get("steps", [])
    bad = [s for s in steps if not s.get("ok")]
    log(f"{name}: built in {time.time() - t:.1f}s, {len(steps)} steps" + (f", FAILED: {bad}" if bad else ""))
    if not r.get("ok"):
        raise VibeError(f"{name}: {res.get('error') or bad}")


def shoot(name: str, recipe: dict) -> list[tuple[str, Path]]:
    client = VibeClient(ROOT, scene=recipe["scene"], mode="headless", timeout=1800)
    shots = [{"shot": "hero", "view": MAIN_VIEW.get(name, "hero")}, {"shot": "aerial", "view": "aerial"}]
    shots += SHOTS.get(name, [])
    cmds, out = [], []
    for s in shots:
        path = f"res://.vibe/screenshots/demos/{name}_{s['shot']}.png"
        args = {"path": path, "width": SIZE[0], "height": SIZE[1], "frames": int(s.get("frames", 16))}
        for k in ("view", "target", "position", "look_at"):
            if k in s:
                args[k] = s[k]
        cmds.append({"cmd": "screenshot", "args": args})
        out.append((s["shot"], ROOT / path.replace("res://", "")))
    t = time.time()
    r = client.run(cmds, keep_going=True)
    errors = [x.get("error") for x in r.get("results", []) if not x.get("ok")]
    log(f"{name}: {len(cmds)} screenshots in {time.time() - t:.1f}s" + (f", errors: {errors}" if errors else ""))
    return [(shot, p) for shot, p in out if p.exists()]


def export_images(name: str, files: list[tuple[str, Path]]) -> dict:
    from PIL import Image
    img_dir = ROOT / "docs" / "img"
    thumb_dir = ROOT / "demos" / "thumbs"
    img_dir.mkdir(parents=True, exist_ok=True)
    thumb_dir.mkdir(parents=True, exist_ok=True)
    images = []
    for shot, png in files:
        im = Image.open(png).convert("RGB")
        dst = img_dir / f"{name}_{shot}.webp"
        im.save(dst, "WEBP", quality=86, method=6)
        images.append(str(dst.relative_to(ROOT)))
        if shot == "hero":
            im.resize((480, 270), Image.LANCZOS).save(thumb_dir / f"{name}.webp", "WEBP", quality=85, method=6)
    return {"images": images, "thumb": f"res://demos/thumbs/{name}.webp"}


def contact_sheet(names: list[str]) -> None:
    from PIL import Image, ImageDraw
    tiles = [(n, ROOT / "docs" / "img" / f"{n}_hero.webp") for n in names]
    tiles = [(n, p) for n, p in tiles if p.exists()]
    if not tiles:
        return
    tw, th, cols = 640, 360, 3
    rows = (len(tiles) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw, rows * th), (14, 16, 22))
    for i, (n, p) in enumerate(tiles):
        im = Image.open(p).convert("RGB").resize((tw, th), Image.LANCZOS)
        d = ImageDraw.Draw(im)
        d.rectangle([0, th - 34, tw, th], fill=(0, 0, 0))
        d.text((12, th - 26), n, fill=(255, 255, 255))
        sheet.paste(im, ((i % cols) * tw, (i // cols) * th))
    sheet.save(ROOT / "docs" / "img" / "demos_sheet.webp", "WEBP", quality=84, method=6)
    log("contact sheet: docs/img/demos_sheet.webp")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("names", nargs="*", help="demo names (default: all)")
    ap.add_argument("--shots-only", action="store_true", help="only re-render screenshots")
    ap.add_argument("--no-shots", action="store_true", help="only build the scenes")
    a = ap.parse_args()
    names = a.names or ORDER
    manifest_path = ROOT / "demos" / "demos.json"
    manifest = {}
    if manifest_path.exists():
        manifest = {d["name"]: d for d in json.loads(manifest_path.read_text(encoding="utf-8")).get("demos", [])}
    failed = []
    for name in names:
        recipe = json.loads((ROOT / "recipes" / f"{name}.json").read_text(encoding="utf-8"))
        meta = recipe.get("meta", {})
        try:
            if not a.shots_only:
                build(name, recipe)
            entry = {"name": name, "title": meta.get("title", name), "subtitle": meta.get("subtitle", ""),
                     "prompt": meta.get("prompt", ""), "style": recipe.get("style", "realistic"),
                     "scene": recipe["scene"], "recipe": f"recipes/{name}.json"}
            if not a.no_shots:
                entry.update(export_images(name, shoot(name, recipe)))
            elif name in manifest:
                entry.update({k: manifest[name][k] for k in ("images", "thumb") if k in manifest[name]})
            manifest[name] = entry
        except (VibeError, OSError) as e:
            log(f"{name}: ERROR {e}")
            failed.append(name)
    ordered = [manifest[n] for n in ORDER if n in manifest] + [d for n, d in manifest.items() if n not in ORDER]
    manifest_path.write_text(json.dumps({"demos": ordered}, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    if not a.no_shots:
        contact_sheet([d["name"] for d in ordered])
    log("done" + (f"; failed: {failed}" if failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
