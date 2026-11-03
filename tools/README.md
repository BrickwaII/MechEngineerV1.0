# tools/

Dev tools. May import any layer except ui/.

## Region prep

`region_prep/prepare_regions.py` builds the act maps in `data/regions/` from
public-domain outlines (Natural Earth, US Census TIGER). It is offline data
prep in Python (standard library only), not game code; the game reads only
its JSON output. Each map has a source file in `data/regions/sources/`.

```sh
python3 tools/region_prep/prepare_regions.py fetch --cache /tmp/region_cache data/regions/sources/*.source.json
python3 tools/region_prep/prepare_regions.py build --cache /tmp/region_cache data/regions/sources/*.source.json
```

`--preview DIR` also writes a PNG of each map's raster. It rasterizes the
outlines, grows city cores over land (act 1), traces and simplifies each
region (retrying with a finer tolerance until no outline crosses itself),
finds land borders, and adds the source file's water crossings.

## Batch simulator

Runs a scenario many times headless and prints win rate, fight length (actions
and ticks: mean ± spread, min, max), energy spent, and per-unit damage and energy.

```sh
godot --headless --path . -s res://tools/batch_sim.gd -- \
    --scenario res://data/scenarios/level2_drafted_squad.json --runs 200
```

Options: `--runs N`, `--seed N` (fight i uses seed + i), `--log PATH` or `--log none`.
Defaults live in `data/scenarios/_dev_tools.json`.

## Simulation harness (policy comparison)

Combat rework S8. Plays one scenario N times with each of several squad
policies on the same seeds and prints a Markdown comparison table plus the
deep dive's exit checks. Every number comes from the fight's own
`FightSummary`.

```sh
# The sandbox (data/scenarios/sandbox_3v3.json), greedy / smart / random, 100 seeds:
godot --headless --path . -s res://tools/batch_sim.gd -- --policies default
# Any scenario and policies:
godot --headless --path . -s res://tools/batch_sim.gd -- \
    --scenario res://data/scenarios/sandbox_3v3.json --policies greedy,smart,careful,random \
    --runs 100 --seed 1 --csv user://harness
```

- Columns, per policy: win rate, squad HP lost (and as a percent of its HP),
  capacity drained (grid cost), energy spent, fight length (squad decisions),
  ticks, combos, Staggers, the top action and its share, fights where one
  action took more than the share limit, and every action's share.
- Checks: `greedy_loses_more` (the careless policy loses `clear_gap_percent`
  more HP, and more capacity, than the clean one), `action_share` (no action
  above `max_action_share_percent` of the clean policy's uses),
  `clean_win_gap` (the same, on only the seeds both win). PASS, FAIL or
  SKIPPED (a policy the check needs was not played).
- CSV: `fights.csv` (one row per fight, with a `share_<action>` column per
  action) and `policies.csv` (one row per policy, with each check's verdict),
  both replaced on every run. `--csv none` skips them.
- Policies: `greedy` (`GreedyFightPolicy`: most real damage now), `smart`
  (`SmartFightPolicy`: the scripted-smart player), `careful`, `simple`,
  `patient`, `random`, `intent`.
- Settings: `data/scenarios/_harness.json`; the smart policy's numbers:
  `data/combat/smart_policy.json`.
- Code: `PolicyComparison.run(scenario, names, runs, seed)`, or
  `PolicyComparison.compare(resolved, name, names, runs, seed)` on a set-up
  that is already resolved (an edited tuning, a live fight's request).

## Battle debug simulator engine (S9b)

`battle_debug/battle_debug_session.gd` `BattleDebugSession` drives the battle
debugger with no scene, so every debugger action is tested headless
(`tests/tools/battle_debug/`). It takes over a live `Fight` and gives:

- **Live edits.** `set_action_field()` (an `ACTION_FIELDS` field of an action
  definition, for every unit holding it), `set_ai_weight()` (an
  `IntentWeights` base or lean), `set_personality()`, `set_unit_field()` (hp,
  stats, energy, gauge, plating, guard, Brace, Stagger). The fight settles at
  once (`Fight.settle_outside_change()`: intents re-plan, the end is checked).
  Edits are session-only: the session plays with its own copy of the tuning
  and planner.
- **Force states.** `apply_status()`, `remove_status()`, `set_gauge()`,
  `give_turn()`, `force_action()` (a unit's next action), `add_enemy()`,
  `copy_unit()`, `remove_unit()`.
- **Time.** `step()`, `submit()`, `rewind_to()` / `rewind_one()` (a
  `FightSnapshot` per decision; state comes back exactly, definitions stay as
  edited), `restart()` (same seed).
- **Measure.** `simulate()` runs the S8 harness (`PolicyComparison.compare`) on
  the set-up as edited (`simulation_setup()`, `DebugEnemyTable`).
- **Keep.** `changes` (the log, `DebugChange`), `preview_save()` (a
  `TuningPatch`: each file's line diff), `save_to_data()` (writes, reloads
  through the loaders), `export_tuning_diff()`.

Settings: `data/dev/battle_debugger.json`. Dev builds only:
`BattleDebugSession.is_enabled()` (the editor, or an export with the
`battle_debugger` feature tag). Saved files keep their layout:
`lib/json_text_patch.gd` changes one value in place, `lib/line_diff.gd` shows
the diff.

## Battle Mode simulator

Plays whole Battle Mode runs headless (`fight/battle_mode/`): fight after
fight against the rising curve in `data/battle_mode/battle_mode.json`, with
the squad's growth carried forward, and prints the end-of-run summary (turns,
HP lost, energy spent and wasted, action-use share, combos, Staggers) and one
line per fight. The numbers are the ones a played run shows.

```sh
godot --headless --path . -s res://tools/battle_mode_sim.gd -- --fights 10 --seed 7 --policy simple
```

Options: `--length gauntlet|endless`, `--fights N` (0: until the run ends),
`--seed N`, `--runs N` (seeds seed, seed+1, ...), `--squad ID` (a preset) or
`--squad draft:SEED`, `--policy` and `--enemy` (simple, patient, intent,
random, careful), `--csv DIR` or `--csv none`. `careful`
(`fight/careful_fight_policy.gd`) plays the rework's verbs; `simple` stays the
greedy baseline. `--squad rework` (the default) is the sandbox kit. Each run appends to `fights.csv` and
`runs.csv` in `user://battle_mode/` by default, for S8's harness and S10.

## Variant comparison

Plays the same seeded fights under every option of one switchboard decision
(`data/variants/variants.json`) and prints win rate, fight length, energy use
and personality drift side by side; for `hp-carryover`, each run plays several
fights in a row and the table adds runs won and end hp.

```sh
godot --headless --path . -s res://tools/compare_variants.gd -- --decision d-wait --runs 200
```

Decisions: `d-wait`, `d-wait-length`, `d-elasticity`, `d-personality-map`,
`hp-carryover`, `skill-progression`, `tag-weight`, `speed-range`,
`strike-cost`, `draft-rule`. Besides growth, the table shows `fair` (the
slowest bot's growth over the fastest's; 1.0 is even), the slowest and
fastest bots' levels and damage per fight, and the squad's Strike, other-skill
and wait shares. Options: `--runs N`, `--seed N`, `--level N`,
`--policy NAME` (the squad's; default `patient`, which waits so the wait
options show), `--enemy-policy NAME` (default `intent`), `--chain N`. Run i
drafts a fresh squad from seed + i. Defaults live in `data/scenarios/_dev_tools.json`.

## Faction check

Win rates at defense levels 0 to 5 for every enemy faction at every act's
tiers (`data/combat/factions.json`), next to the generic roster (today's
enemies), on the same seeded squads:

```sh
godot --headless --path . -s res://tools/check_factions.gd -- --runs 200 [--markdown 1]
```

## Balance sim

Win rates of freshly drafted squads against each act's fights at every alert
tier (the defense level escalation puts a typical region at) and the boss,
next to the target bands in `data/combat/difficulty_targets.json` (alert 0
60-70%, alert 1 52-62%, alert 2 45-55%, boss 30-40%). `--old 1` plays the
switches before the combat-economy pass; `--set d=o,...` any fight switches.

```sh
godot --headless --path . -s res://tools/balance_sim.gd -- --runs 200 [--old 1] [--markdown 1]
```

## Loss report

Expected losses per act for auto-played campaigns: blind autoplay (the
weakest region in range) and careful autoplay (attacks only at Favored or
Even odds, breaches Risky regions it can pay for, else waits), under the
default loss limit and the `scaled` one. The autoplay squad never grows, so
the numbers are floors.

```sh
godot --headless --path . -s res://tools/check_losses.gd -- --runs 40 [--markdown 1]
```

## Fight stats log

Every simulated fight appends one JSON line to `user://fight_stats.jsonl`
(see `SimulatedFight.record()`): scenario, seed, outcome, timed_out, actions,
ticks, squad and enemy energy spent, grid cost, and per unit its side, damage
dealt, energy spent and hp left.

## Pieces

| File | What it does |
|---|---|
| `fight_scenario.gd` | Scenario data, and turning it into a request, enemy table and policies |
| `scenario_files.gd` | Reads, writes and lists scenario JSON files |
| `fixed_enemy_table.gd` | An EnemyTable that fields listed enemies every fight |
| `simulated_fight.gd` | Plays a fight like HeadlessFightRunner, counting per-unit damage |
| `batch_simulator.gd`, `batch_report.gd` | Many seeded fights and their totals |
| `policy_comparison.gd`, `harness_settings.gd` | The simulation harness: policies compared on the same seeds, CSV and exit checks |
| `fight_stats_log.gd` | The JSON-lines log |
| `variant_comparison.gd`, `compare_variants.gd` | Every option of one decision on the same seeded fights |
| `faction_win_rates.gd`, `check_factions.gd` | Win rates per enemy faction, act tier and defense level |
| `loss_report.gd`, `check_losses.gd` | Losses per act and loss-limit hits, blind vs careful autoplay |
| `battle_mode_sim.gd` | Whole Battle Mode runs headless, with the fun metrics and CSV |
| `balance_curve.gd`, `balance_sim.gd` | Win rates per act and alert tier against the difficulty targets |
| `odds_calibration.gd`, `odds_calibration_cli.gd` | The map's simulated odds labels next to real auto-fight outcomes, per defense level |
| `bot_library.gd`, `bot_json.gd` | Saved bots (one BotSquadStorage file each) and inline bots |

The scenario format is in `data/scenarios/README.md`. The screens that use
these tools are in `ui/dev/`.

## Asset generators

`tools/asset_gen/` makes the placeholder art, font and sounds in `assets/`
(CC0, see `CREDITS.md`) from `data/feel/palette.json` and
`data/feel/sprite_manifest.json`. Python 3; the sprite and font scripts need
Pillow. `gen_enemies.py` draws the enemy faction sprites in `assets/enemies/`.
Commands are in `assets/README.md`.

## Run replay and timeline

Re-plays a run from its journal, headless, and prints a readable timeline:
act, day, every map action, each fight with its outcome, length in actions
and real time, what each bot learned, and each act's real-time length
against the 10 to 30 minute target (`data/run/run_data.json`).

```sh
godot --headless --path . -s res://tools/replay_run.gd -- "<run folder or journal.jsonl>" [--detail] [--no-replay]
```

The replay drafts from the run seed with the recorded picks, plays every map
action on a real `Campaign`, every fight from its recorded battle commands
(enemies by the same intent policy), applies the post-fight changes, and at
every snapshot line compares the map state and every bot with the journal.
Fights are deterministic for a seed, so a mismatch is a bug: the tool prints
`REPLAY MISMATCH` with each difference and exits 1. `--detail` lists every
command and resolved action.

- `RunJournal`: the journal format (every line kind is listed at the top of
  `run_journal.gd`), the writer, snapshots and the comparison.
- `RunReplay`: the replay. `RunTimeline`: the timeline text.
- `RunDataSettings`: reads `data/run/run_data.json`.
