class_name UnitEffect
extends RefCounted
## How one unit's hp would change if a pending choice were submitted.

var unit_id: String
var display_name: String
var hp_before: int
## Hp lost; unknown when the outcome is random.
var damage: PreviewValue
## Hp left afterwards; unknown when the outcome is random.
var hp_after: PreviewValue


func _init(p_unit_id: String, p_display_name: String, p_hp_before: int, p_damage: PreviewValue, p_hp_after: PreviewValue) -> void:
	unit_id = p_unit_id
	display_name = p_display_name
	hp_before = p_hp_before
	damage = p_damage
	hp_after = p_hp_after


## Known true when the unit would surely go down; false when it surely would
## not or when that is unknown.
func would_go_down() -> bool:
	return hp_after.known and hp_after.value == 0


func _to_string() -> String:
	return "%s: -%s (%d -> %s)" % [unit_id, damage.text(), hp_before, hp_after.text()]
