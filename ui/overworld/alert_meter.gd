extends Control
## The alert meter over the map (R2-B escalation): the act's alert tier by
## name, one segment per tier with the current one filling toward the next,
## and how many more held territories raise it. Hidden with escalation off.

const Palette := preload("res://ui/overworld/palette.gd")

const HEIGHT := 62.0
const FONT_SMALL := 10
const FONT_TIER := 13
const SEGMENT_GAP := 3.0

var escalation: Escalation:
	set(value):
		escalation = value
		refresh()


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	custom_minimum_size = Vector2(float(Escalation.load_data().get("ui", {}).get("meter_width", 210)), HEIGHT)
	size = custom_minimum_size


func refresh() -> void:
	visible = escalation != null and escalation.on
	queue_redraw()


## The color of alert tier `t`: calm, then warning, then danger.
static func tier_color(t: int) -> Color:
	match t:
		0:
			return Palette.ACCENT
		1:
			return Palette.WARNING
	return Palette.DANGER


## The line under the bar: what raises the alert next, or that it is maxed.
func next_text() -> String:
	var more := escalation.to_next()
	if more < 0:
		return "MAXIMUM ALERT"
	return "%d MORE HELD TO %s" % [more, escalation.tier_name(escalation.tier() + 1).to_upper()]


func _draw() -> void:
	if escalation == null or not escalation.on:
		return
	var font := get_theme_default_font()
	var w := size.x
	var t := escalation.tier()
	draw_rect(Rect2(Vector2.ZERO, size), Palette.LABEL_BACK)
	draw_rect(Rect2(Vector2.ZERO, Vector2(3.0, size.y)), tier_color(t))
	var x := 10.0
	draw_string(font, Vector2(x, 14.0), "%s ALERT" % escalation.scope().to_upper(), HORIZONTAL_ALIGNMENT_LEFT, -1, FONT_SMALL, Palette.TEXT_DIM)
	draw_string(font, Vector2(x, 14.0), escalation.tier_name().to_upper(), HORIZONTAL_ALIGNMENT_RIGHT, w - x - 8.0, FONT_TIER, tier_color(t))
	var count := maxi(1, escalation.tier_count())
	var bar_w := (w - x - 8.0 - SEGMENT_GAP * (count - 1)) / count
	for i in count:
		var seg := Rect2(x + i * (bar_w + SEGMENT_GAP), 21.0, bar_w, 8.0)
		draw_rect(seg, Palette.BAR_BACKGROUND)
		var fill := 0.0
		if i < t:
			fill = 1.0
		elif i == t:
			fill = escalation.progress() if t + 1 < count else 1.0
		if i <= t and fill > 0.0:
			draw_rect(Rect2(seg.position, Vector2(seg.size.x * fill, seg.size.y)), tier_color(i) if i < t else Color(tier_color(t), 0.75))
		draw_rect(seg, Color(tier_color(i), 0.5), false, 1.0)
	draw_string(font, Vector2(x, 43.0), next_text(), HORIZONTAL_ALIGNMENT_LEFT, w - x - 6.0, FONT_SMALL, Palette.TEXT_BODY)
	var fortify := "HOSTILES LEFT ALONE FORTIFY" if escalation.is_fortifying() else "NO FORTIFYING YET"
	draw_string(font, Vector2(x, 56.0), fortify, HORIZONTAL_ALIGNMENT_LEFT, w - x - 6.0, FONT_SMALL,
		Palette.DEFENSE_TEXT if escalation.is_fortifying() else Palette.TEXT_DIM)
