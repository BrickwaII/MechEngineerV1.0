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
| 19 | S4 | Answers 5: does Brace keep its Mega/Ultra reflect? | Owner decided (Nov 2, brace-rule): no. Brace absorbs Defense x power% until the bot's next action; the reflect bonus is gone from skill_ranks.json. Shield Ally keeps its reflect and percent guard until S11 | Answered; `brace-rule` | data/combat/skill_ranks.json, fight/fight.gd | |
| 20 | S4 | Answers 7: how does S4 cancel an intent with no committed intents? | A Staggered unit (`Combatant.staggered`) has no intent (`IntentPlanner` gives none), its wait is cancelled, and its next turn is spent recovering (`Fight.advance()` resolves it, no decision). S5 may turn the lost turn into "cancel and re-plan" once intents are committed | Lost turn; `stagger-intent` | fight/fight.gd `_stagger`, `_recover` | |
| 21 | S4 | Answers 16 in part: Stagger is a `Combatant` flag, not a statuses.json status. Should it become an S3 status, so `payoff_condition: staggered` works? | Payoffs against Staggered need it; today every hit on a Staggered unit gets the flat `stagger.damage_bonus_percent` instead | Flag; `stagger-status` | fight/combatant.gd, fight/stagger_rules.gd | |
| 22 | S4 | Elasticity: switch to the plan's default, Stagger recovery speed? | Added as `d-elasticity` option `stagger_recovery` (cuts the Stagger knockback by elasticity x 10%, at most 60%). Default stays `none` | `none`; `d-elasticity` | data/variants/variants.json | |
| 23 | S4 | Brace absorb is 100% of Defense (Brace power_percent 100), applied after a percent guard. Right size and order? | A Defense 6 bot absorbs 6: about one enemy Strike. Old Brace blocked 50% of one hit | First guess; tune in S10. Brace + Guard Ally stacking stays with S11 | data/combat/actions.json | |
| 24 | S4 | Plating recovery: all of it comes back when the Stagger ends (`recover_percent` 100), none regrows otherwise. Should plating regrow over time, or come back only in part? | The Plated archetype's difficulty (S5) | Full on recovery; `stagger.recover_percent` | data/combat/combat_tuning.json `stagger` | |
| 25 | S4 | A Brace may absorb a hit down to 0 damage, below `min_damage`. Intended? | "Absorbs damage up to a value" reads as a hard soak | Yes, 0 allowed | fight/damage_rules.gd `braced()` | |
| 26 | S4 | Five shipped enemies list `brace` but `IntentPlanner` never plans Brace or guards. Should S5's Charger answer, or enemies Brace before a big player hit? | Brace on enemies is dead weight today, as Brace-as-guard was | Not planned (unchanged) | fight/intent/intent_planner.gd | |
| 27 | S4 | A Stagger's lost turn is not a decision: no action_count, no ActionTag, does not count toward `max_actions`. Should the S6 log and summary count it? | Fight length and tags | Not counted; RECOVER event only | fight/fight.gd `_recover` | |
| 28 | S4 | Stagger knockback clamps at an empty gauge (`Timeline.knockback`). S2 allows gauge debt: should knockback push into debt too? | A unit that just acted loses nothing to a Stagger today | Clamp at 0 until S2's timeline API replaces it | fight/timeline.gd | |
