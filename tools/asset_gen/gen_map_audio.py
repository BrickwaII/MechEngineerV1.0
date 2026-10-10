#!/usr/bin/env python3
"""Generates the map and between-fight sounds and the three act music loops in
assets/map/audio (M7 P3).

Built on the synthesis helpers in gen_sfx.py (same rate, loudness matching and
peak limit), with its own fixed seed so the files are reproducible. Per-sound
trims live in data/feel/audio.json. The output is our own work, dedicated to
the public domain (CC0).

Usage (from the repo root): python3 tools/asset_gen/gen_map_audio.py
Standard library only.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_sfx as sfx  # noqa: E402

ROOT = sfx.ROOT
SFX_DIR = os.path.join(ROOT, "assets", "map", "audio", "sfx")
MUSIC_DIR = os.path.join(ROOT, "assets", "map", "audio", "music")
RATE = sfx.RATE

sfx.rng = random.Random(31)
sweep, noise, mix, concat, square, tri = sfx.sweep, sfx.noise, sfx.mix, sfx.concat, sfx.square, sfx.tri


# ---------------------------------------------------------------- sounds
def map_select():
    return concat(sweep(520, 520, 0.03, square, decay=1), sweep(780, 780, 0.05, square, decay=2))


def map_capture():
    """A low thump under a rising four-note claim."""
    notes = [392, 494, 587, 784]
    rise = concat(*[sweep(f, f, 0.06, square, decay=1.4) for f in notes[:-1]], sweep(notes[-1], notes[-1], 0.2, tri, decay=1.6))
    thump = sweep(140, 45, 0.22, decay=1.5)
    return mix(rise, thump, noise(0.12, decay=3, lowpass=0.3), gains=[0.7, 0.9, 0.35])


def resource_gain():
    return concat(sweep(1046, 1046, 0.03, tri, decay=1), sweep(1568, 1568, 0.06, tri, decay=2))


def resource_loss():
    return concat(sweep(660, 660, 0.03, tri, decay=1), sweep(440, 440, 0.07, tri, decay=2))


def card_flip(v):
    n = sfx.n_samples((0.09, 0.08)[v])
    out, prev = [], 0.0
    for i in range(n):
        cutoff = 0.1 + 0.6 * (i / n)
        prev = prev + cutoff * (sfx.rng.uniform(-1, 1) - prev)
        out.append(prev * math.sin(math.pi * i / n))
    return out


def card_snap():
    return mix(sweep(220, 90, 0.07, decay=2), sweep(1400, 900, 0.025, square, decay=3), noise(0.02, lowpass=0.9),
               gains=[1.0, 0.35, 0.3])


def tally_tick():
    return sweep(1800, 1900, 0.02, tri, decay=3)


def level_up():
    """A bright major arpeggio that rings."""
    notes = [523, 659, 784, 1046]
    run = concat(*[sweep(f, f, 0.05, square, decay=1.2) for f in notes])
    ring = sweep(1046, 1046, 0.35, tri, decay=1.4)
    return concat(run, ring)


def personality_shift():
    return mix(sweep(330, 495, 0.18, tri, curve=0.6, decay=1.5), sweep(660, 990, 0.18, math.sin, curve=0.6, decay=2),
               gains=[0.8, 0.3])


def screen_whoosh():
    n = sfx.n_samples(0.25)
    out, prev = [], 0.0
    for i in range(n):
        cutoff = 0.03 + 0.25 * math.sin(math.pi * i / n)
        prev = prev + cutoff * (sfx.rng.uniform(-1, 1) - prev)
        out.append(prev * math.sin(math.pi * i / n))
    return out


def zoom_whoosh():
    """A long pull-back: filtered noise opening up over a falling tone."""
    n = sfx.n_samples(1.2)
    out, prev, phase = [], 0.0, 0.0
    for i in range(n):
        k = i / n
        cutoff = 0.02 + 0.3 * math.sin(math.pi * k) ** 2
        prev = prev + cutoff * (sfx.rng.uniform(-1, 1) - prev)
        phase += (220 - 140 * k) / RATE
        tone = math.sin(2 * math.pi * phase) * 0.25
        out.append((prev + tone) * math.sin(math.pi * k))
    return out


# ---------------------------------------------------------------- music
def music_loop(bpm, bars, progression, lead_octave, lead_wave, pattern, drums):
    """`bars` bars of bass, arpeggio and a light kick/hat; loops cleanly."""
    beat = 60 / bpm
    total = sfx.n_samples(beat * 4 * bars)
    out = [0.0] * total

    def add(start, samples, gain):
        for i, s in enumerate(samples):
            if 0 <= start + i < total:
                out[start + i] += s * gain

    for bar in range(bars):
        root, chord = progression[bar % len(progression)]
        for step in range(8):
            start = sfx.n_samples((bar * 4 + step * 0.5) * beat)
            length = sfx.n_samples(beat * 0.45)
            bass_f = root if step % 2 == 0 else root * 2
            add(start, [tri(bass_f * i / RATE) * sfx.env(i, length, release=1) for i in range(length)], 0.33)
            note = chord[pattern[step] % len(chord)]
            arp_f = root * lead_octave * 2 ** (note / 12)
            alen = sfx.n_samples(beat * 0.22)
            add(start, [lead_wave(arp_f * i / RATE) * sfx.env(i, alen, release=2) for i in range(alen)], 0.11)
        if drums:
            for b in range(4):
                kick_at = sfx.n_samples((bar * 4 + b) * beat)
                klen = sfx.n_samples(0.12)
                add(kick_at, [math.sin(2 * math.pi * (60 + 90 * (1 - i / klen) ** 3) * i / RATE) * sfx.env(i, klen, release=2)
                              for i in range(klen)], 0.3)
                hat_at = sfx.n_samples((bar * 4 + b + 0.5) * beat)
                add(hat_at, noise(0.03, decay=4, lowpass=0.95), 0.06)
    return out


def act1_loop():
    """Metro: bright, open, 112 bpm in C major."""
    prog = [(130.81, (0, 4, 7, 11)), (110.0, (0, 3, 7, 10)), (87.31, (0, 4, 7, 11)), (98.0, (0, 4, 7, 10))]
    return music_loop(112, 8, prog, 2, tri, [0, 1, 2, 3, 2, 1, 2, 3], drums=False)


def act2_loop():
    """Continent: driving, 120 bpm in A minor."""
    prog = [(110.0, (0, 3, 7)), (87.31, (0, 4, 7)), (130.81, (0, 4, 7)), (98.0, (0, 4, 7))]
    return music_loop(120, 8, prog, 4, square, [0, 1, 2, 1, 0, 1, 2, 1], drums=True)


def act3_loop():
    """Globe: tense, 128 bpm in D minor with a lowered second."""
    prog = [(73.42, (0, 3, 7, 12)), (77.78, (0, 4, 7, 12)), (73.42, (0, 3, 7, 10)), (65.41, (0, 4, 7, 12))]
    return music_loop(128, 8, prog, 8, square, [0, 2, 1, 3, 0, 2, 3, 1], drums=True)


def main():
    sounds = {
        "map_select": map_select(),
        "map_capture": map_capture(),
        "resource_gain": resource_gain(),
        "resource_loss": resource_loss(),
        "card_flip_1": card_flip(0), "card_flip_2": card_flip(1),
        "card_snap": card_snap(),
        "tally_tick": tally_tick(),
        "level_up": level_up(),
        "personality_shift": personality_shift(),
        "screen_whoosh": screen_whoosh(),
        "zoom_whoosh": zoom_whoosh(),
    }
    for name, samples in sounds.items():
        sfx.write(os.path.join(SFX_DIR, name + ".wav"), sfx.normalize(samples))
    for name, samples in (("act1_metro", act1_loop()), ("act2_continent", act2_loop()), ("act3_globe", act3_loop())):
        sfx.write(os.path.join(MUSIC_DIR, name + ".wav"), sfx.normalize(samples, -20.0))


if __name__ == "__main__":
    main()
