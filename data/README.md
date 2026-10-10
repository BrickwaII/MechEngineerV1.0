# data/

Region files and tuning tables. Hand-edited, no code.

- `bot_data/tuning.json`: draft size, squad size, augment slot count, stat ranges,
  starting personality range, starting skills and generation, bot names.
- `bot_data/skills.json`: the starting skill catalog (name, effect id, energy cost).
- `bot_data/tuning.json` `draft_rule`: how drafted bots get their starting skills, `random` (default), `damage_guarantee` or `non_strike_damage` (TODO(decision: draft-rule)).
- `feel/`: presentation tables. `palette.json` (every screen's colors), `feel.json` (tween presets, hit pause, shake, popups, ghost bar), `audio.json` (sounds, variation, throttling), `settings.json` (settings defaults), `sprite_manifest.json` (unit sheets and tiers, format in `assets/README.md`).
