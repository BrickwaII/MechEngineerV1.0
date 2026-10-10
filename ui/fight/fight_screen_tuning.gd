class_name FightScreenTuning
extends RefCounted
## Fight screen and demo settings, read from data/ui/fight_screen.json.

const DEFAULT_PATH := "res://data/ui/fight_screen.json"

## How many upcoming actions the timeline bar shows.
var timeline_length := 0
## Pause before each enemy action, so the player can follow it.
var enemy_turn_delay_seconds := 0.0
var demo_draft_seed := 0
var demo_territory_id := ""
var demo_defense_level := 0
## Problems found while reading, such as a missing key.
var errors: Array[String] = []


static func load_default() -> FightScreenTuning:
	return load_file(DEFAULT_PATH)


static func load_file(path: String) -> FightScreenTuning:
	var parsed: Variant = null
	if FileAccess.file_exists(path):
		parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary:
		var t := FightScreenTuning.new()
		t.errors.append("cannot read %s" % path)
		return t
	return from_dict(parsed)


static func from_dict(d: Dictionary) -> FightScreenTuning:
	var t := FightScreenTuning.new()
	var demo: Dictionary = d.get("demo", {})
	t.timeline_length = int(_number(d, "timeline_length", t.errors))
	t.enemy_turn_delay_seconds = _number(d, "enemy_turn_delay_seconds", t.errors)
	t.demo_draft_seed = int(_number(demo, "draft_seed", t.errors))
	t.demo_defense_level = int(_number(demo, "defense_level", t.errors))
	t.demo_territory_id = str(demo.get("territory_id", ""))
	if t.timeline_length < 1:
		t.errors.append("timeline_length must be at least 1")
	if t.enemy_turn_delay_seconds < 0.0:
		t.errors.append("enemy_turn_delay_seconds may not be negative")
	if t.demo_territory_id.is_empty():
		t.errors.append("demo.territory_id is missing")
	return t


static func _number(d: Dictionary, key: String, errors: Array[String]) -> float:
	var value: Variant = d.get(key)
	if not (value is float or value is int):
		errors.append("%s is missing or not a number" % key)
		return 0.0
	return float(value)
