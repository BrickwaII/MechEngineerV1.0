# fight/post_fight/

M5: what a bot learns from a fight. Pure logic, headless-tested in tests/fight/post_fight/.

- `ActionTag`: one record per decision, kept in order on `Fight.decision_tags`
  (a small hook in fight/fight.gd). Carries actor, skill, target, damage, energy,
  tick and behaviour labels (hit_enemy, self_target, ally_target, wait, solo,
  first_affordable).
- `PersonalityDrift`: tallies labels into pole pushes using the rules in
  data/post_fight/post_fight.json and applies the net shift once, after the
  fight. TODO(decision: d-personality-map).
- `SkillProgress` + `SkillUseLedger`: skill uses toward levels; leftover uses
  bank in the ledger across fights.
- `PostFight.apply(fight, bots, ledger) -> PostFightReport`: the one entry point.
  The readout is ui/post_fight/post_fight_readout.gd.
