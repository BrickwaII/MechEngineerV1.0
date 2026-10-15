extends CaptureScript
## Renders the style check page (ui/common/demo/style_check.tscn) to PNGs.
## Needs a display:
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x820 \
##         -s res://ui/common/demo/capture_style_check.gd -- <out_dir>
## Writes style_check.png, style_check_math.png (a math tooltip open),
## style_check_modal.png (a card's detail modal) and style_check_wide.png
## (the cards in the wide layout).


func _init() -> void:
	start("res://ui/common/screenshots")


func _run() -> void:
	var page: Control = load("res://ui/common/demo/style_check.tscn").instantiate()
	root.add_child(page)
	await frames(10)
	await save("style_check")
	var badge: Control = page.damage_badge
	UiTooltip.show_at(badge, badge.global_position + Vector2(0, badge.size.y + 4))
	await frames(6)
	await save("style_check_math")
	UiTooltip.hide_tooltip()
	page.strip.press(&"layout", &"horizontal")
	await frames(6)
	await save("style_check_wide")
	page.unit_card.open_detail()
	await frames(6)
	await save("style_check_modal")
	quit()
