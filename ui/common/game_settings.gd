class_name GameSettings
extends RefCounted
## The player's presentation settings: volumes, screen shake, reduced motion and
## animation speed. Defaults come from data/feel/settings.json; choices are
## saved to user://settings.cfg and survive between runs.
##
## Screens use GameSettings.shared(). Tests make their own instance with a
## temporary path so they never touch the player's file.

signal changed

const SECTION := "presentation"
const VOLUME_BUSES := {
	"music_volume": "Music",
	"effects_volume": "Effects",
	"interface_volume": "Interface",
}
const SPEED_MULTIPLIERS := {"1x": 1.0, "1.5x": 1.5, "2x": 2.0, "skip": 0.0}

static var _shared: GameSettings

var music_volume := 1.0
var effects_volume := 1.0
var interface_volume := 1.0
var shake_enabled := true
var shake_strength := 1.0
var reduced_motion := false
## One of "1x", "1.5x", "2x", "skip".
var animation_speed := "1x"
## How big the whole interface draws: 1.0 is the design size; larger suits big
## screens (ui/README.md). One of ui_scale_options in data/feel/settings.json.
var ui_scale := 1.0
## The id of the last "What's new" card the player closed.
var whats_new_seen := ""
var path := ""


static func shared() -> GameSettings:
	if _shared == null:
		_shared = GameSettings.new()
		_shared.load_from(FeelData.settings().get("save_path", "user://settings.cfg"))
	return _shared


func _init() -> void:
	reset_to_defaults(false)


static func keys() -> Array[String]:
	return ["music_volume", "effects_volume", "interface_volume", "shake_enabled",
		"shake_strength", "reduced_motion", "animation_speed", "ui_scale", "whats_new_seen"]


func reset_to_defaults(notify := true) -> void:
	var defaults: Dictionary = FeelData.settings().get("defaults", {})
	for key in keys():
		if defaults.has(key):
			_assign(key, defaults[key])
	if notify:
		changed.emit()


## Reads `p_path`; keys it lacks keep their defaults. Remembers the path for save().
func load_from(p_path: String) -> void:
	path = p_path
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	for key in keys():
		if config.has_section_key(SECTION, key):
			_assign(key, config.get_value(SECTION, key))


func save() -> Error:
	if path.is_empty():
		return ERR_FILE_BAD_PATH
	var config := ConfigFile.new()
	for key in keys():
		config.set_value(SECTION, key, get(key))
	return config.save(path)


## Sets one setting by name (clamped to its range), saves and notifies.
func set_value(key: String, value: Variant) -> void:
	if not key in keys():
		push_warning("GameSettings: unknown setting '%s'" % key)
		return
	_assign(key, value)
	save()
	changed.emit()


func to_dict() -> Dictionary:
	var out := {}
	for key in keys():
		out[key] = get(key)
	return out


func skips_animations() -> bool:
	return animation_speed == "skip"


## 1.0, 1.5 or 2.0; 0.0 when animations are skipped.
func speed_multiplier() -> float:
	return SPEED_MULTIPLIERS.get(animation_speed, 1.0)


## A duration after the animation speed setting: shorter when sped up, 0 when skipped.
func scale_seconds(seconds: float) -> float:
	var speed := speed_multiplier()
	return 0.0 if speed <= 0.0 else seconds / speed


## How much of a preset's shake to use: 0 when shake is off or motion is reduced.
func shake_scale() -> float:
	if not shake_enabled:
		return 0.0
	if reduced_motion:
		return shake_strength * FeelData.number("reduced_motion.shake_scale", 0.0)
	return shake_strength


## Draws the whole interface at ui_scale (the root's content scale).
func apply_ui_scale(tree: SceneTree) -> void:
	if tree != null and tree.root != null:
		tree.root.content_scale_factor = ui_scale


## Sets the Music, Effects and Interface bus volumes. A bus that does not
## exist is skipped.
func apply_to_buses() -> void:
	for key: String in VOLUME_BUSES:
		var bus := AudioServer.get_bus_index(VOLUME_BUSES[key])
		if bus < 0:
			continue
		var linear: float = get(key)
		AudioServer.set_bus_mute(bus, linear <= 0.0)
		AudioServer.set_bus_volume_db(bus, linear_to_db(maxf(linear, 0.0001)))


func _assign(key: String, value: Variant) -> void:
	match key:
		"shake_enabled", "reduced_motion":
			set(key, bool(value))
		"animation_speed":
			var text := str(value)
			set(key, text if SPEED_MULTIPLIERS.has(text) else "1x")
		"ui_scale":
			var options: Array = FeelData.settings().get("ui_scale_options", [1.0])
			var v := float(value)
			var best := 1.0
			for o: Variant in options:
				if absf(float(o) - v) < absf(best - v):
					best = float(o)
			ui_scale = best
		"whats_new_seen":
			whats_new_seen = str(value)
		_:
			set(key, clampf(float(value), 0.0, 1.0))
