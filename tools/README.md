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
| `bot_library.gd`, `bot_json.gd` | Saved bots (one BotSquadStorage file each) and inline bots |

The scenario format is in `data/scenarios/README.md`. The screens that use
these tools are in `ui/dev/`.
