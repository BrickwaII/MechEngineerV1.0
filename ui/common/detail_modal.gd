class_name DetailModal
extends Control
## The detail card: everything about one thing (a unit, a region, a skill)
## one click away. A card shows its three headline stats; its ⋮ button, or a
## right-click anywhere on it, opens this modal with the rest: name, flags,
## every stat, skills, notes, links. Several sections show as tabs.
##
##   var more := DetailModal.more_button(_detail_spec)   # put it in the card's title strip
##   DetailModal.attach(card, _detail_spec)               # right-click opens it too
##
##   func _detail_spec() -> Dictionary:
##       return {"title": "Bolt", "icon": "hp", "flags": [Flag.of("elite")],
##           "sections": [{"title": "Stats", "content": DetailModal.rows([...])}]}
##
## Esc, the close button or a click outside closes it. One is open at a time.

signal closed

## The open modal, or null.
static var current: DetailModal

var title: String
var icon_id: String
var tabs: UiTabs
var panel: PanelContainer
var close_button: Button
var _layer: CanvasLayer


## Opens a modal from a spec: title, and optionally subtitle, icon, flags
## (Array of Control), sections (Array of {"title", "content", "icon"}).
static func open(where: Node, spec: Dictionary) -> DetailModal:
	close_current()
	var m := DetailModal.new()
	m._build(spec)
	m._layer = CanvasLayer.new()
	m._layer.name = "DetailModalLayer"
	m._layer.layer = int(UiIcons.kit("detail_modal.layer", 90))
	m._layer.add_child(m)
	where.get_tree().root.add_child(m._layer)
	current = m
	UiTooltip.hide_tooltip()
	return m


static func close_current() -> void:
	if current != null and is_instance_valid(current):
		current.close()
	current = null


static func is_open() -> bool:
	return current != null and is_instance_valid(current)


## The ⋮ button for a card's title strip: pressing it opens the modal that
## `builder` (a Callable returning a spec) describes.
static func more_button(builder: Callable) -> Button:
	var b := Button.new()
	b.name = "More"
	b.focus_mode = Control.FOCUS_NONE
	b.flat = true
	b.icon = UiIcons.scaled_texture("more")
	b.custom_minimum_size = UiIcons.icon_size() + Vector2(UiStyle.space("xs"), UiStyle.space("xs"))
	b.pressed.connect(func() -> void: open(b, builder.call()))
	UiTooltip.attach(b, "More", "Everything about it: all stats, skills and notes. Right-click the card does the same.", "", "more")
	return b


## Right-clicking `control` opens the modal `builder` describes.
static func attach(control: Control, builder: Callable) -> void:
	if control.mouse_filter == Control.MOUSE_FILTER_IGNORE:
		control.mouse_filter = Control.MOUSE_FILTER_PASS
	control.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_RIGHT:
			control.accept_event()
			open(control, builder.call()))


## A table of rows [icon_id, name, value] or [icon_id, name, value, math]:
## the way a modal lists every stat. Each row has its icon's tooltip, with
## its math when given.
static func rows(list: Array) -> GridContainer:
	var g := GridContainer.new()
	g.name = "Rows"
	g.columns = 3
	g.add_theme_constant_override("h_separation", UiStyle.space("s"))
	g.add_theme_constant_override("v_separation", UiStyle.space("xs"))
	g.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for r: Array in list:
		var icon := UiIcons.rect(str(r[0]))
		g.add_child(icon)
		var n := UiStyle.label(str(r[1]), "text_quiet")
		n.mouse_filter = Control.MOUSE_FILTER_PASS
		g.add_child(n)
		var v := UiStyle.label(UiFormula.fmt(r[2]), "title")
		v.mouse_filter = Control.MOUSE_FILTER_PASS
		g.add_child(v)
		var math: Array = r[3] if r.size() > 3 else []
		for c: Control in [n, v]:
			UiTooltip.attach(c, str(r[1]), UiIcons.text(str(r[0])), "%s: %s" % [r[1], UiFormula.fmt(r[2])], str(r[0]), math)
	return g


## A paragraph with keyword links, at body size.
static func prose(text: String) -> RichTextLabel:
	var r := UiGlossary.rich(text, PixelTheme.font_size("body"))
	r.name = "Prose"
	r.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return r


func close() -> void:
	if current == self:
		current = null
	closed.emit()
	if _layer != null and is_instance_valid(_layer):
		_layer.queue_free()
	else:
		queue_free()


func _build(spec: Dictionary) -> void:
	name = "DetailModal"
	theme = PixelTheme.theme()
	title = str(spec.get("title", ""))
	icon_id = str(spec.get("icon", ""))
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.color = Color(FeelData.color("background"), float(UiIcons.kit("detail_modal.dim", 0.6)))
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			close())
	add_child(dim)
	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)
	panel = PanelContainer.new()
	panel.name = "Panel"
	panel.add_theme_stylebox_override("panel", UiStyle.panel("overlay"))
	panel.custom_minimum_size.x = float(UiIcons.kit("detail_modal.width", 640))
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	center.add_child(panel)
	var col := UiStyle.column("s")
	col.name = "Column"
	panel.add_child(col)
	# Header: icon, name, flags, close.
	var head := UiStyle.row("s")
	head.name = "Header"
	col.add_child(head)
	if not icon_id.is_empty():
		var icon := UiIcons.rect(icon_id)
		icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(icon)
	var name_label := UiStyle.label(title, "title", "title")
	name_label.name = "Title"
	head.add_child(name_label)
	var flags: Array = spec.get("flags", [])
	if not flags.is_empty():
		var fr := Flag.row(flags)
		fr.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		fr.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		head.add_child(fr)
	else:
		head.add_child(UiStyle.spring())
	close_button = Button.new()
	close_button.name = "Close"
	close_button.flat = true
	close_button.focus_mode = Control.FOCUS_NONE
	close_button.icon = UiIcons.scaled_texture("action_cancel")
	close_button.pressed.connect(close)
	UiTooltip.attach(close_button, "Close", "Esc or a click outside closes it too.", "", "action_cancel")
	head.add_child(close_button)
	var subtitle := str(spec.get("subtitle", ""))
	if not subtitle.is_empty():
		var sub := UiStyle.label(subtitle, "text_quiet")
		sub.name = "Subtitle"
		sub.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(sub)
	# Sections: tabs when there are several.
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(scroll)
	tabs = UiTabs.new()
	tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(tabs)
	for i in (spec.get("sections", []) as Array).size():
		var s: Dictionary = spec["sections"][i]
		tabs.add_tab(StringName(str(s.get("id", "s%d" % i))), str(s.get("title", "")), s["content"], str(s.get("icon", "")))
	tabs.changed.connect(func(_id: StringName) -> void: _fit.call_deferred())
	# Wrapped text settles its height after the first layout: fit again then.
	tabs.minimum_size_changed.connect(func() -> void: _fit.call_deferred())
	_fit.call_deferred()


## Grows the scroll area to the content, up to the kit's share of the screen.
func _fit() -> void:
	if not is_inside_tree():
		return
	var scroll: ScrollContainer = panel.find_child("Scroll", true, false)
	var view := get_viewport_rect().size
	var want := tabs.get_combined_minimum_size().y
	scroll.custom_minimum_size.y = minf(want, view.y * float(UiIcons.kit("detail_modal.max_height_share", 0.85)) - 120.0)
	panel.reset_size()


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel"):
		if not KeywordPopup.pinned.is_empty():
			return
		close()
		get_viewport().set_input_as_handled()
