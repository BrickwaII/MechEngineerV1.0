#!/usr/bin/env python3
"""Generates the post-fight growth one-shots in assets/audio/sfx:

  skill_rank_up.wav    a small rank step (+1 ... +5): two quick rising blips
  skill_tier_up.wav    a tier shift (Mega, Ultra): a rising sweep into a
                       bright three-note chord with a low hit under it
  personality_grow.wav the hexagon fill: a smooth rising tone, 0.6 s

Same synthesis helpers and loudness matching as gen_sfx.py, fixed seed. Our
own work, dedicated to the public domain (CC0).

Usage (from the repo root): python3 tools/asset_gen/gen_growth_sfx.py
"""
import math
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_sfx as s  # noqa: E402


def tone(freq, seconds, wave_fn=math.sin, decay=2.0, attack=0.005):
    n = s.n_samples(seconds)
    out = []
    for i in range(n):
        ph = freq * i / s.RATE
        v = math.sin(2 * math.pi * ph) if wave_fn is math.sin else wave_fn(ph)
        out.append(v * s.env(i, n, attack=attack, release=decay))
    return out


def rank_up():
    a = s.mix(tone(660, 0.09, s.tri), tone(1320, 0.09), gains=[0.8, 0.3])
    b = s.mix(tone(990, 0.16, s.tri), tone(1980, 0.16), gains=[0.8, 0.3])
    return s.concat(a, [0.0] * s.n_samples(0.02), b)


def tier_up():
    rise = s.sweep(220, 880, 0.35, s.tri, curve=0.7, decay=0.6)
    chord_len = 0.9
    chord = s.mix(
        tone(880, chord_len, s.square, decay=1.6, attack=0.01),
        tone(1108.7, chord_len, s.tri, decay=1.6, attack=0.01),
        tone(1318.5, chord_len, math.sin, decay=1.6, attack=0.01),
        tone(110, chord_len, math.sin, decay=3.0),
        s.noise(0.25, decay=4.0, lowpass=0.3),
        gains=[0.18, 0.35, 0.35, 0.6, 0.25])
    return s.concat(rise, chord)


def personality_grow():
    return s.mix(
        s.sweep(300, 900, 0.6, math.sin, curve=1.2, decay=0.4),
        s.sweep(600, 1800, 0.6, s.tri, curve=1.2, decay=0.6),
        gains=[0.8, 0.2])


def main():
    sounds = {
        "skill_rank_up": rank_up(),
        "skill_tier_up": tier_up(),
        "personality_grow": personality_grow(),
    }
    for name, samples in sounds.items():
        s.write(os.path.join(s.SFX_DIR, name + ".wav"), s.normalize(samples))


if __name__ == "__main__":
    main()
