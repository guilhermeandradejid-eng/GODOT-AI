#!/usr/bin/env python3
"""Installs the Godot Vibe Suite into another Godot 4.3+ project.

    python3 tools/install.py /path/to/my_game            # plugins + terminal tools + Claude Code setup
    python3 tools/install.py /path/to/my_game --no-claude
    python3 tools/install.py /path/to/my_game --force    # overwrite existing copies (update)

What it does:
  * copies addons/vibe_core, vibe_terrain, vibe_grass and vibe_vfx
  * copies tools/vibe.py, vibe_client.py and vibe_mcp.py
  * enables the four plugins in project.godot
  * Claude Code: adds the "godot-vibe" MCP server to .mcp.json, the slash commands
    to .claude/commands/ and a Vibe Suite section to CLAUDE.md
Standard library only.
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import sys
from pathlib import Path

SRC = Path(__file__).resolve().parent.parent
ADDONS = ["vibe_core", "vibe_terrain", "vibe_grass", "vibe_vfx"]
TOOLS = ["vibe.py", "vibe_client.py", "vibe_mcp.py"]
MARK_START = "<!-- vibe-suite:start -->"
MARK_END = "<!-- vibe-suite:end -->"


def copy_tree(src: Path, dst: Path, force: bool) -> str:
    if dst.exists():
        if not force:
            return f"kept    {dst} (exists; use --force to update)"
        shutil.rmtree(dst)
    shutil.copytree(src, dst, ignore=shutil.ignore_patterns("__pycache__", "*.pyc"))
    return f"copied  {dst}"


def enable_plugins(project_file: Path) -> str:
    text = project_file.read_text(encoding="utf-8")
    wanted = [f"res://addons/{a}/plugin.cfg" for a in ADDONS]
    m = re.search(r"^\[editor_plugins\]\s*\n(.*?)(?=^\[|\Z)", text, re.S | re.M)
    if m:
        section = m.group(1)
        em = re.search(r'^enabled=PackedStringArray\((.*?)\)\s*$', section, re.M)
        current = re.findall(r'"([^"]+)"', em.group(1)) if em else []
        merged = current + [w for w in wanted if w not in current]
        line = "enabled=PackedStringArray(" + ", ".join(f'"{p}"' for p in merged) + ")"
        section = section.replace(em.group(0), line) if em else line + "\n" + section
        text = text[:m.start(1)] + section + text[m.end(1):]
    else:
        line = "enabled=PackedStringArray(" + ", ".join(f'"{p}"' for p in wanted) + ")"
        text = text.rstrip() + "\n\n[editor_plugins]\n\n" + line + "\n"
    project_file.write_text(text, encoding="utf-8")
    return "enabled plugins in project.godot"


def setup_claude(target: Path, force: bool) -> list[str]:
    out = []
    mcp_path = target / ".mcp.json"
    data = {}
    if mcp_path.exists():
        try:
            data = json.loads(mcp_path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            return [f"skipped {mcp_path} (invalid JSON, add the godot-vibe server by hand)"]
    data.setdefault("mcpServers", {})["godot-vibe"] = {
        "type": "stdio", "command": "python3", "args": ["tools/vibe_mcp.py"], "env": {}}
    mcp_path.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")
    out.append(f"updated {mcp_path}")

    cmd_dir = target / ".claude" / "commands"
    cmd_dir.mkdir(parents=True, exist_ok=True)
    for f in sorted((SRC / ".claude" / "commands").glob("*.md")):
        dst = cmd_dir / f.name
        if dst.exists() and not force:
            out.append(f"kept    {dst}")
            continue
        shutil.copy2(f, dst)
        out.append(f"copied  {dst}")

    guide = (SRC / "CLAUDE.md").read_text(encoding="utf-8")
    body = guide[guide.index("## Como executar comandos"):] if "## Como executar comandos" in guide else guide
    block = f"{MARK_START}\n# Godot Vibe Suite (terreno, grama, VFX pelo terminal)\n\n{body.strip()}\n{MARK_END}\n"
    claude_md = target / "CLAUDE.md"
    text = claude_md.read_text(encoding="utf-8") if claude_md.exists() else ""
    if MARK_START in text and MARK_END in text:
        text = text[:text.index(MARK_START)] + block + text[text.index(MARK_END) + len(MARK_END):].lstrip("\n")
    else:
        text = (text.rstrip() + "\n\n" if text.strip() else "") + block
    claude_md.write_text(text, encoding="utf-8")
    out.append(f"updated {claude_md}")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("target", help="folder of the Godot project (contains project.godot)")
    ap.add_argument("--force", action="store_true", help="overwrite existing copies")
    ap.add_argument("--no-claude", action="store_true", help="skip .mcp.json / .claude / CLAUDE.md")
    a = ap.parse_args()
    target = Path(a.target).expanduser().resolve()
    if not (target / "project.godot").exists():
        print(f"error: {target} has no project.godot", file=sys.stderr)
        return 2
    if target == SRC:
        print("error: target is this repository", file=sys.stderr)
        return 2
    log = []
    (target / "addons").mkdir(exist_ok=True)
    for name in ADDONS:
        log.append(copy_tree(SRC / "addons" / name, target / "addons" / name, a.force))
    (target / "tools").mkdir(exist_ok=True)
    for name in TOOLS:
        dst = target / "tools" / name
        if dst.exists() and not a.force:
            log.append(f"kept    {dst}")
        else:
            shutil.copy2(SRC / "tools" / name, dst)
            log.append(f"copied  {dst}")
    log.append(enable_plugins(target / "project.godot"))
    if not a.no_claude:
        log += setup_claude(target, a.force)
    print("\n".join(log))
    print("\nPronto. Abra o projeto no Godot (4.3+) uma vez para importar os assets, depois:\n"
          f"  cd {target}\n  python3 tools/vibe.py status\n"
          "  python3 tools/vibe.py vibe \"ilha tropical ao pôr do sol com fogueira\" scene=res://scenes/ilha.tscn\n"
          "No Claude Code, use /mundo, /terreno, /grama, /vfx, /estilo, /screenshot ou as ferramentas MCP godot-vibe.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
