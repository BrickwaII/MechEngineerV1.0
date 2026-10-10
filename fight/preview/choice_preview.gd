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
