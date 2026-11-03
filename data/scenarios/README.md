# data/scenarios/

Fight scenarios for the dev tools: the batch simulator (`tools/batch_sim.gd`),
the scenario builder and the debug overlay demo (`ui/dev/`). Hand-edited JSON.
Files whose names start with `_` are not scenarios: `_dev_tools.json` holds the
dev tools' settings (default run count, log path, save folders), and
`_harness.json` the simulation harness's (policies compared, runs, default
scenario, CSV folder, exit-check thresholds).

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
  "kit": ["strike", "shred"],        // optional: combat action ids every squad member fights with
                                     // instead of its own skills (Wait is always there)
  "opening_gauge_spread_percent": 50, // optional, 0 to 99: every unit starts with a seeded gauge of
                                     // 0 to this percent of a turn (left out: none)
  "player_policy": "simple",         // FightScenario.POLICIES: simple, random, intent, patient,
                                     // careful, greedy, smart
  "enemy_policy": "intent"           // default "intent": enemies act as on the battle screen
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

Each bot fights with the combat skills its own skills map to (`SquadSkills`,
through `bot_skill_effects` in `data/combat/combat_tuning.json`), plus the basic
attack; a bot with no skills gets `CombatTuning.player_skills`. A scenario's
`kit` replaces every squad member's skills with the listed actions, for actions
no bot skill maps to yet (such as Shred).

## Samples

- `level2_drafted_squad.json`: the seed-2024 draft against level 2, enemies drawn per seed.
- `sandbox_3v3.json`: the deep dive's sandbox fight (combat rework S9). Three
  inline bots (Rook, Ace, Vex) with the five-verb kit Basic (`strike`), Shred,
  Heavy Shot (`heavy_strike`), Brace and Wait against a Charger, a Plated and a
  Scaler (`charger_medium`, `plated_medium`, `scaler_medium`), level 3. The
  harness's default scenario (`tools/batch_sim.gd --policies default`). Its
  enemies are fixed, so the seed varies the opening instead: each unit starts
  with a seeded gauge of up to 50% of a turn (`opening_gauge_spread_percent`,
  `TODO(decision: sandbox-seed-variation)`), which changes who acts first and
  when the Charger's Ram lands. Play it by hand from the dev menu (Sandbox
  fight) or the scenario builder (Play on battle screen); F6 shows the live
  action-use share.
- `duo_vs_turret.json`: two inline bots, played by the random policy, against a
  sentry turret and two scrap drones, the same enemies every fight.
