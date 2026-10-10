extends PanelContainer
## One unit on the battle screen: placeholder shape, name, HP and energy bars,
## and a status line. Enemy panels also hold an intent label.
## Emits clicked with the mouse button; the battle screen turns that into a
## FightCommand.

const Palette := preload("res://ui/fight/fight_palette.gd")
const StatBar := preload("res://ui/fight/stat_bar.gd")
const UnitShape := preload("res://ui/fight/unit_shape.gd")

enum Highlight { NONE, ACTIVE, SELECTED, TARGETABLE }

signal clicked(unit_id: String, button_index: MouseButton)

var unit_id := ""
var is_enemy := false
var highlight := Highlight.NONE
var shape: UnitShape
var name_label: Label
var hp_bar: StatBar
var energy_bar: StatBar
var status_label: Label
## Enemy intent telegraph. Placeholder until fight/intent/ is wired in.
## TODO(m4-telegraph): fill from the intent system, and refresh it on change.
var intent_label: Label

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
	name_label = _label(col, unit.display_name, 15, Palette.TEXT_BRIGHT)
	hp_bar = StatBar.new()
	col.add_child(hp_bar)
	energy_bar = StatBar.new()
	col.add_child(energy_bar)
	status_label = _label(col, "", 11, Palette.TEXT_DIM)
	if is_enemy:
		intent_label = _label(col, "Intent: ?", 11, Palette.TARGETABLE)
		intent_label.name = "IntentLabel"
	refresh(unit, Highlight.NONE)


func refresh(unit: Combatant, p_highlight: Highlight) -> void:
	highlight = p_highlight
	var hp_color := Palette.HP_LOW if unit.hp * 3 <= unit.max_hp else Palette.HP
	hp_bar.set_values("HP", unit.hp, unit.max_hp, hp_color)
	@warning_ignore("integer_division")
	energy_bar.set_values("EN", unit.energy(), unit.max_energy_milli / Combatant.MILLI, Palette.ENERGY)
	shape.set_down(not unit.is_alive())
	status_label.text = _status(unit, p_highlight)
	match p_highlight:
		Highlight.ACTIVE:
			_style.border_color = Palette.ACTIVE
		Highlight.SELECTED:
			_style.border_color = Palette.SELECTED
		Highlight.TARGETABLE:
			_style.border_color = Palette.TARGETABLE
		_:
			_style.border_color = Palette.RULE
	_style.bg_color = Palette.PANEL_RAISED if p_highlight != Highlight.NONE else Palette.PANEL
	modulate = Color(1, 1, 1, 0.55) if not unit.is_alive() else Color.WHITE


func _status(unit: Combatant, p_highlight: Highlight) -> String:
	if not unit.is_alive():
		return "DOWN"
	if p_highlight == Highlight.ACTIVE:
		return "READY - choose an action"
	if p_highlight == Highlight.TARGETABLE:
		return "click to target"
	if unit.is_waiting():
		@warning_ignore("integer_division")
		return "charging to %d energy" % (unit.wait_target_milli / Combatant.MILLI)
	return ""


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
