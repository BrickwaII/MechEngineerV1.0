class_name Personality
extends Resource
## A bot's temperament on three spectrums. Each spectrum holds two values, one
## per end, that never go below 0 and have no upper cap. State only: nothing
## here changes them over time; post-fight drift only ever adds to an end.
##
## Spectrums and their ends, first end then second:
## aggressive / defensive, solitary / supportive, reactive / methodical.
## The lean of a spectrum is the larger end: get_net() is second - first, so a
## negative net leans to the first end, as the old signed value did.
## get_lean() scales the net to -1..1 for the intent planner.
##
## Save format 1 kept one signed value per spectrum (-1 to 1). Loading such a
## file sets aggressive_defensive and friends, which split it onto the ends:
## a value v becomes max(-v, 0) on the first end and max(v, 0) on the second.
##
## Every spectrum can grow at every generation. The generation only decides
## how many spectrums the intent planner weighs (1, 2, then 3); see is_active().
## TODO(decision: personality-generation): default until decided: generation
## still gates what the planner weighs (today only enemies are planned), so
## enemy behaviour is unchanged; it no longer locks growth.

enum Scale { AGGRESSIVE_DEFENSIVE, SOLITARY_SUPPORTIVE, REACTIVE_METHODICAL }

## Bounds of a signed spectrum value: a starting roll or a format-1 save.
const MIN_VALUE := -1.0
const MAX_VALUE := 1.0
const MIN_END := 0.0
const MIN_GENERATION := 1
const SCALE_COUNT := 3
## End names per spectrum, first end then second.
const POLES := {
	Scale.AGGRESSIVE_DEFENSIVE: ["aggressive", "defensive"],
	Scale.SOLITARY_SUPPORTIVE: ["solitary", "supportive"],
	Scale.REACTIVE_METHODICAL: ["reactive", "methodical"],
}
## Every end, spectrum by spectrum, first end then second.
const ENDS: Array[String] = ["aggressive", "defensive", "solitary", "supportive", "reactive", "methodical"]
## The tag of a personality with no lean on any spectrum.
const BALANCED_TAG := "balanced"

@export var generation: int = MIN_GENERATION:
	set(value):
		generation = maxi(value, MIN_GENERATION)
@export var aggressive: float = 0.0:
	set(value):
		aggressive = maxf(value, MIN_END)
@export var defensive: float = 0.0:
	set(value):
		defensive = maxf(value, MIN_END)
@export var solitary: float = 0.0:
	set(value):
		solitary = maxf(value, MIN_END)
@export var supportive: float = 0.0:
	set(value):
		supportive = maxf(value, MIN_END)
@export var reactive: float = 0.0:
	set(value):
		reactive = maxf(value, MIN_END)
@export var methodical: float = 0.0:
	set(value):
		methodical = maxf(value, MIN_END)

## Format-1 signed values. Never saved. Reading gives the net; writing splits
## a signed value onto the two ends, replacing them.
var aggressive_defensive: float:
	get:
		return defensive - aggressive
	set(value):
		aggressive = -clampf(value, MIN_VALUE, 0.0)
		defensive = clampf(value, 0.0, MAX_VALUE)
var solitary_supportive: float:
	get:
		return supportive - solitary
	set(value):
		solitary = -clampf(value, MIN_VALUE, 0.0)
		supportive = clampf(value, 0.0, MAX_VALUE)
var reactive_methodical: float:
	get:
		return methodical - reactive
	set(value):
		reactive = -clampf(value, MIN_VALUE, 0.0)
		methodical = clampf(value, 0.0, MAX_VALUE)


## The three values are signed, as in save format 1 and the data files.
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


## How many spectrums the intent planner weighs for this generation: 1, 2, then 3.
func get_active_scale_count() -> int:
	return mini(generation, SCALE_COUNT)


## True when the intent planner weighs `scale`. Every spectrum grows either way.
func is_active(scale: int) -> bool:
	return scale < get_active_scale_count()


## The value of one end, by name ("aggressive"). 0 for an unknown name.
func get_end(pole: String) -> float:
	if not pole in ENDS:
		return 0.0
	return float(get(pole))


## Every end's value, in ENDS order.
func get_ends() -> Array[float]:
	var out: Array[float] = []
	for pole in ENDS:
		out.append(get_end(pole))
	return out


func get_first_end(scale: int) -> float:
	return get_end(POLES[scale][0])


func get_second_end(scale: int) -> float:
	return get_end(POLES[scale][1])


## Second end minus first end. Negative leans to the first end.
func get_net(scale: int) -> float:
	return get_second_end(scale) - get_first_end(scale)


## The net scaled to -1..1: net / max(first + second, `floor`). With both ends
## below `floor` in total this is the plain net; past it, the share by which
## the larger end wins. `floor` comes from data (intent_weights.json).
func get_lean(scale: int, floor: float) -> float:
	var total := get_first_end(scale) + get_second_end(scale)
	return clampf(get_net(scale) / maxf(total, maxf(floor, 0.0001)), MIN_VALUE, MAX_VALUE)


## The end with the strongest net lean over every spectrum, for example
## "aggressive". The earlier spectrum wins a tie; no lean at all is BALANCED_TAG.
func get_tag() -> String:
	var best_scale := -1
	var best_strength := 0.0
	for scale in SCALE_COUNT:
		var strength := absf(get_net(scale))
		if strength > best_strength and not is_zero_approx(strength):
			best_scale = scale
			best_strength = strength
	if best_scale < 0:
		return BALANCED_TAG
	return POLES[best_scale][0 if get_net(best_scale) < 0.0 else 1]


func validation_errors() -> PackedStringArray:
	var errors := PackedStringArray()
	if generation < MIN_GENERATION:
		errors.append("generation %d is below %d" % [generation, MIN_GENERATION])
	for pole in ENDS:
		var value := get_end(pole)
		if value < MIN_END or is_nan(value) or is_inf(value):
			errors.append("end %s value %f is below 0 or not a number" % [pole, value])
	return errors


func is_valid() -> bool:
	return validation_errors().is_empty()
