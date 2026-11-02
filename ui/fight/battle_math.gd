class_name BattleMath
extends RefCounted
## How the battle screen's numbers come about, as formula lines from the real
## values (ui/README.md rule 15): the damage on an arrow badge, the hp a
## repair restores, and when a unit acts next. The rules are the fight's
## (DamagePipeline, SpeedRules, Timeline); this only explains them.
##
##   BattleMath.damage_lines(fight, "rust_hound#1", "bolt", "bite", 6)
##   -> ["ATK 7 − DEF 4 × 50% = 5", ...] (Power, Pierce, Exposed, Payoff and
##      Guard when they matter)


## Lines explaining `amount`, the damage `from` deals `to` with `skill_id`.
## Every number is read from the fight's DamagePipeline breakdown, step by
## step in its order; nothing here redoes the math.
static func damage_lines(fight: Fight, from_id: String, to_id: String, skill_id: String, amount: int) -> Array:
	var a := fight.combatant(from_id)
	var t := fight.combatant(to_id)
	if a == null or t == null:
		return []
	var skill := a.skill(skill_id)
	if skill == null:
		return []
	var hits := DamagePipeline.hits(a, t, skill, fight.tuning)
	var b: DamageBreakdown = hits[0]
	# Terms that change nothing (Power 100%, Pierce 0%) are left out.
	var f := UiFormula.new().term("ATK", b.attack)
	if b.power_percent != 100:
		f.op("×").term("Power", "%d%%" % b.power_percent)
	if b.speed_bonus_percent > 0:
		f.op("×").term("Slow bonus", "%d%%" % (100 + b.speed_bonus_percent))
	f.op("−").term("DEF", b.defense).op("×").num("%d%%" % b.defense_percent)
	if b.pierce_percent > 0:
		f.op("×").open().num(1).op("−").term("Pierce", "%d%%" % b.pierce_percent).close()
	f.equals(b.floored)
	var out: Array = [f]
	if b.is_floored():
		out.append("At least %d: no hit does less." % b.min_damage)
	if b.status_percent > 0:
		var names := PackedStringArray()
		for id in b.status_ids:
			names.append(fight.statuses.name_of(id))
		out.append(UiFormula.new().num(b.floored).op("×").term(", ".join(names), "%d%%" % (100 + b.status_percent)).equals(b.after_status))
	if b.payoff_percent > 0:
		out.append(UiFormula.new().num(b.after_status).op("×").term("Payoff", "%d%%" % (100 + b.payoff_percent)).equals(b.after_payoff))
	if b.elasticity_changed():
		out.append("Elasticity takes it to %d." % b.before_guard)
	if b.guard_percent > 0:
		out.append(UiFormula.new().num(b.before_guard).op("×").open().num(1).op("−").term("Guard", "%d%%" % b.guard_percent).close().equals(b.final))
	var total := 0
	var parts := PackedStringArray()
	for h in hits:
		total += h.final
		parts.append(str(h.final))
	if hits.size() > 1:
		out.append("%d hits: %s = %d." % [hits.size(), " + ".join(parts), total])
	if amount != total:
		if amount == mini(total, t.hp):
			out.append("Only %d left to take: it has %d HP." % [amount, t.hp])
		else:
			out.append("With this turn's bonuses: %d." % amount)
	return out


## Lines explaining a repair of `amount` hp.
static func heal_lines(fight: Fight, from_id: String, to_id: String, skill_id: String, amount: int) -> Array:
	var a := fight.combatant(from_id)
	var t := fight.combatant(to_id)
	if a == null or t == null or a.skill(skill_id) == null:
		return []
	var skill := a.skill(skill_id)
	var power := maxi(0, a.stats.attack * skill.power_percent / 100)
	var out: Array = [UiFormula.new().term("ATK", a.stats.attack).op("×").term("Power", "%d%%" % skill.power_percent).equals(power)]
	if amount < power:
		out.append("Capped at the %d HP it has lost." % (t.max_hp - t.hp))
	return out


## Lines explaining a guard of `percent`.
static func guard_lines(fight: Fight, from_id: String, skill_id: String, percent: int) -> Array:
	var a := fight.combatant(from_id)
	if a == null or a.skill(skill_id) == null:
		return []
	return ["Guard %d%%: its next hit does %d%% less." % [percent, percent]]


## Explanation lines for an arrow badge, by its kind.
static func badge_lines(fight: Fight, badge: ArrowBadge) -> Array:
	if badge == null or not badge.amount.known:
		return ["Unknown: this action's result depends on chance."] if badge != null else []
	var n := int(badge.amount.value)
	match badge.kind:
		ArrowBadge.HEAL:
			return heal_lines(fight, badge.from_id, badge.to_id, badge.skill_id, n)
		ArrowBadge.GUARD:
			return guard_lines(fight, badge.from_id, badge.skill_id, n)
	return damage_lines(fight, badge.from_id, badge.to_id, badge.skill_id, n)


## When `unit_id` acts next, from the upcoming order: {"chip": "Now" | "2nd"
## | "-", "position": 0-based slot or -1, "ticks": ticks from now or -1,
## "tip": a line, "math": formula lines}.
static func turn(fight: Fight, unit_id: String, upcoming: Array[TimelineEntry]) -> Dictionary:
	var u := fight.combatant(unit_id)
	var out := {"chip": "-", "position": -1, "ticks": -1, "tip": "Out of the fight.", "math": []}
	if u == null or not u.is_alive():
		return out
	for i in upcoming.size():
		if upcoming[i].combatant_id == unit_id:
			out["position"] = i
			out["ticks"] = upcoming[i].tick - fight.timeline.current_tick
			break
	var threshold := fight.tuning.turn_threshold()
	var fill := u.charge_per_tick
	var pos: int = out["position"]
	if pos == 0:
		out["chip"] = "Now"
		out["tip"] = "Acts now."
	elif pos > 0:
		out["chip"] = ordinal(pos + 1)
		out["tip"] = "Acts %s, in %d ticks." % [ordinal(pos + 1), out["ticks"]]
	else:
		out["tip"] = "Acts after the next %d actions." % upcoming.size()
	var math: Array = []
	if u.is_waiting():
		math.append("Holding in a wait: its gauge fills once the wait ends.")
	else:
		math.append(UiFormula.new().open().term("Turn at", threshold).op("−").term("Gauge", u.gauge).close()
			.op("/").term("Fill", fill).equals(maxi(0, ceili(float(threshold - u.gauge) / maxf(1.0, fill))), "ticks"))
		math.append("Fill %d per tick comes from Speed %d." % [fill, u.stats.speed])
	out["math"] = math
	return out


## 1 -> "1st", 2 -> "2nd", 3 -> "3rd", 4 -> "4th", 11 -> "11th".
static func ordinal(n: int) -> String:
	var suffix := "th"
	if n % 100 < 11 or n % 100 > 13:
		suffix = {1: "st", 2: "nd", 3: "rd"}.get(n % 10, "th")
	return "%d%s" % [n, suffix]
