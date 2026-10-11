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

## Variant comparison

Plays the same seeded fights under every option of one switchboard decision
(`data/variants/variants.json`) and prints win rate, fight length, energy use
and personality drift side by side; for `hp-carryover`, each run plays several
fights in a row and the table adds runs won and end hp.

```sh
godot --headless --path . -s res://tools/compare_variants.gd -- --decision d-wait --runs 200
```

Decisions: `d-wait`, `d-wait-length`, `d-elasticity`, `d-personality-map`,
`hp-carryover`, `draft-rule`. Options: `--runs N`, `--seed N`, `--level N`,
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
| `fight_stats_log.gd` | The JSON-lines log |
| `variant_comparison.gd`, `compare_variants.gd` | Every option of one decision on the same seeded fights |
| `faction_win_rates.gd`, `check_factions.gd` | Win rates per enemy faction, act tier and defense level |
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
