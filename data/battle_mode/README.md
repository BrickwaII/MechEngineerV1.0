# data/battle_mode/

`battle_mode.json` tunes Battle Mode (combat rework S9c): battle after
battle with no map, territory, countdown or resources, so the fights can be
judged on their own. Read by `fight/battle_mode/battle_mode_tuning.gd`;
every number is a first guess for S10 to tune.

- `lengths`: `gauntlet` (10 fights, bosses at 5 and 10) and `endless` (until
  the squad falls, a boss every 5th fight).
- `squads`: preset squads, each a draft seed and the draft positions fielded
  (the same bots the draft screen shows for that seed).
- `curve`: one row per stage, by fight number. Difficulty grows by the number
  of questions a fight asks (the deep dive's "Fun and fair"): `types` (distinct
  enemy kinds), `factions`, `fast` (kinds at or above `fast_speed`), then
  `tiers`; the stat percents rise only gently. `endless_growth` keeps raising
  them past the last row.
- `elite_every`, `elite`: every Nth fight is an elite (tiers one step up, one
  more kind within the same count, a stat bump).
- `boss`: the bosses in order (the list repeats), their scaling, and escorts.
- `archetypes_from_fight`: from this fight on, any enemy in
  `combat/enemy_tables.json` that names an archetype joins every pool.
- `metrics`: `dominant_share_percent` (an action above this share of a fight's
  turns is flagged; the plan's "no action above about 50%") and `csv_folder`
  (where runs append `fights.csv` and `runs.csv`; never the save or settings).

Enemies come straight from `combat/enemy_tables.json`: every non-boss enemy
with a tier, grouped by faction (`generic` for none). Battle Mode ignores the
`difficulty-curve` switch; its own curve sets enemy stats.
