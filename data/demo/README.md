# data/demo/

Demo scenarios: ready-made moments of each act, opened from the main menu's
DEMO button (the picker, `ui/demo/`). A demo is never saved: no run folder, no
autosave, no journal on disk. Loaded by `DemoScenario` (`ui/demo/demo_scenario.gd`).
Hand-edited JSON, one scenario per file; the file name is its id. Files starting
with `_` are skipped.

```json
{
  "name": "Map, late",                    // the card's name
  "description": "One line for the card.",
  "icon": "alert",                        // an icon id from data/ui/icons.json
  "act": 1,                               // 1 to 3: the picker's group
  "order": 2,                             // place in the act's group, lowest first
  "kind": "map",                          // map, fight, pre_fight, fast_forward, run_over

  "map": "lake_washington_12",            // the act's map variant; "" or absent: its default
  "start": "renton_works",                // a start id on that map; absent: the first
  "held": ["renton", "tukwila"],          // regions held; absent: the start's
  "hostile": ["bellevue"],                // or: the regions NOT held (every other is held)
  "pressure": {"renton": 100},            // pressure percent on held regions (100 forces a defense)
  "alert_tier": 2,                        // 0 to 2
  "fortify": {"*": 2, "bellevue": 3},     // levels per hostile region; "*" for every one
  "resources": {"energy": 30, "material": 20, "grid": 70},
  "day": 60,
  "losses": 1,                            // battles lost this act
  "news": {"kind": "tier"},               // toast the act's alert headline; or {"headline", "body"}

  "squad": {"seed": 13, "picks": ["bot_1", "bot_4", "bot_2"], "skill_ranks": 3},

  "fight": {                              // kind "fight"
    "region": "rockies",                  // a region on the map (its faction fields enemies), or "boss"
    "kind": "attack",                     // or "defend"
    "level": 3,                           // defense level 0 to 5
    "enemies": ["rival_walker"],          // optional: these enemies every time, in order
    "boss": true,                         // optional: a boss fight (boss styling, boss music)
    "music": "boss",                      // optional: "battle" or "boss"
    "title": "Resistance Command"         // optional: the name in the battle header
  },
  "region": "bellevue",                   // kind "pre_fight": the region the step opens on
  "run_over": {"won": false, "end_reason": "loss limit reached", "act": 2, "day": 41}
}
```

The squad is the seeded draft's (BotFactory), the first squad-size bots or
`picks` in order, each skill raised by `skill_ranks` (up to the top rank).
Fight scenarios open the map behind and the battle on top at once; the fight
does not change the map. Every shipped scenario is loaded and built by
`tests/ui/demo/`.

Bosses: act 3's demo boss is the real one, today's stand-in (the generic
roster at Defense 5, `Campaign.boss_fight()`). Acts 1 and 2 have no boss in a
run, so their demo bosses are showcases: the act's strongest faction units as
a fixed lineup, fought over the `boss` territory so the difficulty curve's
boss scaling applies. TODO(decision: act-bosses): should real runs get act 1
and act 2 bosses?

Every fight is winnable but not trivial: `tests/ui/demo/demo_scenario_test.gd`
checks that the simple auto-player wins the exact fight the demo plays and
that a random player wins 10 to 95% of seeds. Print the numbers with
`godot --headless --path . -s res://ui/demo/demo_win_rates_cli.gd -- 60 simple`.
