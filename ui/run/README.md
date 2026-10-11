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
- `RunSave`: one binary resource file (`run.res` in the run's folder; binary
  keeps every float exact, text `.tres` rounds the last digit) with the map's
  `RunState`, the `BotSquad`, the ledger and the run seed. Loading restores
  the squad, the map state and the act. A run keeps only the bots picked in
  the draft (`BotSquad.to_fielded_squad()`); an older save that kept a bench
  drops it on load.
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

## Run data (R1-A)

Every run has its own folder, a journal of everything the player did, and
F8 feedback reports. Numbers and switches: `data/run/run_data.json`.

    <runs folder>/<yyyy-mm-dd_hhmm>_<seed>/
        run.res        the save (autosaved at the map start, after every
                       fight and at every act change; SAVE on the map too)
        journal.jsonl  the run journal, one JSON object per line
        summary.json   act, day, regions held, fights won and lost, play time,
                       finished or not, won or not
        reports/<yyyy-mm-dd_hhmmss>/   one per F8 report:
            screenshot.png, note.json, run.res, journal.jsonl

A new run never reuses a folder (a second run with the same seed in the same
minute gets `_2`). Finished runs, won or lost, keep their folder.

Where the runs folder is (`user://runs`): the game is not set to a custom
user dir, so Godot keeps it under the project name.
- Windows: `%APPDATA%\Godot\app_userdata\Mech Engineer\runs`
  (for example `C:\Users\<you>\AppData\Roaming\Godot\app_userdata\Mech Engineer\runs`)
- macOS: `~/Library/Application Support/Godot/app_userdata/Mech Engineer/runs`
- Linux: `~/.local/share/godot/app_userdata/Mech Engineer/runs`

The main menu prints the full path. RUN FOLDER on the map (beside NEW RUN)
and OPEN RUN FOLDER in the F8 form open the run's folder in the file browser. To
send a playtest to Claude, upload the run folder (or one `reports/` folder).

- `RunFolder`: makes and lists run folders, reads and writes the summary,
  the one-line summary for the load list, and the one-time import of the old
  single-slot `user://run.res`.
- `RunRecorder`: writes the journal (format in `tools/run_journal.gd`) from
  signals: `Campaign.acted` (wait, reinforce), `fight_started`,
  `fight_finished`, `expanded`, `changed`; the overworld's
  `campaign_started` (act zoom, load); `BattleScreen.command_sent` and
  `FightCommandHandler.action_resolved` with the Fight's FightEvents; and
  RunFlow for the draft, focus, save, load and F8. Snapshots (state and every
  bot) at the run start, after every fight, at every act change and after a
  load. Each line has the wall-clock time, the real play time of the run
  (over every session, F8 pauses left out) and the act and day.
- `FeedbackForm`, `FeedbackReport`: F8 pauses the game, takes a screenshot
  and opens a form with a note, a category (bug, balance, UI, idea, other) and
  a 1 to 5 mood rating. SAVE REPORT writes `reports/<time>/` with
  `note.json` (note, category, rating, stage, act, day, screen, active
  variant choices), the screenshot, and copies of the save and the journal.
- Replay and timeline: `tools/replay_run.gd` (see tools/README.md).

Main menu (`ui/main/`): CONTINUE (the latest run that is not over), LOAD
(every run, newest first, with its one-line summary; finished runs are listed
but cannot be loaded) and NEW RUN. The old `user://run.res` is offered once as
an imported run.

Screenshots: `ui/main/demo/capture_run_data.gd` (needs a display, see the
header) renders the main menu, the load list, the F8 form and the map button.
