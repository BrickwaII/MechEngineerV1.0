# fight/post_fight/

M5: what a bot learns from a fight. Pure logic, headless-tested in tests/fight/post_fight/.

- `ActionTag`: one record per decision, kept in order on `Fight.decision_tags`
  (a small hook in fight/fight.gd). Carries actor, skill, target, damage, energy,
  tick and behaviour labels (hit_enemy, self_target, ally_target, wait, solo,
  first_affordable).
- `PersonalityDrift`: tallies labels into pushes per personality end using the
  rules in data/post_fight/post_fight.json and grows the ends once, after the
  fight. Both ends of a spectrum only grow; every spectrum grows from
  generation 1; no cap. The tag-weight switch counts a decision once
  (per_action) or by energy spent (per_energy). TODO(decision: d-personality-map).
- `SkillProgress` + `SkillUseLedger`: skill uses toward named ranks (the
  skill-progression switch's default; uses per rank rise, see
  fight/skill_ranks.gd) or flat levels; leftover uses bank in the ledger.
- `SkillNumbers`: what a skill does for a bot at a level (damage, heal, guard,
  cost, rank bonuses), for the level-up callout.
- `GrowthSaveUpgrade`: save format 1 to 2 (signed personality values split
  onto ends; flat levels become ranks no stronger).
- `PostFight.apply(fight, bots, ledger) -> PostFightReport`: the one entry point.
  The readout is ui/post_fight/post_fight_readout.gd.
