# ui/battle_mode/

Battle Mode on screen (combat rework S9c): fight after fight with no map,
territory, countdown or resources, so the battles can be judged on their own.
The loop is `fight/battle_mode/` `BattleModeRun`, the same one
`tools/battle_mode_sim.gd` plays headless.

| File | What |
|---|---|
| `battle_mode_flow.gd` | `BattleModeFlow`: setup, draft, battle screen, post-fight readout with the Battle Mode bar, end-of-run summary; Esc menu and Home; writes the CSV when the run ends or is left |
| `battle_mode_setup.gd` | `BattleModeSetup`: length cards (Gauntlet, Endless) and squad cards (presets from `data/battle_mode/`, or Draft) |
| `battle_mode_summary.gd` | `BattleModeSummary`: the run's totals as icons, action-use share bars with the dominant-share line, one row per fight |
| `battle_fight_line.gd` | `BattleFightLine`: one fight's numbers as icons (under the readout and on the summary) |

Opened from the main menu's Battle Mode tile. Nothing is saved
(`TODO(decision: battle-mode-save)`): leaving ends the run, and its fights
still go to `user://battle_mode/fights.csv` and `runs.csv`.

Screens are in `ScreenFit` (`battle_mode_setup`, `battle_mode_readout`,
`battle_mode_summary`); the battles are the ordinary battle screen. Tests:
`tests/ui/battle_mode/`. Pictures: `screenshots/`.
