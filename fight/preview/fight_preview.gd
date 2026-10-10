class_name FightPreview
extends RefCounted
## Read-only views of a fight for the fight screen. Nothing here changes the
## fight it is given: a pending choice is tried on a copy.
##
##   var preview := FightPreview.new()
##   for u in preview.units(fight):           # per unit: intent and tag
##       print(u.display_name, " ", u.intent_text())
##   var what_if := preview.preview_choice(fight, FightAction.use("strike", "foe#1"))

var planner: IntentPlanner
var rules: PreviewRules


func _init(p_planner: IntentPlanner = null, p_rules: PreviewRules = null) -> void:
	planner = p_planner if p_planner != null else IntentPlanner.new()
	rules = p_rules if p_rules != null else PreviewRules.load_default()


## One entry per living unit, in roster order. Enemies carry their intent from
## `intents` (for example IntentTracker.current) or, when it is null, a fresh plan.
func units(fight: Fight, intents: Variant = null) -> Array[UnitPreview]:
	var plan: Dictionary = intents if intents is Dictionary else planner.plan_all(fight)
	var out: Array[UnitPreview] = []
	for c in fight.combatants:
		if not c.is_alive():
			continue
		var u := UnitPreview.new(c.id, c.display_name, c.side, c.hp, c.max_hp)
		if c.side == Combatant.Side.ENEMY:
			u.personality_tag = planner.personality_of(c).get_tag()
			u.intent = plan.get(c.id)
			if u.intent != null:
				u.amount = rules.value_for(u.intent.skill_id(), u.intent.amount)
		else:
			u.personality_tag = _squad_tag(fight, c.id)
		out.append(u)
	return out


## What submitting `action` for the pending unit would do, without doing it.
func preview_choice(fight: Fight, action: FightAction) -> ChoicePreview:
	var out := ChoicePreview.new()
	out.problem = fight.check_action(action)
	if not out.problem.is_empty():
		return out
	# A wait deals nothing but is still tried: intents may react to it.
	if action.kind == FightAction.Kind.SKILL and rules.is_random(action.skill_id):
		var target := fight.combatant(action.target_id)
		out.effects.append(UnitEffect.new(
			target.id, target.display_name, target.hp, PreviewValue.unknown(), PreviewValue.unknown()))
		out.intent_changes_known = false
		return out
	var before := planner.plan_all(fight)
	var copy := FightCopy.of(fight)
	var problem := copy.submit(action)
	assert(problem.is_empty(), problem)
	for c in fight.combatants:
		var after := copy.combatant(c.id)
		if after.hp != c.hp:
			out.effects.append(UnitEffect.new(
				c.id, c.display_name, c.hp, PreviewValue.of(c.hp - after.hp), PreviewValue.of(after.hp)))
		if after.guard_percent != c.guard_percent:
			out.guard_changes[c.id] = after.guard_percent
	var after_plan := planner.plan_all(copy)
	var reason := "if %s uses %s" % [fight.pending_actor.display_name, action]
	for id: String in before:
		var old: UnitIntent = before[id]
		var new: UnitIntent = after_plan.get(id)
		if not old.same_as(new):
			out.intent_changes.append(IntentRevision.new(id, old, new, reason, fight.action_count + 1))
	return out


static func _squad_tag(fight: Fight, unit_id: String) -> String:
	for m in fight.request.squad:
		if m.id == unit_id:
			return m.personality_tag
	return ""
