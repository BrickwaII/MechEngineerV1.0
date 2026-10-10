extends Control
## Runnable demo: draft a squad, play the fight, read the result.
## draft -> fight -> result text, then back to the draft.

const Palette := preload("res://ui/fight/fight_palette.gd")
const DRAFT_SCENE := preload("res://ui/draft/draft_screen.tscn")

var tuning: FightScreenTuning
var service: FightSceneService
var draft: DraftScreen
var result_panel: VBoxContainer
var result_label: Label
## The last result reported, for tests.
var last_result: FightResult


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	theme = PixelTheme.theme()
	tuning = FightScreenTuning.load_default()
	service = FightSceneService.new(self, tuning)
	service.finished.connect(_on_finished)
	var back := ColorRect.new()
	back.color = Palette.BACKGROUND
	back.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	_build_result_panel()
	show_draft()


func show_draft() -> void:
	result_panel.visible = false
	draft = DRAFT_SCENE.instantiate()
	draft.draft_seed = tuning.demo_draft_seed
	draft.squad_chosen.connect(_on_squad_chosen)
	add_child(draft)


func _on_squad_chosen(squad: Array[SquadMemberSummary]) -> void:
	draft.queue_free()
	draft = null
	service.start_fight(FightRequest.new(
		FightRequest.Kind.ATTACK, tuning.demo_territory_id, tuning.demo_defense_level, squad))


func _on_finished(result: FightResult) -> void:
	last_result = result
	result_label.text = describe(result)
	result_panel.visible = true


static func describe(result: FightResult) -> String:
	var lines := PackedStringArray()
	lines.append("VICTORY" if result.is_victory() else "DEFEAT")
	lines.append("Grid cost: %.1f%%" % result.grid_cost)
	if result.rewards.is_empty():
		lines.append("Rewards: none")
	else:
		var parts := PackedStringArray()
		for key in result.rewards:
			parts.append("%s %d" % [key, result.rewards[key]])
		lines.append("Rewards: " + ", ".join(parts))
	return "\n".join(lines)


func _build_result_panel() -> void:
	result_panel = VBoxContainer.new()
	result_panel.set_anchors_preset(Control.PRESET_CENTER)
	result_panel.grow_horizontal = Control.GROW_DIRECTION_BOTH
	result_panel.grow_vertical = Control.GROW_DIRECTION_BOTH
	result_panel.alignment = BoxContainer.ALIGNMENT_CENTER
	result_panel.add_theme_constant_override("separation", 16)
	add_child(result_panel)
	result_label = Label.new()
	result_label.name = "ResultLabel"
	result_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	result_label.theme_type_variation = &"TitleLabel"
	result_label.add_theme_color_override("font_color", Palette.TEXT_BRIGHT)
	result_panel.add_child(result_label)
	var again := Button.new()
	again.name = "AgainButton"
	again.text = "DRAFT AGAIN"
	again.custom_minimum_size = Vector2(200, 40)
	again.pressed.connect(show_draft)
	result_panel.add_child(again)
