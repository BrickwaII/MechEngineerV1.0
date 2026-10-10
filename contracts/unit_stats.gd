class_name UnitStats
extends Resource
## The six stats every unit has. Plain data, all integers.

@export var hp: int
@export var attack: int
@export var defense: int
@export var speed: int
@export var elasticity: int
@export var battery_capacity: int


func _init(
	p_hp := 0,
	p_attack := 0,
	p_defense := 0,
	p_speed := 0,
	p_elasticity := 0,
	p_battery_capacity := 0,
) -> void:
	hp = p_hp
	attack = p_attack
	defense = p_defense
	speed = p_speed
	elasticity = p_elasticity
	battery_capacity = p_battery_capacity
