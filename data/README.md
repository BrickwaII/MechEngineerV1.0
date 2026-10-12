# data/

Region files and tuning tables. Hand-edited, no code.

- `bot_data/tuning.json`: draft size, squad size, augment slot count, stat ranges,
  starting personality range, starting skills and generation, bot names.
- `bot_data/skills.json`: the starting skill catalog (name, effect id, energy cost).
- `bot_data/tuning.json` `draft_rule`: how drafted bots get their starting skills, `random` (default), `damage_guarantee` or `non_strike_damage` (TODO(decision: draft-rule)).
- `combat/`: `combat_tuning.json` (skills, energy, damage), `enemy_tables.json` (every enemy, faction units as `<unit>_<tier>`, and the generic pools by defense level), `factions.json` (enemy factions: units, tier by act and level, the faction of every region), `odds.json` (the map's simulated odds: auto-fights per estimate and the label bands), `intent/` (enemy personalities, intent weights, preview rules).
- `variants/variants.json`: the variant switchboard, every open decision with its options and default; see `variants/README.md`.
- `regions/`: the act maps and their variants, built from public-domain outlines
  (see `regions/README.md`), and the placeholder maps the tests use.
- `tuning/acts.json`: the acts, their map variants and the zoom between them.
- `tuning/overworld.json`: every overworld number; `tuning/act1.json` to
  `act3.json` lay each act's pacing over it (countdown, action costs, pressure).
- `tuning/escalation.json`: escalation (campaign/escalation.gd). Each act's three
  alert tiers and their enemy level bands, the held share that raises the tier,
  fortifying, the news headlines, and the alert meter and news card sizes.
- `feel/`: presentation tables. `palette.json` (every screen's colors), `feel.json` (tween presets, hit pause, shake, popups, ghost bar), `audio.json` (sounds, variation, throttling, music tracks and the music director's contexts), `settings.json` (settings defaults), `sprite_manifest.json` (unit sheets and tiers, format in `assets/README.md`).
- `run/run_data.json`: run data. Where run folders go, the old save path, autosave points, the F8 form's categories and mood range, the load list length, the replay's number tolerance, and the act length target in real minutes.
