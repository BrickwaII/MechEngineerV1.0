extends Control
## Entry point to the dev screens. Run it with
##   godot --path . res://ui/dev/dev_menu.tscn
## Map variants per act and the draft rule are picked on the variant
## switchboard, with every other open decision.

const Ui := preload("res://ui/dev/dev_ui.gd")
const RUN_SCENE := "res://ui/run/run_flow.tscn"
const Palette := preload("res://ui/dev/dev_palette.gd")

const SCREENS := [
	["Variant switchboard (also F4 in a run)", "res://ui/dev/switchboard_screen.tscn"],
	["Robot and enemy builder", "res://ui/dev/bot_builder.tscn"],
	["Scenario builder and batch runs", "res://ui/dev/scenario_builder.tscn"],
	["Debug overlay demo", "res://ui/dev/debug_overlay_demo.tscn"],
]


func _ready() -> void:
	theme = Ui.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	Ui.background(self)
	var box := VBoxContainer.new()
	box.position = Vector2(40, 40)
	box.add_theme_constant_override("separation", 10)
	add_child(box)
	box.add_child(Ui.heading("Mech Engineer dev tools"))
	for screen: Array in SCREENS:
		var path: String = screen[1]
		box.add_child(Ui.button(screen[0], func() -> void: get_tree().change_scene_to_file(path)))
	box.add_child(Ui.heading("Play a run"))
	box.add_child(Ui.label(
		"Plays the switchboard's choices, act maps and draft rule included.", Palette.TEXT_DIM, 13))
	var play := Ui.button("Play a run", func() -> void: play_run(PackedStringArray()))
	play.name = "PlayRunButton"
	box.add_child(play)


## Opens a run that plays these map variants, one id per act; empty plays the
## switchboard's act maps.
func play_run(variant_ids: PackedStringArray) -> void:
	var run: Node = load(RUN_SCENE).instantiate()
	run.map_variants = variant_ids
	var tree := get_tree()
	tree.root.add_child(run)
	tree.current_scene = run
	queue_free()
