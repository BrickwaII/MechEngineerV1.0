class_name ControlStrip
extends PanelContainer
## The one control bar of a screen or gallery, always in the same place (the
## top edge of what it controls). It holds the screen's view controls, in
## this order: choices (Size, View, Lens, Group by, Sort), toggles (Log,
## Preview), then actions on the right.
##
##   var strip := ControlStrip.new()
##   strip.add_choice(&"view", "View", [[&"compact", "Compact"], [&"detailed", "Detailed"]], &"compact")
##   strip.add_toggle(&"log", "Log", false, "status_waiting")
##   strip.add_spring()
##   strip.add_control(&"home", ActionButton.make("action_home", "Home"))
##   strip.changed.connect(func(id: StringName, value: Variant) -> void: ...)
##
## Choices are segmented buttons with their text always showing; the group
## name is an optional quiet label before them.

signal changed(id: StringName, value: Variant)

var row: HBoxContainer
var _values := {}
var _buttons := {}


func _init() -> void:
	name = "ControlStrip"
	add_theme_stylebox_override("panel", UiStyle.panel("plain"))
	custom_minimum_size.y = float(UiIcons.kit("control_strip.height", 40))
	mouse_filter = Control.MOUSE_FILTER_PASS
	row = UiStyle.row("m")
	row.name = "Row"
	add_child(row)


## A choice of one option from several: segmented buttons.
## `options` are [id, text] or [id, text, icon_id, tooltip line].
func add_choice(id: StringName, label: String, options: Array, selected: StringName) -> HBoxContainer:
	var group := UiStyle.row("xs")
	group.name = "Choice_%s" % id
	if not label.is_empty():
		var l := UiStyle.label(label, "text_quiet")
		l.name = "Label"
		l.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		group.add_child(l)
	var bg := ButtonGroup.new()
	_buttons[id] = {}
	for o: Array in options:
		var b := _button(StringName(o[0]), str(o[1]), str(o[2]) if o.size() > 2 else "")
		b.toggle_mode = true
		b.button_group = bg
		b.set_pressed_no_signal(StringName(o[0]) == selected)
		var opt := StringName(o[0])
		b.pressed.connect(func() -> void: _apply(id, opt, true))
		if o.size() > 3:
			UiTooltip.attach(b, str(o[1]), str(o[3]), "", str(o[2]) if o.size() > 2 else "")
		group.add_child(b)
		_buttons[id][opt] = b
	_values[id] = selected
	row.add_child(group)
	return group


## An on/off toggle with its text always showing.
func add_toggle(id: StringName, text: String, on: bool, icon_id := "", tip := "") -> Button:
	var b := _button(id, text, icon_id)
	b.name = "Toggle_%s" % id
	b.toggle_mode = true
	b.set_pressed_no_signal(on)
	b.toggled.connect(func(pressed: bool) -> void: _apply(id, pressed, true))
	if not tip.is_empty():
		UiTooltip.attach(b, text, tip, "", icon_id)
	_values[id] = on
	_buttons[id] = b
	row.add_child(b)
	return b


## Any other control, such as an ActionButton or a speed choice.
func add_control(id: StringName, control: Control) -> Control:
	control.name = "Control_%s" % id
	control.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(control)
	return control


## Pushes the following controls to the right end.
func add_spring() -> void:
	row.add_child(UiStyle.spring())


func value(id: StringName) -> Variant:
	return _values.get(id)


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in _values:
		out.append(k)
	return out


## Sets a choice or toggle without emitting changed.
func set_value(id: StringName, v: Variant) -> void:
	_apply(id, v, false)


## Presses a choice option or flips a toggle as a click would.
func press(id: StringName, option: Variant = null) -> void:
	var b: Variant = _buttons.get(id)
	if b is Dictionary:
		var btn: Button = b.get(option)
		btn.button_pressed = true
		btn.pressed.emit()
	elif b is Button:
		(b as Button).button_pressed = not (b as Button).button_pressed


func button(id: StringName, option: Variant = null) -> Button:
	var b: Variant = _buttons.get(id)
	if b is Dictionary:
		return b.get(option)
	return b


func _apply(id: StringName, v: Variant, emit: bool) -> void:
	var b: Variant = _buttons.get(id)
	if b is Dictionary:
		for k: StringName in b:
			(b[k] as Button).set_pressed_no_signal(k == v)
	elif b is Button:
		(b as Button).set_pressed_no_signal(bool(v))
	var was: Variant = _values.get(id)
	_values[id] = v
	if emit and was != v:
		changed.emit(id, v)


func _button(id: StringName, text: String, icon_id: String) -> Button:
	var b := Button.new()
	b.name = "Option_%s" % id
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	if not icon_id.is_empty():
		b.icon = UiIcons.scaled_texture(icon_id)
	return b
