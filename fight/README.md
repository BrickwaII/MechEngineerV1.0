# fight/

Layer 2. Combat, energy, intent, preview, post-fight. May import bot_data and contracts.

Combat core (M2), pure logic with no scenes:
- `Fight`: one fight in ATB wait mode. `advance()` runs time until a unit is
  ready, `submit()` resolves its action. `upcoming(n)` previews the order.
- `Timeline`: gauge-based turn order. `Combatant`: per-unit hp, energy, gauge.
- `DamageRules`: deterministic damage and healing, the entry points. Every
  hit is worked out by `DamagePipeline.run()`, a fixed list of steps (power,
  defense, floor, status, payoff, elasticity, guard; `STEPS`) that returns a
  `DamageBreakdown`; `DamagePipeline.hits()` lands each hit of a multi-hit
  skill in turn. The fight, the intent planner, the preview and
  ui/fight/battle_math.gd all read it. `CombatTuning`,
  `EnemyTable`: read data/combat/. A skill with `"effect": "heal"` (Repair,
  Patch Up) restores attack x power% / 100 hp to a living ally, capped at what
  it lost; `"effect": "guard"` (Shield Ally) blocks power% of the target's
  next hit; `"effect": "absorb"` (Brace) absorbs up to Defense x power% / 100
  damage, over any number of hits, until the target's next action
  (`Combatant.brace_absorb`; BRACE and BRACE_END events); `"target":
  "all_opponents"` (Arc Sweep) hits every enemy. An action lands `hit_count`
  hits.
- Plating and Stagger (S4): an enemy whose archetype has `plating` loses a
  pip per hit (two for its `plating_weakness` damage type). At zero it is
  Staggered: wait cancelled, knocked back (`Timeline.knockback`), hits on it
  deal a bonus, and its next turn is spent recovering (`Fight.advance()`
  resolves it, no decision). Numbers: `combat_tuning.json` `stagger`
  (`StaggerRules`). Events PLATING, STAGGER, RECOVER.
- Combat rework definitions (S1; docs/combat-rework-map.md).
  - Actions (the plan's ActionDef) are `CombatSkill`s, defined in
    `data/combat/actions.json` and read by `actions/ActionTable`;
    `CombatTuning.skills` holds a fresh copy of the table. Besides cost, power,
    effect and target each action has `recovery` (S2), `hit_count`,
    `applies_status`, `payoff_condition` + `payoff_bonus_percent` (S3),
    `tags` (S6) and `damage_type` (S13), with no-op defaults. Fights read
    `hit_count`, `applies_status` and the payoff (S3).
    `CombatSkill.copy_definition()` copies them; level and rank copies use it.
  - `status/StatusDef` + `StatusTable` (data/combat/statuses.json): effect,
    amount, max_stacks, expiry, consumed_by. Holds `exposed`, applied by
    `shred` (catalog only; no draft, enemy or demo uses it yet).
  - Statuses in a fight (S3): `status/StatusManager` (`Fight.statuses`)
    applies, consumes and expires them; the state is `Combatant.statuses`
    (`StatusInstance`), copied by `clone_for_preview()`. "Until the holder's
    next action" ends at `StatusManager.on_unit_acts()`, which `Fight` calls
    as a unit's skill or wait begins. Events: `FightEvent.Kind`
    STATUS_APPLIED, STATUS_CONSUMED, STATUS_EXPIRED; `ChoicePreview`
    `status_changes`. Guard stays `Combatant.guard_percent`; wait state is not
    a status.
  - `EnemyArchetype` (the plan's EnemyArchetypeDef) + `EnemyArchetypeTable`
    (data/combat/archetypes.json: Charger, Plated, Scaler since S5): plating,
    intent_pattern, scaling_percent_per_action, wind_up_opponent_actions. An
    enemy-table entry may name one with `"archetype"`; `EnemyTable.validate()`
    checks the name.
  - `ArchetypeRules` (S5): what an archetype does in a fight. The state is on
    `Combatant` (`archetype`, `pattern_step`, `committed`, `telegraph_wait`,
    `base_stats`, `growth`, `intent`), copied by `clone_for_preview()`.
    `IntentPlanner.rank()` narrows an archetype unit's options to its pattern
    step; a wind_up step's wait commits the hit it telegraphs (the Charger's
    Ram), held until an opponent has acted; a Stagger cancels it and restarts
    the pattern; a Scaler grows each decision (GROWTH event). After every
    decision and recovery `Fight` re-plans archetype enemies with
    `Fight.planner()` and raises INTENT_CHANGED (old and new intent, reason)
    for each that changed. Enemies without an archetype are unchanged.
- `SquadSkills`: a squad member fights with its own skills. Each bot skill's
  effect_id picks a combat skill (`bot_skill_effects` in combat_tuning.json);
  the bot's name and level carry over. With named ranks (skill-progression =
  ranks, the default; `SkillRanks`, data/combat/skill_ranks.json) a level is a
  rank: Beam, Beam +1..+5, Mega Beam, Mega Beam +1..+5, Ultra Beam; tiers add
  a power jump and a bonus (pierce, weakest bonus, heal guard, reflect). With
  flat_levels each level above 1 adds `power_percent_per_level`. Every bot
  keeps the basic attack (Strike).
  Enemies keep their enemy-table skills. Read a unit's skills with
  `Combatant.skill(id)`, not `CombatTuning.skill(id)`.
- `TimelineOps`: timeline moves other rules call (combat rework S2):
  `delay()`, `advance()`, `knockback()` and `recover()` (an action's
  `recovery` pushes its user back after the action lands). Amounts are raw
  gauge; `turn_gauge(percent_of_turn, tuning)` converts data's percent of a
  turn. Gauge may go below 0 (a debt). Each move raises a `FightEvent`
  (RECOVERY, DELAY, ADVANCE, KNOCKBACK). `FightPreview.project_turns()`
  lists the next turns for a hypothetical action, played forward on a copy.
- `variants/`: the fight side of the variant switchboard. `FightVariants`
  reads this layer's switches from `data/variants/variants.json` (plus the
  player's choices in `user://variants.json`); `CombatTuning.variants` holds
  them for a fight. `WaitRules` (d-wait, d-wait-length), `ElasticityRules`
  (d-elasticity), `HpCarryover` (hp-carryover), `SpeedRules` (speed-range:
  turn charge and the slow units' damage bonus), `EnergyRules` (strike-cost:
  the recharge that goes with Strike's cost, which lives in actions.json, and
  the retired free Strike kept for comparisons) and `DifficultyRules` (difficulty-curve: tier
  per act and level, enemy counts, act and tier scaling) implement the options;
  d-personality-map picks a drift rule set and tag-weight and
  skill-progression their options in `PostFightTuning`.
- `FactionTable`: enemy factions (data/combat/factions.json, M7 P4). Which
  faction holds each region, by act; the tier enemies field by act and
  defense level; which unit types join at which level. `EnemyTable.pick_for()`
  draws a fight's enemies from the territory's faction, or from the generic
  level pools for territories outside every act and under the enemy-factions
  switch's `generic` option. `EnemyTable.sprite_of()` names the manifest
  sprite of an enemy. The map reads a region's faction with
  `FactionTable.faction_for_region(region_id)` (region ids are unique across
  acts), its name, color and icon with `faction_name()`, `faction_color()` and
  `faction_icon()`.
- `PatientFightPolicy`: waits for its strongest attack; batch runs use it so
  the wait options show.
- `HeadlessFightRunner`: plays a fight from a seed and policies, with a text log.
- `AutoFightService`: a contracts FightService built on the runner.
- `FightAftermath`: what a run does to its bots when a fight ends (PostFight,
  then HP by hp-carryover), shared by the game's RunFightService and the
  headless replay (tools/run_replay.gd) so both apply the same rules.
- `CarefulFightPolicy`: a squad policy that uses the rework's verbs (answer
  a wind-up with Shred or Brace, Heavy Strike an Exposed or Staggered enemy,
  Shred plating, Shred when an ally's payoff comes before the Exposed wears
  off, Wait for Heavy Strike when Strike barely scratches). Battle Mode's
  careful player; `SmartFightPolicy` builds on it.
- `GreedyFightPolicy` (S8): the deep dive's greedy bot. The affordable damage
  action that takes the most HP off the opponents now, tried on a FightCopy
  with the real rules (hit counts, Exposed, payoff, Stagger, guard, Brace,
  overkill). Never Braces or sets up.
- `SmartFightPolicy` (S8): the harness's scripted-smart player. The careful
  rules, plus a Brace against any big telegraphed hit aimed at the bot (a
  share of its HP set in data/combat/smart_policy.json, read by
  `SmartPolicyTuning`), and the greedy policy as its fallback. The harness
  (tools/policy_comparison.gd) compares it with greedy and random.
- `battle_mode/`: Battle Mode (S9c), fight after fight with growth carried
  forward and no map. `BattleModeRun` draws each encounter from the curve in
  data/battle_mode/ (`BattleEncounterPicker`, fought through
  `BattleEnemyTable`), applies `FightAftermath` after each fight, and records
  the fun metrics (`BattleFightRecorder`: turns, HP lost, energy spent and
  wasted, action-use share, combos, Staggers). See its README.
- `odds/`: honest map odds. `OddsEstimator` plays N seeded headless
  auto-fights (AutoFightService's policies) of the squad against the
  territory's own enemy draw and returns a win rate and its label;
  `OddsTuning` reads N and the label bands from `data/combat/odds.json`.
  Deterministic for a run seed, territory and squad; never replays the real
  fight's seed. `begin()`/`Job.step()` spread an estimate over frames. The
  switchboard's odds-model picks it ("simulated") or the map's old formula.

Preview readouts (R1-B), in preview/:
- `ChoicePreview` also carries `energy_after` (the cost paid), and, once time
  runs to the next decision on the copy, `intents_after`, `order_after` and
  `fight_after`: what the screen will telegraph next. `intent_changes` compare
  against that next decision.
- `BattleReadout` / `ArrowBadge`: the number on each arrow (enemy intents per
  target, the pending unit's own choice), KO marks, the energy after a skill,
  and the turn order a choice would leave. Damage is the hp that leaves the
  bar (capped at the target's hp).
