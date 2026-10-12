extends PanelContainer
## The alert meter over the map (R2-B escalation), icon first: the alert icon
## with the tier number, then one pip bar per tier, the current one filling
## toward the next. The tier name, the thresholds and fortifying are in the
## hover tooltip. Hidden with escalation off.

const Palette := preload("res://ui/overworld/palette.gd")

const PIP_SIZE := Vector2(26, 8)
const PIP_GAP := 3.0

var escalation: Escalation:
	set(value):
		escalation = value
		refresh()

var stat: IconStat
var _pips: Control


func _ready() -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = Palette.LABEL_BACK
	style.set_content_margin_all(6)
	add_theme_stylebox_override("panel", style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(row)
	stat = IconStat.make("alert", 1)
	row.add_child(stat)
	_pips = Control.new()
	_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_pips.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_pips.draw.connect(_draw_pips)
	row.add_child(_pips)
	refresh()


func refresh() -> void:
	visible = escalation != null and escalation.on
	if not visible or stat == null:
		return
	var t := escalation.tier()
	stat.set_value(t + 1)
	stat.set_tip_text(tip_body())
	UiTooltip.attach(self, "%s Alert: %s" % [escalation.scope(), escalation.tier_name()], tip_body(), tip_numbers(), "alert")
	_pips.custom_minimum_size = Vector2(escalation.tier_count() * (PIP_SIZE.x + PIP_GAP) - PIP_GAP, PIP_SIZE.y)
	_pips.queue_redraw()
	reset_size()


## The color of alert tier `t`: calm, then warning, then danger.
static func tier_color(t: int) -> Color:
	match t:
		0:
			return Palette.ACCENT
		1:
			return Palette.WARNING
	return Palette.DANGER


## The tooltip's lines: what the tier means and what raises it next.
func tip_body() -> String:
	var next := escalation.needed_for(escalation.tier() + 1)
	var text := "The highest tier."
	if next >= 0:
		text = "Hold %d regions for %s." % [next, escalation.tier_name(escalation.tier() + 1)]
	if escalation.is_fortifying():
		text += " Hostile regions left alone Fortify."
	return text


## The tooltip's numbers: held and every threshold.
func tip_numbers() -> String:
	var marks: Array[String] = []
	for t in range(1, escalation.tier_count()):
		marks.append(str(escalation.needed_for(t)))
	return "Held %d/%d, tiers at %s" % [escalation.state.owned.size(), escalation.map.regions.size(), " and ".join(marks)]


func _draw_pips() -> void:
	if escalation == null:
		return
	var t := escalation.tier()
	for i in escalation.tier_count():
		var pip := Rect2(Vector2(i * (PIP_SIZE.x + PIP_GAP), 0), PIP_SIZE)
		_pips.draw_rect(pip, Palette.BAR_BACKGROUND)
		var fill := 1.0 if i < t else (escalation.progress() if i == t and t + 1 < escalation.tier_count() else (1.0 if i == t else 0.0))
		if fill > 0.0:
			_pips.draw_rect(Rect2(pip.position, Vector2(pip.size.x * fill, pip.size.y)), tier_color(mini(i, t)))
		_pips.draw_rect(pip, Color(tier_color(i), 0.6), false, 1.0)
