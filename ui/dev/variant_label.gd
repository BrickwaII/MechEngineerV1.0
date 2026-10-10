class_name VariantLabel
extends Label
## A small corner label listing the active non-default variant choices, so
## screenshots and notes say what was tested. Hidden when every decision
## plays its default. RunFlow shows one during play.

const Palette := preload("res://ui/dev/dev_palette.gd")
const FONT_SIZE := 12


func _init() -> void:
	name = "VariantLabel"
	add_theme_font_size_override("font_size", FONT_SIZE)
	add_theme_color_override("font_color", Palette.WARNING)
	add_theme_color_override("font_outline_color", Palette.BACKGROUND)
	add_theme_constant_override("outline_size", 4)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	visible = false


## Shows `board`'s non-default choices, or hides when there are none.
func show_board(board: Switchboard) -> void:
	var summary := board.summary()
	text = "Variants: " + summary
	visible = not summary.is_empty()
