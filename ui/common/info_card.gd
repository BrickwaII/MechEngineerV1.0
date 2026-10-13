class_name InfoCard
extends PanelContainer
## The card anatomy every unit and region card follows:
##
##   vertical                    horizontal
##   +--------------------+      +-------+----------------+
##   | Name            ⋮  |      |       | Name        ⋮  |
##   | [Boss] [Low HP]    |      | art   | ▮▮▮▯ 12  ◔ 62% |
##   |       art          |      |       | [Boss] [Low HP]|
##   | ▮▮▮▯ 38/50  12  ◔  |      +-------+----------------+
##   +--------------------+
##
## The portrait is a slot: nothing is ever drawn over it (only brief damage
## popups). Flags sit on the edge, the three headline stats in the strip, and
## ⋮ or a right-click opens the DetailModal with everything else.
##
##   var card := InfoCard.make("Bolt", portrait, [
##       StatStrip.bar("hp", 38, 50), StatStrip.number("atk", 12), StatStrip.chip("spd", "2nd"),
##   ], [Flag.of("elite")], _detail_spec)

signal pressed

var title_label: Label
var portrait: Control
var strip: StatStrip
var flags_row: HFlowContainer
var more: Button
var title_row: HBoxContainer
var layout := "vertical"
var _hover := false
var _builder: Callable


static func make(p_title: String, p_portrait: Control, stats: Array, flags: Array = [], detail: Callable = Callable(), p_layout := "vertical") -> InfoCard:
	var c := InfoCard.new()
	c.layout = p_layout
	c._builder = detail
	c._build(p_title, p_portrait, stats, flags)
	return c


func set_title(text: String) -> void:
	title_label.text = text


func set_stats(stats: Array) -> void:
	strip.set_stats(stats)


func set_flags(flags: Array) -> void:
	for f in flags_row.get_children():
		flags_row.remove_child(f)
		f.queue_free()
	for f: Control in flags:
		flags_row.add_child(f)
	flags_row.visible = not flags.is_empty()


## Opens this card's DetailModal (as ⋮ does).
func open_detail() -> DetailModal:
	if not _builder.is_valid():
		return null
	return DetailModal.open(self, _builder.call())


func _build(p_title: String, p_portrait: Control, stats: Array, flags: Array) -> void:
	name = "InfoCard"
	mouse_filter = Control.MOUSE_FILTER_STOP
	_restyle()
	mouse_entered.connect(func() -> void: _hover = true; _restyle())
	mouse_exited.connect(func() -> void: _hover = false; _restyle())
	title_row = UiStyle.row("xs")
	title_row.name = "TitleRow"
	title_label = Label.new()
	title_label.name = "Title"
	title_label.text = p_title
	title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	UiTooltip._bold(title_label, UiStyle.role("title"))
	title_row.add_child(title_label)
	if _builder.is_valid():
		more = DetailModal.more_button(_builder)
		more.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
		title_row.add_child(more)
		DetailModal.attach(self, _builder)
	portrait = p_portrait
	portrait.name = "Portrait"
	portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
	strip = StatStrip.make(stats)
	flags_row = Flag.row(flags)
	flags_row.visible = not flags.is_empty()
	if layout == "horizontal":
		var h := UiStyle.row("s")
		h.name = "Body"
		add_child(h)
		portrait.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		h.add_child(portrait)
		var col := UiStyle.column("xs")
		col.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		h.add_child(col)
		col.add_child(title_row)
		col.add_child(strip)
		col.add_child(flags_row)
	else:
		var col := UiStyle.column("xs")
		col.name = "Body"
		add_child(col)
		col.add_child(title_row)
		col.add_child(flags_row)
		portrait.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(portrait)
		col.add_child(strip)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		pressed.emit()


func _restyle() -> void:
	add_theme_stylebox_override("panel", UiStyle.panel("card", _hover))
