extends GhostBar
## A GhostBar that can also show the choice preview: the hp a choice would
## take blinks on the fill (or the hp it would restore, past the fill, in
## green), and an unknown amount hatches the bar. On an energy bar the slice
## is the selected skill's cost. The caption ("HP 12/20") is drawn on top.

var caption := ""
## The value the previewed choice would leave, or -1 for no preview.
var preview_to := -1.0
var preview_known := true

var _blink := 0.0


func show_preview(p_to: float, known := true) -> void:
	preview_to = clampf(p_to, 0.0, max_value) if known else 0.0
	preview_known = known
	set_process(true)
	queue_redraw()


func clear_preview() -> void:
	if preview_to < 0.0:
		return
	preview_to = -1.0
	queue_redraw()


func has_preview() -> bool:
	return preview_to >= 0.0


func text() -> String:
	return caption


func _process(delta: float) -> void:
	super._process(delta)
	if has_preview():
		_blink += delta
		set_process(true)
		queue_redraw()


func _draw() -> void:
	super._draw()
	var border := FeelData.number("ghost_bar.border_px", 1.0)
	var inner := Rect2(Vector2.ZERO, size.floor()).grow(-border)
	if has_preview():
		var period := maxf(0.1, BattleArt.number("preview_blink_ms", 700.0) / 1000.0)
		var lo := BattleArt.number("preview_alpha_low", 0.35)
		var hi := BattleArt.number("preview_alpha_high", 0.9)
		var alpha := hi if fmod(_blink, period) < period / 2.0 else lo
		var x_now := floorf(inner.size.x * shown / max_value)
		if not preview_known:
			_draw_hatch(Rect2(inner.position, Vector2(x_now, inner.size.y)), Color(FeelData.color("preview"), alpha))
		else:
			var x_to := floorf(inner.size.x * preview_to / max_value)
			var from := minf(x_now, x_to)
			var width := absf(x_now - x_to)
			if width > 0.0:
				var gain := x_to > x_now
				var c := FeelData.color("popup_heal" if gain else "hp_ghost")
				if kind == "energy" and not gain:
					c = ReadoutStyle.color("energy_preview.color", "energy_ghost")
				draw_rect(Rect2(inner.position + Vector2(from, 0), Vector2(width, inner.size.y)), Color(c, alpha))
				# A notch at the predicted end, so the change reads without color.
				draw_rect(Rect2(inner.position + Vector2(x_to - (1 if not gain else 0), -1), Vector2(1, inner.size.y + 2)),
					FeelData.color("text_bright"))
	if not caption.is_empty():
		var font := PixelTheme.font()
		var font_size := 10
		var at := inner.position + Vector2(3, floorf((inner.size.y + font.get_ascent(font_size)) / 2.0) - 1)
		draw_string(font, at + Vector2(1, 1), caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color.BLACK)
		draw_string(font, at, caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, FeelData.color("text_bright"))


func _draw_hatch(rect: Rect2, color: Color) -> void:
	var h := int(rect.size.y)
	var x := int(rect.position.x)
	while x < rect.end.x:
		for i in h:
			var px := x + i
			if px < rect.end.x:
				draw_rect(Rect2(px, rect.position.y + i, 1, 1), color)
		x += 3
