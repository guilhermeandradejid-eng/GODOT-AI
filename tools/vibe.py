#!/usr/bin/env python3
"""vibe - drive the Godot Vibe Suite from the terminal (made for Claude Code).

Examples
  python3 tools/vibe.py status
  python3 tools/vibe.py help                       # all commands
  python3 tools/vibe.py help terrain.sculpt        # one command in detail
  python3 tools/vibe.py vibe "ilha tropical ao pôr do sol com fogueira e vagalumes"
  python3 tools/vibe.py scene.new path=res://scenes/mundo.tscn
  python3 tools/vibe.py terrain.create preset=mountains size=512 palette=snowy style=realistic
  python3 tools/vibe.py terrain.sculpt op=raise position=[30,-20] radius=25 strength=15
  python3 tools/vibe.py grass.create preset=flowers && python3 tools/vibe.py grass.fill density=0.6 layer=0
  python3 tools/vibe.py vfx.spawn preset=campfire position=flat
  python3 tools/vibe.py env.set preset=sunset
  python3 tools/vibe.py style.set style=toon
  python3 tools/vibe.py screenshot view=aerial     # prints the PNG path (open it to SEE the result)
  python3 tools/vibe.py batch steps.json           # [{"cmd": ..., "args": {...}}, ...]
  python3 tools/vibe.py world.build path=res://recipes/ilha_tropical.json

Arguments are key=value pairs; values are parsed as JSON when possible
(numbers, true/false, [x,z] lists, {"a": 1} objects), otherwise used as text.
You can also pass --args '{"key": "value"}'.

Mode: uses the open Godot editor (live, undoable) when available; otherwise runs
Godot headless and saves the scene (remembered in .vibe/state.json).
Env: GODOT_BIN=/path/to/godot, VIBE_PROJECT=/path/to/project.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from vibe_client import VibeClient, VibeError  # noqa: E402

POSITIONAL_ARG = {"vibe": "prompt", "help": "command", "scene.new": "path", "scene.open": "path",
                  "scene.save": "path", "vfx.spawn": "preset", "vfx.describe": "preset", "env.set": "preset",
                  "style.set": "style", "world.example": "name", "screenshot": "path", "terrain.palette": "name"}


def parse_value(raw: str):
    try:
        return json.loads(raw)
    except (json.JSONDecodeError, ValueError):
        return raw


def build_args(cmd: str, tokens: list[str], extra_json: str | None) -> dict:
    args: dict = {}
    loose: list[str] = []
    for t in tokens:
        if "=" in t and not t.startswith("=") and t.split("=", 1)[0].replace("_", "").replace(".", "").isalnum():
            k, v = t.split("=", 1)
            args[k] = parse_value(v)
        else:
            loose.append(t)
    if loose:
        key = POSITIONAL_ARG.get(cmd)
        if key is None:
            raise VibeError(f"unexpected argument(s) {loose!r}; use key=value (see: help {cmd})")
        args[key] = " ".join(loose)
    if extra_json:
        args.update(json.loads(extra_json))
    return args


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(prog="vibe", description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("command", nargs="?", default="status")
    parser.add_argument("tokens", nargs="*")
    parser.add_argument("--args", dest="args_json", help="JSON object with arguments")
    parser.add_argument("--project", help="Godot project folder")
    parser.add_argument("--scene", help="target scene (headless mode)")
    parser.add_argument("--godot", help="Godot 4 binary")
    parser.add_argument("--headless", action="store_true", help="never use the open editor")
    parser.add_argument("--live", action="store_true", help="require the open editor")
    parser.add_argument("--keep-going", action="store_true", help="batch: continue after errors")
    parser.add_argument("--timeout", type=float, default=900.0)
    parser.add_argument("--compact", action="store_true", help="single-line JSON output")
    ns = parser.parse_args(argv)

    mode = "headless" if ns.headless else ("live" if ns.live else "auto")
    try:
        client = VibeClient(ns.project, ns.godot, ns.scene, mode, ns.timeout)
        if ns.command == "batch":
            if not ns.tokens:
                raise VibeError("usage: vibe batch steps.json")
            data = json.loads(Path(ns.tokens[0]).read_text(encoding="utf-8"))
            commands = data.get("commands", data) if isinstance(data, dict) else data
            out = client.run(commands, keep_going=ns.keep_going)
        elif ns.command == "schema":
            out = {"ok": True, "commands": client.schema()}
        else:
            args = build_args(ns.command, ns.tokens, ns.args_json)
            out = client.call(ns.command, args)
    except VibeError as e:
        out = {"ok": False, "error": str(e)}
    except Exception as e:  # noqa: BLE001
        out = {"ok": False, "error": f"{type(e).__name__}: {e}"}
    print(json.dumps(out, ensure_ascii=False, indent=None if ns.compact else 2))
    return 0 if out.get("ok") else 1


if __name__ == "__main__":
    sys.exit(main())
