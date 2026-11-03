# fight/battle_mode/

Battle Mode (combat rework S9c): fight after fight, with growth carried
forward, and the numbers that say whether fights are fun. No map, territory,
countdown or resources; nothing here names campaign/.

It is built on the fight and post-fight APIs only, so each new mechanic
(timeline costs, statuses, plating, archetypes, the S6 event log) shows up in
Battle Mode with no change here:

| File | What |
|---|---|
| `battle_mode_tuning.gd` | `BattleModeTuning`: `data/battle_mode/battle_mode.json` (lengths, presets, curve, elites, bosses, metrics) |
| `battle_encounter.gd` | `BattleEncounter`: one fight's enemies, kind (normal, elite, boss) and scaling |
| `battle_encounter_picker.gd` | `BattleEncounterPicker`: draws an encounter from the curve and `EnemyTable`, seeded |
| `battle_enemy_table.gd` | `BattleEnemyTable`: an `EnemyTable` that fields the encounter at its scaling |
| `battle_fight_recorder.gd` | `BattleFightRecorder`: watches a fight (its events and public state) and builds the record |
| `battle_fight_record.gd` | `BattleFightRecord`: one fight's turns, HP lost, energy spent and wasted, action uses, combos, Staggers; its readout line and CSV row |
| `battle_run_summary.gd` | `BattleRunSummary`: the run's totals, action-use shares and dominated fights; end-of-run text and CSV row |
| `battle_mode_run.gd` | `BattleModeRun`: the loop. Next encounter and request, `begin_fight`/`watch`, `finish_fight` (FightAftermath: growth and HP), `play_fight` headless, CSV |

The same `BattleModeRun` drives the screen (`ui/battle_mode/`) and the
headless sim (`tools/battle_mode_sim.gd`), so a played run and a simulated one
report the same numbers. Tests: `tests/fight/battle_mode/`.

Open decisions: `TODO(decision: battle-mode-hp)` (HP between fights follows
`hp-carryover`, default full heal) and `TODO(decision: battle-mode-save)` (no
save; see the UI).
