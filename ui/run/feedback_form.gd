class_name FeedbackForm
extends Control
## The F8 feedback form, over a paused game: a note, a category, a mood
## rating, and buttons to save the report, open the run folder, or cancel
## (Esc). Categories and the rating range come from data/run/run_data.json.
## RunFlow takes the screenshot before the form shows and writes the report
## (FeedbackReport) on `submitted`.

const PANEL_SIZE := Vector2(560, 440)
const NOTE_HEIGHT := 150.0
const MOOD_BUTTON_SIZE := Vector2(48, 40)

signal submitted(note: String, category: String, rating: int)
signal cancelled
signal open_folder_requested

var settings: RunDataSettings
## What the form says the report will hold, under the title.
var context_text := ""
var note_edit: TextEdit
var category_picker: OptionButton
var mood_buttons: Array[Button] = []
var save_button: Button
var folder_button: Button
var cancel_button: Button
var status_label: Label


func _ready() -> void:
	if settings == null:
		settings = RunDataSettings.load_default()
	process_mode = Node.PROCESS_MODE_ALWAYS
	theme = ScreenTheme.theme()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var dim := ColorRect.new()
	dim.color = Color(FeelData.color("background"), 0.75)
	dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = PANEL_SIZE
	var style := StyleBoxFlat.new()
	style.bg_color = FeelData.color("panel")
	style.border_color = FeelData.color("panel_border_light")
	style.set_border_width_all(2)
	style.set_content_margin_all(18)
	panel.add_theme_stylebox_override("panel", style)
	center.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 10)
	panel.add_child(box)
	box.add_child(_label("FEEDBACK REPORT  ·  F8", "accent", 20))
	box.add_child(_label("The game is paused. A screenshot, the save and the journal go with your note.", "text_dim", 10))
	if not context_text.is_empty():
		box.add_child(_label(context_text, "text_dim", 10))
	note_edit = TextEdit.new()
	note_edit.name = "Note"
	note_edit.placeholder_text = "What happened? What did you expect?"
	note_edit.custom_minimum_size = Vector2(0, NOTE_HEIGHT)
	note_edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	box.add_child(note_edit)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	box.add_child(row)
	row.alignment = BoxContainer.ALIGNMENT_BEGIN
	row.add_child(_label("Category", "text", 10, false))
	category_picker = OptionButton.new()
	category_picker.name = "Category"
	for c in settings.feedback_categories:
		category_picker.add_item(c)
	row.add_child(category_picker)
	var mood_row := HBoxContainer.new()
	mood_row.add_theme_constant_override("separation", 6)
	box.add_child(mood_row)
	mood_row.add_child(_label("Mood  (%d awful, %d great)" % [settings.mood_min, settings.mood_max], "text", 10, false))
	var group := ButtonGroup.new()
	for value in range(settings.mood_min, settings.mood_max + 1):
		var b := Button.new()
		b.name = "Mood%d" % value
		b.text = str(value)
		b.toggle_mode = true
		b.button_group = group
		b.custom_minimum_size = MOOD_BUTTON_SIZE
		b.button_pressed = value == settings.mood_default
		mood_row.add_child(b)
		mood_buttons.append(b)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 10)
	box.add_child(buttons)
	save_button = _button("SAVE REPORT", _on_save)
	folder_button = _button("OPEN RUN FOLDER", func() -> void: open_folder_requested.emit())
	cancel_button = _button("CANCEL", func() -> void: cancelled.emit())
	for b in [save_button, folder_button, cancel_button]:
		buttons.add_child(b)
	status_label = _label("", "warning", 10)
	box.add_child(status_label)
	_focus_note.call_deferred()


func _focus_note() -> void:
	if is_inside_tree():
		note_edit.grab_focus()


func _unhandled_key_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key != null and key.pressed and key.keycode == KEY_ESCAPE:
		cancelled.emit()
		get_viewport().set_input_as_handled()


## The chosen rating.
func rating() -> int:
	for i in mood_buttons.size():
		if mood_buttons[i].button_pressed:
			return settings.mood_min + i
	return settings.mood_default


func category() -> String:
	return category_picker.get_item_text(category_picker.selected) if category_picker.selected >= 0 else ""


func _on_save() -> void:
	submitted.emit(note_edit.text.left(settings.note_max_chars), category(), rating())


func _label(text: String, color: String, font_size: int, wrap := true) -> Label:
	var l := Label.new()
	l.text = text
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	l.add_theme_color_override("font_color", FeelData.color(color))
	l.add_theme_font_size_override("font_size", ScreenTheme.size(font_size))
	return l


func _button(text: String, on_press: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.name = text.capitalize().replace(" ", "") + "Button"
	b.pressed.connect(on_press)
	return b
