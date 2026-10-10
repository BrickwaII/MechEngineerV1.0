class_name Personality
extends Resource
## A bot's temperament on three scales, each from -1 to 1. State only: values
## are clamped on write and nothing here changes them over time.
##
## -1 is the first pole of each scale and +1 the second:
## aggressive (-1) to defensive (+1), solitary (-1) to supportive (+1),
## reactive (-1) to methodical (+1).
##
## The generation decides how many scales are active: generation 1 has only
## AGGRESSIVE_DEFENSIVE, generation 2 adds SOLITARY_SUPPORTIVE, generation 3
## and later have all three. An inactive scale reads as 0 through get_value().

enum Scale { AGGRESSIVE_DEFENSIVE, SOLITARY_SUPPORTIVE, REACTIVE_METHODICAL }

const MIN_VALUE := -1.0
const MAX_VALUE := 1.0
const MIN_GENERATION := 1
const SCALE_COUNT := 3
## Pole names per scale, negative end first.
const POLES := {
	Scale.AGGRESSIVE_DEFENSIVE: ["aggressive", "defensive"],
	Scale.SOLITARY_SUPPORTIVE: ["solitary", "supportive"],
	Scale.REACTIVE_METHODICAL: ["reactive", "methodical"],
}
## The tag of a personality with no lean on any active scale.
const BALANCED_TAG := "balanced"

@export var generation: int = MIN_GENERATION:
	set(value):
		generation = maxi(value, MIN_GENERATION)
@export_range(-1.0, 1.0) var aggressive_defensive: float = 0.0:
	set(value):
		aggressive_defensive = clampf(value, MIN_VALUE, MAX_VALUE)
@export_range(-1.0, 1.0) var solitary_supportive: float = 0.0:
	set(value):
		solitary_supportive = clampf(value, MIN_VALUE, MAX_VALUE)
@export_range(-1.0, 1.0) var reactive_methodical: float = 0.0:
	set(value):
		reactive_methodical = clampf(value, MIN_VALUE, MAX_VALUE)


func _init(
	p_generation := MIN_GENERATION,
	p_aggressive_defensive := 0.0,
	p_solitary_supportive := 0.0,
	p_reactive_methodical := 0.0,
) -> void:
	generation = p_generation
	aggressive_defensive = p_aggressive_defensive
	solitary_supportive = p_solitary_supportive
	reactive_methodical = p_reactive_methodical


## How many scales this generation has: 1, 2, then 3.
func get_active_scale_count() -> int:
	return mini(generation, SCALE_COUNT)


func is_active(scale: int) -> bool:
	return scale < get_active_scale_count()


## The stored value of a scale, ignoring whether it is active.
func get_raw_value(scale: int) -> float:
	match scale:
		Scale.AGGRESSIVE_DEFENSIVE:
			return aggressive_defensive
		Scale.SOLITARY_SUPPORTIVE:
			return solitary_supportive
		_:
			return reactive_methodical


## The value of a scale as the rest of the game sees it: 0 when inactive.
func get_value(scale: int) -> float:
	return get_raw_value(scale) if is_active(scale) else 0.0


## The pole of the active scale with the strongest lean, for example
## "aggressive". The earlier scale wins a tie; no lean at all is BALANCED_TAG.
func get_tag() -> String:
	var best_scale := -1
	var best_strength := 0.0
	for scale in get_active_scale_count():
		var strength := absf(get_value(scale))
		if strength > best_strength:
			best_scale = scale
			best_strength = strength
	if best_scale < 0:
		return BALANCED_TAG
	return POLES[best_scale][0 if get_value(best_scale) < 0.0 else 1]


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if generation < MIN_GENERATION:
		errors.append("generation %d is below %d" % [generation, MIN_GENERATION])
	for scale in SCALE_COUNT:
		var value := get_raw_value(scale)
		if value < MIN_VALUE or value > MAX_VALUE:
			errors.append("scale %d value %f is outside -1 to 1" % [scale, value])
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()
