#!/usr/bin/env python3
"""SOPRO — sintetiza todos os sons do jogo (CC0, feitos aqui; só numpy + ffmpeg).

    python3 game/tools/gen_audio.py            # efeitos + músicas
    python3 game/tools/gen_audio.py --sfx      # só efeitos

Efeitos  → game/assets/audio/sfx/*.wav  (mono 16-bit, 32 kHz)
Músicas  → game/assets/audio/music/explore.ogg (deserto ao entardecer: drone de cordas,
           coro etéreo por formantes, harpa esparsa, flauta de vidro, vento) e finale.ogg
           (o portal desperta: coro, sinos, arpejos de cordas), com loop sem emenda.
"""
from __future__ import annotations

import argparse
import subprocess
import wave
from pathlib import Path

import numpy as np

ROOT = Path(__file__).resolve().parents[2]
SFX = ROOT / "game" / "assets" / "audio" / "sfx"
MUS = ROOT / "game" / "assets" / "audio" / "music"
rng = np.random.default_rng(42)


# ----------------------------------------------------------------------------- utils
def t_axis(dur: float, sr: int) -> np.ndarray:
    return np.arange(int(dur * sr)) / sr


def note_hz(n: float) -> float:
    """MIDI note -> Hz."""
    return 440.0 * 2 ** ((n - 69) / 12)


def env_adsr(n: int, sr: int, a=0.005, d=0.1, s=0.6, r=0.2) -> np.ndarray:
    e = np.zeros(n)
    ai, di, ri = int(a * sr), int(d * sr), int(r * sr)
    si = max(0, n - ai - di - ri)
    idx = 0
    for seg, (v0, v1, L) in enumerate(((0, 1, ai), (1, s, di), (s, s, si), (s, 0, ri))):
        L = min(L, n - idx)
        if L > 0:
            e[idx:idx + L] = np.linspace(v0, v1, L, endpoint=False)
            idx += L
    return e


def exp_decay(n: int, sr: int, tau: float) -> np.ndarray:
    return np.exp(-np.arange(n) / sr / tau)


def lowpass(x: np.ndarray, sr: int, fc: float) -> np.ndarray:
    """Zero-phase-ish one-pole lowpass via FFT magnitude (fast, vectorized)."""
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / sr)
    H = 1 / np.sqrt(1 + (f / fc) ** 4)
    return np.fft.irfft(X * H, len(x))


def highpass(x: np.ndarray, sr: int, fc: float) -> np.ndarray:
    X = np.fft.rfft(x)
    f = np.fft.rfftfreq(len(x), 1 / sr)
    H = 1 / np.sqrt(1 + (fc / np.maximum(f, 1e-3)) ** 4)
    return np.fft.irfft(X * H, len(x))


def bandpass(x, sr, lo, hi):
    return highpass(lowpass(x, sr, hi), sr, lo)


def sweep_sine(f0, f1, dur, sr, curve=1.0):
    t = t_axis(dur, sr)
    k = (t / dur) ** curve
    f = f0 + (f1 - f0) * k
    return np.sin(2 * np.pi * np.cumsum(f) / sr)


def fm_bell(freq, dur, sr, ratio=1.4, index=3.0, tau=0.8, partials=None):
    t = t_axis(dur, sr)
    n = len(t)
    env = exp_decay(n, sr, tau)
    idx_env = index * exp_decay(n, sr, tau * 0.35)
    mod = np.sin(2 * np.pi * freq * ratio * t)
    out = np.sin(2 * np.pi * freq * t + idx_env * mod) * env
    if partials:
        for mul, amp, tt in partials:
            out += amp * np.sin(2 * np.pi * freq * mul * t + rng.uniform(0, 6)) * exp_decay(n, sr, tau * tt)
    attack = np.minimum(1.0, np.arange(n) / (0.002 * sr))
    return out * attack


def pluck(freq, dur, sr, bright=1.0, tau=1.2, harmonics=10):
    """Additive harp/kalimba pluck: higher harmonics decay faster."""
    t = t_axis(dur, sr)
    n = len(t)
    out = np.zeros(n)
    for h in range(1, harmonics + 1):
        amp = (1.0 / h ** (1.6 - 0.5 * bright)) * (1.0 if h == 1 else 0.9)
        out += amp * np.sin(2 * np.pi * freq * h * t * (1 + 0.0004 * h * h)) * exp_decay(n, sr, tau / (1 + 0.6 * (h - 1)))
    attack = np.minimum(1.0, np.arange(n) / (0.003 * sr))
    return out * attack


def noise(n):
    return rng.uniform(-1, 1, n)


def reverb_ir(sr, seconds=2.6, decay=2.2, stereo=True, bright=6000):
    n = int(seconds * sr)
    chans = []
    for c in range(2 if stereo else 1):
        ir = noise(n) * np.exp(-np.arange(n) / sr * (6.9 / decay))
        ir = lowpass(ir, sr, bright)
        ir[: int(0.012 * sr)] *= np.linspace(0, 1, int(0.012 * sr))
        chans.append(ir / np.sqrt(np.sum(ir ** 2)))
    return chans


def convolve(x, ir):
    n = len(x) + len(ir) - 1
    N = 1 << (n - 1).bit_length()
    return np.fft.irfft(np.fft.rfft(x, N) * np.fft.rfft(ir, N), N)[:n]


def place(buf, sig, at, gain=1.0):
    i = int(at)
    if i >= len(buf):
        return
    L = min(len(sig), len(buf) - i)
    buf[i:i + L] += sig[:L] * gain


def normalize(x, peak=0.89):
    m = np.max(np.abs(x)) or 1.0
    return x / m * peak


def write_wav(path: Path, x: np.ndarray, sr: int, stereo=False):
    path.parent.mkdir(parents=True, exist_ok=True)
    if stereo:
        data = np.stack(x, axis=1)
    else:
        data = x
    pcm = (np.clip(data, -1, 1) * 32767).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(2 if stereo else 1)
        w.setsampwidth(2)
        w.setframerate(sr)
        w.writeframes(pcm.tobytes())


def soft_room(x, sr, wet=0.25, seconds=1.2):
    ir = reverb_ir(sr, seconds, seconds * 0.8, stereo=False)[0]
    y = convolve(x, ir)[: len(x) + int(0.6 * sr)]
    out = np.zeros(len(y))
    out[: len(x)] += x
    return out * (1 - wet) + y * wet * 0.6


# ----------------------------------------------------------------------------- sfx
def make_sfx():
    sr = 32000
    S = {}
    # footsteps in sand: soft crunchy noise burst
    n = int(0.09 * sr)
    x = bandpass(noise(n), sr, 700, 5200) * exp_decay(n, sr, 0.025)
    x += 0.4 * lowpass(noise(n), sr, 400) * exp_decay(n, sr, 0.02)
    S["step"] = x
    # jumps: agile = airy whistle + fan "fwip"; strong = hollow ceramic thunk + short low hum
    x = sweep_sine(620, 1500, 0.14, sr, 0.5) * env_adsr(int(0.14 * sr), sr, 0.003, 0.04, 0.55, 0.07)
    w = bandpass(noise(int(0.16 * sr)), sr, 2500, 9000) * env_adsr(int(0.16 * sr), sr, 0.002, 0.03, 0.3, 0.1) * 0.45
    S["jump_agile"] = np.concatenate([x, np.zeros(max(0, len(w) - len(x)))])[: max(len(x), len(w))] + np.pad(w, (0, max(0, len(x) - len(w))))
    t = t_axis(0.26, sr)
    f = 92 + 46 * (1 - np.exp(-t * 18))
    x = np.zeros(len(t))
    for h, a in ((1, 1.0), (2, 0.45), (3, 0.25), (5, 0.12)):
        x += a * np.sin(2 * np.pi * np.cumsum(f * h) / sr)
    x = lowpass(x * env_adsr(len(t), sr, 0.006, 0.06, 0.5, 0.12), sr, 1800)
    x += 0.6 * bandpass(noise(len(t)), sr, 220, 900) * exp_decay(len(t), sr, 0.03)
    S["jump_strong"] = x
    buf = np.zeros(int(0.6 * sr))
    for k, m in enumerate((84, 88, 91, 96)):
        place(buf, fm_bell(note_hz(m), 0.5, sr, ratio=2.0, index=1.2, tau=0.2), k * 0.04 * sr, 0.5)
    place(buf, bandpass(noise(int(0.3 * sr)), sr, 3000, 9000) * env_adsr(int(0.3 * sr), sr, 0.01, 0.05, 0.3, 0.2), 0, 0.25)
    S["jump2"] = buf
    n = int(0.18 * sr)
    S["land"] = sweep_sine(110, 45, 0.18, sr) * exp_decay(n, sr, 0.06) + 0.5 * lowpass(noise(n), sr, 900) * exp_decay(n, sr, 0.04)
    t = t_axis(0.42, sr)
    f = 260 + 340 * (1 - np.exp(-t * 12)) + 60 * np.sin(2 * np.pi * 14 * t) * np.exp(-t * 6)
    S["bounce"] = np.sin(2 * np.pi * np.cumsum(f) / sr) * exp_decay(len(t), sr, 0.16) * np.minimum(1, t / 0.004)
    n = int(0.4 * sr)
    tt = np.arange(n) / sr
    x = noise(n)
    spin = np.zeros(n)
    for fc in (900, 1400, 2200):
        spin += bandpass(x, sr, fc * 0.7, fc * 1.3)
    S["spin"] = spin * np.sin(np.pi * tt / 0.4) ** 1.2 * (0.6 + 0.4 * np.sin(2 * np.pi * 9 * tt))
    n = int(0.22 * sr)
    S["bump"] = sweep_sine(160, 70, 0.22, sr) * exp_decay(n, sr, 0.07) + 0.5 * bandpass(noise(n), sr, 300, 2000) * exp_decay(n, sr, 0.03)
    n = int(0.35 * sr)
    S["whoosh"] = bandpass(noise(n), sr, 600, 4000) * np.sin(np.pi * np.arange(n) / n) ** 2
    n = int(0.8 * sr)
    x = sweep_sine(90, 30, 0.8, sr) * exp_decay(n, sr, 0.18) * 1.2
    x += lowpass(noise(n), sr, 1500) * exp_decay(n, sr, 0.12) * 0.8
    x += bandpass(noise(n), sr, 2000, 6000) * exp_decay(n, sr, 0.3) * 0.2
    S["pound"] = x
    # the strong one calls its partner: two-note low foghorn hum
    buf = np.zeros(int(1.0 * sr))
    for k, m in enumerate((43, 47)):
        t = t_axis(0.38, sr)
        f = note_hz(m) * (1 + 0.004 * np.sin(2 * np.pi * 5 * t))
        x = np.zeros(len(t))
        for h, a in ((1, 1.0), (2, 0.6), (3, 0.35), (4, 0.18)):
            x += a * np.sin(2 * np.pi * np.cumsum(f * h) / sr)
        place(buf, lowpass(x * env_adsr(len(t), sr, 0.05, 0.08, 0.8, 0.15), sr, 1400), k * 0.42 * sr, 0.45)
    S["call"] = buf
    buf = np.zeros(int(0.5 * sr))
    for k, m in enumerate((76, 83)):
        place(buf, pluck(note_hz(m), 0.4, sr, tau=0.3), k * 0.08 * sr, 0.5)
    S["mount"] = buf
    n = int(0.7 * sr)
    x = 0.7 * sweep_sine(200, 120, 0.08, sr) * exp_decay(int(0.08 * sr), sr, 0.03)
    w = bandpass(noise(n), sr, 500, 5000) * np.linspace(0, 1, n) ** 0.5 * exp_decay(n, sr, 0.35)
    w[: len(x)] += x
    S["launch"] = w
    buf = np.zeros(int(0.8 * sr))
    for k, m in enumerate((72, 76, 79, 84, 88)):
        place(buf, pluck(note_hz(m), 0.5, sr, tau=0.35, bright=1.3), k * 0.045 * sr, 0.45)
    place(buf, bandpass(noise(int(0.5 * sr)), sr, 800, 6000) * np.hanning(int(0.5 * sr)), 0, 0.25)
    S["superjump"] = buf
    buf = np.zeros(int(1.0 * sr))
    for k, m in enumerate((79, 83, 86)):
        place(buf, fm_bell(note_hz(m), 0.9, sr, ratio=3.0, index=0.8, tau=0.4), k * 0.03 * sr, 0.35)
    place(buf, bandpass(noise(int(0.6 * sr)), sr, 1200, 8000) * np.hanning(int(0.6 * sr)), 0, 0.2)
    S["grind_start"] = buf
    n = int(0.6 * sr)
    x = bandpass(noise(n), sr, 400, 6000) * exp_decay(n, sr, 0.09)
    for k in range(9):
        f = rng.uniform(900, 2400)
        d = rng.uniform(0.03, 0.08)
        blip = sweep_sine(f, f * 1.6, d, sr) * exp_decay(int(d * sr), sr, d * 0.4)
        place(x, blip * 0.25, rng.uniform(0.02, 0.4) * sr)
    S["splash"] = x
    S["hurt_agile"] = sweep_sine(1500, 640, 0.24, sr, 0.8) * env_adsr(int(0.24 * sr), sr, 0.004, 0.05, 0.7, 0.1)
    buf = np.zeros(int(0.5 * sr))
    for k, m in enumerate((45, 40)):
        t = t_axis(0.2, sr)
        x = np.zeros(len(t))
        for h, a in ((1, 1.0), (2, 0.5), (3, 0.3), (4, 0.15)):
            x += a * np.sin(2 * np.pi * note_hz(m) * h * t)
        place(buf, lowpass(x * env_adsr(len(t), sr, 0.01, 0.04, 0.7, 0.08), sr, 1500), k * 0.16 * sr, 0.55)
    S["hurt_strong"] = buf
    n = int(1.1 * sr)
    buf = np.zeros(n)
    for k, m in enumerate((72, 76, 79, 83, 86, 91)):
        place(buf, fm_bell(note_hz(m), 0.9, sr, ratio=2.0, index=0.6, tau=0.35), k * 0.07 * sr, 0.3)
    S["respawn"] = buf * np.linspace(0.6, 1, n)
    lume = fm_bell(note_hz(84), 0.6, sr, ratio=2.0, index=1.0, tau=0.22) * 0.8
    place(lume, fm_bell(note_hz(96), 0.4, sr, ratio=3.0, index=0.5, tau=0.1), 0, 0.2)
    S["lume"] = lume
    buf = np.zeros(int(3.0 * sr))
    for k, m in enumerate((60, 64, 67, 71, 74, 76, 79, 83, 86, 88)):
        place(buf, pluck(note_hz(m), 2.0, sr, tau=1.0, bright=1.2), k * 0.07 * sr, 0.35)
    for m in (72, 79, 84):
        place(buf, fm_bell(note_hz(m), 2.5, sr, ratio=2.0, index=0.5, tau=1.0), 0.75 * sr, 0.25)
    S["seed"] = soft_room(buf, sr, 0.35, 1.6)[: len(buf)]
    S["chime"] = fm_bell(note_hz(84), 2.4, sr, ratio=2.76, index=1.6, tau=0.9,
                         partials=[(2.76, 0.25, 0.4), (5.4, 0.12, 0.2)])
    n = int(1.4 * sr)
    tt = np.arange(n) / sr
    x = np.zeros(n)
    for f in (523, 659, 784, 1046):
        x += np.sin(2 * np.pi * f * tt * (1 + 0.02 * np.sin(2 * np.pi * 3 * tt))) * 0.25
    x *= np.sin(np.pi * tt / 1.4) * (0.6 + 0.4 * np.sin(2 * np.pi * 7 * tt))
    x += bandpass(noise(n), sr, 2000, 9000) * np.sin(np.pi * tt / 1.4) ** 2 * 0.2
    S["portal"] = x
    buf = np.zeros(int(1.6 * sr))
    for m in (60, 64, 67, 72):
        place(buf, pluck(note_hz(m), 1.4, sr, tau=0.7), 0, 0.3)
    place(buf, fm_bell(note_hz(84), 1.2, sr, ratio=2.0, index=0.8, tau=0.5), 0.12 * sr, 0.3)
    S["checkpoint"] = buf
    n = int(0.06 * sr)
    S["ui_click"] = np.sin(2 * np.pi * 1400 * np.arange(n) / sr) * exp_decay(n, sr, 0.012) + 0.3 * bandpass(noise(n), sr, 2000, 6000) * exp_decay(n, sr, 0.006)
    buf = np.zeros(int(0.5 * sr))
    place(buf, fm_bell(note_hz(79), 0.4, sr, ratio=2.0, index=0.7, tau=0.15), 0, 0.5)
    place(buf, fm_bell(note_hz(86), 0.4, sr, ratio=2.0, index=0.7, tau=0.15), 0.09 * sr, 0.5)
    S["swap"] = buf
    S["join"] = buf.copy()
    n = int(0.6 * sr)
    x = bandpass(noise(n), sr, 300, 3000) * exp_decay(n, sr, 0.12) * 0.8
    sq = sweep_sine(900, 320, 0.25, sr) * exp_decay(int(0.25 * sr), sr, 0.08)
    x[: len(sq)] += sq * 0.5
    place(x, fm_bell(note_hz(91), 0.35, sr, ratio=2.0, index=0.6, tau=0.1), 0.12 * sr, 0.3)
    S["enemy_poof"] = x
    # the Great Bell: inharmonic partials, long decay with beating
    bsr = sr
    n = int(7.0 * bsr)
    tt = np.arange(n) / bsr
    f0 = 110.0
    x = np.zeros(n)
    for mul, amp, tau in ((0.5, 0.6, 4.5), (1.0, 1.0, 3.5), (1.19, 0.55, 2.4), (1.5, 0.45, 2.0), (2.0, 0.5, 1.6),
                          (2.74, 0.3, 1.0), (3.0, 0.22, 0.8), (4.07, 0.12, 0.5), (5.4, 0.08, 0.3)):
        beat = 1 + 0.08 * np.sin(2 * np.pi * (0.7 + mul * 0.3) * tt)
        x += amp * np.sin(2 * np.pi * f0 * mul * tt + rng.uniform(0, 6)) * np.exp(-tt / tau) * beat
    x[: int(0.004 * bsr)] *= np.linspace(0, 1, int(0.004 * bsr))
    place(x, 0.4 * bandpass(noise(int(0.05 * bsr)), bsr, 1500, 6000), 0)
    S["bell"] = soft_room(x, bsr, 0.35, 2.5)[:n]
    n = int(0.5 * sr)
    S["flower_load"] = sweep_sine(240, 90, 0.5, sr, 0.5) * exp_decay(n, sr, 0.18) + 0.3 * lowpass(noise(n), sr, 800) * exp_decay(n, sr, 0.1)
    n = int(0.3 * sr)
    S["plate_on"] = lowpass(noise(n), sr, 1200) * exp_decay(n, sr, 0.04) + 0.6 * np.sin(2 * np.pi * 220 * np.arange(n) / sr) * exp_decay(n, sr, 0.12)
    S["plate_off"] = lowpass(noise(n), sr, 900) * exp_decay(n, sr, 0.03) * 0.6
    n = int(2.2 * sr)
    grind = lowpass(noise(n), sr, 500) * (0.5 + 0.5 * np.sin(2 * np.pi * 11 * np.arange(n) / sr)) * np.hanning(n) * 0.8
    buf = grind.copy()
    for k, m in enumerate((67, 71, 74, 79)):
        place(buf, pluck(note_hz(m), 1.4, sr, tau=0.8), (0.9 + k * 0.1) * sr, 0.35)
    S["gate_open"] = buf
    buf = np.zeros(int(1.2 * sr))
    for k, m in enumerate((76, 79, 83, 88, 91)):
        place(buf, fm_bell(note_hz(m), 0.8, sr, ratio=2.0, index=0.7, tau=0.3), k * 0.06 * sr, 0.3)
    S["reveal"] = buf
    # sand surfing: start whoosh + seamless sliding loop (2 s)
    n = int(0.6 * sr)
    S["surf_start"] = bandpass(noise(n), sr, 300, 4500) * np.sin(np.pi * np.arange(n) / n) ** 0.7 * 0.9
    n = int(2.0 * sr)
    tt = np.arange(n) / sr
    hiss = bandpass(noise(n), sr, 700, 6500) * (0.75 + 0.25 * np.sin(2 * np.pi * 3.0 * tt))
    rumble = lowpass(noise(n), sr, 180) * 1.4
    grains = np.zeros(n)
    for k in range(120):
        at = int(rng.uniform(0, n - 400))
        g = bandpass(noise(300), sr, 2500, 9000) * np.hanning(300) * rng.uniform(0.2, 0.6)
        grains[at:at + 300] += g
    loop = hiss * 0.6 + rumble * 0.5 + grains
    fade = int(0.08 * sr)
    loop[:fade] = loop[:fade] * np.linspace(0, 1, fade) + loop[-fade:] * np.linspace(1, 0, fade)
    S["surf"] = loop[:-fade]
    for name, x in S.items():
        write_wav(SFX / f"{name}.wav", normalize(np.asarray(x, dtype=float), 0.85), sr)
    print("sfx:", len(S))


# ----------------------------------------------------------------------------- music
def render_loop(dur, sr, voices_fn, tail=4.0, wet=0.32, ir_seconds=3.2):
    n = int(dur * sr)
    total = n + int(tail * sr)
    L = np.zeros(total)
    R = np.zeros(total)
    voices_fn(L, R, sr)
    irL, irR = reverb_ir(sr, ir_seconds, ir_seconds * 0.85)
    revL = convolve(L, irL)[:total]
    revR = convolve(R, irR)[:total]
    outL = L * (1 - wet) + revL * wet * 0.9
    outR = R * (1 - wet) + revR * wet * 0.9
    # fold the tail back to the start => seamless loop
    loopL = outL[:n].copy()
    loopR = outR[:n].copy()
    loopL[: total - n] += outL[n:]
    loopR[: total - n] += outR[n:]
    m = max(np.max(np.abs(loopL)), np.max(np.abs(loopR)))
    return loopL / m * 0.8, loopR / m * 0.8


def pan(sig, p):
    a = (p + 1) * np.pi / 4
    return sig * np.cos(a), sig * np.sin(a)


def choir(m, dur, sr, vowel="a", vib=0.005):
    """Ethereal choir 'aah': detuned saws through vowel formant band-passes."""
    n = int(dur * sr)
    tt = np.arange(n) / sr
    f = note_hz(m)
    x = np.zeros(n)
    for det in (-0.006, -0.002, 0.003, 0.007):
        ph = 2 * np.pi * f * (1 + det) * tt + vib * np.sin(2 * np.pi * 5.0 * tt + det * 900)
        x += 2 * (ph / (2 * np.pi) % 1.0) - 1.0
    forms = {"a": ((800, 1150, 2900), (1.0, 0.6, 0.25)), "o": ((500, 900, 2600), (1.0, 0.45, 0.18)),
             "e": ((450, 1900, 2600), (1.0, 0.5, 0.2))}[vowel]
    y = np.zeros(n)
    for fc, g in zip(*forms):
        y += bandpass(x, sr, fc * 0.82, fc * 1.18) * g
    return y


def bowed(m, dur, sr, bright=1800.0):
    """Cello-like bowed tone: saw + lowpass, slow attack, vibrato that blooms."""
    n = int(dur * sr)
    tt = np.arange(n) / sr
    vib = 1 + 0.004 * np.sin(2 * np.pi * 5.4 * tt) * np.minimum(1, tt / 0.6)
    ph = 2 * np.pi * note_hz(m) * np.cumsum(vib) / sr
    x = 2 * ((ph / (2 * np.pi)) % 1.0) - 1.0
    x = lowpass(x, sr, bright)
    return x * env_adsr(n, sr, 0.35, 0.3, 0.8, 0.6)


def glass_flute(m, dur, sr):
    n = int(dur * sr)
    tt = np.arange(n) / sr
    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.0 * tt) * np.minimum(1, tt / 0.5)
    ph = 2 * np.pi * note_hz(m) * np.cumsum(vib) / sr
    x = np.sin(ph) + 0.12 * np.sin(2 * ph) + 0.05 * np.sin(3 * ph)
    x += 0.04 * lowpass(noise(n), sr, 2500)
    return x * env_adsr(n, sr, 0.15, 0.25, 0.75, 0.4)


def music_explore(sr=44100):
    """Exploration theme: vast desert at dusk (D dorian/lydian colours)."""
    bpm = 62.0
    beat = 60.0 / bpm
    bar = beat * 4
    bars = 16
    dur = bar * bars
    prog = [[38, 57, 62, 64, 69], [36, 55, 60, 64, 67], [43, 59, 62, 66, 71], [45, 57, 61, 64, 69]]
    scale = [62, 64, 65, 67, 69, 71, 72, 74, 76]

    def voices(L, R, sr):
        for b in range(bars):
            ch = prog[b % 4]
            t0 = b * bar * sr
            # low bowed drone on the root, breathing over two bars
            if b % 2 == 0:
                d = bowed(ch[0], bar * 2.2, sr, 900.0) * 0.10
                place(L, d, t0)
                place(R, d, t0)
            # choir pad
            for k, m in enumerate(ch[1:4]):
                c = choir(m, bar * 1.3, sr, "a" if b % 4 < 2 else "o")
                c *= env_adsr(len(c), sr, 1.2, 0.5, 0.8, 1.0) * 0.022
                l, r = pan(c, (k - 1) * 0.5)
                place(L, l, t0)
                place(R, r, t0)
            # sparse harp arpeggio
            for s in range(8):
                if rng.random() < 0.35:
                    continue
                m = ch[1 + (s * 3) % 4] + (12 if s >= 4 else 0)
                at = t0 + (s * beat / 2 + rng.normal(0, 0.01)) * sr
                p = pluck(note_hz(m), 2.0, sr, tau=1.1, bright=0.8, harmonics=7) * (0.07 + 0.04 * rng.random())
                l, r = pan(p, rng.uniform(-0.6, 0.6))
                place(L, l, at)
                place(R, r, at)
            # glass flute phrase every other bar from bar 4
            if b >= 4 and b % 2 == 1:
                for s in range(3):
                    m = scale[rng.integers(2, len(scale))]
                    dd = beat * rng.choice([1.0, 1.5, 2.0])
                    fl = glass_flute(m, dd, sr) * 0.06
                    l, r = pan(fl, 0.2)
                    place(L, l, t0 + (s * beat * 1.25 + 0.5 * beat) * sr)
                    place(R, r, t0 + (s * beat * 1.25 + 0.5 * beat) * sr)
            # glass bells shimmer
            if rng.random() < 0.6:
                m = scale[rng.integers(4, len(scale))] + 12
                c = fm_bell(note_hz(m), 2.4, sr, ratio=3.5, index=0.9, tau=0.8) * 0.025
                l, r = pan(c, rng.uniform(-0.8, 0.8))
                at = t0 + rng.uniform(0, bar) * sr
                place(L, l, at)
                place(R, r, at)
        n = len(L)
        tt = np.arange(n) / sr
        w = lowpass(noise(n), sr, 600) * (0.5 + 0.5 * np.sin(2 * np.pi * tt / 11.0)) * 0.06
        L += w
        R += np.roll(w, int(0.41 * sr))

    l, r = render_loop(dur, sr, voices, tail=4.5, wet=0.42, ir_seconds=4.0)
    return l, r, sr


def music_finale(sr=44100):
    """Finale: the gate wakes up — choir swell, bells, string arpeggios (D major)."""
    bpm = 76.0
    beat = 60.0 / bpm
    bar = beat * 4
    bars = 12
    dur = bar * bars
    prog = [[50, 62, 66, 69, 74], [47, 62, 66, 71, 74], [43, 62, 67, 71, 74], [45, 61, 64, 69, 73]]

    def voices(L, R, sr):
        for b in range(bars):
            ch = prog[b % 4]
            t0 = b * bar * sr
            d = bowed(ch[0] - 12, bar * 1.1, sr, 1200.0) * 0.12
            place(L, d, t0)
            place(R, d, t0)
            for k, m in enumerate(ch[1:]):
                c = choir(m, bar * 1.2, sr, "a") * env_adsr(int(bar * 1.2 * sr), sr, 0.6, 0.4, 0.85, 0.8) * 0.02
                l, r = pan(c, (k - 1.5) * 0.4)
                place(L, l, t0)
                place(R, r, t0)
            for s in range(16):
                m = ch[1 + s % 4] + (12 if s % 8 >= 4 else 0)
                st = bowed(m, beat * 0.3, sr, 2600.0) * 0.035
                l, r = pan(st, 0.3 if s % 2 else -0.3)
                place(L, l, t0 + s * beat / 4 * sr)
                place(R, r, t0 + s * beat / 4 * sr)
            if b % 2 == 0:
                for k, m in enumerate((ch[1] + 12, ch[2] + 12, ch[3] + 12)):
                    c = fm_bell(note_hz(m), 3.0, sr, ratio=2.0, index=0.7, tau=1.0) * 0.05
                    place(L, c, t0 + k * 0.08 * sr)
                    place(R, c, t0 + k * 0.08 * sr)
            if b >= 4:
                mel = [74, 76, 78, 81, 79, 78, 76, 74][(b * 2) % 8: (b * 2) % 8 + 2]
                for k, m in enumerate(mel):
                    fl = glass_flute(m + 12, beat * 1.8, sr) * 0.05
                    place(L, fl, t0 + k * beat * 2 * sr)
                    place(R, fl, t0 + k * beat * 2 * sr)

    l, r = render_loop(dur, sr, voices, tail=3.5, wet=0.35, ir_seconds=3.2)
    return l, r, sr


def write_ogg(name, l, r, sr):
    MUS.mkdir(parents=True, exist_ok=True)
    tmp = MUS / f"_{name}.wav"
    write_wav(tmp, (l, r), sr, stereo=True)
    out = MUS / f"{name}.ogg"
    subprocess.run(["ffmpeg", "-y", "-loglevel", "error", "-i", str(tmp), "-c:a", "libvorbis", "-q:a", "4", str(out)], check=True)
    tmp.unlink()
    print("music:", out.relative_to(ROOT), f"{out.stat().st_size // 1024} KB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sfx", action="store_true")
    a = ap.parse_args()
    make_sfx()
    if not a.sfx:
        write_ogg("explore", *music_explore())
        write_ogg("finale", *music_finale())


if __name__ == "__main__":
    main()
