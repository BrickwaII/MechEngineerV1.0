# ui/demo/

Demo mode: the main menu's DEMO button opens a picker of ready-made moments
of each act (maps, fights, bosses), played with nothing saved. Scenarios live
in `data/demo/` (format in its README).

- `DemoScenario`: reads and checks one scenario file and builds it through
  the public APIs of campaign/ (ActPlan, RegionMap, MapTuning,
  Campaign.new_run_state, RunState), bot_data/ (BotFactory, BotSquad) and
  fight/ (FightRequest, EnemyTable; FixedEnemyTable from tools/ for a fixed
  lineup). No hook in campaign/ or fight/ is needed.
- `DemoPicker`: the cards, grouped by act (icon, name, one line), and MAIN MENU.
- `DemoRunFlow`: a `RunFlow` (ui/run/) that opens its scenario instead of a
  draft or a save, and never writes a run:
  - no run folder (so no Continue entry), no autosave, no journal (no
    recorder is made); SAVE, LOAD, NEW RUN and RUN FOLDER are hidden;
  - F8 still works: the report (note and screenshot, marked `"demo": true`)
    goes to `user://demo_reports/<scenario id>/<time>/`;
  - F4 opens the variant switchboard as in a run;
  - a DEMO banner sits at the bottom of every screen;
  - Home and the Esc menu's BACK TO DEMOS go straight back to the picker,
    with no confirm;
  - when the scenario ends (a demo fight's readout is done, the run is over,
    an act's payload arrives) `DemoEndPanel` offers REPLAY and BACK TO DEMOS.
  A fight scenario opens the map behind and starts the battle at once
  through the run's own fight service; the result does not change the map.
- `DemoWinRates` (`demo_win_rates_cli.gd` prints it): headless auto-fights of
  each demo fight over many seeds, the win rate and squad hp left, and
  whether the exact fight the demo plays is won. The scenario test holds
  every fight to "winnable but not trivial".
- `capture_demo.gd`: screenshots of the menu, the picker, every scenario, the
  Esc menu and the end panel (needs a display, see the header).
  `screenshots/` holds the latest set.

Tests: `tests/ui/demo/` (every shipped scenario loads, builds and opens; no
saves folder is touched; Home returns to the picker) and
`tests/ui/main/main_scene_test.gd` (DEMO, the picker and back).
