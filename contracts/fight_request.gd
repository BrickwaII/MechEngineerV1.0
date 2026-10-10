class_name FightRequest
extends RefCounted
## What the map asks a FightService to resolve. Plain data.

enum Kind { ATTACK, DEFEND }

const MIN_DEFENSE_LEVEL := 0
const MAX_DEFENSE_LEVEL := 5

var kind: Kind
var territory_id: String
## 0 to 5. Use is_valid() to check before starting a fight.
var defense_level: int
var squad: Array[SquadMemberSummary]


func _init(
	p_kind := Kind.ATTACK,
	p_territory_id := "",
	p_defense_level := 0,
	p_squad: Array[SquadMemberSummary] = [],
) -> void:
	kind = p_kind
	territory_id = p_territory_id
	defense_level = p_defense_level
	squad = p_squad


func is_valid() -> bool:
	return (
		not territory_id.is_empty()
		and defense_level >= MIN_DEFENSE_LEVEL
		and defense_level <= MAX_DEFENSE_LEVEL
		and not squad.is_empty()
	)
