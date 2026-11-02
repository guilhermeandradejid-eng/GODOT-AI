#!/usr/bin/env python3
"""Gera o APK Android de SOPRO (o jogo em game/) para testar no celular.

    python3 tools/build_android.py                 # APK debug (assinado com a keystore de debug)
    python3 tools/build_android.py --release       # APK release (precisa de keystore própria, veja abaixo)
    python3 tools/build_android.py --install       # + instala via adb no aparelho conectado
    python3 tools/build_android.py --check         # + valida o build exportado (export Linux + autoteste)

Pré-requisitos (uma vez):
  * Godot 4.7+ (GODOT_BIN ou `godot` no PATH) e os export templates da MESMA versão
    (Editor → Manage Export Templates, ou extraia o .tpz em
    ~/.local/share/godot/export_templates/<versão>/).
  * Android SDK com build-tools (apksigner) e platform-tools (adb):
    ANDROID_HOME=/caminho/android-sdk  (ou configure em Editor Settings → Export → Android).
  * JDK 17+ (JAVA_HOME).
  * Keystore de debug: usa ~/.android/debug.keystore ou cria uma com keytool.
    Release: SOPRO_KEYSTORE, SOPRO_KEYSTORE_USER, SOPRO_KEYSTORE_PASS.

O que o script faz: escreve/atualiza o preset "Android" em export_presets.cfg (arm64,
renderer Mobile/Vulkan, paisagem, imersivo, permissões de rede para o co-op em Wi-Fi,
ícones), lista os recursos do jogo para exportar só o que o jogo usa (sem as demos da
suíte), importa o projeto e chama o Godot em modo headless.
"""
from __future__ import annotations

import argparse
import configparser
import os
import shutil
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "tools"))

PRESET_NAME = "Android"
PACKAGE = "com.sopro.lencois"
APP_NAME = "Sopro"
VERSION_NAME = "0.1.0"
VERSION_CODE = 1
EXTRA_RESOURCES = [
    "res://addons/vibe_vfx/textures/cloud_noise.png",
    "res://addons/vibe_terrain/textures/water_normal.png",
]
GAME_EXT = {".tscn", ".gd", ".gdshader", ".glb", ".png", ".wav", ".ogg", ".ttf", ".json", ".tres", ".res"}


def find_godot() -> str:
    try:
        from vibe_client import find_godot as fg  # reuses the suite's lookup (.vibe/state.json, PATH...)
        return fg(None)
    except Exception:
        g = os.environ.get("GODOT_BIN") or shutil.which("godot") or shutil.which("godot4")
        if not g:
            sys.exit("Godot não encontrado: defina GODOT_BIN=/caminho/godot")
        return g


def game_resources() -> list[str]:
    out = []
    for p in sorted((ROOT / "game").rglob("*")):
        rel = p.relative_to(ROOT)
        if p.is_dir() or p.suffix not in GAME_EXT:
            continue
        parts = rel.parts
        if "blender" in parts or (len(parts) > 1 and parts[1] == "tools"):
            continue
        out.append("res://" + rel.as_posix())
    return out + EXTRA_RESOURCES


def write_preset(release: bool) -> None:
    path = ROOT / "export_presets.cfg"
    cfg = configparser.RawConfigParser()
    cfg.optionxform = str
    if path.exists():
        cfg.read(path, encoding="utf-8")
    # find (or allocate) our preset index
    idx = None
    used = []
    for sec in cfg.sections():
        if sec.startswith("preset.") and sec.count(".") == 1:
            used.append(int(sec.split(".")[1]))
            if cfg.get(sec, "name", fallback="").strip('"') == PRESET_NAME:
                idx = int(sec.split(".")[1])
    if idx is None:
        idx = (max(used) + 1) if used else 0
    sec = f"preset.{idx}"
    opt = f"preset.{idx}.options"
    for s in (sec, opt):
        if cfg.has_section(s):
            cfg.remove_section(s)
        cfg.add_section(s)
    files = ", ".join(f'"{f}"' for f in game_resources())

    def q(v: str) -> str:
        return f'"{v}"'

    base = {
        "name": q(PRESET_NAME), "platform": q("Android"), "runnable": "true", "advanced_options": "false",
        "dedicated_server": "false", "custom_features": q(""), "export_filter": q("resources"),
        "export_files": f"PackedStringArray({files})", "include_filter": q(""),
        "exclude_filter": q("game/blender/*, game/tools/*"), "export_path": q("build/sopro-debug.apk"),
        "patches": "PackedStringArray()", "encryption_include_filters": q(""),
        "encryption_exclude_filters": q(""), "seed": "0", "encrypt_pck": "false",
        "encrypt_directory": "false", "script_export_mode": "2",
    }
    for k, v in base.items():
        cfg.set(sec, k, v)
    options = {
        "custom_template/debug": q(""), "custom_template/release": q(""),
        "gradle_build/use_gradle_build": "false", "gradle_build/export_format": "0",
        "architectures/armeabi-v7a": "false", "architectures/arm64-v8a": "true",
        "architectures/x86": "false", "architectures/x86_64": "false",
        "version/code": str(VERSION_CODE), "version/name": q(VERSION_NAME),
        "package/unique_name": q(PACKAGE), "package/name": q(APP_NAME), "package/signed": "true",
        "package/app_category": "2", "package/retain_data_on_uninstall": "false",
        "package/exclude_from_recents": "false", "package/show_in_android_tv": "false",
        "package/show_in_app_library": "true", "package/show_as_launcher_app": "false",
        "launcher_icons/main_192x192": q("res://game/assets/icons/icon_192.png"),
        "launcher_icons/adaptive_foreground_432x432": q("res://game/assets/icons/icon_fg_432.png"),
        "launcher_icons/adaptive_background_432x432": q("res://game/assets/icons/icon_bg_432.png"),
        "launcher_icons/adaptive_monochrome_432x432": q("res://game/assets/icons/icon_mono_432.png"),
        "graphics/opengl_debug": "false", "xr_features/xr_mode": "0",
        "screen/immersive_mode": "true", "screen/support_small": "true", "screen/support_normal": "true",
        "screen/support_large": "true", "screen/support_xlarge": "true",
        "user_data_backup/allow": "false", "command_line/extra_args": q(""),
        "apk_expansion/enable": "false",
        "permissions/internet": "true", "permissions/access_network_state": "true",
        "permissions/access_wifi_state": "true", "permissions/change_wifi_multicast_state": "true",
        "permissions/vibrate": "true",
    }
    for k, v in options.items():
        cfg.set(opt, k, v)
    with open(path, "w", encoding="utf-8") as f:
        cfg.write(f, space_around_delimiters=False)
    print(f"preset '{PRESET_NAME}' -> export_presets.cfg ({len(game_resources())} recursos)")


def write_linux_check_preset() -> None:
    """Preset "SoproLinuxCheck": same resources as the APK, exported for Linux so the
    exported build can be self-tested on a PC (no phone needed)."""
    path = ROOT / "export_presets.cfg"
    cfg = configparser.RawConfigParser()
    cfg.optionxform = str
    cfg.read(path, encoding="utf-8")
    idx = None
    used = []
    for sec in cfg.sections():
        if sec.startswith("preset.") and sec.count(".") == 1:
            used.append(int(sec.split(".")[1]))
            if cfg.get(sec, "name", fallback="").strip('"') == "SoproLinuxCheck":
                idx = int(sec.split(".")[1])
    if idx is None:
        idx = max(used) + 1 if used else 0
    sec, opt = f"preset.{idx}", f"preset.{idx}.options"
    for s_ in (sec, opt):
        if cfg.has_section(s_):
            cfg.remove_section(s_)
        cfg.add_section(s_)
    files = ", ".join(f'"{f}"' for f in game_resources())
    for k, v in {"name": '"SoproLinuxCheck"', "platform": '"Linux"', "runnable": "false",
                 "export_filter": '"resources"', "export_files": f"PackedStringArray({files})",
                 "include_filter": '""', "exclude_filter": '"game/blender/*, game/tools/*"',
                 "export_path": '"build/selftest/sopro.x86_64"'}.items():
        cfg.set(sec, k, v)
    for k, v in {"binary_format/embed_pck": "true", "binary_format/architecture": '"x86_64"',
                 "texture_format/s3tc_bptc": "true", "texture_format/etc2_astc": "false"}.items():
        cfg.set(opt, k, v)
    with open(path, "w", encoding="utf-8") as f:
        cfg.write(f, space_around_delimiters=False)


def run_check(godot: str, env: dict) -> int:
    out = ROOT / "build" / "selftest" / "sopro.x86_64"
    out.parent.mkdir(parents=True, exist_ok=True)
    write_linux_check_preset()
    proc = subprocess.run([godot, "--headless", "--path", str(ROOT), "--export-debug", "SoproLinuxCheck", str(out)],
                          env=env, capture_output=True, text=True, timeout=1800)
    if not out.exists():
        print((proc.stdout + proc.stderr)[-3000:])
        print("check: export Linux falhou (instale os export templates de Linux)")
        return 1
    run = subprocess.run([str(out), "--headless", "--", "--selftest"], capture_output=True, text=True, timeout=600)
    line = next((l for l in run.stdout.splitlines() if l.startswith("SELFTEST")), "SELFTEST sem resposta")
    print("build exportado:", line)
    return run.returncode


def ensure_debug_keystore() -> Path:
    ks = Path(os.environ.get("GODOT_ANDROID_KEYSTORE_DEBUG_PATH", Path.home() / ".android" / "debug.keystore"))
    if not ks.exists():
        ks.parent.mkdir(parents=True, exist_ok=True)
        keytool = shutil.which("keytool")
        if not keytool:
            sys.exit("keytool (JDK) não encontrado para criar a keystore de debug")
        subprocess.run([keytool, "-genkeypair", "-v", "-keystore", str(ks), "-storepass", "android",
                        "-alias", "androiddebugkey", "-keypass", "android", "-keyalg", "RSA", "-keysize", "2048",
                        "-validity", "10000", "-dname", "CN=Android Debug,O=Android,C=US", "-deststoretype", "pkcs12"],
                       check=True, capture_output=True)
        print("keystore de debug criada:", ks)
    return ks


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--release", action="store_true")
    ap.add_argument("--install", action="store_true", help="instala com adb depois de gerar")
    ap.add_argument("--out", default=None, help="caminho do APK (padrão build/sopro-debug.apk)")
    ap.add_argument("--check", action="store_true",
                    help="exporta os mesmos recursos para Linux e roda um autoteste no build exportado")
    a = ap.parse_args()
    godot = find_godot()
    write_preset(a.release)
    if a.check:
        rc = run_check(godot, dict(os.environ))
        if rc != 0:
            return rc
    out = Path(a.out) if a.out else ROOT / "build" / ("sopro-release.apk" if a.release else "sopro-debug.apk")
    out.parent.mkdir(parents=True, exist_ok=True)
    env = dict(os.environ)
    if not a.release:
        ks = ensure_debug_keystore()
        env.setdefault("GODOT_ANDROID_KEYSTORE_DEBUG_PATH", str(ks))
        env.setdefault("GODOT_ANDROID_KEYSTORE_DEBUG_USER", "androiddebugkey")
        env.setdefault("GODOT_ANDROID_KEYSTORE_DEBUG_PASSWORD", "android")
    else:
        for k_src, k_dst in (("SOPRO_KEYSTORE", "GODOT_ANDROID_KEYSTORE_RELEASE_PATH"),
                             ("SOPRO_KEYSTORE_USER", "GODOT_ANDROID_KEYSTORE_RELEASE_USER"),
                             ("SOPRO_KEYSTORE_PASS", "GODOT_ANDROID_KEYSTORE_RELEASE_PASSWORD")):
            if not env.get(k_src) and not env.get(k_dst):
                sys.exit(f"--release precisa de {k_src}")
            if env.get(k_src):
                env[k_dst] = env[k_src]
    print("importando o projeto...")
    subprocess.run([godot, "--headless", "--path", str(ROOT), "--import"], env=env, capture_output=True, timeout=1800)
    mode = "--export-release" if a.release else "--export-debug"
    print("exportando", out.relative_to(ROOT) if out.is_relative_to(ROOT) else out)
    proc = subprocess.run([godot, "--headless", "--path", str(ROOT), mode, PRESET_NAME, str(out)], env=env,
                          capture_output=True, text=True, timeout=1800)
    log = proc.stdout + proc.stderr
    errors = [l for l in log.splitlines() if "ERROR" in l and "daemon" not in l]
    if not out.exists():
        print(log[-4000:])
        sys.exit("falhou: APK não foi gerado")
    if errors:
        print("\n".join(errors[:20]))
    size = out.stat().st_size / 1024 / 1024
    print(f"APK: {out}  ({size:.1f} MB)")
    apksigner = shutil.which("apksigner")
    if apksigner:
        v = subprocess.run([apksigner, "verify", "--print-certs", str(out)], capture_output=True, text=True)
        print("assinatura:", "OK" if v.returncode == 0 else v.stderr.strip()[:300])
    if a.install:
        adb = shutil.which("adb")
        if not adb:
            sys.exit("adb não encontrado")
        subprocess.run([adb, "install", "-r", str(out)], check=False)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
