#!/usr/bin/env python3
"""Generates the enemy faction sprites in assets/enemies (M7 P4).

One sheet per unit type and tier, in the sheet layout of
data/feel/sprite_manifest.json. Each faction has its own color ramp
(FACTION_RAMPS, matching the faction colors in data/combat/factions.json);
outline, metal and effect colors come from data/feel/palette.json, as for the
ally bots. Tiers keep the silhouette and add armor, a bigger weapon and
brighter effects. Units are drawn facing right, then flipped to face left.

The output is our own work, dedicated to the public domain (CC0), see
CREDITS.md.

Usage (from the repo root): python3 tools/asset_gen/gen_enemies.py
Needs Pillow. Uses the drawing helpers in gen_sprites.py.
"""
import math
import os
import sys

from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

from gen_sprites import (  # noqa: E402
    CLEAR, FRAME, HEAL_SPARKLES, M0, M1, M2, MANIFEST, O, ROOT, SPARK, TIER_LEVEL, WHITE,
    Canvas, build_sheet, pal, rgba, save, sparkle,
)

GROUND = 29
# Padding around a frame while it is rotated.
PAD = 24

# Dark, mid, light ramp plus accent (weapon glow, eyes, effects) per faction.
FACTION_RAMPS = {
    "human_resistance": dict(ramp=("#4a5124", "#7a8436", "#a4ad4a"), accent="#ff9f43", accent_hi="#ffd08a"),
    "enhanced_humans": dict(ramp=("#23407a", "#3d6ad0", "#7fb0ff"), accent="#9ff0ff", accent_hi="#ffffff"),
    "rival_ai": dict(ramp=("#7a2a2a", "#c9473f", "#ff6b5e"), accent="#ffe08a", accent_hi="#ffffff"),
    "aliens": dict(ramp=("#6a1f63", "#b0399f", "#e05ad0"), accent="#b6ff5a", accent_hi="#eaffc0"),
}
SKIN = (rgba("#8a6446"), rgba("#c99a6e"))
GLASS = (rgba("#3b6f8f"), rgba("#9fd8ff"))
GLITCH = rgba("#ffd23f")
SMOKE = (rgba("#3a3a48"), rgba("#5f6574"))


class Pal:
    def __init__(self, faction):
        f = FACTION_RAMPS[faction]
        self.d, self.m, self.l = (rgba(h) for h in f["ramp"])
        self.a = rgba(f["accent"])
        self.ah = rgba(f["accent_hi"])


def line(c, x0, y0, x1, y1, col):
    """Bresenham line, inclusive."""
    dx, dy = abs(x1 - x0), -abs(y1 - y0)
    sx, sy = (1 if x0 < x1 else -1), (1 if y0 < y1 else -1)
    err = dx + dy
    while True:
        c.set(x0, y0, col)
        if x0 == x1 and y0 == y1:
            return
        e2 = 2 * err
        if e2 >= dy:
            err += dy
            x0 += sx
        if e2 <= dx:
            err += dx
            y0 += sy


def rotated(c, degrees, px, py):
    """Nearest-neighbour rotation about (px, py); positive tips the top left.
    Returns a canvas PAD pixels larger on every side, so nothing is clipped."""
    out = Canvas(c.w + 2 * PAD, c.h + 2 * PAD)
    a = math.radians(degrees)
    ca, sa = math.cos(a), math.sin(a)
    for y in range(out.h):
        for x in range(out.w):
            # Inverse map: rotate the destination back by -a.
            dx, dy = x - PAD - px, y - PAD - py
            sx = round(px + dx * ca - dy * sa)
            sy = round(py + dx * sa + dy * ca)
            p = c.get(sx, sy)
            if p[3]:
                out.set(x, y, p)
    return out


def bounds(c):
    xs, ys = [], []
    for y in range(c.h):
        for x in range(c.w):
            if c.px[y][x][3]:
                xs.append(x)
                ys.append(y)
    if not xs:
        return 0, 0, 0, 0
    return min(xs), min(ys), max(xs), max(ys)


def to_ground(big, anchor_x):
    """Cuts a frame out of a padded canvas: the lowest pixel sits on the ground
    line, the pivot stays at anchor_x unless that would push pixels off the frame."""
    x0, _, x1, y1 = bounds(big)
    out = Canvas(*FRAME)
    left = anchor_x + PAD - 15
    left = min(max(left, x1 - (FRAME[0] - 2)), x0 - 1) if x1 - x0 < FRAME[0] - 2 else x0
    top = y1 - GROUND
    for y in range(FRAME[1]):
        for x in range(FRAME[0]):
            out.set(x, y, big.get(x + left, y + top))
    return out


# ---------------------------------------------------------------- motion
# Authored for the left-facing unit (after the flip): negative x lunges at the
# squad. "bob" lifts the upper body one pixel; "recoil" pulls the weapon back.
MOTION = {
    "idle": [dict(d=(0, 0)), dict(d=(0, 0), bob=1, flags={"glow2"}), dict(d=(0, 0), bob=1), dict(d=(0, 0), flags={"glow2"})],
    "windup": [dict(d=(1, 0)), dict(d=(2, 0), bob=1), dict(d=(2, 0), bob=1, flags={"charge"})],
    "attack": [dict(d=(-3, 0), flags={"flash"}), dict(d=(-4, 0), recoil=1, flags={"flash"}),
               dict(d=(-2, 0), recoil=1), dict(d=(0, 0))],
    "hit": [dict(d=(2, 0), flags={"hurt"}), dict(d=(1, 0), flags={"hurt"}), dict(d=(0, 0))],
    "guard": [dict(d=(1, 0), flags={"guard"}), dict(d=(1, 0), bob=1, flags={"guard", "shimmer"})],
    "heal": [dict(d=(0, 0), flags={"heal0"}), dict(d=(0, 0), bob=1, flags={"heal1"}),
             dict(d=(0, 0), bob=1, flags={"heal2"}), dict(d=(0, 0), flags={"heal3"})],
    "down": [dict(d=(0, 0), fall=0, flags={"dim"}), dict(d=(0, 0), fall=1, flags={"dim", "off"}),
             dict(d=(0, 0), fall=2, flags={"dim", "off"}), dict(d=(0, 0), fall=3, flags={"dim", "off", "flat"})],
}
TOPPLE = (0, 25, 60, 88)


# ---------------------------------------------------------------- humans
def humanoid(c, p, bob, legs_col, torso_col, torso_hi, boots=M0, wide=False):
    """Legs, torso and head of a standing human, facing right. Returns the head's top y."""
    for x0 in (13, 16):
        c.rect(x0, 22, x0 + 1, GROUND - 1, legs_col)
        c.rect(x0, GROUND - 1, x0 + 2, GROUND, boots)
    u = -bob
    w = 1 if wide else 0
    c.rect(12 - w, 14 + u, 18 + w, 21, torso_col)
    c.hline(12 - w, 18 + w, 14 + u, torso_hi)
    c.hline(12, 18, 21, p.d)
    c.rect(13, 8 + u, 17, 13 + u, SKIN[1])
    c.vline(13, 8 + u, 13 + u, SKIN[0])
    c.rect(16, 10 + u, 17, 10 + u, O)
    return 8 + u


def soldier(c, t, pose, p):
    bob, flags = pose.get("bob", 0), pose["flags"]
    u = -bob
    top = humanoid(c, p, bob, p.d, p.m, p.l)
    # Headgear: cap, then helmet, then helmet with a lit visor.
    if t == 0:
        c.rect(13, top - 1, 17, top, p.l)
        c.hline(17, 19, top, p.l)
    else:
        c.rect(12, top - 2, 18, top + 1, M1)
        c.hline(13, 17, top - 2, M2)
        c.hline(18, 19, top + 1, M1)
    if t >= 2:
        c.hline(15, 18, top + 2, p.a if "dim" not in flags else M0)
    # Vest plates.
    if t >= 1:
        c.rect(13, 15 + u, 17, 19 + u, M1)
        c.hline(13, 17, 15 + u, M2)
        c.set(15, 17 + u, M0)
    if t >= 2:
        c.rect(11, 14 + u, 12, 16 + u, M1)
        c.set(11, 14 + u, M2)
    # Rifle, longer and heavier each tier.
    r = -pose.get("recoil", 0)
    tip = (22, 24, 26)[t] + r
    y = 17 + u
    # A downed soldier has dropped the rifle.
    if "off" not in flags:
        c.rect(11 + r, y, tip, y, M0)
        c.hline(13 + r, tip - 1, y - 1, M1)
        c.rect(11 + r, y + 1, 13 + r, y + 2, M0)
        if t >= 1:
            c.rect(17 + r, y + 1, 18 + r, y + 2, M1)
        if t >= 2:
            c.rect(15 + r, y - 3, 18 + r, y - 2, M2)
            c.hline(tip - 3, tip, y + 1, M0)
        c.rect(16 + r, y, 18 + r, y + 1, SKIN[1])
    return tip, y


def tank(c, t, pose, p):
    flags = pose["flags"]
    bob = pose.get("bob", 0)
    # Treads.
    c.rect(4, 24, 27, GROUND, M0)
    c.hline(5, 26, 24, M1)
    for x in range(6, 27, 4):
        c.rect(x, 26, x + 1, 27, M2 if "off" not in flags else M1)
    c.set(4, 24, CLEAR)
    c.set(27, 24, CLEAR)
    c.set(4, GROUND, CLEAR)
    c.set(27, GROUND, CLEAR)
    # Hull.
    c.rect(5, 19, 26, 23, p.m)
    c.hline(6, 25, 19, p.l)
    c.hline(5, 26, 23, p.d)
    if t >= 1:
        c.rect(3, 21, 28, 24, M1)
        c.hline(3, 28, 21, M2)
    # Turret, lifting a pixel on the idle bob (engine rumble).
    u = -bob
    c.rect(10, 13 + u, 20, 18, p.m)
    c.hline(11, 19, 13 + u, p.l)
    c.vline(10, 14 + u, 18, p.d)
    if t >= 2:
        c.rect(11, 15 + u, 14, 17 + u, M1)
        c.hline(11, 14, 15 + u, M2)
    # A human commander in the hatch.
    if "off" not in flags:
        c.rect(13, 10 + u, 15, 12 + u, SKIN[1])
        c.hline(12, 16, 10 + u, p.d)
    # Barrel.
    r = -pose.get("recoil", 0)
    tip = (25, 27, 29)[t] + r
    y = 15 + u
    if "off" in flags:
        line(c, 20, y, tip - 2, y + 4, M0)
    else:
        c.rect(20, y, tip, y + (0 if t == 0 else 1), M1)
        c.hline(20, tip, y, M2)
        if t >= 2:
            c.rect(tip - 1, y - 1, tip, y + 2, M1)
    # Antenna light.
    if t >= 1:
        c.vline(11, 8 + u, 12 + u, M2)
        c.set(11, 7 + u, p.a if "dim" not in flags else M0)
    if "flat" in flags:
        for x, y2 in ((12, 9), (14, 7), (13, 5), (16, 8)):
            c.set(x, y2, SMOKE[1])
            c.set(x + 1, y2, SMOKE[0])
    return tip, y


def pilot_mech(c, t, pose, p):
    bob, flags = pose.get("bob", 0), pose["flags"]
    u = -bob
    # Thick legs with feet.
    for x0 in (10, 17):
        c.rect(x0, 21, x0 + 3, GROUND - 2, M1)
        c.vline(x0 + 3, 21, GROUND - 2, M0)
        c.rect(x0 - 1, GROUND - 1, x0 + 4, GROUND, p.d)
        c.hline(x0 - 1, x0 + 4, GROUND - 1, p.m)
    # Box torso with a glass cockpit and the pilot inside.
    c.rect(8, 9 + u, 22, 20 + u, p.m)
    c.hline(8, 22, 9 + u, p.l)
    c.vline(8, 10 + u, 20 + u, p.l)
    c.hline(8, 22, 20 + u, p.d)
    c.rect(15, 11 + u, 20, 15 + u, GLASS[0])
    c.rect(16, 11 + u, 20, 12 + u, GLASS[1])
    if "off" not in flags:
        c.rect(16, 13 + u, 17, 15 + u, SKIN[1])
    # Shoulder plate, then a missile pod.
    if t >= 1:
        c.rect(6, 8 + u, 11, 12 + u, M1)
        c.hline(6, 11, 8 + u, M2)
    if t >= 2:
        c.rect(7, 4 + u, 12, 7 + u, M0)
        for x in (8, 10, 12):
            c.set(x, 4 + u, p.a if "dim" not in flags else M1)
    # Arm cannon.
    r = -pose.get("recoil", 0)
    tip = (26, 28, 30)[t] + r
    y = 17 + u
    c.rect(19 + r, y - 1, 22 + r, y + 2, M1)
    c.rect(22 + r, y, tip, y + (1 if t < 2 else 2), M0)
    c.hline(22 + r, tip, y, M2)
    return tip, y


def cyborg(c, t, pose, p):
    bob, flags = pose.get("bob", 0), pose["flags"]
    u = -bob
    top = humanoid(c, p, bob, p.d, p.m, p.l, wide=True)
    # Half the face is metal, with an implant eye.
    c.rect(15, top, 17, top + 3, M1)
    c.set(17, top + 2, p.a if "dim" not in flags else M0)
    if t >= 2:
        c.set(16, top + 2, p.ah if "dim" not in flags else M0)
    # Metal plates up the body.
    if t >= 1:
        c.rect(11, 15 + u, 13, 20 + u, M1)
        c.vline(11, 15 + u, 20 + u, M2)
    if t >= 2:
        c.rect(13, top - 1, 17, top - 1, M2)
        c.set(15, top - 2, p.a)
    # The big mechanical arm and its blade, longer and brighter each tier.
    r = -pose.get("recoil", 0)
    c.rect(17 + r, 14 + u, 20 + r, 19 + u, M1)
    c.hline(17 + r, 20 + r, 14 + u, M2)
    c.vline(20 + r, 15 + u, 19 + u, M0)
    length = (4, 6, 8)[t]
    blade = p.l if t == 0 else (p.a if t == 1 else p.ah)
    if "dim" in flags:
        blade = M1
    x0, y0 = 21 + r, 18 + u
    line(c, x0, y0, x0 + length, y0 - length // 2, blade)
    line(c, x0, y0 + 1, x0 + length - 1, y0 + 1 - length // 2, M2)
    return x0 + length, y0 - length // 2


def trooper(c, t, pose, p):
    bob, flags = pose.get("bob", 0), pose["flags"]
    u = -bob
    # Exo-frame rails up the legs and a power pack.
    top = humanoid(c, p, bob, p.d, p.m, p.l)
    c.rect(9, 14 + u, 11, 20 + u, M1)
    c.hline(9, 11, 14 + u, M2)
    if t >= 1:
        for x0 in (12, 15):
            c.vline(x0, 22, GROUND - 2, M2)
    # Full helmet with a visor band.
    c.rect(12, top - 1, 18, top + 3, p.l)
    c.hline(15, 18, top + 2, p.a if "dim" not in flags else M0)
    # Shoulder pads.
    if t >= 1:
        c.rect(11, 13 + u, 15, 15 + u, M1)
        c.hline(11, 15, 13 + u, M2)
    if t >= 2:
        c.rect(10, 12 + u, 16, 13 + u, M2)
        c.set(10, 14 + u, p.a)
    # Energy rifle with a glowing coil.
    r = -pose.get("recoil", 0)
    tip = (23, 25, 26)[t] + r
    y = 18 + u
    if "off" not in flags:
        c.rect(13 + r, y, tip, y + 1, M0)
        c.hline(13 + r, tip, y, M1)
        coil = 1 + t
        for i in range(coil):
            c.set(19 + r + i * 2, y - 1, p.a if "dim" not in flags else M0)
        if "glow2" in flags and t >= 2:
            c.set(tip, y - 1, p.ah)
        c.rect(16 + r, y, 17 + r, y + 1, SKIN[1])
    return tip, y


# ---------------------------------------------------------------- rival AI
def walker(c, t, pose, p):
    bob, flags = pose.get("bob", 0), pose["flags"]
    # A downed walker folds its legs and drops its chassis.
    drop = 7 if "flat" in flags else (3 if "off" in flags else 0)
    u = -bob + drop
    # Two digitigrade legs: thigh back, shin forward, a claw foot.
    knee = 23 + drop // 2
    for x0 in (11, 18):
        line(c, x0, 18 + drop, x0 - 3 - drop // 2, knee, M1)
        line(c, x0 + 1, 18 + drop, x0 - 2 - drop // 2, knee, M0)
        line(c, x0 - 3 - drop // 2, knee, x0, GROUND - 1, M1)
        c.rect(x0 - 2, GROUND, x0 + 2, GROUND, M2)
    # Angular chassis with one eye.
    c.rect(7, 8 + u, 23, 17 + u, p.m)
    c.hline(8, 23, 8 + u, p.l)
    c.set(7, 8 + u, CLEAR)
    c.rect(7, 17 + u, 23, 17 + u, p.d)
    c.rect(19, 11 + u, 22, 13 + u, O)
    eye = p.a if "dim" not in flags else M0
    c.rect(20, 11 + u, 22, 12 + u, eye)
    if t >= 2 and "dim" not in flags:
        c.set(21, 11 + u, WHITE)
    # Armor plates and an antenna.
    if t >= 1:
        c.rect(8, 10 + u, 13, 15 + u, M1)
        c.hline(8, 13, 10 + u, M2)
    if t >= 2:
        c.vline(10, 3 + u, 7 + u, M2)
        c.set(10, 2 + u, p.a if "dim" not in flags else M0)
        c.rect(14, 6 + u, 18, 7 + u, M1)
    # Gun pod under the chassis; it droops when the walker is down.
    r = -pose.get("recoil", 0)
    tip = (26, 28, 30)[t] + r
    y = 15 + u
    if "off" in flags:
        line(c, 20, y, tip - 2, min(GROUND, y + 4), M0)
    else:
        c.rect(20 + r, y, tip, y + (0 if t == 0 else 1), M0)
        c.hline(20 + r, tip, y, M2)
    return tip, y


SHARD_SPOTS = [(8, 9), (22, 7), (6, 20), (24, 21), (15, 4), (11, 24), (21, 14)]


def splinter(c, t, pose, p):
    """The rogue splinter AI: a cracked core with shards in orbit. Floats."""
    bob, flags = pose.get("bob", 0), pose["flags"]
    flat = "flat" in flags
    u = -bob
    cx, cy = 15, (14 if not flat else 24) + u
    size = (4, 5, 6)[t]
    # Diamond core.
    for dy in range(-size, size + 1):
        w = size - abs(dy)
        c.hline(cx - w, cx + w, cy + dy, p.m if dy > 0 else p.l)
    c.hline(cx - size, cx + size, cy, p.d)
    # Glitch crack, brighter each tier.
    crack = GLITCH if "dim" not in flags else M0
    line(c, cx - 1, cy - size + 1, cx + 1, cy + size - 1, crack)
    if t >= 1:
        c.set(cx + 2, cy - 1, crack)
    if t >= 2 and "dim" not in flags:
        c.set(cx, cy, WHITE)
        c.set(cx - 2, cy + 1, WHITE)
    # Shards: more each tier; they jitter on the idle frames.
    jitter = 1 if "glow2" in flags else 0
    for i, (sx, sy) in enumerate(SHARD_SPOTS[:3 + 2 * t]):
        if flat:
            sx, sy = sx, GROUND - (i % 2)
        else:
            sy += (jitter if i % 2 else -jitter) + u
        c.rect(sx, sy, sx + 1, sy + 1, p.m)
        c.set(sx, sy, p.l)
        if t >= 1 and not flat:
            c.set(sx + 1, sy + 1, GLITCH if "dim" not in flags else M0)
    r = -pose.get("recoil", 0)
    return cx + size + 2 + r, cy


# ---------------------------------------------------------------- aliens
def stalker(c, t, pose, p):
    bob, flags = pose.get("bob", 0), pose["flags"]
    # A downed stalker sprawls: the body drops and the legs splay out.
    drop = 6 if "flat" in flags else (3 if "off" in flags else 0)
    u = -bob + drop
    for x0, lean in ((8, -2), (12, -1), (17, 1), (21, 2)):
        splay = lean * (1 + drop // 2)
        line(c, x0, 21 + drop, x0 + splay, GROUND, p.d)
        c.set(x0 + splay + (1 if lean > 0 else -1), GROUND, p.d)
    # Long hunched body and a forward head.
    c.ellipse(15, 18 + u, 8, 4, p.m)
    c.ellipse(14, 17 + u, 6, 2, p.l)
    c.ellipse(24, 16 + u, 3, 3, p.m)
    c.hline(22, 26, 18 + u, p.d)
    eyes = 2 + t
    for i in range(eyes):
        c.set(24 + (i % 2), 14 + u + i, p.a if "dim" not in flags else M0)
    # Tail spikes.
    c.set(6, 15 + u, p.l)
    c.set(5, 14 + u, p.l)
    c.set(4, 13 + u, p.d)
    # Carapace plates, then glowing spines.
    if t >= 1:
        for x in (10, 14, 18):
            c.rect(x, 14 + u, x + 2, 15 + u, p.d)
    if t >= 2:
        for x in (11, 15, 19):
            c.set(x, 13 + u, p.a if "dim" not in flags else M0)
            c.set(x, 12 + u, p.ah if "dim" not in flags else M0)
    # Scythe forelimb, raised; reach grows per tier. It falls slack when down.
    r = -pose.get("recoil", 0)
    reach = (4, 5, 7)[t]
    sx, sy = 21 + r, 14 + u
    if "off" in flags:
        line(c, sx, sy + 2, sx + reach, min(GROUND, sy + 5), p.d)
        return sx + reach, sy + 5
    line(c, sx, sy, sx + 2, sy - 4, p.d)
    line(c, sx + 2, sy - 4, sx + 2 + reach, sy - 1, p.l if t < 2 else p.ah)
    return sx + 2 + reach, sy - 1


def spitter(c, t, pose, p):
    bob, flags = pose.get("bob", 0), pose["flags"]
    flat = "flat" in flags
    u = -bob
    # Tentacles.
    for x0 in (11, 15, 19):
        if flat:
            c.hline(x0 - 2, x0 + 2, GROUND, p.d)
        else:
            line(c, x0, 21, x0 - 1, 25, p.d)
            line(c, x0 - 1, 25, x0, GROUND, p.d)
    # Bulbous sac with a glowing acid core that grows per tier.
    ry = 6 if not flat else 3
    cy = (14 if not flat else 25) + u
    c.ellipse(15, cy, 7, ry, p.m)
    c.ellipse(13, cy - 2, 4, max(1, ry - 3), p.l)
    core = (1, 2, 3)[t]
    glow = p.a if "dim" not in flags else M0
    if not flat:
        c.ellipse(15, cy + 1, core, core, glow)
        if t >= 2 and "dim" not in flags:
            c.set(15, cy + 1, p.ah)
            if "glow2" in flags:
                c.set(14, cy, p.ah)
    # Spines on the sac.
    if t >= 1:
        for x in (11, 15, 19):
            c.set(x, cy - ry - 1, p.d)
    if t >= 2:
        for x in (13, 17):
            c.set(x, cy - ry - 1, p.d)
            c.set(x, cy - ry - 2, p.a if "dim" not in flags else M0)
    # Spout.
    r = -pose.get("recoil", 0)
    tip = (24, 25, 26)[t] + r
    c.rect(21 + r, cy, tip, cy + 1, p.d)
    c.set(tip, cy, glow)
    return tip, cy


# ---------------------------------------------------------------- units
# Unit id -> (faction, draw function, down style, attack effect).
UNITS = {
    "resistance_soldier": ("human_resistance", soldier, "topple", "muzzle"),
    "resistance_tank": ("human_resistance", tank, "sink", "muzzle"),
    "resistance_mech": ("human_resistance", pilot_mech, "topple", "muzzle"),
    "enhanced_cyborg": ("enhanced_humans", cyborg, "topple", "slash"),
    "enhanced_trooper": ("enhanced_humans", trooper, "topple", "beam"),
    "rival_walker": ("rival_ai", walker, "sink", "muzzle"),
    "splinter_swarm": ("rival_ai", splinter, "sink", "shards"),
    "alien_stalker": ("aliens", stalker, "sink", "slash"),
    "alien_spitter": ("aliens", spitter, "sink", "glob"),
}


def guard_overlay(c, p, tip_y, shimmer):
    x = 27
    c.vline(x, 9, 26, p.l)
    c.vline(x + 1, 11, 24, p.a)
    if shimmer:
        c.set(x, 13, WHITE)
        c.set(x, 21, WHITE)


def attack_effect(c, kind, x, y, p):
    """Drawn on the left-facing sprite at the weapon tip (x, y)."""
    if kind == "muzzle":
        for px, py in ((x, y), (x - 1, y), (x - 2, y), (x - 1, y - 1), (x - 1, y + 1)):
            c.set(px, py, SPARK)
        c.set(x - 3, y, WHITE)
    elif kind == "beam":
        c.hline(max(0, x - 8), x, y, p.a)
        c.set(x, y, WHITE)
    elif kind == "glob":
        c.rect(x - 3, y - 1, x - 1, y + 1, p.a)
        c.set(x - 2, y, p.ah)
    elif kind == "shards":
        for px, py in ((x - 2, y - 3), (x - 4, y), (x - 2, y + 3)):
            c.rect(px, py, px + 1, py + 1, GLITCH)
    else:  # slash: an arc in front of the claw or blade
        for i in range(6):
            c.set(x - 1 - i // 2, y - 3 + i, p.ah if i % 2 else p.a)


def unit_frame(unit, tier, motion):
    faction, draw, down_style, effect = UNITS[unit]
    p = Pal(faction)
    flags = set(motion.get("flags", set()))
    pose = dict(bob=motion.get("bob", 0), recoil=motion.get("recoil", 0), flags=flags)
    c = Canvas(*FRAME)
    tip_x, tip_y = draw(c, tier, pose, p)
    if "charge" in flags:
        c.set(tip_x, tip_y, WHITE)
        c.set(tip_x + 1, tip_y, p.a)
        c.set(tip_x, tip_y - 1, p.a)
    if "dim" in flags:
        c.replace(p.ah, M1)
    c.outline()
    if "guard" in flags:
        guard_overlay(c, p, tip_y, "shimmer" in flags)
    fall = motion.get("fall")
    if fall is not None and down_style == "topple" and fall > 0:
        c = to_ground(rotated(c, TOPPLE[fall], 15, GROUND), 15)
    elif fall is not None and down_style == "sink":
        c = c.shifted(0, (0, 1, 1, 2)[fall])
    dx, dy = motion["d"]
    c = c.flipped().shifted(dx, dy)
    if "flash" in flags:
        attack_effect(c, effect, FRAME[0] - 1 - tip_x + dx, tip_y + dy, p)
    for name, points in HEAL_SPARKLES.items():
        if name in flags:
            for x, y in points:
                sparkle(c, x, y)
    return c


# Faction id -> the unit whose medium idle frame is the faction's icon (the
# territory panel shows it).
FACTION_ICONS = {
    "human_resistance": "resistance_soldier",
    "enhanced_humans": "enhanced_cyborg",
    "rival_ai": "rival_walker",
    "aliens": "alien_stalker",
}


def gen_icons():
    written = []
    for faction, unit in FACTION_ICONS.items():
        frame = unit_frame(unit, 1, MOTION["idle"][0])
        img = Image.new("RGBA", FRAME, CLEAR)
        frame.paste_onto(img, 0, 0)
        written.append(save(img, f"res://assets/enemies/{faction}/icon_{faction}.png"))
    return written


def gen_enemies():
    written = []
    for unit in UNITS:
        spec = MANIFEST["units"].get(unit)
        if spec is None:
            raise SystemExit(f"{unit} is missing from data/feel/sprite_manifest.json")
        for tier_name, res in spec["sheets"].items():
            t = TIER_LEVEL[tier_name]
            sheet = build_sheet(lambda anim, i, u=unit, t=t: unit_frame(u, t, MOTION[anim][i]))
            written.append(save(sheet, res))
    return written


def main():
    written = gen_enemies() + gen_icons()
    for path in written:
        print(os.path.relpath(path, ROOT))
    print(f"{len(written)} files", file=sys.stderr)


if __name__ == "__main__":
    main()
