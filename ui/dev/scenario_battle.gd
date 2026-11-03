class_name ScenarioBattle
extends Control
## Plays a fight scenario (data/scenarios, FightScenario) by hand on the
## battle screen, for playtests (combat rework S9, played in S10). The squad,
## the kit, the listed enemies and the opening gauge spread are the
## scenario's; the player picks every bot action and enemies act on their
## intents, as in a run. The scenario's policies are for the harness and are
## not used here.
##
## Dev only: opened from the dev menu ("Sandbox fight") and the scenario
## builder ("Play on battle screen"). An ActionSharePanel (F6) shows the live
## action-use share of this fight and of every fight played here; the
## DebugOverlay (F3, hidden at first) shows gauges, energy and intents.
## When a fight ends: play the next seed, the same seed again, or go back.
##
##   var battle := ScenarioBattle.open(get_tree(), scenario, 7)

const Ui := preload("res://ui/dev/dev_ui.gd")
const Palette := preload("res://ui/dev/dev_palette.gd")
const SANDBOX_PATH := "res://data/scenarios/sandbox_3v3.json"
const SCENE_PATH := "res://ui/dev/scenario_battle.tscn"
const DEV_MENU := "res://ui/dev/dev_menu.tscn"
## Room left under the action-use panel for the battle screen's action dock.
const PANEL_BOTTOM_GAP := 150.0

## The scenario played; null plays the sandbox.
var scenario: FightScenario
var fight_seed := 1
## Where Back goes: a scene path.
var back_scene := DEV_MENU
## Battle screen tuning; null means data/ui/fight_screen.json. Tests set a fast one.
var screen_tuning: FightScreenTuning

var service: FightSceneService
var share_panel: ActionSharePanel
var overlay: DebugOverlay
var resolved: ResolvedScenario
## The last result, for tests.
var last_result: FightResult

var _end_bar: PanelContainer
var _end_label: Label
var _problem_label: Label


## Replaces the current scene with a ScenarioBattle playing `p_scenario` from
## `seed_value`. Returns the new scene.
static func open(tree: SceneTree, p_scenario: FightScenario, seed_value: int, p_back_scene := DEV_MENU) -> ScenarioBattle:
	var battle: ScenarioBattle = (load(SCENE_PATH) as PackedScene).instantiate()
	battle.scenario = p_scenario
	battle.fight_seed = seed_value
	battle.back_scene = p_back_scene
	var old := tree.current_scene
	tree.root.add_child(battle)
	tree.current_scene = battle
	if old != null:
		old.queue_free()
	return battle


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = Ui.theme()
	Ui.background(self)
	if scenario == null:
		scenario = ScenarioFiles.load_scenario(SANDBOX_PATH)
	resolved = scenario.resolve()
	service = FightSceneService.new(self, screen_tuning)
	service.combat_tuning = resolved.tuning
	service.enemy_table = resolved.enemy_table
	service.screen_opened.connect(_on_screen_opened)
	service.finished.connect(_on_finished)
	_build()
	if not resolved.is_playable():
		_problem_label.text = "Cannot play %s: %s" % [scenario.scenario_name, "; ".join(resolved.problems)]
		_problem_label.visible = true
		_show_end_bar("")
		return
	start_fight(fight_seed)


## Starts the scenario's fight for `seed_value` on a fresh battle screen.
func start_fight(seed_value: int) -> void:
	if service.screen != null:
		return
	fight_seed = seed_value
	_end_bar.visible = false
	service.fixed_seed = seed_value
	service.start_fight(resolved.request)


func _on_screen_opened(screen: BattleScreen) -> void:
	move_child(screen, 1)
	screen.show_home_button(func() -> void: go_back())
	share_panel.fight = screen.fight
	overlay.fight = screen.fight
	# F7: the battle debugger (S9b) on this fight.
	BattleDebugger.install(screen)


func _on_finished(result: FightResult) -> void:
	last_result = result
	share_panel.refresh()
	_show_end_bar("%s · %s · seed %d · %d decisions, both sides" % [
		scenario.scenario_name, "VICTORY" if result.is_victory() else "DEFEAT", fight_seed,
		share_panel.fight.action_count if share_panel.fight != null else 0])


func go_back() -> void:
	get_tree().change_scene_to_file(back_scene)


func _show_end_bar(text: String) -> void:
	_end_label.text = text
	_end_label.visible = not text.is_empty()
	_end_bar.visible = true


func _build() -> void:
	share_panel = ActionSharePanel.new()
	# Bottom middle, between the squad and the enemies, above the action dock.
	share_panel.set_anchors_and_offsets_preset(Control.PRESET_CENTER_BOTTOM)
	share_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	share_panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	share_panel.offset_bottom = -PANEL_BOTTOM_GAP
	add_child(share_panel)
	overlay = DebugOverlay.new()
	overlay.position = Vector2(16, 64)
	overlay.visible = false
	add_child(overlay)

	_end_bar = Ui.panel()
	_end_bar.set_anchors_and_offsets_preset(Control.PRESET_CENTER)
	_end_bar.grow_horizontal = Control.GROW_DIRECTION_BOTH
	_end_bar.grow_vertical = Control.GROW_DIRECTION_BOTH
	_end_bar.visible = false
	add_child(_end_bar)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	_end_bar.add_child(box)
	_end_label = Ui.label("", Palette.TEXT, 16)
	_end_label.name = "EndLabel"
	box.add_child(_end_label)
	_problem_label = Ui.label("", Palette.ENEMY)
	_problem_label.visible = false
	box.add_child(_problem_label)
	var next := Ui.button("Next seed", func() -> void: start_fight(fight_seed + 1))
	next.name = "NextSeedButton"
	var again := Ui.button("Same seed again", func() -> void: start_fight(fight_seed))
	again.name = "AgainButton"
	var back := Ui.button("Back", go_back)
	back.name = "BackButton"
	box.add_child(Ui.row([next, again, back]))
	if not resolved.is_playable():
		next.disabled = true
		again.disabled = true
