extends PanelContainer
## One unit on the battle screen: placeholder shape, name and personality tag,
## HP and energy bars, a status line, and a preview line for the choice being
## considered. Enemy panels also telegraph their intent, marked for a turn
## when it changes.
## Emits clicked with the mouse button and hovered when the pointer enters or
## leaves; the battle screen turns those into FightCommands and previews.

const Palette := preload("res://ui/fight/fight_palette.gd")
const StatBar := preload("res://ui/fight/stat_bar.gd")
const UnitShape := preload("res://ui/fight/unit_shape.gd")

enum Highlight { NONE, ACTIVE, SELECTED, TARGETABLE }

signal clicked(unit_id: String, button_index: MouseButton)
signal hovered(unit_id: String, inside: bool)

var unit_id := ""
var is_enemy := false
var highlight := Highlight.NONE
var shape: UnitShape
var name_label: Label
var hp_bar: StatBar
var energy_bar: StatBar
var status_label: Label
## Personality tag, for example "aggressive".
var tag_label: Label
## Enemy intent telegraph: "Intent: Strike -> Ace (6)". Enemies only.
var intent_label: Label
## "changed: <why>" while the intent is marked as revised. Enemies only.
var change_label: Label
## What the previewed choice would do to this unit, or empty.
var preview_label: Label
## True while the intent is marked as revised.
var intent_changed := false

var _style := StyleBoxFlat.new()


func setup(unit: Combatant) -> void:
	unit_id = unit.id
	is_enemy = unit.side == Combatant.Side.ENEMY
	name = "Unit_%s" % unit.id.validate_node_name()
	mouse_filter = Control.MOUSE_FILTER_STOP
	custom_minimum_size = Vector2(250, 0)
	_style.bg_color = Palette.PANEL
	_style.set_border_width_all(2)
	_style.set_corner_radius_all(4)
	_style.set_content_margin_all(8)
	add_theme_stylebox_override("panel", _style)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	shape = UnitShape.new()
	shape.setup(is_enemy, unit.display_name)
	row.add_child(shape)
	var col := VBoxContainer.new()
	col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 3)
	col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(col)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 8)
	name_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	col.add_child(name_row)
	name_label = _label(name_row, unit.display_name, 15, Palette.TEXT_BRIGHT)
	tag_label = _label(name_row, "", 11, Palette.TAG)
	tag_label.name = "TagLabel"
	tag_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hp_bar = StatBar.new()
	col.add_child(hp_bar)
	energy_bar = StatBar.new()
	col.add_child(energy_bar)
	status_label = _label(col, "", 11, Palette.TEXT_DIM)
	if is_enemy:
		intent_label = _label(col, "Intent: ?", 11, Palette.TARGETABLE)
		intent_label.name = "IntentLabel"
		change_label = _label(col, "", 11, Palette.CHANGED)
		change_label.name = "ChangeLabel"
		change_label.visible = false
	preview_label = _label(col, "", 12, Palette.PREVIEW)
	preview_label.name = "PreviewLabel"
	preview_label.visible = false
	mouse_entered.connect(func() -> void: hovered.emit(unit_id, true))
	mouse_exited.connect(func() -> void: hovered.emit(unit_id, false))
	refresh(unit, Highlight.NONE)


func refresh(unit: Combatant, p_highlight: Highlight) -> void:
	highlight = p_highlight
	var hp_color := Palette.HP_LOW if unit.hp * 3 <= unit.max_hp else Palette.HP
	hp_bar.set_values("HP", unit.hp, unit.max_hp, hp_color)
	@warning_ignore("integer_division")
	energy_bar.set_values("EN", unit.energy(), unit.max_energy_milli / Combatant.MILLI, Palette.ENERGY)
	shape.set_down(not unit.is_alive())
	status_label.text = _status(unit, p_highlight)
	_apply_style()
	modulate = Color(1, 1, 1, 0.55) if not unit.is_alive() else Color.WHITE


## Shows the personality tag and, for an enemy, its intent in words.
## `change` is "changed: <why>" while the intent is marked, else "".
func show_intent(tag: String, intent: String, change: String) -> void:
	tag_label.text = tag
	tag_label.visible = not tag.is_empty()
	intent_changed = not change.is_empty()
	if intent_label != null:
		intent_label.text = "Intent: %s" % (intent if not intent.is_empty() else "-")
		intent_label.add_theme_color_override(
			"font_color", Palette.CHANGED if intent_changed else Palette.TARGETABLE)
		change_label.text = change
		change_label.visible = intent_changed
	_apply_style()


## Shows what the previewed choice would do to this unit; "" hides it.
func show_preview(text: String) -> void:
	preview_label.text = text
	preview_label.visible = not text.is_empty()
	_apply_style()


func _apply_style() -> void:
	match highlight:
		Highlight.ACTIVE:
			_style.border_color = Palette.ACTIVE
		Highlight.SELECTED:
			_style.border_color = Palette.SELECTED
		Highlight.TARGETABLE:
			_style.border_color = Palette.TARGETABLE
		_ when intent_changed:
			_style.border_color = Palette.CHANGED
		_:
			_style.border_color = Palette.RULE
	_style.bg_color = Palette.PANEL_RAISED if highlight != Highlight.NONE else Palette.PANEL
	if preview_label != null and preview_label.visible:
		_style.bg_color = Palette.PANEL_RAISED


func _status(unit: Combatant, p_highlight: Highlight) -> String:
	if not unit.is_alive():
		return "DOWN"
	if p_highlight == Highlight.ACTIVE:
		return "READY - choose an action"
	if p_highlight == Highlight.TARGETABLE:
		return "click to target"
	var parts := PackedStringArray()
	if unit.guard_percent > 0:
		parts.append("GUARD %d%%" % unit.guard_percent)
	if unit.is_waiting():
		@warning_ignore("integer_division")
		parts.append("charging to %d energy" % (unit.wait_target_milli / Combatant.MILLI))
	return " · ".join(parts)


func _gui_input(event: InputEvent) -> void:
	var mouse := event as InputEventMouseButton
	if mouse != null and mouse.pressed:
		clicked.emit(unit_id, mouse.button_index)
		accept_event()


static func _label(parent: Node, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label
