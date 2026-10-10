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
##
## Variants: F4 opens the variant switchboard (ui/dev/) over the game, and a
## corner label lists the active non-default choices. A new run reads the
## draft rule and the act maps from it; each fight reads the fight-side
## choices when it starts (RunFightService). The campaign's choices
## (CampaignVariants) are read from the same file: squad-size by the draft,
## the other next-run ones when the map starts a run, grid-cost-owner when
## each fight starts. Selecting a region on the map makes it the
## auto-expansion focus.

const DRAFT_SCENE := preload("res://ui/draft/draft_screen.tscn")
const OVERWORLD_SCENE := preload("res://ui/overworld/overworld.tscn")
const READOUT_SCENE := preload("res://ui/post_fight/post_fight_readout.tscn")

const SAVE_PATH := "user://run.res"
const NO_SEED := -1
const CONTINUE_SIZE := Vector2(220, 48)
const SCREEN_MARGIN := 24.0
const LABEL_MARGIN := 6.0
## Above every screen of the run, so the label and F4 screen always show.
const VARIANT_LAYER := 50

enum Stage { DRAFT, MAP, FIGHT, POST_FIGHT }

signal stage_changed(stage: Stage)

## Set before the flow enters the tree. NO_SEED draws a new seed per run.
@export var run_seed := NO_SEED
## Dev option: let the player choose act 1's start. In normal play the start
## is picked from the run seed and no choice is shown.
@export var choose_start := false
## Plays fights with AutoFightService instead of the battle screen.
@export var auto_fights := false
## Dev option: the map variant for each act, by act index ("" for the act's
## default). The dev menu sets it; see data/tuning/acts.json for the ids.
@export var map_variants: PackedStringArray = []
## The player's variant choices; tests point it elsewhere.
var variants_path := FightVariants.USER_PATH
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
## The switchboard as it stood when this run began: its draft rule and act
## maps hold for the whole run.
var run_board: Switchboard
## The F4 switchboard while it shows, or null.
var switchboard_screen: SwitchboardScreen
var variant_label: VariantLabel
var _variant_layer: CanvasLayer


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	_variant_layer = CanvasLayer.new()
	_variant_layer.name = "VariantLayer"
	_variant_layer.layer = VARIANT_LAYER
	add_child(_variant_layer)
	variant_label = VariantLabel.new()
	_variant_layer.add_child(variant_label)
	variant_label.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT, Control.PRESET_MODE_MINSIZE, int(LABEL_MARGIN))
	variant_label.grow_vertical = Control.GROW_DIRECTION_BEGIN
	get_tree().node_added.connect(_on_node_added)
	new_run()


func _exit_tree() -> void:
	# The campaign layer reads choices from this path; stop pointing it here.
	if CampaignVariants.user_path == variants_path:
		CampaignVariants.user_path = ""
	if get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.disconnect(_on_node_added)


func _input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and not key.echo and key.keycode == KEY_F4:
		toggle_switchboard()
		get_viewport().set_input_as_handled()


## Shows or hides the variant switchboard over the game.
func toggle_switchboard() -> void:
	if switchboard_screen != null:
		_free(switchboard_screen)
		switchboard_screen = null
		return
	switchboard_screen = SwitchboardScreen.new()
	switchboard_screen.name = "SwitchboardScreen"
	switchboard_screen.board = Switchboard.load_board(variants_path)
	switchboard_screen.closable = true
	switchboard_screen.changed.connect(func() -> void: variant_label.show_board(switchboard_screen.board))
	switchboard_screen.closed.connect(toggle_switchboard)
	_variant_layer.add_child(switchboard_screen)
	_variant_layer.move_child(variant_label, -1)


## Drops the run in progress and opens the draft for a new one.
func new_run() -> void:
	_close_all()
	squad = null
	ledger = null
	current_seed = run_seed if run_seed != NO_SEED else randi()
	CampaignVariants.user_path = variants_path
	run_board = Switchboard.load_board(variants_path)
	variant_label.show_board(run_board)
	draft_screen = DRAFT_SCENE.instantiate()
	draft_screen.draft_seed = current_seed
	draft_screen.bot_tuning = run_bot_tuning()
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


## Bot tuning for this run's draft: data/bot_data/ with the switchboard's
## draft rule and squad size.
func run_bot_tuning() -> BotTuning:
	var tuning := BotTuning.load_default()
	var rule := run_board.draft_rule() if run_board != null else ""
	if rule in BotTuning.DRAFT_RULES:
		tuning.draft_rule = rule
	var sizes := CampaignVariants.load_active(variants_path).squad_sizes()
	if not sizes.is_empty():
		tuning.draft_size = sizes.draft_size
		tuning.squad_size = sizes.squad_size
	return tuning


## The map variant per act this run plays: map_variants when set (the dev
## menu, tests), else the switchboard's act maps.
func run_map_variants() -> PackedStringArray:
	if not map_variants.is_empty() or run_board == null:
		return map_variants
	return run_board.act_map_variants()


## The start this run's seed gives, one of `options`.
func seeded_start(options: Array) -> String:
	return options[posmod(current_seed, options.size())].id


func _on_squad_chosen(_summaries: Array[SquadMemberSummary]) -> void:
	start_map(draft_screen.picker.squad, SkillUseLedger.new())


func _open_overworld() -> void:
	overworld = OVERWORLD_SCENE.instantiate()
	if not region_file.is_empty():
		overworld.region_file = region_file
	overworld.act_variants = run_map_variants()
	_hand_services_to(overworld)
	overworld.save_action = func() -> void: save_run()
	overworld.load_action = func() -> void: load_run()
	overworld.new_run_action = new_run
	if not choose_start:
		overworld.start_picker = seeded_start
	add_child(overworld)


## Gives `screen` real contracts implementations over the current squad.
## They are read when its next Campaign is made.
func _hand_services_to(screen: Control) -> void:
	var inner: FightService
	if auto_fights:
		inner = AutoFightService.new()
	else:
		var scene_service := FightSceneService.new(self, fight_screen_tuning)
		scene_service.bot_source = func(id: String) -> Bot: return squad.get_bot(id) if squad != null else null
		scene_service.screen_opened.connect(_on_screen_opened)
		inner = scene_service
	fight_service = RunFightService.new(inner, squad, ledger)
	var path := variants_path
	fight_service.variants_source = func() -> FightVariants: return FightVariants.load_active(path)
	fight_service.campaign_variants_source = func() -> CampaignVariants: return CampaignVariants.load_active(path)
	fight_service.fight_reported.connect(_on_fight_reported)
	fight_service.finished.connect(_on_fight_finished)
	screen.squad_provider = BotSquadProvider.new(squad)
	screen.fight_service = fight_service


## A map view joining the tree (the overworld's, flat or globe): selecting a
## region on it makes that region the campaign's expansion focus.
func _on_node_added(node: Node) -> void:
	if node.has_signal("region_selected") and overworld != null and overworld.is_ancestor_of(node):
		node.connect("region_selected", _on_region_selected)


func _on_region_selected(region_id: String) -> void:
	if overworld != null and overworld.campaign != null:
		overworld.campaign.set_focus(region_id)


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
