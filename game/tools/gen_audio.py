#!/usr/bin/env python3
"""SOPRO — sintetiza todos os sons do jogo (CC0, feitos aqui; só numpy + ffmpeg).

    python3 game/tools/gen_audio.py            # efeitos + músicas
    python3 game/tools/gen_audio.py --sfx      # só efeitos

Efeitos  → game/assets/audio/sfx/*.wav  (mono 16-bit, 32 kHz)
Músicas  → game/assets/audio/music/lencois.ogg (ambiente sonhador: pads, kalimba/harpa,
           flauta suave, vento) e vento.ogg (final festivo em ritmo de baião:
           zabumba, triângulo e "sanfona"), com loop sem emenda (cauda do reverb dobrada).
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
    # jumps
    x = sweep_sine(380, 980, 0.16, sr, 0.6) * env_adsr(int(0.16 * sr), sr, 0.004, 0.05, 0.6, 0.08)
    w = bandpass(noise(int(0.2 * sr)), sr, 1500, 7000) * env_adsr(int(0.2 * sr), sr, 0.02, 0.05, 0.4, 0.12) * 0.3
    S["jump_juba"] = np.concatenate([x, np.zeros(len(w) - len(x))]) + w
    x = sweep_sine(170, 340, 0.2, sr, 0.7) * env_adsr(int(0.2 * sr), sr, 0.006, 0.06, 0.6, 0.1)
    x += 0.4 * sweep_sine(340, 700, 0.2, sr, 0.7) * env_adsr(int(0.2 * sr), sr, 0.006, 0.06, 0.4, 0.1)
    S["jump_caju"] = lowpass(x, sr, 2500)
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
    # capybara chirps (call)
    buf = np.zeros(int(0.5 * sr))
    for k, (f0, f1) in enumerate(((1300, 1700), (1250, 1650))):
        c = sweep_sine(f0, f1, 0.09, sr) * env_adsr(int(0.09 * sr), sr, 0.005, 0.03, 0.6, 0.04)
        place(buf, c, k * 0.14 * sr, 0.6)
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
    S["hurt_juba"] = sweep_sine(1300, 650, 0.22, sr, 0.8) * env_adsr(int(0.22 * sr), sr, 0.005, 0.05, 0.7, 0.1)
    t = t_axis(0.3, sr)
    f = 220 - 80 * t / 0.3
    x = np.zeros(len(t))
    for h, a in ((1, 1.0), (2, 0.5), (3, 0.35), (4, 0.2)):
        x += a * np.sin(2 * np.pi * np.cumsum(f * h) / sr)
    S["hurt_caju"] = lowpass(x * env_adsr(len(t), sr, 0.02, 0.05, 0.7, 0.12), sr, 1600)
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


def music_lencois(sr=44100):
    bpm = 70.0
    beat = 60.0 / bpm
    bar = beat * 4
    bars = 16
    dur = bar * bars
    # D lydian-ish progression (MIDI)
    prog = [
        [50, 57, 62, 64, 66, 69],      # Dmaj9
        [47, 54, 59, 62, 64, 69],      # Bm11
        [43, 50, 59, 61, 66, 69],      # Gmaj7(#11)
        [45, 52, 57, 59, 64, 66],      # A6sus2
    ]
    penta = [62, 64, 66, 69, 71, 74, 76, 78, 81]

    def voices(L, R, sr):
        for b in range(bars):
            ch = prog[b % 4]
            t0 = b * bar * sr
            # pad: detuned soft voices with slow swell
            n = int(bar * 1.6 * sr)
            tt = np.arange(n) / sr
            env = np.minimum(1, tt / 1.6) * np.exp(-np.maximum(0, tt - bar) / 0.9)
            for k, m in enumerate(ch[1:]):
                f = note_hz(m)
                v = np.zeros(n)
                for det in (-0.004, 0.0, 0.0045):
                    v += np.sin(2 * np.pi * f * (1 + det) * tt + k)
                    v += 0.25 * np.sin(2 * np.pi * 2 * f * (1 + det) * tt)
                v = lowpass(v * env, sr, 1800) * 0.045
                l, r = pan(v, (k - 2) * 0.3)
                place(L, l, t0)
                place(R, r, t0)
            # bass
            f = note_hz(ch[0] - 12)
            v = np.sin(2 * np.pi * f * tt) * env * 0.12
            place(L, v, t0)
            place(R, v, t0)
            # kalimba / harp arpeggio in 8ths with humanized timing and velocity
            pattern = [0, 2, 4, 3, 5, 4, 2, 3]
            for s in range(8):
                if rng.random() < 0.18 and s not in (0, 4):
                    continue
                m = ch[1 + pattern[s] % 5] + (12 if s in (4, 5) else 0)
                at = t0 + (s * beat / 2 + rng.normal(0, 0.008)) * sr
                vel = 0.12 + 0.05 * rng.random() + (0.04 if s % 4 == 0 else 0)
                p = pluck(note_hz(m), 1.6, sr, tau=0.9, bright=0.9, harmonics=8) * vel
                l, r = pan(p, rng.uniform(-0.5, 0.5))
                place(L, l, at)
                place(R, r, at)
            # gentle flute melody on some bars (pentatonic phrases)
            if b % 4 in (1, 2) and b >= 4:
                for s in range(3):
                    m = penta[rng.integers(2, len(penta))]
                    d = beat * rng.choice([1.0, 1.5, 2.0])
                    nn = int(d * sr)
                    tt2 = np.arange(nn) / sr
                    vib = 1 + 0.006 * np.sin(2 * np.pi * 5.2 * tt2) * np.minimum(1, tt2 / 0.4)
                    fl = np.sin(2 * np.pi * note_hz(m) * np.cumsum(vib) / sr) + 0.15 * np.sin(4 * np.pi * note_hz(m) * np.cumsum(vib) / sr)
                    fl += 0.03 * lowpass(noise(nn), sr, 3000)
                    fl *= env_adsr(nn, sr, 0.12, 0.2, 0.7, 0.3) * 0.07
                    at = t0 + (s * beat * 1.3 + 0.5 * beat) * sr
                    l, r = pan(fl, 0.15)
                    place(L, l, at)
                    place(R, r, at)
            # sparkle chimes now and then
            if rng.random() < 0.5:
                m = penta[rng.integers(4, len(penta))] + 12
                c = fm_bell(note_hz(m), 2.0, sr, ratio=2.76, index=1.0, tau=0.7) * 0.03
                l, r = pan(c, rng.uniform(-0.8, 0.8))
                at = t0 + rng.uniform(0, bar) * sr
                place(L, l, at)
                place(R, r, at)
        # wind bed
        n = len(L)
        tt = np.arange(n) / sr
        w = lowpass(noise(n), sr, 700) * (0.5 + 0.5 * np.sin(2 * np.pi * tt / 9.0)) * 0.05
        L += w
        R += np.roll(w, int(0.37 * sr))

    l, r = render_loop(dur, sr, voices, tail=4.0, wet=0.38, ir_seconds=3.5)
    return l, r, sr


def music_vento(sr=44100):
    """Festive baião-inspired loop (zabumba, triângulo, sanfona)."""
    bpm = 104.0
    beat = 60.0 / bpm
    bar = beat * 2          # 2/4
    bars = 24
    dur = bar * bars
    prog = [[50, 54, 57], [50, 54, 57], [55, 59, 62], [57, 61, 64], [50, 54, 57], [47, 50, 54], [55, 59, 62], [57, 61, 64]]
    melody = [74, 76, 78, 76, 74, 71, 69, 71, 74, 74, 76, 78, 81, 78, 76, 74,
              71, 74, 76, 74, 71, 69, 66, 69, 71, 74, 71, 69, 67, 66, 64, 62]

    def zabumba(sr):
        n = int(0.35 * sr)
        x = sweep_sine(95, 48, 0.35, sr) * exp_decay(n, sr, 0.12)
        x += 0.25 * lowpass(noise(n), sr, 600) * exp_decay(n, sr, 0.03)
        return x

    def bacalhau(sr):    # high slap (rim)
        n = int(0.08 * sr)
        return bandpass(noise(n), sr, 1500, 5000) * exp_decay(n, sr, 0.015)

    def triangle(sr, open_=True):
        return fm_bell(2400, 0.6 if open_ else 0.1, sr, ratio=1.41, index=2.0, tau=0.3 if open_ else 0.03)

    def accordion(m, d, sr):
        nn = int(d * sr)
        tt = np.arange(nn) / sr
        f = note_hz(m)
        vib = 1 + 0.004 * np.sin(2 * np.pi * 5.5 * tt)
        ph = 2 * np.pi * f * np.cumsum(vib) / sr
        x = np.zeros(nn)
        for h, a in ((1, 1.0), (2, 0.6), (3, 0.45), (4, 0.3), (5, 0.2), (6, 0.12)):
            x += a * np.sin(h * ph) + 0.6 * a * np.sin(h * ph * 1.003)
        x = lowpass(x, sr, 3500)
        return x * env_adsr(nn, sr, 0.02, 0.08, 0.75, 0.06)

    def voices(L, R, sr):
        zb = zabumba(sr)
        bc = bacalhau(sr)
        tri_o = triangle(sr, True)
        tri_c = triangle(sr, False)
        for b in range(bars):
            t0 = b * bar * sr
            ch = prog[b % len(prog)]
            # zabumba baião: dotted pattern (1, a, 2+)
            for at, g in ((0.0, 0.5), (0.75, 0.35), (1.5, 0.45)):
                place(L, zb * g, t0 + at * beat * sr)
                place(R, zb * g, t0 + at * beat * sr)
            place(L, bc * 0.25, t0 + 1.0 * beat * sr)
            place(R, bc * 0.25, t0 + 1.0 * beat * sr)
            # triângulo: 16ths, open on the off-beats
            for s in range(8):
                at = t0 + s * beat / 4 * sr
                tr = tri_o * 0.06 if s % 2 == 1 else tri_c * 0.05
                l, r = pan(tr, 0.5)
                place(L, l, at)
                place(R, r, at)
            # bass (sanfona baixaria)
            for at, m in ((0.0, ch[0] - 12), (0.75, ch[0] - 12 + 7), (1.5, ch[0] - 12)):
                nn = int(beat * 0.7 * sr)
                tt = np.arange(nn) / sr
                bs = (np.sin(2 * np.pi * note_hz(m) * tt) + 0.3 * np.sin(4 * np.pi * note_hz(m) * tt)) * env_adsr(nn, sr, 0.01, 0.1, 0.6, 0.1) * 0.18
                place(L, bs, t0 + at * beat * sr)
                place(R, bs, t0 + at * beat * sr)
            # chords stabs
            for at in (0.5, 1.5):
                for m in ch:
                    st = accordion(m + 12, beat * 0.35, sr) * 0.035
                    l, r = pan(st, -0.3)
                    place(L, l, t0 + at * beat * sr)
                    place(R, r, t0 + at * beat * sr)
            # melody: 2 notes per bar, from bar 4
            if b >= 4:
                i = ((b - 4) * 2) % len(melody)
                for k in range(2):
                    m = melody[(i + k) % len(melody)]
                    ac = accordion(m, beat * 0.95, sr) * 0.07
                    l, r = pan(ac, 0.1)
                    place(L, l, t0 + k * beat * sr)
                    place(R, r, t0 + k * beat * sr)

    l, r = render_loop(dur, sr, voices, tail=2.0, wet=0.22, ir_seconds=1.8)
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
        write_ogg("lencois", *music_lencois())
        write_ogg("vento", *music_vento())


if __name__ == "__main__":
    main()
