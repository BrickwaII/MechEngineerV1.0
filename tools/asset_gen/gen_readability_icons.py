#!/usr/bin/env python3
"""Generates the battle readability icons in assets/fight/icons/ (R1-B).

- Stat icons for the unit panels: attack, defense, speed, battery.
- The KO mark drawn on an arrow badge when a hit would down its target.

Each icon has its own shape and color, so it reads without color too. Drawn
with the kit of gen_sprites.py; our own work, dedicated to the public domain
(CC0), see CREDITS.md.

Usage (from the repo root): python3 tools/asset_gen/gen_readability_icons.py
Needs Pillow.
"""
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gen_sprites as gs  # noqa: E402
from gen_sprites import O, rgba, save  # noqa: E402

OUT = "assets/fight/icons"

# o = outline, a = main color, b = highlight. 12 x 12 like the intent icons.
ICONS = {
    "stat_attack": ("danger", [
        "........ooo.",
        ".......oaao.",
        "......oaao..",
        ".....oaao...",
        "....oaao....",
        ".o.oaao.....",
        ".ooaao......",
        "..oao.......",
        ".oaooo......",
        "oao..o......",
        "oo..........",
        "............",
    ]),
    "stat_defense": ("selected", [
        "............",
        ".oooooooooo.",
        ".oaaaaaaaao.",
        ".oabbaaaaao.",
        ".oabaaaaaao.",
        ".oaaaaaaaao.",
        "..oaaaaaao..",
        "..oaaaaaao..",
        "...oaaaao...",
        "....oaao....",
        ".....oo.....",
        "............",
    ]),
    "stat_speed": ("warning", [
        "............",
        ".oo...oo....",
        ".oao..oao...",
        "..oao..oao..",
        "...oao..oao.",
        "....oao..oao",
        "...oao..oao.",
        "..oao..oao..",
        ".oao..oao...",
        ".oo...oo....",
        "............",
        "............",
    ]),
    "stat_battery": ("energy", [
        "....oooo....",
        "..oooooooo..",
        "..o......o..",
        "..o......o..",
        "..oaaaaaao..",
        "..oaaaaaao..",
        "..oabaaaao..",
        "..oabaaaao..",
        "..oaaaaaao..",
        "..oaaaaaao..",
        "..oooooooo..",
        "............",
    ]),
    "ko_skull": ("text_bright", [
        "...oooooo...",
        "..oaaaaaao..",
        ".oaaaaaaaao.",
        ".oaooaaooao.",
        ".oaooaaooao.",
        ".oaaaooaaao.",
        "..oaaaaaao..",
        "...oaoaoo...",
        "...oaoaoo...",
        "....oooo....",
        "............",
        "............",
    ]),
}


def main():
    for name, (color, rows) in ICONS.items():
        rows = [r.ljust(12, ".")[:12] for r in rows]
        img = gs.icon(rows, {"o": O, "a": gs.pal(color), "b": rgba("#ffffff", 220)})
        print(os.path.relpath(save(img, f"{OUT}/{name}.png"), gs.ROOT))


if __name__ == "__main__":
    main()
