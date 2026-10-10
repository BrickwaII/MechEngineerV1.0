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
- `RunSave`: one binary resource file (`user://run.res`; binary keeps every
  float exact, text `.tres` rounds the last digit) with the map's `RunState`,
  the `BotSquad`, the ledger and the run seed. Loading restores the squad, the
  map state and the act.
- Battle screen: F3 toggles the `DebugOverlay` (hidden by default). It shows
  the intents the screen telegraphs.
- Variants: F4 anywhere in a run opens the variant switchboard over the game;
  the bottom-left label lists the active non-default choices. A new run drafts
  with the switchboard's draft rule and plays its act maps; each fight plays
  its fight-side choices (`RunFightService.variants_source`), which also pick
  the drift rules and the hp after the fight (hp-carryover).
- Run seed: random per new run unless `run_seed` is set. Act 1's start is
  picked from it (`seeded_start()`); no start choice in normal play. Dev
  option: `choose_start = true` brings the choice back.

Screenshots of one run: `screenshots/` (Godot does not import it).

## Presentation (M7 P3)

Timings live in `data/feel/screens.json` and follow the animation speed
setting; sounds and the three act loops are in `data/feel/audio.json`
(files under `assets/map/audio/`, made by `tools/asset_gen/gen_map_audio.py`).

- `ScreenTheme`: P1's `PixelTheme`, plus a glyph fallback (`·`, `×`), and
  `size()` that snaps font sizes to the pixel font's 10/20/30.
- `ScreenFeel`: reads `screens.json`.
- `ScreenTransition`: the band wipe over every change of screen. The swap is
  instant underneath; the bands ignore the mouse.
- Map (`ui/overworld/`): `MapFx` (hover, selection pop, captures, ring fill
  and pulse, pending-cost march), `MapChanges` (captures and resource moves
  held until the map is in view), `MeterBar.animate_to()` (trailing ghost),
  `ActMusic` (crossfaded act loops), `FactionLookup` (P4's faction, or
  nothing), the act title card during the zoom, and the shared-pool meter
  for the energy-grid variant.
- Draft (`ui/draft/`): `DraftCard` flips in, lifts on hover and shows the
  bot's manifest sprite; picks snap into the squad bar.
- Readout (`ui/post_fight/`): `TallySequence` counts each bot up, one after
  another, with level-ups and personality shifts as the payoff. A click, a
  key or CONTINUE skips it.
- Screenshots and frame strips: `demo/capture_screenshots.gd` (needs a
  display, see the header).
