#!/usr/bin/env python3
"""Headless test suite for the Godot Vibe Suite.

    GODOT_BIN=/path/to/godot python3 tests/run_tests.py            # core tests
    GODOT_BIN=/path/to/godot python3 tests/run_tests.py --render   # + shader/render test (display or xvfb-run)

Checks: project import (no script errors), every command family through the
headless CLI, the prompt interpreter, the command schema snapshot and the MCP
server handshake. Exit code 0 = all good.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from vibe_client import CLI_SCRIPT, MARKER, VibeClient, find_godot  # noqa: E402

SCENE = "res://tests/tmp/test_scene.tscn"
FAILS: list[str] = []
PASSES = 0


def check(cond: bool, what: str, detail: object = "") -> bool:
    global PASSES
    if cond:
        PASSES += 1
        print(f"  ok   {what}")
    else:
        FAILS.append(what)
        print(f"  FAIL {what} {str(detail)[:400]}")
    return cond


def test_import(godot: str) -> None:
    print("[import]")
    proc = subprocess.run([godot, "--headless", "--path", str(ROOT), "--import"], capture_output=True, text=True, timeout=900)
    out = proc.stdout + proc.stderr
    bad = [l for l in out.splitlines() if re.search(r"SCRIPT ERROR|Parse Error|Failed to load script|Compile Error", l)]
    check(not bad, "project imports without script errors", bad[:5])


def run_batch(client: VibeClient, cmds: list[dict]) -> list[dict]:
    out = client.run(cmds, keep_going=True)
    return out.get("results", [])


def test_commands(client: VibeClient) -> None:
    print("[commands]")
    cmds = [
        {"cmd": "scene.new", "args": {"path": SCENE, "overwrite": True}},
        {"cmd": "terrain.create", "args": {"preset": "hills", "size": 64, "seed": 3, "palette": "temperate"}},
        {"cmd": "terrain.info", "args": {}},
        {"cmd": "terrain.height_at", "args": {"position": [0, 0]}},
        {"cmd": "terrain.sculpt", "args": {"op": "raise", "position": [0, 0], "radius": 8, "strength": 6}},
        {"cmd": "terrain.height_at", "args": {"position": [0, 0]}},
        {"cmd": "terrain.stamp", "args": {"shape": "lake", "position": [14, 14], "radius": 7, "height": 3}},
        {"cmd": "terrain.carve_path", "args": {"mode": "road", "seed": 2}},
        {"cmd": "terrain.paint", "args": {"layer": 2, "position": [0, 0], "radius": 5}},
        {"cmd": "terrain.erode", "args": {"type": "thermal", "iterations": 5}},
        {"cmd": "terrain.palette", "args": {"name": "autumn"}},
        {"cmd": "grass.create", "args": {"preset": "meadow", "name": "Grama"}},
        {"cmd": "grass.fill", "args": {"grass": "Grama", "density": 0.6}},
        {"cmd": "grass.info", "args": {"grass": "Grama"}},
        {"cmd": "grass.paint", "args": {"grass": "Grama", "position": [0, 0], "radius": 4, "erase": True}},
        {"cmd": "grass.set", "args": {"grass": "Grama", "blade_height": 0.7, "color_tip": "#a0c060"}},
        {"cmd": "vfx.spawn", "args": {"preset": "campfire", "position": "flat", "name": "Fogueira"}},
        {"cmd": "vfx.spawn", "args": {"preset": "explosão", "position": [5, 5], "name": "Boom"}},
        {"cmd": "vfx.set", "args": {"name": "Fogueira", "color": "blue", "scale": 1.5}},
        {"cmd": "vfx.remove", "args": {"name": "Boom"}},
        {"cmd": "env.set", "args": {"preset": "noite"}},
        {"cmd": "node.add", "args": {"type": "OmniLight3D", "name": "Luz", "position": [0, 5, 0], "properties": {"light_color": "#ffaa55", "omni_range": 12}}},
        {"cmd": "node.set", "args": {"path": "Luz", "properties": {"light_energy": 2.5}}},
        {"cmd": "node.get", "args": {"path": "Luz", "properties": ["light_energy"]}},
        {"cmd": "node.remove", "args": {"path": "Luz"}},
        {"cmd": "camera.add", "args": {"type": "fly", "view": "hero"}},
    ]
    for style in ["stylized", "toon", "cel", "lowpoly", "realistic"]:
        cmds.append({"cmd": "style.set", "args": {"style": style}})
    cmds += [
        {"cmd": "scene.tree", "args": {}},
        {"cmd": "status", "args": {}},
        {"cmd": "help", "args": {"command": "terrain.sculpt"}},
        {"cmd": "vfx.list", "args": {}},
        {"cmd": "env.list", "args": {}},
        {"cmd": "world.example", "args": {"name": "vulcao"}},
    ]
    t = time.time()
    res = run_batch(client, cmds)
    print(f"  ({len(res)} commands in {time.time() - t:.1f}s)")
    by_idx = {i: r for i, r in enumerate(res)}
    for i, c in enumerate(cmds):
        r = by_idx.get(i, {"ok": False, "error": "no result"})
        check(bool(r.get("ok")), f"{c['cmd']} {json.dumps(c['args'], ensure_ascii=False)[:60]}", r.get("error", ""))
    if len(res) >= 6:
        info = res[2].get("result", {})
        check(abs(float(info.get("size", 0)) - 64.0) < 0.01, "terrain.info reports size 64", info.get("size"))
        h0 = float(res[3].get("result", {}).get("height", 0))
        h1 = float(res[5].get("result", {}).get("height", 0))
        check(h1 > h0 + 1.0, "sculpt raise increases the height", (h0, h1))
    if len(res) > 13:
        cov = float(res[13].get("result", {}).get("coverage", 0))
        check(cov > 0.1, "grass.fill gives coverage", cov)
    saved = ROOT / "tests" / "tmp" / "test_scene.tscn"
    check(saved.exists(), "scene saved to disk", saved)
    data_dir = ROOT / "tests" / "tmp" / "test_scene_data"
    check(data_dir.exists() and any(data_dir.glob("*.res")), "generated data saved next to the scene", data_dir)


def test_world_build(client: VibeClient) -> None:
    print("[world.build]")
    recipe = {
        "scene": "res://tests/tmp/test_world.tscn", "style": "toon", "environment": "sunset",
        "terrain": {"preset": "island", "size": 64, "seed": 2, "palette": "tropical", "water": True,
                    "features": [{"type": "mountain", "at": "center", "radius": 12, "height": 10}]},
        "grass": [{"preset": "lush", "density": 0.8}, {"preset": "flowers", "name": "Flores", "density": 0.3}],
        "vfx": [{"preset": "campfire", "at": "beach"}, {"preset": "fireflies", "count": 2}],
        "camera": {"type": "fly", "view": "hero"},
        "commands": [{"cmd": "node.add", "args": {"type": "Label3D", "name": "Placa", "position": [0, 6, 0], "properties": {"text": "oi"}}}],
    }
    res = run_batch(client, [{"cmd": "world.build", "args": {"recipe": recipe}}])
    r = res[0] if res else {}
    steps = r.get("result", {}).get("steps", [])
    check(bool(r.get("ok")), "world.build builds a full recipe", [s for s in steps if not s.get("ok")] or r.get("error"))
    check(len(steps) >= 10, "world.build ran every step", len(steps))


def test_prompts(client: VibeClient) -> None:
    print("[prompts]")
    cases = [
        ("ilha tropical ao pôr do sol com fogueira e vagalumes",
         {"terrain.preset": "island", "terrain.palette": "tropical", "environment": "sunset", "vfx": ["campfire", "fireflies"]}),
        ("montanhas nevadas à noite com neve caindo, estilo toon",
         {"terrain.preset": "mountains", "terrain.palette": "snowy", "environment": "night", "style": "toon", "vfx": ["snowfall"]}),
        ("desert canyon at sunset with a river, low poly",
         {"terrain.preset": "canyon", "environment": "sunset", "style": "lowpoly", "features": ["river"]}),
        ("vulcão em erupção numa tempestade", {"terrain.preset": "volcano", "environment": "stormy"}),
        ("campo de trigo com flores ao amanhecer, cel shading", {"environment": "dawn", "style": "cel", "grass": ["wheat", "flowers"]}),
    ]
    cmds = [{"cmd": "vibe", "args": {"prompt": p, "apply": False}} for p, _ in cases]
    res = run_batch(client, cmds)
    for (prompt, exp), r in zip(cases, res):
        rec = r.get("result", {}).get("recipe", {})
        env = rec.get("environment")
        env = env.get("preset") if isinstance(env, dict) else env
        terrain = rec.get("terrain") or {}
        got = {
            "terrain.preset": terrain.get("preset"), "terrain.palette": terrain.get("palette"),
            "environment": env, "style": rec.get("style", "realistic"),
            "vfx": [v.get("preset") for v in rec.get("vfx", [])],
            "grass": [g.get("preset") for g in rec.get("grass", [])],
            "features": [f.get("type") for f in terrain.get("features", [])],
        }
        ok = True
        for k, v in exp.items():
            if isinstance(v, list):
                ok &= all(x in got[k] for x in v)
            else:
                ok &= got[k] == v
        check(ok and bool(r.get("ok")), f"vibe \"{prompt}\"", {k: got[k] for k in exp})


def test_schema(godot: str) -> None:
    print("[schema]")
    proc = subprocess.run([godot, "--headless", "--path", str(ROOT), "--script", CLI_SCRIPT, "--", "--schema"],
                          capture_output=True, text=True, timeout=300)
    live = None
    for line in proc.stdout.splitlines():
        if line.startswith(MARKER):
            live = json.loads(line[len(MARKER):])
    check(live is not None, "CLI prints the schema")
    if live is None:
        return
    snap = json.loads((ROOT / "addons" / "vibe_core" / "commands.schema.json").read_text(encoding="utf-8"))

    def shape(s: dict) -> dict:
        return {c["name"]: sorted((c.get("input_schema") or {}).get("properties", {}).keys()) for c in s["commands"]}
    a, b = shape(live), shape(snap)
    diff = sorted(k for k in set(a) | set(b) if a.get(k) != b.get(k))
    check(not diff, "commands.schema.json is up to date (regenerate with --write-schema)", diff)
    check(len(live["commands"]) >= 50, "50+ commands registered", len(live["commands"]))


def test_mcp() -> None:
    print("[mcp]")
    proc = subprocess.Popen([sys.executable, str(ROOT / "tools" / "vibe_mcp.py")], stdin=subprocess.PIPE,
                            stdout=subprocess.PIPE, text=True, cwd=str(ROOT))

    def rpc(msg: dict) -> dict:
        proc.stdin.write(json.dumps(msg) + "\n")
        proc.stdin.flush()
        return json.loads(proc.stdout.readline())
    try:
        init = rpc({"jsonrpc": "2.0", "id": 1, "method": "initialize",
                    "params": {"protocolVersion": "2025-06-18", "capabilities": {}, "clientInfo": {"name": "test", "version": "1"}}})
        check(init.get("result", {}).get("serverInfo", {}).get("name") == "godot-vibe", "MCP initialize", init)
        proc.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized"}) + "\n")
        tools = rpc({"jsonrpc": "2.0", "id": 2, "method": "tools/list"}).get("result", {}).get("tools", [])
        names = {t["name"] for t in tools}
        check(len(tools) >= 50 and {"terrain_sculpt", "grass_fill", "vfx_spawn", "screenshot", "godot_status"} <= names,
              "MCP tools/list exposes the commands", len(tools))
        call = rpc({"jsonrpc": "2.0", "id": 3, "method": "tools/call", "params": {"name": "vfx_list", "arguments": {}}})
        text = call.get("result", {}).get("content", [{}])[0].get("text", "")
        check(not call.get("result", {}).get("isError") and "campfire" in text, "MCP tools/call runs a command", text[:200])
    finally:
        proc.stdin.close()
        proc.terminate()
        proc.wait(timeout=10)


def test_render(client: VibeClient) -> None:
    print("[render]")
    shots = []
    cmds = [{"cmd": "scene.open", "args": {"path": SCENE}}]
    for style in ["realistic", "stylized", "toon", "cel", "lowpoly"]:
        path = f"res://tests/tmp/render_{style}.png"
        shots.append((style, ROOT / "tests" / "tmp" / f"render_{style}.png"))
        cmds += [{"cmd": "style.set", "args": {"style": style}},
                 {"cmd": "screenshot", "args": {"path": path, "view": "hero", "width": 320, "height": 180, "frames": 4}}]
    for _, p in shots:
        if p.exists():
            p.unlink()
    res = run_batch(client, cmds)
    check(all(r.get("ok") for r in res), "every style renders", [r.get("error") for r in res if not r.get("ok")])
    for style, p in shots:
        check(p.exists() and p.stat().st_size > 2000, f"screenshot {style}", p)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--render", action="store_true", help="also render every style (needs a display or xvfb-run)")
    ap.add_argument("--skip-import", action="store_true")
    a = ap.parse_args()
    godot = find_godot(None)
    print("godot:", godot)
    (ROOT / "tests" / "tmp").mkdir(parents=True, exist_ok=True)
    for p in (ROOT / "tests" / "tmp").glob("test_*"):
        shutil.rmtree(p) if p.is_dir() else p.unlink()
    client = VibeClient(ROOT, godot=godot, scene=SCENE, mode="headless", timeout=900)
    if not a.skip_import:
        test_import(godot)
    test_commands(client)
    test_world_build(VibeClient(ROOT, godot=godot, scene="res://tests/tmp/test_world.tscn", mode="headless", timeout=900))
    test_prompts(client)
    test_schema(godot)
    test_mcp()
    if a.render:
        test_render(client)
    print(f"\n{PASSES} passed, {len(FAILS)} failed")
    for f in FAILS:
        print("  -", f)
    return 1 if FAILS else 0


if __name__ == "__main__":
    os.environ.setdefault("PYTHONIOENCODING", "utf-8")
    sys.exit(main())
