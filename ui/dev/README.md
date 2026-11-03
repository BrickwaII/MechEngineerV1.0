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
- `scenario_builder.tscn`: pick saved bots and enemies, set the kit and the
  opening gauge spread, save a scenario (`user://dev/scenarios/`), run it with
  the batch simulator, or play it by hand (Play on battle screen). The S9
  sandbox (`data/scenarios/sandbox_3v3.json`) is in its Load list.
- `scenario_battle.tscn` (`ScenarioBattle`): plays a scenario on the battle
  screen, the sandbox when none is given (the dev menu's Sandbox fight), with
  an `ActionSharePanel` (F6) and a hidden `DebugOverlay` (F3). Next seed, same
  seed again, or back when a fight ends. `capture_sandbox.gd` renders it.
- `action_share_panel.gd` (`ActionSharePanel`): a standalone node that shows
  one side's live action-use share, this fight and the session, read from
  FightSummary (S6); shares above the harness's
  `max_action_share_percent` are marked. Add it to any scene and set
  `panel.fight`; F6 toggles it.
- `debug_overlay.gd` (`DebugOverlay`): a standalone node that shows a Fight's
  units, energy, gauges, timeline and each enemy's planned intent
  (IntentPlanner), live. Add it to any scene and set `overlay.fight`; F3
  toggles it. `debug_overlay_demo.tscn` shows it on a fight
  driven headless.

- `enemy_lineup.tscn` (`EnemyLineup`): every enemy unit type grouped by
  faction, in all three tiers, idling. `capture_enemy_lineup.gd` renders it
  and one battle per faction to PNGs (needs a display, see the script).

`screenshots/` holds images for pull requests; Godot does not import it.
