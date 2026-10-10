extends HBoxContainer
## The upcoming actions, left to right, as Fight.upcoming() gives them.
## The first chip is the unit acting now.

const Palette := preload("res://ui/fight/fight_palette.gd")

## Combatant ids in the order shown, for tests and the intent hookup.
var shown_ids: Array[String] = []


func _init() -> void:
	add_theme_constant_override("separation", 6)
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func refresh(entries: Array[TimelineEntry]) -> void:
	for child in get_children():
		remove_child(child)
		child.free()
	shown_ids.clear()
	var title := Label.new()
	title.text = "NEXT"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Palette.TEXT_DIM)
	add_child(title)
	for i in entries.size():
		add_child(_chip(entries[i], i == 0))
		shown_ids.append(entries[i].combatant_id)


func _chip(entry: TimelineEntry, is_now: bool) -> Control:
	var chip := PanelContainer.new()
	var style := StyleBoxFlat.new()
	var side_color := Palette.ENEMY if entry.side == Combatant.Side.ENEMY else Palette.ALLY
	style.bg_color = side_color.darkened(0.55)
	style.border_color = Palette.ACTIVE if is_now else side_color
	style.set_border_width_all(2 if is_now else 1)
	style.set_corner_radius_all(3)
	style.content_margin_left = 8
	style.content_margin_right = 8
	style.content_margin_top = 2
	style.content_margin_bottom = 2
	chip.add_theme_stylebox_override("panel", style)
	chip.tooltip_text = "acts at tick %d" % entry.tick
	var label := Label.new()
	label.text = entry.display_name + (" (wait)" if entry.ends_wait else "")
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Palette.TEXT_BRIGHT)
	chip.add_child(label)
	return chip
