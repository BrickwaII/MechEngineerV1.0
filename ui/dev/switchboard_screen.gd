class_name SwitchboardScreen
extends Control
## The variant switchboard: one picker per open design decision. A change is
## saved to user://variants.json at once and takes effect when its decision
## applies (live, next fight or next run, shown on each row). Options no code
## implements yet are listed but disabled.
##
## Run it alone (godot --path . res://ui/dev/switchboard_screen.tscn), from the
## dev menu, or press F4 in a run (RunFlow shows it over the game).

const Ui := preload("res://ui/dev/dev_ui.gd")
const Palette := preload("res://ui/dev/dev_palette.gd")
const NAME_WIDTH := 300.0
const PICKER_WIDTH := 380.0
const MARGIN := 32.0

## Emitted after every saved change, and after a reset.
signal changed
## Emitted by the Close button.
signal closed

## Set before the screen enters the tree; null loads user://variants.json.
var board: Switchboard
## Shows a Close button (for the in-run overlay).
var closable := false
## Decision id -> its picker.
var pickers: Dictionary[String, OptionButton] = {}
var summary_label: Label


func _ready() -> void:
	theme = Ui.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if board == null:
		board = Switchboard.load_board()
	var bg := ColorRect.new()
	bg.color = Palette.OVERLAY if closable else Palette.BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	bg.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(bg)
	var scroll := ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.offset_left = MARGIN
	scroll.offset_top = MARGIN * 0.75
	scroll.offset_right = -MARGIN
	scroll.offset_bottom = -MARGIN * 0.75
	add_child(scroll)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)
	var buttons: Array = [Ui.label("Variant switchboard", Palette.ACCENT, 20)]
	var reset := Ui.button("Reset all to defaults", reset_all)
	reset.name = "ResetButton"
	buttons.append(reset)
	if closable:
		var close := Ui.button("Close (F4)", func() -> void: closed.emit())
		close.name = "CloseButton"
		buttons.append(close)
	box.add_child(Ui.row(buttons))
	box.add_child(Ui.label(
		"Each change is saved at once to %s and applies as marked on its row." % board.user_path,
		Palette.TEXT_DIM, 13))
	summary_label = Ui.label("", Palette.WARNING, 13)
	summary_label.name = "SummaryLabel"
	box.add_child(summary_label)
	var layer := ""
	for d in board.decisions:
		if d.layer != layer:
			layer = d.layer
			var head := Ui.label("%s/" % layer, Palette.TEXT_DIM, 13)
			head.add_theme_constant_override("line_spacing", 0)
			box.add_child(head)
		box.add_child(_row(d))
	refresh()


## Picks `option` for decision `id` and saves. False if either is unknown or
## the option is not built.
func pick(id: String, option: String) -> bool:
	if not board.has_option(id, option) or not board.is_built(id, option):
		return false
	board.choose(id, option)
	_save_and_refresh()
	return true


func reset_all() -> void:
	board.reset()
	_save_and_refresh()


func refresh() -> void:
	for id in pickers:
		var picker := pickers[id]
		var chosen := board.option_of(id)
		for i in picker.item_count:
			if picker.get_item_metadata(i) == chosen:
				picker.select(i)
	var text := board.summary()
	summary_label.text = "Active non-default choices: " + (text if not text.is_empty() else "none, every decision plays its default")


func _row(d: Dictionary) -> HBoxContainer:
	var title := Ui.label(d.name)
	title.custom_minimum_size.x = NAME_WIDTH
	title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	var picker := OptionButton.new()
	picker.name = "Pick_" + str(d.id).replace("/", "_")
	picker.custom_minimum_size.x = PICKER_WIDTH
	picker.fit_to_longest_item = false
	for o: Dictionary in d.options:
		var text: String = o.name
		if o.id == d.default:
			text += "  (default)"
		if not o.built:
			text += "  (not built yet)"
		picker.add_item(text)
		var index := picker.item_count - 1
		picker.set_item_metadata(index, o.id)
		picker.set_item_disabled(index, not o.built)
		if not o.description.is_empty():
			picker.set_item_tooltip(index, o.description)
	var id: String = d.id
	picker.item_selected.connect(func(index: int) -> void: pick(id, picker.get_item_metadata(index)))
	pickers[id] = picker
	var marker := Ui.label(id, Palette.TEXT_DIM, 12)
	marker.custom_minimum_size.x = 150
	var applies := Ui.label(Switchboard.APPLIES_TEXT.get(d.applies, d.applies), Palette.TEXT_DIM, 12)
	return Ui.row([title, marker, picker, applies])


func _save_and_refresh() -> void:
	var error := board.save()
	if error != OK:
		push_error("SwitchboardScreen: cannot save %s (%s)" % [board.user_path, error_string(error)])
	refresh()
	changed.emit()
