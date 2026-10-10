class_name FightTelegraph
extends RefCounted
## What the battle screen tells the player about the enemies and about a
## choice before it is made: each enemy's intent in words, which intents just
## changed and why, each unit's personality tag, and the choice preview.
## Needs no scene. Nothing here changes the fight: intents come from an
## IntentTracker, the preview is tried on a copy.
##
##   var telegraph := FightTelegraph.new(fight)
##   fight.submit(action)
##   telegraph.after_action(fight, actor)   # re-plans, marks revised intents
##   telegraph.intent_text(fight, "rust_hound#1")  # "Heavy Strike -> Ace (9)"
##   var what_if := telegraph.preview_choice(fight, FightAction.use("strike", id))
##
## A revised intent stays marked for one turn: until the next bot action
## resolves. Marks made by enemy actions in between pile up, so the player
## sees every change since their last decision.

var planner: IntentPlanner
var tracker: IntentTracker
var preview: FightPreview
## Unit id -> the latest revision of its intent, while it is marked.
var marks: Dictionary[String, IntentRevision] = {}

## Unit id -> personality tag, kept for units that go down.
var _tags: Dictionary[String, String] = {}


func _init(fight: Fight, p_planner: IntentPlanner = null) -> void:
	planner = p_planner if p_planner != null else IntentPlanner.new()
	tracker = IntentTracker.new(planner)
	preview = FightPreview.new(planner)
	tracker.intent_revised.connect(_on_intent_revised)
	tracker.refresh(fight)
	_remember_tags(fight)


## The enemy policy that plays what is telegraphed.
func enemy_policy() -> FightPolicy:
	return IntentFightPolicy.new(planner)


## Call after every resolved action. `actor` is the unit that acted.
func after_action(fight: Fight, actor: Combatant) -> Array[IntentRevision]:
	if actor != null and actor.side == Combatant.Side.PLAYER:
		marks.clear()
	var revisions := tracker.refresh(fight)
	_remember_tags(fight)
	return revisions


func intent_of(unit_id: String) -> UnitIntent:
	return tracker.intent_of(unit_id)


func is_marked(unit_id: String) -> bool:
	return marks.has(unit_id)


## "changed: <why>" while the unit's intent is marked, else "".
func change_text(unit_id: String) -> String:
	var r: IntentRevision = marks.get(unit_id)
	return "changed: %s" % r.reason if r != null else ""


## The unit's personality tag, or "" when it has none.
func tag_of(unit_id: String) -> String:
	return _tags.get(unit_id, "")


## The unit's current intent in words, or "" when it has none.
func intent_text(fight: Fight, unit_id: String) -> String:
	return describe_intent(fight, intent_of(unit_id))


## What submitting `action` would do. Changes nothing.
func preview_choice(fight: Fight, action: FightAction) -> ChoicePreview:
	return preview.preview_choice(fight, action)


## An intent in words, for example "Heavy Strike -> Ace (9)", "Repair ->
## Grunt 1 (+8)" or "charging Overload, then -> Ace (15)". "?" stands in for
## an amount the preview cannot know.
func describe_intent(fight: Fight, intent: UnitIntent) -> String:
	if intent == null:
		return ""
	var amount := preview.rules.value_for(intent.skill_id(), intent.amount).text()
	var target := unit_name(fight, intent.target_id())
	var skill := skill_name(fight, intent.skill_id())
	match intent.kind:
		UnitIntent.Kind.HEAL:
			return "%s -> %s (+%s)" % [skill, target, amount]
		UnitIntent.Kind.WAIT:
			return "charging %s, then -> %s (%s)" % [skill, target, amount]
	return "%s -> %s (%s)" % [skill, target, amount]


## One unit's line in the choice preview, for its panel: "-6 (14 -> 8)",
## "-14 (14 -> 0) DOWN", "+8 (10 -> 18)", or "-? (14 -> ?)". "" when the
## choice does not touch the unit.
static func effect_text(effect: UnitEffect) -> String:
	if effect == null:
		return ""
	var amount := effect.damage.text()
	if effect.damage.known and effect.damage.value < 0:
		amount = "+%d" % -effect.damage.value
	else:
		amount = "-" + amount
	var line := "%s (%d -> %s)" % [amount, effect.hp_before, effect.hp_after.text()]
	return line + " DOWN" if effect.would_go_down() else line


## An enemy's line in the choice preview: what it would switch to.
func intent_change_text(fight: Fight, revision: IntentRevision) -> String:
	if revision == null:
		return ""
	if revision.new_intent == null:
		return "would drop its plan"
	return "would switch to %s" % describe_intent(fight, revision.new_intent)


## The preview box text for `action` with its preview `choice`.
func describe_choice(fight: Fight, action: FightAction, choice: ChoicePreview) -> String:
	var lines := PackedStringArray()
	var actor := fight.pending_actor
	lines.append("%s: %s -> %s" % [
		actor.display_name if actor != null else "?", skill_name(fight, action.skill_id),
		unit_name(fight, action.target_id)])
	if not choice.is_allowed():
		lines.append("not allowed: %s" % choice.problem)
		return "\n".join(lines)
	if choice.effects.is_empty():
		lines.append("no hp changes")
	for e in choice.effects:
		lines.append("%s %s" % [e.display_name, effect_text(e)])
	var downs := PackedStringArray()
	for e in choice.effects:
		if e.would_go_down():
			downs.append(e.display_name)
	if not downs.is_empty():
		lines.append("goes down: %s" % ", ".join(downs))
	if not choice.intent_changes_known:
		lines.append("enemy intents: ?")
	elif choice.intent_changes.all(func(r: IntentRevision) -> bool: return r.unit_id in downs_ids(choice)):
		lines.append("no enemy changes its plan")
	else:
		for r in choice.intent_changes:
			var effect := choice.effect_on(r.unit_id)
			if effect != null and effect.would_go_down():
				continue
			lines.append("%s %s" % [unit_name(fight, r.unit_id), intent_change_text(fight, r)])
	return "\n".join(lines)


## Ids of the units `choice` would surely down.
static func downs_ids(choice: ChoicePreview) -> Array[String]:
	var out: Array[String] = []
	for e in choice.effects:
		if e.would_go_down():
			out.append(e.unit_id)
	return out


static func unit_name(fight: Fight, unit_id: String) -> String:
	var c := fight.combatant(unit_id)
	return c.display_name if c != null else unit_id


static func skill_name(fight: Fight, skill_id: String) -> String:
	var s := fight.tuning.skill(skill_id)
	return s.display_name if s != null else skill_id


func _on_intent_revised(revision: IntentRevision) -> void:
	if revision.new_intent == null:
		marks.erase(revision.unit_id)
		return
	marks[revision.unit_id] = revision


func _remember_tags(fight: Fight) -> void:
	for u in preview.units(fight, tracker.current):
		_tags[u.unit_id] = u.personality_tag
