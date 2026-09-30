#!/usr/bin/env python3
"""Makes the Godot Vibe Suite trailer (docs/video/trailer.mp4).

Everything on screen is rendered by the plugins themselves:
  1. shots  - animated camera moves over the demo scenes, recorded with
              Godot's movie writer (tools/trailer_shot.gd);
  2. stills - a world built command by command from the terminal, and one
              scene in the 5 art styles (vibe CLI screenshots);
  3. music  - a 120 BPM soundtrack synthesized here with numpy;
  4. edit   - cuts on the beat, titles, captions and a typing terminal, composed
              with Pillow and encoded with ffmpeg (from imageio-ffmpeg).

    GODOT_BIN=/path/to/godot python3 tools/make_trailer.py        # all steps, reusing cached renders
    python3 tools/make_trailer.py --only edit                     # re-edit (music + video) only
    python3 tools/make_trailer.py --force shots                   # re-record the shots

Needs Godot 4.3+ (Forward+ looks best), a display or xvfb-run, numpy, Pillow and
imageio-ffmpeg (pip install imageio-ffmpeg). Renders are cached in .vibe/trailer/.
Build the demos first (python3 tools/build_demos.py).
"""
from __future__ import annotations

import argparse
import json
import math
import os
import shutil
import subprocess
import sys
import textwrap
import time
import wave
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))
from vibe_client import VibeClient, find_godot  # noqa: E402

CACHE = ROOT / ".vibe" / "trailer"
OUT = ROOT / "docs" / "video" / "trailer.mp4"
POSTER = ROOT / "docs" / "img" / "trailer_poster.webp"
W, H, FPS = 1280, 720, 24
WARMUP = 24                      # frames recorded before each move starts (trimmed)
RENDER_SCALE = 1.0               # < 1: 3D rendered smaller and upscaled with FSR (faster)
BPM = 120.0
BEAT = 60.0 / BPM
SR = 44100
LENGTH = 60.0
ACCENT = (120, 255, 190)
WARM = (255, 196, 110)
REPO = "github.com/guilhermeandradejid-eng/GODOT-AI"

# --- shots (tools/trailer_shot.gd) -------------------------------------------------------------

FX_HIDE = ["DemoHUD"] + ["Label_" + n for n in ("fire", "campfire", "torch", "embers", "sparks", "smoke", "steam", "volcano_plume",
                                                 "magic_aura", "portal", "heal", "force_field", "fountain", "waterfall", "bubbles",
                                                 "fireflies", "lightning", "explosion", "shockwave", "confetti")]

SHOTS: dict[str, dict] = {
    "intro": {"scene": "res://demos/ilha_tropical.tscn", "duration": 4.4, "hide": ["DemoHUD", "Fireflies", "Fireflies2"],
              "camera": {"from_camera": "VibeCamera", "move": [8, 5, 16], "pan": 9}},
    "fogueira": {"scene": "res://demos/ilha_tropical.tscn", "duration": 4.3, "loop_animations": True, "anim_offset": 0.25,
                 "camera": {"orbit": "Fogueira", "base": "camera", "radius": 4.6, "height": 2.3, "from": -30, "to": 8, "focus": 0.9, "fov": 52}},
    "galeria": {"scene": "res://demos/galeria_animacoes.tscn", "duration": 4.3, "loop_animations": True, "anim_offset": 0.3,
                "camera": {"keys": [{"t": 0, "pos": [-10.5, 2.4, 6.4], "look": [-6.5, 1.6, 0], "fov": 48},
                                    {"t": 1, "pos": [10.5, 2.4, 6.4], "look": [6.5, 1.6, 0], "fov": 48}]}},
    "montanhas": {"scene": "res://demos/montanhas_nevadas.tscn", "duration": 4.3,
                  "camera": {"orbit": [0, 0, 0], "radius": 360, "height": 175, "from": -25, "to": 5, "focus": 25, "fov": 50}},
    "timelapse": {"scene": "res://demos/ilha_tropical.tscn", "duration": 4.3, "ease": False, "hide": ["DemoHUD", "Fireflies", "Fireflies2"],
                  "camera": {"from_camera": "VibeCamera", "move": [0, 9, -12], "pan": 22},
                  "timelapse": [["day", 0.0], ["sunset", 0.5], ["night", 1.0]]},
    "vulcao": {"scene": "res://demos/vulcao.tscn", "duration": 4.3,
               "camera": {"orbit": "Pluma", "base": "camera", "radius": 185, "height": -32, "from": -16, "to": 12, "focus": 6, "fov": 44}},
    "fx_portal": {"scene": "res://demos/vfx_showcase.tscn", "duration": 1.1, "hide": FX_HIDE,
                  "camera": {"orbit": "FX_portal", "base": "camera", "radius": 7.5, "height": 2.4, "from": -12, "to": 8, "focus": 1.6}},
    "fx_field": {"scene": "res://demos/vfx_showcase.tscn", "duration": 1.1, "hide": FX_HIDE,
                 "camera": {"orbit": "FX_force_field", "base": "camera", "radius": 9, "height": 3.0, "from": 10, "to": -10, "focus": 1.8}},
    "fx_explosion": {"scene": "res://demos/vfx_showcase.tscn", "duration": 1.1, "play": ["FX_explosion"], "hide": FX_HIDE,
                     "camera": {"orbit": "FX_explosion", "base": "camera", "radius": 11, "height": 3.5, "from": -8, "to": 8, "focus": 2.5}},
    "fx_fire": {"scene": "res://demos/vfx_showcase.tscn", "duration": 1.1, "hide": FX_HIDE,
                "camera": {"orbit": "FX_campfire", "base": "camera", "radius": 5, "height": 1.8, "from": 10, "to": -10, "focus": 0.8}},
    "noturno": {"scene": "res://demos/campo_noturno.tscn", "duration": 2.2, "loop_animations": True, "anim_offset": 0.5,
                "camera": {"orbit": "Mago", "base": "facing", "radius": 6.0, "height": 2.2, "from": 128, "to": 152, "focus": 1.3, "fov": 50}},
    "ninja": {"scene": "res://demos/vale_cel.tscn", "duration": 2.2, "loop_animations": True, "anim_offset": 0.35,
              "camera": {"orbit": "Ninja", "base": "facing", "radius": 4.6, "height": 1.6, "from": -30, "to": -5, "focus": 1.0, "fov": 50}},
    "alien": {"scene": "res://demos/planeta_alien.tscn", "duration": 2.2, "loop_animations": True, "anim_offset": 0.4,
              "camera": {"orbit": "Astronauta", "base": "facing", "radius": 6.5, "height": 2.4, "from": 132, "to": 152, "focus": 1.3, "fov": 50}},
    "arquipelago": {"scene": "res://demos/arquipelago_lowpoly.tscn", "duration": 2.2,
                    "camera": {"from_camera": "VibeCamera", "move": [5, 1.5, 14], "pan": 6}},
    "claude": {"scene": "res://demos/campo_noturno.tscn", "duration": 4.3, "loop_animations": True, "anim_offset": 0.2,
               "camera": {"orbit": "Fogueira", "base": "camera", "radius": 8.5, "height": 2.6, "from": 20, "to": -20, "focus": 0.8, "fov": 50}},
    "outro": {"scene": "res://demos/ilha_tropical.tscn", "duration": 6.3, "hide": ["DemoHUD", "Fireflies", "Fireflies2"],
              "camera": {"orbit": [0, 0, 0], "radius": 210, "height": 80, "from": -20, "to": 15, "focus": -10, "fov": 48}},
}

# --- stills (vibe CLI) ------------------------------------------------------------------------

BUILD_SCENE = "res://.vibe/trailer/construcao.tscn"
BUILD_CAM = {"position": [34, 16, 122], "look_at": [-6, 11, 8], "width": W, "height": H, "fov": 56, "frames": 60}
BUILD_PROMPT = 'vibe "ilha tropical ao pôr do sol com palmeiras, fogueira e alguém dançando"'
BUILD_STAGES = [
    # (log line shown in the terminal, commands, still name)
    ("", [{"cmd": "scene.new", "args": {"path": BUILD_SCENE, "overwrite": True}},
          {"cmd": "env.set", "args": {"preset": "day"}}], "b0_vazio"),
    ("terrain.create  island · palette tropical",
     [{"cmd": "terrain.create", "args": {"preset": "island", "size": 256, "seed": 11, "palette": "tropical", "water": False}}], "b1_terreno"),
    ("terrain.water   mar com ondas e espuma",
     [{"cmd": "terrain.water", "args": {"enabled": True}}], "b2_agua"),
    ("grass.fill      lush + flores",
     [{"cmd": "grass.create", "args": {"preset": "lush"}}, {"cmd": "grass.fill", "args": {"density": 0.9}},
      {"cmd": "grass.create", "args": {"preset": "flowers", "name": "Flores"}}, {"cmd": "grass.fill", "args": {"grass": "Flores", "density": 0.3}}],
     "b3_grama"),
    ("scatter.add     palmeiras · selva · rochas",
     [{"cmd": "scatter.add", "args": {"preset": "palms", "density": 1.3}}, {"cmd": "scatter.add", "args": {"preset": "jungle", "density": 0.35}},
      {"cmd": "scatter.add", "args": {"preset": "rocks", "density": 0.5}}], "b4_arvores"),
    ("env.set         sunset  ·  motion.character \"dança\"",
     [{"cmd": "vfx.spawn", "args": {"preset": "campfire", "name": "Fogueira", "position": "beach"}},
      {"cmd": "motion.character", "args": {"outfit": "casual", "position": "near:Fogueira", "text": "dança animado"}},
      {"cmd": "env.set", "args": {"preset": "sunset"}}], "b5_final"),
]
STYLE_SCENE = "res://.vibe/trailer/estilos.tscn"
STYLE_PROMPT = "colinas verdes com um lago, floresta, flores e uma fogueira"
STYLES = ["realistic", "stylized", "toon", "cel", "lowpoly"]

# --- edit -------------------------------------------------------------------------------------------

# (start, end, kind, params). Cuts land on the beat (0.5 s at 120 BPM).
TIMELINE = [
    (0.0, 4.0, "clip", {"shot": "intro"}),
    (4.0, 12.0, "buildup", {}),
    (12.0, 16.0, "clip", {"shot": "fogueira"}),
    (16.0, 20.0, "clip", {"shot": "galeria"}),
    (20.0, 24.0, "clip", {"shot": "montanhas"}),
    (24.0, 28.0, "clip", {"shot": "timelapse"}),
    (28.0, 32.0, "clip", {"shot": "vulcao"}),
    (32.0, 33.0, "clip", {"shot": "fx_portal"}),
    (33.0, 34.0, "clip", {"shot": "fx_field"}),
    (34.0, 35.0, "clip", {"shot": "fx_explosion"}),
    (35.0, 36.0, "clip", {"shot": "fx_fire"}),
    (36.0, 37.0, "card", {"title": "1 MUNDO", "sub": "5 ESTILOS DE ARTE", "bg": "style_realistic"}),
    (37.0, 38.0, "still", {"img": "style_realistic", "label": "REALISTIC"}),
    (38.0, 39.0, "still", {"img": "style_stylized", "label": "STYLIZED"}),
    (39.0, 40.0, "still", {"img": "style_toon", "label": "TOON"}),
    (40.0, 41.0, "still", {"img": "style_cel", "label": "CEL"}),
    (41.0, 42.0, "still", {"img": "style_lowpoly", "label": "LOW POLY"}),
    (42.0, 44.0, "clip", {"shot": "noturno"}),
    (44.0, 46.0, "clip", {"shot": "ninja"}),
    (46.0, 48.0, "clip", {"shot": "alien"}),
    (48.0, 50.0, "clip", {"shot": "arquipelago"}),
    (50.0, 54.0, "clip", {"shot": "claude"}),
    (54.0, 60.0, "clip", {"shot": "outro"}),
]
# (start, end, tag, caption, command)
CAPTIONS = [
    (12.0, 16.0, "ANIMAÇÃO POR TEXTO", "Descreva o movimento: o personagem anima", 'motion.character text="dança animado"'),
    (16.0, 20.0, "50 AÇÕES · PT / EN", "Sequências, humor, estilo · IA Kimodo · mocap", 'motion.generate text="faz polichinelos e uma reverência"'),
    (20.0, 24.0, "TERRENO", "11 geradores · pincéis · erosão · rios · 11 biomas", "terrain.create preset=mountains palette=snowy"),
    (24.0, 28.0, "CÉU & ÁGUA", "Nuvens iluminadas · ondas Gerstner · dia e noite", "env.set preset=sunset quality=ultra"),
    (28.0, 32.0, "25 EFEITOS VFX", "Lava, raios, fumaça, magia, clima", "vfx.spawn preset=volcano_plume position=peak"),
    (32.0, 36.0, "VFX", "Portal · campo de força · explosão · fogueira", "vfx.spawn preset=portal color=purple"),
    (42.0, 44.0, "12 PERSONAGENS", "Mago, astronauta, ninja, robô, cavaleiro...", 'motion.character outfit=wizard text="lança um feitiço"'),
    (44.0, 46.0, "CEL SHADING", "Anime em 2 tons, com contorno", "style.set style=cel"),
    (46.0, 48.0, "VEGETAÇÃO", "17 tipos: florestas, palmeiras, cactos, cristais", "scatter.add preset=alien_trees"),
    (48.0, 50.0, "LOW POLY", "Facetado, cores por triângulo", "style.set style=lowpoly"),
    (50.0, 54.0, "FEITO PARA O CLAUDE CODE", "MCP · 68 comandos · ponte ao vivo com o editor", "/animacao o mago abre um portal e todos comemoram"),
]
DROP = 12.0          # the beat drops on the first feature
OUTRO = 54.0


# ------------------------------------------------------------------------------------------------
# Rendering
# ------------------------------------------------------------------------------------------------

def log(*a) -> None:
    print("[trailer]", *a, flush=True)


def record_shots(godot: str, force: bool, names: list[str] | None = None) -> None:
    out_dir = CACHE / "shots"
    out_dir.mkdir(parents=True, exist_ok=True)
    for name, shot in SHOTS.items():
        if names and name not in names:
            continue
        out = out_dir / f"{name}.avi"
        if out.exists() and not force:
            continue
        part = out_dir / f"{name}.part.avi"  # renamed when complete (a killed run leaves no broken shot)
        s = dict(shot)
        s.setdefault("fps", FPS)
        s.setdefault("warmup", WARMUP)
        s.setdefault("render_scale", RENDER_SCALE)
        cmd = [godot, "--path", str(ROOT), "--fixed-fps", str(FPS), "--write-movie", str(part),
               "--script", "res://tools/trailer_shot.gd", "--", json.dumps(s)]
        if sys.platform.startswith("linux") and not os.environ.get("DISPLAY") and shutil.which("xvfb-run"):
            cmd = ["xvfb-run", "-a", "-s", f"-screen 0 {W}x{H}x24"] + cmd
        t = time.time()
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=7200)
        ok = p.returncode == 0 and part.exists() and part.stat().st_size > 0
        if ok:
            part.replace(out)
        log(f"shot {name}: {'ok' if ok else 'FAILED'} in {time.time() - t:.0f}s")
        if not ok:
            log("\n".join(l for l in (p.stdout + p.stderr).splitlines() if "ERROR" in l)[-2000:])


def render_stills(force: bool) -> None:
    out_dir = CACHE / "stills"
    out_dir.mkdir(parents=True, exist_ok=True)
    if force or not all((out_dir / f"{s[2]}.png").exists() for s in BUILD_STAGES):
        cmds = []
        for _line, stage_cmds, still in BUILD_STAGES:
            cmds += stage_cmds
            shot = dict(BUILD_CAM)
            shot["path"] = f"res://.vibe/trailer/stills/{still}.png"
            cmds.append({"cmd": "screenshot", "args": shot})
        t = time.time()
        r = VibeClient(ROOT, scene=BUILD_SCENE, mode="headless", timeout=7200).run(cmds, save=False)
        bad = [x.get("error") for x in r.get("results", []) if not x.get("ok")]
        log(f"build-up stills in {time.time() - t:.0f}s" + (f", errors: {bad}" if bad else ""))
    if force or not all((out_dir / f"style_{s}.png").exists() for s in STYLES):
        client = VibeClient(ROOT, scene=STYLE_SCENE, mode="headless", timeout=7200)
        cmds = [{"cmd": "scene.new", "args": {"path": STYLE_SCENE, "overwrite": True}},
                {"cmd": "vibe", "args": {"prompt": STYLE_PROMPT}}]
        for st in STYLES:
            cmds += [{"cmd": "style.set", "args": {"style": st}},
                     {"cmd": "screenshot", "args": {"view": "hero", "width": W, "height": H, "frames": 30,
                                                    "path": f"res://.vibe/trailer/stills/style_{st}.png"}}]
        t = time.time()
        r = client.run(cmds, save=False)
        bad = [x.get("error") for x in r.get("results", []) if not x.get("ok")]
        log(f"style stills in {time.time() - t:.0f}s" + (f", errors: {bad}" if bad else ""))


# ------------------------------------------------------------------------------------------------
# Music (numpy synth, 120 BPM, A minor: Am - F - C - G)
# ------------------------------------------------------------------------------------------------

CHORDS = [[57, 60, 64], [53, 57, 60], [48, 52, 55], [55, 59, 62]]
ROOTS = [45, 41, 36, 43]


def midi_hz(m: float) -> float:
    return 440.0 * 2.0 ** ((m - 69.0) / 12.0)


def additive(freq: float, n: int, cutoff: float, harmonics: int = 16, odd_only: bool = False) -> np.ndarray:
    """Band-limited saw (or square) through a soft lowpass at `cutoff` Hz."""
    t = np.arange(n) / SR
    out = np.zeros(n)
    ph = np.random.uniform(0, 2 * np.pi)
    for k in range(1, harmonics + 1):
        if odd_only and k % 2 == 0:
            continue
        f = freq * k
        if f > SR * 0.45:
            break
        g = (1.0 / k) * math.exp(-((f / max(cutoff, 1.0)) ** 2))
        if g < 1e-4:
            continue
        out += g * np.sin(2 * np.pi * f * t + ph * k)
    return out


def fft_filter(x: np.ndarray, lo: float = 0.0, hi: float = 1e9) -> np.ndarray:
    n = len(x)
    spec = np.fft.rfft(x)
    f = np.fft.rfftfreq(n, 1.0 / SR)
    gain = np.ones_like(f)
    if lo > 0:
        gain *= 1.0 / (1.0 + (lo / np.maximum(f, 1.0)) ** 4)
    if hi < 1e9:
        gain *= 1.0 / (1.0 + (f / hi) ** 4)
    return np.fft.irfft(spec * gain, n)


def sweep_noise(dur: float, f0: float, f1: float, rng: np.random.Generator) -> np.ndarray:
    """Noise through a band-pass whose center glides from f0 to f1 (block FFT, overlap-add)."""
    n = int(dur * SR)
    blk, hop = 2048, 1024
    x = rng.standard_normal(n + blk)
    out = np.zeros(n + blk)
    win = np.hanning(blk)
    freqs = np.fft.rfftfreq(blk, 1.0 / SR)
    for start in range(0, n, hop):
        u = start / max(n, 1)
        fc = f0 * (f1 / f0) ** u
        seg = x[start:start + blk] * win
        spec = np.fft.rfft(seg)
        g = np.exp(-((np.log2(np.maximum(freqs, 1.0) / fc)) ** 2) / 0.5)
        out[start:start + blk] += np.fft.irfft(spec * g, blk) * win
    return out[:n]


def place(buf: np.ndarray, sig: np.ndarray, t0: float, gain: float = 1.0, pan: float = 0.0) -> None:
    i = int(round(t0 * SR))
    if i >= len(buf):
        return
    j = min(len(buf), i + len(sig))
    s = sig[: j - i] * gain
    buf[i:j, 0] += s * math.cos((pan + 1) * math.pi / 4) * math.sqrt(2)
    buf[i:j, 1] += s * math.sin((pan + 1) * math.pi / 4) * math.sqrt(2)


def env_adsr(n: int, a: float, d: float, s: float, r: float, gate: float) -> np.ndarray:
    t = np.arange(n) / SR
    e = np.where(t < a, t / max(a, 1e-4), s + (1 - s) * np.exp(-(t - a) / max(d, 1e-4)))
    rel = np.clip(1.0 - (t - gate) / max(r, 1e-4), 0.0, 1.0)
    return e * np.where(t > gate, rel, 1.0)


def reverb(x: np.ndarray, seconds: float = 2.4, damp: float = 5000.0, seed: int = 3) -> np.ndarray:
    rng = np.random.default_rng(seed)
    n = int(seconds * SR)
    t = np.arange(n) / SR
    out = np.zeros_like(x)
    for ch in range(2):
        ir = rng.standard_normal(n) * np.exp(-t / (seconds / 5.5))
        ir = fft_filter(ir, hi=damp)
        ir[: int(0.012 * SR)] = 0.0
        ir /= np.sqrt(np.sum(ir ** 2))
        size = 1 << int(math.ceil(math.log2(len(x) + n)))
        y = np.fft.irfft(np.fft.rfft(x[:, ch], size) * np.fft.rfft(ir, size), size)[: len(x)]
        out[:, ch] = y
    return out


def typing_times() -> list[float]:
    """Moments a key is typed (shared by the terminal overlay and the click sounds)."""
    times = []
    t0, dt = BUILDUP_TYPE_START, BUILDUP_TYPE_DT
    for i, _c in enumerate("> " + BUILD_PROMPT):
        times.append(t0 + i * dt)
    cap = [c for c in CAPTIONS if c[2].startswith("FEITO PARA")][0]
    for i, _c in enumerate(cap[4]):
        times.append(cap[0] + 0.35 + i * 0.03)
    return times


def make_music(path: Path) -> None:
    rng = np.random.default_rng(7)
    n = int((LENGTH + 0.5) * SR)
    pads = np.zeros((n, 2))
    arp = np.zeros((n, 2))
    bass = np.zeros((n, 2))
    drums = np.zeros((n, 2))
    fx = np.zeros((n, 2))
    bars = int(LENGTH / (4 * BEAT))

    def section(t: float) -> str:
        if t < 4.0:
            return "intro"
        if t < DROP:
            return "build"
        if 36.0 <= t < 42.0:
            return "styles"
        if 50.0 <= t < OUTRO:
            return "break"
        if t >= OUTRO:
            return "outro"
        return "full"

    # Pads: one chord per bar, long release so bars overlap.
    for b in range(bars + 1):
        t0 = b * 4 * BEAT
        sec = section(t0)
        chord = CHORDS[b % 4]
        cutoff = {"intro": 700, "build": 900 + 300 * (t0 - 4.0), "full": 2600, "styles": 2600, "break": 1200, "outro": 1500}[sec]
        level = {"intro": 0.5, "build": 0.55, "full": 0.42, "styles": 0.42, "break": 0.5, "outro": 0.55}[sec]
        dur = 4 * BEAT + 1.2
        m = int(dur * SR)
        e = env_adsr(m, 0.35 if sec in ("intro", "outro", "break") else 0.08, 1.5, 0.8, 1.0, 4 * BEAT)
        for note in chord + [chord[0] - 12]:
            for det, pan in ((-0.09, -0.6), (0.0, 0.0), (0.09, 0.6)):
                sig = additive(midi_hz(note + det), m, cutoff, 18) * e
                place(pads, sig, t0, level * 0.11, pan)

    # Arpeggio (16ths) from the build-up on.
    pattern = [0, 1, 2, 1, 0, 2, 1, 2]
    for step in range(int(LENGTH / (BEAT / 4))):
        t0 = step * BEAT / 4
        sec = section(t0)
        if sec in ("intro",) or t0 >= LENGTH - 1.0:
            continue
        chord = CHORDS[int(t0 / (4 * BEAT)) % 4]
        note = chord[pattern[step % 8]] + 12 + (12 if step % 16 in (6, 14) else 0)
        cutoff = {"build": 700 + 350 * (t0 - 4.0), "full": 3800, "styles": 3800, "break": 1400, "outro": 1800}.get(sec, 2000)
        m = int(0.32 * SR)
        tt = np.arange(m) / SR
        sig = additive(midi_hz(note), m, cutoff, 10) * np.exp(-tt * 11) * (1 - np.exp(-tt * 400))
        lvl = {"build": 0.10 + 0.012 * (t0 - 4.0), "full": 0.16, "styles": 0.14, "break": 0.12, "outro": 0.1 * max(0.0, 1 - (t0 - OUTRO) / 5)}.get(sec, 0.12)
        place(arp, sig, t0, lvl, 0.35 if step % 2 else -0.35)

    # Drum and bass one-shots.
    m = int(0.45 * SR)
    tt = np.arange(m) / SR
    kick = np.sin(2 * np.pi * np.cumsum(46 + 120 * np.exp(-tt * 30)) / SR) * np.exp(-tt * 6.5)
    kick[: int(0.004 * SR)] += rng.standard_normal(int(0.004 * SR)) * 0.4
    clap = fft_filter(rng.standard_normal(int(0.3 * SR)), 900, 3200)
    ct = np.arange(len(clap)) / SR
    clap *= (np.exp(-ct * 22) + 0.6 * np.exp(-np.maximum(ct - 0.011, 0) * 60) * (ct > 0.011) + 0.5 * np.exp(-np.maximum(ct - 0.022, 0) * 60) * (ct > 0.022))
    clap /= np.max(np.abs(clap))
    hat = fft_filter(rng.standard_normal(int(0.09 * SR)), 7000)
    hat *= np.exp(-np.arange(len(hat)) / SR * 55)
    hat /= np.max(np.abs(hat))
    kick_times = []
    for beat in range(int(LENGTH / BEAT)):
        t0 = beat * BEAT
        sec = section(t0)
        if sec in ("full",) or (sec == "styles" and beat % 2 == 0):
            place(drums, kick, t0, 0.9)
            kick_times.append(t0)
            if sec == "full" and beat % 2 == 1:
                place(drums, clap, t0, 0.35)
        if sec == "full":
            for k in range(4):
                place(drums, hat, t0 + k * BEAT / 4, 0.065 if k % 2 else 0.035, 0.3)
        if sec == "build" and t0 >= 8.0:
            place(drums, hat, t0 + BEAT / 2, 0.06, 0.3)
        if sec in ("full", "styles"):
            root = ROOTS[int(t0 / (4 * BEAT)) % 4]
            for k in range(2):
                mb = int(0.24 * SR)
                sig = additive(midi_hz(root), mb, 380, 10) * env_adsr(mb, 0.005, 0.12, 0.6, 0.03, 0.2)
                place(bass, sig, t0 + k * BEAT / 2, 0.42)

    # Risers into the drop and the outro, hits and whooshes on the cuts.
    riser = sweep_noise(3.2, 300, 7000, rng) * np.linspace(0, 1, int(3.2 * SR)) ** 2
    riser /= np.max(np.abs(riser))
    place(fx, riser, DROP - 3.2, 0.32)
    place(fx, riser[: int(1.8 * SR)] / 1.0, OUTRO - 1.8, 0.2)
    boom_t = np.arange(int(2.5 * SR)) / SR
    boom = np.sin(2 * np.pi * np.cumsum(34 + 40 * np.exp(-boom_t * 5)) / SR) * np.exp(-boom_t * 1.8)
    crash = fft_filter(rng.standard_normal(len(boom_t)), 2500) * np.exp(-boom_t * 2.2)
    crash /= np.max(np.abs(crash))
    for t_hit, g in ((0.9, 0.5), (DROP, 0.9), (36.0, 0.6), (OUTRO, 0.9)):
        place(fx, boom, t_hit, g)
        place(fx, crash, t_hit, g * 0.22)
    whoosh = sweep_noise(0.55, 4000, 500, rng) * np.hanning(int(0.55 * SR))
    whoosh /= np.max(np.abs(whoosh))
    for seg in TIMELINE:
        if DROP < seg[0] < OUTRO and seg[0] not in (36.0,):
            place(fx, whoosh, seg[0] - 0.3, 0.1)
    for t_style in (37.0, 38.0, 39.0, 40.0, 41.0):
        place(fx, boom[: int(0.8 * SR)], t_style, 0.35)
    click = fft_filter(rng.standard_normal(int(0.012 * SR)), 1800, 6000) * np.exp(-np.arange(int(0.012 * SR)) / SR * 500)
    click /= np.max(np.abs(click))
    for i, tk in enumerate(typing_times()):
        place(fx, click, tk, 0.1 + 0.04 * ((i * 7) % 3), 0.2 * math.sin(i))

    # Sidechain: pads and bass duck under the kick.
    duck = np.ones(n)
    for tk in kick_times:
        i = int(tk * SR)
        m2 = min(n - i, int(0.3 * SR))
        duck[i:i + m2] = np.minimum(duck[i:i + m2], 1 - 0.55 * np.exp(-np.arange(m2) / SR * 14))
    pads *= duck[:, None]
    bass *= duck[:, None]
    wet = reverb(pads * 0.6 + arp * 0.8 + drums * 0.08 + fx * 0.2)
    mix = pads + arp + bass + drums + fx * 0.9 + wet * 0.35
    fade = np.ones(n)
    fade[int((LENGTH - 2.0) * SR):] = np.linspace(1, 0, n - int((LENGTH - 2.0) * SR)) ** 1.5
    fade[: int(0.3 * SR)] = np.linspace(0, 1, int(0.3 * SR))
    mix *= fade[:, None]
    mix = np.tanh(mix * 1.1) / math.tanh(1.1)
    mix *= 0.89 / max(np.max(np.abs(mix)), 1e-6)
    pcm = (mix[: int(LENGTH * SR)] * 32767).astype(np.int16)
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2)
        w.setsampwidth(2)
        w.setframerate(SR)
        w.writeframes(pcm.tobytes())
    log(f"music: {path.relative_to(ROOT)} ({LENGTH:.0f}s)")


# ------------------------------------------------------------------------------------------------
# Edit
# ------------------------------------------------------------------------------------------------

BUILDUP_TYPE_START = 4.35
BUILDUP_TYPE_DT = 0.028
BUILDUP_STAGE_TIMES = [4.0, 6.6, 7.6, 8.6, 9.6, 10.6]   # when each still (and log line) appears
FONT_DIRS = ["/usr/share/fonts/truetype/liberation", "/usr/share/fonts/truetype/dejavu", "/usr/share/fonts",
             "/Library/Fonts", "C:/Windows/Fonts"]


def font(names: list[str], size: int) -> ImageFont.FreeTypeFont:
    for d in FONT_DIRS:
        for nm in names:
            p = Path(d) / nm
            if p.exists():
                return ImageFont.truetype(str(p), size)
    for nm in names:
        try:
            return ImageFont.truetype(nm, size)
        except OSError:
            pass
    return ImageFont.load_default()


F_TITLE = lambda s: font(["LiberationSans-Bold.ttf", "DejaVuSans-Bold.ttf", "arialbd.ttf", "Arial Bold.ttf"], s)  # noqa: E731
F_TEXT = lambda s: font(["LiberationSans-Regular.ttf", "DejaVuSans.ttf", "arial.ttf", "Arial.ttf"], s)  # noqa: E731
F_MONO = lambda s: font(["DejaVuSansMono.ttf", "LiberationMono-Regular.ttf", "consola.ttf", "Menlo.ttc"], s)  # noqa: E731
F_CHECK = lambda s: font(["DejaVuSans-Bold.ttf", "seguisym.ttf", "Apple Symbols.ttf"], s)  # noqa: E731
F_MONO_B = lambda s: font(["DejaVuSansMono-Bold.ttf", "LiberationMono-Bold.ttf", "consolab.ttf", "Menlo.ttc"], s)  # noqa: E731


class Clips:
    """Decodes the recorded shots on demand (one or two in memory at a time)."""

    def __init__(self) -> None:
        self.cache: dict[str, np.ndarray] = {}

    def frame(self, name: str, t: float) -> np.ndarray:
        if name not in self.cache:
            import imageio_ffmpeg
            path = CACHE / "shots" / f"{name}.avi"
            if not path.exists():
                raise SystemExit(f"missing shot {path} (run without --only edit first)")
            gen = imageio_ffmpeg.read_frames(str(path), pix_fmt="rgb24")
            meta = next(gen)
            w, h = meta["size"]
            frames = [np.frombuffer(f, np.uint8).reshape(h, w, 3) for f in gen]
            arr = np.stack(frames)
            if (w, h) != (W, H):
                arr = np.stack([np.asarray(Image.fromarray(f).resize((W, H), Image.LANCZOS)) for f in arr])
            if len(self.cache) >= 2:
                self.cache.pop(next(iter(self.cache)))
            self.cache[name] = arr
        arr = self.cache[name]
        i = min(WARMUP + int(round(t * FPS)), len(arr) - 1)
        return arr[i]


_still_cache: dict[str, Image.Image] = {}


def still(name: str) -> Image.Image:
    if name not in _still_cache:
        p = CACHE / "stills" / f"{name}.png"
        _still_cache[name] = Image.open(p).convert("RGB").resize((W, H), Image.LANCZOS) if p.exists() else Image.new("RGB", (W, H), (20, 24, 30))
    return _still_cache[name]


def ken_burns(img: Image.Image, u: float, zoom: float = 0.07, drift=(0.0, 0.0)) -> Image.Image:
    s = 1.0 + zoom * u
    cw, ch = W / s, H / s
    cx = W / 2 + drift[0] * W * u
    cy = H / 2 + drift[1] * H * u
    box = (cx - cw / 2, cy - ch / 2, cx + cw / 2, cy + ch / 2)
    return img.resize((W, H), Image.BICUBIC, box=box)


def smooth(x: float) -> float:
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def text_layer(text: str, fnt: ImageFont.FreeTypeFont, fill, spacing: int = 0, glow: int = 0, shadow: bool = True) -> Image.Image:
    """RGBA image with the text (letter-spaced), a soft shadow and an optional glow."""
    widths = [fnt.getlength(c) for c in text]
    tw = int(sum(widths) + spacing * max(len(text) - 1, 0)) + 8
    asc, desc = fnt.getmetrics()
    th = asc + desc + 8
    pad = 30
    layer = Image.new("RGBA", (tw + pad * 2, th + pad * 2), (0, 0, 0, 0))
    d = ImageDraw.Draw(layer)
    x = pad + 4
    for c, wdt in zip(text, widths):
        d.text((x, pad + 4), c, font=fnt, fill=fill)
        x += wdt + spacing
    out = Image.new("RGBA", layer.size, (0, 0, 0, 0))
    if shadow:
        sh = Image.new("RGBA", layer.size, (0, 0, 0, 0))
        sh.putalpha(layer.getchannel("A").point(lambda a: a * 0.75))
        sh = sh.filter(ImageFilter.GaussianBlur(6))
        out.alpha_composite(sh, (2, 3))
    if glow:
        g = Image.new("RGBA", layer.size, fill[:3] + (0,))
        g.putalpha(layer.getchannel("A").filter(ImageFilter.GaussianBlur(glow)).point(lambda a: min(255, a * 1.6)))
        out.alpha_composite(g)
    out.alpha_composite(layer)
    return out


def paste(base: Image.Image, layer: Image.Image, cx: float, cy: float, alpha: float = 1.0, scale: float = 1.0, anchor: str = "center") -> None:
    if alpha <= 0.004:
        return
    if abs(scale - 1.0) > 1e-3:
        layer = layer.resize((max(1, int(layer.width * scale)), max(1, int(layer.height * scale))), Image.LANCZOS)
    if alpha < 0.999:
        a = layer.getchannel("A").point(lambda v: int(v * alpha))
        layer = layer.copy()
        layer.putalpha(a)
    if anchor == "center":
        x, y = int(cx - layer.width / 2), int(cy - layer.height / 2)
    elif anchor == "right":
        x, y = int(cx - layer.width + 30), int(cy - layer.height / 2)
    else:  # left
        x, y = int(cx - 30), int(cy - layer.height / 2)
    base.alpha_composite(layer, (x, y))


_layers: dict = {}


def cached_text(key: str, *args, **kw) -> Image.Image:
    if key not in _layers:
        _layers[key] = text_layer(*args, **kw)
    return _layers[key]


def vignette() -> Image.Image:
    if "vignette" not in _layers:
        yy, xx = np.mgrid[0:H, 0:W]
        r = np.sqrt(((xx - W / 2) / (W / 2)) ** 2 + ((yy - H / 2) / (H / 2)) ** 2)
        a = np.clip((r - 0.75) / 0.7, 0, 1) ** 1.6 * 150
        v = np.zeros((H, W, 4), np.uint8)
        v[..., 3] = a.astype(np.uint8)
        _layers["vignette"] = Image.fromarray(v, "RGBA")
    return _layers["vignette"]


def lower_third(img: Image.Image, t: float, cap) -> None:
    start, end, tag, caption, command = cap
    u_in = smooth((t - start) / 0.35)
    u_out = smooth((end - t) / 0.3)
    a = min(u_in, u_out)
    if a <= 0:
        return
    grad = _layers.get("grad")
    if grad is None:
        g = np.zeros((230, W, 4), np.uint8)
        g[..., 3] = (np.linspace(0, 1, 230) ** 1.4 * 190).astype(np.uint8)[:, None]
        grad = _layers["grad"] = Image.fromarray(g, "RGBA")
    paste(img, grad, W / 2, H - 115, a)
    slide = (1 - u_in) * 40
    x0 = 70 - slide
    paste(img, cached_text("tag:" + tag, tag, F_TITLE(26), ACCENT + (255,), spacing=4, shadow=True), x0, H - 150, a, anchor="left")
    paste(img, cached_text("cap:" + caption, caption, F_TITLE(38), (255, 255, 255, 255), shadow=True), x0, H - 108, a, anchor="left")
    # The command types in.
    shown = command[: max(0, int((t - start - 0.25) / 0.022))]
    if shown:
        prompt = "> " if not command.startswith("/") else "> "
        lay = text_layer(prompt + shown + ("_" if int(t * 3) % 2 == 0 and len(shown) < len(command) else ""), F_MONO(22), (210, 225, 235, 255), shadow=True)
        paste(img, lay, x0, H - 62, a, anchor="left")


def terminal(img: Image.Image, t: float) -> None:
    """The build-up terminal: the prompt types in, then one log line per command."""
    a = smooth((t - 4.0) / 0.3) * smooth((12.0 - t) / 0.25)
    if a <= 0:
        return
    pw, ph = 700, 262
    x0, y0 = 48, H - ph - 44
    panel = _layers.get("panel")
    if panel is None:
        panel = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
        d = ImageDraw.Draw(panel)
        d.rounded_rectangle([0, 0, pw - 1, ph - 1], 14, fill=(12, 16, 22, 215), outline=(90, 110, 130, 140), width=1)
        d.rounded_rectangle([0, 0, pw - 1, 34], 14, fill=(30, 36, 46, 235))
        d.rectangle([0, 20, pw - 1, 34], fill=(30, 36, 46, 235))
        for i, c in enumerate([(255, 95, 86), (255, 189, 46), (39, 201, 63)]):
            d.ellipse([16 + i * 22, 11, 28 + i * 22, 23], fill=c + (255,))
        d.text((pw / 2 - 90, 9), "claude  —  ~/meu-jogo", font=F_TEXT(16), fill=(170, 180, 190, 255))
        panel = _layers["panel"] = panel
    layer = panel.copy()
    d = ImageDraw.Draw(layer)
    mono = F_MONO(19)
    mono_b = F_MONO_B(19)
    full = "> " + BUILD_PROMPT
    n = max(0, int((t - BUILDUP_TYPE_START) / BUILDUP_TYPE_DT) + 1) if t >= BUILDUP_TYPE_START else 0
    # Wrap the whole prompt at word boundaries, then reveal it character by character.
    wrapped = textwrap.wrap(full, 56) or [""]
    shown, left = [], n
    for ln in wrapped:
        if left <= 0:
            break
        shown.append(ln[:left])
        left -= len(ln) + 1
    shown = shown or [""]
    y = 48
    for ln in shown:
        d.text((18, y), ln, font=mono_b, fill=(235, 240, 245, 255))
        y += 25
    if n < len(full) and int(t * 3) % 2 == 0:
        d.rectangle([18 + mono.getlength(shown[-1]), y - 25, 28 + mono.getlength(shown[-1]), y - 5], fill=ACCENT + (255,))
    y = 48 + 25 * len(wrapped) + 8
    for k, (line, _c, _s) in enumerate(BUILD_STAGES[1:], start=1):
        tk = BUILDUP_STAGE_TIMES[k]
        if t < tk - 0.25:
            break
        done = t >= tk
        d.text((18, y - 1), "✓" if done else "·", font=F_CHECK(20), fill=ACCENT + (255,) if done else (150, 160, 170, 255))
        d.text((44, y), line, font=mono, fill=(200, 210, 220, 255))
        y += 25
    layer.putalpha(layer.getchannel("A").point(lambda v: int(v * a)))
    img.alpha_composite(layer, (x0, y0))


def buildup_frame(t: float) -> Image.Image:
    idx = 0
    for k, tk in enumerate(BUILDUP_STAGE_TIMES):
        if t >= tk:
            idx = k
    cur = still(BUILD_STAGES[idx][2])
    u = (t - 4.0) / 8.0
    frame = ken_burns(cur, u, 0.08, (0.01, -0.01))
    tk = BUILDUP_STAGE_TIMES[idx]
    if idx > 0 and t - tk < 0.35:
        prev = ken_burns(still(BUILD_STAGES[idx - 1][2]), u, 0.08, (0.01, -0.01))
        frame = Image.blend(prev, frame, smooth((t - tk) / 0.35))
    return frame


def title_card(img: Image.Image, title: str, sub: str, t: float, t0: float, t1: float) -> None:
    a = smooth((t - t0) / 0.2) * smooth((t1 - t) / 0.15)
    sc = 1.08 - 0.08 * smooth((t - t0) / 0.6)
    paste(img, cached_text("t:" + title, title, F_TITLE(120), (255, 255, 255, 255), spacing=10, glow=12), W / 2, H / 2 - 40, a, sc)
    paste(img, cached_text("s:" + sub, sub, F_TITLE(40), ACCENT + (255,), spacing=8), W / 2, H / 2 + 60, a)


def compose(t: float, clips: Clips) -> Image.Image:
    seg = TIMELINE[-1]
    for s in TIMELINE:
        if s[0] <= t < s[1]:
            seg = s
            break
    start, end, kind, p = seg
    lt = t - start
    if kind == "clip":
        frame = Image.fromarray(clips.frame(p["shot"], lt))
    elif kind == "buildup":
        frame = buildup_frame(t)
    elif kind == "still":
        frame = ken_burns(still(p["img"]), lt / (end - start), 0.05)
    else:  # card
        frame = still(p["bg"]).filter(ImageFilter.GaussianBlur(14))
        frame = Image.blend(frame, Image.new("RGB", (W, H), (8, 10, 14)), 0.55)
    img = frame.convert("RGBA")
    img.alpha_composite(vignette())

    # Titles and captions.
    if t < 4.0:
        a = smooth((t - 0.9) / 0.5) * smooth((3.9 - t) / 0.3)
        sc = 1.12 - 0.12 * smooth((t - 0.9) / 1.6)
        paste(img, cached_text("title", "GODOT VIBE SUITE", F_TITLE(104), (255, 255, 255, 255), spacing=12, glow=14), W / 2, H / 2 - 30, a, sc)
        a2 = smooth((t - 1.8) / 0.5) * smooth((3.9 - t) / 0.3)
        paste(img, cached_text("tag1", "Mundos 3D criados conversando com o Claude", F_TEXT(34), (235, 240, 245, 255)), W / 2, H / 2 + 50, a2)
    if 4.0 <= t < 12.0:
        terminal(img, t)
        a = smooth((t - 4.2) / 0.4) * smooth((11.8 - t) / 0.3)
        paste(img, cached_text("desc", "DESCREVA.", F_TITLE(64), (255, 255, 255, 255), spacing=6, glow=8), W - 50, 90,
              a * smooth((t - 4.2) / 0.4) * smooth((6.5 - t) / 0.3), anchor="right")
        paste(img, cached_text("veja", "O MUNDO SE MONTA.", F_TITLE(56), ACCENT + (255,), spacing=5, glow=8), W - 50, 90,
              smooth((t - 6.7) / 0.4) * smooth((11.8 - t) / 0.3), anchor="right")
    if kind == "card":
        title_card(img, p["title"], p["sub"], t, start, end)
    if kind == "still":
        a = smooth(lt / 0.12)
        paste(img, cached_text("st:" + p["label"], p["label"], F_TITLE(84), (255, 255, 255, 255), spacing=10, glow=10), 80, H - 110, a, 1.0, anchor="left")
        paste(img, cached_text("stc", "style.set", F_MONO(24), ACCENT + (255,)), 80, H - 170, a, 1.0, anchor="left")
    for cap in CAPTIONS:
        if cap[0] <= t < cap[1]:
            lower_third(img, t, cap)
    if t >= OUTRO:
        u = t - OUTRO
        a = smooth((u - 0.4) / 0.6)
        sc = 1.1 - 0.1 * smooth((u - 0.4) / 1.8)
        paste(img, cached_text("title2", "GODOT VIBE SUITE", F_TITLE(96), (255, 255, 255, 255), spacing=12, glow=14), W / 2, H / 2 - 70, a, sc)
        paste(img, cached_text("feat", "terreno · grama · vegetação · céu · água · VFX · animação por texto", F_TEXT(30), (235, 240, 245, 255)),
              W / 2, H / 2 + 5, smooth((u - 1.0) / 0.6))
        paste(img, cached_text("spec", "Godot 4.3+  ·  6 plugins  ·  68 comandos  ·  5 estilos  ·  MCP para Claude Code", F_TEXT(24), ACCENT + (255,)),
              W / 2, H / 2 + 50, smooth((u - 1.5) / 0.6))
        paste(img, cached_text("repo", REPO, F_MONO_B(26), (255, 255, 255, 255)), W / 2, H / 2 + 110, smooth((u - 2.0) / 0.6))

    # Flash on the drop, fades at both ends.
    out = img.convert("RGB")
    flash = max(0.0, 1.0 - abs(t - DROP) / 0.12) if t >= DROP - 0.04 else 0.0
    flash = max(flash, 0.55 * max(0.0, 1.0 - abs(t - 36.0) / 0.1))
    if flash > 0:
        out = Image.blend(out, Image.new("RGB", (W, H), (255, 255, 255)), min(flash, 1.0) * 0.8)
    fade = smooth(t / 0.8) * smooth((LENGTH - t) / 1.4)
    if fade < 0.999:
        out = Image.blend(Image.new("RGB", (W, H), (0, 0, 0)), out, fade)
    return out


def edit(music: Path) -> None:
    import imageio_ffmpeg
    OUT.parent.mkdir(parents=True, exist_ok=True)
    clips = Clips()
    n = int(LENGTH * FPS)
    writer = imageio_ffmpeg.write_frames(str(OUT), (W, H), fps=FPS, codec="libx264", pix_fmt_out="yuv420p", quality=None,
                                         output_params=["-crf", "27", "-preset", "slow", "-movflags", "+faststart", "-b:a", "192k"],
                                         audio_path=str(music), audio_codec="aac", macro_block_size=8)
    writer.send(None)
    t0 = time.time()
    poster_t = OUTRO + 3.2
    for i in range(n):
        t = i / FPS
        frame = compose(t, clips)
        if abs(t - poster_t) < 0.5 / FPS:
            POSTER.parent.mkdir(parents=True, exist_ok=True)
            frame.save(POSTER, "WEBP", quality=88, method=6)
        writer.send(np.asarray(frame, np.uint8).tobytes())
        if i % (FPS * 10) == 0:
            log(f"edit {t:5.1f}s / {LENGTH:.0f}s")
    writer.close()
    log(f"video: {OUT.relative_to(ROOT)} ({OUT.stat().st_size / 1e6:.1f} MB, {time.time() - t0:.0f}s)")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--only", choices=["shots", "stills", "edit"], help="run a single step")
    ap.add_argument("--force", choices=["shots", "stills"], help="re-render instead of reusing the cache")
    ap.add_argument("--shots", nargs="*", help="only these shots (with --only shots)")
    ap.add_argument("--render-scale", type=float, default=1.0, help="3D resolution scale for the shots (0.5..1)")
    a = ap.parse_args()
    global RENDER_SCALE
    RENDER_SCALE = max(0.5, min(1.0, a.render_scale))
    CACHE.mkdir(parents=True, exist_ok=True)
    (CACHE / ".gdignore").touch()
    steps = [a.only] if a.only else ["shots", "stills", "edit"]
    if "shots" in steps or "stills" in steps:
        godot = find_godot(None)
        if "stills" in steps:
            render_stills(a.force == "stills")
        if "shots" in steps:
            record_shots(godot, a.force == "shots", a.shots)
    if "edit" in steps:
        music = CACHE / "music.wav"
        make_music(music)
        edit(music)
    return 0


if __name__ == "__main__":
    sys.exit(main())
