class_name ArrowBadge
extends RefCounted
## One arrow on the battle screen and the number on it: who acts on whom, what
## kind of action it is, and how much it does. Built by BattleReadout from an
## enemy intent or from the choice preview; a plain value.

const ATTACK := "attack"
const HEAL := "heal"
const GUARD := "guard"
const WAIT := "wait"

var from_id: String
var to_id: String
## ATTACK, HEAL, GUARD or WAIT (an attack once a charge ends).
var kind: String
var skill_id: String
## Hp the target loses (ATTACK, WAIT), hp it gains (HEAL), or the percent of
## its next hit it blocks (GUARD). Damage is what leaves the bar: never more
## than the target's hp. Unknown when the outcome is random.
var amount: PreviewValue
## True when the action would surely down the target.
var knocks_out := false
## True when the previewed choice changed this arrow (new target, new skill or
## new amount). Set by BattleReadout.compare().
var changed := false
## The amount before the previewed choice, when it changed; else null.
var old_amount: PreviewValue


func _init(p_from := "", p_to := "", p_kind := ATTACK, p_skill_id := "", p_amount: PreviewValue = null) -> void:
	from_id = p_from
	to_id = p_to
	kind = p_kind
	skill_id = p_skill_id
	amount = p_amount if p_amount != null else PreviewValue.of(0)


## The badge text: "6", "+5", "50%", or "?" for an unknown amount.
func text() -> String:
	if amount.is_unknown():
		return PreviewValue.UNKNOWN_TEXT
	match kind:
		HEAL:
			return "+%d" % amount.value
		GUARD:
			return "%d%%" % amount.value
	return str(amount.value)


## Same arrow: same ends, kind and skill.
func same_arrow(other: ArrowBadge) -> bool:
	return other != null and from_id == other.from_id and to_id == other.to_id and kind == other.kind and skill_id == other.skill_id


func _to_string() -> String:
	return "%s -%s-> %s: %s%s" % [from_id, kind, to_id, text(), " KO" if knocks_out else ""]
