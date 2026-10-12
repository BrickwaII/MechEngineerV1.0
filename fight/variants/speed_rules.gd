class_name SpeedRules
extends RefCounted
## How speed turns into turn order and power, by the speed-range switch
## (FightVariants). Every rule is deterministic.
##
##   wide        gauge per tick = speed, threshold = action_threshold (the old
##               rule: speed 3 to 11 acts about 3.7 times as often at the top)
##   compressed  speed_low..speed_high maps linearly onto charge_low..charge_high
##               gauge per tick (clamped), and the threshold is
##               action_threshold x gauge_scale, so the fastest unit acts at
##               most charge_high / charge_low as often as the slowest (1.6:1
##               by default). A slower unit's damage skills hit harder:
##               slow_power_percent of the tempo it gives up comes back as power,
##               bonus% = slow_power_percent x (charge_high - charge) / charge.
##
## TODO(decision: speed-range): the compressed numbers are stand-ins (max:min
## 1.6:1, 80% of lost tempo returned as damage) until playtested.


static func compressed(tuning: CombatTuning) -> bool:
	return tuning.variants != null and tuning.variants.is_chosen(FightVariants.SPEED_RANGE, FightVariants.SPEED_COMPRESSED)


## Gauge a unit must fill before it acts.
static func threshold(tuning: CombatTuning) -> int:
	if compressed(tuning):
		return tuning.action_threshold * maxi(1, _param(tuning, "gauge_scale", 10))
	return tuning.action_threshold


## Gauge a unit with `speed` gains per tick.
static func charge_per_tick(speed: int, tuning: CombatTuning) -> int:
	if not compressed(tuning):
		return maxi(tuning.min_charge_per_tick, speed)
	var lo := _param(tuning, "speed_low", 3)
	var hi := _param(tuning, "speed_high", 11)
	var charge_lo := _param(tuning, "charge_low", 50)
	var charge_hi := _param(tuning, "charge_high", 80)
	var t := clampf(float(speed - lo) / maxf(1.0, float(hi - lo)), 0.0, 1.0)
	return maxi(tuning.min_charge_per_tick, roundi(charge_lo + t * (charge_hi - charge_lo)))


## Extra damage, in percent, for a unit with `speed`. 0 under wide.
static func power_bonus_percent(speed: int, tuning: CombatTuning) -> int:
	if not compressed(tuning):
		return 0
	var charge := charge_per_tick(speed, tuning)
	var charge_hi := _param(tuning, "charge_high", 80)
	var share := maxi(0, _param(tuning, "slow_power_percent", 80))
	return maxi(0, roundi(float(share) * (charge_hi - charge) / charge))


static func _param(tuning: CombatTuning, key: String, fallback: int) -> int:
	return tuning.variants.param_int(FightVariants.SPEED_RANGE, key, fallback)
