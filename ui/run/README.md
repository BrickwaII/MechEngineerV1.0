# ui/run/

One playable run: the project's main scene (`ui/main/main.tscn`) opens it.

    new run -> squad draft (seeded) -> overworld -> attack or forced defense
    -> battle screen -> result back to the map -> post-fight readout -> map

- `RunFlow` (`run_flow.tscn`): owns the run. Hands the overworld real
  contracts implementations, `BotSquadProvider` over the drafted bots and a
  `RunFightService`, so the map code is unchanged. `stage` says which screen
  shows. The overworld's SAVE / LOAD / NEW RUN buttons call the flow's
  `save_run()`, `load_run()` and `new_run()`.
- `RunFightService`: a contracts `FightService` around `FightSceneService` (or
  `AutoFightService` with `auto_fights`). When a fight ends it applies
  `PostFight` to the fielded bots (personality drift, skill levels, banked
  uses in a `SkillUseLedger`), emits `fight_reported`, then passes the result
  to the map. TODO(decision: hp-carryover): bots heal to full after each fight.
- `RunSave`: one resource file (`user://run.tres`) with the map's `RunState`,
  the `BotSquad`, the ledger and the run seed. Loading restores the squad, the
  map state and the act.
- Battle screen: F3 toggles the `DebugOverlay` (hidden by default). It shows
  the intents the screen telegraphs.
- Run seed: random per new run unless `run_seed` is set. Act 1's start is
  picked from it (`seeded_start()`); no start choice in normal play. Dev
  option: `choose_start = true` brings the choice back.

Screenshots of one run: `screenshots/` (Godot does not import it).
