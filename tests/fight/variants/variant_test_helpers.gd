extends RefCounted
## Builders shared by the variant tests.

const H := preload("res://tests/fight/fight_test_helpers.gd")


## The default combat tuning with `option` chosen for `decision`.
static func tuning_with(decision: String, option: String) -> CombatTuning:
	var v := FightVariants.defaults()
	assert(v.choose(decision, option), "%s has no option %s" % [decision, option])
	return CombatTuning.load_default().with_variants(v)


## Ally (fast, battery 10) against a foe too slow to act during the test.
static func slow_foe_fight(tuning: CombatTuning) -> Fight:
	return H.duel(H.stats(50, 5, 0, 50, 10), H.stats(50, 1, 0, 1, 10), tuning)
