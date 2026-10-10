# ui/dev/

Developer screens. Start at `res://ui/dev/dev_menu.tscn`, or run one directly.
The dev menu also plays a run on the switchboard's choices.

- `switchboard_screen.tscn` (`SwitchboardScreen`, model `Switchboard`): the
  variant switchboard, one picker per open decision in
  `data/variants/variants.json`, the per-act map variants and the draft rule
  included. Choices save at once to `user://variants.json`. F4 in a run opens
  it over the game; `VariantLabel` lists active non-default choices in the
  bottom-left corner during play.


- `bot_builder.tscn`: create or edit a bot's or enemy's stats and skills and
  save it through BotSquadStorage (`user://dev/bots/`, `user://dev/enemies/`).
- `scenario_builder.tscn`: pick saved bots and enemies, save a scenario
  (`user://dev/scenarios/`), and run it with the batch simulator.
- `debug_overlay.gd` (`DebugOverlay`): a standalone node that shows a Fight's
  units, energy, gauges, timeline and each enemy's planned intent
  (IntentPlanner), live. Add it to any scene and set `overlay.fight`; F3
  toggles it. `debug_overlay_demo.tscn` shows it on a fight
  driven headless.

- `enemy_lineup.tscn` (`EnemyLineup`): every enemy unit type grouped by
  faction, in all three tiers, idling. `capture_enemy_lineup.gd` renders it
  and one battle per faction to PNGs (needs a display, see the script).

`screenshots/` holds images for pull requests; Godot does not import it.
