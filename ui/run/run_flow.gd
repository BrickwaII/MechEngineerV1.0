class_name RunFlow
extends Control
## One run of the game, from the draft to the end:
##
##   new run -> squad draft (seeded) -> overworld -> attack or forced defense
##   -> battle screen -> result back to the map -> post-fight readout -> map
##
## The overworld is handed real contracts implementations: BotSquadProvider
## over the drafted bots, and a RunFightService that plays fights on the
## battle screen and applies PostFight to the bots when each one ends. The
## map code does not know any of this.
##
## Save and load go through RunSave, so a save holds the bots as well as the
## map. F3 on the battle screen shows the debug overlay (hidden by default).

const DRAFT_SCENE := preload("res://ui/draft/draft_screen.tscn")
const OVERWORLD_SCENE := preload("res://ui/overworld/overworld.tscn")
const READOUT_SCENE := preload("res://ui/post_fight/post_fight_readout.tscn")

const SAVE_PATH := "user://run.tres"
const NO_SEED := -1
const CONTINUE_SIZE := Vector2(220, 48)
const SCREEN_MARGIN := 24.0

enum Stage { DRAFT, MAP, FIGHT, POST_FIGHT }

signal stage_changed(stage: Stage)

## Set before the flow enters the tree. NO_SEED draws a new seed per run.
@export var run_seed := NO_SEED
## Plays fights with AutoFightService instead of the battle screen.
@export var auto_fights := false
## Battle screen tuning; null means data/ui/fight_screen.json.
var fight_screen_tuning: FightScreenTuning
## Set on the overworld when it is made, as its own exports: tests use them.
var region_file := ""
var save_path := SAVE_PATH

var stage := Stage.DRAFT
## The seed this run's draft came from.
var current_seed := 0
var squad: BotSquad
var ledger: SkillUseLedger
var fight_service: RunFightService

var draft_screen: DraftScreen
## The overworld screen (ui/overworld/overworld.gd), or null during the draft.
var overworld: Control
## The battle screen of the fight in progress, or null.
var battle_screen: BattleScreen
var debug_overlay: DebugOverlay
## The post-fight readout while it shows, or null.
var readout: Control
var continue_button: Button


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	new_run()


## Drops the run in progress and opens the draft for a new one.
func new_run() -> void:
	_close_all()
	squad = null
	ledger = null
	current_seed = run_seed if run_seed != NO_SEED else randi()
	draft_screen = DRAFT_SCENE.instantiate()
	draft_screen.draft_seed = current_seed
	draft_screen.squad_chosen.connect(_on_squad_chosen)
	add_child(draft_screen)
	draft_screen.start_button.text = "DEPLOY SQUAD"
	_set_stage(Stage.DRAFT)


## Takes the drafted squad to the map, where the start choice opens.
func start_map(p_squad: BotSquad, p_ledger: SkillUseLedger) -> void:
	_close_all()
	squad = p_squad
	ledger = p_ledger
	_open_overworld()
	_set_stage(Stage.MAP)


## Closes the post-fight readout and shows the map again.
func continue_to_map() -> void:
	if readout == null:
		return
	_free(readout)
	readout = null
	continue_button = null
	overworld.visible = true
	_set_stage(Stage.MAP)


## Saves the map, the bots and the banked skill uses in one file.
func save_run(path := save_path) -> Error:
	if overworld == null or overworld.campaign == null or overworld.campaign.fighting:
		return ERR_BUSY
	var error := RunSave.make(current_seed, squad, ledger, overworld.campaign.state).save_file(path)
	overworld.log_event("Run saved." if error == OK else "Could not save the run (%s)." % error_string(error))
	return error


## Continues the run saved at `path`: the same bots, map state and act.
## False, with the current run kept, if there is no usable save.
func load_run(path := save_path) -> bool:
	var save := RunSave.load_file(path)
	if save == null:
		if overworld != null:
			overworld.log_event("No saved run.")
		return false
	if overworld == null:
		start_map(save.squad, save.ledger)
		current_seed = save.run_seed
		if overworld.load_state(save.run_state()):
			return true
		new_run()
		return false
	var kept := [squad, ledger, fight_service, overworld.squad_provider, overworld.fight_service]
	squad = save.squad
	ledger = save.ledger
	_hand_services_to(overworld)
	if not overworld.load_state(save.run_state()):
		squad = kept[0]
		ledger = kept[1]
		fight_service = kept[2]
		overworld.squad_provider = kept[3]
		overworld.fight_service = kept[4]
		return false
	current_seed = save.run_seed
	_close_readout_and_show_map()
	return true


func _on_squad_chosen(_summaries: Array[SquadMemberSummary]) -> void:
	start_map(draft_screen.picker.squad, SkillUseLedger.new())


func _open_overworld() -> void:
	overworld = OVERWORLD_SCENE.instantiate()
	if not region_file.is_empty():
		overworld.region_file = region_file
	_hand_services_to(overworld)
	overworld.save_action = func() -> void: save_run()
	overworld.load_action = func() -> void: load_run()
	overworld.new_run_action = new_run
	add_child(overworld)


## Gives `screen` real contracts implementations over the current squad.
## They are read when its next Campaign is made.
func _hand_services_to(screen: Control) -> void:
	var inner: FightService
	if auto_fights:
		inner = AutoFightService.new()
	else:
		var scene_service := FightSceneService.new(self, fight_screen_tuning)
		scene_service.screen_opened.connect(_on_screen_opened)
		inner = scene_service
	fight_service = RunFightService.new(inner, squad, ledger)
	fight_service.fight_reported.connect(_on_fight_reported)
	fight_service.finished.connect(_on_fight_finished)
	screen.squad_provider = BotSquadProvider.new(squad)
	screen.fight_service = fight_service


func _on_screen_opened(screen: BattleScreen) -> void:
	battle_screen = screen
	overworld.visible = false
	debug_overlay = DebugOverlay.new()
	debug_overlay.visible = false
	# Show the intents the screen telegraphs, which are what enemies do.
	debug_overlay.intent_source = func(f: Fight, unit: Combatant) -> String: return screen.telegraph.intent_text(f, unit.id)
	screen.add_child(debug_overlay)
	debug_overlay.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT, Control.PRESET_MODE_MINSIZE, int(SCREEN_MARGIN))
	debug_overlay.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	debug_overlay.fight = screen.fight
	_set_stage(Stage.FIGHT)


func _on_fight_reported(report: PostFightReport, _result: FightResult) -> void:
	battle_screen = null
	debug_overlay = null
	overworld.visible = false
	readout = READOUT_SCENE.instantiate()
	add_child(readout)
	readout.show_report(report)
	continue_button = Button.new()
	continue_button.name = "ContinueButton"
	continue_button.text = "BACK TO THE MAP"
	continue_button.custom_minimum_size = CONTINUE_SIZE
	continue_button.pressed.connect(continue_to_map)
	readout.add_child(continue_button)
	continue_button.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT, Control.PRESET_MODE_MINSIZE, int(SCREEN_MARGIN))
	continue_button.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	continue_button.grow_vertical = Control.GROW_DIRECTION_BEGIN
	_set_stage(Stage.POST_FIGHT)


## A fight with no report (a stub service) goes straight back to the map.
func _on_fight_finished(_result: FightResult) -> void:
	battle_screen = null
	debug_overlay = null
	if readout == null:
		_close_readout_and_show_map()


func _close_readout_and_show_map() -> void:
	if readout != null:
		continue_to_map()
		return
	if overworld != null:
		overworld.visible = true
		_set_stage(Stage.MAP)


func _close_all() -> void:
	for node: Node in [draft_screen, overworld, readout, battle_screen]:
		_free(node)
	draft_screen = null
	overworld = null
	readout = null
	continue_button = null
	battle_screen = null
	debug_overlay = null


func _set_stage(p_stage: Stage) -> void:
	stage = p_stage
	stage_changed.emit(stage)


static func _free(node: Node) -> void:
	if node != null and is_instance_valid(node):
		if node.get_parent() != null:
			node.get_parent().remove_child(node)
		node.queue_free()
