# Mech Engineer — Combat Rework Code Plan

Nov 2, 2026 · @Henry Greenhut

## Overview

The rework runs as 19 Claude Code sessions in four phases, building the [Combat & Leveling Deep Dive](https://claude.ai/artifact/DFwzCELCYtU4zaiNpdxTP4) into the game. The order is set by one rule: **prove combat is fun before building leveling on top of it.** Bounded growth and personality hookup come last because leveling built on one-button combat would inherit the problem.

| Phase | Sessions | Goal | Exit check |
| --- | --- | --- | --- |
| 1. Combat foundation | S0–S6 | Data model, time costs, combos, Brace, plating, first 3 enemies | All new systems pass gdUnit4 tests headless |
| 2. Prove it's fun | S7–S10 | Preview UI, simulation harness, sandbox fight, tuning | Greedy-bot test fails for the greedy bot; no action above \~50% use |
| 3. Expand the kit | S11–S14 | Disruption, follow-ups, elemental reactions, Overdraw | Tests still pass after each addition |
| 4. Growth and personality | S15–S17 | Generation caps, upgrades, wear, lineage, action-tag mapping | A maxed Gen 1 bot measurably falls behind the Act 3 curve |

**How to use a session brief.** Each session below has a goal, what it depends on, its scope, a "done when" check, and a short prompt to paste into Claude Code. Every prompt assumes the session first reads the main design doc, this plan and the deep dive. Module and file names are suggestions; S0 maps them onto the actual repo, and later briefs should follow S0's map.

**Parallelism.** After S1 lands, S2, S3 and S4 can run in parallel worktrees, since they touch separate modules. Phase 2's UI and harness sessions can also run side by side. The session map below shows which can overlap.

## Ground rules for every session

These apply to every session and belong at the top of each prompt, or in the repo's CLAUDE.md so they load automatically.

1. **Respect the layers.** Bot data (bottom) holds pure state. In-fight systems (middle) read and mutate it. Metagame (top) runs between fights. Dependencies flow downward only. Combat code never imports campaign or generations code.
2. **Tuning lives in data, not code.** Damage, energy cost, recovery, status durations, the Exposed multiplier and plating counts all go in Godot Resources (`.tres`) the scenario and robot builders can edit. No magic numbers in combat logic.
3. **Resolution is deterministic.** No random dodge (settled). Any randomness takes a seeded RNG passed in, so the simulation harness can replay fights exactly.
4. **Every rule gets a gdUnit4 test that runs headless.** A status, a combo, a timeline cost: each ships with a test proving it. GUT is the fallback only if gdUnit4 can't run headless.
5. **Combat emits events.** Every action, status applied or consumed, Stagger and damage instance goes through one combat event log. The preview, the harness, personality tagging and the post-fight flourishes all read from it.
6. **Preview is a read-only consumer.** It simulates on a copy of state and never mutates the live fight.
7. **One session, one scope.** Each session ends with tests green, a short summary in the PR, and any new open questions added to this doc. If a session finds the brief is wrong, it stops and reports rather than redesigning.

## Session map

&#91;embedded content: session map · 18 sessions, 4 phases\]

S10 is the gate: nothing in Phases 3 or 4 starts until the sandbox passes its fun checks.

## Phase 1 — Combat foundation

### S0 · Audit and map

- **Depends on:** nothing
- **Scope:** read-only. Map current combat code onto the three layers; find where actions, energy, the ATB timeline, intents and preview live; list what's missing for this plan. Write a repo map to a doc in the repo that later sessions read.
- **Done when:** the map names a concrete file or module for every system in S1–S6, and flags anything that violates the layer rules.

```
Read the design doc, the combat deep dive and this plan. Don't change code.
Map the existing combat code to the bot-data / in-fight / metagame layers.
Write docs/combat-rework-map.md: where each system lives today, what S1-S6
will touch, and any layer violations. End with open questions.
```

### S1 · Data model

- **Depends on:** S0
- **Scope:** Resources for `ActionDef` (energy cost, recovery, hit count, damage per hit, damage type, tags, applies-status, payoff-condition and bonus), `StatusDef` (effect, stacks, expiry rule, consumed-by), `EnemyArchetypeDef` (plating, intent pattern, scaling). Bot data gains active-skill slots and generation-band fields now, unused until Phase 4. Migrate existing actions into the new format.
- **Done when:** existing fights run unchanged on the new data, and tests load every Resource.

```
Implement S1 from the code plan. Add ActionDef, StatusDef and
EnemyArchetypeDef Resources in the bot-data layer, migrate current actions,
and add (unused) skill-slot and generation-band fields to bot data.
No behavior changes. gdUnit4 tests for loading and validation.
```

### S2 · Timeline costs and wait

- **Depends on:** S1 (parallel with S3, S4)
- **Scope:** each action's recovery value pushes the bot back on the ATB timeline. Add timeline operations other systems call: delay(unit, amount), advance(unit, amount), knockback for Stagger. Rework Wait to bank bonus charge (current lean). Add a projection function returning the next N turns for a hypothetical action.
- **Done when:** tests show a Heavy action yields fewer turns over a fixed span than Light actions, and the projection matches what actually happens.

```
Implement S2. Add per-action recovery to the ATB timeline, delay/advance/
knockback operations, Wait banking bonus charge, and project_turns(state,
action, n) on a copy of state. Tests: recovery ordering, projection accuracy.
```

### S3 · Statuses and combos

- **Depends on:** S1 (parallel with S2, S4)
- **Scope:** a status manager that applies, ticks and expires statuses using timeline events ("until the target's next action"), and a damage pipeline where modifiers stack in a fixed order. First status: Exposed (+50% from the next hit, consumed on hit). First payoff: Heavy attacks get a bonus against Exposed. Emit status events to the combat log.
- **Done when:** tests prove Exposed then Heavy beats two Heavies on damage per energy, and Exposed expires correctly if the enemy acts first.

```
Implement S3. StatusManager driven by timeline events; a damage pipeline
with ordered modifiers; Exposed applied by Shred and consumed by the next
hit; Heavy payoff bonus vs Exposed. Log events. Tests for apply, consume,
expiry-before-payoff and the damage comparison.
```

### S4 · Brace, plating and Stagger

- **Depends on:** S1 (parallel with S2, S3; Stagger knockback wires to S2 once merged)
- **Scope:** Brace absorbs damage up to a Defense-based value until the bot's next action. Enemy plating: each hit removes one pip, a matching damage type removes two. At zero: Stagger cancels the intent, knocks the enemy back and applies a damage bonus. Plating recovery rule in data.
- **Done when:** tests show a multi-hit action Staggers a plated enemy that a single Heavy hit doesn't, and Brace expires on the bot's next action.

```
Implement S4. Brace (absorb until next action, scaled by Defense), plating
pips, Stagger (cancel intent, knockback via timeline API, damage bonus).
Tests for multi-hit vs single-hit on plating and Brace expiry.
```

### S5 · First enemy archetypes and intent

- **Depends on:** S2, S3, S4
- **Scope:** Charger (telegraphed wind-up hit), Plated, Scaler (grows each turn) built from EnemyArchetypeDef. Intent AI reads state and re-plans when Staggered or when the situation changes, emitting an intent-changed event so preview can show the shift.
- **Done when:** each archetype has a test fight where the "right" answer beats the greedy answer.

```
Implement S5. Charger, Plated and Scaler archetypes as data plus intent
logic that re-plans on Stagger or state change and emits intent_changed.
One scripted test fight per archetype comparing good vs greedy play.
```

### S6 · Combat event log and action tags

- **Depends on:** S2–S5
- **Scope:** consolidate all events into one log with action tags (offense, defense, setup, payoff, self, ally, reactive, banked). Add a fight summary object at end of fight: actions used, HP and capacity lost, statuses applied, combos landed. This is what the harness, personality and post-fight presentation consume later.
- **Done when:** a test fight produces a complete, replayable log and summary.

## Phase 2 — Prove it's fun

### S7 · Preview and timeline UI

- **Depends on:** S6 (parallel with S8)
- **Scope:** the UI/input layer only. When hovering an action, show its damage, energy cost and where the bot lands on the timeline afterward. Show combo bonuses conditionally ("18 damage, 36 if Rook acts first"). Show plating pips, status icons with their expiry marked on the timeline, Brace values, and intent changes animating rather than silently swapping. Unknown outcomes show as question marks (settled).
- **Done when:** you can play the sandbox fight from the screen alone, without reading logs to know what will happen.

```
Implement S7 in the UI layer only. Action hover preview: damage, cost,
projected timeline slot, conditional combo bonus. Plating pips, status
icons with expiry on the timeline, Brace value, animated intent changes.
Preview must read from a state copy, never mutate the fight.
```

### S8 · Simulation harness

- **Depends on:** S6 (parallel with S7)
- **Scope:** a headless fight runner that plays scenarios with pluggable policies: Greedy (highest damage affordable), Scripted-smart (uses setups, Brace on big intents, breaks plating), Random. Runs N seeded fights and writes CSV: win rate, bot HP lost, capacity drained, fight length, action-use shares, combos landed. Add a CLI entry point so it runs from Claude Code.
- **Done when:** one command produces a comparison table for the sandbox scenario.

```
Implement S8. Headless fight runner with Greedy, ScriptedSmart and Random
policies, seeded runs, CSV output (HP lost, capacity, length, action share,
combos). Command-line entry point. Tests for determinism with a fixed seed.
```

### S9 · Sandbox scenario

- **Depends on:** S5, S7
- **Scope:** in the scenario builder, define the 3-bot vs. Charger + Plated + Scaler sandbox from the deep dive's test plan, with each bot carrying Basic, Shred, Heavy Shot, Brace and Wait. Add a debug-mode panel showing live action-use share.
- **Done when:** the scenario loads from the builder and the harness can run it.

### S9b · Battle debug simulator

A dev-only mode inside a live battle for tuning by experimentation: click anything, change it, and see the effect immediately. It extends the developer debug mode already planned in the tooling domain.

- **Depends on:** S1 (data Resources), S7 (preview), S8 (harness)
- **Scope:**
  - **Inspect and edit units.** Click any bot or enemy to open an inspector: HP, Attack, Defense, Speed, Elasticity, Battery, current energy, statuses, plating, personality values. Every field is editable mid-fight.
  - **Inspect and edit moves.** Click any action to edit its definition: energy cost, recovery, damage per hit, hit count, damage type, status applied, payoff bonus. Enemy intents and AI parameters are editable too.
  - **Live recalculation.** Edits apply to the running fight at once; the preview, timeline and intents refresh so you see the consequence before acting.
  - **Time controls.** Pause, step one action at a time, rewind to any earlier action (snapshots per action, possible because resolution is deterministic), and restart with the same seed.
  - **Force states.** Apply or remove a status, set plating, move a unit on the timeline, force an enemy's next intent, add or remove units.
  - **Measure from here.** A "Simulate 100" button runs the S8 harness on the current edited setup and shows greedy vs. smart results and action-use shares in a panel.
  - **Keep what works.** Edits are session-only by default. A change log lists every tweak; "Save to data" writes chosen changes back to their `.tres` Resources after showing a diff, and "Export tuning diff" writes a file you can hand to a later session.
  - **Dev builds only.** Gated behind a feature tag so it never ships in release exports. Lives in the UI/tools layer and edits data through the same Resources as the builders.
- **Done when:** mid-fight, you can change Heavy Shot's recovery, watch the timeline preview update, rewind a turn to try both values, run 100 simulations on the edited version, and save the winner to its Resource.
- **Size note:** if this proves large, split it: inspector and live edit first, then rewind, simulate and save.

```
Implement S9b, a dev-only battle debug simulator. Click any unit or action
to open an editable inspector (stats, energy, statuses, plating,
personality; ActionDef fields; enemy intent/AI params). Edits apply live
and refresh preview, timeline and intents. Add pause, step, rewind via
per-action snapshots, same-seed restart, force-status/intent/timeline
controls, a Simulate 100 button using the S8 harness, a change log, and
Save to data (.tres, with diff) / Export tuning diff. Gate behind a
dev feature tag. Tests: rewind restores exact state; saved edits reload.
```

### S10 · Playtest and tune (you + Claude)

- **Depends on:** S7, S8, S9, S9b
- **Scope:** play the sandbox in the S9b debug simulator, tweak values live, run the harness, and save what works back to data. Repeat until the Phase 2 exit checks pass:
  - [ ] Greedy policy loses clearly more HP and capacity than Scripted-smart
  - [ ] No action above about 50% use in typical fights
  - [ ] Most turns had two options you genuinely weighed
  - [ ] Clean vs. careless play differ clearly in cost even when both win
- **Done when:** the checks pass. If they won't pass by tuning alone, stop and revisit the design before Phase 3.

## Phase 3 — Expand the kit

Add one mechanic per session, each with a new enemy that asks for it, and re-run the S10 checks after each. If a new mechanic becomes the new dominant button, tune or cut it before the next session.

| Session | Adds | New enemy that asks for it | Depends on |
| --- | --- | --- | --- |
| S11 · Disruption | EMP (drain enemy energy), Delay, Jammed status, Taunt / Guard Ally | Overclocker (fast, low HP); Medic (focus-fire target) | S10 |
| S12 · Follow-ups | Marked status; Follow-up skills that fire when an ally hits a Marked target; Power Transfer (Charged ally) | Swarm (many small threats) | S10 |
| S13 · Elemental reactions | Typed augment damage; Overheated status; Thermal Shock reaction (Overheated + ice); matching types strip 2 plating | Reflector (punishes multi-hit spam) | S10, augment system |
| S14 · Overdraw | Spend past battery capacity for a burst, then a long stall | Drainer (attacks battery) | S10 |

S11, S12 and S14 touch separate statuses and actions and can run in parallel. S13 depends on how augments are currently equipped, so check S0's map first.

```
Implement S1x from the code plan: add <mechanic> as data plus the minimum
logic, add <enemy> as an EnemyArchetypeDef, extend the harness's
ScriptedSmart policy to use the new verb, and re-run the sandbox and the
new enemy's scenario. Report action-use shares before and after.
```

## Phase 4 — Bounded growth and personality

These sessions touch the bot-data and metagame layers. If S0 found the generations or upgrade screens don't exist yet, build them as minimal debug-mode panels first and leave final UI for later.

### S15 · Generation caps, slots and upgrade costs

- **Depends on:** S10 (can start after Phase 2, in parallel with Phase 3)
- **Scope:** enforce generation bands on skill levels and stats (Gen 1 skills cap at 5; inherited bands such as 3–7). Enforce the active-skill slot limit, so a new skill offer at full slots becomes a replace-or-skip choice. Add chassis upgrades that raise one bot's cap a step or add a slot, priced in Material and Energy from a rising cost curve in data.
- **Done when:** tests show a bot can't level past its band, a full-slot offer forces a choice, and each upgrade step costs more than the last.

```
Implement S15. Enforce generation bands and the active-skill slot limit in
bot data; replace-or-skip flow for offers at full slots; chassis upgrade
with a data-driven rising cost curve. Tests for cap, slots and cost growth.
```

### S16 · Wear and lineage

- **Depends on:** S15
- **Scope:** persistent fatigue from heavy use lowers max durability until overhauled (overhaul costs resources). Retire-into-lineage: a retired bot's crystallized traits and raised skill caps feed its offspring at the next payload. Extend the harness with a run simulation that plays a capped Gen 1 squad against the act curve.
- **Done when:** the harness shows a maxed Gen 1 squad handling Act 1, struggling in Act 2 elites and falling behind in Act 3, and a Gen 2 squad recovering the gap.

```
Implement S16. Fatigue and overhaul in bot data; retire-into-lineage
feeding offspring at payload; a run-level harness mode comparing Gen 1 and
Gen 2 squads across act difficulty. Report the power gap per act.
```

### S17 · Personality from action tags

- **Depends on:** S6 tags, S10
- **Scope:** map S6's action tags onto the three axes using the deep dive's proposed mapping (offense vs. defense; self vs. ally; reactive vs. banked/setup). Tally over the fight and apply once at the end (settled). Feed the drift into skill-offer weighting. Show the shifts in the post-fight results.
- **Done when:** harness runs with different policies produce visibly different personality drift, and skill offers shift accordingly.

```
Implement S17. Map action tags to the three personality axes (mapping in
data), tally per fight, apply at fight end, feed offer weighting. Harness:
show drift per policy. Tests for the tally and application timing.
```

## Decisions to settle along the way

Each of these is needed before the listed session starts. The deep dive's proposals are the defaults if no decision is made.

| Decision | Needed before | Default if undecided |
| --- | --- | --- |
| Exact wait bonus (banked charge vs. something else) | S2 | Banked charge (current lean) |
| How many active skills per bot | S1 | 4 slots, enforced in S15 |
| What Elasticity governs | S4 | Stagger recovery speed |
| Does Brace stack with Guard Ally? | S11 | No; the larger value applies |
| Is a bot's generation cap visible from the start? | S15 | Yes |
| Wear per fight, or only after heavy damage? | S16 | Only after heavy damage |
| Can retired bots be recalled from lineage? | S16 | No, retirement is permanent |
| Accept the proposed tag-to-personality mapping? | S17 | Yes, as data so it can change |

When a session settles one of these, update this table and the main design doc.
