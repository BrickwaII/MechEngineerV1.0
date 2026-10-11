#!/usr/bin/env python3
"""Generates the context music in assets/music (R1-D): the menu loop, the
battle loop and its boss variant, the bright post-fight readout loop, and the
victory and defeat stings. The map keeps its per-act loops (gen_map_audio.py).

Built on the synthesis helpers in gen_sfx.py (same rate, loudness matching and
peak limit), with its own fixed seed so the files are reproducible. Per-track
trims live in data/feel/audio.json "music". The output is our own work,
dedicated to the public domain (CC0).

Usage (from the repo root): python3 tools/asset_gen/gen_music.py
Standard library only.
"""
import math
import os
import random
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_sfx as sfx  # noqa: E402

ROOT = sfx.ROOT
MUSIC_DIR = os.path.join(ROOT, "assets", "music")
RATE = sfx.RATE

sfx.rng = random.Random(53)
noise, square, tri = sfx.noise, sfx.square, sfx.tri


def saw(phase):
    return 2 * (phase % 1.0) - 1


class Track:
    """A fixed-length buffer that notes and drums are added into."""

    def __init__(self, bpm, beats):
        self.beat = 60 / bpm
        self.out = [0.0] * sfx.n_samples(self.beat * beats)

    def at(self, beats):
        return sfx.n_samples(beats * self.beat)

    def add(self, start, samples, gain):
        n = len(self.out)
        for i, s in enumerate(samples):
            if 0 <= start + i < n:
                self.out[start + i] += s * gain

    def note(self, beats, freq, length_beats, wave, gain, release=2.0, attack=0.005):
        n = self.at(length_beats)
        self.add(self.at(beats), [wave(freq * i / RATE) * sfx.env(i, n, attack=attack, release=release)
                                  for i in range(n)], gain)

    def kick(self, beats, gain=0.32):
        n = sfx.n_samples(0.13)
        self.add(self.at(beats), [math.sin(2 * math.pi * (55 + 100 * (1 - i / n) ** 3) * i / RATE) * sfx.env(i, n, release=2)
                                  for i in range(n)], gain)

    def snare(self, beats, gain=0.14):
        self.add(self.at(beats), noise(0.11, decay=3, lowpass=0.7), gain)

    def hat(self, beats, gain=0.05):
        self.add(self.at(beats), noise(0.03, decay=4, lowpass=0.95), gain)


def semis(root, n):
    return root * 2 ** (n / 12)


def menu_loop():
    """Menus and the draft: slow, calm pads over a soft pulse, 84 bpm in F."""
    t = Track(84, 32)
    prog = [(87.31, (0, 4, 7, 11)), (73.42, (0, 3, 7, 10)), (77.78, (0, 4, 7, 11)), (65.41, (0, 4, 7, 10))]
    for bar in range(8):
        root, chord = prog[bar % 4]
        for n in chord:
            t.note(bar * 4, semis(root * 2, n), 4, tri, 0.07, release=0.6, attack=0.4)
        t.note(bar * 4, root, 2, tri, 0.25, release=1)
        t.note(bar * 4 + 2, root, 2, tri, 0.18, release=1)
        for step, n in enumerate((0, 2, 1, 3)):
            t.note(bar * 4 + step + 0.5, semis(root * 4, chord[n % len(chord)]), 0.4, math.sin, 0.06, release=3)
    return t.out


def battle_loop(boss=False):
    """Battle: tense and driving, 144 bpm in E minor (the boss: lower, heavier,
    a lowered second and a saw lead)."""
    bpm = 132 if boss else 144
    t = Track(bpm, 32)
    if boss:
        prog = [(41.20, (0, 3, 7)), (43.65, (0, 4, 7)), (41.20, (0, 3, 6)), (38.89, (0, 4, 7))]
    else:
        prog = [(82.41, (0, 3, 7)), (65.41, (0, 4, 7)), (73.42, (0, 4, 7)), (61.74, (0, 4, 7))]
    lead = saw if boss else square
    riff = [0, 0, 12, 0, 7, 0, 10, 12] if not boss else [0, 0, 1, 0, 0, 13, 0, 12]
    for bar in range(8):
        root, chord = prog[bar % 4]
        for step in range(8):
            t.note(bar * 4 + step * 0.5, semis(root * (2 if boss else 1), riff[step]), 0.45, square if boss else tri, 0.2, release=1.5)
        for step in range(16):
            n = chord[(step * 3 + bar) % len(chord)]
            if step % 4 != 3:
                t.note(bar * 4 + step * 0.25, semis(root * 8, n), 0.2, lead, 0.05, release=3)
        for b in range(4):
            t.kick(bar * 4 + b)
            if boss:
                t.kick(bar * 4 + b + 0.75, 0.2)
            if b % 2 == 1:
                t.snare(bar * 4 + b)
            t.hat(bar * 4 + b + 0.5)
            t.hat(bar * 4 + b + 0.25, 0.03)
        if bar % 4 == 3:
            for k in range(4):
                t.snare(bar * 4 + 3 + k * 0.25, 0.08 + 0.02 * k)
    return t.out


def readout_loop():
    """The post-fight readout and level-ups: a short bright loop, 120 bpm in
    G major, four bars."""
    t = Track(120, 16)
    prog = [(98.0, (0, 4, 7, 12)), (130.81, (0, 4, 7, 12)), (110.0, (0, 3, 7, 12)), (146.83, (0, 4, 7, 12))]
    for bar in range(4):
        root, chord = prog[bar]
        t.note(bar * 4, root, 1.8, tri, 0.25, release=1)
        t.note(bar * 4 + 2, root * 2, 1.8, tri, 0.18, release=1)
        for step in range(8):
            n = chord[[0, 1, 2, 3, 2, 1, 2, 3][step]]
            t.note(bar * 4 + step * 0.5, semis(root * 4, n), 0.3, tri, 0.1, release=2)
        t.note(bar * 4, semis(root * 8, chord[2]), 0.25, math.sin, 0.05, release=3)
        for b in range(4):
            t.hat(bar * 4 + b + 0.5, 0.04)
    return t.out


def sting(notes, bpm, wave, last_beats, low):
    """A short phrase that ends on a held chord; not looped."""
    t = Track(bpm, len(notes) * 0.5 + last_beats + 0.5)
    for i, f in enumerate(notes):
        t.note(i * 0.5, f, 0.5, wave, 0.16, release=1.5)
    end = len(notes) * 0.5
    for f in low:
        t.note(end, f, last_beats, tri, 0.14, release=1.2, attack=0.02)
    t.kick(end, 0.3)
    return t.out


def victory_sting():
    """The run is won: a rising major fanfare in C."""
    return sting([261.63, 329.63, 392.0, 523.25, 392.0, 523.25, 659.25], 132, square, 3,
                 [130.81, 261.63, 329.63, 392.0, 523.25])


def defeat_sting():
    """The run is lost: a falling minor phrase in A that ends low."""
    return sting([440.0, 415.30, 392.0, 349.23, 329.63, 293.66], 96, tri, 4,
                 [55.0, 110.0, 130.81, 164.81])


def main():
    tracks = {
        "menu_loop": (menu_loop(), -20.0),
        "battle_loop": (battle_loop(), -19.0),
        "battle_boss_loop": (battle_loop(boss=True), -19.0),
        "readout_loop": (readout_loop(), -20.0),
        "sting_victory": (victory_sting(), -18.0),
        "sting_defeat": (defeat_sting(), -18.0),
    }
    for name, (samples, level) in tracks.items():
        sfx.write(os.path.join(MUSIC_DIR, name + ".wav"), sfx.normalize(samples, level))


if __name__ == "__main__":
    main()
