class_name UiTabs
extends VBoxContainer
## Tabs: related content on one page, one tab shown at a time. A row of tab
## buttons (text always shows, an icon when given) over the pages.
##
##   var tabs := UiTabs.new()
##   tabs.add_tab("summary", "Summary", summary_page)
##   tabs.add_tab("growth", "Growth", growth_page, "intent_buff")
##   tabs.select("growth")
##   tabs.changed.connect(func(id: StringName) -> void: ...)

signal changed(id: StringName)

var bar: HBoxContainer
var pages: Control
var current: StringName = &""
var _buttons := {}
var _pages := {}
var _group := ButtonGroup.new()


func _init() -> void:
	name = "UiTabs"
	add_theme_constant_override("separation", UiStyle.space("s"))
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	bar = HBoxContainer.new()
	bar.name = "TabBar"
	bar.add_theme_constant_override("separation", UiStyle.space("xs"))
	bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(bar)
	pages = MarginContainer.new()
	pages.name = "Pages"
	pages.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(pages)


func add_tab(id: StringName, title: String, page: Control, icon_id := "") -> Button:
	var b := Button.new()
	b.name = "Tab_%s" % id
	b.text = title
	b.toggle_mode = true
	b.button_group = _group
	b.focus_mode = Control.FOCUS_NONE
	if not icon_id.is_empty():
		b.icon = UiIcons.scaled_texture(icon_id)
	b.pressed.connect(select.bind(id))
	bar.add_child(b)
	_buttons[id] = b
	page.name = "Page_%s" % id
	page.visible = false
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	pages.add_child(page)
	_pages[id] = page
	if current == &"":
		select(id)
	# One tab needs no tab bar.
	bar.visible = _buttons.size() > 1
	return b


func select(id: StringName) -> void:
	if not _pages.has(id):
		return
	var was := current
	current = id
	for k: StringName in _pages:
		(_pages[k] as Control).visible = k == id
		(_buttons[k] as Button).set_pressed_no_signal(k == id)
	if was != id:
		changed.emit(id)


func ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for k: StringName in _pages:
		out.append(k)
	return out


func page(id: StringName) -> Control:
	return _pages.get(id)


func button(id: StringName) -> Button:
	return _buttons.get(id)
