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

ORDER = ["ilha_tropical", "galeria_animacoes", "montanhas_nevadas", "deserto_canion", "vulcao", "campo_noturno",
         "vale_cel", "arquipelago_lowpoly", "planeta_alien", "vfx_showcase"]

# Extra screenshots per demo (besides "hero" and "aerial").
SHOTS: dict[str, list[dict]] = {
    "ilha_tropical": [{"shot": "fogueira", "target": "Fogueira"}],
    "galeria_animacoes": [{"shot": "feitico", "target": "Feitico"}, {"shot": "aerial_bosque", "view": "aerial"}],
    "montanhas_nevadas": [{"shot": "alpinista", "target": "Alpinista"}],
    "deserto_canion": [{"shot": "fogueira", "target": "Fogueira"}],
    "vulcao": [{"shot": "pluma", "target": "Pluma"}],
    "campo_noturno": [{"shot": "portal", "target": "Portal"}, {"shot": "fogueira", "target": "Fogueira"}],
    "vale_cel": [{"shot": "chao", "view": "ground"}, {"shot": "ninja", "target": "Ninja"}],
    "arquipelago_lowpoly": [{"shot": "naufrago", "target": "Naufrago"}],
    "planeta_alien": [{"shot": "portal", "target": "Portal"}],
    "vfx_showcase": [{"shot": "fogueira", "target": "FX_campfire"}, {"shot": "portal", "target": "FX_portal"},
                     {"shot": "campo_de_forca", "target": "FX_force_field"}, {"shot": "aura", "target": "FX_magic_aura"}],
}
MAIN_VIEW = {"vfx_showcase": "camera", "galeria_animacoes": "camera"}
# Characters are frozen at this fraction of their animation for the pictures
# (a recipe character can set its own "pose").
POSE_FRACTION = 0.45
SIZE = (1280, 720)
# The VFX showcase also gets a labeled close-up of every effect, combined into
# docs/img/vfx_biblioteca.webp.
FX_LABELS = {"fire": "fogo", "campfire": "fogueira", "torch": "tocha", "embers": "brasas", "sparks": "faíscas",
             "smoke": "fumaça", "steam": "vapor", "volcano_plume": "pluma vulcânica", "magic_aura": "aura mágica",
             "portal": "portal", "heal": "cura", "force_field": "campo de força", "fountain": "fonte",
             "waterfall": "cachoeira", "bubbles": "bolhas", "fireflies": "vagalumes", "lightning": "raio",
             "explosion": "explosão", "shockwave": "onda de choque", "confetti": "confete"}
GRID_SIZE = (480, 270)


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
    fx_shots = []
    if name == "vfx_showcase":
        for v in recipe.get("vfx", []):
            shot = {"shot": "fx_" + v["preset"], "target": v["name"], "size": GRID_SIZE, "frames": 24}
            if v["preset"] in ("explosion", "shockwave", "confetti", "lightning"):
                # Trigger the one-shot/periodic effect right before capturing it.
                shot.update({"play": v["name"], "frames": {"lightning": 4, "shockwave": 4}.get(v["preset"], 8)})
            fx_shots.append(shot)
    cmds, out = [], []
    # Freeze every character in a telling pose (not saved: save=False below).
    for c in recipe.get("characters", []):
        if isinstance(c, dict) and int(c.get("count", 1)) == 1 and c.get("name"):
            cmds.append({"cmd": "motion.play", "args": {"character": c["name"], "fraction": float(c.get("pose", POSE_FRACTION))}})
    for s in shots + fx_shots:
        if fx_shots and s is fx_shots[0]:
            # Close-ups carry their own labels in the grid image: hide the 3D ones.
            for c in recipe.get("commands", []):
                if c["cmd"] == "node.add" and c["args"].get("type") == "Label3D":
                    cmds.append({"cmd": "node.set", "args": {"path": c["args"]["name"], "properties": {"visible": False}}})
        if "play" in s:
            cmds.append({"cmd": "vfx.play", "args": {"name": s["play"]}})
        path = f"res://.vibe/screenshots/demos/{name}_{s['shot']}.png"
        w, h = s.get("size", SIZE)
        args = {"path": path, "width": w, "height": h, "frames": int(s.get("frames", 16))}
        for k in ("view", "target", "position", "look_at"):
            if k in s:
                args[k] = s[k]
        cmds.append({"cmd": "screenshot", "args": args})
        out.append((s["shot"], ROOT / path.replace("res://", "")))
    t = time.time()
    r = client.run(cmds, keep_going=True, save=False)
    errors = [x.get("error") for x in r.get("results", []) if not x.get("ok")]
    log(f"{name}: {len(out)} screenshots in {time.time() - t:.1f}s" + (f", errors: {errors}" if errors else ""))
    return [(shot, p) for shot, p in out if p.exists()]


def export_images(name: str, files: list[tuple[str, Path]]) -> dict:
    from PIL import Image
    img_dir = ROOT / "docs" / "img"
    thumb_dir = ROOT / "demos" / "thumbs"
    img_dir.mkdir(parents=True, exist_ok=True)
    thumb_dir.mkdir(parents=True, exist_ok=True)
    images = []
    fx = [(shot[3:], png) for shot, png in files if shot.startswith("fx_")]
    if fx:
        images.append(vfx_grid(fx))
    for shot, png in files:
        if shot.startswith("fx_"):
            continue
        im = Image.open(png).convert("RGB")
        dst = img_dir / f"{name}_{shot}.webp"
        im.save(dst, "WEBP", quality=86, method=6)
        images.append(str(dst.relative_to(ROOT)))
        if shot == "hero":
            im.resize((480, 270), Image.LANCZOS).save(thumb_dir / f"{name}.webp", "WEBP", quality=85, method=6)
    return {"images": images, "thumb": f"res://demos/thumbs/{name}.webp"}


def vfx_grid(fx: list[tuple[str, Path]]) -> str:
    """Labeled 5-column grid with a close-up of every effect."""
    from PIL import Image, ImageDraw, ImageFont
    tw, th = GRID_SIZE
    cols = 5
    rows = (len(fx) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw, rows * th), (10, 12, 18))
    try:
        font = ImageFont.truetype("DejaVuSans-Bold.ttf", 22)
    except OSError:
        font = ImageFont.load_default()
    for i, (preset, png) in enumerate(fx):
        im = Image.open(png).convert("RGB").resize((tw, th), Image.LANCZOS)
        d = ImageDraw.Draw(im)
        label = f"{FX_LABELS.get(preset, preset)}  ·  {preset}"
        d.rectangle([0, th - 36, tw, th], fill=(0, 0, 0))
        d.text((12, th - 31), label, fill=(255, 255, 255), font=font)
        sheet.paste(im, ((i % cols) * tw, (i // cols) * th))
    dst = ROOT / "docs" / "img" / "vfx_biblioteca.webp"
    sheet.save(dst, "WEBP", quality=84, method=6)
    log("vfx grid: docs/img/vfx_biblioteca.webp")
    return str(dst.relative_to(ROOT))


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


def hub_screenshot() -> None:
    """Imports the new thumbnails and captures the demo hub with Godot's movie writer."""
    import os
    import shutil
    import subprocess
    import tempfile
    from vibe_client import find_godot
    from PIL import Image
    godot = find_godot(None)
    subprocess.run([godot, "--headless", "--path", str(ROOT), "--import"], capture_output=True, text=True, timeout=900)
    with tempfile.TemporaryDirectory() as tmp:
        out = Path(tmp) / "hub.png"
        cmd = [godot, "--path", str(ROOT), "--resolution", "1280x720", "--fixed-fps", "10", "--quit-after", "8",
               "--write-movie", str(out), "res://demos/demo_hub.tscn"]
        if sys.platform.startswith("linux") and not os.environ.get("DISPLAY") and shutil.which("xvfb-run"):
            cmd = ["xvfb-run", "-a", "-s", "-screen 0 1280x720x24"] + cmd
        subprocess.run(cmd, capture_output=True, text=True, timeout=600)
        frames = sorted(Path(tmp).glob("hub*.png"))
        if frames:
            Image.open(frames[-1]).convert("RGB").save(ROOT / "docs" / "img" / "hub.webp", "WEBP", quality=88, method=6)
            log("hub screenshot: docs/img/hub.webp")
        else:
            log("hub screenshot: no frames written (needs a display or xvfb-run)")


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
        hub_screenshot()
    log("done" + (f"; failed: {failed}" if failed else ""))
    return 1 if failed else 0


if __name__ == "__main__":
    sys.exit(main())
