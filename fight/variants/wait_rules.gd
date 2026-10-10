class_name WaitRules
extends RefCounted
## What waiting gives, by the d-wait and d-wait-length switches
## (FightVariants). Every rule is deterministic.
##
## d-wait, the bonus a wait gives:
##   banked        energy recharges faster while waiting, by
##                 CombatTuning.wait_recharge_bonus_percent (the default)
##   extra_energy  normal recharge; starting a wait grants extra_energy_points
##   bonus_damage  normal recharge; the damage skill that ends the wait deals
##                 bonus_damage_percent more
## d-wait-length, when a wait ends:
##   snap          on the first tick the unit can afford its skill (the default)
##   exact         after the exact number of ticks the wait names, if it names
##                 one (FightAction.wait_ticks); a wait naming none snaps


## Recharge per tick while waiting, for a unit whose normal recharge is
## `recharge_milli`.
@warning_ignore("integer_division")
static func wait_recharge_milli(recharge_milli: int, tuning: CombatTuning) -> int:
	if tuning.variants.is_chosen(FightVariants.WAIT_FORM, FightVariants.WAIT_BANKED):
		return recharge_milli * (100 + tuning.wait_recharge_bonus_percent) / 100
	return recharge_milli


## Energy granted the moment `unit` starts a wait, in thousandths.
static func start_bonus_milli(tuning: CombatTuning) -> int:
	if tuning.variants.is_chosen(FightVariants.WAIT_FORM, FightVariants.WAIT_EXTRA_ENERGY):
		return maxi(0, tuning.variants.param_int(FightVariants.WAIT_FORM, "extra_energy_points")) * Combatant.MILLI
	return 0


## Extra damage, in percent, for a damage skill used on the turn that ends a
## wait (`after_wait`). 0 otherwise.
static func damage_bonus_percent(after_wait: bool, tuning: CombatTuning) -> int:
	if after_wait and tuning.variants.is_chosen(FightVariants.WAIT_FORM, FightVariants.WAIT_BONUS_DAMAGE):
		return maxi(0, tuning.variants.param_int(FightVariants.WAIT_FORM, "bonus_damage_percent"))
	return 0


static func exact_waits_allowed(tuning: CombatTuning) -> bool:
	return tuning.variants.is_chosen(FightVariants.WAIT_LENGTH, FightVariants.WAIT_LENGTH_EXACT)


static func max_wait_ticks(tuning: CombatTuning) -> int:
	return tuning.variants.param_int(FightVariants.WAIT_LENGTH, "max_wait_ticks")


## Why a wait of exactly `ticks` is refused, or "" when it is allowed.
## 0 ticks means a snapping wait, always allowed.
static func check_wait_ticks(ticks: int, tuning: CombatTuning) -> String:
	if ticks == 0:
		return ""
	if not exact_waits_allowed(tuning):
		return "exact waits are off (d-wait-length is snap)"
	if ticks < 1 or ticks > max_wait_ticks(tuning):
		return "a wait lasts 1 to %d ticks" % max_wait_ticks(tuning)
	return ""
