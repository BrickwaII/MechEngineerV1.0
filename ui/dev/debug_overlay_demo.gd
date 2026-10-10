extends Control
## Demo of the debug overlay on a fight driven headless: a sample scenario is
## played by its policies, one decision every demo_seconds_per_action, with the
## overlay attached. When the fight ends a new one starts on the next seed.
## F3 hides and shows the overlay.

const Palette := preload("res://ui/dev/dev_palette.gd")
const SCENARIO_PATH := "res://data/scenarios/level2_drafted_squad.json"

var overlay: DebugOverlay
var sim: SimulatedFight

var _resolved: ResolvedScenario
var _seed: int
var _seconds_per_action: float
var _until_next := 0.0
var _log: Label


func _ready() -> void:
	var settings := DevToolSettings.load_default()
	_seconds_per_action = settings.demo_seconds_per_action
	_seed = settings.default_base_seed
	var bg := ColorRect.new()
	bg.color = Palette.BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	_log = Label.new()
	_log.add_theme_color_override("font_color", Palette.TEXT_DIM)
	_log.add_theme_font_size_override("font_size", 12)
	_log.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	_log.offset_top = -170
	_log.offset_left = 16
	_log.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	add_child(_log)
	overlay = DebugOverlay.new()
	overlay.position = Vector2(16, 16)
	add_child(overlay)
	_resolved = ScenarioFiles.load_scenario(SCENARIO_PATH).resolve()
	start_fight()


func start_fight() -> void:
	sim = _resolved.start(_seed)
	_seed += 1
	overlay.fight = sim.fight
	sim.fight.advance()
	_show_log()


## Plays one decision and refreshes the overlay. Once a fight is over, the
## next call starts a new one, so the end stays on screen for one beat.
func step() -> void:
	if sim.fight.is_over():
		start_fight()
		return
	sim.step()
	sim.fight.advance()
	overlay.refresh()
	_show_log()


func _process(delta: float) -> void:
	_until_next -= delta
	if _until_next <= 0.0:
		_until_next = _seconds_per_action
		step()


func _show_log() -> void:
	var lines := sim.fight.log_lines
	_log.text = "\n".join(lines.slice(maxi(0, lines.size() - 8)))
