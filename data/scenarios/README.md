# data/scenarios/

Fight scenarios for the dev tools: the batch simulator (`tools/batch_sim.gd`),
the scenario builder and the debug overlay demo (`ui/dev/`). Hand-edited JSON.
Files whose names start with `_` are not scenarios: `_dev_tools.json` holds the
dev tools' settings (default run count, log path, save folders).

Scenarios saved from the scenario builder go to `user://dev/scenarios/`, and
bots saved from the robot builder to `user://dev/bots/` and `user://dev/enemies/`.

## Format

```json
{
  "name": "Level 2, drafted squad",
  "kind": "attack",                  // or "defend"
  "territory_id": "scenario",
  "defense_level": 2,                // 0 to 5: enemies drawn, rewards, grid cost
  "squad": [ ...entries... ],
  "enemies": [ ...entries... ],      // optional; leave out to draw from the enemy table
  "player_policy": "simple",         // "simple" or "random"
  "enemy_policy": "simple"
}
```

Squad entries, in any mix:

| Entry | Gives |
|---|---|
| `{"squad_file": "user://dev/bots/bolt.tres"}` | the fielded bots of a squad saved with BotSquadStorage |
| `{"squad_file": "...", "bot_id": "bot_2"}` | one bot of that squad |
| `{"draft_seed": 2024}` | the fielded bots of BotFactory's draft for that seed |
| `{"bot": {"id", "name", "hp", "stats": {...}, "skills": [{"name", "level"}]}}` | an inline bot |

Enemy entries: an enemy id from `data/combat/enemy_tables.json` (`"rust_hound"`),
`{"enemy": "rust_hound", "count": 2}`, or any squad entry above to field a bot as
an enemy. Listed enemies appear every fight in that order; without `enemies`,
each fight draws them for `defense_level` with its seed.

Bots' own skills do not drive fights yet: fight/ gives every squad member the
skills in `CombatTuning.player_skills`, and a bot fielded as an enemy gets the same.

## Samples

- `level2_drafted_squad.json`: the seed-2024 draft against level 2, enemies drawn per seed.
- `duo_vs_turret.json`: two inline bots, played by the random policy, against a
  sentry turret and two scrap drones, the same enemies every fight.
