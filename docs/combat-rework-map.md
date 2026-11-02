# Combat rework: repo map (S0)

The map that sessions S1 to S17 of the combat rework read before they start.
It says where each system lives today, what each session touches or adds
under this repo's names, which plan rules clash with this repo, and what is
still open.

- Plan: `docs/design/combat-rework-plan.md` (snapshot of the live doc)
- Design: `docs/design/combat-deep-dive.md` (snapshot) and the main design doc
  (https://claude.ai/artifact/Lkdta9UVJ1wbxcWdbG6LvL)
- Code tour: `docs/code_review.md`, plus each folder's `README.md`
  (`fight/README.md` is the most detailed)
- New open questions go in `docs/design/combat-rework-questions.md`, not in
  the plan.

Written against `main` at b058452 (2026-11-02). File names are exact; line
counts are approximate.

**Contents.** 1 Where each system lives today · 2 Sessions S1 to S6 ·
3 Sessions S7 to S17 · 4 Layer check · 5 Conflicts and resolutions ·
6 Open questions and the decisions table

---

## 1. Where each system lives today

### 1.1 The fight loop

| System | Where | Notes |
|---|---|---|
| One fight | `fight/fight.gd` `Fight` (372 lines) | ATB wait mode. `advance()` runs time until a unit is ready; `submit(FightAction)` resolves it. `check_action()` validates. `_resolve_skill`, `_hit`, `_resolve_wait` hold every rule that runs during an action. The seed only picks enemies. |
| A unit's fight state | `fight/combatant.gd` `Combatant` | hp, `gauge`, `charge_per_tick`, energy in thousandths (`energy_milli`, `MILLI = 1000`), recharge, wait state (`wait_target_milli`, `wait_ticks`, `wait_length`), `guard_percent`, `reflect_percent`. `finish_action(threshold)` spends one threshold of gauge, **clamped at 0**. `clone_for_preview()` copies the changing state. |
| Decision | `fight/fight_action.gd` `FightAction` | `Kind { SKILL, WAIT }`, `skill_id`, `target_id`, `wait_ticks`. |
| Player input | `fight/commands/fight_command.gd`, `fight_command_handler.gd` | Select bot, skill, target; wait; cancel. Plays enemy turns with a policy. |
| Turn order (ATB) | `fight/timeline.gd` `Timeline`, `fight/timeline_entry.gd` | Each tick every living unit adds `charge_per_tick` to `gauge`; ready at `threshold`. Ties: fuller gauge, then faster, then roster order. `preview(count)` = `Fight.upcoming(n)`: simulates on clones, assuming every unit acts as soon as it is ready and spends nothing. |
| Speed | `fight/variants/speed_rules.gd` `SpeedRules` | `speed-range` switch, default **compressed**: speed 3..11 maps to charge 50..80 per tick, threshold x10, and slow units get a damage bonus (`slow_power_percent`). |
| Energy and battery | `Combatant` + `fight/variants/energy_rules.gd` `EnergyRules` | Pool = `battery_capacity` x 1000; recharge per tick = battery x `recharge_milli_per_battery_per_tick`, with a floor; units start at `starting_percent`. `strike-cost` switch, default **costs**: Strike costs 1 energy with its own recharge numbers. |
| Wait | `fight/variants/wait_rules.gd` `WaitRules` | `d-wait` (default **banked**: +100% recharge while waiting; `extra_energy`; `bonus_damage`) and `d-wait-length` (default **snap**: the wait ends on the first tick the skill is affordable; `exact`). A waiting unit holds its gauge. |
| End of fight, grid cost | `Fight._check_end`, `Fight.result()` | Defeat at `max_actions` (400). Grid cost from `combat_tuning.json` `grid`. |
| Tuning | `fight/combat_tuning.gd` `CombatTuning` + `data/combat/combat_tuning.json` | Every combat number, plus the skill table, `player_skills`, `basic_attack`, `bot_skill_effects`. Holds the fight switches (`tuning.variants`). |
| Switches | `fight/variants/fight_variants.gd` `FightVariants` (on `lib/variant_set.gd`) + `data/variants/variants.json` | One chosen option per open decision; the switchboard screen is `ui/dev/switchboard_screen.gd`. |
| Events | `fight/fight_event.gd` `FightEvent` | `Kind { SKILL, HIT, HEAL, GUARD, WAIT, DOWN }`. `Fight.last_events` holds **only the latest action's** events; `Fight.event_raised` signal. The UI presenter reads them. |
| Logs | `Fight.log_lines` (text), `Fight.action_tags` (`"<unit>:<skill>"`), `Fight.decision_tags` (`ActionTag`) | Three parallel records today, not one log. The golden check captures all of them. |

### 1.2 Actions and skills

| System | Where | Notes |
|---|---|---|
| Combat skill (action) | `fight/combat_skill.gd` `CombatSkill` | `energy_cost`, `power_percent`, `effect` (`damage`, `heal`, `guard`), `target` (`opponent`, `all_opponents`, `ally`, `self`), `level`, `fx_level`, `names_rank`, rank bonuses (`pierce_percent`, `weakest_bonus_percent`, `heal_guard_percent`, `reflect_percent`). No recovery, hit count, damage type, tags or status. A per-unit copy is built by `CombatTuning.skill_at()`. |
| Skill table | `data/combat/combat_tuning.json` `skills` | strike, heavy_strike, overload, repair, arc_sweep, brace, patch_up, shield. |
| Bot's skills | `bot_data/skill.gd` `Skill` (Resource) + `data/bot_data/skills.json` | `display_name`, `effect_id`, `energy_cost`, `level`. The bot catalog calls heavy_strike "Overcharge Shot". |
| Bot skill to combat skill | `fight/squad_skills.gd` `SquadSkills` via `bot_skill_effects` | `effect_id` picks the combat skill; the basic attack (Strike) is added when missing. Members with no skills fight with `player_skills`. |
| Combat skill back to bot skill | `data/post_fight/post_fight.json` `combat_skill_effects` | The reverse map for skill growth; a test checks the two maps agree. |
| Enemy skills | `data/combat/enemy_tables.json` `skills` per enemy | Plain combat skill ids. |

### 1.3 Damage, statuses, Elasticity, Pierce

| System | Where | Notes |
|---|---|---|
| Damage | `fight/damage_rules.gd` `DamageRules` | `damage = max(min_damage, (atk x power% x (100 + bonus)% - def x defense% x (100 - pierce)%) / 100)`, then Elasticity, then guard (`guarded()`). Bonuses in today's order: wait bonus + weakest bonus (added together), speed bonus, pierce, elasticity, guard. No damage pipeline object; the order is the order of the code. |
| **Duplicate damage math in ui/** | `ui/fight/battle_math.gd` `BattleMath._raw_damage` | Re-implements the raw-damage formula to show the math lines on the focus card. Any change to the damage formula must change it too, or the card lies. S3 should make it read a breakdown from the pipeline. |
| Heal | `DamageRules.heal` | Capped at hp lost. |
| Guard (the only real status) | `Combatant.guard_percent`, `reflect_percent`; set in `Fight._resolve_skill`, cleared in `Fight._hit` | **Blocks a percent of the next hit**, then clears. Does not expire on time. Max 80% (`guard.max_percent`). Set by the `brace` (self) and `shield` (ally) skills, and by Mega/Ultra `patch_up`. Mega/Ultra guards reflect. |
| "Charging", "Waiting", "Low energy", "Down", "Changed" | `ui/fight/status_row.gd` `StatusRow` | **UI flags, not fight statuses.** Charging = a unit in a snapping wait (`wait_target_milli`); Waiting = an exact wait; Changed = intent revised this turn. Nothing in `fight/` models them as statuses. |
| Elasticity | `fight/variants/elasticity_rules.gd` `ElasticityRules`, `d-elasticity` switch | Default **none** (no effect). Options: `reduce_big_hits`, `resist_knockback` (every hit knocks the target's gauge back, less per Elasticity point), `energy_when_hit`. `Bot.stats.elasticity` is stored for every unit. |
| Pierce | `CombatSkill.pierce_percent`, rank bonus in `data/combat/skill_ranks.json` | Strike and Heavy Strike gain pierce at Mega and Ultra rank. |
| Damage types | none | No typed damage anywhere. |

### 1.4 Intent and preview

| System | Where | Notes |
|---|---|---|
| Intent planner | `fight/intent/intent_planner.gd` `IntentPlanner` | Scores every option (attack per skill per target, heal, wait for an unaffordable attack) with `IntentWeights`, leaned by `Personality`. **Guard skills are not planned.** Re-plans from scratch each call. |
| Weights | `fight/intent/intent_weights.gd` `IntentWeights` + `data/combat/intent/intent_weights.json` | damage, energy_cost, kill, heal, retaliate, focus, wait; base + lean per scale. |
| Enemy personalities | `fight/intent/enemy_personalities.gd` + `data/combat/intent/enemy_personalities.json` | One `Personality` per enemy id. |
| Intent value | `fight/intent/unit_intent.gd` `UnitIntent` | `Kind { ATTACK, HEAL, WAIT }`, action, amount, score. |
| Intent changes | `fight/intent/intent_tracker.gd` `IntentTracker` (`intent_revised` signal), `intent_revision.gd` `IntentRevision` | Revisions with a reason, kept **outside** the fight. Intents are not stored in `Fight`: an enemy is played by `IntentFightPolicy`, which re-plans on its turn. Nothing is committed in advance, so there is nothing to "cancel" yet. |
| Intent policy | `fight/intent/intent_fight_policy.gd` | Plays the top legal intent. |
| Preview rules | `fight/preview/preview_rules.gd` `PreviewRules` + `data/combat/intent/preview_rules.json` | Lists random skills (none today); `value_for()` turns them into `?`. |
| Choice preview | `fight/preview/fight_preview.gd` `FightPreview.preview_choice()` → `ChoicePreview` | Submits the action on `FightCopy.of(fight)`, runs to the next decision, and reports hp effects, guard changes, `energy_after`, `intent_changes`, `intents_after`, `order_after` (the turn order the choice leaves) and `fight_after`. |
| Fight copy | `fight/preview/fight_copy.gd` `FightCopy` | Copies each `Combatant` with `clone_for_preview()`; shares request, tuning, stats and the skill objects. **Every new piece of fight state (statuses, plating, Brace, committed intents) must be copied here and in `clone_for_preview()`**, or the preview silently differs from the fight. |
| Badges and numbers | `fight/preview/battle_readout.gd` `BattleReadout`, `arrow_badge.gd`, `preview_value.gd` (`?`), `unit_effect.gd`, `unit_preview.gd` | Arrow numbers, KO marks, `order_with_choice()`. |
| Proof | `tests/fight/preview/preview_matches_resolution_test.gd` | Checks every previewed number against the resolved fight over many seeds. Keep it green through S2 to S5. |

### 1.5 Enemies, factions, bosses

| System | Where | Notes |
|---|---|---|
| Enemy definitions | `fight/enemy_table.gd` `EnemyTable` + `data/combat/enemy_tables.json` `enemies` | Stats, skills, sprite, tier, faction, unit, `boss`. Per-level `count`, `pool`, `rewards`. No plating, archetype or intent pattern. |
| Factions | `fight/faction_table.gd` `FactionTable` + `data/combat/factions.json` | Faction per region per act, unit types by level, tiers by act. |
| Difficulty curve | `fight/variants/difficulty_rules.gd` `DifficultyRules`, `difficulty-curve` switch (default **tuned**) | Tier per act and level, act and tier stat scaling; targets in `data/combat/difficulty_targets.json`. |
| Bosses | `enemy_tables.json` entries with `"boss": true` (precinct_overseer, continental_defense_grid, last_command) | Demo-only showcase bosses (`data/demo/act*_boss.json`); a real run's boss is the generic roster at Defense 5 (`Campaign.boss_fight()`). `TODO(decision: act-bosses)`. |
| Fixed enemies | `tools/fixed_enemy_table.gd` `FixedEnemyTable` | Same enemies every fight; used by scenarios and demos. |

### 1.6 Personality, action tags, growth

| System | Where | Notes |
|---|---|---|
| Personality | `bot_data/personality.gd` `Personality` (Resource) | Three spectrums, two ends each, ends only grow. `generation` lives **here** (not on `Bot`) and decides how many spectrums the planner weighs (`is_active()`). |
| Action tags | `fight/post_fight/action_tag.gd` `ActionTag` | One per decision, built by `Fight.submit()`. Labels: `hit_enemy`, `self_target`, `ally_target`, `wait`, `solo`, `first_affordable`. |
| Tags to axes | `fight/post_fight/personality_drift.gd` + `data/post_fight/post_fight.json` `drift_rules` | **Already a data-driven tag-to-pole mapping**, tallied per fight and applied once at the end (settled rule). `d-personality-map` switch picks the rule set; `tag-weight` (default `per_turn_time`) weights each decision. |
| Skill growth | `fight/post_fight/skill_progress.gd`, `skill_use_ledger.gd`, `skill_change.gd`, `skill_numbers.gd`, `post_fight.gd` `PostFight.apply()` | Skills rank up by use; uses bank across fights. |
| Skill ranks | `fight/skill_ranks.gd` `SkillRanks` + `data/combat/skill_ranks.json` | base, +1..+5, Mega, Mega +1..+5, Ultra; tier shifts add power and a bonus (pierce, weakest bonus, heal guard, reflect). The closest thing to the design's "named variants". `skill-progression` switch (default ranks). |
| **Skill offers** | **none** | Skills come only from the draft (`BotFactory._starting_skills`); there is no offer, no slot limit and no replace flow. |
| After a fight | `fight/fight_aftermath.gd` `FightAftermath`, `fight/variants/hp_carryover.gd` (`hp-carryover`, default full_heal) | Shared by `ui/run/run_fight_service.gd` and `tools/run_replay.gd`. |
| Save upgrades | `fight/post_fight/growth_save_upgrade.gd` | Converts old saves (flat levels to ranks). |
| Post-fight UI | `ui/post_fight/post_fight_readout.gd`, `level_up_callout.gd`, `personality_hexagon.gd`, `tally_sequence.gd` | Shows generation pips, drift, rank-ups. |

### 1.7 Bot data

| System | Where | Notes |
|---|---|---|
| Bot | `bot_data/bot.gd` `Bot` (Resource) | id, name, hp, `stats: UnitStats`, `personality`, `skills: Array[Skill]`, augment slots. `to_summary()` → `SquadMemberSummary`. |
| Squad | `bot_data/bot_squad.gd`, `bot_squad_storage.gd` (`.tres` saves), `bot_squad_provider.gd` | |
| Tuning | `bot_data/bot_tuning.gd` + `data/bot_data/tuning.json` | draft_size, squad_size, `augment_slot_count`, `starting_generation`, `starting_skill_count`, stat ranges, draft rule. **No active-skill slot limit.** |
| Augments | `bot_data/augment_slot.gd` `AugmentSlot` | Structure only: `augment_id` is always empty, no augment catalog, no effect. |
| Draft | `bot_data/bot_factory.gd` `BotFactory` | Seeded. |
| Contracts | `contracts/unit_stats.gd`, `squad_member_summary.gd` (skills as `{name, effect_id, level}`), `fight_request.gd`, `fight_result.gd`, `fight_service.gd`, `squad_provider.gd` | |

### 1.8 Generations, lineage, payload

- **Generation:** `Personality.generation` (bot_data) and `BotTuning.starting_generation`; the `tier-rule` switch (bot_data, default `generation`) and `ui/fight/battle_tier_rule.gd` draw a bot's tier plate from it. That is all.
- **Lineage, offspring, retirement, chassis upgrades, wear/fatigue, generation bands, crystallization: none.**
- **Payload:** only the campaign countdown (`campaign/campaign.gd` `is_payload_due()`); its end starts the boss fight. No offspring are produced.
- Resources Material and Energy exist on the map (`campaign/run_state.gd`, fight `rewards`), so S15's prices have a currency.

### 1.9 Headless runner, policies, tools, golden check

| System | Where | Notes |
|---|---|---|
| Runner | `fight/headless_fight_runner.gd` `HeadlessFightRunner` | `run()`, `play_turn()`, `policy_rng(seed)`. Policies get their own seeded rng. |
| Policies | `fight/fight_policy.gd` (base), `simple_fight_policy.gd` (strongest affordable single-target attack by `power_percent`, on the lowest-hp foe; the squad's auto-player), `patient_fight_policy.gd` (waits for its strongest attack), `random_fight_policy.gd`, `scripted_fight_policy.gd` (fixed list, then fallback), `intent/intent_fight_policy.gd` (enemies) | `SimpleFightPolicy` is close to the plan's Greedy but ranks by power, not by real damage, and never guards or heals. |
| Auto fights | `fight/auto_fight_service.gd` `AutoFightService` | Simple vs Intent. Also auto mode on the map. |
| Odds | `fight/odds/odds_estimator.gd`, `odds_tuning.gd` + `data/combat/odds.json` | N seeded auto-fights per map estimate. |
| Per-unit sim | `tools/simulated_fight.gd` `SimulatedFight` | Same turn loop, counts damage per unit; `record()` for the stats log. |
| Scenarios | `tools/fight_scenario.gd` `FightScenario`, `resolved_scenario.gd`, `scenario_files.gd` + `data/scenarios/*.json` | Squad entries (saved squad, draft seed, inline bot), fixed or drawn enemies, policies by name (`simple`, `random`, `intent`). |
| Batch | `tools/batch_simulator.gd`, `tools/batch_sim.gd` (CLI), `tools/fight_stats_log.gd` (JSON lines) | Win rate, length, energy. |
| Balance | `tools/balance_curve.gd`, `tools/balance_sim.gd` (CLI) | Drafted squads vs each act's fights against `difficulty_targets.json`. |
| Losses | `tools/loss_report.gd`, `tools/check_losses.gd` (CLI), `tools/campaign_autoplay.gd` | Whole auto-played campaigns. |
| Variant comparison | `tools/variant_comparison.gd`, `tools/compare_variants.gd` (CLI) | Same seeds under every option of one switch. |
| Other | `tools/odds_calibration*.gd`, `tools/faction_win_rates.gd`, `tools/check_factions.gd`, `tools/cli_options.gd` (shared option parsing), `tools/run_journal.gd`, `run_replay.gd`, `replay_run.gd`, `run_timeline.gd` | |
| Golden check | `scripts/golden_check.sh` + `tests/golden/golden_capture.gd` | Captures fixed-seed output (fight logs, tags, events, previews, growth, odds, every tool report, autoplay, maps, saves, journaled runs) from the working tree and from a **base ref checked out fresh** (default `origin/main`), then diffs. Nothing golden is stored in the repo. |

### 1.10 Demos and builders

| System | Where | Notes |
|---|---|---|
| Demo scenarios | `data/demo/*.json`, read by `ui/demo/demo_scenario.gd` `DemoScenario`; picker `ui/demo/demo_picker.gd`; tests `tests/ui/demo/` | Whole-game moments (map, fight, pre-fight, run over), squad from a draft seed. Fight demos name region, level, optional fixed enemies and boss. |
| Robot and enemy builder | `ui/dev/bot_builder.gd` | Edits stats and skills (from the bot catalog), saves a bot with `BotSquadStorage` to `user://dev/bots/` or `user://dev/enemies/` (`tools/bot_library.gd`). **No editing of skill definitions, enemy-table enemies, archetypes or statuses.** |
| Scenario builder | `ui/dev/scenario_builder.gd` | Picks saved bots and enemies, level and policies, saves scenario JSON to `user://dev/scenarios/`, runs the batch sim. |
| Debug overlay | `ui/dev/debug_overlay.gd` (F3) | Read-only: stats, energy, gauge, upcoming order, intents, personality leans. |
| Dev menu | `ui/dev/dev_menu.gd`, `dev_ui.gd`, `switchboard_screen.gd`, `enemy_lineup.gd` | |

`data/scenarios/README.md` says "Bots' own skills do not drive fights yet"; that is stale: `SquadSkills` fights with each bot's skills now.

### 1.11 Battle UI

| System | Where | Notes |
|---|---|---|
| Battle screen | `ui/fight/battle_screen.gd` (1,314 lines) | Layout, input to `FightCommand`, previews on hover. |
| Action dock | `battle_screen.gd` `_build_layout` "ActionDock" + `ui/common/action_tile.gd` `ActionTile` (on `skill_card.gd`) | Portrait, name, energy, one tile per skill with cost and hotkey. |
| Focused card | `ui/fight/focus_card.gd` `FocusCard` + `ui/fight/battle_math.gd` | The chosen skill with cost, rank, effect and the math for the target under the pointer; every valid target shows what the skill would do. |
| Arrows and badges | `ui/fight/intent_arrows.gd` (from `BattleReadout`) | Enemy intents and the player's choice, with numbers, KO marks, changed marks. |
| Telegraph | `ui/fight/fight_telegraph.gd` `FightTelegraph` | Owns the `IntentTracker` and choice preview; intent text ("charging Overload, then -> Ace (15)"). |
| Timeline bar | `ui/fight/timeline_bar.gd` | `Fight.upcoming()` chips; shows the AFTER order of a previewed choice and slides chips. |
| Unit cards | `ui/fight/unit_panel.gd`, `status_row.gd`, `preview_bar.gd` (hp and energy slices), `unit_detail.gd` | |
| Presentation | `ui/fight/battle_presenter.gd`, `battle_beat.gd`, `skill_fx.gd`, `outcome_banner.gd` | Reads `FightEvent`s. |
| Tuning | `ui/fight/fight_screen_tuning.gd` + `data/ui/*`, `data/feel/battle_readout.json` | |
| Tests | `tests/ui/fight/` | Need a display (xvfb) for input. |

---

## 2. Sessions S1 to S6

Status key: **exists** (extend it), **partial** (some of the job is done),
**new**.

### S1 · Data model

| Plan name | This repo | Status |
|---|---|---|
| `ActionDef` | `fight/combat_skill.gd` `CombatSkill`, extended in place. Definitions move from `combat_tuning.json` `skills` to a new `data/combat/actions.json`, still read by `CombatTuning` (or a small `fight/actions/action_table.gd`). | partial |
| ActionDef fields | Add: `recovery` (gauge, default 0), `hit_count` (default 1), `damage_type` (default `""`), `tags` (`Array[String]`), `applies_status` (status id, default `""`), `payoff_condition` + `payoff_bonus_percent`. Keep `energy_cost`, `power_percent` (= damage per hit), `effect`, `target`, rank bonuses. | new fields |
| `StatusDef` | New `fight/status/status_def.gd` + `data/combat/statuses.json` (effect, stacks, expiry rule, consumed_by). Guard stays a `Combatant` field until S3/S4 decide whether it becomes a status. | new |
| `EnemyArchetypeDef` | New `fight/enemy_archetype.gd` + `data/combat/archetypes.json`; an `enemy_tables.json` entry may name an `"archetype"`. Plating, intent pattern, per-turn scaling. `EnemyTable.validate()` checks the reference. | new |
| Active-skill slots | `bot_data/bot_tuning.gd` + `data/bot_data/tuning.json` `active_skill_slots` (default 4, `TODO(decision: skill-slots)`). Unused until S15. | new |
| Generation band | `bot_data/bot.gd`: exported `skill_level_band` (`Vector2i`, min..max rank) with a default that changes nothing; generation itself stays `Personality.generation`. Defaults in `data/bot_data/tuning.json`. Old `.tres` saves load with the defaults (exported fields with defaults need no `GrowthSaveUpgrade` step; add one only if a default must depend on old data). | new |
| Migrate actions | Move the 8 skills into `actions.json` with identical numbers. | — |
| Tests | `tests/fight/combat_data_test.gd` (exists: extend), new `tests/fight/status/status_def_test.gd`, `tests/fight/enemy_archetype_test.gd`, `tests/bot_data/bot_tuning_test.gd` (extend). | |

Notes for S1:
- **Done-when must include `scripts/golden_check.sh` showing no difference.** S1 changes no behaviour.
- The bot-skill to combat-skill mapping is written twice (`bot_skill_effects`
  in `combat_tuning.json`, `combat_skill_effects` in `post_fight.json`). S1
  may leave it; folding it into one `action_id` on `Skill` would change the
  save format, so it is a separate, explained step if anyone wants it.
- `ActionDef` belongs in `fight/`, not `bot_data/` (see conflict C4).
- Everything else that reads skills (`IntentPlanner`, `BattleReadout`,
  `BattleMath`, `SkillNumbers`, `SkillRanks.apply`, `ui/common/skill_card.gd`,
  tools) keeps working because the class name stays `CombatSkill`.

### S2 · Timeline costs and wait

| Plan name | This repo | Status |
|---|---|---|
| Recovery pushes the bot back | `Combatant.finish_action(threshold)` → spend `threshold + skill.recovery`. The gauge clamp at 0 (`maxi(0, ...)`) must allow negative gauge (debt), or recovery needs its own field. With recovery 0 nothing changes. | new rule on an existing seam |
| `delay(unit, amount)`, `advance(unit, amount)`, knockback | New methods on `fight/timeline.gd` `Timeline` (or `Combatant`), raising new `FightEvent` kinds. `ElasticityRules.after_hit` already writes `target.gauge` directly for `resist_knockback`: route it through the new knockback call. | partial (knockback exists inside ElasticityRules) |
| Wait banks bonus charge | `fight/variants/wait_rules.gd`. `d-wait` `banked` (the default) already banks faster energy recharge while waiting; `extra_energy` grants energy at the start. If "charge" means gauge rather than energy, add a `d-wait` option (`bonus_gauge`), do not replace the switch. `TODO(decision: d-wait)`. | partial |
| `project_turns(state, action, n)` | `FightPreview.preview_choice()` already submits a hypothetical action on a `FightCopy` and returns `order_after` (`copy.upcoming(n)`). Add `FightPreview.project_turns(fight, action, n)` as a thin wrapper on that, not new machinery. `Timeline.preview()` assumes every later action costs zero recovery; S2 must decide what recovery to assume for other units' future actions (their current intent's skill is the natural answer; say so in the PR). | partial |
| Tests | `tests/fight/timeline_test.gd`, `wait_test.gd`, `atb_loop_test.gd` (extend); new projection-accuracy test next to `tests/fight/preview/preview_matches_resolution_test.gd`. | |

Watch: the default `speed-range = compressed` already gives slow units a
damage bonus for lost tempo (`SpeedRules.power_bonus_percent`). Heavy actions
with long recovery would be "slow" twice. Note it in the PR and in the
questions file; do not change SpeedRules in S2.

### S3 · Statuses and combos

| Plan name | This repo | Status |
|---|---|---|
| StatusManager | New `fight/status/status_manager.gd`, owned by `Fight`, state per `Combatant` (`statuses: Array` of instances). Driven by timeline events: "until the target's next action" hooks into `Fight.submit()` (actor about to act) and `Combatant.finish_action`. | new |
| Damage pipeline with ordered modifiers | Replace the inline formula in `fight/damage_rules.gd` `DamageRules.damage()` / `damage_to()` with an ordered pipeline (new `fight/damage_pipeline.gd` or inside DamageRules) that also returns a breakdown. Fold in today's modifiers in today's order: wait bonus, weakest bonus, speed bonus, pierce, defense, min damage, elasticity, guard. Then Exposed and the payoff bonus. **Make `ui/fight/battle_math.gd` read the breakdown** instead of its own `_raw_damage`. | partial (formula exists, no pipeline) |
| Exposed, applied by Shred, consumed by next hit | `data/combat/statuses.json` `exposed`; new action `shred` in `actions.json` (multi-hit, `applies_status: exposed`). | new |
| Heavy payoff vs Exposed | `payoff_condition` / `payoff_bonus_percent` on the heavy action. The plan's "Heavy Shot" is today's `heavy_strike` (bot name "Overcharge Shot"). Adding the payoff to `heavy_strike` changes nothing until something applies Exposed, so goldens stay identical. | new |
| Status events | New `FightEvent.Kind` values (`STATUS_APPLIED`, `STATUS_CONSUMED`, `STATUS_EXPIRED`). | new |
| Preview | Copy statuses in `Combatant.clone_for_preview()` and `FightCopy`. `ChoicePreview` gains status changes beside `guard_changes`. | must extend |
| Tests | New `tests/fight/status/`; extend `damage_rules_test.gd`, `fight_events_test.gd`, `preview_matches_resolution_test.gd` (add a scenario that uses Shred). | |

### S4 · Brace, plating, Stagger

| Plan name | This repo | Status |
|---|---|---|
| Brace | **A `brace` skill already exists** (`combat_tuning.json`: guard, self, 2 energy, blocks 50% of the next hit; bot skill effect `guard_self`; Mega/Ultra reflect). The plan's Brace absorbs up to a Defense-scaled amount **until the bot's next action**. Rework the existing `brace` action rather than adding a second one: a new effect (`absorb`, or a `brace` status from S3) with the value from Defense and expiry on the bot's next action. See conflict C5. | exists, different rule |
| Guard Ally | `shield` ("Shield Ally", `guard_ally`) stays a percent guard until S11 decides Guard Ally. | exists |
| Plating pips | `EnemyArchetypeDef.plating` (S1) → `Combatant.plating` at fight start; each hit removes 1, a matching `damage_type` removes 2. Damage types exist only as the S1 field, so "matching" has nothing to match until S13; S4 tests it with a test-only type. | new |
| Stagger | Plating at 0 → cancel intent, knockback (S2 API), damage bonus (pipeline step from S3). **Intents are not stored in the fight today** (see 1.4), so "cancel the intent" needs a committed intent on `Combatant`; either S4 adds a `staggered` flag that `IntentPlanner` and `IntentFightPolicy` read, and S5 builds committed intents on it, or S5 owns cancellation. Recommend: S4 adds the flag and the events; S5 makes intents committed. | new |
| Plating recovery rule | `data/combat/archetypes.json` (or `combat_tuning.json` `plating`). | new |
| Elasticity | Plan default: Stagger recovery speed. Add it as a new `d-elasticity` option (`stagger_recovery`), keep `none` the default until decided. `TODO(decision: d-elasticity)`. | partial (switch exists) |
| Intent planner | `IntentPlanner` does not plan guards ("no enemy has one yet"); enemies with Brace need it. Its damage estimate must count Brace absorb the way the fight resolves it (today it counts `guard_percent`). | must extend |
| Post-fight | `post_fight.json` `drift_rules` names `brace` and `shield` for the defensive push; keep the ids. | — |
| Tests | Extend `tests/fight/damage_rules_test.gd`; new `tests/fight/brace_test.gd`, `plating_test.gd`; the reflect bonus test in `skill_rank_bonus_test.gd` must be revisited if Brace stops being a percent guard. | |

S4 is the first session that changes an existing skill's behaviour, so it
changes golden output. See conflict C2.

### S5 · First enemy archetypes and intent

| Plan name | This repo | Status |
|---|---|---|
| Charger, Plated, Scaler | Entries in `data/combat/archetypes.json` plus new enemies in `data/combat/enemy_tables.json` that are **in no pool and no faction** (like the demo bosses), so runs and goldens do not change until a later session puts them in pools. | new |
| Telegraphed wind-up | Needs a committed intent: new `Combatant.intent` (or a `Fight.intents` map) set when the plan is made and kept until the unit acts or is Staggered. Today `IntentFightPolicy` re-plans each turn. Charger's wind-up maps naturally onto today's WAIT intent ("charging Overload, then -> Ace"), which already telegraphs a big hit. | partial |
| Re-plan on Stagger / state change | `IntentTracker.refresh()` already compares plans and records `IntentRevision` with a reason; move the "changed" detection into the fight as an `INTENT_CHANGED` `FightEvent` so preview and logs see it. | partial |
| Scaler grows each turn | A status (S3) or archetype rule applied at the unit's turn start. | new |
| Good vs greedy test fights | `fight/scripted_fight_policy.gd` for the good line, `simple_fight_policy.gd` for greedy, on `tools/fixed_enemy_table.gd`. Tests in `tests/fight/archetypes/`. | partial (tools exist) |

### S6 · Combat event log and action tags

| Plan name | This repo | Status |
|---|---|---|
| One log | `fight/fight_event.gd` becomes the log: add `Fight.events` (every event, in order) beside `last_events`. Derive `log_lines`, `action_tags` and `decision_tags` from it, or at least make sure every rule raises an event. | partial |
| Action tags (offense, defense, setup, payoff, self, ally, reactive, banked) | **Extend `fight/post_fight/action_tag.gd` `ActionTag`**, which already labels each decision (`hit_enemy`, `self_target`, `ally_target`, `wait`, `solo`, `first_affordable`). Add the new labels from action `tags` (S1) and events. Do not build a second tagger. Consider moving `action_tag.gd` to `fight/` (it is built by `Fight.submit()`, so it is in-fight code living in `post_fight/`). | partial |
| Fight summary | New `fight/fight_summary.gd`: actions used, HP and capacity lost, statuses applied, combos landed. `tools/simulated_fight.gd` already counts damage per unit; `Fight.result()` already has grid cost. | new |
| Replayable | Fights replay from request + seed + the decision list (deterministic today); `tools/run_replay.gd` already replays whole runs. The test: replay the decisions and compare `Fight.events`. | partial |
| Tests | `tests/fight/fight_events_test.gd`, `tests/fight/post_fight/action_tag_test.gd` (extend), new summary test. | |

Adding log lines for existing actions changes golden output; adding events
does not, unless the capture dumps them (it dumps `last_events`). Keep new log
lines to new event kinds where possible.

---

## 3. Sessions S7 to S17

| Session | Touches | Status and what already exists |
|---|---|---|
| S7 Preview and timeline UI | `ui/fight/focus_card.gd`, `battle_math.gd`, `intent_arrows.gd`, `timeline_bar.gd`, `status_row.gd`, `unit_panel.gd`, `preview_bar.gd`, `fight_telegraph.gd`; reads `fight/preview/`. | **Mostly exists.** Hover preview of damage and cost (focus card, target marks, hp and energy slices), the AFTER timeline order, intent-changed marks with slide animation, `?` for unknown values (`PreviewValue`). New: plating pips, status icons with expiry on the timeline, Brace value, conditional combo text ("36 if Rook acts first"), projected own slot (from S2). Add status icons to `data/ui/icons.json` and `StatusRow.IDS`. |
| S8 Simulation harness | `fight/headless_fight_runner.gd`, policies in `fight/`, `tools/batch_simulator.gd`, `tools/batch_sim.gd`, `tools/simulated_fight.gd`, `tools/fight_stats_log.gd`, `tools/fight_scenario.gd`. | **Partial.** Runner, seeded policies, Random, Scripted, scenarios, batch CLI, JSON-lines log, `CliOptions` all exist. New: `fight/greedy_fight_policy.gd` (highest real damage via `DamageRules`/preview, not `power_percent`), `fight/smart_fight_policy.gd` (ScriptedSmart), CSV output, action-share and combo columns (from the S6 summary), a policy-comparison table. Extend `batch_sim.gd` with `--policies` and `--csv` rather than a new CLI; register the new policy names in `FightScenario`. |
| S9 Sandbox scenario | `data/scenarios/sandbox_3v3.json` (scenario builder format), new bots inline, enemies from S5; a fight demo `data/demo/sandbox_fight.json` if it should open from the menu. Debug panel: extend `ui/dev/debug_overlay.gd` with action-use share. | Scenario format, builder and overlay exist. The scenario format has no per-bot skill list override beyond inline bots with `skills`; inline bots can carry Basic, Shred, Heavy, Brace (Wait is always available). |
| S9b Battle debug simulator | New `ui/dev/battle_debugger/`; reads and edits `fight/` state and data. | **New.** Builds on `debug_overlay.gd` (read-only today), the switchboard, `FightCopy` (a snapshot), and determinism: rewind = replay request + seed + decisions to step N. "Save to data" writes JSON (see C1), with a diff. Gate with `OS.has_feature("editor")` or a custom feature tag in export presets. |
| S10 Playtest and tune | `data/combat/*.json`, maybe new switch options. | Process. Re-run S8 and `tools/balance_sim.gd`. |
| S11 Disruption | `fight/status/`, `actions.json`, `archetypes.json`; Delay uses S2's API; Taunt and Guard Ally touch `IntentPlanner` target choice and the existing `shield`. Energy drain touches `Combatant.energy_milli`. | New on S2 to S5 pieces. Decide Brace + Guard Ally stacking (decisions table). |
| S12 Follow-ups | Marked status; follow-up hook in `Fight._hit` that queues free hits; Power Transfer as Charged status. | New. Follow-ups are extra actions inside one decision: preview and the S6 log must show them. |
| S13 Elemental reactions | `damage_type` on actions; augments. | **Augments do not exist** (`bot_data/augment_slot.gd` is an empty slot). S13 needs an augment catalog (`data/bot_data/augments.json`), equip rules, and augments reaching the fight through `SquadMemberSummary` (a contracts change, its own PR). Plan S13 as two or three PRs, or descope to action damage types first. |
| S14 Overdraw | `Combatant.can_afford` / `spend` (allow negative energy), long recovery (S2). | New. `check_action` refuses unaffordable skills today. |
| S15 Generation caps, slots, upgrades | `bot_data/` (bands, slot limit, cost curve in `data/bot_data/`), `fight/post_fight/skill_progress.gd` (stop ranks at the band top), offer flow. | **Skill offers do not exist**, so "replace-or-skip at full slots" needs an offer system first (pick from a small set after a fight; the design calls it Hades-style). Upgrades spend Material and Energy, which live in `campaign/`, which may not import `bot_data/` (see C7). Build the screens as minimal `ui/dev/` panels first, as the plan says. |
| S16 Wear and lineage | `bot_data/` (fatigue, overhaul, lineage), payload offspring, `tools/campaign_autoplay.gd` / `loss_report.gd` for the run-level harness. | **New.** Closest existing: `hp-carryover` (HP between fights). Payload today only starts the boss fight; producing offspring is new campaign + bot_data + ui/run work. |
| S17 Personality from action tags | `data/post_fight/post_fight.json` `drift_rules`, `fight/post_fight/personality_drift.gd`, `ActionTag`. | **Mostly exists**: tags, the data-driven mapping, tally per fight and apply once at the end are built. S17 adds the S6 labels to `drift_rules` and feeds drift into offer weighting, which needs S15's offers. |

---

## 4. Layer check

### 4.1 The plan's three layers in this repo

| Plan layer | Repo folders |
|---|---|
| Bot data (bottom, pure state) | `contracts/` (UnitStats, SquadMemberSummary, FightRequest, FightResult), `bot_data/` (Bot, Skill, Personality, AugmentSlot, BotSquad, BotTuning, BotFactory) |
| In-fight (middle) | `fight/` core: `fight.gd`, `combatant.gd`, `timeline.gd`, `damage_rules.gd`, `combat_skill.gd`, `combat_tuning.gd`, `squad_skills.gd`, `enemy_table.gd`, `faction_table.gd`, `fight_event.gd`, `commands/`, `intent/`, `preview/`, `variants/` (except `hp_carryover.gd`), the policies, `headless_fight_runner.gd` |
| Metagame (top, between fights) | `campaign/` (map, time, pressure, run state, payload countdown); in `fight/`: `post_fight/` (growth), `fight_aftermath.gd`, `variants/hp_carryover.gd`, `odds/`, `auto_fight_service.gd` (service adapter); in `ui/`: `ui/run/` (RunFlow, RunFightService), `ui/draft/` |
| Outside the three | `lib/` (generic helpers), `ui/` (screens, may import all), `tools/` (dev tools), `data/` (no code), `tests/`, `addons/` |

This repo's rules are stricter than the plan's in one way (campaign/ may not
import bot_data/ or fight/ until the integration step; it talks through
contracts/) and looser in another (growth code, which the plan calls
metagame, lives in fight/post_fight/ because it needs fight types). Both are
enforced by `tests/architecture/layer_rules.gd`.

### 4.2 Current imports against "combat never imports campaign or generations code"

- **No violations in code.** `fight/` imports only `contracts/`, `lib/`,
  `bot_data/`, `data/`, and the architecture test enforces it. The only
  mention of campaign code is a comment in `fight/odds/odds_estimator.gd`
  ("`Campaign.odds_label()`").
- **No generations code exists**, so nothing imports it.

Borderline cases to keep in view:

1. **Campaign geography in fight data.** `data/combat/factions.json` maps act
   ids to region ids; `FactionTable.act_of()`, `DifficultyRules` (scaling by
   act and territory id) and `FightRequest.territory_id` mean fight code knows
   what an act and a region are. Allowed (it is data), but it is metagame
   knowledge inside combat. No action needed for the rework.
2. **Generation read by combat.** `Personality.generation` (bot_data) decides
   which personality scales `fight/intent/intent_weights.gd` weighs
   (`Personality.is_active()`). Combat reads a generation-derived answer from
   bot data, which the plan allows (bot data is the bottom layer). Rule for
   S15/S16: keep generation logic behind bot_data accessors like
   `is_active()` and put lineage/payload code where `fight/` core never names
   it (see C7).
3. **In-fight code in a metagame folder.** `Fight.submit()` builds
   `ActionTag` from `fight/post_fight/action_tag.gd`. Direction is fine (same
   layer folder), but the plan's S6 makes tags an in-fight concern; moving the
   file to `fight/` in S6 removes the oddity.
4. **Progression in the fight core.** `CombatTuning.skill_at()` applies
   `SkillRanks` (rank → power and bonuses) when units are built. A rank is a
   bot property, so this is bot data flowing down, not a violation.

---

## 5. Conflicts between the plan and the repo

### C1 · Tuning format: `.tres` Resources vs JSON in `data/`

The plan (ground rule 2, S1, S9b) puts tuning in Godot Resources (`.tres`).
This repo keeps every tunable in `data/` as hand-edited JSON read through
`lib/json_file.gd` (`JsonFile.read_object_cached`) by a typed loader class with
`from_dict()` and `validate()` (`CombatTuning`, `EnemyTable`, `SkillRanks`,
`PostFightTuning`, about 25 of them).

**Recommendation: keep JSON in `data/`. Read the plan's "Resource" as "a data
file in `data/` plus a typed loader class in the owning layer".** So
`ActionDef` = a typed class built from `data/combat/actions.json`, `StatusDef`
from `statuses.json`, `EnemyArchetypeDef` from `archetypes.json`. Reasons:
every loader, test fixture, switchboard param override (`VariantSet` params
are applied to JSON-loaded tuning), golden dump and dev tool already works
this way; JSON diffs read well in PRs; S9b's "Save to data" can write JSON
with a readable diff as easily as `.tres`. Resources stay for **state** that is
saved (Bot, Skill, Personality, BotSquad, SkillUseLedger), as today.
Mark `TODO(decision: tuning-format)` in S1's loader.

### C2 · The golden check will change on purpose

`scripts/golden_check.sh` diffs fixed-seed output of the working tree against
a fresh checkout of a base ref. No golden files are stored, so there is
nothing to "regenerate": the base is always whatever `main` was.

**Recommendation:**
1. **Tag the pre-rework baseline** once this PR merges: `git tag
   combat-rework-base <merge commit>` and push it (the owner does this, or the
   S1 session). Any session can then run `scripts/golden_check.sh
   combat-rework-base` to see the total drift since the rework began, next to
   the per-PR check against `origin/main`.
2. **Every rework PR runs `scripts/golden_check.sh` against `origin/main` and
   reports the result in a "Golden check" section of the PR**: either
   "identical", or the list of changed captures (file names from the diff)
   with one line each saying why. An unexplained diff is a bug.
3. **Keep diffs small by construction:** S1 must be identical. New rules land
   on new content first (new actions, statuses, archetypes and enemies that no
   pool, faction, draft or demo uses), so S2, S3 and S5 can stay identical
   while their own tests prove the rules. A change to existing behaviour
   (recovery on existing skills, the Brace rework in S4, putting new enemies
   in pools) is its own commit, explained in the PR.
4. **Where a change to existing behaviour is a design bet, put it behind a
   `FightVariants` switch** (as `speed-range` and `strike-cost` were), with
   the old rule as the default until S10 flips it. The switchboard and
   `tools/compare_variants.gd` then compare old and new on the same seeds for
   free. Do not do this for every rule; only where S10 needs the comparison.
5. Add the sandbox scenario (S9) to `tests/golden/golden_capture.gd` so the
   new rules get pinned too.

### C3 · Open questions file

Ground rule 7 says sessions add open questions to the plan doc; sessions
cannot edit it. **Resolution:** `docs/design/combat-rework-questions.md` (added
in this PR). Sessions append there; the owner copies them into the live doc.

### C4 · Where ActionDef, StatusDef and EnemyArchetypeDef live

The plan puts the three defs "in the bot-data layer". In this repo
`bot_data/skill.gd` says outright that it holds no combat meaning ("fight/
reads effect_id and decides what the skill does"), combat skill definitions
live in `fight/` (`CombatSkill`, `combat_tuning.json`), and enemies live in
`fight/` (`EnemyTable`). `bot_data/` may not import `fight/`.

**Recommendation:** all three defs live in `fight/`, data in `data/combat/`.
`bot_data/` gains only what is bot state (skill slots, generation band). A bot
names its actions through `Skill.effect_id` as today. The dev builders in
`ui/` can import `fight/`, so S9b can edit the defs.

### C5 · Brace already exists, with a different rule

Today's Brace (`brace`, effect guard) blocks 50% of the next hit and clears on
that hit; ranks add reflect. The plan's Brace absorbs a Defense-scaled amount
until the bot's next action.

**Recommendation:** S4 reworks the existing `brace` action (same id, so bot
skills, the drift rules and rank bonuses keep pointing at it) to the plan's
rule, and keeps `shield` (Shield Ally) as the percent guard until S11. Decide
in S4 whether Brace's Mega/Ultra reflect bonus survives. This changes golden
output (drafted bots hold Brace): report it per C2, or put it behind a
`brace-rule` switch if S10 should compare the two.

### C6 · Existing switch defaults vs the plan's action table

| Plan says | Repo default today | Recommendation |
|---|---|---|
| Basic shot costs 0 energy and banks a little | `strike-cost = costs`: Strike costs 1 energy (`TODO(decision: strike-cost)`) | Leave the switch; S2 or S10 decides. List it in the questions file. |
| Heavy actions cost time (recovery) | `speed-range = compressed` already pays slow units back in damage | S2 notes the overlap; S10 tunes. |
| Wait banks bonus charge | `d-wait = banked` banks faster energy recharge | Read "charge" as energy unless told otherwise; a gauge bonus would be a new `d-wait` option. |
| Elasticity = Stagger recovery | `d-elasticity = none` (three other options exist) | New option, default unchanged until decided. |

### C7 · Phase 4 crosses a layer line

Upgrades (S15) and lineage at payload (S16) spend Material and Energy
(`campaign/`) on bots (`bot_data/`). `campaign/` may import only
`contracts/`, `lib/` and `data/` "until the integration step", and nothing
outside `ui/` may import `ui/`.

**Recommendation:** pure rules go in `bot_data/` (band per generation, cap
step, cost of step n from `data/bot_data/`, building an offspring from a
parent, like `BotFactory`); the run spends resources through a new contract
(for example an `UpgradeService` or an extension of `SquadProvider`), which is
its own PR per CLAUDE.md; `ui/run/` wires them. Decide before S15 whether this
is the "integration step" that lets `campaign/` import `bot_data/`; if so,
change `ALLOWED` in `tests/architecture/layer_rules.gd` and CLAUDE.md in the
same PR.

### C8 · Things the plan assumes that do not exist yet

| Assumed | Reality | Who handles it |
|---|---|---|
| Scenario and robot builders that edit tuning ("the scenario and robot builders can edit") | Builders exist (`ui/dev/bot_builder.gd`, `scenario_builder.gd`) but edit only bots (stats, catalog skills) and scenarios, not action, status or enemy definitions | S9b's inspector is the first tuning editor; until then, edit JSON |
| Skill offers ("a full-slot offer forces a choice", "feed drift into skill-offer weighting") | None | S15 builds a minimal offer flow first |
| Augments ("depends on how augments are currently equipped") | Empty slots only | S13 builds them, or is split |
| Generations, lineage, payload offspring | Only `Personality.generation` and the countdown | S15, S16 (minimal `ui/dev/` panels first) |
| A single combat event log | Three logs, events per action only | S6 |
| Committed enemy intents that can be cancelled | Intents are re-planned each turn, outside the fight | S4 flag + S5 |
| Damage types | None | S1 field, S13 meaning |
| "Material and Energy" upgrade currency | Exists in `campaign/` | S15, via C7 |

### C9 · Smaller clashes

- **Data paths.** The plan says nothing about where data lives; follow this
  repo: `data/combat/` for combat, `data/bot_data/` for bots,
  `data/post_fight/` for growth, `data/scenarios/` for harness scenarios.
- **Ground rule 4 (GUT fallback).** gdUnit4 runs headless here
  (`scripts/run_tests.sh`, CI); GUT is not needed.
- **Ground rule 6 (preview reads a copy).** Already true (`FightCopy`); the
  risk is new state that `FightCopy` forgets to copy, caught by
  `preview_matches_resolution_test.gd` only if a test fight uses the state.
- **Two UI flags vs statuses.** "Charging" and "Waiting" are UI words for wait
  state. When S3 adds real statuses, keep wait state out of the status manager
  (it is timeline state) or the timeline and the status icons will disagree.
- **Stale README.** `data/scenarios/README.md` says bots' own skills do not
  drive fights; they do. Fix it when S9 touches the file.

---

## 6. Open questions

1. Is "bonus charge" from Wait energy (today's `banked`) or gauge? (S2)
2. What recovery should `project_turns` assume for other units' future actions?
   Recommend: their current intent's skill. (S2)
3. Should recovery and `speed-range = compressed`'s slow-unit damage bonus
   both stay? They pay for the same thing. (S2, S10)
4. Does Strike cost energy (`strike-cost = costs`) or 0 with a small energy
   bank, as the plan's table says? (S2, S10)
5. Does today's Brace rank bonus (reflect at Mega and Ultra) survive the Brace
   rework? (S4)
6. Should Guard become a status in the S3 status manager, or stay a field
   until S11's Guard Ally? (S3, S4)
7. Who owns intent cancellation: S4 (a `staggered` flag) or S5 (committed
   intents)? Recommend both, as in section 2. (S4, S5)
8. Do the new archetype enemies go into faction pools in Phase 1, or stay out
   of runs until S10 passes? Recommend: out until S10. (S5)
9. Should the bot-skill/combat-skill double mapping (`bot_skill_effects`,
   `combat_skill_effects`) be folded into one action id on `Skill`? It is a
   save-format change. (S1 or later)
10. Is S15/S16 the "integration step" that lets `campaign/` import
    `bot_data/`, or do upgrades go through a new contract? (S15, see C7)
11. Is S13 allowed to build the augment system, or should it ship typed
    action damage only? (S13)
12. Where do skill offers come from in a run (after each fight, at payload, on
    the map)? Needed by S15 and S17.

### The plan's "Decisions to settle" table, with what the code implies

| Decision | Needed before | Plan default | What the code implies today |
|---|---|---|---|
| Exact wait bonus | S2 | Banked charge | `d-wait = banked` already banks **energy** (+100% recharge while waiting); `extra_energy` and `bonus_damage` are the other options. The default matches if "charge" means energy. Existing id: `TODO(decision: d-wait)`; also `d-wait-length = snap`. |
| Active skills per bot | S1 | 4, enforced in S15 | No limit; drafted bots start with `starting_skill_count` skills (data/bot_data/tuning.json), plus Strike added in the fight. Decide whether Strike and Wait count against the 4 (recommend: no). |
| What Elasticity governs | S4 | Stagger recovery speed | `d-elasticity` switch exists, default `none`, with `reduce_big_hits`, `resist_knockback`, `energy_when_hit`. Add `stagger_recovery` as a fourth option; `resist_knockback` is close (it resists gauge knockback, which Stagger uses). Existing id: `TODO(decision: d-elasticity)`. |
| Brace stacks with Guard Ally? | S11 | No; the larger applies | Today's guards already take the larger value (`maxi(target.guard_percent, ...)` in `Fight._resolve_skill`), so "larger applies" matches current behaviour. |
| Generation cap visible from start? | S15 | Yes | No caps exist. The post-fight readout already shows generation pips, a natural place for the cap. |
| Wear per fight or only after heavy damage? | S16 | Only after heavy damage | No wear. `hp-carryover` (full_heal default, carry, partial_heal) is the nearest existing rule and could carry the threshold. |
| Retired bots recallable? | S16 | No | No lineage code. |
| Accept tag-to-personality mapping? | S17 | Yes, as data | Already data: `drift_rules` in `data/post_fight/post_fight.json`, `TODO(decision: d-personality-map)`. The deep dive's mapping is close to today's (`hit_enemy`→aggressive, brace/shield→defensive, `ally_target`→supportive, `solo`→solitary, `wait`→methodical, `first_affordable`→reactive); S17 adds setup/payoff/banked labels. |

New decision ids proposed for the rework (use these in `TODO(decision: ...)`):
`tuning-format`, `skill-slots`, `recovery-projection`, `brace-rule`,
`stagger-intent`, `archetype-pools`, `upgrade-layer`.
