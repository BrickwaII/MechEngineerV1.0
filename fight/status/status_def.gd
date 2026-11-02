class_name StatusDef
extends RefCounted
## One status a unit can hold in a fight: what it does, how it stacks, when it
## ends and what uses it up. Plain data, read from data/combat/statuses.json by
## StatusTable. The combat rework plan's StatusDef (S1).
##
## Definitions only: nothing applies a status yet. S3's status manager gives
## them meaning; until then no action names one (CombatSkill.applies_status).
##
## Effects:
##   damage_taken_percent  the holder takes `amount` percent more damage
##                         (Exposed)
## Expiry:
##   holder_next_action  ends when the holder next acts
##   never               ends only when consumed
## Consumed by:
##   hit     the next damage hit the holder takes uses it up
##   payoff  an action whose payoff_condition names it uses it up

const EFFECT_DAMAGE_TAKEN_PERCENT := "damage_taken_percent"
const EFFECTS: Array[String] = [EFFECT_DAMAGE_TAKEN_PERCENT]

const EXPIRY_HOLDER_NEXT_ACTION := "holder_next_action"
const EXPIRY_NEVER := "never"
const EXPIRIES: Array[String] = [EXPIRY_HOLDER_NEXT_ACTION, EXPIRY_NEVER]

const CONSUMED_BY_HIT := "hit"
const CONSUMED_BY_PAYOFF := "payoff"
const CONSUMERS: Array[String] = [CONSUMED_BY_HIT, CONSUMED_BY_PAYOFF]

var id: String
var display_name: String
## One of EFFECTS.
var effect: String
## The effect's size; for damage_taken_percent, the percent of extra damage.
var amount := 0
## Most stacks a unit may hold; 1 means applying it again only refreshes it.
var max_stacks := 1
## One of EXPIRIES.
var expiry := EXPIRY_HOLDER_NEXT_ACTION
## Any of CONSUMERS; empty: nothing uses it up, it only expires.
var consumed_by: Array[String] = []


## The status defined by one entry of data/combat/statuses.json. Keys left out
## take the defaults above.
static func from_dict(p_id: String, d: Dictionary) -> StatusDef:
	var s := StatusDef.new()
	s.id = p_id
	s.display_name = String(d.get("name", p_id))
	s.effect = String(d.get("effect", ""))
	s.amount = int(d.get("amount", 0))
	s.max_stacks = int(d.get("max_stacks", 1))
	s.expiry = String(d.get("expiry", EXPIRY_HOLDER_NEXT_ACTION))
	for c: Variant in d.get("consumed_by", []):
		s.consumed_by.append(String(c))
	return s


func is_consumed_by(trigger: String) -> bool:
	return trigger in consumed_by


## Problems with this definition; empty when usable.
func validate() -> Array[String]:
	var problems: Array[String] = []
	if id.is_empty():
		problems.append("a status has no id")
	if display_name.is_empty():
		problems.append("status %s has no name" % id)
	if not effect in EFFECTS:
		problems.append("status %s has unknown effect '%s'" % [id, effect])
	if max_stacks < 1:
		problems.append("status %s max_stacks must be at least 1" % id)
	if not expiry in EXPIRIES:
		problems.append("status %s has unknown expiry '%s'" % [id, expiry])
	var seen := {}
	for c in consumed_by:
		if not c in CONSUMERS:
			problems.append("status %s has unknown consumed_by '%s'" % [id, c])
		elif seen.has(c):
			problems.append("status %s lists consumed_by %s twice" % [id, c])
		seen[c] = true
	if expiry == EXPIRY_NEVER and consumed_by.is_empty():
		problems.append("status %s never expires and nothing consumes it" % id)
	return problems
