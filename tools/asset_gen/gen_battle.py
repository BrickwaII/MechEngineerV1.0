#!/usr/bin/env python3
"""Generates the battle presentation art and sound in assets/fight/ (M7 P2).

- Extra ally part variants (hover and spider legs, angular and barrel bodies,
  antenna and cyclops heads, cannon and drill arms), 3 tiers each, drawn in the
  key colors like P1's parts so the palette swap recolors them.
- A fallback enemy sheet in key colors, for enemies with no manifest entry;
  the battle recolors it per enemy type (data/ui/battle_presentation.json).
- Skill effects and projectiles, drawn white so the battle tints them.
- Intent icons, a target reticle, tier plates and a soft glow.
- Skill sounds, level layers and the victory and defeat stingers.

Reuses the drawing kit of gen_sprites.py and the synths of gen_sfx.py. The
output is our own work, dedicated to the public domain (CC0), see CREDITS.md.

Usage (from the repo root): python3 tools/asset_gen/gen_battle.py
Needs Pillow.
"""
import math
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_sfx as sfx  # noqa: E402
import gen_sprites as gs  # noqa: E402
from gen_sprites import (  # noqa: E402
    CLEAR, G, M0, M1, M2, O, P0, P1, P2, S0, S1, S2, WHITE, Canvas, rgba, save,
)

OUT = "assets/fight"


# ---------------------------------------------------------------- ally parts
def legs_hover(c, t):
    c.rect(11, 22, 21, 23, M0)
    c.rect(10, 24, 22, 27, M1)
    c.hline(10, 22, 24, M2)
    c.hline(10, 22, 27, M0)
    c.rect(12, 25, 20, 26, P1)
    c.hline(12, 20, 25, P2)
    flame = (1, 2, 2)[t]
    for x0 in (12, 18):
        c.rect(x0, 28, x0 + 2, 27 + flame, G)
    if t >= 1:
        c.rect(8, 25, 9, 27, S1)
        c.rect(23, 25, 24, 27, S1)
        c.set(8, 25, S2)
        c.set(23, 25, S2)
    if t >= 2:
        c.rect(15, 28, 17, 30, G)
        c.set(16, 31, WHITE)


def legs_spider(c, t):
    c.rect(11, 22, 21, 24, M0)
    c.hline(11, 21, 22, M1)
    for (x0, x1) in ((12, 8), (14, 12), (18, 20), (20, 24)):
        steps = 7
        for i in range(steps + 1):
            x = round(x0 + (x1 - x0) * i / steps)
            c.set(x, 24 + i, M1)
        c.rect(x1 - 1, 31, x1 + 1, 31, P1)
    if t >= 1:
        for x in (10, 13, 19, 22):
            c.set(x, 27, S2)
            c.set(x, 28, S1)
    if t >= 2:
        c.hline(13, 19, 23, G)


def body_angular(c, t):
    for y in range(13, 24):
        inset = (y - 13) // 4
        c.hline(10 + inset, 21 - inset, y, P1)
    c.hline(10, 21, 13, P2)
    c.hline(12, 19, 23, P0)
    c.rect(14, 16, 17, 19, M1)
    c.hline(14, 17, 16, M2)
    if t >= 1:
        for x in (8, 9):
            c.vline(x, 12 + (9 - x), 15, S1)
        c.rect(22, 11, 23, 14, S1)
        c.set(22, 11, S2)
    if t >= 2:
        c.rect(15, 17, 16, 18, G)
        c.hline(11, 20, 21, S0)
        c.set(9, 11, G)


def body_barrel(c, t):
    c.rect(11, 12, 20, 23, P1)
    c.vline(12, 13, 22, P2)
    c.vline(20, 12, 23, P0)
    c.hline(11, 20, 12, P2)
    c.hline(11, 20, 23, P0)
    c.rect(14, 15, 17, 19, M1)
    if t >= 1:
        for y in (14, 20):
            c.hline(10, 21, y, S1)
            c.set(10, y, S0)
            c.set(21, y, S0)
    if t >= 2:
        for y in (16, 18):
            c.hline(15, 16, y, G)
        c.set(11, 17, G)


def head_antenna(c, t):
    c.rect(13, 7, 19, 12, P1)
    c.hline(13, 19, 7, P2)
    c.hline(13, 19, 12, P0)
    c.hline(15, 19, 9, M0)
    c.hline(16, 19, 9, G)
    c.rect(14, 12, 18, 13, M0)
    c.vline(15, 2, 6, M2)
    c.rect(14, 1, 16, 2, P2)
    if t >= 1:
        c.vline(18, 4, 6, M2)
        c.set(18, 3, S2)
        c.rect(12, 9, 12, 11, S1)
    if t >= 2:
        c.set(15, 1, G)
        c.set(18, 3, G)
        c.hline(13, 19, 11, S1)


def head_cyclops(c, t):
    c.ellipse(16, 9, 4, 3, P1)
    c.hline(13, 18, 6, P2)
    c.hline(13, 19, 12, P0)
    c.ellipse(17, 9, 2, 2, M0)
    c.rect(17, 9, 18, 9, G)
    c.rect(14, 12, 18, 13, M0)
    if t >= 1:
        c.hline(14, 20, 6, S1)
        c.set(20, 7, S0)
    if t >= 2:
        c.set(12, 9, G)
        c.set(16, 4, G)
        c.ellipse(17, 9, 1, 1, G)


def arm_cannon(c, t):
    length = (6, 7, 9)[t]
    c.rect(15, 15, 17, 19, M1)
    c.vline(17, 15, 19, M0)
    c.rect(15, 14, 17, 15, P2)
    c.rect(17, 17, 17 + length, 20, M1)
    c.hline(17, 17 + length, 17, M2)
    c.hline(17, 17 + length, 20, M0)
    c.vline(17 + length, 16, 21, P1)
    c.set(17 + length, 18, G)
    c.set(17 + length, 19, G)
    if t >= 1:
        c.rect(18, 16, 20, 21, S1)
        c.hline(18, 20, 16, S2)
    if t >= 2:
        c.rect(21, 15, 17 + length - 2, 15, M2)
        c.set(17 + length - 2, 15, G)


def arm_drill(c, t):
    length = (4, 5, 7)[t]
    c.rect(15, 15, 17, 19, M1)
    c.vline(17, 15, 19, M0)
    c.rect(15, 14, 17, 15, P2)
    c.rect(17, 17, 20, 20, M1)
    c.hline(17, 20, 17, M2)
    for i in range(length + 1):
        half = round(2 * (1 - i / max(1, length)))
        x = 21 + i
        c.vline(x, 18 - half, 19 + half, M2 if i % 2 == 0 else M0)
    if t >= 1:
        c.rect(18, 16, 20, 16, S1)
        c.rect(18, 21, 20, 21, S1)
    if t >= 2:
        c.set(21 + length, 18, G)
        c.set(21 + length, 19, G)


NEW_PARTS = {
    "legs": {"hover": legs_hover, "spider": legs_spider},
    "body": {"angular": body_angular, "barrel": body_barrel},
    "head": {"antenna": head_antenna, "cyclops": head_cyclops},
    "arm": {"cannon": arm_cannon, "drill": arm_drill},
}

_base_tip = gs.weapon_tip


def weapon_tip(variant, tier):
    if variant == "cannon":
        return 17 + (6, 7, 9)[tier] - 1
    if variant == "drill":
        return 21 + (4, 5, 7)[tier] - 2
    return _base_tip(variant, tier)


def ally_part_path(part, variant, tier):
    return f"res://{OUT}/units/ally_frame/{part}_{variant}_{tier}.png"


def gen_ally_parts():
    gs.weapon_tip = weapon_tip
    for part, variants in NEW_PARTS.items():
        gs.PART_DRAW[part].update(variants)
    written = []
    for part, variants in NEW_PARTS.items():
        for variant in variants:
            for tier_name, t in gs.TIER_LEVEL.items():
                def frame(anim, i, part=part, variant=variant, t=t):
                    return gs.ally_part_frame(part, variant, t, gs.ALLY_MOTION[anim][i])
                written.append(save(gs.build_sheet(frame), ally_part_path(part, variant, tier_name)))
    return written


# ---------------------------------------------------------------- fallback enemy
def fallback_frame(tier, motion):
    """A hostile walker drawn facing right in key colors, then flipped."""
    flags = motion.get("flags", set())
    c = Canvas(*gs.FRAME)
    hull_w = (5, 6, 7)[tier]
    cx = 15
    down = "flat" in flags
    if not down:
        for x0 in (cx - 4, cx + 2):
            c.rect(x0, 23, x0 + 2, 29, M1)
            c.vline(x0 + 2, 23, 29, M0)
            c.rect(x0 - 1, 30, x0 + 3, 31, S0)
    top = 12 if not down else 20
    bottom = 23 if not down else 27
    c.rect(cx - hull_w, top, cx + hull_w, bottom, P1)
    c.hline(cx - hull_w, cx + hull_w, top, P2)
    c.hline(cx - hull_w, cx + hull_w, bottom, P0)
    c.vline(cx + hull_w, top + 1, bottom, P0)
    # Head with one eye, toward the front.
    hy = top - 4
    c.rect(cx - 2, hy, cx + 4, top - 1, S1)
    c.hline(cx - 2, cx + 4, hy, S2)
    eye = G if "dim" not in flags else M0
    c.rect(cx + 2, hy + 1, cx + 4, hy + 2, eye)
    if "charge" in flags:
        c.rect(cx + 2, hy + 1, cx + 4, hy + 2, WHITE)
    # Gun arm.
    gun = (5, 6, 8)[tier]
    c.rect(cx + hull_w, top + 4, cx + hull_w + gun, top + 6, M1)
    c.hline(cx + hull_w, cx + hull_w + gun, top + 4, M2)
    c.set(cx + hull_w + gun, top + 5, G)
    if tier >= 1:
        c.rect(cx - hull_w - 2, top - 1, cx - hull_w + 2, top + 3, S1)
        c.hline(cx - hull_w - 2, cx - hull_w + 2, top - 1, S2)
        c.rect(cx - 2, top + 3, cx + 2, top + 7, M1)
    if tier >= 2:
        for x in (cx - 4, cx - 1, cx + 2):
            c.set(x, top - 1, S2)
            c.set(x, top - 2, G)
        c.hline(cx - hull_w + 1, cx + hull_w - 1, bottom - 2, S0)
        c.set(cx, top + 5, G)
    c.outline()
    if "guard" in flags:
        x = cx + hull_w + gun + 2
        c.vline(x, top - 4, bottom, S2)
        c.vline(x + 1, top - 2, bottom - 2, S1)
        if "shimmer" in flags:
            c.set(x, top, WHITE)
    dx, dy = motion["d"]
    c = c.flipped().shifted(dx, dy)
    if "flash" in flags:
        x, y = 31 - (cx + hull_w + gun) - 2 + dx, top + 5 + dy
        for px, py in ((x, y), (x - 1, y), (x, y - 1), (x, y + 1), (x + 1, y)):
            c.set(px, py, gs.SPARK)
    for name, points in gs.HEAL_SPARKLES.items():
        if name in flags:
            for x, y in points:
                gs.sparkle(c, x, y)
    return c


def gen_fallback():
    written = []
    for tier_name, t in gs.TIER_LEVEL.items():
        sheet = gs.build_sheet(lambda anim, i, t=t: fallback_frame(t, gs.DRONE_MOTION[anim][i]))
        written.append(save(sheet, f"res://{OUT}/units/enemy_fallback/fallback_{tier_name}.png"))
    return written


# ---------------------------------------------------------------- effects (white, tinted in game)
W = WHITE
W2 = (255, 255, 255, 180)
W3 = (255, 255, 255, 100)


def strip(frames, w, h):
    img = Image.new("RGBA", (w * len(frames), h), CLEAR)
    for i, c in enumerate(frames):
        c.paste_onto(img, i * w, 0)
    return img


def arc_points(cx, cy, r, a0, a1, n=40):
    pts = []
    for k in range(n + 1):
        a = a0 + (a1 - a0) * k / n
        pts.append((round(cx + math.cos(a) * r), round(cy + math.sin(a) * r)))
    return pts


def fx_slash():
    out = []
    for i in range(5):
        c = Canvas(32, 32)
        sweep_to = -math.pi * 0.75 + i * math.pi * 0.35
        for r, col in ((11, W), (10, W2), (12, W3)):
            for x, y in arc_points(16, 16, r, -math.pi * 0.75, min(sweep_to, math.pi * 0.6)):
                if i < 4 or r != 10:
                    c.set(x, y, col if i < 3 else W3)
        out.append(c)
    return out


def fx_impact_ring():
    out = []
    for i in range(5):
        c = Canvas(32, 32)
        r = 3 + i * 3
        for x, y in arc_points(16, 16, r, 0, math.tau, 60):
            c.set(x, y, W if i < 3 else W2)
        if i < 2:
            c.ellipse(16, 16, 4 - i, 4 - i, W)
        for k in range(6):
            a = k * math.tau / 6 + 0.3
            for d in range(r - 2, r + 3):
                c.set(round(16 + math.cos(a) * d), round(16 + math.sin(a) * d), W2)
        out.append(c)
    return out


def fx_bolt():
    out = []
    for i in range(2):
        c = Canvas(16, 16)
        c.rect(2, 7, 13, 8, W2)
        c.rect(6, 6, 14, 9, W)
        c.set(15, 7 + i, W)
        c.hline(0, 4, 7 + i, W3)
        out.append(c)
    return out


def fx_orb():
    out = []
    for i in range(2):
        c = Canvas(16, 16)
        c.ellipse(8, 8, 5, 5, W3)
        c.ellipse(8, 8, 4 - i, 4 - i, W2)
        c.ellipse(8, 8, 2, 2, W)
        out.append(c)
    return out


def fx_arc_wave():
    out = []
    import random
    rnd = random.Random(11)
    for i in range(5):
        c = Canvas(32, 32)
        y = 16
        x = 1
        while x < 31:
            ny = max(4, min(28, y + rnd.choice((-3, -2, 2, 3))))
            steps = 3
            for s in range(steps + 1):
                c.set(x + s, round(y + (ny - y) * s / steps), W if i < 3 else W2)
                c.set(x + s, round(y + (ny - y) * s / steps) + 1, W3)
            x += steps
            y = ny
        out.append(c)
    return out


def fx_shield_dome():
    out = []
    for i in range(4):
        c = Canvas(32, 32)
        top = math.pi + 0.25
        reach = top + (math.pi - 0.5) * min(1.0, (i + 1) / 3)
        for x, y in arc_points(16, 22, 14, top, reach, 60):
            c.set(x, y, W)
        for x, y in arc_points(16, 22, 12, top, reach, 60):
            c.set(x, y, W3)
        if i >= 2:
            for k in range(5):
                a = math.pi + 0.5 + k * 0.5
                c.set(round(16 + math.cos(a) * 13), round(22 + math.sin(a) * 13), W2)
        out.append(c)
    return out


def fx_wrench():
    out = []
    for i in range(4):
        c = Canvas(16, 16)
        a = -0.8 + i * 0.5
        for d in range(-5, 5):
            c.set(round(8 + math.cos(a) * d), round(8 + math.sin(a) * d), W)
        hx, hy = round(8 + math.cos(a) * 5), round(8 + math.sin(a) * 5)
        c.ellipse(hx, hy, 2, 2, W)
        c.set(hx, hy, CLEAR)
        if i >= 2:
            c.set(2, 2 + i, W2)
            c.set(13, 12 - i, W2)
        out.append(c)
    return out


def fx_gear():
    out = []
    for i in range(4):
        c = Canvas(16, 16)
        c.ellipse(8, 8, 4, 4, W)
        c.ellipse(8, 8, 1, 1, CLEAR)
        for k in range(6):
            a = k * math.tau / 6 + i * math.tau / 24
            for d in (5, 6):
                c.set(round(8 + math.cos(a) * d), round(8 + math.sin(a) * d), W2 if d == 6 else W)
        out.append(c)
    return out


def fx_blast():
    out = []
    for i in range(6):
        c = Canvas(32, 32)
        r = 4 + i * 2
        if i < 4:
            c.ellipse(16, 16, r, r, W2)
            c.ellipse(16, 16, max(1, r - 3), max(1, r - 3), W)
        for k in range(10):
            a = k * math.tau / 10 + i * 0.15
            d = r + 2
            c.set(round(16 + math.cos(a) * d), round(16 + math.sin(a) * d), W if i < 4 else W3)
            c.set(round(16 + math.cos(a) * (d + 2)), round(16 + math.sin(a) * (d + 2)), W3)
        out.append(c)
    return out


def fx_charge():
    out = []
    for i in range(4):
        c = Canvas(16, 16)
        r = 7 - i * 2
        for k in range(6):
            a = k * math.tau / 6 + i * 0.4
            c.set(round(8 + math.cos(a) * r), round(8 + math.sin(a) * r), W)
        c.ellipse(8, 8, max(0, i - 1), max(0, i - 1), W2)
        out.append(c)
    return out


def fx_cross():
    out = []
    for i in range(4):
        c = Canvas(16, 16)
        y = 9 - i * 2
        c.rect(7, y - 3, 8, y + 2, W if i < 3 else W2)
        c.rect(5, y - 1, 10, y, W if i < 3 else W2)
        out.append(c)
    return out


EFFECTS = {
    "slash": (fx_slash, 32),
    "impact_ring": (fx_impact_ring, 32),
    "bolt": (fx_bolt, 16),
    "orb": (fx_orb, 16),
    "arc_wave": (fx_arc_wave, 32),
    "shield_dome": (fx_shield_dome, 32),
    "wrench": (fx_wrench, 16),
    "gear": (fx_gear, 16),
    "blast": (fx_blast, 32),
    "charge": (fx_charge, 16),
    "cross": (fx_cross, 16),
}


def gen_effects():
    written = []
    for name, (maker, size) in EFFECTS.items():
        written.append(save(strip(maker(), size, size), f"{OUT}/effects/{name}.png"))
    return written


# ---------------------------------------------------------------- icons, plates, glow
INTENT_ICONS = {
    "attack": ("danger", [
        "..........oo",
        ".........oao",
        "........oao.",
        ".......oao..",
        "......oao...",
        ".o...oao....",
        ".oo.oao.....",
        "..ooao......",
        "..oaoo......",
        ".oaoooo.....",
        "oao...o.....",
        "oo..........",
    ]),
    "heal": ("hp", [
        "...oooo.....",
        "..oaaaao....",
        "..oao.oo....",
        "..oaao......",
        "...oaao.....",
        "....oaao....",
        ".....oaao...",
        "......oaao..",
        ".......oaao.",
        "........oaao",
        ".........ooo",
        "............",
    ]),
    "guard": ("selected", [
        "....oooo....",
        "..ooaaaaoo..",
        ".oaaaaaaaao.",
        ".oaaabbaaao.",
        ".oaabbbbaao.",
        ".oaaabbaaao.",
        "..oaaaaaao..",
        "..oaaaaaao..",
        "...oaaaao...",
        "....oaao....",
        ".....oo.....",
        "............",
    ]),
    "charge": ("energy", [
        "....oooo....",
        "...oaaaao...",
        "..oooooooo..",
        "..o..oo..o..",
        "..o.oao..o..",
        "..ooaao..o..",
        "..oaaaaoo...",
        "..o.oaao.o..",
        "..o.oao..o..",
        "..o.oo...o..",
        "..oooooooo..",
        "............",
    ]),
}


def gen_icons():
    written = []
    for name, (color, rows) in INTENT_ICONS.items():
        rows = [r.ljust(12, ".")[:12] for r in rows]
        img = gs.icon(rows, {"o": O, "a": gs.pal(color), "b": rgba("#ffffff", 220)})
        written.append(save(img, f"{OUT}/icons/intent_{name}.png"))
    # Target reticle: white corners, tinted in game.
    c = Canvas(16, 16)
    for (x, y, dx, dy) in ((0, 0, 1, 1), (15, 0, -1, 1), (0, 15, 1, -1), (15, 15, -1, -1)):
        for k in range(4):
            c.set(x + dx * k, y, W)
            c.set(x, y + dy * k, W)
    c.rect(7, 7, 8, 8, W2)
    written.append(save(strip([c], 16, 16), f"{OUT}/icons/target_reticle.png"))
    return written


def plate(tier):
    """A 32x6 base plate in key colors: plain, trimmed, then glowing."""
    c = Canvas(32, 6)
    c.rect(4, 1, 27, 4, gs.M1)
    c.hline(4, 27, 1, gs.M2)
    c.hline(4, 27, 4, gs.M0)
    if tier >= 1:
        c.rect(3, 2, 28, 3, S1)
        c.hline(3, 28, 2, S2)
        for x in (6, 25):
            c.set(x, 3, gs.M2)
    if tier >= 2:
        c.hline(8, 23, 3, G)
        for x in (12, 16, 20):
            c.set(x, 2, P2)
    c.outline()
    return c


def glow():
    img = Image.new("RGBA", (32, 32), CLEAR)
    for y in range(32):
        for x in range(32):
            d = math.hypot(x - 15.5, y - 15.5) / 15.5
            if d < 1.0:
                a = int(255 * (1.0 - d) ** 2)
                # Banded, so the glow stays pixel-art.
                a = (a // 48) * 48
                if a:
                    img.putpixel((x, y), (255, 255, 255, a))
    return img


def gen_tiers():
    written = []
    for tier_name, t in gs.TIER_LEVEL.items():
        written.append(save(strip([plate(t)], 32, 6), f"{OUT}/tiers/plate_{tier_name}.png"))
    written.append(save(glow(), f"{OUT}/tiers/glow.png"))
    return written


# ---------------------------------------------------------------- sounds
def clicks(n, gap, f=2400):
    out = []
    for _ in range(n):
        out += sfx.mix(sfx.noise(0.012, decay=3, lowpass=0.9), sfx.sweep(f, f * 0.7, 0.012, sfx.square, decay=3),
                       gains=[0.6, 0.4])
        out += [0.0] * sfx.n_samples(gap)
    return out


def chord(freqs, seconds, wave_fn=sfx.tri, decay=1.5):
    return sfx.mix(*[sfx.sweep(f, f, seconds, wave_fn, decay=decay) for f in freqs])


SOUNDS = {
    "skill_strike": lambda: sfx.mix(sfx.swing(0), sfx.concat([0.0] * sfx.n_samples(0.05), sfx.hit_light(1)),
                                    gains=[0.6, 1.0]),
    "skill_overcharge_shot": lambda: sfx.concat(sfx.sweep(300, 1400, 0.08, sfx.square, decay=0.5),
                                                sfx.mix(sfx.shot(0), sfx.noise(0.06, lowpass=0.7), gains=[1.0, 0.3])),
    "skill_heavy_strike": lambda: sfx.mix(sfx.swing(1), sfx.concat([0.0] * sfx.n_samples(0.06), sfx.hit_heavy(0)),
                                          gains=[0.5, 1.0]),
    "skill_arc_sweep": lambda: sfx.mix(sfx.sweep(90, 180, 0.3, sfx.square, decay=1.2),
                                       sfx.noise(0.3, decay=1.5, lowpass=0.85), gains=[0.6, 0.7]),
    "skill_brace": lambda: sfx.concat(sfx.mix(sfx.guard(0), sfx.noise(0.03, lowpass=0.9), gains=[1.0, 0.4]),
                                      sfx.sweep(220, 220, 0.12, sfx.tri, decay=1.5)),
    "skill_patch_up": lambda: sfx.concat(clicks(3, 0.03), chord((659, 988), 0.14)),
    "skill_shield_ally": lambda: sfx.concat(chord((523, 784), 0.08), chord((659, 988, 1319), 0.16, decay=2)),
    "skill_overload": lambda: sfx.concat(sfx.charge()[: sfx.n_samples(0.18)],
                                         sfx.mix(sfx.hit_heavy(1), sfx.sweep(80, 30, 0.3, decay=1.2), gains=[1.0, 0.8])),
    "skill_repair": lambda: sfx.concat(clicks(2, 0.04, 1800), chord((392, 587), 0.16)),
    "skill_layer_impact": lambda: sfx.mix(sfx.sweep(90, 40, 0.14, decay=1.5), sfx.noise(0.05, lowpass=0.3),
                                          gains=[1.0, 0.4]),
    "skill_layer_shimmer": lambda: sfx.concat(*[sfx.sweep(f, f, 0.04, sfx.tri, decay=2) for f in (1568, 2093, 2637)]),
    "skill_layer_bass": lambda: sfx.sweep(70, 35, 0.35, decay=1.3),
    "battle_victory": lambda: sfx.concat(*[sfx.sweep(f, f, d, sfx.square, decay=1.2) for f, d in (
        (523, 0.1), (659, 0.1), (784, 0.1), (1047, 0.35))]),
    "battle_defeat": lambda: sfx.concat(*[sfx.sweep(f, f * 0.98, d, sfx.tri, decay=1.0) for f, d in (
        (392, 0.16), (330, 0.16), (262, 0.16), (196, 0.45))]),
}


def gen_sounds():
    written = []
    for name, maker in SOUNDS.items():
        path = os.path.join(gs.ROOT, OUT, "audio", name + ".wav")
        sfx.write(path, sfx.normalize(maker()))
        written.append(path)
    return written


def main():
    written = gen_ally_parts() + gen_fallback() + gen_effects() + gen_icons() + gen_tiers()
    for path in written:
        print(os.path.relpath(path, gs.ROOT))
    written += gen_sounds()
    print(f"{len(written)} files", file=sys.stderr)


if __name__ == "__main__":
    main()
