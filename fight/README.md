# fight/

Layer 2. Combat, energy, intent, preview, post-fight. May import bot_data and contracts.

Combat core (M2), pure logic with no scenes:
- `Fight`: one fight in ATB wait mode. `advance()` runs time until a unit is
  ready, `submit()` resolves its action. `upcoming(n)` previews the order.
- `Timeline`: gauge-based turn order. `Combatant`: per-unit hp, energy, gauge.
- `DamageRules`: deterministic damage and healing. `CombatTuning`,
  `EnemyTable`: read data/combat/. A skill with `"effect": "heal"` (Repair,
  Patch Up) restores attack x power% / 100 hp to a living ally, capped at what
  it lost; `"effect": "guard"` (Brace, Shield Ally) blocks power% of the
  target's next hit; `"target": "all_opponents"` (Arc Sweep) hits every enemy.
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
- `variants/`: the fight side of the variant switchboard. `FightVariants`
  reads this layer's switches from `data/variants/variants.json` (plus the
  player's choices in `user://variants.json`); `CombatTuning.variants` holds
  them for a fight. `WaitRules` (d-wait, d-wait-length), `ElasticityRules`
  (d-elasticity) and `HpCarryover` (hp-carryover) implement the options;
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
