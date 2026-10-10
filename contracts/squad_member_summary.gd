class_name SquadMemberSummary
extends Resource
## What the rest of the game sees of one squad member. Plain data.

@export var id: String
@export var display_name: String
@export var hp: int
@export var max_hp: int
@export var personality_tag: String
@export var stats: UnitStats


func _init(
	p_id := "",
	p_display_name := "",
	p_hp := 0,
	p_max_hp := 0,
	p_personality_tag := "",
	p_stats: UnitStats = null,
) -> void:
	id = p_id
	display_name = p_display_name
	hp = p_hp
	max_hp = p_max_hp
	personality_tag = p_personality_tag
	stats = p_stats if p_stats != null else UnitStats.new()
