class_name GameSettings
extends RefCounted
## The player's presentation settings: volumes, screen shake, reduced motion,
## animation speed, interface size, scaling and fullscreen. Defaults come from
## data/feel/settings.json; choices are saved to user://settings.cfg and
## survive between runs. The file carries a version, and an older file is
## migrated when it loads (_migrate()).
##
## Screens use GameSettings.shared(). Tests and dev tools (anything run with
## -s, so the main loop is a script) get a shared instance that lives in memory
## only, so they never read or write the player's file; the
## MECH_ENGINEER_SETTINGS environment variable points them at a file instead.
## Tests that need a file make their own instance with a temporary path.

signal changed

const SECTION := "presentation"
const VOLUME_BUSES := {
	"music_volume": "Music",
	"effects_volume": "Effects",
	"interface_volume": "Interface",
}
const SPEED_MULTIPLIERS := {"1x": 1.0, "1.5x": 1.5, "2x": 2.0, "skip": 0.0}
const VERSION_KEY := "version"
## Points tests and tools at a settings file of their own (shared_path()).
const PATH_ENV := "MECH_ENGINEER_SETTINGS"

static var _shared: GameSettings

var music_volume := 1.0
var effects_volume := 1.0
var interface_volume := 1.0
var shake_enabled := true
var shake_strength := 1.0
var reduced_motion := false
## One of "1x", "1.5x", "2x", "skip".
var animation_speed := "1x"
## How big the whole interface draws: 0 is Auto (as big as the scale mode
## allows in the window), 1.0 is the design size, larger suits big screens;
## capped to what fits (WindowFit). One of ui_scale_options in data/feel/settings.json.
var ui_scale := 0.0
## Fullscreen (F11, Alt+Enter, or the settings screen).
var fullscreen := false
## How the interface scales to the window: WindowFit.FIT ("fit", the
## default) or WindowFit.CRISP ("crisp", whole steps only).
var scale_mode := "fit"
## The id of the last "What's new" card the player closed.
var whats_new_seen := ""
var path := ""


static func shared() -> GameSettings:
	if _shared == null:
		_shared = GameSettings.new()
		_shared.load_from(shared_path())
	return _shared


## Where shared() keeps the settings: the player's file when the game runs,
## nowhere ("", in memory only) for tests and tools, or the file named by the
## MECH_ENGINEER_SETTINGS environment variable.
static func shared_path() -> String:
	var override := OS.get_environment(PATH_ENV)
	if not override.is_empty():
		return override
	var loop := Engine.get_main_loop()
	if loop != null and loop.get_script() != null:
		return ""
	return player_path()


## The player's settings file (data/feel/settings.json "save_path").
static func player_path() -> String:
	return str(FeelData.settings().get("save_path", "user://settings.cfg"))


## The settings file version this build writes.
static func current_version() -> int:
	return int(FeelData.settings().get("version", 1))


func _init() -> void:
	reset_to_defaults(false)


static func keys() -> Array[String]:
	return ["music_volume", "effects_volume", "interface_volume", "shake_enabled",
		"shake_strength", "reduced_motion", "animation_speed", "ui_scale", "fullscreen", "scale_mode", "whats_new_seen"]


func reset_to_defaults(notify := true) -> void:
	var defaults: Dictionary = FeelData.settings().get("defaults", {})
	for key in keys():
		if defaults.has(key):
			_assign(key, defaults[key])
	if notify:
		changed.emit()


## Reads `p_path`; keys it lacks keep their defaults. Remembers the path for
## save(). A file from an older version is migrated and saved back.
func load_from(p_path: String) -> void:
	path = p_path
	if path.is_empty():
		return
	var config := ConfigFile.new()
	if config.load(path) != OK:
		return
	for key in keys():
		if config.has_section_key(SECTION, key):
			_assign(key, config.get_value(SECTION, key))
	var version := int(config.get_value(SECTION, VERSION_KEY, 0))
	if version < current_version():
		_migrate(version, config)
		save()


## Brings settings read from a version `from` file up to date.
##   - Before version 2, every save wrote ui_scale, and its default was 1.0
##     (100%). 1.0 then meant "never chose": it becomes Auto, so the window
##     fit (Fit window scaling) applies. Any other saved size was a choice
##     and stays.
func _migrate(from: int, config: ConfigFile) -> void:
	if from < 2 and is_equal_approx(float(config.get_value(SECTION, "ui_scale", 0.0)), 1.0):
		ui_scale = 0.0


func save() -> Error:
	if path.is_empty():
		return ERR_FILE_BAD_PATH
	var config := ConfigFile.new()
	config.set_value(SECTION, VERSION_KEY, current_version())
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


## Draws the whole interface at ui_scale, fitted to the window (WindowFit).
func apply_ui_scale(tree: SceneTree) -> void:
	if tree != null and tree.root != null:
		WindowFit.apply(tree.root, ui_scale, scale_mode)


## Puts the window in or out of fullscreen to match the setting.
func apply_fullscreen() -> void:
	WindowFit.set_fullscreen(fullscreen)


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
		"shake_enabled", "reduced_motion", "fullscreen":
			set(key, bool(value))
		"animation_speed":
			var text := str(value)
			set(key, text if SPEED_MULTIPLIERS.has(text) else "1x")
		"ui_scale":
			var options: Array = FeelData.settings().get("ui_scale_options", [0.0])
			var v := float(value)
			var best := float(options[0]) if not options.is_empty() else 0.0
			for o: Variant in options:
				if absf(float(o) - v) < absf(best - v):
					best = float(o)
			ui_scale = best
		"scale_mode":
			var mode := str(value)
			scale_mode = mode if mode in FeelData.settings().get("scale_mode_options", [WindowFit.FIT]) else WindowFit.FIT
		"whats_new_seen":
			whats_new_seen = str(value)
		_:
			set(key, clampf(float(value), 0.0, 1.0))
