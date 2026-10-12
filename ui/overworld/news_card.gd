extends PanelContainer
## A news card over the map (R2-B escalation): an icon (alert or fortify), a
## headline and one line, when the alert tier rises or a region fortifies. Cards queue and show one at a time, only while
## can_show() says the map is in view; each stays up ui.news_seconds
## (data/tuning/escalation.json) or until clicked.

const Palette := preload("res://ui/overworld/palette.gd")
const AlertMeter := preload("res://ui/overworld/alert_meter.gd")

## Callable() -> bool: true when a card may show now. Unset always shows.
var can_show: Callable
## The card on screen, or {} when none is.
var shown: Dictionary = {}

var _queue: Array[Dictionary] = []
var _left := 0.0
var _icon: TextureRect
var _headline: Label
var _body: Label


func _ready() -> void:
	visible = false
	var ui: Dictionary = Escalation.load_data().get("ui", {})
	custom_minimum_size.x = float(ui.get("news_width", 360))
	var style := StyleBoxFlat.new()
	style.bg_color = Color(Palette.PANEL, 0.96)
	style.border_color = Palette.RULE
	style.set_border_width_all(1)
	style.border_width_left = 4
	style.set_content_margin_all(12)
	add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	_icon = TextureRect.new()
	_icon.custom_minimum_size = Vector2(12, 12) * float(UiIcons.kit("icon_scale", 2))
	_icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_icon.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	row.add_child(_icon)
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", 4)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(rows)
	_headline = _label(16, Palette.TEXT_BRIGHT)
	_body = _label(12, Palette.TEXT_BODY)
	for label in [_headline, _body]:
		rows.add_child(label)
	gui_input.connect(func(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.pressed:
			_next())


## Queues a card from Escalation.news.
func push(card: Dictionary) -> void:
	_queue.append(card)


func pending() -> int:
	return _queue.size()


func clear() -> void:
	_queue.clear()
	shown = {}
	visible = false


func _process(delta: float) -> void:
	if visible:
		# Autowrapped labels can leave the card taller than its text needs.
		if size.y > get_combined_minimum_size().y + 1.0:
			reset_size()
		_left -= delta
		if _left <= 0.0:
			_next()
	elif not _queue.is_empty() and (not can_show.is_valid() or can_show.call()):
		_show(_queue.pop_front())


func _show(card: Dictionary) -> void:
	shown = card
	var fortified := str(card.get("kind", "")) == Escalation.NEWS_FORTIFIED
	var color := Palette.DEFENSE if fortified else AlertMeter.tier_color(int(card.get("tier", 0)))
	(get_theme_stylebox("panel") as StyleBoxFlat).border_color = color
	_icon.texture = UiIcons.texture("fortify" if fortified else "alert")
	_headline.text = str(card.get("headline", ""))
	_body.text = str(card.get("body", ""))
	_left = float(Escalation.load_data().get("ui", {}).get("news_seconds", 6.0))
	visible = true


func _next() -> void:
	visible = false
	shown = {}


func _label(font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	return label

