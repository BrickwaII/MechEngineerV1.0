# Combat rework: open questions from sessions

Sessions cannot edit the live plan doc (ground rule 7), so they add their open
questions here. The owner copies them into the live Combat Rework Code Plan
and marks them copied.

How to add one: append a row under your session. Give the question, why it
blocks or matters, the default you used (with its `TODO(decision: <id>)`),
and the file it lives in. Do not edit other sessions' rows; answer a question
by adding a row that says so.

| # | Session | Question | Why it matters | Default used / TODO id | Where | Copied |
|---|---|---|---|---|---|---|
| 1 | S0 | Is Wait's "bonus charge" energy (today's `d-wait = banked`) or timeline gauge? | Decides whether S2 changes the wait rule or keeps it | Energy; `d-wait` | fight/variants/wait_rules.gd | |
| 2 | S0 | What recovery does `project_turns` assume for other units' future actions? | The projection is only exact if it knows | Their current intent's skill; `recovery-projection` | fight/preview/fight_preview.gd | |
| 3 | S0 | Keep both action recovery and `speed-range = compressed`'s slow-unit damage bonus? | Both pay for lost tempo | Keep both until S10; `speed-range` | fight/variants/speed_rules.gd | |
| 4 | S0 | Does Strike cost 1 energy (`strike-cost = costs`) or 0 with a small energy bank, as the plan's action table says? | Sets the floor of every turn | Today's default (costs); `strike-cost` | fight/variants/energy_rules.gd | |
| 5 | S0 | Does Brace keep its Mega/Ultra reflect bonus after the S4 rework? | Rank bonuses are in data/combat/skill_ranks.json | Decide in S4; `brace-rule` | data/combat/skill_ranks.json | |
| 6 | S0 | Should Guard become a status in the S3 status manager, or stay a Combatant field until S11? | Shield Ally and heal-guard use it | Stay a field; S3/S4 decide | fight/combatant.gd | |
| 7 | S0 | Who owns intent cancellation on Stagger: S4 (a flag) or S5 (committed intents)? | Intents are not stored in the fight today | S4 flag, S5 commits; `stagger-intent` | fight/intent/ | |
| 8 | S0 | Do the new archetype enemies join faction pools in Phase 1? | Joining changes every run and the golden output | No, not until S10 passes; `archetype-pools` | data/combat/enemy_tables.json | |
| 9 | S0 | Fold `bot_skill_effects` and `combat_skill_effects` into one action id on `Skill`? | Save-format change | Leave as is | data/combat/combat_tuning.json, data/post_fight/post_fight.json | |
| 10 | S0 | Is S15/S16 the "integration step" that lets campaign/ import bot_data/, or do upgrades go through a new contract? | Layer rule in CLAUDE.md | New contract; `upgrade-layer` | tests/architecture/layer_rules.gd | |
| 11 | S0 | May S13 build the augment system, or ship typed action damage only? | Augments are empty slots today | Ask before S13 | bot_data/augment_slot.gd | |
| 12 | S0 | Where do skill offers come from in a run (after each fight, at payload, on the map)? | S15 and S17 need offers; none exist | Ask before S15 | — | |
| 13 | S0 | Tuning in `.tres` Resources or JSON in data/? | Ground rule 2 vs CLAUDE.md | JSON + typed loader; `tuning-format` | docs/combat-rework-map.md C1 | |
| 14 | S0 | Do Strike and Wait count against the active-skill slot limit? | Sets what "4 slots" means | No | data/bot_data/tuning.json | |
| 15 | S1 | What unit is an action's `recovery` in: gauge on `action_threshold`'s scale (100), or the switch-scaled turn threshold (`speed-range = compressed` multiplies it by `gauge_scale`, 10)? | The same number means 10x more delay under one reading | Field documented as `action_threshold` units; S2 decides and scales; `recovery-projection` | fight/combat_skill.gd | |
| 16 | S1 | `payoff_condition` names a status the target must hold. Is Stagger a status (so "big damage against Staggered" is `payoff_condition: staggered`), or does the payoff need a second kind of condition? | S3 and S4 both touch it | Status id only; S4 decides | fight/combat_skill.gd | |
| 17 | S1 | Enemy intent patterns use the steps `plan`, `wind_up` and action ids. Enough for the Charger, Plated and Scaler? | S5 builds on it | Those three; S5 may add steps | fight/enemy_archetype.gd | |
| 18 | S1 | The design's "Gen 1 skills reach level 5" predates named ranks (base to Ultra, 13 ranks). Is the band in ranks, and where does Gen 1's top sit? | S15 caps by it | Band stored in ranks, open (no ceiling) by default | data/bot_data/tuning.json `starting_skill_level_band` | |
| 19 | S3 | Do drafted bots (or the skill offers of S15) get Shred now, or only after S9's sandbox? | Giving it to drafts changes every run and the golden output | Catalog only: no bot skill maps to it, no enemy holds it; `shred-in-drafts` | data/combat/actions.json | |
| 20 | S3 | Do Exposed and the payoff add to each other (+50% and +50% = +100%) or multiply (x1.5 x1.5 = x2.25), and do they come before or after the defense subtraction? | Sets how big a combo is | Multiply, in DamagePipeline order: after defense and the floor, before elasticity and guard; Heavy Strike's payoff_bonus_percent 50 is a first guess; `status-stacking` | fight/damage_pipeline.gd | |
| 21 | S3 | Does a Wait count as the holder's "next action" for statuses that end then? | A waiting enemy could otherwise keep Exposed through its whole charge | Yes: any decision (skill or wait) ends them; `status-expiry-wait` | fight/fight.gd `_on_unit_acts` | |
| 22 | S3 | When should a multi-hit action's status go on: after its last hit (so its own hits do not use it up) or after the first? | Shred's own second hit would otherwise eat the Exposed it just applied | After all its hits, on each target still up | fight/fight.gd `_resolve_skill` | |
| 27 | S2 | Answers 1 (`d-wait`). | The brief | **Answered per the S2 brief:** Wait's bonus charge is energy, today's `d-wait = banked`. No new option. Wait is free, always available, and has no recovery. | fight/variants/wait_rules.gd | |
| 28 | S2 | Answers 2 (`recovery-projection`). | `project_turns` needs every later decision | **Answered as S0 recommended:** `FightPreview.project_turns()` plays the copy forward with `IntentFightPolicy` for every unit, so it uses each unit's current intent (the caller may pass another policy). It is exact when the fight is played by that policy. `Timeline.preview()` / `Fight.upcoming()` (the battle screen's `order_after`) still assume no recovery for later actions; S7 should show `project_turns`. | fight/preview/fight_preview.gd | |
| 29 | S2 | Answers 15 (recovery units). | Same number, 10x apart | **Answered:** `recovery` is in percent of a turn (`action_threshold` units, 100 = one whole turn), scaled to the turn threshold by `TimelineOps.turn_gauge()`, so it means the same under both speed rules. Other rules' delay and knockback amounts in data should use the same units. | fight/timeline_ops.gd | |
| 30 | S2 | What does a delay or knockback do to a **waiting** unit? A wait holds a full gauge and ends on energy (snap) or ticks (exact), not on gauge. | S4 knocks back Chargers, whose wind-up may be a wait (S5); S11 Delay | Held (`Combatant.held_delay`) and paid when the unit next finishes an action: the wait itself is neither shortened nor lengthened. `advance()` cannot shorten a wait. `TODO(decision: wait-delay)` | fight/timeline_ops.gd | |
| 31 | S2 | Should `d-elasticity = resist_knockback` move onto `TimelineOps.knockback()`? | Its knockback floors at 0 and lands mid-wait; S2's may push into debt and is held during a wait. Moving it changes that option's golden fights. | Left as it was (no event, floored at 0); `d-elasticity` | fight/variants/elasticity_rules.gd | |
| 32 | S2 | Recovery values on the existing actions are first guesses: heavy_strike 30, overload 50, arc_sweep 20, the rest 0 (short). Right sizes? | Sets how much Heavy costs in time beside `speed-range`'s slow-unit bonus | Those values, behind the `action-recovery` switch (default `by_action`, `none` the old rule) so S10 can compare | data/combat/actions.json | |
