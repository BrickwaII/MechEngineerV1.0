extends Control
## Placeholder art for one unit: a square for a bot, a diamond for an enemy,
## with the unit's initial on it. Greyed out once the unit is down.

const Palette := preload("res://ui/fight/fight_palette.gd")

var is_enemy := false
var is_down := false
var initial := "?"


func _init() -> void:
	custom_minimum_size = Vector2(48, 48)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func setup(p_is_enemy: bool, p_name: String) -> void:
	is_enemy = p_is_enemy
	initial = p_name.left(1).to_upper() if not p_name.is_empty() else "?"
	queue_redraw()


func set_down(p_down: bool) -> void:
	if p_down != is_down:
		is_down = p_down
		queue_redraw()


func _draw() -> void:
	var color := Palette.DOWN if is_down else (Palette.ENEMY if is_enemy else Palette.ALLY)
	var c := size / 2.0
	var r := minf(size.x, size.y) / 2.0 - 2.0
	if is_enemy:
		draw_colored_polygon(PackedVector2Array([
			c + Vector2(0, -r), c + Vector2(r, 0), c + Vector2(0, r), c + Vector2(-r, 0)]), color)
	else:
		draw_rect(Rect2(c - Vector2(r, r) * 0.85, Vector2(r, r) * 1.7), color)
	var font := get_theme_default_font()
	var font_size := 20
	var text := "x" if is_down else initial
	var w := font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	draw_string(font, c + Vector2(-w / 2.0, font.get_ascent(font_size) / 2.0 - 2.0), text,
		HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Palette.BACKGROUND)
