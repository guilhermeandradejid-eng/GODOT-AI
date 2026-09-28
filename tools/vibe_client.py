"""Shared client for the Godot Vibe Suite (used by vibe.py and vibe_mcp.py).

Two transports, chosen automatically:
  * live     - the Godot editor is open with the Vibe plugins: HTTP bridge on
               127.0.0.1 (port + token read from <project>/.godot/vibe_bridge.json).
               Changes appear instantly in the editor and are undoable (Ctrl+Z).
  * headless - no editor running: Godot is launched in the background
               (godot --headless --script res://addons/vibe_core/cli/vibe_cli.gd),
               the target scene is loaded, modified and saved.

Only the Python standard library is used.
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

MARKER = "@@VIBE@@"
CLI_SCRIPT = "res://addons/vibe_core/cli/vibe_cli.gd"
STATE_FILE = ".vibe/state.json"
BRIDGE_FILE = ".godot/vibe_bridge.json"
# Commands that must render frames (need a display in headless mode).
RENDER_COMMANDS = {"screenshot", "scene.screenshot", "editor.screenshot", "capture"}


class VibeError(RuntimeError):
    pass


def find_project(start: str | os.PathLike | None = None) -> Path:
    env = os.environ.get("VIBE_PROJECT")
    if env and (Path(env) / "project.godot").exists():
        return Path(env).resolve()
    here = Path(start or os.getcwd()).resolve()
    for p in [here, *here.parents]:
        if (p / "project.godot").exists():
            return p
    # Fallback: the repository that contains this tools/ folder.
    repo = Path(__file__).resolve().parent.parent
    if (repo / "project.godot").exists():
        return repo
    raise VibeError("project.godot not found (run inside the Godot project or pass --project)")


def find_godot(explicit: str | None = None) -> str:
    candidates = [explicit, os.environ.get("GODOT_BIN"), os.environ.get("GODOT"),
                  "godot4", "godot", "godot-4", "Godot", "godot.exe", "Godot_v4.exe"]
    for c in candidates:
        if not c:
            continue
        found = shutil.which(c)
        if found:
            return found
        if Path(c).exists():
            return str(Path(c))
    extra = [
        "/Applications/Godot.app/Contents/MacOS/Godot",
        "/Applications/Godot_mono.app/Contents/MacOS/Godot",
        str(Path.home() / "Applications/Godot.app/Contents/MacOS/Godot"),
        "C:/Program Files/Godot/Godot.exe",
        "/usr/local/bin/godot", "/usr/bin/godot", "/snap/bin/godot",
        str(Path.home() / ".local/bin/godot"), str(Path.home() / "bin/godot"),
    ]
    for c in extra:
        if Path(c).exists():
            return c
    raise VibeError("Godot binary not found. Set GODOT_BIN=/path/to/godot (Godot 4.3+) or add godot to PATH.")


def _pid_alive(pid: int) -> bool:
    if pid <= 0:
        return False
    if os.name == "nt":
        try:
            out = subprocess.run(["tasklist", "/FI", f"PID eq {pid}"], capture_output=True, text=True, timeout=5)
            return str(pid) in out.stdout
        except Exception:
            return True
    try:
        os.kill(pid, 0)
        return True
    except ProcessLookupError:
        return False
    except PermissionError:
        return True


class VibeClient:
    def __init__(self, project: str | os.PathLike | None = None, godot: str | None = None,
                 scene: str | None = None, mode: str = "auto", timeout: float = 600.0):
        self.project = find_project(project)
        self.godot = godot
        self.scene = scene
        self.mode = mode  # auto | live | headless
        self.timeout = timeout

    # ------------------------------------------------------------------ state
    def _state_path(self) -> Path:
        return self.project / STATE_FILE

    def load_state(self) -> dict:
        try:
            return json.loads(self._state_path().read_text(encoding="utf-8"))
        except Exception:
            return {}

    def save_state(self, **values) -> None:
        state = self.load_state()
        state.update(values)
        p = self._state_path()
        p.parent.mkdir(parents=True, exist_ok=True)
        (p.parent / ".gdignore").touch(exist_ok=True)
        p.write_text(json.dumps(state, indent=2), encoding="utf-8")

    # ------------------------------------------------------------------ live bridge
    def bridge_info(self) -> dict | None:
        f = self.project / BRIDGE_FILE
        if not f.exists():
            return None
        try:
            info = json.loads(f.read_text(encoding="utf-8"))
        except Exception:
            return None
        if not _pid_alive(int(info.get("pid", -1))):
            return None
        return info

    def _http(self, info: dict, method: str, path: str, payload: dict | None = None, timeout: float | None = None) -> dict:
        url = f"http://127.0.0.1:{info['port']}{path}"
        data = json.dumps(payload).encode("utf-8") if payload is not None else None
        req = urllib.request.Request(url, data=data, method=method)
        req.add_header("Content-Type", "application/json")
        req.add_header("X-Vibe-Token", info.get("token", ""))
        opener = urllib.request.build_opener(urllib.request.ProxyHandler({}))  # never proxy localhost
        try:
            with opener.open(req, timeout=timeout or self.timeout) as resp:
                return json.loads(resp.read().decode("utf-8"))
        except urllib.error.HTTPError as e:
            body = e.read().decode("utf-8", "replace")
            try:
                return json.loads(body)
            except Exception:
                raise VibeError(f"bridge HTTP {e.code}: {body[:300]}")

    def live_available(self) -> dict | None:
        info = self.bridge_info()
        if info is None:
            return None
        try:
            status = self._http(info, "GET", "/status", timeout=3)
            return info if status.get("ok") else None
        except Exception:
            return None

    # ------------------------------------------------------------------ headless
    def _ensure_imported(self, godot: str) -> None:
        cache = self.project / ".godot" / "global_script_class_cache.cfg"
        imported = self.project / ".godot" / "imported"
        if cache.exists() and imported.exists():
            return
        print("[vibe] First run: importing the Godot project (one time, may take a minute)...", file=sys.stderr)
        subprocess.run([godot, "--headless", "--path", str(self.project), "--import"],
                       capture_output=True, text=True, timeout=self.timeout)

    def _run_headless(self, commands: list[dict], render: bool = False, keep_going: bool = False) -> dict:
        godot = find_godot(self.godot)
        self._ensure_imported(godot)
        scene = self.scene or self.load_state().get("scene", "")
        args = [godot]
        if not render:
            args.append("--headless")
        args += ["--path", str(self.project), "--script", CLI_SCRIPT, "--"]
        if scene:
            args += ["--scene", scene]
        if keep_going:
            args.append("--keep-going")
        args += ["--cmd", json.dumps(commands)]
        env = dict(os.environ)
        if render and sys.platform.startswith("linux") and not env.get("DISPLAY") and not env.get("WAYLAND_DISPLAY"):
            if shutil.which("xvfb-run"):
                args = ["xvfb-run", "-a", "-s", "-screen 0 1920x1080x24"] + args
            else:
                raise VibeError("screenshots need a display (or xvfb-run) when the editor is not open")
        started = time.time()
        proc = subprocess.run(args, capture_output=True, text=True, timeout=self.timeout, env=env)
        for line in proc.stdout.splitlines():
            if line.startswith(MARKER):
                result = json.loads(line[len(MARKER):])
                result["seconds"] = round(time.time() - started, 2)
                if result.get("scene"):
                    self.save_state(scene=result["scene"])
                return result
        errors = [l for l in (proc.stderr + "\n" + proc.stdout).splitlines() if "ERROR" in l or "error" in l.lower()]
        raise VibeError("Godot did not return a result (exit %s).\n%s" % (proc.returncode, "\n".join(errors[-15:])))

    # ------------------------------------------------------------------ public API
    def run(self, commands: list[dict], keep_going: bool = False) -> dict:
        """Runs one or more commands. Returns {"ok", "mode", "results": [...]}."""
        live = None if self.mode == "headless" else self.live_available()
        if self.mode == "live" and live is None:
            raise VibeError("the Godot editor is not running with the Vibe plugins (no live bridge found)")
        if live is not None:
            if len(commands) == 1:
                r = self._http(live, "POST", "/cmd", commands[0])
                return {"ok": r.get("ok", False), "mode": "live", "results": [r]}
            r = self._http(live, "POST", "/batch", {"commands": commands, "stop_on_error": not keep_going})
            return {"ok": r.get("ok", False), "mode": "live", "results": r.get("results", [])}
        render = any(c.get("cmd") in RENDER_COMMANDS for c in commands)
        return self._run_headless(commands, render=render, keep_going=keep_going)

    def call(self, cmd: str, args: dict | None = None) -> dict:
        """Runs a single command and returns its result dict ({"ok", "result"|"error", ...})."""
        out = self.run([{"cmd": cmd, "args": args or {}}])
        results = out.get("results", [])
        r = results[0] if results else {"ok": False, "error": "no result"}
        r["mode"] = out.get("mode")
        if "saved" in out and out["saved"]:
            r["saved"] = out["saved"]
        return r

    def schema(self) -> list[dict]:
        live = None if self.mode == "headless" else self.live_available()
        if live is not None:
            try:
                return self._http(live, "GET", "/commands").get("commands", [])
            except Exception:
                pass
        snap = self.project / "addons" / "vibe_core" / "commands.schema.json"
        if snap.exists():
            return json.loads(snap.read_text(encoding="utf-8")).get("commands", [])
        godot = find_godot(self.godot)
        self._ensure_imported(godot)
        proc = subprocess.run([godot, "--headless", "--path", str(self.project), "--script", CLI_SCRIPT, "--", "--schema"],
                              capture_output=True, text=True, timeout=self.timeout)
        for line in proc.stdout.splitlines():
            if line.startswith(MARKER):
                return json.loads(line[len(MARKER):]).get("commands", [])
        return []
