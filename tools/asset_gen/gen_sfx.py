#!/usr/bin/env python3
"""Generates the placeholder sound effects and music loop in assets/audio.

Pure synthesis (oscillators, noise, envelopes) with a fixed seed, so the files
are reproducible. Every effect is loudness-matched (RMS normalized, peak
limited) so no sound jumps out; per-sound trims live in data/feel/audio.json.
The output is our own work, dedicated to the public domain (CC0).

Usage (from the repo root): python3 tools/asset_gen/gen_sfx.py
Standard library only.
"""
import math
import os
import random
import struct
import wave

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
SFX_DIR = os.path.join(ROOT, "assets", "audio", "sfx")
MUSIC_DIR = os.path.join(ROOT, "assets", "audio", "music")
RATE = 22050
TARGET_RMS_DB = -18.0
PEAK_DB = -1.0

rng = random.Random(7)


def n_samples(seconds):
    return int(RATE * seconds)


def env(i, n, attack=0.005, release=None):
    """Linear attack, exponential-ish decay to zero at the end."""
    t = i / RATE
    a = min(1.0, t / attack) if attack > 0 else 1.0
    r = (1.0 - i / n) ** (release if release else 2.0)
    return a * r


def square(phase):
    return 1.0 if (phase % 1.0) < 0.5 else -1.0


def tri(phase):
    p = phase % 1.0
    return 4 * p - 1 if p < 0.5 else 3 - 4 * p


def sweep(f0, f1, seconds, wave_fn=math.sin, curve=1.0, decay=2.0):
    n = n_samples(seconds)
    out, phase = [], 0.0
    for i in range(n):
        k = (i / n) ** curve
        f = f0 + (f1 - f0) * k
        phase += f / RATE
        s = math.sin(2 * math.pi * phase) if wave_fn is math.sin else wave_fn(phase)
        out.append(s * env(i, n, release=decay))
    return out


def noise(seconds, decay=2.0, lowpass=0.5):
    n = n_samples(seconds)
    out, prev = [], 0.0
    for i in range(n):
        prev = prev + lowpass * (rng.uniform(-1, 1) - prev)
        out.append(prev * env(i, n, release=decay))
    return out


def mix(*tracks, gains=None):
    n = max(len(t) for t in tracks)
    gains = gains or [1.0] * len(tracks)
    out = [0.0] * n
    for t, g in zip(tracks, gains):
        for i, s in enumerate(t):
            out[i] += s * g
    return out


def concat(*tracks):
    out = []
    for t in tracks:
        out += t
    return out


def normalize(samples, target_db=TARGET_RMS_DB):
    rms = math.sqrt(sum(s * s for s in samples) / max(1, len(samples))) or 1.0
    gain = 10 ** (target_db / 20) / rms
    peak = max(abs(s) for s in samples) * gain
    limit = 10 ** (PEAK_DB / 20)
    if peak > limit:
        gain *= limit / peak
    return [s * gain for s in samples]


def write(path, samples):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(struct.pack("<h", int(max(-1, min(1, s)) * 32767)) for s in samples))
    print(os.path.relpath(path, ROOT))


# ---------------------------------------------------------------- sounds
def ui_hover():
    return sweep(1300, 1400, 0.03, square, decay=3)


def ui_click(v):
    f = (900, 980)[v]
    return mix(sweep(f, f * 0.8, 0.045, square, decay=3), noise(0.01, lowpass=0.9), gains=[1.0, 0.3])


def ui_confirm():
    return concat(sweep(660, 660, 0.05, square, decay=1), sweep(990, 990, 0.08, square, decay=2))


def ui_back():
    return concat(sweep(700, 700, 0.05, square, decay=1), sweep(470, 470, 0.08, square, decay=2))


def ui_error():
    return mix(sweep(180, 160, 0.14, square, decay=1.5), sweep(190, 170, 0.14, square, decay=1.5))


def hit_light(v):
    lp = (0.35, 0.5, 0.25)[v]
    thump = sweep((160, 190, 140)[v], 60, 0.08, decay=2)
    return mix(noise(0.08, decay=3, lowpass=lp), thump, gains=[1.0, 0.8])


def hit_heavy(v):
    thump = sweep((120, 100)[v], 35, 0.2, decay=1.5)
    crunch = noise(0.18, decay=2.5, lowpass=(0.4, 0.3)[v])
    return mix(thump, crunch, gains=[1.0, 0.8])


def shot(v):
    return mix(sweep((1500, 1300)[v], 280, 0.15, square, curve=0.5, decay=2),
               noise(0.04, lowpass=0.8), gains=[0.8, 0.4])


def swing(v):
    n = n_samples(0.15)
    out, prev = [], 0.0
    for i in range(n):
        cutoff = 0.05 + 0.4 * math.sin(math.pi * i / n)
        prev = prev + cutoff * (rng.uniform(-1, 1) - prev)
        out.append(prev * math.sin(math.pi * i / n) * (1.0 if v == 0 else 0.9))
    return out


def charge():
    n = n_samples(0.3)
    out, phase = [], 0.0
    for i in range(n):
        f = 200 + 600 * (i / n)
        phase += f / RATE
        trem = 0.6 + 0.4 * math.sin(2 * math.pi * 30 * i / RATE)
        out.append(math.sin(2 * math.pi * phase) * trem * min(1.0, i / (n * 0.2)) * (1 - (i / n) ** 4))
    return out


def energy_tick():
    return sweep(1500, 1700, 0.025, tri, decay=3)


def heal(v):
    notes = ((523, 659, 784), (587, 740, 880))[v]
    return concat(*[sweep(f, f, 0.07, tri, decay=1.2) for f in notes])


def guard(v):
    n = n_samples(0.15)
    partials = ((620, 1.0), (1370, 0.6), (2210, 0.4)) if v == 0 else ((560, 1.0), (1290, 0.6), (2380, 0.35))
    return [sum(math.sin(2 * math.pi * f * i / RATE) * a for f, a in partials) * env(i, n, release=3) for i in range(n)]


def down():
    return mix(sweep(400, 70, 0.5, square, curve=0.7, decay=1.2), noise(0.4, decay=2, lowpass=0.2), gains=[0.6, 0.6])


def music_loop():
    """8 bars at 120 bpm, bass + arpeggio, loops cleanly (8 s)."""
    bpm, bars = 120, 8
    beat = 60 / bpm
    total = n_samples(beat * 4 * bars)
    out = [0.0] * total
    progression = [(110.0, (0, 3, 7)), (87.31, (0, 4, 7)), (130.81, (0, 4, 7)), (98.0, (0, 4, 7))]
    for bar in range(bars):
        root, chord = progression[bar % 4]
        for step in range(8):
            start = n_samples((bar * 4 + step * 0.5) * beat)
            length = n_samples(beat * 0.45)
            bass_f = root if step % 2 == 0 else root * 2
            for i in range(length):
                if start + i < total:
                    out[start + i] += 0.35 * tri(bass_f * i / RATE) * env(i, length, release=1)
            arp_f = root * 4 * 2 ** (chord[step % 3] / 12)
            alen = n_samples(beat * 0.22)
            for i in range(alen):
                if start + i < total:
                    out[start + i] += 0.12 * square(arp_f * i / RATE) * env(i, alen, release=2)
    return out


def main():
    sounds = {
        "ui_hover": ui_hover(),
        "ui_click_1": ui_click(0), "ui_click_2": ui_click(1),
        "ui_confirm": ui_confirm(), "ui_back": ui_back(), "ui_error": ui_error(),
        "hit_light_1": hit_light(0), "hit_light_2": hit_light(1), "hit_light_3": hit_light(2),
        "hit_heavy_1": hit_heavy(0), "hit_heavy_2": hit_heavy(1),
        "shot_1": shot(0), "shot_2": shot(1),
        "swing_1": swing(0), "swing_2": swing(1),
        "charge": charge(), "energy_tick": energy_tick(),
        "heal_1": heal(0), "heal_2": heal(1),
        "guard_1": guard(0), "guard_2": guard(1),
        "down": down(),
    }
    for name, samples in sounds.items():
        write(os.path.join(SFX_DIR, name + ".wav"), normalize(samples))
    write(os.path.join(MUSIC_DIR, "loop_placeholder.wav"), normalize(music_loop(), -20.0))


if __name__ == "__main__":
    main()
