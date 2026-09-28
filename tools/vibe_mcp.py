#!/usr/bin/env python3
"""MCP server (stdio) exposing every Godot Vibe Suite command as a tool.

Claude Code picks it up from .mcp.json. Tools are named after the commands
(terrain.sculpt -> terrain_sculpt). Screenshots are returned as images so the
model can look at the result. Standard library only.
"""
from __future__ import annotations

import base64
import json
import sys
import traceback
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from vibe_client import VibeClient, VibeError  # noqa: E402

SERVER_INFO = {"name": "godot-vibe", "version": "1.0.0"}
SUPPORTED_VERSIONS = ["2025-06-18", "2025-03-26", "2024-11-05"]
INSTRUCTIONS = (
    "Godot Vibe Suite: build 3D game worlds (terrain, grass, VFX, sky) in a Godot project. "
    "Start with godot_status. For a quick world use vibe (free text PT/EN) or world_build (recipe). "
    "Refine with terrain_*, grass_*, vfx_*, env_set, style_set. ALWAYS call screenshot after visual "
    "changes and look at the image before continuing. Positions: [x, z] snaps to the terrain surface; "
    "anchors like 'center', 'north', 'peak', 'flat', 'beach', 'valley', 'random' also work. "
    "Styles: realistic, stylized, toon, cel, lowpoly."
)

_client: VibeClient | None = None


def client() -> VibeClient:
    global _client
    if _client is None:
        _client = VibeClient(Path(__file__).resolve().parent.parent)
    return _client


def tool_name(cmd: str) -> str:
    name = cmd.replace(".", "_")
    return "godot_" + name if cmd in ("status", "help", "undo", "redo") else name


def load_tools() -> tuple[list[dict], dict]:
    tools, mapping = [], {}
    try:
        schema = client().schema()
    except Exception:  # noqa: BLE001
        schema = []
    for c in schema:
        name = tool_name(c["name"])
        desc = c.get("description", "")
        if c.get("editor_only"):
            desc += " (needs the Godot editor open)"
        if c.get("examples"):
            desc += " Example args: " + json.dumps(c["examples"][0], ensure_ascii=False)
        input_schema = c.get("input_schema") or {"type": "object", "properties": {}}
        input_schema.setdefault("type", "object")
        tools.append({"name": name, "description": desc[:1024], "inputSchema": input_schema})
        mapping[name] = c["name"]
    return tools, mapping


def send(msg: dict) -> None:
    sys.stdout.write(json.dumps(msg, ensure_ascii=False) + "\n")
    sys.stdout.flush()


def result(req_id, payload: dict) -> None:
    send({"jsonrpc": "2.0", "id": req_id, "result": payload})


def error(req_id, code: int, message: str) -> None:
    send({"jsonrpc": "2.0", "id": req_id, "error": {"code": code, "message": message}})


def call_tool(name: str, arguments: dict, mapping: dict) -> dict:
    cmd = mapping.get(name) or name.replace("godot_", "", 1).replace("_", ".", 1)
    try:
        r = client().call(cmd, arguments or {})
    except VibeError as e:
        return {"content": [{"type": "text", "text": json.dumps({"ok": False, "error": str(e)})}], "isError": True}
    content = [{"type": "text", "text": json.dumps(r, ensure_ascii=False, indent=1)}]
    res = r.get("result") if isinstance(r.get("result"), dict) else {}
    png = res.get("file") if cmd in ("screenshot",) else None
    if png and Path(png).exists():
        data = base64.b64encode(Path(png).read_bytes()).decode("ascii")
        content.append({"type": "image", "data": data, "mimeType": "image/png"})
    return {"content": content, "isError": not r.get("ok", False)}


def main() -> None:
    tools, mapping = [], {}
    for line in sys.stdin:
        line = line.strip()
        if not line:
            continue
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            error(None, -32700, "parse error")
            continue
        method = msg.get("method")
        req_id = msg.get("id")
        params = msg.get("params") or {}
        try:
            if method == "initialize":
                requested = params.get("protocolVersion", SUPPORTED_VERSIONS[0])
                version = requested if requested in SUPPORTED_VERSIONS else SUPPORTED_VERSIONS[0]
                result(req_id, {"protocolVersion": version, "capabilities": {"tools": {"listChanged": False}},
                                "serverInfo": SERVER_INFO, "instructions": INSTRUCTIONS})
            elif method == "notifications/initialized" or (method or "").startswith("notifications/"):
                continue
            elif method == "ping":
                result(req_id, {})
            elif method == "tools/list":
                if not tools:
                    tools, mapping = load_tools()
                result(req_id, {"tools": tools})
            elif method == "tools/call":
                if not mapping:
                    tools, mapping = load_tools()
                result(req_id, call_tool(params.get("name", ""), params.get("arguments") or {}, mapping))
            elif req_id is not None:
                error(req_id, -32601, f"method not found: {method}")
        except Exception as e:  # noqa: BLE001
            if req_id is not None:
                error(req_id, -32603, f"{type(e).__name__}: {e}\n{traceback.format_exc(limit=3)}")


if __name__ == "__main__":
    main()
