class_name UnitPreview
extends RefCounted
## What the fight screen shows for one unit: its personality tag and, for an
## enemy, what it means to do next. A copy: changing it changes nothing.

var unit_id: String
var display_name: String
var side: Combatant.Side
var hp: int
var max_hp: int
## Personality.get_tag() for enemies; the squad summary's tag for allies.
var personality_tag: String
## The unit's current intent, or null (allies: the player decides).
var intent: UnitIntent
## Expected damage dealt or hp restored by the intent; unknown when random.
## Known 0 when there is no intent.
var amount: PreviewValue = PreviewValue.of(0)


## p_side is a Combatant.Side value, typed int as in TimelineEntry.
func _init(p_unit_id: String, p_display_name: String, p_side: int, p_hp: int, p_max_hp: int) -> void:
	unit_id = p_unit_id
	display_name = p_display_name
	side = p_side
	hp = p_hp
	max_hp = p_max_hp


func has_intent() -> bool:
	return intent != null


## For example "Strike on Bolt: 6", "Repair on Grunt 1: +5" or "Overload on Bolt: ?".
func intent_text() -> String:
	if intent == null:
		return ""
	var target := intent.target_id()
	match intent.kind:
		UnitIntent.Kind.WAIT:
			return "wait for %s, then %s: %s" % [intent.skill_id(), target, amount.text()]
		UnitIntent.Kind.HEAL:
			return "%s on %s: +%s" % [intent.skill_id(), target, amount.text()]
	return "%s on %s: %s" % [intent.skill_id(), target, amount.text()]
