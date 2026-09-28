#!/usr/bin/env python3
"""Builds a test world and renders it in every art style (contact sheet).

    GODOT_BIN=/path/to/godot python3 tests/render_gallery.py [--recipe campo_noturno] [--out docs/img]

Needs a display (or xvfb-run on Linux).
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from vibe_client import VibeClient  # noqa: E402

STYLES = ["realistic", "stylized", "toon", "cel", "lowpoly"]


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--scene", default="res://tests/tmp/gallery.tscn")
    ap.add_argument("--prompt", default="colinas verdes com um lago, flores e uma fogueira ao entardecer")
    ap.add_argument("--styles", default=",".join(STYLES))
    ap.add_argument("--views", default="aerial,ground")
    ap.add_argument("--out", default="res://.vibe/screenshots")
    ap.add_argument("--size", default="960x540")
    ap.add_argument("--skip-build", action="store_true")
    a = ap.parse_args()
    w, h = (int(v) for v in a.size.split("x"))
    c = VibeClient(ROOT, scene=a.scene, mode="headless")
    if not a.skip_build:
        r = c.run([{"cmd": "vibe", "args": {"prompt": a.prompt, "scene": a.scene}}])
        print("build:", r.get("ok"), [s["cmd"] + ("" if s["ok"] else "!") for s in r["results"][0].get("result", {}).get("build", {}).get("steps", [])])
    cmds = []
    shots = []
    for style in a.styles.split(","):
        cmds.append({"cmd": "style.set", "args": {"style": style}})
        for view in a.views.split(","):
            path = f"{a.out}/gallery_{style}_{view}.png"
            args = {"path": path, "width": w, "height": h}
            if view.startswith("target:"):
                args["target"] = view.split(":", 1)[1]
            else:
                args["view"] = view
            cmds.append({"cmd": "screenshot", "args": args})
            shots.append(path)
    r = c.run(cmds, keep_going=True)
    print("render:", r.get("ok"), [(x.get("cmd"), x.get("ok"), x.get("error", "")) for x in r.get("results", []) if not x.get("ok")])
    try:
        from PIL import Image
    except ImportError:
        return 0
    files = [ROOT / p.replace("res://", "") for p in shots]
    files = [f for f in files if f.exists()]
    if not files:
        return 1
    ims = [Image.open(f).convert("RGB").resize((w // 2, h // 2)) for f in files]
    cols = len(a.views.split(","))
    rows = (len(ims) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * (w // 2), rows * (h // 2)), (20, 20, 20))
    for i, im in enumerate(ims):
        sheet.paste(im, ((i % cols) * (w // 2), (i // cols) * (h // 2)))
    out = ROOT / a.out.replace("res://", "") / "gallery_sheet.png"
    sheet.save(out)
    print("sheet:", out)
    return 0


if __name__ == "__main__":
    sys.exit(main())
