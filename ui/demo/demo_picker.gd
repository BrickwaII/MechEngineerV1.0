class_name DemoPicker
extends Control
## The demo picker, from the main menu's DEMO button: every scenario in
## data/demo/ as a card (its type's icon, name, one line; hover for a longer
## one), in a column per act under the act's name and color, and an "Other
## screens" column for the steps and screens (globe, forced defense,
## pre-fight, fast-forward, run over). Clicking a card emits scenario_chosen; MAIN MENU emits
## back_requested. Nothing here or in a demo is saved.

signal scenario_chosen(scenario: DemoScenario)
signal back_requested

const CARD_SIZE := Vector2(0, 92)
const COLUMN_GAP := 14
## Each act's column color (data/feel/palette.json names).
const ACT_COLORS: Array[String] = ["ally", "warning", "energy"]
## The group key of the "Other screens" column.
const OTHER := "other"
const ACTS_FILE := "res://data/tuning/acts.json"

## Where scenarios are read from; tests point it elsewhere.
var scenario_dir := DemoScenario.DEFAULT_DIR

var scenarios: Array[DemoScenario] = []
## Scenario id -> its card.
var cards: Dictionary[String, Button] = {}
var back_button: ActionButton
## The columns, side by side.
var _rows: HBoxContainer


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = ScreenTheme.theme()
	_build()
	refresh()


## Reads the scenarios again and rebuilds the columns: one per act (its
## name over a band in the act's color), then "Other screens".
func refresh() -> void:
	scenarios = DemoScenario.load_all(scenario_dir)
	cards.clear()
	for child in _rows.get_children():
		_rows.remove_child(child)
		child.queue_free()
	var plan := ActPlan.load_file(ACTS_FILE)
	var columns := {}
	for act in [1, 2, 3]:
		var act_name := plan.act_name(act - 1) if plan.is_valid() else ""
		columns[act] = _column("Act%d" % act, "ACT %d" % act, act_name.to_upper(), ACT_COLORS[act - 1])
	columns[OTHER] = _column("Other", "OTHER SCREENS", "STEPS AND SCREENS", "text_dim")
	for s in scenarios:
		var other := s.group == OTHER
		var key: Variant = OTHER if other else s.act
		var card := _card(s, other)
		(columns[key] as VBoxContainer).add_child(card)
		cards[s.id] = card


## Plays the scenario with this id, as clicking its card does.
func choose(scenario_id: String) -> void:
	if cards.has(scenario_id):
		cards[scenario_id].pressed.emit()


func _column(node_name: String, title: String, subtitle: String, color: String) -> VBoxContainer:
	var col := VBoxContainer.new()
	col.name = node_name
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 8)
	_rows.add_child(col)
	var head := PanelContainer.new()
	head.name = "%sHeader" % node_name
	var style := StyleBoxFlat.new()
	style.bg_color = Color(FeelData.color(color), 0.18)
	style.border_color = FeelData.color(color)
	style.border_width_top = 4
	style.set_content_margin_all(8)
	head.add_theme_stylebox_override("panel", style)
	col.add_child(head)
	var titles := VBoxContainer.new()
	titles.add_theme_constant_override("separation", 2)
	head.add_child(titles)
	titles.add_child(_label(title, color, 20))
	if not subtitle.is_empty():
		titles.add_child(_label(subtitle, "text_dim", 10))
	return col


func _card(s: DemoScenario, show_act := false) -> Button:
	var card := Button.new()
	card.name = "Card_%s" % s.id
	card.custom_minimum_size = CARD_SIZE
	card.focus_mode = Control.FOCUS_NONE
	card.disabled = not s.is_valid()
	card.pressed.connect(func() -> void:
		SoundPlayer.fire(&"ui_confirm")
		scenario_chosen.emit(s))
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.offset_left = 12
	row.offset_right = -12
	row.offset_top = 8
	row.offset_bottom = -8
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(row)
	var icon := UiIcons.rect(s.icon if UiIcons.has(s.icon) else "unknown")
	icon.custom_minimum_size = UiIcons.icon_size() * 2.0
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.alignment = BoxContainer.ALIGNMENT_CENTER
	text.add_theme_constant_override("separation", 4)
	text.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(text)
	var title := _label(s.scenario_name + ("  · A%d" % s.act if show_act else ""), "text_bright", 20)
	title.name = "Name"
	text.add_child(title)
	var line := _label(s.description if s.is_valid() else "Cannot play: " + "; ".join(s.errors), "text_dim" if s.is_valid() else "danger", 10)
	line.name = "Description"
	text.add_child(line)
	# The card grows to its text: a long name or line wraps, never spills.
	row.minimum_size_changed.connect(func() -> void:
		card.custom_minimum_size.y = maxf(CARD_SIZE.y, row.get_combined_minimum_size().y + 16.0))
	UiTooltip.attach(card, s.scenario_name, s.details if not s.details.is_empty() else s.description,
		"Act %d" % s.act, s.icon if UiIcons.has(s.icon) else "")
	return card


func _build() -> void:
	var back := ColorRect.new()
	back.color = FeelData.color("background")
	back.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(back)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 24)
	add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 14)
	margin.add_child(column)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	column.add_child(head)
	var titles := VBoxContainer.new()
	titles.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(titles)
	titles.add_child(_label("DEMOS", "accent", 30))
	titles.add_child(_label("Jump into any act, fight or boss. Demos are never saved.", "text_dim", 10))
	back_button = ActionButton.make("action_home", "Main menu")
	back_button.name = "BackButton"
	back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	back_button.pressed.connect(func() -> void:
		SoundPlayer.fire(&"ui_back")
		back_requested.emit())
	head.add_child(back_button)
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	_rows = HBoxContainer.new()
	_rows.name = "Columns"
	_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_rows.add_theme_constant_override("separation", COLUMN_GAP)
	scroll.add_child(_rows)


func _label(text: String, color: String, font_size: int) -> Label:
	var l := Label.new()
	l.text = text
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.mouse_filter = Control.MOUSE_FILTER_IGNORE
	l.add_theme_color_override("font_color", FeelData.color(color))
	l.add_theme_font_size_override("font_size", ScreenTheme.size(font_size))
	return l
