extends Control
## The battle debugger (S9b) on the sandbox fight: a battle screen with the
## debugger open and the fight paused. Run it from the dev menu, or with
##   godot --path . res://ui/dev/battle_debugger/battle_debugger_demo.tscn

const BATTLE_SCENE := "res://ui/fight/battle_screen.tscn"
const SCENARIO_PATH := "res://data/scenarios/sandbox_3v3.json"

var screen: BattleScreen
var debugger: BattleDebugger


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var resolved := ScenarioFiles.load_scenario(SCENARIO_PATH).resolve()
	screen = load(BATTLE_SCENE).instantiate()
	screen.setup(resolved.request, DevToolSettings.load_default().default_base_seed, null,
		resolved.tuning, resolved.enemy_table)
	add_child(screen)
	debugger = BattleDebugger.attach(screen, true)
	debugger.visible = true
