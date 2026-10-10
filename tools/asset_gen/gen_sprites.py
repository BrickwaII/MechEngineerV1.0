#!/usr/bin/env python3
"""Generates the placeholder pixel art in assets/sprites and assets/ui.

Every color comes from data/feel/palette.json and the sheet layout from
data/feel/sprite_manifest.json, so the art follows the data. The output is our
own work, dedicated to the public domain (CC0), see CREDITS.md.

Usage (from the repo root): python3 tools/asset_gen/gen_sprites.py
Needs Pillow.
"""
import json
import os
import sys

from PIL import Image

ROOT = os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
PALETTE = json.load(open(os.path.join(ROOT, "data/feel/palette.json")))
MANIFEST = json.load(open(os.path.join(ROOT, "data/feel/sprite_manifest.json")))


def rgba(hex_color, alpha=255):
    h = hex_color.lstrip("#")
    return (int(h[0:2], 16), int(h[2:4], 16), int(h[4:6], 16), alpha)


def pal(name):
    return rgba(PALETTE[name])


def res_to_path(res):
    return os.path.join(ROOT, res.replace("res://", ""))


# Shorthand colors. Ally parts use key colors that the palette swap shader
# replaces; outline and metal stay fixed.
P0, P1, P2 = pal("key_primary_dark"), pal("key_primary"), pal("key_primary_light")
S0, S1, S2 = pal("key_secondary_dark"), pal("key_secondary"), pal("key_secondary_light")
G = pal("key_glow")
O = pal("sprite_outline")
M0, M1, M2 = pal("sprite_metal_dark"), pal("sprite_metal"), pal("sprite_metal_light")
HEAL = pal("sprite_heal")
SPARK = pal("sprite_spark")
WHITE = (255, 255, 255, 255)
CLEAR = (0, 0, 0, 0)


class Canvas:
    """A small RGBA pixel grid with clipped drawing."""

    def __init__(self, w, h):
        self.w, self.h = w, h
        self.px = [[CLEAR] * w for _ in range(h)]

    def set(self, x, y, c):
        if 0 <= x < self.w and 0 <= y < self.h:
            self.px[y][x] = c

    def get(self, x, y):
        if 0 <= x < self.w and 0 <= y < self.h:
            return self.px[y][x]
        return CLEAR

    def rect(self, x0, y0, x1, y1, c):
        """Filled rectangle, inclusive corners."""
        for y in range(y0, y1 + 1):
            for x in range(x0, x1 + 1):
                self.set(x, y, c)

    def hline(self, x0, x1, y, c):
        self.rect(x0, y, x1, y, c)

    def vline(self, x, y0, y1, c):
        self.rect(x, y0, x, y1, c)

    def ellipse(self, cx, cy, rx, ry, c):
        for y in range(cy - ry, cy + ry + 1):
            for x in range(cx - rx, cx + rx + 1):
                dx = (x - cx) / (rx + 0.5)
                dy = (y - cy) / (ry + 0.5)
                if dx * dx + dy * dy <= 1.0:
                    self.set(x, y, c)

    def replace(self, old, new):
        for y in range(self.h):
            for x in range(self.w):
                if self.px[y][x] == old:
                    self.px[y][x] = new

    def outline(self, c=O):
        """Adds a 1 px outline around every opaque pixel (4-neighbourhood)."""
        add = []
        for y in range(self.h):
            for x in range(self.w):
                if self.px[y][x][3] != 0:
                    continue
                for nx, ny in ((x + 1, y), (x - 1, y), (x, y + 1), (x, y - 1)):
                    p = self.get(nx, ny)
                    if p[3] != 0 and p != c:
                        add.append((x, y))
                        break
        for x, y in add:
            self.px[y][x] = c

    def shifted(self, dx, dy):
        out = Canvas(self.w, self.h)
        for y in range(self.h):
            for x in range(self.w):
                if self.px[y][x][3]:
                    out.set(x + dx, y + dy, self.px[y][x])
        return out

    def flipped(self):
        out = Canvas(self.w, self.h)
        for y in range(self.h):
            out.px[y] = list(reversed(self.px[y]))
        return out

    def paste_onto(self, sheet, ox, oy):
        for y in range(self.h):
            for x in range(self.w):
                if self.px[y][x][3]:
                    sheet.putpixel((ox + x, oy + y), self.px[y][x])


def save(img, res_or_rel):
    path = res_to_path(res_or_rel) if res_or_rel.startswith("res://") else os.path.join(ROOT, res_or_rel)
    os.makedirs(os.path.dirname(path), exist_ok=True)
    img.save(path)
    return path


# ---------------------------------------------------------------- animation
# Per animation: one entry per frame. "upper" moves body, head and arm;
# "arm" adds to the arm; "legs" moves the legs. Flags add details.
FRAME = tuple(MANIFEST["frame_size"])
ANIMS = MANIFEST["animations"]
ROWS = max(a["row"] for a in ANIMS.values()) + 1
COLS = max(a["frames"] for a in ANIMS.values())

ALLY_MOTION = {
    "idle": [dict(upper=(0, 0)), dict(upper=(0, 1)), dict(upper=(0, 1)), dict(upper=(0, 0))],
    "windup": [dict(upper=(-1, 0), arm=(-1, -1)), dict(upper=(-2, 0), arm=(-1, -2)),
               dict(upper=(-2, 0), arm=(-1, -3), flags={"charge"})],
    "attack": [dict(upper=(2, 0), arm=(1, 0), flags={"flash"}), dict(upper=(3, 0), arm=(1, 0), flags={"flash"}),
               dict(upper=(2, 0)), dict(upper=(0, 0))],
    "hit": [dict(upper=(-2, 0), legs=(-1, 0), flags={"hurt"}), dict(upper=(-1, 0)), dict(upper=(0, 0))],
    "guard": [dict(upper=(-1, 0), flags={"guard"}), dict(upper=(-1, 1), flags={"guard", "shimmer"})],
    "heal": [dict(upper=(0, 0), flags={"heal0"}), dict(upper=(0, -1), flags={"heal1"}),
             dict(upper=(0, -1), flags={"heal2"}), dict(upper=(0, 0), flags={"heal3"})],
    "down": [dict(upper=(0, 1)), dict(upper=(-1, 3), flags={"dim"}), dict(upper=(-2, 6), flags={"dim"}),
             dict(upper=(-2, 8), legs=(0, 1), flags={"dim", "off"})],
}

HEAL_SPARKLES = {
    "heal0": [(7, 20), (25, 22)],
    "heal1": [(6, 15), (26, 17), (16, 2)],
    "heal2": [(8, 10), (24, 11), (12, 1)],
    "heal3": [(9, 5), (23, 6)],
}


def sparkle(c, x, y, color=HEAL):
    c.set(x, y, color)
    c.set(x - 1, y, color)
    c.set(x + 1, y, color)
    c.set(x, y - 1, color)
    c.set(x, y + 1, color)


# ---------------------------------------------------------------- ally parts
TIER_LEVEL = {"beginner": 0, "medium": 1, "advanced": 2}


def legs_biped(c, t):
    w = 3 if t < 2 else 4
    for x0 in (11, 17):
        c.rect(x0, 23, x0 + w - 1, 29, M1)
        c.vline(x0 + w - 1, 23, 29, M0)
        c.rect(x0 - 1, 30, x0 + w + 1, 31, P0)
        c.hline(x0 - 1, x0 + w, 30, P1)
        if t >= 1:
            c.rect(x0, 25, x0 + w - 1, 26, S1)
            c.hline(x0, x0 + w - 1, 25, S2)
        if t >= 2:
            c.set(x0 + 1, 28, G)
    c.rect(11, 22, 21, 23, M0)


def legs_treads(c, t):
    c.rect(9, 26, 23, 31, M0)
    c.hline(10, 22, 26, M1)
    for x in range(11, 23, 3):
        c.rect(x, 28, x + 1, 29, M2)
    c.set(9, 26, CLEAR)
    c.set(23, 26, CLEAR)
    c.set(9, 31, CLEAR)
    c.set(23, 31, CLEAR)
    c.rect(11, 23, 21, 25, P0)
    c.hline(11, 21, 23, P1)
    if t >= 1:
        c.rect(8, 24, 24, 25, S1)
        c.hline(8, 24, 24, S2)
    if t >= 2:
        c.hline(10, 22, 30, G)


def body_box(c, t):
    c.rect(10, 13, 21, 23, P1)
    c.hline(10, 21, 13, P2)
    c.vline(21, 14, 23, P0)
    c.hline(10, 21, 23, P0)
    c.rect(13, 16, 17, 20, M1)
    c.hline(13, 17, 16, M2)
    if t >= 1:
        c.rect(8, 12, 12, 15, S1)
        c.hline(8, 12, 12, S2)
        c.hline(8, 12, 15, S0)
    if t >= 2:
        c.rect(14, 17, 16, 19, G)
        c.rect(20, 12, 23, 15, S1)
        c.hline(20, 23, 12, S2)


def body_round(c, t):
    c.ellipse(16, 18, 6, 5, P1)
    c.ellipse(15, 17, 4, 3, P2)
    c.ellipse(16, 18, 3, 2, P1)
    c.hline(12, 20, 23, P0)
    c.rect(14, 17, 17, 19, M1)
    if t >= 1:
        c.ellipse(10, 15, 2, 2, S1)
        c.set(9, 14, S2)
    if t >= 2:
        c.rect(15, 18, 16, 18, G)
        c.ellipse(22, 15, 2, 2, S1)
        c.set(21, 14, S2)
        c.hline(11, 21, 22, S0)


def head_visor(c, t):
    c.rect(12, 5, 20, 12, P1)
    c.hline(12, 20, 5, P2)
    c.vline(12, 6, 12, P2)
    c.hline(12, 20, 12, P0)
    c.rect(15, 8, 20, 9, M0)
    c.hline(16, 20, 8, G)
    c.rect(14, 12, 18, 13, M0)
    if t >= 1:
        c.rect(13, 3, 17, 4, S1)
        c.hline(13, 17, 3, S2)
    if t >= 2:
        c.vline(13, 0, 3, M2)
        c.set(13, 0, G)
        c.rect(12, 10, 13, 11, S1)


def head_dome(c, t):
    c.ellipse(16, 9, 4, 4, P1)
    c.ellipse(15, 8, 2, 2, P2)
    c.hline(13, 19, 12, P0)
    c.rect(17, 8, 19, 9, M0)
    c.rect(18, 8, 19, 9, G)
    c.rect(14, 12, 18, 13, M0)
    if t >= 1:
        c.hline(12, 20, 10, S1)
        c.set(12, 10, S0)
        c.set(20, 10, S0)
    if t >= 2:
        c.vline(16, 1, 4, M2)
        c.set(16, 1, G)
        c.set(15, 2, G)
        c.set(17, 2, G)


def arm_blaster(c, t):
    length = (5, 7, 8)[t]
    c.rect(15, 15, 17, 19, M1)
    c.vline(17, 15, 19, M0)
    c.rect(15, 14, 17, 15, P2)
    c.rect(17, 18, 18 + length, 19, M1)
    c.hline(17, 18 + length, 18, M2)
    if t >= 1:
        c.rect(18, 17, 21, 20, S1)
        c.hline(18, 21, 17, S2)
    if t >= 2:
        c.rect(19, 21, 18 + length, 21, M1)
        c.set(18 + length, 21, G)
    c.set(18 + length, 18, G)


def arm_claw(c, t):
    reach = (4, 5, 6)[t]
    c.rect(15, 15, 17, 19, M1)
    c.vline(17, 15, 19, M0)
    c.rect(15, 14, 17, 15, P2)
    c.rect(17, 18, 17 + reach, 19, M1)
    tip = 17 + reach
    c.rect(tip, 16, tip + 2, 16, M2)
    c.rect(tip, 21, tip + 2, 21, M2)
    c.vline(tip, 16, 21, M1)
    c.set(tip + 3, 17, M2)
    c.set(tip + 3, 20, M2)
    if t >= 1:
        c.rect(18, 17, 20, 20, S1)
    if t >= 2:
        c.set(tip + 1, 18, G)
        c.set(tip + 1, 19, G)


def weapon_tip(variant, tier):
    """The x of the arm's front pixel, where flashes and charge glow sit."""
    if variant == "blaster":
        return 18 + (5, 7, 8)[tier]
    return 20 + (4, 5, 6)[tier]


PART_DRAW = {
    "legs": {"biped": legs_biped, "treads": legs_treads},
    "body": {"box": body_box, "round": body_round},
    "head": {"visor": head_visor, "dome": head_dome},
    "arm": {"blaster": arm_blaster, "claw": arm_claw},
}


def ally_part_frame(part, variant, tier, motion):
    c = Canvas(*FRAME)
    PART_DRAW[part][variant](c, tier)
    flags = motion.get("flags", set())
    tip = weapon_tip(variant, tier) if part == "arm" else 0
    if part == "arm":
        if "charge" in flags:
            c.set(tip + 1, 17, G)
            c.set(tip + 2, 18, G)
        if "guard" in flags:
            c.rect(22, 11, 24, 23, S1)
            c.vline(22, 11, 23, S2)
            c.vline(24, 11, 23, S0)
            if "shimmer" in flags:
                c.set(23, 14, G)
                c.set(23, 19, G)
    if "dim" in flags:
        c.replace(G, M0)
    if "off" in flags and part in ("head", "body"):
        c.replace(P2, P1)
    c.outline()
    dx, dy = 0, 0
    if part == "legs":
        dx, dy = motion.get("legs", (0, 0))
    else:
        dx, dy = motion.get("upper", (0, 0))
        if part == "arm":
            ax, ay = motion.get("arm", (0, 0))
            dx, dy = dx + ax, dy + ay
    c = c.shifted(dx, dy)
    # Effects that sit on top of the whole bot go on the top layer, unshifted.
    if part == "arm":
        if "flash" in flags:
            x = tip + 2 + dx
            for px, py in ((x, 18 + dy), (x + 1, 17 + dy), (x + 1, 19 + dy), (x + 2, 18 + dy), (x + 1, 18 + dy)):
                c.set(px, py, SPARK)
        for name, points in HEAL_SPARKLES.items():
            if name in flags:
                for x, y in points:
                    sparkle(c, x, y)
    return c


def build_sheet(frame_fn):
    sheet = Image.new("RGBA", (FRAME[0] * COLS, FRAME[1] * ROWS), CLEAR)
    for anim, spec in ANIMS.items():
        for i in range(spec["frames"]):
            frame_fn(anim, i).paste_onto(sheet, i * FRAME[0], spec["row"] * FRAME[1])
    return sheet


def gen_ally():
    unit = MANIFEST["units"]["ally_frame"]
    written = []
    for part, variants in unit["parts"].items():
        for variant, tiers in variants.items():
            if variant not in PART_DRAW[part]:
                continue  # drawn by gen_battle.py (assets/fight/)
            for tier_name, res in tiers.items():
                t = TIER_LEVEL[tier_name]

                def frame(anim, i, part=part, variant=variant, t=t):
                    return ally_part_frame(part, variant, t, ALLY_MOTION[anim][i])

                written.append(save(build_sheet(frame), res))
    return written


# ---------------------------------------------------------------- enemy drone
E0, E1, E2 = rgba("#7a2a2a"), rgba("#c9473f"), pal("enemy")
EYE = pal("preview")
THRUST = pal("energy")

DRONE_MOTION = {
    "idle": [dict(d=(0, 0)), dict(d=(0, -1), flags={"thrust2"}), dict(d=(0, -1)), dict(d=(0, 0), flags={"thrust2"})],
    "windup": [dict(d=(1, 0)), dict(d=(2, -1)), dict(d=(2, -1), flags={"charge"})],
    "attack": [dict(d=(-3, 0), flags={"flash"}), dict(d=(-4, 0), flags={"flash"}), dict(d=(-2, 0)), dict(d=(0, 0))],
    "hit": [dict(d=(2, 0), flags={"hurt"}), dict(d=(1, 0)), dict(d=(0, 0))],
    "guard": [dict(d=(1, 0), flags={"guard"}), dict(d=(1, 1), flags={"guard", "shimmer"})],
    "heal": [dict(d=(0, 0), flags={"heal0"}), dict(d=(0, -1), flags={"heal1"}),
             dict(d=(0, -1), flags={"heal2"}), dict(d=(0, 0), flags={"heal3"})],
    "down": [dict(d=(0, 2), flags={"dim"}), dict(d=(1, 5), flags={"dim", "off"}),
             dict(d=(2, 8), flags={"dim", "off"}), dict(d=(2, 10), flags={"dim", "off", "flat"})],
}


def drone_frame(tier, motion):
    """Drawn facing right, then flipped so the drone faces left."""
    flags = motion.get("flags", set())
    c = Canvas(*FRAME)
    rx = (6, 7, 8)[tier]
    cx, cy = 15, 15
    if "flat" in flags:
        c.ellipse(cx, cy + 2, rx, 3, E1)
        c.hline(cx - rx, cx + rx, cy + 4, E0)
    else:
        c.ellipse(cx, cy, rx, 5, E1)
        c.ellipse(cx - 1, cy - 2, rx - 2, 2, E2)
        c.hline(cx - rx + 1, cx + rx - 1, cy + 4, E0)
        c.hline(cx - rx + 2, cx + rx - 2, cy + 5, E0)
    eye_x = cx + rx - 4
    c.rect(eye_x, cy - 1, eye_x + 2, cy + 1, O)
    c.rect(eye_x + 1, cy - 1, eye_x + 2, cy, EYE if "dim" not in flags else M0)
    if "charge" in flags:
        c.rect(eye_x, cy - 1, eye_x + 2, cy, WHITE)
    if tier >= 1:
        for y0 in (cy - 6, cy + 3):
            c.rect(cx - rx - 2, y0, cx - rx + 2, y0 + 3, M1)
            c.hline(cx - rx - 2, cx - rx + 2, y0, M2)
        c.rect(cx + 1, cy + 6, cx + 6, cy + 7, M1)
        c.set(cx + 6, cy + 7, M2)
    if tier >= 2:
        for x in (cx - 3, cx, cx + 3):
            c.set(x, cy - 6, E2)
            c.set(x, cy - 7, M2)
        c.rect(cx + 1, cy - 8, cx + 8, cy - 7, M1)
        c.set(cx + 8, cy - 8, EYE)
        c.hline(cx - rx + 2, cx + rx - 2, cy + 1, rgba("#ff9a8f"))
    if "off" not in flags and "flat" not in flags:
        flame = 2 if "thrust2" in flags else 1
        c.rect(cx - 2, cy + 6, cx, cy + 6 + flame, THRUST)
        c.set(cx - 1, cy + 7 + flame, WHITE)
    c.outline()
    if "guard" in flags:
        x = cx + rx + 3
        c.vline(x, cy - 7, cy + 7, rgba("#ff9a8f"))
        c.vline(x + 1, cy - 5, cy + 5, E2)
        if "shimmer" in flags:
            c.set(x, cy - 2, WHITE)
            c.set(x, cy + 3, WHITE)
    dx, dy = motion["d"]
    # Motion is authored for a left-facing unit; flip first, then move.
    c = c.flipped().shifted(dx, dy)
    if "flash" in flags:
        x, y = 3 + dx, 22 + dy
        for px, py in ((x, y), (x - 1, y), (x, y - 1), (x, y + 1), (x + 1, y)):
            c.set(px, py, SPARK)
    for name, points in HEAL_SPARKLES.items():
        if name in flags:
            for x, y in points:
                sparkle(c, x, y)
    return c


def gen_enemy():
    unit = MANIFEST["units"]["enemy_drone"]
    written = []
    for tier_name, res in unit["sheets"].items():
        t = TIER_LEVEL[tier_name]
        written.append(save(build_sheet(lambda anim, i, t=t: drone_frame(t, DRONE_MOTION[anim][i])), res))
    return written


# ---------------------------------------------------------------- effects
def effect_sheet(spec, frames):
    w, h = spec["frame_size"]
    img = Image.new("RGBA", (w * spec["frames"], h), CLEAR)
    for i, c in enumerate(frames):
        c.paste_onto(img, i * w, 0)
    return img


def fx_hit_spark():
    out = []
    for i, r in enumerate((2, 4, 6, 7)):
        c = Canvas(16, 16)
        col = WHITE if i < 2 else SPARK
        for k in range(1, r + 1):
            if i == 3 and k < 4:
                continue
            for dx, dy in ((1, 0), (-1, 0), (0, 1), (0, -1)):
                c.set(8 + dx * k, 8 + dy * k, col)
            if k <= r - 2:
                for dx, dy in ((1, 1), (-1, -1), (1, -1), (-1, 1)):
                    c.set(8 + dx * k, 8 + dy * k, SPARK)
        if i < 2:
            c.rect(7, 7, 9, 9, WHITE)
        out.append(c)
    return out


def fx_heal_plus():
    out = []
    for i in range(4):
        c = Canvas(16, 16)
        y = 9 - i * 2
        col = HEAL if i < 3 else rgba(PALETTE["sprite_heal"], 140)
        c.rect(7, y - 3, 8, y + 2, col)
        c.rect(5, y - 1, 10, y, col)
        c.outline(rgba("#0f3a1e"))
        out.append(c)
    return out


def fx_energy_spark():
    out = []
    bolts = [
        [(8, 2), (7, 3), (7, 4), (6, 5), (6, 6), (7, 7), (8, 7), (9, 7), (9, 8), (8, 9), (8, 10), (7, 11), (7, 12)],
    ]
    for i in range(4):
        c = Canvas(16, 16)
        col = WHITE if i == 1 else THRUST
        for x, y in bolts[0]:
            c.set(x + (i % 2), y, col)
        if i >= 2:
            c.set(3, 4 + i, THRUST)
            c.set(12, 10 - i, THRUST)
        out.append(c)
    return out


def fx_muzzle_flash():
    out = []
    for i, r in enumerate((3, 5, 2)):
        c = Canvas(16, 16)
        c.ellipse(4 + r, 8, r, max(1, r // 2), SPARK)
        c.ellipse(3 + r // 2, 8, max(1, r // 2), max(0, r // 3), WHITE)
        out.append(c)
    return out


def fx_shield_shimmer():
    out = []
    for i in range(4):
        c = Canvas(32, 32)
        col = pal("selected")
        for y in range(4, 28):
            x = 22 + int(((y - 16) / 12.0) ** 2 * 4)
            c.set(x, y, col)
        y_hi = 6 + i * 6
        for y in range(y_hi, min(28, y_hi + 3)):
            x = 22 + int(((y - 16) / 12.0) ** 2 * 4)
            c.set(x, y, WHITE)
            c.set(x - 1, y, col)
        out.append(c)
    return out


def fx_down_burst():
    out = []
    for i in range(6):
        c = Canvas(32, 32)
        r = 3 + i * 2
        if i < 4:
            c.ellipse(16, 16, r, r, SPARK if i < 2 else pal("danger"))
            c.ellipse(16, 16, max(0, r - 3), max(0, r - 3), WHITE if i < 2 else SPARK)
        else:
            for k in range(8):
                import math
                a = k * math.pi / 4 + i * 0.2
                c.set(int(16 + math.cos(a) * r), int(16 + math.sin(a) * r), M1)
                c.set(int(16 + math.cos(a) * (r - 2)), int(16 + math.sin(a) * (r - 2)), M2)
        out.append(c)
    return out


def gen_effects():
    makers = {
        "hit_spark": fx_hit_spark, "heal_plus": fx_heal_plus, "energy_spark": fx_energy_spark,
        "muzzle_flash": fx_muzzle_flash, "shield_shimmer": fx_shield_shimmer, "down_burst": fx_down_burst,
    }
    written = []
    for name, spec in MANIFEST["effects"].items():
        frames = makers[name]()
        assert len(frames) == spec["frames"], name
        written.append(save(effect_sheet(spec, frames), spec["sheet"]))
    # Particle textures: white so a particle system can tint them.
    for name, pattern in {
        "dot_2": ["##", "##"],
        "square_3": ["###", "###", "###"],
        "spark_5": ["..#..", "..#..", "#####", "..#..", "..#.."],
        "ring_7": ["..###..", ".#...#.", "#.....#", "#.....#", "#.....#", ".#...#.", "..###.."],
    }.items():
        img = Image.new("RGBA", (len(pattern[0]), len(pattern)), CLEAR)
        for y, row in enumerate(pattern):
            for x, ch in enumerate(row):
                if ch == "#":
                    img.putpixel((x, y), WHITE)
        written.append(save(img, f"assets/sprites/particles/{name}.png"))
    return written


# ---------------------------------------------------------------- interface
def nine_slice(fill, border, light, shadow, size=12, inset_shift=0):
    """A 12x12 bevelled pixel box; the theme slices it 4 px from each edge."""
    c = Canvas(size, size)
    c.rect(1, 1, size - 2, size - 2, fill)
    c.hline(1, size - 2, 0, border)
    c.hline(1, size - 2, size - 1, border)
    c.vline(0, 1, size - 2, border)
    c.vline(size - 1, 1, size - 2, border)
    if light:
        c.hline(1, size - 2, 1 + inset_shift, light)
        c.vline(1, 1 + inset_shift, size - 2, light)
    if shadow:
        c.hline(1, size - 2, size - 2, shadow)
        c.vline(size - 2, 1, size - 2, shadow)
    img = Image.new("RGBA", (size, size), CLEAR)
    c.paste_onto(img, 0, 0)
    return img


def x2(img):
    return img.resize((img.width * 2, img.height * 2), Image.NEAREST)


def darker(name, k=0.7):
    r, g, b, a = pal(name)
    return (int(r * k), int(g * k), int(b * k), a)


def icon(rows, colors):
    img = Image.new("RGBA", (len(rows[0]), len(rows)), CLEAR)
    for y, row in enumerate(rows):
        for x, ch in enumerate(row):
            if ch in colors:
                img.putpixel((x, y), colors[ch])
    return img


# Status icons: each has its own shape AND color (never color alone).
# o = outline, a = main color, b = highlight, w = white detail.
STATUS_ICONS = {
    "guard": ("selected", [
        "..oooooooo..",
        ".oaaaaaaaao.",
        ".oabbbbbbao.",
        ".oabaaaaaao.",
        ".oabaaaaaao.",
        ".oaaaaaaaao.",
        ".oaaaaaaaao.",
        "..oaaaaaao..",
        "..oaaaaaao..",
        "...oaaaao...",
        "....oaao....",
        ".....oo.....",
    ]),
    "charging": ("energy", [
        "......ooo...",
        ".....oaao...",
        "....oaao....",
        "...oaao.....",
        "..oaaaaooo..",
        "..oooaaaao..",
        "....oaao....",
        "...oaao.....",
        "..oaao......",
        "..oao.......",
        "..oo........",
        "............",
    ]),
    "waiting": ("text_dim", [
        ".oooooooooo.",
        ".oaaaaaaaao.",
        "..oaaaaaao..",
        "...oabbao...",
        "....oaao....",
        ".....oo.....",
        "....o..o....",
        "...o.bb.o...",
        "..o.bbbb.o..",
        ".obbbbbbbbo.",
        ".oaaaaaaaao.",
        ".oooooooooo.",
    ]),
    "low_energy": ("warning", [
        "............",
        "..........",
        "oooooooooo..",
        "o........ooo",
        "o.aa.....o.o",
        "o.aa.....o.o",
        "o.aa.....o.o",
        "o.aa.....ooo",
        "oooooooooo..",
        "............",
        "....oo......",
        "....oo......",
    ]),
    "down": ("danger", [
        "oo........oo",
        "oaao....oaao",
        "oaaao..oaaao",
        ".oaaaooaaao.",
        "..oaaaaaao..",
        "...oaaaao...",
        "...oaaaao...",
        "..oaaaaaao..",
        ".oaaaooaaao.",
        "oaaao..oaaao",
        "oaao....oaao",
        "oo........oo",
    ]),
    "intent_changed": ("changed", [
        ".....oo.....",
        "....oaao....",
        "...oaaaao...",
        "..oaawwaao..",
        ".oaaawwaaao.",
        "oaaaawwaaaao",
        "oaaaawwaaaao",
        ".oaaaaaaaao.",
        "..oaawwaao..",
        "...oaaaao...",
        "....oaao....",
        ".....oo.....",
    ]),
}


def gen_interface():
    written = []
    fill, raised = pal("panel"), pal("panel_raised")
    border, light = pal("panel_border"), pal("panel_border_light")
    boxes = {
        "panel": nine_slice(fill, border, None, None),
        "panel_raised": nine_slice(raised, border, light, None),
        "button_normal": nine_slice(raised, light, pal("panel_border_light"), darker("panel_raised", 0.6)),
        "button_hover": nine_slice(raised, pal("accent"), pal("accent_hover"), darker("panel_raised", 0.6)),
        "button_pressed": nine_slice(darker("panel_raised", 0.6), pal("accent"), darker("panel_raised", 0.4), None, inset_shift=0),
        "button_disabled": nine_slice(pal("disabled"), pal("rule"), None, None),
        "focus": nine_slice(CLEAR, pal("focus"), None, None),
        "field": nine_slice(pal("bar_back"), border, None, None),
        "tooltip": nine_slice(pal("background"), light, None, None),
    }
    # Interface art is stored at 2x so it sits on the same pixel grid as the
    # font, which the theme draws at 2x (20 px).
    for name, img in boxes.items():
        written.append(save(x2(img), f"assets/ui/{name}.png"))

    a, o, b = pal("accent"), O, pal("accent_hover")
    small = {
        "check_off": icon([
            "oooooooooo", "o........o", "o........o", "o........o", "o........o",
            "o........o", "o........o", "o........o", "o........o", "oooooooooo"],
            {"o": pal("panel_border_light")}),
        "check_on": icon([
            "oooooooooo", "o........o", "o......aao", "o.....aa.o", "oaa..aa..o",
            "o.aaaa...o", "o..aa....o", "o........o", "o........o", "oooooooooo"],
            {"o": a, "a": b}),
        "slider_grabber": icon([
            "oooooo", "oaaaao", "oabbao", "oaaaao", "oabbao", "oaaaao", "oabbao", "oaaaao", "oaaaao", "oooooo"],
            {"o": o, "a": a, "b": b}),
        "slider_grabber_highlight": icon([
            "oooooo", "obbbbo", "obwwbo", "obbbbo", "obwwbo", "obbbbo", "obwwbo", "obbbbo", "obbbbo", "oooooo"],
            {"o": o, "b": b, "w": WHITE}),
        "arrow_down": icon([
            "aaaaaaa", ".aaaaa.", "..aaa..", "...a..."],
            {"a": pal("text")}),
    }
    for name, img in small.items():
        written.append(save(x2(img), f"assets/ui/{name}.png"))

    for name, (color, rows) in STATUS_ICONS.items():
        rows = [r.ljust(12, ".")[:12] for r in rows]
        img = icon(rows, {"o": O, "a": pal(color), "b": rgba("#ffffff", 200), "w": WHITE})
        written.append(save(img, f"assets/ui/icons/status_{name}.png"))
    # Popup icons: a cross for heals, a bolt for energy (shape, not just color).
    written.append(save(icon(["..ooo..", "..oao..", "oooaooo", "oaaaaao", "oooaooo", "..oao..", "..ooo.."],
                             {"o": O, "a": pal("popup_heal")}), "assets/ui/icons/popup_heal.png"))
    written.append(save(icon(["...ooo", "..oao.", ".oao..", "oaaaao", "..oao.", ".oao..", "ooo..."],
                             {"o": O, "a": pal("popup_energy")}), "assets/ui/icons/popup_energy.png"))
    return written


def main():
    written = gen_ally() + gen_enemy() + gen_effects() + gen_interface()
    for path in written:
        print(os.path.relpath(path, ROOT))
    print(f"{len(written)} files", file=sys.stderr)


if __name__ == "__main__":
    main()
