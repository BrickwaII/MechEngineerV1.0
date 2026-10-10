extends Control
## A flat bar with its value written on it, for HP and energy.

const Palette := preload("res://ui/fight/fight_palette.gd")

var label := ""
var value := 0
var max_value := 1
var fill := Palette.HP


func _init() -> void:
	custom_minimum_size = Vector2(0, 16)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func set_values(p_label: String, p_value: int, p_max: int, p_fill: Color) -> void:
	label = p_label
	value = p_value
	max_value = maxi(1, p_max)
	fill = p_fill
	queue_redraw()


func text() -> String:
	return "%s %d/%d" % [label, value, max_value]


func _draw() -> void:
	var rect := Rect2(Vector2.ZERO, size)
	draw_rect(rect, Palette.BAR_BACK)
	var share := clampf(float(value) / max_value, 0.0, 1.0)
	draw_rect(Rect2(Vector2.ZERO, Vector2(size.x * share, size.y)), fill)
	var font := get_theme_default_font()
	var font_size := 12
	var baseline := (size.y + font.get_ascent(font_size) - font.get_descent(font_size)) / 2.0
	draw_string(font, Vector2(4, baseline + 1), text(), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
	draw_string(font, Vector2(3, baseline), text(), HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Palette.TEXT_BRIGHT)
