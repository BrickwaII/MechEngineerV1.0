class_name ChoicePreview
extends RefCounted
## What a pending choice would do, worked out without submitting it: which
## units take how much damage and which enemy intents would change.
## Built by FightPreview.preview_choice().

## Why the action would be refused, or "" when it is allowed. A refused choice
## has no effects and no intent changes.
var problem := ""
## One entry per unit whose hp would (or might) change, in roster order.
var effects: Array[UnitEffect] = []
## Unit id -> the percent of its next hit it would block afterwards, for every
## unit whose guard the choice would change (Brace, Shield Ally, or a hit that
## uses a guard up).
var guard_changes: Dictionary[String, int] = {}
## False when the outcome is random, so which intents change is unknown.
var intent_changes_known := true
## One revision per enemy whose intent would change. Empty when unknown.
var intent_changes: Array[IntentRevision] = []
## Unit id -> its energy right after the choice resolves, for every unit whose
## energy the choice would change (the cost the actor pays).
var energy_after: Dictionary[String, int] = {}
## Every enemy's intent once time runs to the next decision after the choice:
## what the screen would telegraph next. Empty when unknown or the fight ends.
var intents_after: Dictionary[String, UnitIntent] = {}
## The upcoming order once the choice resolves and time runs to the next
## decision, as Fight.upcoming() would give it then. Empty when unknown.
var order_after: Array[TimelineEntry] = []
## The fight as it would stand at that next decision. Read-only; null when
## unknown. For reading the arrows the intents_after would draw.
var fight_after: Fight


func is_allowed() -> bool:
	return problem.is_empty()


func effect_on(unit_id: String) -> UnitEffect:
	for e in effects:
		if e.unit_id == unit_id:
			return e
	return null


func change_for(unit_id: String) -> IntentRevision:
	for r in intent_changes:
		if r.unit_id == unit_id:
			return r
	return null
