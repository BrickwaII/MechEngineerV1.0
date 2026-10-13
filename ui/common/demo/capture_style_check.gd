extends SceneTree
## Renders the style check page (ui/common/demo/style_check.tscn) to PNGs.
## Needs a display:
##     xvfb-run -a godot --path . --rendering-driver opengl3 --resolution 1280x820 \
##         -s res://ui/common/demo/capture_style_check.gd -- <out_dir>
## Writes style_check.png, style_check_math.png (a math tooltip open),
## style_check_modal.png (a card's detail modal) and style_check_wide.png
## (the cards in the wide layout).

var out_dir := "res://ui/common/screenshots"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if not args.is_empty():
		out_dir = args[0]
	DirAccess.make_dir_recursive_absolute(out_dir)
	_run.call_deferred()


func _run() -> void:
	var page: Control = load("res://ui/common/demo/style_check.tscn").instantiate()
	root.add_child(page)
	await _frames(10)
	await _save("style_check")
	var badge: Control = page.damage_badge
	UiTooltip.show_at(badge, badge.global_position + Vector2(0, badge.size.y + 4))
	await _frames(6)
	await _save("style_check_math")
	UiTooltip.hide_tooltip()
	page.strip.press(&"layout", &"horizontal")
	await _frames(6)
	await _save("style_check_wide")
	page.unit_card.open_detail()
	await _frames(6)
	await _save("style_check_modal")
	quit()


func _frames(n: int) -> void:
	for i in n:
		await process_frame


func _save(file: String) -> void:
	await RenderingServer.frame_post_draw
	root.get_texture().get_image().save_png("%s/%s.png" % [out_dir, file])
