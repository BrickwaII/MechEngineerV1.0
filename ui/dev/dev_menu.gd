extends Control
## Entry point to the dev screens. Run it with
##   godot --path . res://ui/dev/dev_menu.tscn

const Ui := preload("res://ui/dev/dev_ui.gd")
const RUN_SCENE := "res://ui/run/run_flow.tscn"
const ACTS_FILE := "res://data/tuning/acts.json"

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
	_add_map_variants(box)


## Map variants: one picker per act, and a button that plays a run on them.
func _add_map_variants(box: VBoxContainer) -> void:
	var plan := ActPlan.load_file(ACTS_FILE)
	if not plan.is_valid():
		return
	box.add_child(Ui.heading("Play a run on map variants"))
	var pickers: Array[OptionButton] = []
	for act in plan.act_count():
		var picker := OptionButton.new()
		picker.name = "Act%dVariant" % (act + 1)
		for variant: Dictionary in plan.variants(act):
			picker.add_item(variant["name"])
			picker.set_item_metadata(picker.item_count - 1, variant["id"])
			if variant["id"] == plan.chosen_variant(act):
				picker.select(picker.item_count - 1)
		pickers.append(picker)
		box.add_child(Ui.row([Ui.label("Act %d · %s" % [act + 1, plan.act_name(act)]), picker]))
	box.add_child(Ui.button("Play a run", func() -> void: play_run(_picked(pickers))))


static func _picked(pickers: Array[OptionButton]) -> PackedStringArray:
	var ids := PackedStringArray()
	for picker in pickers:
		ids.append(picker.get_item_metadata(picker.selected))
	return ids


## Opens a run that plays these map variants, one id per act.
func play_run(variant_ids: PackedStringArray) -> void:
	var run: Node = load(RUN_SCENE).instantiate()
	run.map_variants = variant_ids
	var tree := get_tree()
	tree.root.add_child(run)
	tree.current_scene = run
	queue_free()
