extends Control
## Entry point to the dev screens. Run it with
##   godot --path . res://ui/dev/dev_menu.tscn

const Ui := preload("res://ui/dev/dev_ui.gd")

const SCREENS := [
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
