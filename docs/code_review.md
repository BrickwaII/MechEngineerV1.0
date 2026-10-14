# Code review: tidiness and effectiveness (2026-10)

A cross-cutting audit of the ~36k lines of GDScript, done before a series of
behaviour-preserving cleanup pull requests. Findings are ranked by value
(lines saved, bugs avoided, time saved) within each section. File:line refs
are to `main` at 8f7101a.

## How "no behaviour change" is proven

- `scripts/run_tests.sh`: every suite, green on every PR. No test is deleted
  or weakened; moved tests keep every case.
- `scripts/golden_check.sh [BASE_REF]`: runs `tests/golden/golden_capture.gd`
  in the working tree and in a worktree of the base ref, and diffs the
  outputs. The capture covers fixed-seed fights (every policy, kind, level and
  fight-variant option: logs, tags, results), previews and intent badges,
  post-fight growth chains, odds estimates, every tool report (batch sim,
  variant and campaign comparisons, faction win rates, balance curve with
  today's and the old switches, loss report, odds calibration), campaign
  autoplay records (both policies, growing and not, every campaign variant
  option), every region map, every act's tuning and start states with their
  save files, every data-file tuning object, and whole runs played through
  RunFlow (auto-fought and fought on the battle screen): journal (wall-clock
  fields zeroed), timeline, replay verdict, summary and save file.
  Two captures of the same tree are byte-identical (checked), so any diff is
  a behaviour change.
- ui/ PRs: screenshots of the demo scenarios before and after (xvfb).

## Shared code: where it goes

| Folder | Holds | May import | Imported by |
|---|---|---|---|
| `lib/` (new) | Generic helpers with no game rules: JSON files, checked data reading, the switchboard variant set, number text | nothing | every code layer but contracts/ |
| `ui/common/` | ui-only helpers (capture scripts, labels, frames) | as ui/ | ui/ |
| `tools/` | tools-only helpers (command line options) | as today | tools/, ui/ |

contracts/ keeps "imports nothing": it needs none of lib/. The rule lives in
`tests/architecture/layer_rules.gd` and CLAUDE.md.

## Findings: shared across layers

1. **JSON loading, ~25 hand-written copies** (high). The same
   `JSON.parse_string(FileAccess.get_file_as_string(path))` + "is it a
   Dictionary" check, each with its own error style:
   bot_data/bot_tuning.gd:172, campaign/act_plan.gd:55,
   campaign/escalation.gd:60, campaign/map_tuning.gd:112,
   campaign/region_map.gd:42, campaign/variants/campaign_variants.gd:108,122,
   fight/combat_tuning.gd:56, fight/enemy_table.gd:27,
   fight/faction_table.gd:44, fight/intent/enemy_personalities.gd:20,
   fight/intent/intent_weights.gd:42, fight/odds/odds_tuning.gd:24,
   fight/post_fight/post_fight_tuning.gd:58, fight/preview/preview_rules.gd:16,
   fight/skill_ranks.gd:41, fight/variants/fight_variants.gd:220,
   tools/balance_curve.gd:248, tools/dev_tool_settings.gd:42,
   tools/run_data_settings.gd:35, tools/scenario_files.gd:8,
   ui/common/feel_data.gd:18, ui/demo/demo_scenario.gd:103,
   ui/dev/switchboard.gd:166, ui/fight/battle_art.gd:29,
   ui/fight/battle_tier_rule.gd:135, ui/fight/fight_screen_tuning.gd:25,
   ui/run/run_folder.gd:70. Writes repeat too (tools/scenario_files.gd:21,
   ui/run/run_folder.gd:75, ui/run/feedback_report.gd:36,
   ui/dev/switchboard.gd:86). Move to `lib/json_file.gd`.
2. **Repeated file reads in simulations** (high, speed). Every
   `IntentFightPolicy.new()` reads `intent_weights.json` and
   `enemy_personalities.json`; one careful autoplay campaign reads each
   **1,073 times** (strace). `CombatTuning.load_default()` and
   `EnemyTable.load_default()` re-read their files on every `Fight.new()`
   that is not handed a tuning (~0.7 ms of a ~10 ms fight). Fix: a
   read-once cache of the parsed default files in `lib/json_file.gd`; each
   `load_default()` still builds a fresh object, so callers that change the
   object they get are unaffected.
3. **FightVariants and CampaignVariants are one class written twice** (high):
   fight/variants/fight_variants.gd:105-217 and
   campaign/variants/campaign_variants.gd:97-240 (31 shared 5-line windows):
   the fields, `from_dict`, `choose`, `option`, `is_chosen`, params,
   `non_default`, `duplicate_variants`. fight/ and campaign/ may not import
   each other, so the base class `VariantSet` goes in lib/.
4. **Checked data readers duplicated** (medium): dotted-path `_lookup`/`_num`/
   `_list` in campaign/map_tuning.gd:258-285 and campaign/act_plan.gd:238-255
   (same code, different error label); `_string` in campaign/map_region.gd:113
   and campaign/start_option.gd:80 (identical); `_number`
   campaign/start_option.gd:88 and ui/fight/fight_screen_tuning.gd:50;
   bot_data/bot_tuning.gd:183 `_read_int`. Move to `lib/data_reader.gd`.
5. **Number formatting** (low): "whole numbers bare, else one decimal" in
   campaign/stakes.gd:197 (`Stakes._n`, also called from campaign.gd:681 as a
   private member of another class) and ui/overworld/overworld.gd:1994.
   fight/post_fight/skill_numbers.gd:47 is close but truncates with `int()`
   rather than rounding, so it is left as is (changing it could change text).
   Move the shared one to `lib/text_format.gd`.

## fight/

1. **The policy loop is written twice** (medium): HeadlessFightRunner.run
   (fight/headless_fight_runner.gd:21-34) and SimulatedFight.step
   (tools/simulated_fight.gd:40-53) both seed `hash("policy:%d")`, pick the
   side's policy, submit, and fall back to SimpleFightPolicy. A third copy of
   the seed is in fight/commands/fight_command_handler.gd:42. One
   `HeadlessFightRunner.play_turn()` and `policy_rng()` serve all three.
2. **Dead code** (low): `SkillRanks.uses_to_reach` (fight/skill_ranks.gd:161),
   `FactionTable.pick_for_territory` (fight/faction_table.gd:150),
   `BattleReadout.slots_of` (fight/preview/battle_readout.gd:120). No callers
   in code or tests.
3. **Hot path** (measured, 200 fights): a fight costs ~10.7 ms through the
   default path: 3.2 ms enemy intent choice, 1.6 ms submit, 1.2 ms setup,
   ~0.7 ms re-reading two data files, 0.5 ms building an IntentFightPolicy
   (two more file reads). The timeline ticks one at a time but averages only
   67 ticks a fight, so it is not the cost. Fixed by finding 2 above;
   GDScript micro-tuning of the planner is not worth its readability cost.
4. fight.gd (372 lines) and the rules classes are in good shape; no long
   functions (the longest, `_resolve_skill`, is 50 lines and reads in order).

## campaign/

1. VariantSet (shared 3), readers (shared 4), number text (shared 5).
2. **Inline tunable** (low): campaign/escalation.gd:264 rotates headlines every
   4 time points with a literal 4. Move it to data/tuning/escalation.json.
3. `Stakes._n` is private but used by Campaign (campaign.gd:681): goes away
   with shared 5.
4. campaign.gd (731 lines) is long but cohesive, sectioned and documented;
   splitting it would scatter one rule set. Left as is.

## bot_data/

Small and clean (723 lines). Only shared 1 and 4 apply (bot_tuning.gd).

## tools/

1. **Command line option parsing copied 7 times** (medium):
   tools/balance_sim.gd:33-41, batch_sim.gd:24-31, check_factions.gd:22-29,
   check_losses.gd:28-36, compare_variants.gd:36-43,
   odds_calibration_cli.gd:9-13 (looser copy), plus `decision=option` list
   parsing in balance_sim.gd:42-47 and check_losses.gd:42-51. Move to
   `tools/cli_options.gd`.
2. **Fielded squad summaries** (low): the "build_squad(seed), to_summary each
   fielded bot" loop in tools/faction_win_rates.gd:102,
   tools/balance_curve.gd:190, tools/odds_calibration.gd:44 duplicates
   `BotSquadProvider.get_squad()`.
3. tools/variant_comparison.gd:155 `_play_option` is 107 lines; it reads in
   order (one run loop with per-decision bookkeeping). Splitting out the
   per-run tally would help but risks the golden numbers for little gain.
   Left as is.
4. Report table formatting is bespoke per report (column sets differ); a
   shared table builder would add code. Left as is.

## tests/

1. Fixture copies in tests/ui (`_frames`, `after_test` clean-up, scene
   runner set-up) across run_flow_test.gd:37, run_journal_test.gd:37,
   leave_run_test.gd:41, battle_*_test.gd: done with the ui/ PR, since
   another session is changing ui/ now.
2. tests/fight/intent/intent_test_helpers.gd:13 and
   tests/fight/legacy_switches.gd:23 parse data files by hand: use
   `JsonFile`.
3. Suite time: 178 s of test bodies, 3m24s wall. The slowest suites are ui
   flows (overworld_acts 16 s, run_flow 13 s, post_fight_readout 14 s) and
   preview_matches_resolution (15 s), campaign_comparison (12 s),
   loss_report (11 s), which are simulation-bound and gain from fight 3.

## ui/ (after the screen-fit work merges)

1. **Capture scripts** (high, ~20 files): ui/*/demo/capture_*.gd and
   ui/overworld/capture_*.gd each re-implement argument parsing (`out_dir`,
   `only`), frame waiting (`_frames`, `_settle`, `_wait_until`), flow set-up
   and saving PNGs. A shared `ui/common/capture_script.gd` base.
2. Label and panel builders repeated across screens
   (ui/fight/unit_panel.gd:628 and battle_screen.gd:1194 `_label`;
   ui/main/main_menu.gd:445, run_over_screen.gd:133, run/feedback_form.gd:137
   colored labels; dim + center overlay in demo_end_panel.gd:30,
   pause_menu.gd:112, feedback_form.gd:37).
3. JSON reads (shared 1) in feel_data, demo_scenario, switchboard,
   battle_art, battle_tier_rule, fight_screen_tuning, run_folder.
4. Long functions: ui/fight/battle_screen.gd:630 `_build_layout` (205
   lines), ui/overworld/overworld.gd (2,001 lines; `_refresh_panel` 82,
   `_build_top_bar` 76).
5. Dead code: ui/common/info_card.gd `set_title`, `set_flags`;
   ui/common/entry_tile.gd `set_line`; ui/common/sound_player.gd
   `play_music`, `stop_music`, `music_id`; ui/main/main_menu.gd `_centered`;
   ui/overworld/overworld.gd `_pip`; ui/overworld/palette.gd
   `resource_color`; ui/run/run_recorder.gd `is_ended`;
   ui/run/run_fight_service.gd `heal_squad`; ui/fight/battle_beat.gd
   `of_kind`; ui/fight/battle_unit_sprite.gd `is_still`;
   ui/draft/draft_card.gd `is_flipping` (each to be checked for scene or
   string use first).

## Pull requests

1. `track/cleanup-lib`: this report, `lib/` (JsonFile, DataReader,
   VariantSet, TextFormat) with tests, the layer rule, the golden check.
2. `track/cleanup-fight`: fight/ onto lib/, the shared policy turn, read-once
   defaults, dead code.
3. `track/cleanup-campaign`: campaign/ onto lib/, the escalation tunable.
4. `track/cleanup-bot-data-tools`: bot_data/ and tools/ onto lib/, the
   command line options, squad summaries.
5. `track/cleanup-test-fixtures`: non-ui test helpers.
6. `track/cleanup-ui`: once the screen-fit PRs have merged.
